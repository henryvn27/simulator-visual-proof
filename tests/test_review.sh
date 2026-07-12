#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
review="$root/scripts/review.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

expect_failure() {
  if "$@" >"$tmp/stdout" 2>"$tmp/stderr"; then
    printf 'expected failure: %q ' "$@" >&2
    printf '\n' >&2
    exit 1
  fi
}

"$review" --help >/dev/null 2>&1 || true
expect_failure "$review" video --input relative.mp4 --output-dir "$tmp/review"
grep -q -- 'absolute path' "$tmp/stderr"
expect_failure "$review" video --input "$tmp/missing.mp4" --output-dir "$tmp/review"
grep -q -- 'missing or empty' "$tmp/stderr"

if command -v ffmpeg >/dev/null; then
  ffmpeg -y -f lavfi -i color=c=blue:s=320x240:d=2 -r 10 "$tmp/input.mp4" >/dev/null 2>&1
  output="$($review video --input "$tmp/input.mp4" --output-dir "$tmp/review" --target-max-seconds 1)"
  grep -q 'exceeds target' <<<"$output"
  test -s "$tmp/review/contact-sheet.png"
  test -s "$tmp/review/proof.gif"
  file "$tmp/review/proof.gif" | grep -q 'GIF image data'
  test -s "$tmp/review/start.png"
  test -s "$tmp/review/middle.png"
  test -s "$tmp/review/end.png"
  grep -q 'required_manual_review=' "$tmp/review/review.txt"
  python3 - "$tmp/review/review.json" <<'PY'
import json
import sys
with open(sys.argv[1]) as handle:
    review = json.load(handle)
assert review["decision"] == "review_required"
assert review["duration_within_target"] is False
assert review["primary_presentation"] == "proof.gif"
assert review["storyboard"] == "contact-sheet.png"
PY
fi

printf 'review tests passed\n'
