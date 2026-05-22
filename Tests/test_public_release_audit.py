import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def copy_audit_script(tmp_path: Path) -> Path:
    source = REPO_ROOT / "scripts" / "public_release_audit.py"
    target = tmp_path / "public_release_audit.py"
    shutil.copy(source, target)
    return target


def write_minimal_public_ready_repo(root: Path) -> None:
    (root / "scripts").mkdir(parents=True)
    (root / "mcp").mkdir()
    (root / "docs").mkdir()
    (root / ".github" / "workflows").mkdir(parents=True)
    (root / "README.md").write_text(
        "# agent-safari\n\n"
        "```sh\n"
        "git clone https://github.com/handlecusion/agent-safari.git agent-safari\n"
        "```\n",
        encoding="utf-8",
    )
    (root / "LICENSE").write_text("MIT License\n", encoding="utf-8")
    (root / ".gitignore").write_text(".build/\n.tmp/\n.env\n__pycache__/\n", encoding="utf-8")
    (root / ".github" / "workflows" / "ci.yml").write_text(
        "name: CI\n"
        "on: [push, pull_request]\n"
        "jobs:\n"
        "  test:\n"
        "    runs-on: macos-15\n"
        "    steps:\n"
        "      - uses: actions/checkout@v5\n"
        "      - run: swift test\n"
        "      - run: swift build -c release\n"
        "      - run: python3 -m py_compile mcp/agent_safari_mcp.py scripts/smoke_mcp_wrapper.py\n"
        "      - run: bash -n scripts/*.sh\n"
        "      - run: python3 scripts/public_release_audit.py\n",
        encoding="utf-8",
    )
    (root / ".github" / "workflows" / "release.yml").write_text(
        "name: Release\n"
        "on:\n"
        "  push:\n"
        "    tags:\n"
        "      - 'v*'\n"
        "permissions:\n"
        "  contents: write\n"
        "jobs:\n"
        "  release:\n"
        "    environment: release\n"
        "    steps:\n"
        "      - run: echo Validate release version\n"
        "      - run: scripts/package_release.sh\n"
        "      - run: gh release create v0.1.0 artifact.zip --verify-tag --target \"$GITHUB_SHA\"\n",
        encoding="utf-8",
    )
    (root / ".github" / "workflows" / "smoke.yml").write_text(
        "name: macOS Smoke\n"
        "on:\n"
        "  workflow_dispatch:\n"
        "jobs:\n"
        "  smoke:\n"
        "    steps:\n"
        "      - run: scripts/smoke_cli.sh\n"
        "      - run: python3 scripts/smoke_mcp_wrapper.py\n"
        "      - uses: actions/upload-artifact@v4\n",
        encoding="utf-8",
    )
    (root / "scripts" / "placeholder.sh").write_text("#!/usr/bin/env bash\n", encoding="utf-8")
    (root / "scripts" / "package_release.sh").write_text("#!/usr/bin/env bash\n", encoding="utf-8")
    (root / "mcp" / "agent_safari_mcp.py").write_text("print('ok')\n", encoding="utf-8")
    (root / "docs" / "MCP_WRAPPER.md").write_text("safe docs\n", encoding="utf-8")


def run_audit(script: Path, root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(script), "--root", str(root)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


class PublicReleaseAuditTests(unittest.TestCase):
    def test_public_release_audit_passes_for_minimal_ready_repo(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            script = copy_audit_script(tmp_path)
            fixture = tmp_path / "fixture"
            fixture.mkdir()
            write_minimal_public_ready_repo(fixture)

            result = run_audit(script, fixture)

            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn("public release audit passed", result.stdout)

    def test_public_release_audit_fails_when_license_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            script = copy_audit_script(tmp_path)
            fixture = tmp_path / "fixture"
            fixture.mkdir()
            write_minimal_public_ready_repo(fixture)
            (fixture / "LICENSE").unlink()

            result = run_audit(script, fixture)

            self.assertEqual(result.returncode, 1)
            self.assertIn("missing required file: LICENSE", result.stdout)

    def test_public_release_audit_fails_on_placeholder_clone_url(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            script = copy_audit_script(tmp_path)
            fixture = tmp_path / "fixture"
            fixture.mkdir()
            write_minimal_public_ready_repo(fixture)
            (fixture / "README.md").write_text("git clone <repo-url> agent-safari\n", encoding="utf-8")

            result = run_audit(script, fixture)

            self.assertEqual(result.returncode, 1)
            self.assertIn("placeholder clone URL", result.stdout)


if __name__ == "__main__":
    unittest.main()
