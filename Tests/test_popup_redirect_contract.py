#!/usr/bin/env python3
"""Regression contracts for target=_blank / window.open popup redirect handling."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = ROOT / "Sources" / "AgentSafari" / "BrowserController.swift"
UI_DELEGATE = ROOT / "Sources" / "AgentSafari" / "BrowserControllerUIDelegate.swift"
INPUT = ROOT / "Sources" / "AgentSafari" / "BrowserControllerInput.swift"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_wkuidelegate_conformance_on_class_declaration() -> None:
    source = read(CONTROLLER)
    assert "WKUIDelegate" in source
    # Conformance must be on the class declaration line, not only in an extension
    class_line = next(l for l in source.splitlines() if "final class BrowserController" in l)
    assert "WKUIDelegate" in class_line


def test_pending_popup_redirect_url_property_exists() -> None:
    source = read(CONTROLLER)
    # Per-tab storage exposed through the original property name
    assert "var pendingPopupRedirectURL: String?" in source
    assert "pendingPopupRedirectURLByTab" in source


def test_uidelegete_assigned_in_make_web_view() -> None:
    source = read(CONTROLLER)
    assert "newWebView.uiDelegate = self" in source
    # Must appear inside makeWebView, i.e. between the func declaration and its closing brace
    make_web_view_body = source.split("func makeWebView()")[1].split("\n    }")[0]
    assert "uiDelegate = self" in make_web_view_body


def test_create_web_view_with_is_implemented() -> None:
    source = read(UI_DELEGATE)
    assert "createWebViewWith" in source
    assert "windowFeatures: WKWindowFeatures" in source
    assert "-> WKWebView?" in source


def test_popup_redirect_navigates_current_webview_and_returns_nil() -> None:
    source = read(UI_DELEGATE)
    # Must load URL into the ORIGINATING webView via navigate(), not create a new
    # WKWebView — the popup may come from a background tab under parallel use
    assert "navigate(urlString, in: webView)" in source
    assert "setPendingPopupRedirectURL(urlString, for: webView)" in source
    assert "return nil" in source
    # Bare window.open() yields a non-nil but EMPTY request URL in WebKit — must be
    # ignored without navigating or recording a pending redirect
    assert "guard let url" in source
    assert "!url.absoluteString.isEmpty" in source
    assert "popup with no URL ignored" in source


def test_click_discards_stale_popup_redirect_and_settles_async_popups() -> None:
    source = read(INPUT)
    # Stale popup evidence from earlier actions must be cleared at click entry
    click_body = source.split("func click(selector:")[1]
    assert "pendingPopupRedirectURL = nil" in click_body.split("if native {")[0]
    # Anchor-driven popups arrive async — js click must wait (bounded) when expected
    assert "func settlePendingPopupRedirect(expected: Bool)" in source
    assert "settlePendingPopupRedirect(expected: popupExpected)" in source
    assert "closest('a[target]')" in source


def test_popup_redirect_url_reported_in_click_result() -> None:
    source = read(INPUT)
    assert 'result["popupRedirectedURL"]' in source or 'fallback["popupRedirectedURL"]' in source
    assert "pendingPopupRedirectURL = nil" in source
    # Field must be drained at every return site — count occurrences
    drain_count = source.count("pendingPopupRedirectURL = nil")
    assert drain_count >= 6, f"Expected >=6 drain sites, found {drain_count}"



def test_js_dialog_handlers_suppress_and_log() -> None:
    source = read(UI_DELEGATE)
    # alert: completionHandler() with no argument
    assert "runJavaScriptAlertPanelWithMessage" in source
    assert "alert suppressed" in source
    # confirm: completionHandler(false)
    assert "runJavaScriptConfirmPanelWithMessage" in source
    assert "completionHandler(false)" in source
    assert "confirm suppressed" in source
    # prompt: completionHandler("")
    assert "runJavaScriptTextInputPanelWithPrompt" in source
    assert 'completionHandler("")' in source
    assert "prompt suppressed" in source


def main() -> int:
    test_wkuidelegate_conformance_on_class_declaration()
    test_pending_popup_redirect_url_property_exists()
    test_uidelegete_assigned_in_make_web_view()
    test_create_web_view_with_is_implemented()
    test_popup_redirect_navigates_current_webview_and_returns_nil()
    test_click_discards_stale_popup_redirect_and_settles_async_popups()
    test_popup_redirect_url_reported_in_click_result()
    test_js_dialog_handlers_suppress_and_log()
    print("popup redirect contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
