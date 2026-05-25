import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts" / "agent_safari_mcp_setup.py"
WRAPPER = REPO_ROOT / "mcp" / "agent_safari_mcp.py"


class MCPSetupHelperTests(unittest.TestCase):
    def run_helper(self, home: Path, *args: str) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["HOME"] = str(home)
        env["PATH"] = f"{REPO_ROOT / '.tmp' / 'fake-bin'}{os.pathsep}{env.get('PATH', '')}"
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--wrapper", str(WRAPPER), "--bin", "/usr/local/bin/agent-safari", *args],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=env,
            check=False,
        )

    def test_dry_run_detects_agents_but_does_not_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            claude_dir = home / "Library/Application Support/Claude"
            cursor_dir = home / ".cursor"
            claude_dir.mkdir(parents=True)
            cursor_dir.mkdir(parents=True)

            result = self.run_helper(home, "--dry-run")

            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn("Claude Desktop", result.stdout)
            self.assertIn("Cursor", result.stdout)
            self.assertIn("would update Claude Desktop", result.stdout)
            self.assertFalse((claude_dir / "claude_desktop_config.json").exists())
            self.assertFalse((cursor_dir / "mcp.json").exists())

    def test_yes_writes_json_mcp_servers_config_and_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            config_path = home / ".cursor/mcp.json"
            config_path.parent.mkdir(parents=True)
            config_path.write_text(json.dumps({"mcpServers": {"existing": {"command": "x"}}}), encoding="utf-8")

            result = self.run_helper(home, "--yes", "--agent", "cursor")
            second = self.run_helper(home, "--yes", "--agent", "cursor")

            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertEqual(second.returncode, 0, second.stdout)
            self.assertIn("updated Cursor", result.stdout)
            self.assertIn("already configured Cursor", second.stdout)
            data = json.loads(config_path.read_text(encoding="utf-8"))
            self.assertEqual(data["mcpServers"]["existing"]["command"], "x")
            server = data["mcpServers"]["agent-safari"]
            self.assertEqual(server["command"], "python3")
            self.assertEqual(server["args"], [str(WRAPPER)])
            self.assertEqual(server["env"]["AGENT_SAFARI_BIN"], "/usr/local/bin/agent-safari")
            self.assertEqual(server["env"]["AGENT_SAFARI_SOCKET"], "/tmp/agent-safari.sock")

    def test_yes_appends_hermes_yaml(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            config_path = home / ".hermes/config.yaml"
            config_path.parent.mkdir(parents=True)
            config_path.write_text("model:\n  provider: local\n", encoding="utf-8")

            result = self.run_helper(home, "--yes", "--agent", "hermes")

            self.assertEqual(result.returncode, 0, result.stdout)
            text = config_path.read_text(encoding="utf-8")
            self.assertIn("mcp_servers:", text)
            self.assertIn("  agent-safari:", text)
            self.assertIn(f'    args: ["{WRAPPER}"]', text)
            self.assertIn('      AGENT_SAFARI_SOCKET: "/tmp/agent-safari.sock"', text)

    def test_non_interactive_without_yes_skips_writes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            claude_dir = home / "Library/Application Support/Claude"
            claude_dir.mkdir(parents=True)

            result = self.run_helper(home)

            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn("skipped Claude Desktop", result.stdout)
            self.assertFalse((claude_dir / "claude_desktop_config.json").exists())


if __name__ == "__main__":
    unittest.main()
