#!/usr/bin/env python3
"""Regression contracts for WebKit download handling.

Pins the reliability contract proven by live reproduction:
  - navigate() to an attachment must NOT hang or surface "Frame load interrupted";
    it reports downloadStarted/downloadId instead.
  - click() on a download link reports downloadStarted/downloadId instead of a
    silent no-op.
  - downloads are written to ~/.agent-safari/downloads/<id>/<filename> and tracked
    with a state machine, capped at 50 entries.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = ROOT / "Sources" / "AgentSafari" / "BrowserController.swift"
NAV_DELEGATE = ROOT / "Sources" / "AgentSafari" / "BrowserControllerNavigationDelegate.swift"
DOWNLOADS = ROOT / "Sources" / "AgentSafari" / "BrowserControllerDownloads.swift"
NAVIGATION = ROOT / "Sources" / "AgentSafari" / "BrowserControllerNavigation.swift"
INPUT = ROOT / "Sources" / "AgentSafari" / "BrowserControllerInput.swift"
ERROR = ROOT / "Sources" / "AgentSafari" / "AgentSafariError.swift"
COMMAND = ROOT / "Sources" / "AgentSafariCore" / "CommandRequest.swift"
METADATA = ROOT / "Sources" / "AgentSafariCore" / "AgentSafariMetadata.swift"
RPC = ROOT / "Sources" / "AgentSafari" / "RPCHandler.swift"
CLI = ROOT / "Sources" / "AgentSafari" / "CLIHelpers.swift"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_wkdownloaddelegate_conformance_on_class_declaration() -> None:
    source = read(CONTROLLER)
    class_line = next(l for l in source.splitlines() if "final class BrowserController" in l)
    assert "WKDownloadDelegate" in class_line, "WKDownloadDelegate must be on the class declaration line"


def test_download_record_and_capped_model() -> None:
    source = read(CONTROLLER)
    assert "final class DownloadRecord" in source
    # State machine fields and tab attribution
    for field in ("let id: String", "var path: String", "var state: String", "let tabId: String"):
        assert field in source, field
    # Daemon-wide model capped at 50
    assert "var downloadsModel: [DownloadRecord]" in source
    assert "downloadModelCap = 50" in source


def test_navigation_response_policy_returns_download_for_unshowable_mime() -> None:
    source = read(NAV_DELEGATE)
    # Must use the async-imported form so the selector matches and WebKit actually calls it.
    assert "decidePolicyFor navigationResponse: WKNavigationResponse" in source
    assert "async -> WKNavigationResponsePolicy" in source
    assert "navigationResponse.canShowMIMEType ? .allow : .download" in source
    # Anchor download attribute path
    assert "decidePolicyFor navigationAction: WKNavigationAction" in source
    assert "async -> WKNavigationActionPolicy" in source
    assert "navigationAction.shouldPerformDownload ? .download : .allow" in source


def test_didbecome_download_resumes_without_throwing() -> None:
    source = read(NAV_DELEGATE)
    assert "navigationResponse: WKNavigationResponse, didBecome download: WKDownload" in source
    assert "navigationAction: WKNavigationAction, didBecome download: WKDownload" in source
    # Both didBecome callbacks resume the continuation WITHOUT a thrown error and start the download.
    become_section = source.split("didBecome download: WKDownload)")[1]
    assert "resume()" in become_section
    assert "beginDownload(download, originatingWebView: webView)" in source


def test_policy_change_error_swallowed_so_navigate_does_not_hang_or_error() -> None:
    source = read(NAV_DELEGATE)
    # 102 = WebKitErrorFrameLoadInterruptedByPolicyChange, emitted when a response becomes
    # a download. It must resume successfully (no throw) so navigate() reports the download.
    fail_body = source.split("didFailProvisionalNavigation")[-1]
    assert "WebKitErrorDomain" in fail_body
    assert "102" in fail_body
    assert "resume()" in fail_body


def test_download_destination_layout_and_delegate_methods() -> None:
    source = read(DOWNLOADS)
    assert ".agent-safari/downloads" in source
    # Per-download directory keyed by id, then suggested filename
    assert "decideDestinationUsing response: URLResponse" in source
    assert "downloadDidFinish" in source
    assert "didFailWithError error: Error" in source
    # State transitions
    assert 'record.state = "completed"' in source
    assert 'record.state = "failed"' in source
    # downloads list and wait-for-download polling
    assert "func downloads()" in source
    assert "func waitForDownload(id: String, timeoutMs: Int)" in source
    assert "AgentSafariError.waitTimedOut" in source
    # --last resolves to the most recent download
    assert '"--last"' in source


def test_navigate_drains_download_started_evidence() -> None:
    source = read(NAVIGATION)
    # Clear-at-entry so stale evidence cannot attach to this navigate.
    assert 'setPendingDownloadStarted("", for: target)' in source
    # Return downloadStarted/downloadId when the response became a download.
    assert 'pendingDownloadStarted(for: target)' in source
    assert '"downloadStarted": "true"' in source
    assert '"downloadId": downloadID' in source


def test_click_drains_download_started_at_every_return_site() -> None:
    source = read(INPUT)
    # Stale download evidence cleared at click entry, alongside popup evidence.
    click_body = source.split("func click(selector:")[1]
    assert "pendingDownloadStarted = nil" in click_body.split("if native {")[0]
    # Download settle mirrors popup settle so an async click download is reported here.
    assert "func settlePendingDownload()" in source
    assert "settlePendingDownload()" in source
    # Field drained at every return site (mirror popupRedirectedURL): >=6 sites.
    drain_count = source.count('["downloadStarted"] = "true"')
    assert drain_count >= 6, f"Expected >=6 download drain sites, found {drain_count}"


def test_unknown_download_error_code() -> None:
    source = read(ERROR)
    assert "case unknownDownload(String)" in source
    assert '"unknown_download"' in source


def test_cli_parses_downloads_and_wait_for_download() -> None:
    source = read(COMMAND)
    assert 'case "downloads":' in source
    assert 'method: "downloads"' in source
    assert 'case "wait-for-download":' in source
    assert 'method: "waitForDownload"' in source
    metadata = read(METADATA)
    assert '"downloads"' in metadata
    assert '"wait-for-download"' in metadata


def test_rpc_dispatch_and_cli_usage() -> None:
    rpc = read(RPC)
    assert 'case "downloads":' in rpc
    assert "browser.downloads()" in rpc
    assert 'case "waitForDownload":' in rpc
    assert "browser.waitForDownload(id: id, timeoutMs: timeoutMs)" in rpc
    cli = read(CLI)
    assert "agent-safari downloads" in cli
    assert "wait-for-download <id|--last>" in cli


def main() -> int:
    test_wkdownloaddelegate_conformance_on_class_declaration()
    test_download_record_and_capped_model()
    test_navigation_response_policy_returns_download_for_unshowable_mime()
    test_didbecome_download_resumes_without_throwing()
    test_policy_change_error_swallowed_so_navigate_does_not_hang_or_error()
    test_download_destination_layout_and_delegate_methods()
    test_navigate_drains_download_started_evidence()
    test_click_drains_download_started_at_every_return_site()
    test_unknown_download_error_code()
    test_cli_parses_downloads_and_wait_for_download()
    test_rpc_dispatch_and_cli_usage()
    print("download contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
