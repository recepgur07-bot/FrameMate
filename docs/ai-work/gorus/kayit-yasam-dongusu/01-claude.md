# 01 — Claude (coordinator review)

Read-only review. No code was changed. Evidence is source-level; the runtime log lines
listed under "Doğrulama listesi" are what would confirm each finding on the user's Mac.

## Sonuç

The recording pipeline mixes **three different clocks** and treats them as one:

1. `ProcessInfo.systemUptime` sampled on the main actor (pause ranges),
2. each component file's own t=0 (its first sample PTS),
3. the screen file's t=0, which on macOS 15+ is written by `SCRecordingOutput` and is
   **not** the timestamp the app observes.

Every reported symptom is a consequence of that. The missing head is not one bug but a
sum of independent offsets that all point the same way, which is exactly why patching
them one at a time has looped: fixing one shrinks the gap without removing it. The fix
has to be structural — one session clock, captured once, that every component and the
pause timeline are expressed against — not another offset correction.

The stop error is a separate, simpler defect: an `isStopping` latch that is never
cleared on the early-return paths of `complete()`.

## Kritik bulgular

**K1 — Pause ranges are measured from a clock the cut is not applied to.**
`beginPauseTracking()` sets `recordingStartUptime` to the moment
`SCStream.startCapture()` *returned* (`RecorderViewModel.swift:1664`, set at
`:2469`). Pause offsets are then computed as `systemUptime - recordingStartUptime`
(`:1704`, `:1713`) and handed to `RecordingPauseTimeline.segments(for:)`, which cuts
the **screen file**, whose t=0 is its first frame PTS
(`ScreenRecorder.swift:271`). `startCapture()` returning and the first frame arriving
are not the same instant; on a busy or static display the gap is seconds. Every pause
cut therefore lands late by that gap, and the cut length is right while its position is
wrong — the classic "the wrong part got removed" report.

**K2 — Camera and audio-only modes have no primary-capture anchor at all.**
`primaryCaptureStartUptime` is assigned on exactly one path, the screen path
(`RecorderViewModel.swift:2469`). In camera mode (`:2107`) and audio mode (`:2383`)
`markRecordingStarted` → `beginPauseTracking` falls back to
`ProcessInfo.processInfo.systemUptime` **after every component has finished starting**
(`:1664`). In audio mode the microphone and system audio start serially (`:2355-2371`),
and the system-audio start pays a full `SCShareableContent` enumeration. So the pause
origin can be several seconds later than the microphone file's real t=0, and every
pause cut is displaced by that amount. This is the single most likely source of a
multi-second discrepancy in audio mode.

**K3 — Audio-only export applies no track offsets whatsoever.**
`maybeFinalizeAudioRecordingExport` passes only `pauseTimeline` to the exporter
(`RecorderViewModel.swift:2735-2742`). `RecordingTrackOffsets` is used exclusively by
the screen path (`:2797`). Microphone and system audio are therefore both laid at
composition time zero even though their files started seconds apart (K2's serial
start). Result: the two audio tracks drift against each other by the system-audio
startup cost, and neither is anchored to the session start.

**K4 — On macOS 15+ the screen "zero point" is measured from the wrong object.**
`SCRecordingOutput` owns and writes the file (`ScreenRecorder.swift:151`), but the
reference timestamp fed into `RecordingTrackOffsets` comes from a *second*, plain
`.screen` stream output attached alongside purely to observe timestamps
(`:157`, `:271`, consumed at `RecorderViewModel.swift:2798`). Nothing guarantees the
two agree on which frame is first: the observing output is added after the recording
output, and `didOutputSampleBuffer` accepts any buffer with `numSamples > 0` without
checking `SCStreamFrameInfoStatus` — ScreenCaptureKit's idle/duplicate frames pass that
check. If the observed first sample is an idle frame that `SCRecordingOutput` did not
write, the computed screen zero is **earlier** than the file's real zero, and every
`offset(from:to:)` result (`ScreenCameraOverlayCompositionBuilder.swift:52-57`) is
inflated by that difference — pushing microphone and camera audio later, i.e. removing
the beginning of what the user said. This is the strongest single candidate for the
~10 s head loss in screen mode and must be measured before anything is changed.

**K5 — The stop error: `isStopping` is a latch with no reliable release.**
`ScreenRecorder.stopRecording()` returns immediately when `isStopping` is already true
(`ScreenRecorder.swift:196`). It is cleared only in `resetState()` (`:462`), which runs
only from `complete()` (`:371`) — and `complete()` has two early returns before that
point: a stale-generation guard (`:358`) and `guard let completion else { return }`
(`:362`). Once either fires, `isStopping` stays `true` for the lifetime of this
long-lived recorder instance, so **the next recording can never be stopped**: the user
presses stop, `stopCapture` is never issued, the pending completion never arrives,
`maybeFinalizeScreenRecordingExport` never fires, and the fallback in
`finishMacOS15RecordingIfNeeded` (`:383-405`) times out into
`fallbackStopResult` / an error banner. `SystemAudioRecorder.swift:105` and
`MicrophoneAudioRecorder.swift:188` repeat the identical pattern.

**K6 — In-flight export state is clobbered by the next recording.**
`recordingPauseTimeline` and `primaryCaptureStartUptime` are plain view-model
properties, reset by `beginPauseTracking()` (`:1666-1667`), yet
`maybeFinalizeScreenRecordingExport` reads `recordingPauseTimeline` at finalize time
(`:2791`). Because finalize is driven by async completion callbacks, starting a new
recording before the previous export finishes silently applies the **new** (empty)
pause timeline to the **old** file, or the old timeline to a session that had no
pauses. All per-session state must be captured into a value at stop time, not read from
live properties at finalize time.

**K7 — Up to ~5 s of user-audible "recording" happens before capture exists.**
`playCommandReceivedSoundIfEnabled` (`:2230`) starts the command cue, then
`playStartSoundBeforeCapture` (`:2216`) awaits up to 3.5 s for it plus 1.5 s for the
start cue, all before `startRecording` is issued. Independently,
`markRecordingStarted` (`:2549`) runs only after the whole secondary task group has
come up, so the UI's "Kayıt yapılıyor" is late relative to capture while the audible cue
is early relative to capture. The user's mental model of when recording began is
therefore wrong in both directions, which inflates the perceived size of the real gap.
This is a UX aggravator, not the root cause, and should not be "fixed" first.

**K8 — `stopRecording()` is not gated on lifecycle phase.**
`RecorderViewModel.stopRecording()` (`:2116`) is reachable from the max-duration timer
(`:2171`), the menu bar and the global hotkey without the `isPreparingRecording` guard
that `toggleRecording` applies (`:1615`). Stopping during preparation tears down
components whose completion handlers then fire against half-initialised pending state.

## Onaylanan kararlar

- Per-component files plus export-time alignment is the right architecture; the defect
  is in the time bases, not the design. Do not rewrite toward a single muxed writer.
- `RecordingPauseTimeline`'s own arithmetic (`normalizedRanges`, `segments`,
  `shiftedEarlier`, `outputPosition`) is internally consistent and well covered. It is
  being fed wrong inputs. Do not start by changing this file.
- Keeping capture running through a pause and cutting at export is sound, and is what
  makes the timeline correctness above load-bearing.
- The generation counter in `ScreenRecorder` (`:33`) is the right defence against stale
  callbacks and should be kept — but it must not be able to strand `isStopping`.

## Riskli varsayımlar

- **A1.** That `SCRecordingOutput`'s file starts at the same frame as the observing
  stream output (K4). Unverified. If false, screen-mode offsets are wrong by that
  amount. Verify before designing the fix.
- **A2.** That `CMSampleBufferGetPresentationTimeStamp` from `SCStream`,
  `AVCaptureAudioDataOutput` and `AVCaptureVideoDataOutput` share one host clock. The
  code states this (`ScreenRecording.swift:120-125`) and it is normally true on macOS,
  but it is asserted, never measured.
- **A3.** That the user's ~10 s is a single offset. It may be the sum of K1/K2 and K4
  in different modes. The reproduction must record which mode was used.
- **A4.** That `systemUptime` sampled on the main actor is close to the sample-buffer
  clock. Under main-thread contention during startup the sampling itself is late.
- **A5.** That the reported stop error is one error. It may be `emptyRecording` (K5's
  timeout path) in one attempt and an AVFoundation "Cannot Record" in another; these
  have different causes and `ScreenRecorder.describe` (`:441`) already exists to tell
  them apart.

## Doğrulama listesi

1. Reproduce with the runtime log on, once per mode (screen, camera, audio). Capture the
   exact error text and the `startScreenRecording ... at +N ms` lines (`:2437`).
2. Read the logged `first sample at host time` values
   (`ScreenRecorder.swift:54`, `MicrophoneAudioRecorder.swift:45`) and the
   `Screen recording track offsets (seconds)` line (`RecorderViewModel.swift:2803`).
   Compare the offsets against the observed missing seconds. Equal ⇒ K4/K1 confirmed.
3. `ffprobe -show_streams` the finished file and each surviving temp file: compare
   per-track `start_time` and `duration`. This localises the loss to capture vs.
   composition without guessing.
4. Add a temporary log of the *screen file's* own first-frame PTS read back from disk
   after finalize, and diff it against `firstSamplePresentationTime`. This is the direct
   test of A1 / K4.
5. Reproduce K5 deliberately: start, stop, immediately start again, stop. Confirm the
   second stop is a no-op and that no `stopCapture` log line appears.
6. Pause/resume matrix per mode: pause at 5 s, resume at 10 s, stop at 20 s. The output
   must be 15 s with the 5–10 s content absent. Measure where the seam actually lands.
7. Start a recording while the previous export is still running; verify K6 by checking
   whether the second file's pause seam matches the first session's pauses.

## Önerilen plan düzeltmeleri

1. **Introduce one session clock and stop deriving anything from `systemUptime`.**
   Define the session zero as the screen (or, in audio mode, the microphone) file's
   first-sample PTS, and express pause ranges as
   `CMClockGetTime(CMClockGetHostTimeClock()) - sessionZero` captured at the moment of
   the pause, not as a main-actor `systemUptime` delta. This subsumes K1, K2 and A4 in
   one change.
2. **Make the anchor mandatory, not optional.** Replace
   `primaryCaptureStartUptime ?? now` (`:1664`) with an explicit per-mode primary
   component; if its first sample has not arrived yet, defer the pause origin rather
   than substituting "now". A missing anchor should be an assertion in debug, not a
   silent fallback.
3. **Extend `RecordingTrackOffsets` to the audio-only path** (K3), with the microphone
   as the reference component, and pass it into `audioRecordingExporter.export`.
4. **Settle K4 before changing offsets.** Either read the screen file's real first-frame
   PTS back after finalize and use *that* as the reference, or, on macOS 15+, drop the
   observing stream output and derive the screen zero from the written file. Filter
   non-`.complete` frames in `didOutputSampleBuffer` (`ScreenRecorder.swift:266`) as a
   minimum.
5. **Convert `isStopping` from a latch to a guarded state with an owner** (K5): clear it
   on every exit path of `complete()`, including both early returns, or replace it with
   the existing generation counter. Apply to all three recorders.
6. **Snapshot per-session state at stop time** into a single value type
   (pause timeline, offsets, URLs, mode) and pass it through the completion chain, so
   finalize never reads live view-model properties (K6).
7. **Gate `stopRecording()` on `recordingLifecycle`** the way `toggleRecording` gates
   start (K8).
8. **Tests that would have caught this:** a `RecordingPauseTimeline` test where the
   pause origin is deliberately offset from the file's t=0 (asserting the seam position,
   not just the duration); a `RecordingTrackOffsets` test for the audio-only pairing; and
   a `ScreenRecorder` test that calls `stop → complete(stale) → stop` and asserts the
   second stop still issues `stopCapture`.
9. **Only then** revisit the cue timing (K7): with the clocks correct, decide whether
   the start cue plays before or after capture begins, and make the UI's "recording"
   state change at capture start rather than after the secondary components come up.
