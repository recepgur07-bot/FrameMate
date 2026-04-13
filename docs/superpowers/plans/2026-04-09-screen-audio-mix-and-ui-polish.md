# Screen Audio Mix And UI Polish Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make screen and window recordings support real separate microphone/system-audio mixing while simplifying the screen-mode UI for better VoiceOver usability.

**Architecture:** Record screen video and system audio through `ScreenRecorder`, record microphone audio through a dedicated `MicrophoneAudioRecorder`, and merge them during export with `RecordingAudioMixBuilder`. Reorganize screen-mode controls in `ContentView` behind clearer view-model flags so only relevant settings appear.

**Tech Stack:** SwiftUI, AVFoundation, ScreenCaptureKit, XCTest, XcodeGen

---

## Chunk 1: Separate Screen Microphone Capture

### Task 1: Add failing tests for separate screen microphone capture

**Files:**
- Modify: `/Users/recepgur/Desktop/video recorder/Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`
- Modify: `/Users/recepgur/Desktop/video recorder/Tests/VideoRecorderAppTests/TestSupport.swift`

- [ ] Add tests showing screen recording starts a dedicated microphone recorder when a microphone is selected.
- [ ] Add tests showing `ScreenRecordingProviding` receives an empty microphone device ID in screen modes.
- [ ] Run the targeted tests and confirm they fail for the right reason.

### Task 2: Implement microphone-only recorder and screen flow

**Files:**
- Create: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/MicrophoneAudioRecorder.swift`
- Modify: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/RecorderViewModel.swift`
- Modify: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/ScreenRecorder.swift`

- [ ] Add a dedicated microphone audio recording protocol and implementation.
- [ ] Inject the recorder into `RecorderViewModel`.
- [ ] Start/stop it in screen modes only when a microphone is selected.
- [ ] Ensure `ScreenRecorder` no longer embeds microphone capture in screen recordings.
- [ ] Re-run targeted tests until green.

## Chunk 2: Real Screen Export Audio Mix

### Task 3: Add failing tests for screen export audio mix

**Files:**
- Modify: `/Users/recepgur/Desktop/video recorder/Tests/VideoRecorderAppTests/ScreenCameraOverlayCompositionBuilderTests.swift`

- [ ] Add tests for screen export audio mix generation with separate microphone/system volumes.
- [ ] Verify the test fails before implementation.

### Task 4: Implement screen export mix support

**Files:**
- Modify: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/ScreenCameraOverlayCompositionBuilder.swift`
- Modify: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/RecorderViewModel.swift`

- [ ] Extend the screen composition builder to accept an optional microphone asset and build an audio mix.
- [ ] Pass screen and microphone track IDs into `RecordingAudioMixBuilder`.
- [ ] Wire the returned audio mix into the export session for screen mode.
- [ ] Re-run targeted tests until green.

## Chunk 3: Screen UI Simplification

### Task 5: Add failing tests for screen UI state flags

**Files:**
- Modify: `/Users/recepgur/Desktop/video recorder/Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] Add tests for new screen-mode visibility/state helpers.
- [ ] Verify they fail before implementation.

### Task 6: Implement grouped screen controls

**Files:**
- Modify: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/RecorderViewModel.swift`
- Modify: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/ContentView.swift`

- [ ] Add view-model helpers for screen audio and overlay sections.
- [ ] Group screen-mode controls into `Kaynak`, `Ses`, and `Kamera Kutusu`.
- [ ] Hide microphone slider when no microphone is selected.
- [ ] Keep camera-mode behavior intact.
- [ ] Re-run targeted tests until green.

## Chunk 4: Verification

### Task 7: Regenerate project and run full verification

**Files:**
- Modify if needed: `/Users/recepgur/Desktop/video recorder/project.yml`

- [ ] Run `xcodegen generate`.
- [ ] Run `xcodebuild build -project '/Users/recepgur/Desktop/video recorder/VideoRecorder.xcodeproj' -scheme VideoRecorderApp -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.
- [ ] Run `xcodebuild test -project '/Users/recepgur/Desktop/video recorder/VideoRecorder.xcodeproj' -scheme VideoRecorderApp -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.
- [ ] If anything fails, fix the issue and re-run before finishing.
