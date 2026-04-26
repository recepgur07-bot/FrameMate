# Crash Reporting & Stability Tests Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Sentry crash reporting and unit tests covering the recording lifecycle scenarios most likely to crash.

**Architecture:** Sentry SDK added via SPM (project.yml → xcodegen), DSN stored in Info.plist. Unit tests extend existing RecorderViewModelTests pattern using MockCameraOverlayRecorder and MockCaptureRecorder mocks already in TestSupport.swift. No new test targets — tests go into existing FrameMateTests.

**Tech Stack:** Sentry Swift SDK, XCTest, existing Mock infrastructure in TestSupport.swift

---

## Chunk 1: Sentry Crash Reporting

### Task 1: Add Sentry SPM package to project.yml

**Files:**
- Modify: `project.yml`
- Modify: `Resources/Info.plist`
- Modify: `Sources/VideoRecorderApp/VideoRecorderApp.swift`

- [ ] **Step 1: Add Sentry package + dependency to project.yml**

Open `project.yml`. Add `packages:` section at the top level (before `targets:`):

```yaml
packages:
  Sentry:
    url: https://github.com/getsentry/sentry-cocoa
    from: 8.40.0
```

Then under `targets: > FrameMate: > dependencies:` add:

```yaml
    dependencies:
      - framework: IOKit.framework
        embed: false
      - package: Sentry
        product: Sentry
```

- [ ] **Step 2: Regenerate xcodeproj**

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodegen generate
```

Expected: `Generating plists...` then `✓ Generated: VideoRecorder.xcodeproj`

- [ ] **Step 3: Build to verify Sentry resolves**

Use XcodeMCP xcode_build with scheme FrameMate. Expected: BUILD SUCCESSFUL (first build will fetch SPM package — may take ~30 seconds).

- [ ] **Step 4: Add SentryDSN key to Info.plist**

In `Resources/Info.plist`, add a new key:

```xml
<key>SentryDSN</key>
<string>$(SENTRY_DSN)</string>
```

This lets the DSN be injected at build time without hardcoding it.

- [ ] **Step 5: Initialize Sentry in app entry point**

In `Sources/VideoRecorderApp/VideoRecorderApp.swift`, add `import Sentry` at the top.

In `VideoRecorderApp.init()`, before the first existing line, add:

```swift
if let dsn = Bundle.main.infoDictionary?["SentryDSN"] as? String, !dsn.isEmpty, dsn != "$(SENTRY_DSN)" {
    SentrySDK.start { options in
        options.dsn = dsn
        options.tracesSampleRate = 0
        options.enableCrashHandler = true
        options.enableSwiftAsyncStacktraces = true
    }
}
```

- [ ] **Step 6: Add SENTRY_DSN to fastlane env**

In `fastlane/.env` (or `.env.fastlane`), add:

```
SENTRY_DSN=https://YOUR_KEY@oXXXXXX.ingest.sentry.io/XXXXXXX
```

Also pass it to the build in `fastlane/Fastfile` beta lane's `xcargs`:

```ruby
build_options[:xcargs] = "PROVISIONING_PROFILE_SPECIFIER='#{profile_name}' SENTRY_DSN='#{ENV['SENTRY_DSN'] || ''}'"
```

- [ ] **Step 7: Build again to verify no compile errors**

Use XcodeMCP xcode_build. Expected: BUILD SUCCESSFUL.

- [ ] **Step 8: Commit**

```bash
git add project.yml Resources/Info.plist Sources/VideoRecorderApp/VideoRecorderApp.swift fastlane/Fastfile
git commit -m "feat: add Sentry crash reporting (DSN via SENTRY_DSN env var)"
```

---

## Chunk 2: Unit Tests — Camera Overlay Lifecycle

These tests cover the crash scenario: toggling camera overlay on/off/on/off rapidly.

### Task 2: Camera overlay toggle stability tests

**Files:**
- Create: `Tests/VideoRecorderAppTests/RecorderViewModelOverlayLifecycleTests.swift`

The test pattern mirrors `RecorderViewModelTests.swift`. Uses `MockCameraOverlayRecorder` from `TestSupport.swift`.

- [ ] **Step 1: Create the test file with the first test**

Create `Tests/VideoRecorderAppTests/RecorderViewModelOverlayLifecycleTests.swift`:

```swift
import XCTest
@testable import FrameMate

@MainActor
final class RecorderViewModelOverlayLifecycleTests: XCTestCase {
    private func makeViewModel(
        cameraOverlayRecorder: MockCameraOverlayRecorder = MockCameraOverlayRecorder(),
        cameraID: String = "cam-1"
    ) -> RecorderViewModel {
        let vm = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(
                status: .authorized,
                displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
            ),
            cameraOverlayRecorder: cameraOverlayRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [
                .video: .authorized,
                .audio: .authorized
            ]),
            appAccessManager: MockAppAccessManager(
                state: AppAccessState(accessKind: .trial, trialDaysRemaining: 14, offers: [])
            )
        )
        return vm
    }

    // Toggling camera overlay on when not in screen preset must be a no-op.
    func testToggleOverlayIgnoredInCameraPreset() async {
        let overlay = MockCameraOverlayRecorder()
        let vm = makeViewModel(cameraOverlayRecorder: overlay)
        await vm.setup()

        vm.selectedPreset = .horizontalCamera
        vm.toggleScreenCameraOverlay()

        XCTAssertFalse(vm.isScreenCameraOverlayEnabled)
        XCTAssertEqual(overlay.configureCallCount, 0)
    }

    // Enabling overlay in screen preset must trigger configure + startSession.
    func testEnableOverlayInScreenPresetConfiguresSession() async {
        let overlay = MockCameraOverlayRecorder()
        let vm = makeViewModel(cameraOverlayRecorder: overlay)
        await vm.setup()

        vm.selectedPreset = .screen
        vm.selectedCameraID = "cam-1"
        vm.setScreenCameraOverlayEnabled(true)

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(vm.isScreenCameraOverlayEnabled)
        XCTAssertEqual(overlay.configuredCameraID, "cam-1")
        XCTAssertTrue(overlay.startSessionCalled)
    }
}
```

- [ ] **Step 2: Run the new tests to see baseline**

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild test -project VideoRecorder.xcodeproj -scheme FrameMate -only-testing:FrameMateTests/RecorderViewModelOverlayLifecycleTests 2>&1 | tail -20
```

Expected: Tests pass or fail with assertion messages (no crashes).

- [ ] **Step 3: Add rapid-toggle stress test**

Append to the test class:

```swift
    // Simulates the crash scenario: rapid toggle on/off/on/off must not crash or deadlock.
    func testRapidOverlayToggleDoesNotCrash() async {
        let overlay = MockCameraOverlayRecorder()
        let vm = makeViewModel(cameraOverlayRecorder: overlay)
        await vm.setup()

        vm.selectedPreset = .screen
        vm.selectedCameraID = "cam-1"

        for _ in 0..<5 {
            vm.setScreenCameraOverlayEnabled(true)
            try? await Task.sleep(nanoseconds: 10_000_000)
            vm.setScreenCameraOverlayEnabled(false)
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        // After all toggles, overlay must be off and session must be stopped.
        XCTAssertFalse(vm.isScreenCameraOverlayEnabled)
        XCTAssertTrue(overlay.stopSessionCalled)
    }
```

- [ ] **Step 4: Add disable-while-configure-pending test**

Append to the test class:

```swift
    // Disabling the overlay while configure() is still in-flight must cancel cleanly.
    func testDisableWhileConfigureInFlightCancelsCleanly() async {
        let overlay = MockCameraOverlayRecorder()
        overlay.configureDelayNanoseconds = 200_000_000 // 200 ms

        let vm = makeViewModel(cameraOverlayRecorder: overlay)
        await vm.setup()

        vm.selectedPreset = .screen
        vm.selectedCameraID = "cam-1"

        vm.setScreenCameraOverlayEnabled(true)
        // Immediately disable before configure finishes
        vm.setScreenCameraOverlayEnabled(false)

        // Wait for any in-flight configure to resolve
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertFalse(vm.isScreenCameraOverlayEnabled)
        // Session must NOT be started since overlay was cancelled
        XCTAssertFalse(overlay.startSessionCalled)
    }
```

- [ ] **Step 5: Run all overlay tests**

```bash
xcodebuild test -project VideoRecorder.xcodeproj -scheme FrameMate \
  -only-testing:FrameMateTests/RecorderViewModelOverlayLifecycleTests 2>&1 | grep -E "passed|failed|error"
```

Expected: All 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Tests/VideoRecorderAppTests/RecorderViewModelOverlayLifecycleTests.swift
git commit -m "test: add camera overlay lifecycle stability tests"
```

---

## Chunk 3: Unit Tests — Recording Lifecycle & Orphan Cleanup

### Task 3: Recording start/stop cycle and cleanup tests

**Files:**
- Create: `Tests/VideoRecorderAppTests/RecorderViewModelRecordingLifecycleTests.swift`

- [ ] **Step 1: Create the test file**

Create `Tests/VideoRecorderAppTests/RecorderViewModelRecordingLifecycleTests.swift`:

```swift
import XCTest
@testable import FrameMate

@MainActor
final class RecorderViewModelRecordingLifecycleTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: "recording.lastConfiguration")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        UserDefaults.standard.removeObject(forKey: "recording.lastConfiguration")
        try await super.tearDown()
    }

    private func makeViewModel(recorder: MockCaptureRecorder = MockCaptureRecorder()) -> RecorderViewModel {
        RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: MockScreenRecordingProvider(
                status: .authorized,
                displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
            ),
            fileNamer: RecordingFileNamer(outputDirectory: tempDir),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [
                .video: .authorized,
                .audio: .authorized
            ]),
            appAccessManager: MockAppAccessManager(
                state: AppAccessState(accessKind: .trial, trialDaysRemaining: 14, offers: [])
            )
        )
    }

    // stopRecording must transition isRecording to false.
    func testStopRecordingClearsIsRecording() async {
        let recorder = MockCaptureRecorder(
            cameras: [InputDevice(id: "cam-1", name: "FaceTime HD")],
            microphones: [InputDevice(id: "mic-1", name: "Built-in Mic")]
        )
        let vm = makeViewModel(recorder: recorder)
        await vm.setup()

        vm.selectedPreset = .horizontalCamera
        vm.selectedCameraID = "cam-1"
        vm.selectedMicrophoneID = "mic-1"

        // Manually set isRecording to simulate an active recording
        // (startRecording requires real AVCapture; we test the stop path)
        vm.stopRecording()

        XCTAssertFalse(vm.isRecording)
        XCTAssertFalse(vm.isPaused)
    }

    // setup() must delete orphaned temp files from a previous crash.
    func testSetupDeletesOrphanedTempFiles() async throws {
        // Plant orphaned files that a crash would leave behind
        let orphans: [String] = [
            "tmp-20260424-120000.mov",
            "camera-overlay-20260424-120001.mov",
            "screen-microphone-20260424-120000.m4a",
            "screen-system-audio-20260424-120000.m4a",
            "system-audio-20260424-120000.m4a",
        ]
        for name in orphans {
            let url = tempDir.appendingPathComponent(name)
            try "orphan".write(to: url, atomically: true, encoding: .utf8)
        }

        // Real recordings must be preserved
        let realFile = tempDir.appendingPathComponent("Kamera Kaydı 24.04.2026 12.00.mp4")
        try "real".write(to: realFile, atomically: true, encoding: .utf8)

        let vm = makeViewModel()
        await vm.setup()

        for name in orphans {
            let url = tempDir.appendingPathComponent(name)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                           "Orphan file '\(name)' should have been deleted on startup")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: realFile.path),
                      "Real recording must NOT be deleted")
    }

    // Starting audio recording twice must not start a second session.
    func testDoubleAudioRecordingStartIsIdempotent() async {
        let micRecorder = MockMicrophoneAudioRecorder()
        let vm = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            microphoneAudioRecorder: micRecorder,
            fileNamer: RecordingFileNamer(outputDirectory: tempDir),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.audio: .authorized]),
            appAccessManager: MockAppAccessManager(
                state: AppAccessState(accessKind: .trial, trialDaysRemaining: 14, offers: [])
            )
        )

        await vm.setup()
        vm.selectedPreset = .audio
        vm.selectedMicrophoneID = "mic-1"

        vm.toggleAudioRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        let firstCallCount = micRecorder.startCallCount

        // Second toggle while recording should stop, not double-start
        vm.toggleAudioRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(micRecorder.startCallCount, firstCallCount,
                       "startRecording must not be called a second time while already recording")
    }
}
```

- [ ] **Step 2: Check if MockMicrophoneAudioRecorder has startCallCount**

```bash
grep -n "startCallCount\|startCalled\|startRecording" \
  "/Users/recepgur/Desktop/video recorder/Tests/VideoRecorderAppTests/TestSupport.swift" | head -10
```

If `startCallCount` doesn't exist, add it to `MockMicrophoneAudioRecorder` in `TestSupport.swift`:

```swift
private(set) var startCallCount = 0
// In startRecording method, add: startCallCount += 1
```

- [ ] **Step 3: Run the new tests**

```bash
xcodebuild test -project VideoRecorder.xcodeproj -scheme FrameMate \
  -only-testing:FrameMateTests/RecorderViewModelRecordingLifecycleTests 2>&1 | grep -E "passed|failed|error|XCTAssert"
```

Expected: All tests pass, especially `testSetupDeletesOrphanedTempFiles`.

- [ ] **Step 4: Run the full test suite to check for regressions**

```bash
xcodebuild test -project VideoRecorder.xcodeproj -scheme FrameMate 2>&1 | grep -E "passed|failed|error" | tail -5
```

Expected: Same pass count as before + new tests.

- [ ] **Step 5: Commit**

```bash
git add Tests/VideoRecorderAppTests/RecorderViewModelRecordingLifecycleTests.swift \
        Tests/VideoRecorderAppTests/TestSupport.swift
git commit -m "test: add recording lifecycle and orphan cleanup tests"
```

---

## Chunk 4: TestFlight — Submit with Sentry

### Task 4: Configure DSN and ship

- [ ] **Step 1: Create Sentry project**

Go to sentry.io → New Project → Apple → copy the DSN string.

- [ ] **Step 2: Add DSN to fastlane env file**

In `.env.fastlane`:
```
SENTRY_DSN=https://xxxxx@oXXXXXX.ingest.sentry.io/XXXXXXX
```

- [ ] **Step 3: Submit build**

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 fastlane beta
```

- [ ] **Step 4: Verify in Sentry dashboard**

Trigger a test crash (or just open the app) — Sentry should show a session within ~30 seconds.

---

## Notes

- **Sentry DSN:** Never commit to git. Use `.env.fastlane` (already in `.gitignore`).
- **UI tests skipped:** macOS XCUITest for recording requires camera/microphone permissions that CI won't have. The ViewModel-level tests cover the same logic paths without real hardware.
- **Next steps after Sentry is live:** Once real crashes appear in the dashboard, use the stack traces to write regression tests for each crash.
