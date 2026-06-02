#!/usr/bin/env python3
"""Regression contracts for text insertion and keyboard key paths."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT / "Sources" / "AgentSafari" / "BrowserControllerInput.swift"
SMOKE = ROOT / "scripts" / "smoke_real_world.py"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_key_path_mutates_editable_targets_for_common_keys() -> None:
    source = read(INPUT)

    assert "function editTextTarget" in source
    assert "case 'Backspace':" in source
    assert "case 'Delete':" in source
    assert "case 'Enter':" in source
    assert "case 'ArrowLeft':" in source
    assert "case 'ArrowRight':" in source
    assert "deleteContentBackward" in source
    assert "insertLineBreak" in source


def test_key_path_supports_shortcut_parsing_and_select_all() -> None:
    source = read(INPUT)

    assert "parseKeySpec" in source
    assert "metaKey" in source
    assert "ctrlKey" in source
    assert "selectAllEditableText" in source
    assert "normalizedKey.toLowerCase() === 'a'" in source


def test_type_text_covers_input_textarea_and_contenteditable_smoke() -> None:
    source = read(SMOKE)

    assert "#typed" in source
    assert "#notes" in source
    assert "#editor" in source
    assert "typed by agent-safari" in source
    assert "textarea line one" in source
    assert "rich tex!" in source


def main() -> int:
    test_key_path_mutates_editable_targets_for_common_keys()
    test_key_path_supports_shortcut_parsing_and_select_all()
    test_type_text_covers_input_textarea_and_contenteditable_smoke()
    print("input key-path contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
