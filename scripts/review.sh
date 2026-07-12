#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  review.sh video --input <file.mp4> --output-dir <directory> [--plan <proof.json>] [--target-max-seconds <seconds>]

Generates an inline animated proof, storyboard, and deterministic review artifacts.
The agent must still inspect the complete source timeline.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[[ ${1:-} == "video" ]] || { usage; exit 2; }
shift
input=""
output_dir=""
target_max="12"
plan=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input) [[ $# -ge 2 ]] || die '--input requires a value'; input="$2"; shift 2 ;;
    --output-dir) [[ $# -ge 2 ]] || die '--output-dir requires a value'; output_dir="$2"; shift 2 ;;
    --plan) [[ $# -ge 2 ]] || die '--plan requires a value'; plan="$2"; shift 2 ;;
    --target-max-seconds) [[ $# -ge 2 ]] || die '--target-max-seconds requires a value'; target_max="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "$input" == /* ]] || die '--input must be an absolute path'
[[ "$output_dir" == /* ]] || die '--output-dir must be an absolute path'
[[ -s "$input" ]] || die 'input video is missing or empty'
[[ -z "$plan" || ( "$plan" == /* && -s "$plan" ) ]] || die '--plan must be an absolute path to a non-empty file'
[[ "$target_max" =~ ^[0-9]+([.][0-9]+)?$ ]] || die '--target-max-seconds must be numeric'
command -v ffmpeg >/dev/null || die 'ffmpeg is required'

mkdir -p "$output_dir"
metadata="$output_dir/metadata.txt"
ffmpeg -hide_banner -i "$input" 2>"$metadata" || true
duration="$(sed -nE 's/.*Duration: ([0-9]+):([0-9]+):([0-9]+([.][0-9]+)?).*/\1 \2 \3/p' "$metadata" | head -1 | awk '{ printf "%.2f", ($1 * 3600) + ($2 * 60) + $3 }')"
[[ -n "$duration" ]] || die 'could not determine video duration'

clip_start="0"
clip_end="$duration"
if [[ -n "$plan" ]]; then
  python3 - "$plan" "$duration" "$output_dir/milestones.json" "$output_dir/clip-range.txt" <<'PY'
import json
import sys

plan, duration, output, range_output = sys.argv[1], float(sys.argv[2]), sys.argv[3], sys.argv[4]
with open(plan) as handle:
    events = [event for event in json.load(handle).get("events", [])
              if event.get("event") != "recording-start" and "media_seconds" in event]
times = [float(event["media_seconds"]) for event in events]
start = max(0, min(times) - 0.75) if times else 0
end = min(duration, max(times) + 1.25) if times else duration
with open(output, "w") as handle:
    json.dump({"clip_start_seconds": start, "clip_end_seconds": end, "events": events},
              handle, indent=2, sort_keys=True)
    handle.write("\n")
with open(range_output, "w") as handle:
    handle.write(f"{start:.3f} {end:.3f}\n")
PY
  read -r clip_start clip_end <"$output_dir/clip-range.txt"
fi
clip_duration="$(awk -v s="$clip_start" -v e="$clip_end" 'BEGIN { printf "%.3f", e-s }')"
midpoint="$(awk -v s="$clip_start" -v e="$clip_end" 'BEGIN { printf "%.3f", (s+e)/2 }')"
endpoint="$(awk -v e="$clip_end" 'BEGIN { e=e-0.15; if (e<0) e=0; printf "%.3f", e }')"

ffmpeg -y -ss "$clip_start" -i "$input" -frames:v 1 "$output_dir/start.png" >/dev/null 2>&1
ffmpeg -y -ss "$midpoint" -i "$input" -frames:v 1 "$output_dir/middle.png" >/dev/null 2>&1
ffmpeg -y -ss "$endpoint" -i "$input" -frames:v 1 "$output_dir/end.png" >/dev/null 2>&1
sample_rate="$(awk -v d="$clip_duration" 'BEGIN { r=16/d; if (r>2) r=2; printf "%.6f", r }')"
ffmpeg -y -ss "$clip_start" -t "$clip_duration" -i "$input" -vf "fps=$sample_rate,scale=240:-1,tile=4x4" -frames:v 1 "$output_dir/contact-sheet.png" >/dev/null 2>&1
ffmpeg -y -ss "$clip_start" -t "$clip_duration" -i "$input" -filter_complex \
  "fps=8,scale=420:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=3" \
  -loop 0 "$output_dir/proof.gif" >/dev/null 2>&1

warnings=()
if awk -v d="$clip_duration" -v m="$target_max" 'BEGIN { exit !(d > m) }'; then
  warnings+=("proof duration ${clip_duration}s exceeds target ${target_max}s; inspect for avoidable idle time")
fi
if cmp -s "$output_dir/start.png" "$output_dir/middle.png" && cmp -s "$output_dir/middle.png" "$output_dir/end.png"; then
  warnings+=("start, middle, and end frames are identical; inspect for idle or frozen footage")
fi
if ffmpeg -hide_banner -v info -ss "$clip_start" -t "$clip_duration" -i "$input" \
  -vf "blackframe=amount=98:threshold=32" -an -f null - 2>&1 | grep -q 'blackframe:'; then
  warnings+=("black frames detected; inspect for blank or obscured simulator footage")
fi
warning="none"
if [[ ${#warnings[@]} -gt 0 ]]; then
  warning="${warnings[0]}"
  for item in "${warnings[@]:1}"; do
    warning="$warning | $item"
  done
fi

cat >"$output_dir/review.txt" <<EOF
duration_seconds=$duration
target_max_seconds=$target_max
warning=$warning
required_manual_review=watch the entire video and verify the proof contract
EOF

python3 - "$output_dir/review.json" "$duration" "$target_max" "$warning" "$clip_start" "$clip_end" <<'PY'
import json
import sys

path, duration, target, warning, clip_start, clip_end = sys.argv[1:]
warnings = [] if warning == "none" else warning.split(" | ")
with open(path, "w") as handle:
    json.dump({"duration_seconds": float(duration),
               "target_max_seconds": float(target),
               "duration_within_target": float(clip_end) - float(clip_start) <= float(target),
               "clip_start_seconds": float(clip_start),
               "clip_end_seconds": float(clip_end),
               "clip_duration_seconds": float(clip_end) - float(clip_start),
               "warning": warning, "warnings": warnings, "requires_full_playback": True,
               "primary_presentation": "proof.gif",
               "storyboard": "contact-sheet.png",
               "decision": "review_required"}, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

printf 'duration_seconds=%s\n' "$duration"
printf 'warning=%s\n' "$warning"
printf 'clip_seconds=%s..%s\n' "$clip_start" "$clip_end"
printf 'contact_sheet=%s\n' "$output_dir/contact-sheet.png"
printf 'animated_proof=%s\n' "$output_dir/proof.gif"
printf 'start_frame=%s\n' "$output_dir/start.png"
printf 'middle_frame=%s\n' "$output_dir/middle.png"
printf 'end_frame=%s\n' "$output_dir/end.png"
printf 'review_json=%s\n' "$output_dir/review.json"
