# macOS Video Recorder Design

## Goal

Build a native macOS video recording app for recording 1080p horizontal or vertical videos with selectable camera and microphone input. The app must support starting and stopping recording from both the UI and the `Cmd+R` keyboard shortcut, play a short sound effect on recording transitions, and save recordings as MP4 files.

## Scope

The first version will provide:

- Camera device selection.
- Microphone device selection.
- 1080p horizontal mode, targeting 1920x1080 output.
- 1080p vertical mode, targeting 1080x1920 output.
- Start and stop recording button.
- `Cmd+R` toggle for start and stop.
- Short system sound effect when recording starts and stops.
- MP4 output in `~/Movies/Video Recorder/` with timestamped filenames.
- Clear text status for accessibility: ready, recording, saved, and error states.

The first version will not include editing, trimming, streaming, filters, cloud upload, or advanced audio processing.

## Platform And Frameworks

Use a native SwiftUI macOS app backed by AVFoundation:

- `SwiftUI` for the app shell and accessible controls.
- `AVFoundation` for camera, microphone, capture session, device discovery, and movie recording.
- `AppKit` only where macOS integration is needed, such as sound playback or file URL helpers.

Target macOS 14 or newer unless the implementation environment requires a different minimum.

## Architecture

Use small, focused units:

- `VideoRecorderApp`: app entry point.
- `ContentView`: accessible UI for device selection, mode selection, status, and recording controls.
- `RecorderViewModel`: observable state coordinator for devices, selected options, recording state, errors, and keyboard-triggered toggle.
- `CaptureRecorder`: AVFoundation service that owns the capture session, input switching, output configuration, and recording lifecycle.
- `RecordingMode`: enum for horizontal and vertical 1080p modes.

The UI should talk to `RecorderViewModel` only. `RecorderViewModel` should talk to `CaptureRecorder`, which isolates AVFoundation details from the SwiftUI layer.

## Recording Flow

On launch:

- Request camera and microphone permission if needed.
- Discover available video and audio devices.
- Select default camera and microphone when available.
- Prepare an AVCapture session for the selected devices and selected recording mode.

When the user starts recording:

- Ensure the output directory exists.
- Generate a timestamped `.mp4` destination URL.
- Start recording through the capture service.
- Play a short start sound.
- Update status to recording.

When the user stops recording:

- Stop recording through the capture service.
- Play a short stop sound.
- Update status to saved when the output callback completes successfully.
- Show a readable error state if recording fails.

## Keyboard Shortcut

Bind `Cmd+R` to the same toggle action as the primary recording button:

- If not recording, start recording.
- If recording, stop recording.

This keeps keyboard and button behavior identical and easier to test.

## MP4 Output

Prefer MP4 output directly when AVFoundation supports it for the selected output path and codec settings. If a macOS API limitation requires recording to `.mov` first, the implementation may record to a temporary `.mov` and transcode to `.mp4` as a second step, but direct MP4 is the preferred first attempt.

Filenames should use a stable timestamp format, for example:

```text
recording-20260407-153012.mp4
```

## Accessibility

The app should not rely on visual preview for core operation. Controls and state should be usable through VoiceOver:

- Device pickers should have clear labels.
- The recording button should expose its current action as either start or stop.
- The status text should announce meaningful state changes.
- The last saved file path should be shown as selectable text.

## Error Handling

Handle these cases with user-readable messages:

- Camera permission denied.
- Microphone permission denied.
- No camera found.
- No microphone found.
- Selected device becomes unavailable.
- Recording cannot start.
- MP4 output cannot be created.
- Save directory cannot be created.

## Testing

Verify manually on macOS with:

- App launches and lists available camera and microphone devices.
- Horizontal mode records a playable 1920x1080 MP4.
- Vertical mode records a playable 1080x1920 MP4 or applies the closest supported device format plus correct output orientation.
- UI button starts and stops recording.
- `Cmd+R` starts and stops recording.
- Sound effect plays on start and stop.
- Output file appears in `~/Movies/Video Recorder/`.
- VoiceOver can identify the main controls and status text.

If automated tests are added, prioritize pure Swift tests for filename generation, mode mapping, and view-model state transitions.
