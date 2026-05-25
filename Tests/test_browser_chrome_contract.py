#!/usr/bin/env python3
"""Regression tests for the visible browser chrome contract."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = ROOT / "Sources" / "AgentSafari" / "BrowserController.swift"
NAVIGATION = ROOT / "Sources" / "AgentSafari" / "BrowserControllerNavigation.swift"
DELEGATE = ROOT / "Sources" / "AgentSafari" / "BrowserControllerNavigationDelegate.swift"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_window_keeps_visible_address_bar_above_webview() -> None:
    source = read(CONTROLLER)

    assert "addressField" in source
    assert "NSSearchField" in source or "NSTextField" in source
    assert "placeholderString = \"Enter URL or search\"" in source
    assert "setAccessibilityIdentifier(\"agent-safari-address-bar\")" in source
    assert "NSRect(x: 100, y: 100, width: 1280, height: 764)" in source
    assert "webContainerView = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))" in source
    assert "window.contentView = rootView" in source
    assert "attachWebViewToContainer" in source


def test_navigation_keeps_address_bar_in_sync() -> None:
    controller = read(CONTROLLER)
    navigation = read(NAVIGATION)
    delegate = read(DELEGATE)

    assert "updateAddressBar" in controller
    assert "addressBarCommit" in controller
    assert "normalizedAddressBarURL" in controller
    assert "updateAddressBar(urlString)" in navigation
    assert "updateAddressBar(webView.url?.absoluteString" in delegate


def test_native_click_clears_focused_text_input_before_mouse_events() -> None:
    source = read(ROOT / "Sources" / "AgentSafari" / "BrowserControllerInput.swift")

    assert "blurActiveElementBeforeNativeClick" in source
    assert "document.activeElement" in source
    assert ".blur()" in source
    assert "try await blurActiveElementBeforeNativeClick()" in source


def main() -> int:
    test_window_keeps_visible_address_bar_above_webview()
    test_navigation_keeps_address_bar_in_sync()
    test_native_click_clears_focused_text_input_before_mouse_events()
    print("browser chrome contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
