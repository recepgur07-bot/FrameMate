# Recording Scenario Tests Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add comprehensive lifecycle scenario tests for audio, camera, and screen recording modes covering start/stop, pause/resume cycles, and completedRecording state integrity.

**Architecture:** New test class `RecordingLifecycleTests` appended to `RecorderViewModelTests.swift` so it can reuse the private mocks already defined there (`RecorderCaptureStub`, `MockSoundEffectPlayer`, `MockAudioRecordingExporter`, `RecorderPermissionsStub`).

**Tech Stack:** XCTest, `@MainActor`, `@testable import FrameMate`, existing mock infrastructure in `RecorderViewModelTests.swift`

---

## Chunk 1: Audio recording lifecycle scenarios

**Files:**
- Modify: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift` (append new class at end)

### Task 1: Audio start → stop sets completedRecording

- [ ] **Step 1: Append new class skeleton**

```swift
// MARK: - Recording lifecycle scenarios
@MainActor
final class RecordingLifecycleTests: XCTestCase {
    private func makeAudioViewModel(
        microphoneRecorder: MockMicrophoneAudioRecorder = MockMicrophoneAudioRecorder(),
        systemAudioRecorder: MockSystemAudioRecorder = MockSystemAudioRecorder(),
        audioExporter: MockAudioRecordingExporter = MockAudioRecordingExporter()
    ) -> (RecorderViewModel, MockMicrophoneAudioRecorder, MockSystemAudioRecorder, MockAudioRecordingExporter) {
        let permissions = RecorderPermissionsStub(statuses: [.audio: .authorized])
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let vm = RecorderViewModel(
            recorder: RecorderCaptureStub(cameras: [], microphones: [InputDevice(id: "mic-1", name: "USB Mic")]),
            screenRecordingProvider: MockScreenRecordingProvider(),
            systemAudioRecorder: systemAudioRecorder,
            microphoneAudioRecorder: microphoneRecorder,
            audioRecordingExporter: audioExporter,
            fileNamer: RecordingFileNamer(homeDirectory: tempRoot),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )
        return (vm, microphoneRecorder, systemAudioRecorder, audioExporter)
    }
}
```

- [ ] **Step 2: Run tests to verify class compiles (no test methods yet)**

Run: `xcodebuild test -scheme FrameMate -destination 'platform=macOS' -only-testing:VideoRecorderAppTests/RecordingLifecycleTests 2>&1 | tail -20`
Expected: BUILD SUCCEEDED (no test methods run yet)

### Task 2: Audio start → stop

- [ ] **Step 1: Write failing test**

```swift
func testAudioStartStop_setsCompletedRecording() async {
    let (vm, mic, _, _) = makeAudioViewModel()
    await vm.setup()
    vm.selectPreset(.audioOnly)
    vm.refreshDeviceState()

    vm.startRecording()
    for _ in 0..<20 where !vm.isRecording { try? await Task.sleep(nanoseconds: 25_000_000) }

    XCTAssertTrue(vm.isRecording)
    XCTAssertFalse(vm.isPaused)
    XCTAssertNil(vm.completedRecording)

    vm.stopRecording()
    try? await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertFalse(vm.isRecording)
    XCTAssertFalse(vm.isPaused)
    XCTAssertNotNil(vm.completedRecording)
    XCTAssertEqual(vm.completedRecording?.fileExtension, "m4a")
}
```

- [ ] **Step 2: Run test**

Run: `xcodebuild test -scheme FrameMate -destination 'platform=macOS' -only-testing:VideoRecorderAppTests/RecordingLifecycleTests/testAudioStartStop_setsCompletedRecording 2>&1 | tail -20`
Expected: PASS

### Task 3: Audio start → pause → stop

- [ ] **Step 1: Write test**

```swift
func testAudioStartPauseStop_setsCompletedRecording() async {
    let (vm, _, _, _) = makeAudioViewModel()
    await vm.setup()
    vm.selectPreset(.audioOnly)
    vm.refreshDeviceState()

    vm.startRecording()
    for _ in 0..<20 where !vm.isRecording { try? await Task.sleep(nanoseconds: 25_000_000) }

    vm.togglePauseResume()
    XCTAssertTrue(vm.isPaused)

    vm.stopRecording()
    try? await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertFalse(vm.isRecording)
    XCTAssertFalse(vm.isPaused)
    XCTAssertNotNil(vm.completedRecording)
}
```

- [ ] **Step 2: Run test**

Expected: PASS

### Task 4: Audio start → pause → resume → stop

- [ ] **Step 1: Write test**

```swift
func testAudioStartPauseResumeStop_setsCompletedRecording() async {
    let (vm, _, _, _) = makeAudioViewModel()
    await vm.setup()
    vm.selectPreset(.audioOnly)
    vm.refreshDeviceState()

    vm.startRecording()
    for _ in 0..<20 where !vm.isRecording { try? await Task.sleep(nanoseconds: 25_000_000) }

    vm.togglePauseResume()
    XCTAssertTrue(vm.isPaused)

    vm.togglePauseResume()
    try? await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertFalse(vm.isPaused)
    XCTAssertTrue(vm.isRecording)

    vm.stopRecording()
    try? await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertFalse(vm.isRecording)
    XCTAssertNotNil(vm.completedRecording)
}
```

- [ ] **Step 2: Run test**

Expected: PASS

### Task 5: Audio multi-cycle pause/resume → stop

- [ ] **Step 1: Write test**

```swift
func testAudioMultiCyclePauseResume_setsCompletedRecording() async {
    let (vm, _, _, _) = makeAudioViewModel()
    await vm.setup()
    vm.selectPreset(.audioOnly)
    vm.refreshDeviceState()

    vm.startRecording()
    for _ in 0..<20 where !vm.isRecording { try? await Task.sleep(nanoseconds: 25_000_000) }

    for _ in 0..<3 {
        vm.togglePauseResume()
        XCTAssertTrue(vm.isPaused)
        vm.togglePauseResume()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(vm.isPaused)
    }

    vm.stopRecording()
    try? await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertFalse(vm.isRecording)
    XCTAssertFalse(vm.isPaused)
    XCTAssertNotNil(vm.completedRecording)
}
```

- [ ] **Step 2: Run test**

Expected: PASS

### Task 6: completedRecording is nil before and during recording

- [ ] **Step 1: Write test**

```swift
func testAudioCompletedRecordingIsNilBeforeAndDuringRecording() async {
    let (vm, _, _, _) = makeAudioViewModel()
    await vm.setup()
    vm.selectPreset(.audioOnly)
    vm.refreshDeviceState()

    XCTAssertNil(vm.completedRecording, "Should be nil before recording starts")

    vm.startRecording()
    for _ in 0..<20 where !vm.isRecording { try? await Task.sleep(nanoseconds: 25_000_000) }

    XCTAssertNil(vm.completedRecording, "Should be nil while recording is active")
}
```

- [ ] **Step 2: Run test**

Expected: PASS

### Task 7: Second audio start clears previous completedRecording

- [ ] **Step 1: Write test**

```swift
func testAudioSecondStart_clearsPreviousCompletedRecording() async {
    let (vm, _, _, _) = makeAudioViewModel()
    await vm.setup()
    vm.selectPreset(.audioOnly)
    vm.refreshDeviceState()

    vm.startRecording()
    for _ in 0..<20 where !vm.isRecording { try? await Task.sleep(nanoseconds: 25_000_000) }
    vm.stopRecording()
    try? await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertNotNil(vm.completedRecording)
    let firstRecording = vm.completedRecording

    vm.startRecording()
    for _ in 0..<20 where !vm.isRecording { try? await Task.sleep(nanoseconds: 25_000_000) }

    XCTAssertNil(vm.completedRecording, "Should be cleared when new recording starts")
}
```

- [ ] **Step 2: Run test**

Expected: PASS

### Task 8: Commit audio tests

- [ ] **Step 1: Commit**

```bash
git add Tests/VideoRecorderAppTests/RecorderViewModelTests.swift
git commit -m "test: add audio recording lifecycle scenario tests"
```

---

## Chunk 2: Camera recording lifecycle scenarios

### Task 9: Camera helper + start → stop

- [ ] **Step 1: Write helper and test**

```swift
private func makeCameraViewModel(
    recorder: RecorderCaptureStub? = nil
) -> (RecorderViewModel, RecorderCaptureStub) {
    let stub = recorder ?? RecorderCaptureStub(
        cameras: [InputDevice(id: "cam-1", name: "FaceTime HD")],
        microphones: [InputDevice(id: "mic-1", name: "Built-in Mic")]
    )
    let permissions = RecorderPermissionsStub(statuses: [.video: .authorized, .audio: .authorized])
    let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let vm = RecorderViewModel(
        recorder: stub,
        screenRecordingProvider: MockScreenRecordingProvider(),
        fileNamer: RecordingFileNamer(homeDirectory: tempRoot),
        soundEffectPlayer: MockSoundEffectPlayer(),
        permissionProvider: permissions
    )
    return (vm, stub)
}

func testCameraStartStop_setsCompletedRecording() async {
    let (vm, stub) = makeCameraViewModel()
    await vm.setup()
    vm.selectPreset(.horizontalCamera)
    vm.selectedCameraID = "cam-1"
    vm.refreshDeviceState()

    vm.startRecording()
    for _ in 0..<20 where !vm.isRecording { try? await Task.sleep(nanoseconds: 25_000_000) }

    XCTAssertTrue(vm.isRecording)
    XCTAssertNil(vm.completedRecording)

    vm.stopRecording()
    try? await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertFalse(vm.isRecording)
    XCTAssertNotNil(vm.completedRecording)
}
```

- [ ] **Step 2: Run test**

Expected: PASS

### Task 10: Camera start → pause → stop

- [ ] **Step 1: Write test**

```swift
func testCameraStartPauseStop_setsCompletedRecording() async {
    let (vm, _) = makeCameraViewModel()
    await vm.setup()
    vm.selectPreset(.horizontalCamera)
    vm.selectedCameraID = "cam-1"
    vm.refreshDeviceState()

    vm.startRecording()
    for _ in 0..<20 where !vm.isRecording { try? await Task.sleep(nanoseconds: 25_000_000) }

    vm.togglePauseResume()
    XCTAssertTrue(vm.isPaused)

    vm.stopRecording()
    try? await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertFalse(vm.isRecording)
    XCTAssertFalse(vm.isPaused)
    XCTAssertNotNil(vm.completedRecording)
}
```

- [ ] **Step 2: Run test**

Expected: PASS

### Task 11: Camera start → pause → resume → stop

- [ ] **Step 1: Write test**

```swift
func testCameraStartPauseResumeStop_setsCompletedRecording() async {
    let (vm, _) = makeCameraViewModel()
    await vm.setup()
    vm.selectPreset(.horizontalCamera)
    vm.selectedCameraID = "cam-1"
    vm.refreshDeviceState()

    vm.startRecording()
    for _ in 0..<20 where !vm.isRecording { try? await Task.sleep(nanoseconds: 25_000_000) }

    vm.togglePauseResume()
    XCTAssertTrue(vm.isPaused)

    vm.togglePauseResume()
    try? await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertFalse(vm.isPaused)
    XCTAssertTrue(vm.isRecording)

    vm.stopRecording()
    try? await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertFalse(vm.isRecording)
    XCTAssertNotNil(vm.completedRecording)
}
```

- [ ] **Step 2: Run test**

Expected: PASS

### Task 12: Camera multi-cycle pause/resume → stop

- [ ] **Step 1: Write test**

```swift
func testCameraMultiCyclePauseResume_setsCompletedRecording() async {
    let (vm, _) = makeCameraViewModel()
    await vm.setup()
    vm.selectPreset(.horizontalCamera)
    vm.selectedCameraID = "cam-1"
    vm.refreshDeviceState()

    vm.startRecording()
    for _ in 0..<20 where !vm.isRecording { try? await Task.sleep(nanoseconds: 25_000_000) }

    for _ in 0..<3 {
        vm.togglePauseResume()
        XCTAssertTrue(vm.isPaused)
        vm.togglePauseResume()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(vm.isPaused)
    }

    vm.stopRecording()
    try? await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertFalse(vm.isRecording)
    XCTAssertFalse(vm.isPaused)
    XCTAssertNotNil(vm.completedRecording)
}
```

- [ ] **Step 2: Run test**

Expected: PASS

### Task 13: Commit camera tests

- [ ] **Step 1: Commit**

```bash
git add Tests/VideoRecorderAppTests/RecorderViewModelTests.swift
git commit -m "test: add camera recording lifecycle scenario tests"
```

---

## Chunk 3: Screen recording lifecycle scenarios

### Task 14: Screen helper + start → stop

- [ ] **Step 1: Write helper and test**

```swift
private func makeScreenViewModel(
    screenProvider: MockScreenRecordingProvider? = nil
) -> (RecorderViewModel, MockScreenRecordingProvider) {
    let provider = screenProvider ?? MockScreenRecordingProvider(
        status: .authorized,
        displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
    )
    provider.shouldCompleteOnStop = true
    let permissions = RecorderPermissionsStub(statuses: [.video: .authorized, .audio: .authorized])
    let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let vm = RecorderViewModel(
        recorder: RecorderCaptureStub(),
        screenRecordingProvider: provider,
        fileNamer: RecordingFileNamer(homeDirectory: tempRoot),
        soundEffectPlayer: MockSoundEffectPlayer(),
        permissionProvider: permissions
    )
    return (vm, provider)
}

func testScreenStartStop_setsCompletedRecording() async {
    let (vm, provider) = makeScreenViewModel()
    await vm.setup()
    vm.selectPreset(.horizontalScreen)
    vm.selectScreenCaptureSource(.screen)
    await vm.refreshScreenRecordingOptions()
    vm.refreshDeviceState()

    vm.startRecording()
    for _ in 0..<20 where !vm.isRecording { try? await Task.sleep(nanoseconds: 25_000_000) }

    XCTAssertTrue(vm.isRecording)

    vm.stopRecording()
    try? await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertFalse(vm.isRecording)
    XCTAssertNotNil(vm.completedRecording)
}
```

- [ ] **Step 2: Run test**

Expected: PASS

### Task 15: Screen start → pause → resume → stop

- [ ] **Step 1: Write test**

```swift
func testScreenStartPauseResumeStop_setsCompletedRecording() async {
    let (vm, _) = makeScreenViewModel()
    await vm.setup()
    vm.selectPreset(.horizontalScreen)
    vm.selectScreenCaptureSource(.screen)
    await vm.refreshScreenRecordingOptions()
    vm.refreshDeviceState()

    vm.startRecording()
    for _ in 0..<20 where !vm.isRecording { try? await Task.sleep(nanoseconds: 25_000_000) }

    vm.togglePauseResume()
    XCTAssertTrue(vm.isPaused)

    vm.togglePauseResume()
    try? await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertFalse(vm.isPaused)

    vm.stopRecording()
    try? await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertFalse(vm.isRecording)
    XCTAssertNotNil(vm.completedRecording)
}
```

- [ ] **Step 2: Run test**

Expected: PASS

---

## Chunk 4: State integrity and guard tests

### Task 16: State after stop is fully reset

- [ ] **Step 1: Write test**

```swift
func testStateFullyResetAfterAudioStop() async {
    let (vm, _, _, _) = makeAudioViewModel()
    await vm.setup()
    vm.selectPreset(.audioOnly)
    vm.refreshDeviceState()

    vm.startRecording()
    for _ in 0..<20 where !vm.isRecording { try? await Task.sleep(nanoseconds: 25_000_000) }
    vm.togglePauseResume()
    vm.stopRecording()
    try? await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertFalse(vm.isRecording)
    XCTAssertFalse(vm.isPaused)
    XCTAssertFalse(vm.isPreparingRecording)
    XCTAssertFalse(vm.isCountingDown)
}
```

- [ ] **Step 2: Run test**

Expected: PASS

### Task 17: toggleAudioRecording ignored when camera recording is active

- [ ] **Step 1: Write test**

```swift
func testAudioToggleIsGuardedWhenCameraRecordingIsActive() async {
    let (vm, cameraStub) = makeCameraViewModel()
    let micRecorder = MockMicrophoneAudioRecorder()
    await vm.setup()
    vm.selectPreset(.horizontalCamera)
    vm.selectedCameraID = "cam-1"
    vm.refreshDeviceState()

    vm.startRecording()
    for _ in 0..<20 where !vm.isRecording { try? await Task.sleep(nanoseconds: 25_000_000) }
    XCTAssertTrue(vm.isRecording)
    XCTAssertEqual(vm.selectedRecordingSource, .camera)

    vm.toggleAudioRecording()
    try? await Task.sleep(nanoseconds: 50_000_000)

    // Camera recording should still be the active mode; audio should not have started
    XCTAssertEqual(vm.selectedRecordingSource, .camera)
    XCTAssertTrue(vm.isRecording)
}
```

- [ ] **Step 2: Run test**

Expected: PASS

### Task 18: Commit state tests

- [ ] **Step 1: Commit**

```bash
git add Tests/VideoRecorderAppTests/RecorderViewModelTests.swift
git commit -m "test: add recording state integrity and guard scenario tests"
```

### Task 19: Run full suite

- [ ] **Step 1: Run all tests**

Run: `xcodebuild test -scheme FrameMate -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All tests PASS
