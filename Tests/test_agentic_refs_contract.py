#!/usr/bin/env python3
"""Regression contracts for agentic snapshot refs and actionability checks."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "Sources" / "AgentSafari" / "BrowserControllerSnapshot.swift"
INPUT = ROOT / "Sources" / "AgentSafari" / "BrowserControllerInput.swift"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_snapshot_refs_emit_schema_version_and_dom_index() -> None:
    source = read(SNAPSHOT)

    assert "snapshotSchemaVersion: 2" in source
    assert "domIndex" in source
    assert ".sort((left, right) => left.domIndex - right.domIndex)" in source


def test_action_targets_reject_stale_disabled_hidden_and_offscreen_refs() -> None:
    source = read(INPUT)

    assert "Element is disabled:" in source
    assert "Element is hidden:" in source
    assert "Element center is outside viewport:" in source
    assert "No element found for snapshot ref: ${target}. Run snapshot first or refresh it with snapshot." in source


def test_fill_uses_same_actionability_contract_as_click() -> None:
    source = read(INPUT)

    assert "validateActionableElement(element, target);" in source
    assert source.count("validateActionableElement") >= 2


def main() -> int:
    test_snapshot_refs_emit_schema_version_and_dom_index()
    test_action_targets_reject_stale_disabled_hidden_and_offscreen_refs()
    test_fill_uses_same_actionability_contract_as_click()
    print("agentic refs contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
