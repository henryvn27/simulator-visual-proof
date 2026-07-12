#!/usr/bin/env python3
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROVE = ROOT / "scripts" / "prove.py"


class ProveTests(unittest.TestCase):
    def run_tool(self, *arguments, expected=0):
        result = subprocess.run([str(PROVE), *arguments], text=True, capture_output=True)
        self.assertEqual(result.returncode, expected, result.stderr)
        return result

    def test_init_creates_standard_workspace_and_status_reports_missing_work(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = self.run_tool("init", "--output-dir", str(root), "--claim", "Search works",
                                   "--start", "Home", "--action", "Search cuties",
                                   "--finish", "Results", "--must-contain", "Cuties")
            self.assertIn(f"plan={root / 'proof.json'}", output.stdout)
            self.assertTrue((root / "proof.json").is_file())
            status = self.run_tool("status", "--plan", str(root / "proof.json"), expected=3)
            parsed = json.loads(status.stdout)
            self.assertFalse(parsed["accepted"])
            self.assertIn("Search cuties", parsed["uncovered_actions"])
            self.assertIn("screenshot", parsed["missing_artifacts"])


if __name__ == "__main__":
    unittest.main()
