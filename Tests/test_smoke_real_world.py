#!/usr/bin/env python3
"""Regression tests for the real-world smoke runner helpers."""

from __future__ import annotations

import importlib.util
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SMOKE = ROOT / "scripts" / "smoke_real_world.py"


def load_smoke_module():
    spec = importlib.util.spec_from_file_location("smoke_real_world", SMOKE)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_png_header(path: Path, width: int, height: int, payload: bytes = b"agent-safari") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + struct.pack(">I", 13)
        + b"IHDR"
        + struct.pack(">II", width, height)
        + b"\x08\x02\x00\x00\x00"
        + b"\x00\x00\x00\x00"
        + payload
    )


def test_screenshot_artifact_reports_png_dimensions(tmp_path: Path) -> None:
    smoke = load_smoke_module()
    image = tmp_path / "element.png"
    write_png_header(image, 321, 123)

    artifact = smoke.screenshot_artifact(image, min_width=10, min_height=10)

    assert artifact == {
        "path": str(image),
        "bytes": image.stat().st_size,
        "width": 321,
        "height": 123,
    }


def test_screenshot_artifact_rejects_empty_or_implausible_png(tmp_path: Path) -> None:
    smoke = load_smoke_module()
    empty = tmp_path / "empty.png"
    empty.parent.mkdir(parents=True, exist_ok=True)
    empty.write_bytes(b"")
    tiny = tmp_path / "tiny.png"
    write_png_header(tiny, 1, 1)

    try:
        smoke.screenshot_artifact(empty)
    except AssertionError as exc:
        assert "missing or empty" in str(exc)
    else:
        raise AssertionError("empty screenshot artifact should fail")

    try:
        smoke.screenshot_artifact(tiny, min_width=20, min_height=20)
    except AssertionError as exc:
        assert "implausible dimensions" in str(exc)
    else:
        raise AssertionError("implausible screenshot dimensions should fail")


def test_full_page_artifact_must_be_taller_than_viewport(tmp_path: Path) -> None:
    smoke = load_smoke_module()
    full = tmp_path / "full.png"
    viewport = tmp_path / "viewport.png"
    write_png_header(full, 900, 2400)
    write_png_header(viewport, 900, 640)

    comparison = smoke.assert_full_page_taller_than_viewport(full, viewport)

    assert comparison["full"]["height"] == 2400
    assert comparison["viewport"]["height"] == 640


def test_screenshot_command_metadata_requires_phase3_fields() -> None:
    smoke = load_smoke_module()
    result = {
        "path": "/tmp/capture.png",
        "outputPath": "/tmp/capture.png",
        "width": "900",
        "height": "640",
        "fullPage": "false",
        "viewportWidth": "900",
        "viewportHeight": "640",
        "pageWidth": "900",
        "pageHeight": "2400",
        "scale": "2.000",
        "tileCount": "1",
        "warnings": "[]",
        "strategy": "viewport",
    }

    metadata = smoke.screenshot_command_metadata(result)

    assert metadata == {
        "outputPath": "/tmp/capture.png",
        "width": 900,
        "height": 640,
        "viewport": {"width": 900, "height": 640},
        "page": {"width": 900, "height": 2400},
        "scale": 2.0,
        "tileCount": 1,
        "warnings": [],
        "strategy": "viewport",
        "fullPage": False,
    }

    full_page = dict(result, fullPage="true", strategy="single-rect", preflightScrollCount="13")
    full_metadata = smoke.screenshot_command_metadata(full_page)
    assert full_metadata["preflightScrollCount"] == 13

    try:
        smoke.screenshot_command_metadata(dict(result, fullPage="true"))
    except AssertionError as exc:
        assert "missing full-page preflight metadata" in str(exc)
    else:
        raise AssertionError("full-page screenshot metadata without preflight count should fail")

    try:
        smoke.screenshot_command_metadata({"path": "/tmp/capture.png"})
    except AssertionError as exc:
        assert "missing screenshot metadata" in str(exc)
    else:
        raise AssertionError("screenshot result without Phase 3 metadata should fail")


def test_native_click_delivery_metadata_is_explicit() -> None:
    smoke = load_smoke_module()

    required = {
        "method": "native",
        "nativeVerified": "true",
        "fallbackUsed": "false",
        "strategy": "native-quartz-session",
        "coordinateStrategy": "webkit-viewport-to-window-to-quartz",
        "viewportX": "100.0",
        "viewportY": "200.0",
        "boundsX": "80.0",
        "boundsY": "180.0",
        "scrollDeltaY": "420.0",
        "scrolledIntoView": "true",
    }
    fallback_required = dict(required, method="dom-fallback", nativeVerified="false", fallbackUsed="true", strategy="native-unobserved-js-click")
    native = smoke.native_click_delivery(required, strict_native=True)
    fallback = smoke.native_click_delivery(fallback_required, strict_native=False)

    assert native == {"method": "native", "nativeVerified": True, "fallbackUsed": False, "scrolledIntoView": True, "coordinateStrategy": "webkit-viewport-to-window-to-quartz", "acceptable": True}
    assert fallback == {"method": "dom-fallback", "nativeVerified": False, "fallbackUsed": True, "scrolledIntoView": True, "coordinateStrategy": "webkit-viewport-to-window-to-quartz", "acceptable": True}

    try:
        smoke.native_click_delivery({"strategy": "native-unobserved-js-click"}, strict_native=False)
    except AssertionError as exc:
        assert "missing native click metadata" in str(exc)
    else:
        raise AssertionError("native click result without explicit metadata should fail")

    try:
        smoke.native_click_delivery({"method": "native", "nativeVerified": "true", "fallbackUsed": "false"}, strict_native=True)
    except AssertionError as exc:
        assert "missing native click metadata" in str(exc)
    else:
        raise AssertionError("native click result without coordinate/scroll metadata should fail")


def test_bounded_timeout_failure_helper_requires_structured_error() -> None:
    smoke = load_smoke_module()
    record = {"json": {"ok": False, "error": {"code": "error", "message": "Timed out after 250 ms"}}}
    assert smoke.assert_bounded_timeout_failure(record, 250) == "Timed out after 250 ms"

    try:
        smoke.assert_bounded_timeout_failure({"json": {"ok": True}}, 250)
    except AssertionError as exc:
        assert "bounded structured timeout failure" in str(exc)
    else:
        raise AssertionError("helper accepted a successful response as a timeout failure")


def test_quality_gate_matrix_separates_ci_local_and_strict_native() -> None:
    smoke = load_smoke_module()

    matrix = smoke.quality_gate_matrix(strict_native=False)
    names = {item["name"] for item in matrix}

    assert names == {
        "snapshot_refs_form",
        "full_page_screenshot",
        "fetch_xhr_resource_timing",
        "modeled_tab_session_profile",
        "native_click_type_viewport",
        "strict_native_click_only",
    }
    assert all(item["gate"] in {"ci-compatible", "local-gui", "strict-native-opt-in"} for item in matrix)
    assert [item["gate"] for item in matrix if item["name"] == "strict_native_click_only"] == ["strict-native-opt-in"]
    assert all(item["artifact_limit_mb"] <= 25 for item in matrix)


def test_failure_diagnostics_payload_is_bounded_and_actionable(tmp_path: Path) -> None:
    smoke = load_smoke_module()
    log = tmp_path / "daemon.log"
    log.write_text("line-1\n" + "x" * 6000 + "\nline-last\n", encoding="utf-8")

    payload = smoke.failure_diagnostics_payload(
        RuntimeError("boom"),
        out_dir=tmp_path,
        daemon_log=log,
        scenarios=[{"name": "1. Snapshot refs + form action", "verdict": "PASS"}],
        strict_native=False,
    )

    assert payload["errorType"] == "RuntimeError"
    assert payload["error"] == "boom"
    assert payload["artifactRoot"] == str(tmp_path)
    assert payload["completedScenarios"] == 1
    assert payload["strictNative"] is False
    assert payload["qualityGates"][0]["name"] == "snapshot_refs_form"
    assert len(payload["daemonLogTail"]) <= 4096
    assert "line-last" in payload["daemonLogTail"]


def main() -> int:
    import tempfile

    with tempfile.TemporaryDirectory() as d:
        test_screenshot_artifact_reports_png_dimensions(Path(d) / "a")
    with tempfile.TemporaryDirectory() as d:
        test_screenshot_artifact_rejects_empty_or_implausible_png(Path(d) / "b")
    with tempfile.TemporaryDirectory() as d:
        test_full_page_artifact_must_be_taller_than_viewport(Path(d) / "c")
    test_screenshot_command_metadata_requires_phase3_fields()
    test_native_click_delivery_metadata_is_explicit()
    test_bounded_timeout_failure_helper_requires_structured_error()
    test_quality_gate_matrix_separates_ci_local_and_strict_native()
    with tempfile.TemporaryDirectory() as d:
        test_failure_diagnostics_payload_is_bounded_and_actionable(Path(d))
    print("smoke_real_world helper tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
