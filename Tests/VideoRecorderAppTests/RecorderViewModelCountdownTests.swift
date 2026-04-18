import XCTest
@testable import FrameMate

@MainActor
final class RecorderViewModelCountdownTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "recording.lastConfiguration")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "recording.lastConfiguration")
        super.tearDown()
    }

    func testIsCountingDownFalseWhenZero() {
        let vm = makeViewModel()
        XCTAssertFalse(vm.isCountingDown)
    }

    func testIsCountingDownTrueWhenPositive() {
        let vm = makeViewModel()
        vm.countdownRemaining = 3
        XCTAssertTrue(vm.isCountingDown)
    }

    func testCanStartRecordingFalseWhenCountingDown() {
        let vm = makeViewModel()
        vm.countdownRemaining = 3
        XCTAssertFalse(vm.canStartRecording)
    }

    // Smoke test: sets countdownRemaining directly (no Task started) to verify
    // that toggleRecording() calls cancelCountdown() and resets state synchronously.
    func testToggleRecordingCancelsCountdownWhenCounting() {
        let vm = makeViewModel()
        vm.countdownRemaining = 3
        vm.toggleRecording()
        XCTAssertEqual(vm.countdownRemaining, 0)
        XCTAssertFalse(vm.isCountingDown)
    }

    func testRecordingCountdownDefaultIsNone() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.recordingCountdown, .none)
    }

    func testMaxRecordingDurationDefaultIsUnlimited() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.maxRecordingDuration, .unlimited)
    }

    func testMaxDurationUnlimitedHasNilSeconds() {
        XCTAssertNil(MaxRecordingDuration.unlimited.seconds)
    }

    func testMaxDurationFiveHasCorrectSeconds() {
        XCTAssertEqual(MaxRecordingDuration.five.seconds, 300)
    }

    private func makeViewModel() -> RecorderViewModel {
        RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )
    }
}
