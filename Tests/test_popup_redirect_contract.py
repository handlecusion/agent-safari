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
    # Property must be a var of Optional String initialised to nil
    assert "var pendingPopupRedirectURL: String? = nil" in source


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
    # Must load URL into current WebView via navigate(), not create a new WKWebView
    assert "navigate(" in source
    assert "return nil" in source
    # Bare window.open() (nil URL) must be a no-op — guard on url being non-nil
    assert "guard let url" in source or "navigationAction.request.url" in source


def test_popup_redirect_url_reported_in_click_result() -> None:
    source = read(INPUT)
    assert 'result["popupRedirectedURL"]' in source or 'fallback["popupRedirectedURL"]' in source
    assert "pendingPopupRedirectURL = nil" in source
    # Field must be drained at every return site — count occurrences
    drain_count = source.count("pendingPopupRedirectURL = nil")
    assert drain_count >= 6, f"Expected >=6 drain sites, found {drain_count}"


def main() -> int:
    test_wkuidelegate_conformance_on_class_declaration()
    test_pending_popup_redirect_url_property_exists()
    test_uidelegete_assigned_in_make_web_view()
    test_create_web_view_with_is_implemented()
    test_popup_redirect_navigates_current_webview_and_returns_nil()
    test_popup_redirect_url_reported_in_click_result()
    print("popup redirect contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
