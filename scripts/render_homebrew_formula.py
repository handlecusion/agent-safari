#!/usr/bin/env python3
"""Render the Homebrew formula for a tagged agent-safari release."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "packaging" / "homebrew" / "Formula" / "agent-safari.rb.template"
VERSION_RE = re.compile(r"^v\d+\.\d+\.\d+(-[A-Za-z0-9][A-Za-z0-9.-]*)?$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def render(version: str, sha256: str) -> str:
    if not VERSION_RE.fullmatch(version):
        raise ValueError(f"invalid version: {version}")
    if not SHA256_RE.fullmatch(sha256):
        raise ValueError(f"invalid sha256: {sha256}")
    text = TEMPLATE.read_text(encoding="utf-8")
    return text.replace("{{VERSION}}", version).replace("{{SHA256}}", sha256)


def main() -> int:
    parser = argparse.ArgumentParser(description="Render Homebrew Formula/agent-safari.rb")
    parser.add_argument("--version", required=True, help="Release tag, e.g. v0.1.0")
    parser.add_argument("--sha256", required=True, help="SHA-256 of the GitHub source tarball")
    parser.add_argument("--output", required=True, help="Output formula path")
    args = parser.parse_args()

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(render(args.version, args.sha256), encoding="utf-8")
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
