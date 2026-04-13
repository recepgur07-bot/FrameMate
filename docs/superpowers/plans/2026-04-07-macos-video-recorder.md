# macOS Video Recorder Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS SwiftUI app that records MP4 video from selectable camera and microphone devices in 1080p horizontal or vertical modes.

**Architecture:** Create a small Swift Package-based macOS app with focused files for UI, view-model state, recording modes, file naming, sound playback, and AVFoundation capture. Keep SwiftUI dependent on a `RecorderViewModel`, and keep AVFoundation details isolated in `CaptureRecorder`.

**Tech Stack:** Swift 5.9+, SwiftUI, AVFoundation, AppKit, XCTest, macOS 14+.

---

## File Structure

- Create: `Package.swift` for the Swift package, executable app target, and test target.
- Create: `Sources/VideoRecorderApp/VideoRecorderApp.swift` for the app entry point and command binding.
- Create: `Sources/VideoRecorderApp/ContentView.swift` for the accessible UI.
- Create: `Sources/VideoRecorderApp/RecorderViewModel.swift` for observable app state and user actions.
- Create: `Sources/VideoRecorderApp/CaptureRecorder.swift` for AVFoundation device discovery, session setup, and recording.
- Create: `Sources/VideoRecorderApp/RecordingMode.swift` for 1080p horizontal and vertical mode definitions.
- Create: `Sources/VideoRecorderApp/RecordingFileNamer.swift` for output directory and timestamped MP4 filenames.
- Create: `Sources/VideoRecorderApp/SoundEffectPlayer.swift` for start/stop system sounds.
- Create: `Sources/VideoRecorderApp/VideoPreviewView.swift` for optional camera preview that is not required for VoiceOver operation.
- Create: `Tests/VideoRecorderAppTests/RecordingModeTests.swift` for mode dimensions and labels.
- Create: `Tests/VideoRecorderAppTests/RecordingFileNamerTests.swift` for deterministic file naming.

## Chunk 1: Project Skeleton And Pure Tests

### Task 1: Create Swift Package Skeleton

**Files:**
- Create: `Package.swift`
- Create: `Sources/VideoRecorderApp/VideoRecorderApp.swift`
- Create: `Sources/VideoRecorderApp/ContentView.swift`
- Create: `Tests/VideoRecorderAppTests/RecordingModeTests.swift`

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VideoRecorder",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VideoRecorder", targets: ["VideoRecorderApp"])
    ],
    targets: [
        .executableTarget(name: "VideoRecorderApp"),
        .testTarget(name: "VideoRecorderAppTests", dependencies: ["VideoRecorderApp"])
    ]
)
```

- [ ] **Step 2: Add minimal SwiftUI app and placeholder UI**

Create `VideoRecorderApp.swift` with `@main struct VideoRecorderApp: App`.

Create `ContentView.swift` with a simple `Text("Video Recorder")`.

- [ ] **Step 3: Run build**

Run: `swift build`

Expected: package builds successfully.

- [ ] **Step 4: Add first failing mode test**

Create `RecordingModeTests.swift` with tests expecting horizontal dimensions `1920x1080`, vertical dimensions `1080x1920`, and Turkish-accessible labels.

Expected before implementation: FAIL because `RecordingMode` does not exist.

### Task 2: Implement Recording Mode

**Files:**
- Create: `Sources/VideoRecorderApp/RecordingMode.swift`
- Modify: `Tests/VideoRecorderAppTests/RecordingModeTests.swift`

- [ ] **Step 1: Add `RecordingMode` enum**

Implement:

```swift
enum RecordingMode: String, CaseIterable, Identifiable {
    case horizontal1080p
    case vertical1080p

    var id: String { rawValue }
    var label: String { ... }
    var width: Int32 { ... }
    var height: Int32 { ... }
}
```

- [ ] **Step 2: Run tests**

Run: `swift test`

Expected: `RecordingModeTests` pass.

### Task 3: Add File Naming Helper

**Files:**
- Create: `Sources/VideoRecorderApp/RecordingFileNamer.swift`
- Create: `Tests/VideoRecorderAppTests/RecordingFileNamerTests.swift`

- [ ] **Step 1: Write failing filename tests**

Test that a fixed date creates a `.mp4` filename like `recording-20260407-153012.mp4`.

Test that the output directory defaults to `Movies/Video Recorder`.

- [ ] **Step 2: Implement `RecordingFileNamer`**

Implement a small type that accepts a base movies directory and date, creates deterministic MP4 URLs, and exposes the default output directory.

- [ ] **Step 3: Run tests**

Run: `swift test`

Expected: all pure tests pass.

## Chunk 2: Recording Service

### Task 4: Add Sound Effect Player

**Files:**
- Create: `Sources/VideoRecorderApp/SoundEffectPlayer.swift`

- [ ] **Step 1: Implement small sound helper**

Use `NSSound(named:)?.play()` with two methods:

```swift
func playStart()
func playStop()
```

Use built-in macOS sounds so no asset files are required.

- [ ] **Step 2: Build**

Run: `swift build`

Expected: build succeeds.

### Task 5: Add Capture Recorder Skeleton

**Files:**
- Create: `Sources/VideoRecorderApp/CaptureRecorder.swift`

- [ ] **Step 1: Implement device model**

Create an `InputDevice` struct with `id` and `name` so SwiftUI can list devices without depending directly on `AVCaptureDevice`.

- [ ] **Step 2: Implement device discovery**

Use `AVCaptureDevice.DiscoverySession` for video devices and `AVCaptureDevice.DiscoverySession` or default audio device discovery for microphones.

- [ ] **Step 3: Implement permission checks**

Expose async methods or completion-based helpers to request video and audio access.

- [ ] **Step 4: Build**

Run: `swift build`

Expected: build succeeds.

### Task 6: Implement Capture Session And MP4 Recording

**Files:**
- Modify: `Sources/VideoRecorderApp/CaptureRecorder.swift`

- [ ] **Step 1: Add session state**

Add `AVCaptureSession`, `AVCaptureMovieFileOutput`, selected video/audio inputs, and delegate handling.

- [ ] **Step 2: Configure selected devices**

Implement a method like:

```swift
func configure(videoDeviceID: String, audioDeviceID: String, mode: RecordingMode) throws
```

It should remove existing inputs, add the selected camera and microphone, set a high-quality preset, and prepare movie output.

- [ ] **Step 3: Start recording**

Implement:

```swift
func startRecording(to url: URL) throws
```

Prefer direct `.mp4` URL output. If direct MP4 fails during verification, add a fallback task to record `.mov` and convert to `.mp4`.

- [ ] **Step 4: Stop recording**

Implement:

```swift
func stopRecording()
```

Report completion through a closure or delegate callback to the view model.

- [ ] **Step 5: Build**

Run: `swift build`

Expected: build succeeds.

## Chunk 3: View Model And UI

### Task 7: Add Recorder View Model

**Files:**
- Create: `Sources/VideoRecorderApp/RecorderViewModel.swift`

- [ ] **Step 1: Define observable state**

Include cameras, microphones, selected IDs, selected recording mode, `isRecording`, status text, last saved URL, and error text.

- [ ] **Step 2: Implement launch setup**

Request permissions, load devices, choose defaults, and configure the recorder.

- [ ] **Step 3: Implement toggle recording**

If idle, create output URL, configure recorder, play start sound, and start recording.

If recording, stop recording and play stop sound.

- [ ] **Step 4: Build**

Run: `swift build`

Expected: build succeeds.

### Task 8: Build Accessible SwiftUI Interface

**Files:**
- Modify: `Sources/VideoRecorderApp/ContentView.swift`
- Modify: `Sources/VideoRecorderApp/VideoRecorderApp.swift`
- Create: `Sources/VideoRecorderApp/VideoPreviewView.swift`

- [ ] **Step 1: Add controls**

Add pickers for camera, microphone, and recording mode. Add a primary button whose label changes between `Kaydı Başlat` and `Kaydı Durdur`.

- [ ] **Step 2: Add status text**

Show status and last saved file path as selectable text.

- [ ] **Step 3: Add optional preview**

Create `VideoPreviewView` with `NSViewRepresentable` and `AVCaptureVideoPreviewLayer`, but keep core operation usable without the preview.

- [ ] **Step 4: Add `Cmd+R` command**

Add a command in `VideoRecorderApp.swift` that calls the same `toggleRecording()` action as the button.

- [ ] **Step 5: Build**

Run: `swift build`

Expected: build succeeds.

## Chunk 4: Verification And Polish

### Task 9: Manual Runtime Verification

**Files:**
- No planned file changes unless verification finds bugs.

- [ ] **Step 1: Run unit tests**

Run: `swift test`

Expected: all tests pass.

- [ ] **Step 2: Run app**

Run: `swift run VideoRecorder`

Expected: app launches.

- [ ] **Step 3: Verify permissions and devices**

Expected: macOS prompts for camera and microphone access if needed, then lists available devices.

- [ ] **Step 4: Verify recording**

Record one horizontal clip and one vertical clip.

Expected: playable `.mp4` files appear under `~/Movies/Video Recorder/`.

- [ ] **Step 5: Verify shortcut and sound**

Press `Cmd+R` to start and stop recording.

Expected: the shortcut toggles recording and a sound plays on each transition.

- [ ] **Step 6: Verify accessibility basics**

Use VoiceOver or keyboard navigation.

Expected: controls have meaningful labels, and status changes are readable as text.

### Task 10: Document Known Limits

**Files:**
- Create: `README.md`

- [ ] **Step 1: Add usage instructions**

Document how to build, run, grant permissions, choose camera/microphone, toggle with `Cmd+R`, and find output files.

- [ ] **Step 2: Add MP4 fallback note if needed**

If direct MP4 recording fails on the local macOS setup, document the fallback behavior and implementation choice.

- [ ] **Step 3: Final verification**

Run: `swift test && swift build`

Expected: tests pass and build succeeds.
