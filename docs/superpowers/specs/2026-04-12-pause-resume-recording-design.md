# Pause Resume Recording Design

## Goal

Add a shared pause/resume control for active video or audio recordings. Pressing `Cmd+Ctrl+P` pauses the active recording; pressing it again resumes. The final MP4 or M4A must not contain the paused interval, so a viewer or listener cannot tell that recording was paused.

The same behavior must be available from the main app screen and app/menu-bar controls. The transition sound `ara.wav` plays when pausing and when resuming, but the sound must not be captured into the final recording.

## Recommended Approach

Use a pause timeline during the active recording. Pausing records the current offset; resuming closes that paused range. Stopping the recording exports the captured media by inserting only the unpaused source ranges into the final MP4 or M4A.

This keeps the paused interval out of the final file and gives one consistent model for camera, screen, microphone-only audio, system audio, overlays, cursor highlights, keyboard shortcut overlays, and auto-reframe keyframes without restarting every capture engine.

## UI And Hotkeys

Add `Cmd+Ctrl+P` to `GlobalHotkeyMonitor`. The hotkey is ignored when no recording is active or while a recording is preparing/stopping.

Add a main-screen button next to the existing start/stop control:

- `Duraklat` while an active recording is running
- `Devam Et` while recording is paused

Add matching app command and menu-bar entries. The status text should use `Kayıt duraklatıldı` for video/screen recordings and `Ses kaydı duraklatıldı` for audio-only recordings.

## Recording Model

`RecorderViewModel` owns the state:

- `isRecording`: there is an active logical recording session
- `isPaused`: the logical session is currently paused
- `togglePauseResume()`: pauses or resumes the current session

The implementation adds state, hotkey, button, menu entries, transition sound, and export-time pause removal behind focused tests so every recording family shares the same public UI contract.

## Completion Sheet Checks

Regression tests should cover the completion sheet actions:

- opening uses the completed recording URL
- revealing uses the completed recording URL
- renaming updates the completed recording and last saved URL
- save-as uses the edited name and reports file-move failures visibly

When an action fails because a file is missing or a destination conflicts, keep the sheet open and show the existing error/status text instead of silently doing nothing.

## Testing

Add tests for:

- `Cmd+Ctrl+P` matching and rejecting extra modifiers
- `togglePauseResume()` ignored with no recording
- pause/resume state and status text while audio/video recording
- pause/resume transition sound playback
- UI/menu labels switching between pause and resume
- reveal/open completion actions using `completedRecording.url`

Because this workspace is not a git repository, no design commit is made.
