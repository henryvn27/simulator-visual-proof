#!/usr/bin/env python3
"""Small coordinator for simulator visual proof workspaces."""

import argparse
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROOFCTL = ROOT / "scripts" / "proofctl.py"
REVIEW = ROOT / "scripts" / "review.sh"


def absolute_path(value):
    path = Path(value)
    if not path.is_absolute():
        raise argparse.ArgumentTypeError("path must be absolute")
    return path


def run(*command):
    return subprocess.run([str(item) for item in command], check=False)


def command_init(args):
    args.output_dir.mkdir(parents=True, exist_ok=True)
    plan = args.output_dir / "proof.json"
    command = [
        PROOFCTL, "init", "--output", plan, "--claim", args.claim,
        "--start", args.start, "--finish", args.finish,
        "--evidence", args.evidence,
    ]
    for action in args.action:
        command.extend(["--action", action])
    for label in args.must_contain:
        command.extend(["--must-contain", label])
    for label in args.must_not_contain:
        command.extend(["--must-not-contain", label])
    result = run(*command)
    if result.returncode == 0:
        print(f"plan={plan}")
        print(f"video={args.output_dir / 'interaction.mp4'}")
        print(f"screenshot={args.output_dir / 'finish.png'}")
        print(f"review_dir={args.output_dir / 'review'}")
    return result.returncode


def command_review(args):
    return run(REVIEW, "video", "--input", args.video,
               "--output-dir", args.plan.parent / "review",
               "--plan", args.plan,
               "--target-max-seconds", args.target_max_seconds).returncode


def command_complete(args):
    root = args.plan.parent
    return run(PROOFCTL, "complete", "--plan", args.plan,
               "--screenshot", root / "finish.png",
               "--video", root / "interaction.mp4",
               "--preview", root / "review" / "proof.gif",
               "--review", root / "review" / "review.json").returncode


def command_status(args):
    return run(PROOFCTL, "status", "--plan", args.plan).returncode


def command_handoff(args):
    command = [PROOFCTL, "handoff", "--plan", args.plan]
    for destination in args.destination:
        command.extend(["--destination", destination])
    return run(*command).returncode


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    init = commands.add_parser("init")
    init.add_argument("--output-dir", type=absolute_path, required=True)
    init.add_argument("--claim", required=True)
    init.add_argument("--start", required=True)
    init.add_argument("--action", action="append", default=[])
    init.add_argument("--finish", required=True)
    init.add_argument("--evidence", choices=("screenshot", "video", "video+screenshot"),
                      default="video+screenshot")
    init.add_argument("--must-contain", action="append", default=[])
    init.add_argument("--must-not-contain", action="append", default=[])
    init.set_defaults(function=command_init)

    review = commands.add_parser("review")
    review.add_argument("--plan", type=absolute_path, required=True)
    review.add_argument("--video", type=absolute_path)
    review.add_argument("--target-max-seconds", default="12")
    review.set_defaults(function=command_review)

    complete = commands.add_parser("complete")
    complete.add_argument("--plan", type=absolute_path, required=True)
    complete.set_defaults(function=command_complete)

    status = commands.add_parser("status")
    status.add_argument("--plan", type=absolute_path, required=True)
    status.set_defaults(function=command_status)

    handoff = commands.add_parser("handoff")
    handoff.add_argument("--plan", type=absolute_path, required=True)
    handoff.add_argument("--destination", action="append",
                         choices=("linear", "github"), required=True)
    handoff.set_defaults(function=command_handoff)
    return parser


if __name__ == "__main__":
    arguments = build_parser().parse_args()
    if arguments.command == "review" and arguments.video is None:
        arguments.video = arguments.plan.parent / "interaction.mp4"
    sys.exit(arguments.function(arguments))
