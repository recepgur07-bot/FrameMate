# Video Recorder

Native macOS SwiftUI video recorder with selectable camera and microphone inputs, 1080p horizontal and vertical modes, `Cmd+R` start/stop toggle, sound effects, and MP4 output.

## Build

```bash
swift build
```

## Test

```bash
swift test
```

## Create The App Bundle

```bash
bash scripts/package-app.sh
```

The packaged app is created at:

```text
build/VideoRecorder.app
```

Open it from Finder or with:

```bash
open build/VideoRecorder.app
```

macOS should ask for camera and microphone permission on first use.

## Use

- Choose a camera from the `Kamera` picker.
- Choose a microphone from the `Mikrofon` picker.
- Choose `1080p Yatay` or `1080p Dikey`.
- Press `Kaydı Başlat`, or press `Cmd+R`, to start recording.
- Press `Kaydı Durdur`, or press `Cmd+R`, to stop recording.
- Recordings are saved under `~/Movies/Video Recorder/` as timestamped `.mp4` files.

## Accessibility

The core workflow is usable without relying on the video preview. Camera, microphone, mode, recording action, status text, and last saved path are exposed as text controls for VoiceOver and keyboard use.

## Known Limits

This first version uses AVFoundation movie recording with an `.mp4` destination URL. If a specific camera or macOS setup refuses direct MP4 output, the next fallback is to record a temporary `.mov` file and transcode to `.mp4`.
