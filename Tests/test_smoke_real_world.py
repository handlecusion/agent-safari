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


def test_native_click_delivery_metadata_is_explicit() -> None:
    smoke = load_smoke_module()

    native = smoke.native_click_delivery({"method": "native", "nativeVerified": "true", "fallbackUsed": "false", "strategy": "native-quartz-session"}, strict_native=True)
    fallback = smoke.native_click_delivery({"method": "dom-fallback", "nativeVerified": "false", "fallbackUsed": "true", "strategy": "native-unobserved-js-click"}, strict_native=False)

    assert native == {"method": "native", "nativeVerified": True, "fallbackUsed": False, "acceptable": True}
    assert fallback == {"method": "dom-fallback", "nativeVerified": False, "fallbackUsed": True, "acceptable": True}

    try:
        smoke.native_click_delivery({"strategy": "native-unobserved-js-click"}, strict_native=False)
    except AssertionError as exc:
        assert "missing native click metadata" in str(exc)
    else:
        raise AssertionError("native click result without explicit metadata should fail")


def main() -> int:
    import tempfile

    with tempfile.TemporaryDirectory() as d:
        test_screenshot_artifact_reports_png_dimensions(Path(d) / "a")
    with tempfile.TemporaryDirectory() as d:
        test_screenshot_artifact_rejects_empty_or_implausible_png(Path(d) / "b")
    with tempfile.TemporaryDirectory() as d:
        test_full_page_artifact_must_be_taller_than_viewport(Path(d) / "c")
    test_native_click_delivery_metadata_is_explicit()
    print("smoke_real_world helper tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
