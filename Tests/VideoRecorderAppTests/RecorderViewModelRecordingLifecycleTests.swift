import CoreMedia
import XCTest
@testable import FrameMate

private final class MockRecordingOutputDirectoryStore: RecordingOutputDirectoryStoring {
    var outputDirectoryPath: String?
    var outputDirectoryBookmarkData: Data?
}

private final class MockSoundEffectPlayer: SoundEffectPlaying {
    func playStart() -> TimeInterval { 0 }
    func playStop() -> TimeInterval { 0 }
    func playPauseResume() -> TimeInterval { 0 }
}

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

    private func makeViewModel(
        recorder: MockCaptureRecorder = MockCaptureRecorder(),
        microphoneRecorder: MockMicrophoneAudioRecorder = MockMicrophoneAudioRecorder(),
        stopWatchdogTimeout: Duration = .seconds(15)
    ) -> RecorderViewModel {
        RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: MockScreenRecordingProvider(
                status: .authorized,
                displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
            ),
            microphoneAudioRecorder: microphoneRecorder,
            fileNamer: RecordingFileNamer(outputDirectory: tempDir),
            soundEffectPlayer: MockSoundEffectPlayer(),
            recordingOutputDirectoryStore: MockRecordingOutputDirectoryStore(),
            permissionProvider: MockMediaPermissionProvider(statuses: [
                .video: .authorized,
                .audio: .authorized
            ]),
            appAccessManager: MockAppAccessManager(
                state: AppAccessState(accessKind: .trial, trialDaysRemaining: 14, offers: [])
            ),
            stopWatchdogTimeout: stopWatchdogTimeout
        )
    }

    // stopRecording must clear isRecording and isPaused even with no active session.
    func testStopRecordingClearsState() async {
        let vm = makeViewModel()
        await vm.setup()

        vm.stopRecording()

        XCTAssertFalse(vm.isRecording)
        XCTAssertFalse(vm.isPaused)
    }

    // setup() preserves temporary captures from a previous crash for recovery.
    func testSetupPreservesRecoverableTempFiles() async throws {
        let orphans: [String] = [
            "tmp-20260424-120000.mov",
            "camera-overlay-20260424-120001.mov",
            "screen-microphone-20260424-120000.m4a",
            "screen-system-audio-20260424-120000.m4a",
            "system-audio-20260424-120000.m4a",
        ]
        for name in orphans {
            try "orphan".write(to: tempDir.appendingPathComponent(name),
                               atomically: true, encoding: .utf8)
        }

        // Real final recordings must be preserved
        let realFile = tempDir.appendingPathComponent("Kamera Kaydı 24.04.2026 12.00.mp4")
        try "real".write(to: realFile, atomically: true, encoding: .utf8)

        let vm = makeViewModel()
        await vm.setup()

        for name in orphans {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(name).path),
                "Recoverable temporary capture '\(name)' must be retained on startup"
            )
        }
        XCTAssertEqual(vm.recoveredTemporaryRecordingURLs.map(\.lastPathComponent).sorted(), orphans.sorted())
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: realFile.path),
            "Real recording must NOT be removed"
        )
    }

    // Audio recording toggle while already recording must not call startRecording again.
    func testAudioToggleWhileRecordingDoesNotDoubleStart() async {
        let mic = MockMicrophoneAudioRecorder()
        let vm = makeViewModel(microphoneRecorder: mic)
        await vm.setup()

        vm.selectedPreset = .audioOnly
        vm.selectedMicrophoneID = "mic-1"

        vm.toggleAudioRecording()
        try? await Task.sleep(nanoseconds: 80_000_000)
        let callsAfterFirst = mic.startCallCount

        // Second toggle while recording should stop, not start again
        vm.toggleAudioRecording()
        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(mic.startCallCount, callsAfterFirst,
                       "startRecording must not fire a second time while recording is active")
    }

    // Calling setup() twice must be idempotent — no double-initialisation.
    func testDoubleSetupIsIdempotent() async {
        let vm = makeViewModel()
        await vm.setup()
        await vm.setup()

        // No crash and state is consistent
        XCTAssertFalse(vm.isRecording)
    }

    // Phase 1.3: audio-only with no microphone and system audio disabled has no
    // component left to produce a completion, so it must be rejected at start rather
    // than silently sitting in `.stopping` forever after stop.
    func testAudioOnlyWithNoMicrophoneAndNoSystemAudioIsRejectedAtStart() async {
        let vm = makeViewModel()
        await vm.setup()

        vm.selectedMicrophoneID = ""
        vm.isSystemAudioEnabled = false
        vm.recordingCountdown = .none

        vm.toggleAudioRecording()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(vm.isRecording, "Audio-only recording with no mic and no system audio must not start")
    }

    // Phase 1.2: if a component's completion callback never arrives, the stop watchdog
    // must force the pending result and re-enter finalize so the lifecycle returns to
    // idle and a subsequent recording can start — instead of being stuck in `.stopping`
    // for the lifetime of the app.
    func testStopWatchdogUnsticksLifecycleWhenAComponentNeverCompletes() async {
        let mic = MockMicrophoneAudioRecorder()
        let vm = makeViewModel(
            recorder: MockCaptureRecorder(microphones: [InputDevice(id: "mic-1", name: "Built-in Mic")]),
            microphoneRecorder: mic,
            stopWatchdogTimeout: .milliseconds(50)
        )
        await vm.setup()

        vm.isSystemAudioEnabled = false
        vm.recordingCountdown = .none
        // Setting the preset first (as toggleAudioRecording() itself would) runs
        // refreshDeviceState(), which re-validates the microphone selection against the
        // recorder's device list — so the microphone must be selected afterwards, or
        // refreshDeviceState() clears a selection that doesn't match any known device.
        vm.selectPreset(.audioOnly)
        vm.selectedMicrophoneID = "mic-1"

        vm.toggleAudioRecording()
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(vm.isRecording, "Precondition: recording must have started")

        // Simulate a component whose completion callback never fires.
        mic.shouldCompleteOnStop = false
        vm.stopRecording()
        XCTAssertFalse(vm.isRecording)

        // Wait past the (shortened) watchdog timeout for it to force-finalize.
        try? await Task.sleep(nanoseconds: 400_000_000)

        // Proof the lifecycle is back to idle: a new recording must be able to start.
        mic.shouldCompleteOnStop = true
        vm.toggleAudioRecording()
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(
            vm.isRecording,
            "After the stop watchdog forces finalize, the lifecycle must return to idle so a new recording can start"
        )
    }

    // Phase 2: pause session time must be anchored to the primary component's first
    // sample, not to wall-clock time since startRecording() was called. This is the test
    // that would have caught the original bug — a pause taken well after the recording
    // "started" (by wall clock) must still be measured from when the first sample
    // actually landed, which can be later.
    func testPauseSessionTimeIsAnchoredToPrimaryFirstSampleNotWallClockStart() async {
        let mic = MockMicrophoneAudioRecorder()
        let vm = makeViewModel(
            recorder: MockCaptureRecorder(microphones: [InputDevice(id: "mic-1", name: "Built-in Mic")]),
            microphoneRecorder: mic
        )
        await vm.setup()

        vm.isSystemAudioEnabled = false
        vm.recordingCountdown = .none
        vm.selectPreset(.audioOnly)
        vm.selectedMicrophoneID = "mic-1"

        vm.toggleAudioRecording()
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(vm.isRecording, "Precondition: recording must have started")

        // The primary component's first sample "lands" 10 real seconds before the pause
        // below is requested (simulated by backdating the fake's first-sample time rather
        // than actually waiting 10 seconds).
        mic.firstSamplePresentationTime = RecordingSessionClock.now() - CMTime(seconds: 10, preferredTimescale: 600)

        vm.togglePauseResume() // pause
        try? await Task.sleep(nanoseconds: 20_000_000)
        vm.togglePauseResume() // resume — finalizes the pause range

        let pauseTimeline = vm.recordingPauseTimelineForTesting
        XCTAssertEqual(pauseTimeline.ranges.count, 1)
        let pauseStart = pauseTimeline.ranges.first?.start ?? -1
        XCTAssertEqual(
            pauseStart, 10.0, accuracy: 1.0,
            "Pause must be anchored ~10s after session zero (the first sample), not ~0s after wall-clock recording start"
        )
    }
}
