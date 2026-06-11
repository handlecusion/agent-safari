#!/usr/bin/env python3
"""Regression contracts for same-document (fragment-only) navigation handling.

WebKit performs fragment-only navigations as same-document navigations and does
not fire the didFinish/didFail delegate callbacks that resume the navigation
continuation. navigate() must detect that case and drive the fragment change via
JavaScript so the CLI returns instead of hanging forever.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAVIGATION = ROOT / "Sources" / "AgentSafari" / "BrowserControllerNavigation.swift"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_same_document_detection_helper_exists() -> None:
    source = read(NAVIGATION)
    assert "func isSameDocumentNavigation(to target: URL) -> Bool" in source
    # Detection requires both a fragment on the target and an equal base URL.
    assert "target.fragment != nil" in source
    assert "urlIgnoringFragment(current) == urlIgnoringFragment(target)" in source


def test_url_ignoring_fragment_strips_fragment() -> None:
    source = read(NAVIGATION)
    assert "func urlIgnoringFragment(_ url: URL) -> String" in source
    assert "components.fragment = nil" in source


def test_navigate_branches_on_same_document_before_load() -> None:
    source = read(NAVIGATION)
    func_body = source.split("func navigate(")[1].split("\n    }")[0]
    # The same-document branch must appear, and must come before the
    # load/continuation path so the hang is bypassed entirely.
    branch_idx = func_body.find("if isSameDocumentNavigation(to: url)")
    continuation_idx = func_body.find("withCheckedThrowingContinuation")
    assert branch_idx != -1, "navigate() does not branch on same-document navigation"
    assert continuation_idx != -1, "navigate() lost its continuation path"
    assert branch_idx < continuation_idx, "same-document branch must precede the load/continuation path"


def test_same_document_branch_uses_javascript_not_continuation() -> None:
    source = read(NAVIGATION)
    func_body = source.split("func navigate(")[1].split("\n    }")[0]
    branch = func_body.split("if isSameDocumentNavigation(to: url)")[1].split("withCheckedThrowingContinuation")[0]
    # Must drive the fragment change via JS, using the safe string-literal helper.
    assert "javaScriptStringLiteral(urlString)" in branch
    assert "location.href = " in branch
    assert "evaluateJavaScript" in branch
    # Must NOT register a navigation continuation on the same-document path.
    assert "navigationContinuation" not in branch


def test_same_document_result_reports_field() -> None:
    source = read(NAVIGATION)
    assert '"sameDocument": "true"' in source


def main() -> int:
    test_same_document_detection_helper_exists()
    test_url_ignoring_fragment_strips_fragment()
    test_navigate_branches_on_same_document_before_load()
    test_same_document_branch_uses_javascript_not_continuation()
    test_same_document_result_reports_field()
    print("same-document navigation contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
