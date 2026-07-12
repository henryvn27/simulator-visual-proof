#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  capture.sh screenshot --device <UDID> --output <file.png>
  capture.sh video --device <UDID> --output <file.mp4> [--duration <seconds>] [--stop-on-enter] [--poster <file.png>]

Options:
  --device    Exact UDID of a booted iOS Simulator.
  --output    Absolute output path.
  --duration  Safety timeout in seconds (default: 8, maximum: 60).
  --stop-on-enter
              Stop as soon as Enter is pressed; use this for action-cued proof.
  --poster    Optional PNG preview generated from the finished video.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[[ $# -gt 0 ]] || { usage; exit 2; }
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi
mode="$1"
shift

device=""
output=""
duration="8"
poster=""
stop_on_enter=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) [[ $# -ge 2 ]] || die '--device requires a value'; device="$2"; shift 2 ;;
    --output) [[ $# -ge 2 ]] || die '--output requires a value'; output="$2"; shift 2 ;;
    --duration) [[ $# -ge 2 ]] || die '--duration requires a value'; duration="$2"; shift 2 ;;
    --stop-on-enter) stop_on_enter=1; shift ;;
    --poster) [[ $# -ge 2 ]] || die '--poster requires a value'; poster="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "$mode" == "screenshot" || "$mode" == "video" ]] || die "unknown mode: $mode"
[[ -n "$device" ]] || die '--device is required; never guess when multiple simulators may be booted'
[[ -n "$output" ]] || die '--output is required'
[[ "$output" == /* ]] || die '--output must be an absolute path'
[[ "$device" =~ ^[0-9A-Fa-f-]{36}$ ]] || die '--device must be a simulator UDID'
[[ "$duration" =~ ^[0-9]+$ ]] || die '--duration must be a whole number of seconds'
(( duration >= 1 && duration <= 60 )) || die '--duration must be between 1 and 60 seconds'
command -v xcrun >/dev/null || die 'xcrun is required'

device_line="$(xcrun simctl list devices booted | grep -F "$device" || true)"
[[ -n "$device_line" ]] || die "simulator is not booted: $device"

mkdir -p "$(dirname "$output")"
xcrun simctl io "$device" screenConfig power on >/dev/null

if [[ "$mode" == "screenshot" ]]; then
  [[ "$output" == *.png ]] || die 'screenshot output must end in .png'
  tmp="${output}.partial"
  trap 'rm -f "$tmp"' EXIT
  rm -f "$tmp"
  xcrun simctl io "$device" screenshot --type=png --mask=black "$tmp" >/dev/null
  [[ -s "$tmp" ]] || die 'simctl produced an empty screenshot'
  file "$tmp" | grep -q 'PNG image data' || die 'simctl output is not a readable PNG'
  mv -f "$tmp" "$output"
  trap - EXIT
  printf '%s\n' "$output"
  exit 0
fi

[[ "$output" == *.mp4 ]] || die 'video output must end in .mp4'
[[ -z "$poster" || "$poster" == /* ]] || die '--poster must be an absolute path'
[[ -z "$poster" || "$poster" == *.png ]] || die '--poster must end in .png'

tmp="${output}.partial.mp4"
log="${output}.recording.log"
pid=""
cleanup() {
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill -INT "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -f "$tmp" "$log"
}
trap cleanup EXIT INT TERM
rm -f "$tmp" "$log"
xcrun simctl io "$device" recordVideo --codec=h264 --mask=black --force "$tmp" >"$log" 2>&1 &
pid=$!

started=0
for _ in {1..100}; do
  if grep -q 'Recording started' "$log"; then
    started=1
    break
  fi
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.1
done
(( started == 1 )) || { cat "$log" >&2; die 'recording did not start'; }
printf 'RECORDING_STARTED %s\n' "$output"

if (( stop_on_enter == 1 )); then
  printf 'Perform the action now; press Enter immediately after the final state is readable.\n'
  read -r -t "$duration" _ || true
else
  sleep "$duration"
fi
kill -0 "$pid" 2>/dev/null || { cat "$log" >&2; die 'recorder exited before capture was stopped'; }
kill -INT "$pid"
wait "$pid"
pid=""
[[ -s "$tmp" ]] || die 'simctl produced an empty video'
file "$tmp" | grep -Eq 'QuickTime|ISO Media' || die 'simctl output is not a readable movie'
mv -f "$tmp" "$output"

if [[ -n "$poster" ]]; then
  command -v qlmanage >/dev/null || die 'qlmanage is required to generate a poster'
  mkdir -p "$(dirname "$poster")"
  preview_dir="$(mktemp -d)"
  qlmanage -t -s 1200 -o "$preview_dir" "$output" >/dev/null 2>&1
  generated="$preview_dir/$(basename "$output").png"
  [[ -s "$generated" ]] || die 'Quick Look could not generate a poster frame'
  mv -f "$generated" "$poster"
  rm -rf "$preview_dir"
fi

rm -f "$log"
trap - EXIT
printf '%s\n' "$output"
[[ -z "$poster" ]] || printf '%s\n' "$poster"
