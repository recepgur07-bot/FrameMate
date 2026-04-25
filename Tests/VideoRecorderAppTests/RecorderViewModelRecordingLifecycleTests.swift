import XCTest
@testable import FrameMate

private final class MockRecordingOutputDirectoryStore: RecordingOutputDirectoryStoring {
    var outputDirectoryPath: String?
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
        microphoneRecorder: MockMicrophoneAudioRecorder = MockMicrophoneAudioRecorder()
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
            )
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

    // setup() must delete orphaned temp files from a previous crash.
    func testSetupDeletesOrphanedTempFiles() async throws {
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
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(name).path),
                "Orphan '\(name)' must be removed on startup"
            )
        }
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
}
