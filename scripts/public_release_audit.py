#!/usr/bin/env python3
"""Public-release hygiene checks for agent-safari.

This script is intentionally conservative and dependency-free so it can run in
GitHub Actions and locally before changing the repository from private to public.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

EXPECTED_REPO_URL = "https://github.com/handlecusion/agent-safari.git"
REQUIRED_FILES = [
    "LICENSE",
    "README.md",
    ".gitignore",
    ".github/workflows/ci.yml",
    ".github/workflows/release.yml",
    ".github/workflows/smoke.yml",
    ".github/workflows/publish-packages.yml",
    "scripts/package_release.sh",
    "scripts/package_npm.sh",
    "scripts/agent_safari_mcp_setup.py",
    "scripts/render_homebrew_formula.py",
    "npm/agent-safari/package.json",
    "npm/agent-safari/bin/agent-safari.js",
    "npm/agent-safari/scripts/install.js",
    "packaging/homebrew/Formula/agent-safari.rb.template",
]
REQUIRED_CI_SNIPPETS = [
    "runs-on: macos-15",
    "actions/checkout@v5",
    "swift test",
    "swift build -c release",
    "python3 -m py_compile mcp/agent_safari_mcp.py scripts/smoke_mcp_wrapper.py",
    "bash -n scripts/*.sh",
    "scripts/package_npm.sh",
    "scripts/render_homebrew_formula.py",
    "python3 scripts/public_release_audit.py",
    "Tests/test_mcp_setup_helper.py",
]
REQUIRED_RELEASE_SNIPPETS = [
    "tags:",
    "v*",
    "environment: release",
    "contents: write",
    "Validate release version",
    "scripts/package_release.sh",
    "scripts/package_npm.sh",
    "agent-safari.rb",
    "gh release",
    "--verify-tag",
    "--target \"$GITHUB_SHA\"",
]
REQUIRED_SMOKE_SNIPPETS = [
    "workflow_dispatch",
    "scripts/smoke_cli.sh",
    "python3 scripts/smoke_mcp_wrapper.py",
    "actions/upload-artifact@v4",
]
REQUIRED_PUBLISH_SNIPPETS = [
    "release:",
    "types: [published]",
    "NPM_TOKEN",
    "npm publish",
    "HOMEBREW_TAP_REPO",
    "HOMEBREW_TAP_TOKEN",
    "scripts/render_homebrew_formula.py",
    "actions/upload-artifact@v4",
]
REQUIRED_GITIGNORE_SNIPPETS = [
    ".build/",
    ".tmp/",
    ".env",
    "__pycache__/",
]
TEXT_SUFFIXES = {
    "",
    ".md",
    ".py",
    ".sh",
    ".swift",
    ".js",
    ".json",
    ".yml",
    ".yaml",
    ".txt",
    ".toml",
    ".gitignore",
}
SKIP_DIRS = {".git", ".build", ".swiftpm", ".venv", ".venv-mcp", "venv", "__pycache__", ".tmp", ".hermes", ".omc"}
SECRET_PATTERNS = [
    re.compile(part, re.IGNORECASE)
    for part in [
        "OPENAI",
        "ANTHROPIC",
        r"API[_-]?KEY",
        r"SECRET[_-]?(KEY|TOKEN)",
        r"ACCESS[_-]?TOKEN",
        r"AUTH[_-]?TOKEN",
        "PASSWORD",
        "Bearer ",
        "Authorization:",
        "sk-" + r"[A-Za-z0-9]",
        "gh" + r"[po]_[A-Za-z0-9]",
    ]
]
LOCAL_PATH_PATTERN = re.compile(r"/Users/[^\s)`'\"]+")
PASSKEY_FEATURE_PATTERN = re.compile(r"passkey|webauthn", re.IGNORECASE)
PASSKEY_SCAN_DIRS = ["Sources", "mcp", "scripts"]


def iter_text_files(root: Path):
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        rel_parts = path.relative_to(root).parts
        if any(part in SKIP_DIRS for part in rel_parts):
            continue
        if path.name == "public_release_audit.py":
            continue
        suffix = path.suffix if path.name != ".gitignore" else ".gitignore"
        if suffix not in TEXT_SUFFIXES:
            continue
        yield path


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def check_required_files(root: Path, errors: list[str]) -> None:
    for rel in REQUIRED_FILES:
        if not (root / rel).is_file():
            errors.append(f"missing required file: {rel}")


def check_readme(root: Path, errors: list[str]) -> None:
    readme = root / "README.md"
    if not readme.is_file():
        return
    text = read_text(readme)
    if "<repo-url>" in text:
        errors.append("README.md contains placeholder clone URL: <repo-url>")
    if EXPECTED_REPO_URL not in text:
        errors.append(f"README.md should mention final clone URL: {EXPECTED_REPO_URL}")


def check_ci(root: Path, errors: list[str]) -> None:
    ci = root / ".github" / "workflows" / "ci.yml"
    if not ci.is_file():
        return
    text = read_text(ci)
    for snippet in REQUIRED_CI_SNIPPETS:
        if snippet not in text:
            errors.append(f"CI workflow missing required command/snippet: {snippet}")


def check_release_workflow(root: Path, errors: list[str]) -> None:
    release = root / ".github" / "workflows" / "release.yml"
    if not release.is_file():
        return
    text = read_text(release)
    for snippet in REQUIRED_RELEASE_SNIPPETS:
        if snippet not in text:
            errors.append(f"release workflow missing required command/snippet: {snippet}")


def check_smoke_workflow(root: Path, errors: list[str]) -> None:
    smoke = root / ".github" / "workflows" / "smoke.yml"
    if not smoke.is_file():
        return
    text = read_text(smoke)
    for snippet in REQUIRED_SMOKE_SNIPPETS:
        if snippet not in text:
            errors.append(f"smoke workflow missing required command/snippet: {snippet}")


def check_publish_workflow(root: Path, errors: list[str]) -> None:
    publish = root / ".github" / "workflows" / "publish-packages.yml"
    if not publish.is_file():
        return
    text = read_text(publish)
    for snippet in REQUIRED_PUBLISH_SNIPPETS:
        if snippet not in text:
            errors.append(f"publish workflow missing required command/snippet: {snippet}")


def check_gitignore(root: Path, errors: list[str]) -> None:
    gitignore = root / ".gitignore"
    if not gitignore.is_file():
        return
    text = read_text(gitignore)
    for snippet in REQUIRED_GITIGNORE_SNIPPETS:
        if snippet not in text:
            errors.append(f".gitignore missing required pattern: {snippet}")


def check_local_paths(root: Path, errors: list[str]) -> None:
    for path in iter_text_files(root):
        rel = path.relative_to(root)
        text = read_text(path)
        if LOCAL_PATH_PATTERN.search(text):
            errors.append(f"local absolute path found in public text: {rel}")


def check_secretish_text(root: Path, errors: list[str]) -> None:
    for path in iter_text_files(root):
        rel = path.relative_to(root)
        text = read_text(path)
        for pattern in SECRET_PATTERNS:
            if pattern.search(text):
                errors.append(f"secret-ish token pattern found in {rel}: {pattern.pattern}")
                break


def check_passkey_feature_code(root: Path, errors: list[str]) -> None:
    for dirname in PASSKEY_SCAN_DIRS:
        base = root / dirname
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if not path.is_file() or any(part in SKIP_DIRS for part in path.relative_to(root).parts):
                continue
            suffix = path.suffix if path.name != ".gitignore" else ".gitignore"
            if suffix not in TEXT_SUFFIXES:
                continue
            rel = path.relative_to(root)
            if rel == Path("scripts/public_release_audit.py"):
                continue
            if PASSKEY_FEATURE_PATTERN.search(read_text(path)):
                errors.append(f"passkey/WebAuthn feature-code reference found in {rel}")


def audit(root: Path) -> list[str]:
    errors: list[str] = []
    check_required_files(root, errors)
    check_readme(root, errors)
    check_ci(root, errors)
    check_release_workflow(root, errors)
    check_smoke_workflow(root, errors)
    check_publish_workflow(root, errors)
    check_gitignore(root, errors)
    check_local_paths(root, errors)
    check_secretish_text(root, errors)
    check_passkey_feature_code(root, errors)
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run public-release hygiene checks.")
    parser.add_argument("--root", default=".", help="Repository root to audit")
    args = parser.parse_args(argv)
    root = Path(args.root).resolve()
    errors = audit(root)
    if errors:
        print("public release audit failed:")
        for error in errors:
            print(f"- {error}")
        return 1
    print("public release audit passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
