#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  review.sh video --input <file.mp4> --output-dir <directory> [--target-max-seconds <seconds>]

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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input) [[ $# -ge 2 ]] || die '--input requires a value'; input="$2"; shift 2 ;;
    --output-dir) [[ $# -ge 2 ]] || die '--output-dir requires a value'; output_dir="$2"; shift 2 ;;
    --target-max-seconds) [[ $# -ge 2 ]] || die '--target-max-seconds requires a value'; target_max="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "$input" == /* ]] || die '--input must be an absolute path'
[[ "$output_dir" == /* ]] || die '--output-dir must be an absolute path'
[[ -s "$input" ]] || die 'input video is missing or empty'
[[ "$target_max" =~ ^[0-9]+([.][0-9]+)?$ ]] || die '--target-max-seconds must be numeric'
command -v ffmpeg >/dev/null || die 'ffmpeg is required'

mkdir -p "$output_dir"
metadata="$output_dir/metadata.txt"
ffmpeg -hide_banner -i "$input" 2>"$metadata" || true
duration="$(sed -nE 's/.*Duration: ([0-9]+):([0-9]+):([0-9]+([.][0-9]+)?).*/\1 \2 \3/p' "$metadata" | head -1 | awk '{ printf "%.2f", ($1 * 3600) + ($2 * 60) + $3 }')"
[[ -n "$duration" ]] || die 'could not determine video duration'

midpoint="$(awk -v d="$duration" 'BEGIN { printf "%.3f", d / 2 }')"
endpoint="$(awk -v d="$duration" 'BEGIN { e=d-0.15; if (e<0) e=0; printf "%.3f", e }')"

ffmpeg -y -ss 0 -i "$input" -frames:v 1 "$output_dir/start.png" >/dev/null 2>&1
ffmpeg -y -ss "$midpoint" -i "$input" -frames:v 1 "$output_dir/middle.png" >/dev/null 2>&1
ffmpeg -y -ss "$endpoint" -i "$input" -frames:v 1 "$output_dir/end.png" >/dev/null 2>&1
sample_rate="$(awk -v d="$duration" 'BEGIN { r=16/d; if (r>2) r=2; printf "%.6f", r }')"
ffmpeg -y -i "$input" -vf "fps=$sample_rate,scale=240:-1,tile=4x4" -frames:v 1 "$output_dir/contact-sheet.png" >/dev/null 2>&1
ffmpeg -y -i "$input" -filter_complex \
  "fps=8,scale=420:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=3" \
  -loop 0 "$output_dir/proof.gif" >/dev/null 2>&1

warning="none"
if awk -v d="$duration" -v m="$target_max" 'BEGIN { exit !(d > m) }'; then
  warning="duration ${duration}s exceeds target ${target_max}s; inspect for avoidable idle time"
fi

cat >"$output_dir/review.txt" <<EOF
duration_seconds=$duration
target_max_seconds=$target_max
warning=$warning
required_manual_review=watch the entire video and verify the proof contract
EOF

python3 - "$output_dir/review.json" "$duration" "$target_max" "$warning" <<'PY'
import json
import sys

path, duration, target, warning = sys.argv[1:]
with open(path, "w") as handle:
    json.dump({"duration_seconds": float(duration),
               "target_max_seconds": float(target),
               "duration_within_target": float(duration) <= float(target),
               "warning": warning, "requires_full_playback": True,
               "primary_presentation": "proof.gif",
               "storyboard": "contact-sheet.png",
               "decision": "review_required"}, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

printf 'duration_seconds=%s\n' "$duration"
printf 'warning=%s\n' "$warning"
printf 'contact_sheet=%s\n' "$output_dir/contact-sheet.png"
printf 'animated_proof=%s\n' "$output_dir/proof.gif"
printf 'start_frame=%s\n' "$output_dir/start.png"
printf 'middle_frame=%s\n' "$output_dir/middle.png"
printf 'end_frame=%s\n' "$output_dir/end.png"
printf 'review_json=%s\n' "$output_dir/review.json"
