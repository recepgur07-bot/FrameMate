# Pause Resume Recording Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shared `Cmd+Ctrl+P` and main-screen pause/resume control, play `ara.wav` on both transitions, and tighten completion-sheet action coverage.

**Architecture:** Start with a ViewModel-level pause contract and UI/hotkey plumbing, then export through a pause timeline that skips paused source ranges. The public behavior is `isRecording` plus `isPaused`; the final output path must exclude paused intervals by appending only unpaused media ranges.

**Tech Stack:** SwiftUI, AppKit/Carbon global hotkeys, AVFoundation, ScreenCaptureKit, XCTest.

---

## File Structure

- Modify `Sources/VideoRecorderApp/SoundEffectPlayer.swift` to expose a pause/resume transition sound.
- Modify `Sources/VideoRecorderApp/GlobalHotkeyMonitor.swift` to register and match `Cmd+Ctrl+P`.
- Modify `Sources/VideoRecorderApp/RecorderViewModel.swift` to add pause state and transition action.
- Modify `Sources/VideoRecorderApp/ContentView.swift` to add the main-screen pause/resume button.
- Modify `Sources/VideoRecorderApp/VideoRecorderApp.swift` to wire the hotkey and command menu.
- Modify `Sources/VideoRecorderApp/MenuBarController.swift` to show a pause/resume menu item and state.
- Add `Resources/Sounds/ara.wav` from `ses dosyaları/ara.wav`.
- Modify `Tests/VideoRecorderAppTests/GlobalHotkeyMonitorTests.swift`.
- Modify `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`.
- Modify `Tests/VideoRecorderAppTests/MenuBarControllerTests.swift`.

## Chunk 1: Public Pause Contract And Sound

### Task 1: Add failing tests for hotkey and transition sound

- [ ] Add a `GlobalHotkeyMonitorTests` test asserting `pauseResumeToggleDisplay == "Cmd+Ctrl+P"` and a keyDown `p` event with keyCode `35` matches.
- [ ] Add a rejection test for `Cmd+Ctrl+Shift+P`.
- [ ] Add `RecorderViewModelTests` coverage that `togglePauseResume()` does nothing when no recording is active.
- [ ] Add `RecorderViewModelTests` coverage that toggling pause/resume while `isRecording = true` flips `isPaused`, updates `statusText`, and calls the pause sound twice.
- [ ] Run the targeted tests and confirm they fail for missing API.

### Task 2: Implement minimal hotkey, state, and sound support

- [ ] Add `playPauseResume()` to `SoundEffectPlaying` and `SoundEffectPlayer`, using `ara.wav`.
- [ ] Add `pauseResumeToggleDisplay`, keyCode `35`, a new Carbon hotkey ID, `onPauseResumeToggle`, and `matchesPauseResumeToggle(for:)` to `GlobalHotkeyMonitor`.
- [ ] Add `isPaused`, `canPauseRecording`, `pauseResumeButtonTitle`, and `togglePauseResume()` to `RecorderViewModel`.
- [ ] Ensure stop/start paths reset `isPaused`.
- [ ] Run targeted tests and confirm they pass.

## Chunk 2: UI And Menus

### Task 3: Add failing menu/UI tests

- [ ] Add `MenuBarControllerTests` coverage that the menu contains `Duraklat (Cmd+Ctrl+P)` while recording and `Devam Et (Cmd+Ctrl+P)` while paused.
- [ ] Add command/menu state tests where the existing debug surface makes it possible.
- [ ] Run targeted tests and confirm they fail.

### Task 4: Wire UI controls

- [ ] Add a main-screen button near the recording button in `ContentView`.
- [ ] Add app command menu button in `VideoRecorderApp`.
- [ ] Add `onPauseResumeToggle`, paused state, tooltip/status/menu title updates to `MenuBarController`.
- [ ] Wire `GlobalHotkeyMonitor(onPauseResumeToggle:)` in `VideoRecorderApp`.
- [ ] Run targeted tests and confirm they pass.

## Chunk 3: Completion Sheet Regression Check

### Task 5: Add missing action coverage

- [ ] Add a test that `revealCompletedRecording()` uses `completedRecording.url` over stale `lastSavedURL`.
- [ ] Add a test that rename collision leaves `completedRecording` unchanged and sets `errorText`.
- [ ] Add a test that save-as collision leaves `completedRecording` unchanged and sets `errorText`.
- [ ] Run targeted tests and confirm any missing coverage fails.

### Task 6: Implement any missing completion action fixes

- [ ] Keep existing successful action behavior.
- [ ] Ensure failed moves report visible errors without dismissing the sheet.
- [ ] Run targeted tests.

## Chunk 4: Pause Timeline Export Follow-Through

### Task 7: Add segment model tests

- [x] Add a focused model for pause ranges and unpaused export segments.
- [x] Add tests proving pause ranges are removed from output timing.
- [x] Add tests proving overlay shortcut events inside paused ranges are dropped and later events are shifted.

### Task 8: Implement segment export for active recording families

- [x] Extend camera, screen, and audio-only paths to collect pause ranges.
- [x] Update export builders to concatenate unpaused source ranges in order.
- [x] Preserve overlay, microphone, system audio, cursor, keyboard, and auto-reframe timelines relative to active recording time.
- [ ] Run the full test suite.

## Verification

- [ ] Run `xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS'`.
- [ ] Manually verify `Cmd+Ctrl+P` during camera recording, screen recording, and audio-only recording.
- [ ] Manually verify pause gaps are absent from final output and `ara.wav` is not captured.

Because this workspace is not a git repository, skip commit steps and report changed files with citations.
