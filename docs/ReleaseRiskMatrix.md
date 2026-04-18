# FrameMate Release Risk Matrix

This checklist turns crash, freeze, and stuck-recording risks into repeatable
release gates. Run it before App Store submission and after changes touching
recording, permissions, shortcuts, settings, export, or accessibility.

## Automated Gates

- `xcodebuild test -project VideoRecorder.xcodeproj -scheme FrameMate -destination 'platform=macOS'`
- `xcodebuild build -project VideoRecorder.xcodeproj -scheme FrameMate -destination 'platform=macOS'`

## Risk Classes

| Risk class | Examples | Current safeguards | Manual release check |
| --- | --- | --- | --- |
| Permission mismatch | Screen, camera, microphone, accessibility denied or restart required | Permission preflight tests, onboarding tests, permission hub tests | Fresh install with each permission denied, then granted |
| Stuck preparation | Start fails while camera overlay, system audio, or microphone was partially started | Start-error tests, `isPreparingRecording` reset checks | Force start then deny/remove a device if possible |
| Stuck stopping | Stop waits forever because one capture branch was not stopped | Screen/audio/system-audio stop tests, overlay stop tests | Start each recording type, stop immediately, confirm UI returns |
| Mid-recording setting drift | User changes mode, source, camera box, or countdown while capture is active | Settings are locked while recording, preparing, or counting down | Try changing source/overlay while recording and during countdown |
| Shortcut race | Global shortcut starts without permissions, double-starts, or cancels wrong flow | Shortcut, countdown, direct-start guard tests | Use Cmd+Ctrl+R, Cmd+Ctrl+5, Cmd+Ctrl+P repeatedly |
| Export failure | Empty screen file, missing overlay/audio, collision on rename/save-as | Empty-file fallback, save/rename collision tests, export completion tests | Record short screen/camera/audio clips and open saved files |
| Optional input absence | No camera, no mic, no windows, no displays, listing failure | Readiness and fallback tests | Launch with no external devices, switch all modes |
| Accessibility conflict | App voice speaks over VoiceOver, status cannot be understood | VoiceOver announcement tests, accessibility summary tests | Turn VoiceOver on, use status and record shortcuts |
| Trial/paywall lock | Expired trial allows capture, active trial blocks capture | App access and paywall preflight tests | Test trial, expired, and restored purchase states |
| App lifecycle | Window closes during recording, menu bar state gets stale | main-window and menu tests | Close main window while recording, stop from menu bar |

## Manual Smoke Matrix

Run each row once with countdown off and once with a 3-second countdown.

| Mode | Options | Start path | Expected result |
| --- | --- | --- | --- |
| Camera | Mic on, system audio off | Main button and Cmd+Ctrl+R | Starts, stops, saves MP4 |
| Camera | System audio on | Main button | Shows clear guidance if unsupported or records expected audio |
| Screen | Full screen, mic off, system audio off | Main button and Cmd+Ctrl+R | Starts, stops, saves MP4 |
| Screen | Full screen, mic on, system audio on | Main button | Starts, stops, saves MP4 with audio |
| Screen | Camera box on | Main button | Overlay starts and stop returns UI to ready |
| Screen | Camera box on, then try to disable while recording | Main button | Setting does not change until recording stops |
| Window | Window selected, mic on | Main button | Starts target window and stops cleanly |
| Audio only | Mic on | Cmd+Ctrl+5 | Countdown applies, starts, stops, saves M4A |
| Audio only | Mic off, system audio on | Cmd+Ctrl+5 | Starts only if screen permission is valid |
| Any active recording | Pause/resume | Cmd+Ctrl+P | Pause state changes without losing final export |

## Red Flags

- UI remains on "Kayıt hazırlanıyor" or "Kayıt durduruluyor" for more than a few seconds.
- Stop button does nothing, or a second start is allowed while the first start is still preparing.
- Changing a setting during recording changes the active stop/export path.
- A permission-denied state starts a countdown or capture anyway.
- VoiceOver is running but FrameMate speaks status using its own voice.
- A saved recording summary appears but the output file is missing or zero bytes.

## Release Decision

- Ship when all automated gates pass and the manual smoke matrix has no red flags.
- If a red flag appears, add or update an automated regression test before fixing it.
- If the issue depends on real macOS services and cannot be unit-tested, add it to this matrix and document the manual check.
