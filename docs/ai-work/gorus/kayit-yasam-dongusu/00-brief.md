# Opinion request — recording lifecycle & A/V timing

Session: `kayit-yasam-dongusu` · Coordinator: Claude · Targets: Codex, Claude, Antigravity
Type: read-only review. No code changes until the user approves a `handoff.md`.

## Reported symptoms (user, macOS app "video recorder")

1. Press start, press stop → an error is shown.
2. Recording starts, but the finished file is missing roughly the **first ~10 seconds**.
   If the user speaks for a minute, the saved file begins ~10 s in.
3. Start / pause / resume / finish need detailed scrutiny — for **all three recording
   modes** (screen/window, camera, audio-only).
4. Previous fix attempts have been going in circles; the cause is not yet identified.

## Scope

- `Sources/VideoRecorderApp/RecorderViewModel.swift`
  (`toggleRecording`, `togglePauseResume`, `beginPauseTracking`,
  `beginCurrentPauseRange`, `finishCurrentPauseRange`, `startRecordingAsync`,
  `startAudioRecording`, `startScreenRecording`, `stopRecording`,
  `maybeFinalizeScreenRecordingExport`, `maybeFinalizeAudioRecordingExport`,
  `handle*Completion`)
- `ScreenRecorder.swift`, `MicrophoneAudioRecorder.swift`, `SystemAudioRecorder.swift`,
  `CameraOverlayRecorder.swift`, `CaptureRecorder.swift`
- `RecordingPauseTimeline.swift`, `ScreenCameraOverlayCompositionBuilder.swift`
  (`RecordingTrackOffsets`), `RecordingAudioMixBuilder.swift`,
  `RecordingLifecycleState.swift`

## Architecture facts a reviewer needs

- Every component writes its **own file**: screen (`SCRecordingOutput` on macOS 15+,
  else `AVAssetWriter`), camera overlay, microphone, system audio. Each file's t=0 is
  **that component's first sample**, not a shared session zero.
- Alignment is done at export time by `RecordingTrackOffsets.make(...)`, comparing
  `firstSamplePresentationTime` of each recorder against the screen's.
- Pause is **not** a capture-level pause. Capture keeps running; paused stretches are
  cut out at export via `RecordingPauseTimeline`, whose ranges are measured as
  `ProcessInfo.systemUptime - recordingStartUptime`.
- `recordingStartUptime` is set in `beginPauseTracking()` from
  `primaryCaptureStartUptime` (the moment `SCStream.startCapture()` **returned**),
  falling back to "now" when that is nil.
- Start cues: `playCommandReceivedSoundIfEnabled` + `playStartSoundBeforeCapture`
  can delay the actual capture start by up to ~5 s before anything is captured.

## Questions each reviewer must answer

- Q1. Exactly where does the missing head of the recording come from? Name the clock
  mismatch, not a general theory.
- Q2. Which specific call path produces the stop error, and which state flag stays
  stuck afterwards?
- Q3. Are pause ranges expressed in the same time base as the file they cut? Prove it
  per mode (screen, camera, audio).
- Q4. What breaks when start or stop is pressed twice, or a new recording begins while
  the previous export is still running?
- Q5. Minimal, testable fix — preferably one shared time base — and the unit test that
  would have caught the bug.

## Output rules

Each tool writes **only** its own file in this folder:
`01-claude.md`, `02-codex.md`, `03-antigravity.md`. Coordinator writes `sentez.md`.
Use the mandatory headings, in order, each non-empty:
Sonuç / Kritik bulgular / Onaylanan kararlar / Riskli varsayımlar /
Doğrulama listesi / Önerilen plan düzeltmeleri.
Cite `file.swift:line` for every finding. Do not edit another tool's file.
