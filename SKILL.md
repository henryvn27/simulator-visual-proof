---
name: simulator-visual-proof
description: Capture, inspect, and present screenshot or video proof from a running iOS Simulator app. Use after visual UI changes, animation or interaction changes, simulator QA, or whenever the user asks to see proof of an iOS change. Make a best-effort screenshot for visual changes and use video when motion, transitions, gestures, or multi-step behavior matter.
---

# Simulator Visual Proof

## Choose the simulator

List booted devices and select the exact UDID that owns the app under test:

```bash
xcrun simctl list devices booted
```

Never use the `booted` alias when more than one simulator is running. Reuse the simulator selected by the build/run workflow.

## Reach the changed state

Build, launch, and navigate the real app to the changed screen. Use real available data; do not fabricate content merely to make proof look complete. Wait for loading and animation to settle before capturing a final-state screenshot.

## Capture a screenshot

Use the bundled script with an exact device UDID and absolute output path:

```bash
<skill-root>/scripts/capture.sh screenshot \
  --device "<simulator-udid>" \
  --output "/tmp/codex-visual-proof/<descriptive-name>.png"
```

The script wakes the display, writes atomically, and rejects missing or unreadable output.

Open the PNG with the available image-viewing tool. Check that it shows the intended screen and inspect clipping, overlap, contrast, safe areas, stale data, loading/error states, and accidental regressions. Recapture after fixing any problem.

If the inspected PNG is blank or black, confirm that the intended app is foregrounded and recapture. A technically valid but blank image is failed proof.

## Record a video

Use video for animation, transitions, gestures, scrolling, navigation, or other behavior a still image cannot prove:

```bash
<skill-root>/scripts/capture.sh video \
  --device "<simulator-udid>" \
  --output "/tmp/codex-visual-proof/<descriptive-name>.mp4" \
  --duration 8 \
  --poster "/tmp/codex-visual-proof/<descriptive-name>-poster.png"
```

Start the command, perform the shortest interaction that demonstrates the change during the recording window, and wait for completion. The script waits for the first frame, sends `SIGINT`, waits for finalization, validates the movie, and optionally creates a poster frame. Use a duration from 1 to 60 seconds.

The script validates that the file is non-empty and readable. For additional metadata when needed:

```bash
test -s "/tmp/codex-visual-proof/<descriptive-name>.mp4"
xcrun simctl list devices | rg "<simulator-udid>"
mdls -name kMDItemDurationSeconds -name kMDItemPixelHeight -name kMDItemPixelWidth \
  "/tmp/codex-visual-proof/<descriptive-name>.mp4"
```

Inspect representative frames with the available video/image tooling. Re-record if the interaction is missing, obscured, or begins/ends in the wrong state.

## Troubleshoot

- `simulator is not booted`: use `xcrun simctl list devices booted` and pass the exact active UDID.
- Blank capture: foreground the app, ensure the screen is unlocked, and retry.
- Recording does not start: run `xcrun simctl io <UDID> enumerate` and confirm the display exists.
- UI cannot reach the changed state: report the navigation, data, authentication, or runtime blocker rather than staging fake proof.
- Multiple simulators are booted: never substitute the `booted` alias; keep using the build workflow's explicit UDID.

## Present proof

Show the screenshot inline with an absolute local path. Link the MP4 with an absolute local path when video was required. State the simulator model, screen or flow proved, and any state that could not be reached. A build log, source diff, or uninspected artifact is not visual proof.

Treat capture as a strong default, not a hard gate. If simulator capture is unavailable or disproportionate, report why and state the strongest visual or non-visual verification completed instead.
