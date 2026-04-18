# Spatial Frame Coach Audio Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional spatial audio guidance layer to Frame Coach without changing the existing spoken guidance behavior.

**Architecture:** Keep speech and VoiceOver output in `SpeechCuePlayer`, and add a separate spatial cue path for non-speech tones. A deterministic resolver converts `FrameAnalysis` and current guidance into a structured cue, then a cue player handles pan, pitch, cooldown, and center confirmation.

**Tech Stack:** Swift, SwiftUI, AVFoundation, UserDefaults, XCTest.

---

## File Structure

- Create: `Sources/VideoRecorderApp/FrameCoach/FrameCoachSpatialCue.swift`
  - Holds spatial mode, cue direction, severity, style, and cue value types.

- Create: `Sources/VideoRecorderApp/FrameCoach/FrameCoachSpatialCueResolver.swift`
  - Converts analysis and guidance into an optional spatial cue.

- Create: `Sources/VideoRecorderApp/FrameCoach/SpatialCoachCuePlayer.swift`
  - Owns AVFoundation tone playback and non-speech cooldown.

- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`
  - Add spatial settings, persistence, dependencies, and call the resolver/player in the Frame Coach analysis path.

- Modify: `Sources/VideoRecorderApp/ContentView.swift`
  - Add settings controls under `Erişilebilirlik ve Yönlendirme`.

- Modify: `Sources/VideoRecorderApp/Localizable.xcstrings`
  - Add user-facing strings.

- Modify: `VideoRecorder.xcodeproj/project.pbxproj`
  - Add new Swift files to the target.

- Test: `Tests/VideoRecorderAppTests/FrameCoachSpatialCueResolverTests.swift`
  - Unit tests for cue decision logic.

- Test: `Tests/VideoRecorderAppTests/RecorderViewModelFrameCoachTests.swift`
  - Integration tests for settings and player invocation.

## Chunk 1: Model And Resolver

### Task 1: Add spatial cue value types

**Files:**
- Create: `Sources/VideoRecorderApp/FrameCoach/FrameCoachSpatialCue.swift`
- Test: `Tests/VideoRecorderAppTests/FrameCoachSpatialCueResolverTests.swift`

- [ ] **Step 1: Write failing tests for basic directions**

Add tests proving the resolver can return left, right, up, down, centered, and nil.

Run:

```bash
xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' -only-testing:VideoRecorderAppTests/FrameCoachSpatialCueResolverTests
```

Expected: fail because the test file or types do not exist yet.

- [ ] **Step 2: Add value types**

Create:

```swift
enum FrameCoachSpatialAudioMode: String, CaseIterable, Identifiable {
    case off
    case tonesOnly
    case tonesAndSpeech

    var id: String { rawValue }
}

enum FrameCoachSpatialDirection: Equatable {
    case left
    case right
    case up
    case down
    case center
}

enum FrameCoachSpatialSeverity: Equatable {
    case mild
    case strong
}

struct FrameCoachSpatialCue: Equatable {
    var direction: FrameCoachSpatialDirection
    var severity: FrameCoachSpatialSeverity
    var confirmsCentered: Bool
}
```

- [ ] **Step 3: Add resolver skeleton**

Create `FrameCoachSpatialCueResolver` with:

```swift
struct FrameCoachSpatialCueResolver {
    func cue(for analysis: FrameAnalysis?, guidance: String) -> FrameCoachSpatialCue? {
        nil
    }
}
```

- [ ] **Step 4: Run tests and confirm expected failures**

Run the same `xcodebuild test` command.

Expected: tests fail because resolver returns `nil`.

### Task 2: Implement resolver rules

**Files:**
- Modify: `Sources/VideoRecorderApp/FrameCoach/FrameCoachSpatialCueResolver.swift`
- Test: `Tests/VideoRecorderAppTests/FrameCoachSpatialCueResolverTests.swift`

- [ ] **Step 1: Implement guidance-keyed resolver behavior**

Use the final spoken guidance as the first-release source of truth:

- contains `sağa`: `.right`
- contains `sola`: `.left`
- contains `yukarı`: `.up`
- contains `aşağı`: `.down`
- equals `kadraj uygun` or `kadraj dengeli`: `.center`
- contains `algılanamıyor`, `ışık düşük`, `izin`: `nil`

Keep this small and explicit. Do not re-implement all frame coach thresholds.

- [ ] **Step 2: Add severity**

Use `.strong` for clipped, too close, too far, missing edge, or large movement phrases. Use `.mild` for simple `biraz ...` guidance.

- [ ] **Step 3: Run resolver tests**

Run:

```bash
xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' -only-testing:VideoRecorderAppTests/FrameCoachSpatialCueResolverTests
```

Expected: pass.

## Chunk 2: Settings And Persistence

### Task 3: Add settings state

**Files:**
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelFrameCoachTests.swift`

- [ ] **Step 1: Write failing persistence tests**

Add tests for default spatial mode and UserDefaults persistence.

Expected defaults:

- spatial mode: `.off`
- center confirmation: `true`

- [ ] **Step 2: Extend `FrameCoachPreferences`**

Add:

```swift
var spatialAudioMode: FrameCoachSpatialAudioMode
var playsCenterConfirmation: Bool
```

Default:

```swift
spatialAudioMode: .off
playsCenterConfirmation: true
```

- [ ] **Step 3: Extend `FrameCoachSettingsStoring`**

Add:

```swift
var spatialAudioMode: FrameCoachSpatialAudioMode { get set }
var playsCenterConfirmation: Bool { get set }
```

- [ ] **Step 4: Extend `UserDefaultsFrameCoachSettingsStore`**

Add keys:

```swift
frameCoach.spatialAudioMode
frameCoach.playsCenterConfirmation
```

- [ ] **Step 5: Add view model bindable properties**

Add properties similar to `frameCoachSpeechMode` and `showsFrameCoachTextOnScreen`.

- [ ] **Step 6: Run focused tests**

Run:

```bash
xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' -only-testing:VideoRecorderAppTests/RecorderViewModelFrameCoachTests
```

Expected: pass.

### Task 4: Add settings UI

**Files:**
- Modify: `Sources/VideoRecorderApp/ContentView.swift`
- Modify: `Sources/VideoRecorderApp/Localizable.xcstrings`

- [ ] **Step 1: Add spatial mode labels**

Add localized labels:

- `Kapalı`
- `Sadece yön sesi`
- `Yön sesi ve konuşma`

- [ ] **Step 2: Add Settings controls**

Under `Erişilebilirlik ve Yönlendirme`, add:

```swift
Picker("Yön sesi", selection: $viewModel.frameCoachSpatialAudioMode) {
    ForEach(FrameCoachSpatialAudioMode.allCases) { mode in
        Text(mode.label).tag(mode)
    }
}

Toggle("Merkez onayı çal", isOn: $viewModel.playsFrameCoachCenterConfirmation)
```

- [ ] **Step 3: Ensure the center toggle disables when spatial mode is off**

Use `.disabled(viewModel.frameCoachSpatialAudioMode == .off)`.

- [ ] **Step 4: Build**

Run:

```bash
xcodebuild build -scheme VideoRecorderApp -destination 'platform=macOS'
```

Expected: build succeeds.

## Chunk 3: Cue Playback

### Task 5: Add player protocol and mockable implementation

**Files:**
- Create: `Sources/VideoRecorderApp/FrameCoach/SpatialCoachCuePlayer.swift`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelFrameCoachTests.swift`

- [ ] **Step 1: Write failing integration test**

Test that when Frame Coach is enabled and spatial mode is `.tonesOnly`, a left/right guidance result calls the spatial cue player once.

- [ ] **Step 2: Add protocol**

```swift
protocol SpatialCuePlaying: AnyObject {
    func play(_ cue: FrameCoachSpatialCue, preferences: FrameCoachPreferences)
    func reset()
}
```

- [ ] **Step 3: Add no-op implementation for wiring**

Start with a no-op player so wiring can be tested before real audio.

- [ ] **Step 4: Inject into `RecorderViewModel`**

Add dependencies:

```swift
private let spatialCueResolver: FrameCoachSpatialCueResolver
private let spatialCuePlayer: any SpatialCuePlaying
```

Use defaults in initializers.

- [ ] **Step 5: Call resolver/player in `processCaptureCoachAnalysis`**

After final `guidance` is chosen and before or after speech output, call:

```swift
if frameCoachSpatialAudioMode != .off,
   let cue = spatialCueResolver.cue(for: analysis, guidance: guidance) {
    spatialCuePlayer.play(cue, preferences: frameCoachPreferences)
}
```

For `.tonesOnly`, suppress speech for ordinary guidance but keep essential state announcements like coach on/off and permission problems.

- [ ] **Step 6: Run focused tests**

Run:

```bash
xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' -only-testing:VideoRecorderAppTests/RecorderViewModelFrameCoachTests
```

Expected: pass.

### Task 6: Implement generated tone playback

**Files:**
- Modify: `Sources/VideoRecorderApp/FrameCoach/SpatialCoachCuePlayer.swift`

- [ ] **Step 1: Add AVFoundation engine**

Use `AVAudioEngine`, `AVAudioSourceNode`, or short generated `AVAudioPCMBuffer` playback.

First-release tone targets:

- left/right: 660 Hz
- up: 880 Hz
- down: 440 Hz
- center: 700 Hz two short pulses
- duration: 90-140 ms

- [ ] **Step 2: Add stereo pan**

Use pan values:

- left: `-0.85`
- right: `0.85`
- up/down: `0`
- center: `0`

If using `AVAudioPlayerNode`, set pan on the player node before scheduling the buffer.

- [ ] **Step 3: Add cooldown**

Prevent cue spam:

- same direction minimum interval: 0.6 seconds
- center confirmation minimum interval: 2 seconds

- [ ] **Step 4: Reset on coach toggle**

Call `spatialCuePlayer.reset()` next to `speechCuePlayer.reset()`.

- [ ] **Step 5: Manual sound check**

Run the app, enable Frame Coach, enable `Yön sesi`, and verify:

- left guidance sounds left
- right guidance sounds right
- center confirmation sounds centered
- turning spatial audio off silences tones

## Chunk 4: Regression And Release Checks

### Task 7: Full verification

**Files:**
- No new files unless fixes are needed.

- [ ] **Step 1: Run Frame Coach test suite**

Run:

```bash
xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' -only-testing:VideoRecorderAppTests/FrameCoachingEngineTests -only-testing:VideoRecorderAppTests/RecorderViewModelFrameCoachTests -only-testing:VideoRecorderAppTests/FrameCoachSpatialCueResolverTests
```

Expected: pass.

- [ ] **Step 2: Run full app tests**

Run:

```bash
xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS'
```

Expected: pass.

- [ ] **Step 3: Manual VoiceOver check**

With VoiceOver running:

- existing VoiceOver announcements still work
- spatial tones can be enabled independently
- tones do not make the spoken guidance unusable

- [ ] **Step 4: Manual recording check**

Confirm coach sounds are not mixed into exported recordings unless the app already captures system audio by user choice. If system audio capture is on, document that macOS may capture app-generated sounds as part of system audio.

- [ ] **Step 5: Commit**

Only after the other expert's work is merged or stabilized:

```bash
git add Sources/VideoRecorderApp/FrameCoach/FrameCoachSpatialCue.swift \
  Sources/VideoRecorderApp/FrameCoach/FrameCoachSpatialCueResolver.swift \
  Sources/VideoRecorderApp/FrameCoach/SpatialCoachCuePlayer.swift \
  Sources/VideoRecorderApp/RecorderViewModel.swift \
  Sources/VideoRecorderApp/ContentView.swift \
  Sources/VideoRecorderApp/Localizable.xcstrings \
  Tests/VideoRecorderAppTests/FrameCoachSpatialCueResolverTests.swift \
  Tests/VideoRecorderAppTests/RecorderViewModelFrameCoachTests.swift \
  VideoRecorder.xcodeproj/project.pbxproj

git commit -m "feat: add spatial frame coach audio"
```

## Implementation Notes

- Do not modify `FrameCoachingEngine` thresholds for this feature unless a test proves it is necessary.
- Keep spatial audio off by default.
- Keep speech behavior unchanged when spatial audio is off.
- Favor generated tones first. Add bundled WAV assets only if generated audio feels poor in manual testing.
- Avoid playing multiple cues for one analysis frame.
- Be careful with `tonesOnly`: state announcements such as "Kadraj koçu açık", "Kadraj koçu kapalı", missing permissions, and countdown should remain spoken unless product direction explicitly changes.
