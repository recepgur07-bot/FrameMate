# Handoff — recording lifecycle & timing fix

Approved by the user on 2026-07-27. Source of the decision:
`docs/ai-work/gorus/kayit-yasam-dongusu/sentez.md` (synthesis of three independent
reviews: `01-claude.md`, `02-codex.md`, `03-antigravity.md`).

Implementer: single agent. Coordinator: Claude.

## Goal

One session clock for a recording, applied identically in all three modes
(screen/window, camera, audio-only); a lifecycle that always returns to `.idle`;
per-session state frozen at stop time.

## Non-goals (do not touch)

- The start/stop/pause **sound cue** timing and `playStartSoundBeforeCapture`. Out of
  scope; a separate task.
- Rewriting toward a single muxed writer. The per-component-file + export-time
  alignment architecture is correct and stays.
- `RecordingPauseTimeline`'s internal arithmetic (`normalizedRanges`, `segments`,
  `shiftedEarlier`, `outputPosition`, `outputDuration`). It is correct; it is fed wrong
  inputs. Add to it only if a phase below explicitly says so.
- UI/layout, localization strings beyond what a change forces, App Store metadata.

## Ground rules

- **There is no `Package.swift`. This is an Xcode-only project.** The scheme is
  `FrameMate` (targets: `FrameMate`, `FrameMateTests`, `FrameMateProjectTests`).
  Build:
  `xcodebuild -project VideoRecorder.xcodeproj -scheme FrameMate -configuration Debug build 2>&1 | tail -25`
  Test:
  `xcodebuild -project VideoRecorder.xcodeproj -scheme FrameMate test 2>&1 | tail -60`
  The build is **green as of 2026-07-27**; if it is red, that is your change.
- **New `.swift` files are not picked up automatically** — this project does not use
  Xcode 16 synchronized groups. Prefer adding new types to a file already in the target
  (e.g. put `RecordingSessionClock` in `RecordingPauseTimeline.swift`). If a new file is
  genuinely warranted, register it in `VideoRecorder.xcodeproj/project.pbxproj` by
  copying the four-entry pattern used for `RecordingTrackAlignmentTests.swift`
  (PBXBuildFile, PBXFileReference, group `children`, Sources build phase) and prove it
  compiled.
- Run the tests after **every** phase. Do not start a phase with a red build.
- Keep the existing comment style: comments explain *why*, in full sentences, only where
  the reason is non-obvious. Match surrounding code. Do not add banner comments or
  restate what the code says.
- Turkish user-facing strings stay Turkish and keep using `String(localized:)`.
- Do not commit. Do not push. Leave the work in the working tree.
- Append one short, evidence-linked line per phase to
  `docs/ai-work/tasks/kayit-zamanlama-duzeltmesi/seyir-defteri.md` (create it) — what
  changed, which test proves it. No prose essays.

## Phase 1 — Lifecycle can never get stuck (do this first)

This is the deterministic part of the user's "press stop → error" report. Three
independent defects, all real:

1.1 `ScreenRecorder.stopRecording()` guards on `isStopping`
(`Sources/VideoRecorderApp/ScreenRecorder.swift:196`) but `isStopping` is cleared only in
`resetState()` (`:462`), reached only from `complete()` (`:371`). `complete()` has two
early returns before that: the stale-generation guard (`:358`) and
`guard let completion else { return }` (`:362`). Once either fires the latch is stuck
for the lifetime of this long-lived instance and **the next recording can never be
stopped**. Fix: clear `isStopping` on every exit path of `complete()` (a `defer` at the
top of `complete()` is not enough because the early returns must also clear it — write it
explicitly). Apply the identical fix to `SystemAudioRecorder.swift:105` and
`MicrophoneAudioRecorder.swift:188`.

1.2 `maybeFinalizeScreenRecordingExport` (`RecorderViewModel.swift:2768`) returns early
when any component result is still `nil`, and `finishRecordingLifecycle()` (`:2808`) sits
below those guards. If a component's completion never arrives, the phase stays
`.stopping` forever and `beginPreparing()` (`RecordingLifecycleState.swift:18`) rejects
every later start. Fix: add a **stop watchdog** — when `stopRecording()` runs, start a
task that after a bounded wait (use 15 s; the screen fallback in
`finishMacOS15RecordingIfNeeded` already takes up to ~6 s) forces any still-`nil` pending
component result to a `.success(nil)` with a warning, then re-enters the finalize path.
The watchdog must be cancelled when finalize completes normally. Same treatment for
`maybeFinalizeAudioRecordingExport` and the camera path
(`completeCameraRecordingIfReady`, `:2591`).

1.3 Audio-only with **no microphone and system audio disabled**: both pending results are
pre-set to `.success(nil)` at start (`:2342-2345`), `stopRecording()` then stops nothing
(`:2120-2126`), no completion ever fires, finalize is never called, phase stays
`.stopping`. Fix: reject this configuration in `ensureSelectedRecordingCanStart()` /
`validateRecordingReadiness` with a clear Turkish error, **and** make `stopRecording()`
call the finalize path directly when there is no component left to wait for.

1.4 Gate `stopRecording()` (`:2116`) on the lifecycle: if
`recordingLifecycle.beginStopping()` returns `false`, return without repeating component
teardown. `markRecordingStopping()` (`:2313`) currently discards that return value.

**Phase 1 tests** (in `Tests/VideoRecorderAppTests/`):
- `ScreenRecorder`: `stop` → a stale-generation `complete` → `stop` again must still
  issue the stop path (assert via the fake/observable seam that already exists).
- ViewModel: start → stop where one fake component never calls its completion → after the
  watchdog fires, `recordingLifecycle.phase == .idle` and a new recording can start.
- ViewModel: audio-only with no mic and system audio off is rejected at start.

## Phase 2 — One session clock

Today pause ranges are `ProcessInfo.systemUptime` deltas
(`RecorderViewModel.swift:1704`, `:1713`) measured from
`primaryCaptureStartUptime` — the moment `SCStream.startCapture()` *returned*
(`:2469`) — while the cut is applied to a file whose t=0 is its first sample PTS
(`ScreenRecorder.swift:271`). Worse, `primaryCaptureStartUptime` is assigned **only** on
the screen path; camera (`:2107`) and audio-only (`:2383`) fall back to
`ProcessInfo.processInfo.systemUptime` at `beginPauseTracking()` (`:1664`), i.e. after
every component has finished starting.

2.1 Add `Sources/VideoRecorderApp/RecordingSessionClock.swift`:

```swift
/// The single time base a recording session is expressed in.
///
/// Every component writes its own file and each file's t=0 is that component's first
/// sample. Session time is defined by the *primary* component's first sample, and every
/// pause range and track offset is derived from it, so that one recording is never
/// described by two different clocks.
struct RecordingSessionClock: Equatable {
    let sessionZero: CMTime          // host-clock PTS of the primary component's first sample
    func sessionSeconds(at hostTime: CMTime) -> TimeInterval
    static func now() -> CMTime      // CMClockGetTime(CMClockGetHostTimeClock())
}
```

2.2 Primary component per mode: screen/window → `screenRecordingProvider`;
camera → `recorder` (`CaptureRecording`); audio-only → `microphoneAudioRecorder`, or
`systemAudioRecorder` when there is no microphone.

2.3 `CaptureRecording` (`CaptureRecorder.swift:6`) has no
`firstSamplePresentationTime`. Add it, mirroring `ScreenRecordingProviding`
(`ScreenRecording.swift:125`) — protocol requirement with a `nil` default extension so
existing fakes keep compiling. `CaptureRecorder` uses `AVCaptureMovieFileOutput`, so
record the host time in `fileOutput(_:didStartRecordingTo:...)`, the same approach
`CameraOverlayRecorder.swift:171` already takes.

2.4 Replace `recordingStartUptime` / `primaryCaptureStartUptime` /
`currentPauseStartOffset` with session-clock equivalents:
`beginCurrentPauseRange()` and `finishCurrentPauseRange()` (`:1702-1718`) record
`RecordingSessionClock.now()` and convert to session seconds through the clock.
`beginPauseTracking()` (`:1658`) must **not** fall back to "now". If the primary
component's first sample has not arrived yet, hold the pause origin as pending and
resolve it when the first sample lands; pausing before the first sample arrives must be
either blocked or recorded as a pause starting at session time 0.

2.5 `currentRecordingDuration` and the UI elapsed timer may keep using `systemUptime` —
that is display-only and must not feed the pause timeline. Keep them separate and say so
in a comment.

**Phase 2 tests**: given a fake primary whose first sample lands 10 s after
`startRecording` returns, a pause taken at wall-time +20 s must produce a pause range
starting at session time 10 s, not 20 s. This is the test that would have caught the
original bug — write it first and watch it fail.

## Phase 3 — Same offset handling in all three modes

`RecordingTrackOffsets` (`ScreenCameraOverlayCompositionBuilder.swift:27-58`) and the
`shiftedEarlier` + `outputPosition` placement in `insertComponentSegments`
(`:303-340`) are correct and are the model to follow. They are used **only** by the
screen path (`RecorderViewModel.swift:2797`).

3.1 Audio-only: `AudioRecordingExporting.export` (`RecorderViewModel.swift:48-57`) takes
no offsets, and `addAudioTracks` (`:121`) lays microphone and system audio both at zero.
Add an offsets parameter and apply the same per-asset translation the screen builder
uses: cut in the asset's own local time via `pauseTimeline.shiftedEarlier(by: offset)`,
then place at `pauseTimeline.outputPosition(of: offset)`. Reference component = the
primary from 2.2.

3.2 Camera: `makeCameraExportAsset` (`:2990`) applies the raw `pauseTimeline` to both the
camera movie and the separately recorded system-audio file, even though system audio is
started *before* the camera (`:2084-2098`). Give it the same treatment.

3.3 Factor the shared "cut in local time, place at output position" logic out of
`ScreenCameraOverlayCompositionBuilder` so all three call sites use one implementation.
Do not duplicate it three times.

**Phase 3 tests**: Codex's fixture, run for all three modes — primary first PTS = 100 s,
secondary = 110 s, session pause = [20, 25]. The secondary's local cut must be [10, 15]
and its output placement 10 s.

## Phase 4 — Harden the screen reference (measure, don't guess)

On macOS 15+ `SCRecordingOutput` writes the file (`ScreenRecorder.swift:151`) but the
reference timestamp comes from a second, observing `.screen` stream output added
alongside it (`:157`, `:271`). All three reviews flagged that these may disagree.

4.1 `didOutputSampleBuffer` (`:266`) accepts any buffer with `numSamples > 0`.
ScreenCaptureKit's idle/duplicate frames pass that check. Read
`SCStreamFrameInfoStatus` from the buffer's attachments and only record the first sample
whose status is `.complete`.

4.2 After the screen file is finalized, load its real first-frame PTS from disk and log
the difference against the observed `firstSamplePresentationTime`. Do **not** silently
correct with it in this phase — log it. This is the measurement that tells the user
whether a residual offset remains, and it is what has been missing from every previous
attempt.

## Phase 5 — Session generation

`recordingPauseTimeline` and the `pending*` properties are live view-model state read at
finalize time (`:2791`), while finalize is driven by async callbacks. Starting a new
recording before the previous export completes applies the wrong timeline, and old export
tasks unconditionally write `lastSavedURL`, `completedRecording`, `statusText`,
`errorText` (`:2642-2663`, `:2749-2763`, `:2849-2858`).

5.1 Add a monotonic `recordingGeneration` to the view model, incremented on each start.
5.2 Capture everything a finalize/export needs into one immutable value at stop time
(pause timeline, offsets, URLs, mode, warnings, generation) and pass it through the
completion chain. Finalize must not read live properties.
5.3 Export tasks carry their generation and only write UI state when it still matches.

**Phase 5 test**: an old export completion at generation N must not modify
`lastSavedURL` / `completedRecording` / `statusText` / `errorText` while generation N+1
is active.

## Phase 6 — Instrumentation

Make the residual measurable on the user's own machine via `runtimeDebugLog`, one line
each, at finalize: session zero, each component's first-sample host time, each computed
offset, each pause range in session time, and the finalized screen file's real first
frame PTS from 4.2. Keep it to a handful of lines — this is diagnostic output the user
will read, not a trace.

## Definition of done

- `swift build` and `swift test` both clean.
- Every phase's named test exists and passes; the Phase 2 test demonstrably fails against
  the old logic.
- `seyir-defteri.md` has one line per phase.
- A final summary in Turkish listing: what changed per phase, which of the six synthesis
  findings (A–F) each addresses, what was measured vs. what is still assumed, and what is
  left for the user to verify on a real recording.

## Report back

If a phase turns out to be wrong or blocked, complete every other phase in full and say
explicitly which one you left out and why. Do not silently narrow the scope.
