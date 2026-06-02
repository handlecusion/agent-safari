#!/usr/bin/env python3
"""Contract checks for Phase 4 network capture/export hardening."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NETWORK = ROOT / "Sources" / "AgentSafari" / "BrowserControllerNetwork.swift"
MCP = ROOT / "mcp" / "agent_safari_mcp.py"
PRODUCT_SPEC = ROOT / "docs" / "PRODUCT_SPEC.md"
DEVELOPMENT_PHASES = ROOT / "docs" / "DEVELOPMENT_PHASES.md"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_network_export_metadata_is_honest_and_bounded() -> None:
    source = read(NETWORK)

    required_result_fields = [
        '"captureType"',
        '"limitations"',
        '"bodyPreviewBytes"',
        '"maxEntries"',
        '"eventCount"',
        '"resourceTimingCount"',
        '"redactionPolicy"',
    ]
    for field in required_result_fields:
        assert field in source, f"missing network export result field {field}"

    required_limitations = [
        "fetch/xhr has request/response metadata",
        "parser-driven resources are included from PerformanceResourceTiming only",
        "no request/response headers for parser-driven resources",
        "no websocket frames",
        "no service-worker internals",
        "no downloads",
        "not full HAR completeness",
        "no default proxy capture",
    ]
    for limitation in required_limitations:
        assert limitation in source, f"missing honest limitation {limitation!r}"

    assert "bodyPreviewBytes !== null" in source
    assert "events.slice(-Math.max(0, maxEntries))" in source
    assert '"resourceTimingCount": "see-artifact"' not in source
    assert '"entryCount"' in source
    assert '"eventCount": String(eventCount)' in source
    assert '"resourceTimingCount": String(resourceTimingCount)' in source


def test_network_export_redacts_sensitive_headers_and_body_preview() -> None:
    source = read(NETWORK)

    sensitive_terms = ["authorization", "cookie", "set-cookie", "password", "token", "secret", "api_key"]
    for term in sensitive_terms:
        assert term in source.lower(), f"missing redaction term {term}"

    assert "redactBodyPreview" in source
    assert "[REDACTED]" in source


def test_network_export_limitation_representations_stay_in_sync() -> None:
    source = read(NETWORK)
    artifact_match = re.search(r"limitations: \[(?P<body>.*?)\],\n\s+redacted", source, re.S)
    result_match = re.search(r'"limitations": "(?P<body>[^"]+)"', source)
    assert artifact_match and result_match

    artifact_items = [item.strip().strip("'") for item in artifact_match.group("body").split(",")]
    result_items = [item.strip() for item in result_match.group("body").split(";")]
    assert artifact_items == result_items


def test_mcp_network_export_contract_exposes_phase4_result_fields() -> None:
    namespace: dict[str, object] = {}
    exec(MCP.read_text(encoding="utf-8"), namespace)
    tool_contracts = namespace["TOOL_CONTRACTS"]
    assert isinstance(tool_contracts, list)
    contracts = {tool["name"]: tool for tool in tool_contracts}
    result = set(contracts["network_export"]["result"])

    required = {
        "path",
        "count",
        "redacted",
        "schema",
        "schemaVersion",
        "captureType",
        "limitations",
        "bodyPreviewBytes",
        "maxEntries",
        "entryCount",
        "eventCount",
        "resourceTimingCount",
        "redactionPolicy",
    }
    assert required.issubset(result)


def test_phase4_docs_state_current_scope_boundaries() -> None:
    combined = read(PRODUCT_SPEC) + "\n" + read(DEVELOPMENT_PHASES)
    required_phrases = [
        "JavaScript fetch/XHR instrumentation",
        "PerformanceResourceTiming",
        "not full HAR",
        "no WebSocket frames",
        "no service worker internals",
        "no downloads",
        "no default proxy capture",
        "body preview",
        "redaction",
    ]
    for phrase in required_phrases:
        assert phrase.lower() in combined.lower(), f"missing Phase 4 scope phrase {phrase!r}"


def main() -> int:
    for test in (
        test_network_export_metadata_is_honest_and_bounded,
        test_network_export_redacts_sensitive_headers_and_body_preview,
        test_network_export_limitation_representations_stay_in_sync,
        test_mcp_network_export_contract_exposes_phase4_result_fields,
        test_phase4_docs_state_current_scope_boundaries,
    ):
        test()
    print("network capture contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
