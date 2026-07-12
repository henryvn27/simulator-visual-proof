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

Use video to show the agent actually operating the app: tapping controls, typing, scrolling, navigating, exercising animations, and completing multi-step flows. First navigate to a sensible starting state and inspect the UI so the interaction path is known.

Start the capture in a long-running terminal session that can yield while it remains active:

```bash
<skill-root>/scripts/capture.sh video \
  --device "<simulator-udid>" \
  --output "/tmp/codex-visual-proof/<descriptive-name>.mp4" \
  --duration 20 \
  --poster "/tmp/codex-visual-proof/<descriptive-name>-poster.png"
```

Wait until the terminal prints `RECORDING_STARTED`. While that same recording session remains active, use the simulator UI tools to perform the shortest clear demonstration:

1. Describe the current UI before tapping.
2. Tap by accessibility identifier or label when possible.
3. Type, swipe, scroll, or navigate through the requested behavior.
4. Pause briefly on the final state so it is readable.
5. Wait for the recording command to finish and finalize the MP4.

Prefer XcodeBuildMCP accessibility-based snapshot, tap, gesture, and typing tools when enabled. Otherwise use the available iOS Simulator UI automation tools. If interactive tools are unavailable, a focused UI test may drive the same real app flow while the recorder runs. Do not substitute app relaunches or unrelated system activity for the requested interaction.

The script sends `SIGINT` to `simctl`, waits for finalization, validates the movie, and optionally creates a poster frame. Choose a duration from 1 to 60 seconds that leaves enough time for tool round trips. Do not record idle simulator footage and call it interaction proof.

If a tool call takes longer than expected, repeat the recording with a longer duration rather than rushing or omitting the important action. Keep sensitive text, notifications, credentials, and unrelated user data out of the recording.

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
- UI automation reports a missing helper such as `spawn idb ENOENT`: try the XcodeBuildMCP UI tools or a focused UI test; if neither is available, report interaction proof as blocked rather than presenting idle footage.
- UI cannot reach the changed state: report the navigation, data, authentication, or runtime blocker rather than staging fake proof.
- Multiple simulators are booted: never substitute the `booted` alias; keep using the build workflow's explicit UDID.

## Present proof

Show the screenshot or poster inline with an absolute local path. Link the playable MP4 with an absolute local path so Henry can watch the agent perform the flow. State the simulator model, the actions shown, the screen or behavior proved, and any state that could not be reached. A build log, source diff, idle recording, or uninspected artifact is not interaction proof.

Treat capture as a strong default, not a hard gate. If simulator capture is unavailable or disproportionate, report why and state the strongest visual or non-visual verification completed instead.
