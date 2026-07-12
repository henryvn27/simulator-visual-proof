#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
capture="$root/scripts/capture.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

expect_failure() {
  if "$@" >"$tmp/stdout" 2>"$tmp/stderr"; then
    printf 'expected failure: %q ' "$@" >&2
    printf '\n' >&2
    exit 1
  fi
}

"$capture" --help >/dev/null
expect_failure "$capture" screenshot --output "$tmp/proof.png"
grep -q -- '--device is required' "$tmp/stderr"
expect_failure "$capture" screenshot --device invalid --output "$tmp/proof.png"
grep -q -- 'simulator UDID' "$tmp/stderr"
expect_failure "$capture" video --device 00000000-0000-0000-0000-000000000000 --output "$tmp/proof.mp4" --duration 0
grep -q -- 'between 1 and 60' "$tmp/stderr"
expect_failure "$capture" screenshot --device 00000000-0000-0000-0000-000000000000 --output relative.png
grep -q -- 'absolute path' "$tmp/stderr"

printf 'capture argument tests passed\n'

if [[ -n "${SIMULATOR_UDID:-}" ]]; then
  "$capture" screenshot \
    --device "$SIMULATOR_UDID" \
    --output "$tmp/integration.png" >/dev/null
  video_output="$($capture video \
    --device "$SIMULATOR_UDID" \
    --output "$tmp/integration.mp4" \
    --duration 1 \
    --poster "$tmp/integration-poster.png")"
  grep -q 'RECORDING_STARTED' <<<"$video_output"
  file "$tmp/integration.png" | grep -q 'PNG image data'
  file "$tmp/integration.mp4" | grep -Eq 'QuickTime|ISO Media'
  file "$tmp/integration-poster.png" | grep -q 'PNG image data'
  printf 'live simulator integration tests passed\n'
else
  printf 'live simulator integration tests skipped (set SIMULATOR_UDID to enable)\n'
fi
