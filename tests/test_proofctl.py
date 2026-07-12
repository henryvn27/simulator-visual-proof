#!/usr/bin/env python3
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROOFCTL = ROOT / "scripts" / "proofctl.py"


class ProofControlTests(unittest.TestCase):
    def run_tool(self, *arguments, expected=0):
        result = subprocess.run([str(PROOFCTL), *arguments], text=True, capture_output=True)
        self.assertEqual(result.returncode, expected, result.stderr)
        return result

    def test_contract_state_check_log_and_complete(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plan = root / "proof.json"
            accessibility = root / "accessibility.json"
            self.run_tool("init", "--output", str(plan), "--claim", "Analytics contains data",
                          "--start", "Home", "--action", "Open Analytics", "--finish", "Analytics",
                          "--evidence", "video+screenshot", "--must-contain", "Performance Trends",
                          "--must-not-contain", "Loading")
            accessibility.write_text(json.dumps([{"AXLabel": "Performance Trends"}]))
            checked = self.run_tool("check-state", "--plan", str(plan),
                                    "--accessibility", str(accessibility))
            self.assertTrue(json.loads(checked.stdout)["accepted"])
            self.run_tool("log", "--plan", str(plan), "--event", "recording-start")
            self.run_tool("log", "--plan", str(plan), "--event", "tap", "--detail", "Analytics",
                          "--covers", "Open Analytics")
            screenshot = root / "proof.png"
            video = root / "proof.mp4"
            preview = root / "proof.gif"
            review = root / "review.json"
            for artifact in (screenshot, video, preview, review):
                artifact.write_text("proof")
            self.run_tool("complete", "--plan", str(plan), "--screenshot", str(screenshot),
                          "--video", str(video), "--preview", str(preview), "--review", str(review))
            contract = json.loads(plan.read_text())
            self.assertEqual(contract["status"], "accepted")
            self.assertEqual(contract["events"][1]["detail"], "Analytics")
            self.assertIn("media_seconds", contract["events"][1])
            self.assertTrue((root / "proof.md").is_file())
            self.assertIn("Open Analytics", (root / "proof.md").read_text())

    def test_missing_required_state_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plan = root / "proof.json"
            accessibility = root / "accessibility.json"
            self.run_tool("init", "--output", str(plan), "--claim", "Data", "--start", "Home",
                          "--finish", "Analytics", "--evidence", "screenshot",
                          "--must-contain", "Metric Board")
            accessibility.write_text("[]")
            checked = self.run_tool("check-state", "--plan", str(plan),
                                    "--accessibility", str(accessibility), expected=3)
            self.assertIn("Metric Board", checked.stdout)
            blocked = self.run_tool("complete", "--plan", str(plan),
                                    "--screenshot", str(root / "proof.png"), expected=1)
            self.assertIn("state check has not passed", blocked.stderr)

    def test_complete_requires_promised_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plan = root / "proof.json"
            self.run_tool("init", "--output", str(plan), "--claim", "Flow works", "--start", "Home",
                          "--finish", "Analytics", "--evidence", "video")
            blocked = self.run_tool("complete", "--plan", str(plan), expected=1)
            self.assertIn("video is required", blocked.stderr)

    def test_complete_rejects_uncovered_planned_action(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plan = root / "proof.json"
            self.run_tool("init", "--output", str(plan), "--claim", "Search works", "--start", "Home",
                          "--action", "Type cuties", "--finish", "Results", "--evidence", "screenshot")
            screenshot = root / "proof.png"
            screenshot.write_text("proof")
            blocked = self.run_tool("complete", "--plan", str(plan),
                                    "--screenshot", str(screenshot), expected=1)
            self.assertIn("Type cuties", blocked.stderr)


if __name__ == "__main__":
    unittest.main()
