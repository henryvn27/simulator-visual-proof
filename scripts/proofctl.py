#!/usr/bin/env python3
"""Create and evaluate machine-readable simulator proof contracts."""

import argparse
import datetime as dt
import json
import os
import sys
import time
from pathlib import Path


def absolute_path(value):
    path = Path(value)
    if not path.is_absolute():
        raise argparse.ArgumentTypeError("path must be absolute")
    return path


def read_json(path):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        raise SystemExit(f"error: missing file: {path}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"error: invalid JSON in {path}: {exc}")


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".partial")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    os.replace(temporary, path)


def flatten_strings(value):
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        result = []
        for key, item in value.items():
            result.extend([str(key), *flatten_strings(item)])
        return result
    if isinstance(value, list):
        result = []
        for item in value:
            result.extend(flatten_strings(item))
        return result
    return []


def command_init(args):
    contract = {
        "version": 1, "status": "planned", "claim": args.claim,
        "start": args.start, "actions": args.action, "finish": args.finish,
        "evidence": args.evidence, "must_contain": args.must_contain,
        "must_not_contain": args.must_not_contain,
        "created_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "started_at_epoch": time.time(), "events": [], "artifacts": {},
    }
    write_json(args.output, contract)
    print(args.output)
    return 0


def command_check_state(args):
    contract = read_json(args.plan)
    haystack = "\n".join(flatten_strings(read_json(args.accessibility))).casefold()
    required = contract.get("must_contain", [])
    forbidden = contract.get("must_not_contain", [])
    missing = [label for label in required if label.casefold() not in haystack]
    present_forbidden = [label for label in forbidden if label.casefold() in haystack]
    result = {
        "accepted": not missing and not present_forbidden,
        "missing_required": missing, "present_forbidden": present_forbidden,
        "required_count": len(required), "forbidden_count": len(forbidden),
    }
    contract["state_check"] = result
    contract["status"] = "state_verified" if result["accepted"] else "state_rejected"
    write_json(args.plan, contract)
    if args.output:
        write_json(args.output, result)
    print(json.dumps(result, sort_keys=True))
    return 0 if result["accepted"] else 3


def command_log(args):
    contract = read_json(args.plan)
    started = float(contract.get("started_at_epoch", time.time()))
    contract.setdefault("events", []).append({
        "seconds": round(time.time() - started, 3),
        "event": args.event, "detail": args.detail,
    })
    contract["status"] = "recording"
    write_json(args.plan, contract)
    return 0


def command_complete(args):
    contract = read_json(args.plan)
    has_semantic_constraints = bool(contract.get("must_contain") or contract.get("must_not_contain"))
    if has_semantic_constraints and not contract.get("state_check", {}).get("accepted"):
        raise SystemExit("error: latest semantic state check has not passed")
    evidence = contract.get("evidence")
    required = []
    if evidence in ("screenshot", "video+screenshot"):
        required.append(("screenshot", args.screenshot))
    if evidence in ("video", "video+screenshot"):
        required.append(("video", args.video))
        required.append(("review", args.review))
        required.append(("preview", args.preview))
    for name, path in required:
        if path is None:
            raise SystemExit(f"error: {name} is required by the proof contract")
        if not path.is_file() or path.stat().st_size == 0:
            raise SystemExit(f"error: {name} artifact is missing or empty: {path}")
    contract["status"] = "accepted"
    contract["completed_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
    contract["artifacts"] = {
        "screenshot": str(args.screenshot) if args.screenshot else None,
        "video": str(args.video) if args.video else None,
        "preview": str(args.preview) if args.preview else None,
        "review": str(args.review) if args.review else None,
    }
    write_json(args.plan, contract)
    print(args.plan)
    return 0


def build_parser():
    root = argparse.ArgumentParser(description=__doc__)
    commands = root.add_subparsers(dest="command", required=True)
    init = commands.add_parser("init")
    init.add_argument("--output", type=absolute_path, required=True)
    init.add_argument("--claim", required=True)
    init.add_argument("--start", required=True)
    init.add_argument("--action", action="append", default=[])
    init.add_argument("--finish", required=True)
    init.add_argument("--evidence", choices=("screenshot", "video", "video+screenshot"), required=True)
    init.add_argument("--must-contain", action="append", default=[])
    init.add_argument("--must-not-contain", action="append", default=[])
    init.set_defaults(function=command_init)
    check = commands.add_parser("check-state")
    check.add_argument("--plan", type=absolute_path, required=True)
    check.add_argument("--accessibility", type=absolute_path, required=True)
    check.add_argument("--output", type=absolute_path)
    check.set_defaults(function=command_check_state)
    log = commands.add_parser("log")
    log.add_argument("--plan", type=absolute_path, required=True)
    log.add_argument("--event", required=True)
    log.add_argument("--detail", default="")
    log.set_defaults(function=command_log)
    complete = commands.add_parser("complete")
    complete.add_argument("--plan", type=absolute_path, required=True)
    complete.add_argument("--screenshot", type=absolute_path)
    complete.add_argument("--video", type=absolute_path)
    complete.add_argument("--preview", type=absolute_path)
    complete.add_argument("--review", type=absolute_path)
    complete.set_defaults(function=command_complete)
    return root


if __name__ == "__main__":
    arguments = build_parser().parse_args()
    sys.exit(arguments.function(arguments))
