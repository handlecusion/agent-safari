#!/usr/bin/env python3
"""Contract tests for stable error codes in AgentSafariError.swift.

Asserts:
1. Each case->code mapping string is present in AgentSafariError.swift.
2. The errorCode switch is exhaustive (no 'default' fallback remains).
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ERROR_SWIFT = ROOT / "Sources" / "AgentSafari" / "AgentSafariError.swift"


def read() -> str:
    return ERROR_SWIFT.read_text(encoding="utf-8")


# Each tuple: (case_fragment, expected_code)
EXPECTED_MAPPINGS = [
    ("case .waitTimedOut", "wait_timeout"),
    ("case .invalidURL", "invalid_url"),
    ("case .missingParam", "missing_param"),
    ("case .invalidIntegerParam", "invalid_param"),
    ("case .unknownMethod", "unknown_method"),
    ("case .elementResolutionFailed", "element_resolution_failed"),
    ("case .screenshotFailed", "screenshot_failed"),
    ("case .pageMeasurementFailed", "page_measurement_failed"),
    ("case .javascriptEncodingFailed", "javascript_encoding_failed"),
    ("case .socketPathTooLong, .socketOperationFailed", "socket_error"),
    ("case .unknownTab", "unknown_tab"),
    ("case .unknownDownload", "unknown_download"),
    # Pre-existing codes must still be present
    ("case .nativeClickUnverified", "native_click_unverified"),
    ("case .nativeInputFailed", "native_input_failed"),
    ("case .uploadFileNotFound", "upload_file_not_found"),
    ("case .uploadPanelNotTriggered", "upload_panel_not_triggered"),
    ("case .uploadMultipleNotAllowed", "upload_multiple_not_allowed"),
    ("case .uploadFileTooLargeForFallback", "upload_file_too_large_for_fallback"),
]


def test_each_case_has_stable_code_string() -> None:
    source = read()
    errors = []
    for case_fragment, code in EXPECTED_MAPPINGS:
        if case_fragment not in source:
            errors.append(f"case fragment not found: {case_fragment!r}")
        if f'"{code}"' not in source:
            errors.append(f"code string not found: {code!r}")
    if errors:
        raise AssertionError("Missing mappings in AgentSafariError.swift:\n" + "\n".join(errors))


def test_errorcode_switch_has_no_default_fallback() -> None:
    source = read()
    # Find the errorCode computed property
    ec_start = source.find("var errorCode: String?")
    assert ec_start != -1, "errorCode property not found"
    # Find the closing brace of the switch (the property ends with two closing braces)
    ec_block = source[ec_start:]
    # The switch inside errorCode must not contain 'default:'
    switch_start = ec_block.find("switch self {")
    assert switch_start != -1, "switch self not found inside errorCode"
    # Find matching close of switch: locate the 'default:' keyword before next property/func
    next_var = ec_block.find("\n    var ", 1)
    next_func = ec_block.find("\n    func ", 1)
    end = min(x for x in [next_var, next_func, len(ec_block)] if x > 0)
    switch_body = ec_block[switch_start:end]
    assert "default:" not in switch_body, (
        "errorCode switch still has a 'default:' fallback — new cases may silently return nil"
    )


def test_actionability_codes_preserved() -> None:
    source = read()
    # actionabilityFailed must still return its dynamic code
    assert "case .actionabilityFailed(let code, _):" in source
    assert "return code" in source


def main() -> int:
    test_each_case_has_stable_code_string()
    test_errorcode_switch_has_no_default_fallback()
    test_actionability_codes_preserved()
    print("error code contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
