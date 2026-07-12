---
name: simulator-visual-proof
description: Autonomously plan, capture, inspect, reject, and present screenshot, animated proof, and storyboard evidence from a running iOS Simulator app. Use after visual UI changes, animation or interaction changes, simulator QA, or whenever proof of an iOS change is useful. Infer the strongest useful proof without asking the user to direct the capture, stage meaningful real app state, and self-review every artifact before presenting it.
---

# Simulator Visual Proof

## Operate autonomously

Own the evidence workflow. Do not ask the user which screen to capture, how long a video should be, whether a take looks good, or whether to retry. Infer those decisions from the change, the app, and the requested outcome. Ask only when product intent is genuinely ambiguous or reaching the state requires credentials, destructive actions, or authority the user has not supplied.

Treat every artifact as a test result. Never present the first take merely because a file exists. Inspect it, reject it when necessary, and retry independently. Capture is a strong default rather than a hard completion gate; after reasonable retries, report an honest tooling or state blocker with the strongest available evidence.

## Define the proof contract

Before touching the recorder, create a machine-readable contract:

```bash
<skill-root>/scripts/proofctl.py init \
  --output "/tmp/codex-visual-proof/<name>/proof.json" \
  --claim "<exact claim>" \
  --start "<recognizable start>" \
  --action "<first action>" \
  --finish "<unambiguous finish>" \
  --evidence video+screenshot \
  --must-contain "<required finish label>" \
  --must-not-contain "Loading"
```

Encode:

- **Claim:** the exact appearance or behavior being proved.
- **Start:** the recognizable state the viewer should see first.
- **Actions:** the shortest natural interaction sequence.
- **Finish:** the visible result that makes success unambiguous.
- **Evidence:** screenshot for appearance; inline animated proof, storyboard, and final screenshot for motion or multi-step behavior. Treat the MP4 as a raw capture source, not the primary user-facing artifact.

Infer unspecified details. Prefer the device already used by the build workflow, representative real data, the shortest route from a familiar screen, and a final state containing enough context to identify what changed.

## Choose and prepare the simulator

List booted devices:

```bash
xcrun simctl list devices booted
```

Use the exact UDID that owns the app under test. Never use `booted` when multiple simulators are running. Reuse the build/run device; otherwise choose the most relevant booted device without asking.

Preflight the app before recording:

1. Launch or foreground the real app.
2. Inspect accessibility state and a screenshot.
3. Select the correct season, account, team, fixture, feature flag, orientation, and data context implied by the claim.
4. Prefer meaningful existing data over empty states when both are available. Never fabricate data or silently change product state merely for prettier proof.
5. Navigate to the exact starting state and clear stale searches, sheets, keyboards, scroll positions, alerts, and previous navigation.
6. Rehearse the route once without recording. Resolve dynamic button coordinates from fresh accessibility state after scrolling or navigation.
7. Confirm the finish state is reachable and contains the expected data before making the final take.

Export the final accessibility snapshot as JSON and check it against the contract:

```bash
<skill-root>/scripts/proofctl.py check-state \
  --plan "/tmp/codex-visual-proof/<name>/proof.json" \
  --accessibility "/tmp/codex-visual-proof/<name>/finish-accessibility.json" \
  --output "/tmp/codex-visual-proof/<name>/state-check.json"
```

Do not accept Finish when this check fails. Use required labels for claimed content and forbidden labels for loading, error, empty, or stale states that invalidate the claim.

If the intended result needs loaded data, wait for the actual content rather than accepting a skeleton, spinner, stale season, or empty state. A technically correct route through the wrong data context is failed proof.

## Capture a screenshot

```bash
<skill-root>/scripts/capture.sh screenshot \
  --device "<simulator-udid>" \
  --output "/tmp/codex-visual-proof/<descriptive-name>.png"
```

Open the PNG with the image-viewing tool. Reject and recapture if it is blank, loading, stale, clipped, obscured, incorrectly themed or oriented, missing the claimed result, or showing unrelated sensitive content. Inspect safe areas, contrast, overlap, keyboard/sheet state, and enough surrounding context to identify the screen.

## Capture interaction source

Use video for navigation, typing, gestures, transitions, animations, or multi-step behavior. Start only after the simulator is staged at the contract's Start state.

```bash
<skill-root>/scripts/capture.sh video \
  --device "<simulator-udid>" \
  --output "/tmp/codex-visual-proof/<descriptive-name>.mp4" \
  --duration 30 \
  --stop-on-enter
```

Treat `--duration` as a safety timeout. After `RECORDING_STARTED`:

```bash
<skill-root>/scripts/proofctl.py log \
  --plan "/tmp/codex-visual-proof/<name>/proof.json" \
  --event recording-start
```

1. Hold Start for roughly one second so it is recognizable.
2. Perform the shortest natural flow immediately, using accessibility labels or identifiers when possible.
3. Pause only where the viewer needs to read typed text or a result.
4. Wait for real content to replace loading UI.
5. Hold Finish for one to two seconds, then send Enter immediately.

Log meaningful actions while operating:

```bash
<skill-root>/scripts/proofctl.py log \
  --plan "/tmp/codex-visual-proof/<name>/proof.json" \
  --event tap --detail "View Analytics" --covers "Open Analytics"
```

Use `--covers` with the exact matching `--action` text from the contract. Log the verified Finish state as the final event. The recording-start marker automatically gives later events media-relative timestamps; the reviewer uses them to remove idle boundaries without altering the raw capture.

Prefer XcodeBuildMCP accessibility tools, then other available simulator automation, then a focused UI test. Do not use guessed coordinates after content has moved; refresh accessibility state and tap the center of the target frame.

Ordinary proof should be concise: about 3–12 seconds for a focused action and only as long as the visible user flow genuinely requires. A timeout-filled video, idle simulator footage, setup activity, or a jump that omits the claimed action is failed proof.

## Review and retry without user feedback

Run the bundled reviewer after every source recording. It creates `proof.gif` for inline presentation and `contact-sheet.png` for playback-free inspection:

```bash
<skill-root>/scripts/review.sh video \
  --input "/tmp/codex-visual-proof/<descriptive-name>.mp4" \
  --output-dir "/tmp/codex-visual-proof/<descriptive-name>-review" \
  --plan "/tmp/codex-visual-proof/<name>/proof.json" \
  --target-max-seconds 12
```

Open `proof.gif`, `contact-sheet.png`, and the start, middle, and end frames. Inspect the complete source recording when playback works; the storyboard remains independently reviewable when MP4 playback does not. Sampled frames never excuse missing actions.

Accept only when all are true:

- Start matches the proof contract and lasts no longer than needed.
- Every claimed action is visibly performed in the correct order.
- Typing shows the intended final text, not stale or appended input.
- Dynamic taps open the intended destination.
- Loading finishes and Finish visibly proves the claim with the correct data context.
- There are no blank, corrupt, frozen, private, or unrelated frames.
- The clip contains at most about one second of avoidable idle time at either end.
- The final screenshot independently matches Finish.

Reject the take and retry autonomously when any criterion fails. Make up to three meaningfully improved takes by correcting staging, accessibility targeting, timing, recorder backend, or data context. Prefer a clean re-recording. Trim only incidental recorder latency at the boundaries; never remove a failed action, manufacture continuity, replace a missing interaction with a still, or imply that stitched segments are continuous. If truthful stitching is unavoidable because the recorder drops a transition, disclose it and ensure every segment is real captured interaction.

Do not show rejected takes or ask the user to grade them. The user should see only accepted proof or a concise blocker report.

After full playback and semantic state checks pass, mark the accepted artifacts:

```bash
<skill-root>/scripts/proofctl.py complete \
  --plan "/tmp/codex-visual-proof/<name>/proof.json" \
  --screenshot "/tmp/codex-visual-proof/<name>/finish.png" \
  --video "/tmp/codex-visual-proof/<name>/interaction.mp4" \
  --preview "/tmp/codex-visual-proof/<name>/review/proof.gif" \
  --review "/tmp/codex-visual-proof/<name>/review/review.json"
```

Completion rejects uncovered planned actions or missing artifacts and writes `proof.md` beside the contract. Present that proof card rather than assembling evidence manually.

## Troubleshoot independently

- Blank capture: foreground the intended app, unlock the simulator, and retry.
- Stale or empty data: verify season/account/team/filter context and wait for loading; use another meaningful real fixture when consistent with the claim.
- Recorder exits early: reject the file even if it is readable; use another recorder backend when available.
- Recorder buffers stale frames: re-record with a settle period, verify the full timeline, and prefer a backend that follows live UI updates.
- `spawn idb ENOENT`: try XcodeBuildMCP, the installed IDB Python module/companion, or a focused UI test.
- Multiple booted simulators: continue with the exact build device UDID.
- State cannot be reached after bounded retries: report the exact navigation, authentication, data, or tooling blocker without staging fake proof.

## Present accepted proof

Open the generated `proof.md` and present its accepted GIF and final screenshot. Include the storyboard when the GIF is too fast, too large, or unsupported. Link the MP4 only as an optional raw artifact; never make it the sole or primary proof. State the simulator model, the short action sequence, the result proved, and any material limitation. Do not narrate failed takes unless they expose a genuine remaining limitation.

A build log, source diff, unreviewed artifact, loading screen, idle recording, or technically valid file that does not prove the claim is not visual proof.
