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
final class RecorderViewModelOverlayLifecycleTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "recording.lastConfiguration")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "recording.lastConfiguration")
        super.tearDown()
    }

    private func makeViewModel(
        cameraOverlayRecorder: MockCameraOverlayRecorder = MockCameraOverlayRecorder()
    ) -> RecorderViewModel {
        RecorderViewModel(
            recorder: MockCaptureRecorder(cameras: [InputDevice(id: "cam-1", name: "Test Camera")]),
            screenRecordingProvider: MockScreenRecordingProvider(
                status: .authorized,
                displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
            ),
            cameraOverlayRecorder: cameraOverlayRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
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

    // Toggling camera overlay when not in screen preset must not trigger configure/session.
    func testToggleOverlayIgnoredInCameraPreset() async {
        let overlay = MockCameraOverlayRecorder()
        let vm = makeViewModel(cameraOverlayRecorder: overlay)
        await vm.setup()

        vm.selectPreset(.horizontalCamera)
        vm.toggleScreenCameraOverlay()

        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(overlay.configureCallCount, 0,
                       "configure must not be called when preset is not screen-based")
        XCTAssertFalse(overlay.startSessionCalled,
                       "session must not start when preset is not screen-based")
    }

    // Enabling overlay in screen preset must trigger configure + startSession.
    func testEnableOverlayInScreenPresetConfiguresSession() async {
        let overlay = MockCameraOverlayRecorder()
        let vm = makeViewModel(cameraOverlayRecorder: overlay)
        await vm.setup()

        vm.selectPreset(.horizontalScreen)
        vm.setScreenCameraOverlayEnabled(true)

        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertTrue(vm.isScreenCameraOverlayEnabled)
        XCTAssertEqual(overlay.configuredCameraID, "cam-1")
        XCTAssertTrue(overlay.startSessionCalled)
    }

    // Rapid toggle on/off/on/off must not crash or leave session in bad state.
    func testRapidOverlayToggleDoesNotCrash() async {
        let overlay = MockCameraOverlayRecorder()
        let vm = makeViewModel(cameraOverlayRecorder: overlay)
        await vm.setup()

        vm.selectPreset(.horizontalScreen)

        for _ in 0..<5 {
            vm.setScreenCameraOverlayEnabled(true)
            try? await Task.sleep(nanoseconds: 10_000_000)
            vm.setScreenCameraOverlayEnabled(false)
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(vm.isScreenCameraOverlayEnabled)
        XCTAssertTrue(overlay.stopSessionCalled)
    }

    // Disabling overlay while configure() is still in-flight must cancel cleanly.
    func testDisableWhileConfigureInFlightCancelsCleanly() async {
        let overlay = MockCameraOverlayRecorder()
        overlay.configureDelayNanoseconds = 200_000_000 // 200 ms

        let vm = makeViewModel(cameraOverlayRecorder: overlay)
        await vm.setup()

        vm.selectPreset(.horizontalScreen)

        vm.setScreenCameraOverlayEnabled(true)
        vm.setScreenCameraOverlayEnabled(false)

        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertFalse(vm.isScreenCameraOverlayEnabled)
        XCTAssertFalse(overlay.startSessionCalled,
                       "Session must NOT be started when overlay was cancelled mid-configure")
    }
}
