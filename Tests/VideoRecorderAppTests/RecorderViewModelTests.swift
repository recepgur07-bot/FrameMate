import XCTest
import AVFoundation
@testable import VideoRecorderApp

@MainActor
final class RecorderViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "recording.lastConfiguration")
        UserDefaults.standard.removeObject(forKey: "appAccess.trialStartDate")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "recording.lastConfiguration")
        UserDefaults.standard.removeObject(forKey: "appAccess.trialStartDate")
        super.tearDown()
    }

    func testExpiredAccessPresentsPaywallBeforeStartingAudioRecording() async {
        let microphoneRecorder = MockMicrophoneAudioRecorder()
        let appAccessManager = MockAppAccessManager(
            state: AppAccessState(
                accessKind: .expired,
                trialDaysRemaining: 0,
                offers: []
            )
        )
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(
                microphones: [InputDevice(id: "mic-1", name: "Built-in Mic")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(),
            microphoneAudioRecorder: microphoneRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.audio: .authorized]),
            appAccessManager: appAccessManager
        )

        await viewModel.setup()
        viewModel.toggleAudioRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(viewModel.isPaywallPresented)
        XCTAssertFalse(microphoneRecorder.startCalled)
    }

    func testTrialAccessAllowsAudioRecordingToStart() async {
        let microphoneRecorder = MockMicrophoneAudioRecorder()
        let appAccessManager = MockAppAccessManager(
            state: AppAccessState(
                accessKind: .trial,
                trialDaysRemaining: 14,
                offers: []
            )
        )
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(
                microphones: [InputDevice(id: "mic-1", name: "Built-in Mic")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(),
            microphoneAudioRecorder: microphoneRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.audio: .authorized]),
            appAccessManager: appAccessManager
        )

        await viewModel.setup()
        viewModel.toggleAudioRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(viewModel.isPaywallPresented)
        XCTAssertTrue(microphoneRecorder.startCalled)
    }

    func testFrameCoachSettingsDefaultToAccessibleBalancedGuidance() async {
        let settingsStore = MockFrameCoachSettingsStore()
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            frameCoachSettingsStore: settingsStore,
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )

        await viewModel.setup()

        XCTAssertEqual(viewModel.frameCoachSpeechMode, FrameCoachSpeechMode.automatic)
        XCTAssertEqual(viewModel.frameCoachFeedbackFrequency, FrameCoachFeedbackFrequency.balanced)
        XCTAssertEqual(viewModel.frameCoachRepeatInterval, FrameCoachRepeatInterval.medium)
        XCTAssertTrue(viewModel.showsFrameCoachTextOnScreen)
    }

    func testUpdatingFrameCoachSettingsPersistsThemToStore() {
        let settingsStore = MockFrameCoachSettingsStore()
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            frameCoachSettingsStore: settingsStore,
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )

        viewModel.frameCoachSpeechMode = FrameCoachSpeechMode.voiceOver
        viewModel.frameCoachFeedbackFrequency = FrameCoachFeedbackFrequency.minimal
        viewModel.frameCoachRepeatInterval = FrameCoachRepeatInterval.long
        viewModel.showsFrameCoachTextOnScreen = false

        XCTAssertEqual(settingsStore.speechMode, FrameCoachSpeechMode.voiceOver)
        XCTAssertEqual(settingsStore.feedbackFrequency, FrameCoachFeedbackFrequency.minimal)
        XCTAssertEqual(settingsStore.repeatInterval, FrameCoachRepeatInterval.long)
        XCTAssertFalse(settingsStore.showsOnScreenText)
    }

    func testKeyboardShortcutOverlayDefaultsToDisabled() async {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )

        await viewModel.setup()

        XCTAssertFalse(viewModel.isKeyboardShortcutOverlayEnabled)
    }

    func testCursorHighlightDefaultsToDisabled() async {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )

        await viewModel.setup()

        XCTAssertFalse(viewModel.isCursorHighlightEnabled)
    }

    func testRestoresLastRecordingConfigurationOnSetup() async {
        let store = MockLastRecordingConfigurationStore()
        store.configuration = LastRecordingConfiguration(
            selectedPreset: .horizontalScreen,
            selectedScreenCaptureSource: .window,
            isScreenCameraOverlayEnabled: true,
            isSystemAudioEnabled: true,
            isCursorHighlightEnabled: true,
            isKeyboardShortcutOverlayEnabled: true,
            isAutoReframeEnabled: false,
            isFrameCoachEnabled: true,
            selectedCameraID: "cam-2",
            selectedMicrophoneID: "mic-2",
            selectedDisplayID: "display-2",
            selectedWindowID: "window-2"
        )
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(
                cameras: [
                    InputDevice(id: "cam-1", name: "Camera 1"),
                    InputDevice(id: "cam-2", name: "Camera 2")
                ],
                microphones: [
                    InputDevice(id: "mic-1", name: "Mic 1"),
                    InputDevice(id: "mic-2", name: "Mic 2")
                ]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            lastRecordingConfigurationStore: store,
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .authorized, .audio: .authorized]),
        )

        await viewModel.setup()

        XCTAssertEqual(viewModel.selectedPreset, .horizontalScreen)
        XCTAssertEqual(viewModel.selectedRecordingSource, .window)
        XCTAssertEqual(viewModel.selectedScreenCaptureSource, .window)
        XCTAssertTrue(viewModel.isScreenCameraOverlayEnabled)
        XCTAssertTrue(viewModel.isSystemAudioEnabled)
        XCTAssertTrue(viewModel.isCursorHighlightEnabled)
        XCTAssertTrue(viewModel.isKeyboardShortcutOverlayEnabled)
        XCTAssertFalse(viewModel.isAutoReframeEnabled)
        XCTAssertTrue(viewModel.isFrameCoachEnabled)
        XCTAssertEqual(viewModel.selectedCameraID, "cam-2")
        XCTAssertEqual(viewModel.selectedMicrophoneID, "mic-2")
    }

    func testPersistsLastRecordingConfigurationWhenSettingsChange() {
        let store = MockLastRecordingConfigurationStore()
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            lastRecordingConfigurationStore: store,
            permissionProvider: MockMediaPermissionProvider(statuses: [:]),
        )

        viewModel.selectPreset(.verticalScreen)
        viewModel.selectScreenCaptureSource(.window)
        viewModel.isScreenCameraOverlayEnabled = true
        viewModel.isSystemAudioEnabled = true
        viewModel.isCursorHighlightEnabled = true
        viewModel.isKeyboardShortcutOverlayEnabled = true
        viewModel.isAutoReframeEnabled = false
        viewModel.toggleFrameCoach()
        viewModel.selectedCameraID = "cam-1"
        viewModel.selectedMicrophoneID = "mic-1"

        XCTAssertEqual(
            store.configuration,
            LastRecordingConfiguration(
                selectedPreset: .verticalScreen,
                selectedScreenCaptureSource: .window,
                isScreenCameraOverlayEnabled: true,
                isSystemAudioEnabled: true,
                isCursorHighlightEnabled: true,
                isKeyboardShortcutOverlayEnabled: true,
                isAutoReframeEnabled: false,
                isFrameCoachEnabled: true,
                selectedCameraID: "cam-1",
                selectedMicrophoneID: "mic-1",
                selectedDisplayID: "",
                selectedWindowID: ""
            )
        )
    }

    func testSelectingVerticalScreenPresetUpdatesModeAndSource() async {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )

        await viewModel.setup()
        viewModel.selectPreset(.verticalScreen)

        XCTAssertEqual(viewModel.selectedPreset, .verticalScreen)
        XCTAssertEqual(viewModel.selectedMode, .vertical1080p)
        XCTAssertEqual(viewModel.selectedRecordingSource, .screen)
    }

    func testEachPresetMapsToExpectedModeAndSource() async {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )

        await viewModel.setup()

        let expectations: [(RecordingPreset, RecordingMode, RecordingSource)] = [
            (.horizontalCamera, .horizontal1080p, .camera),
            (.verticalCamera, .vertical1080p, .camera),
            (.horizontalScreen, .horizontal1080p, .screen),
            (.verticalScreen, .vertical1080p, .screen),
            (.audioOnly, .horizontal1080p, .audio)
        ]

        for (preset, expectedMode, expectedSource) in expectations {
            viewModel.selectScreenCaptureSource(.screen)
            viewModel.selectPreset(preset)

            XCTAssertEqual(viewModel.selectedPreset, preset)
            XCTAssertEqual(viewModel.selectedMode, expectedMode)
            XCTAssertEqual(viewModel.selectedRecordingSource, expectedSource)
        }
    }

    func testAudioOnlyPresetUsesCommandFive() {
        XCTAssertEqual(RecordingPreset.audioOnly.commandKey, "5")
    }

    func testCameraPresetMatrixStartsRecorderWithExpectedMode() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        let expectations: [(RecordingPreset, RecordingMode)] = [
            (.horizontalCamera, .horizontal1080p),
            (.verticalCamera, .vertical1080p)
        ]

        for (preset, expectedMode) in expectations {
            let recorder = RecorderCaptureStub(
                cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
                microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
            )
            let viewModel = RecorderViewModel(
                recorder: recorder,
                screenRecordingProvider: MockScreenRecordingProvider(),
                fileNamer: RecordingFileNamer(homeDirectory: tempRoot),
                soundEffectPlayer: SoundEffectPlayer(),
                permissionProvider: permissions
            )

            await viewModel.setup()
            viewModel.selectPreset(preset)
            viewModel.refreshDeviceState()

            XCTAssertTrue(viewModel.canStartRecording)

            viewModel.startRecording()
            try? await Task.sleep(nanoseconds: 50_000_000)

            XCTAssertEqual(viewModel.selectedRecordingSource, .camera)
            XCTAssertEqual(recorder.configuredMode, expectedMode)
            XCTAssertEqual(recorder.configuredVideoDeviceID, "cam-1")
            XCTAssertEqual(recorder.configuredAudioDeviceID, "mic-1")
            XCTAssertTrue(recorder.startCalled)

            viewModel.stopRecording()
            try? await Task.sleep(nanoseconds: 50_000_000)

            XCTAssertTrue(recorder.stopCalled)
        }
    }

    func testVerticalScreenPresetKeepsVerticalModeWhenSwitchingToWindowSource() async {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )

        await viewModel.setup()
        viewModel.selectPreset(.verticalScreen)
        viewModel.selectScreenCaptureSource(.window)

        XCTAssertEqual(viewModel.selectedPreset, .verticalScreen)
        XCTAssertEqual(viewModel.selectedMode, .vertical1080p)
        XCTAssertEqual(viewModel.selectedRecordingSource, .window)
        XCTAssertEqual(viewModel.selectedScreenCaptureSource, .window)
    }

    func testScreenPresetMatrixUsesExpectedTargetForScreenAndWindowSources() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        let expectations: [(RecordingPreset, ScreenCaptureSource, RecordingMode, ScreenRecordingTarget)] = [
            (.horizontalScreen, .screen, .horizontal1080p, .display(id: "display-1")),
            (.horizontalScreen, .window, .horizontal1080p, .window(id: "window-1")),
            (.verticalScreen, .screen, .vertical1080p, .display(id: "display-1")),
            (.verticalScreen, .window, .vertical1080p, .window(id: "window-1"))
        ]

        for (preset, source, expectedMode, expectedTarget) in expectations {
            let recorder = RecorderCaptureStub(
                cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
                microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
            )
            let screenProvider = MockScreenRecordingProvider(
                status: .authorized,
                displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")],
                windows: [ScreenWindowOption(id: "window-1", name: "Safari - Docs")]
            )
            let viewModel = RecorderViewModel(
                recorder: recorder,
                screenRecordingProvider: screenProvider,
                systemAudioRecorder: MockSystemAudioRecorder(),
                microphoneAudioRecorder: MockMicrophoneAudioRecorder(),
                fileNamer: RecordingFileNamer(homeDirectory: tempRoot),
                soundEffectPlayer: MockSoundEffectPlayer(),
                permissionProvider: permissions
            )

            await viewModel.setup()
            viewModel.selectPreset(preset)
            viewModel.selectScreenCaptureSource(source)
            viewModel.refreshDeviceState()
            await viewModel.refreshScreenRecordingOptions()

            XCTAssertEqual(viewModel.selectedMode, expectedMode)
            XCTAssertTrue(viewModel.canStartRecording)

            viewModel.startRecording()
            for _ in 0..<20 where screenProvider.startedTarget == nil {
                try? await Task.sleep(nanoseconds: 25_000_000)
            }

            XCTAssertEqual(viewModel.selectedRecordingSource, source.recordingSource)
            XCTAssertEqual(screenProvider.startedTarget, expectedTarget)
            XCTAssertEqual(viewModel.currentPresetReadinessLabel, source == .window ? "\(preset == .verticalScreen ? "Dikey" : "Yatay") pencere kaydı" : "\(preset == .verticalScreen ? "Dikey" : "Yatay") ekran kaydı")
        }
    }

    func testScreenPresetMatrixStopsCleanlyAcrossOrientations() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        let expectations: [(RecordingPreset, ScreenCaptureSource)] = [
            (.horizontalScreen, .screen),
            (.horizontalScreen, .window),
            (.verticalScreen, .screen),
            (.verticalScreen, .window)
        ]

        for (preset, source) in expectations {
            let recorder = RecorderCaptureStub(
                cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
                microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
            )
            let screenProvider = MockScreenRecordingProvider(
                status: .authorized,
                displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")],
                windows: [ScreenWindowOption(id: "window-1", name: "Safari - Docs")]
            )
            screenProvider.shouldCompleteOnStop = true
            let viewModel = RecorderViewModel(
                recorder: recorder,
                screenRecordingProvider: screenProvider,
                systemAudioRecorder: MockSystemAudioRecorder(),
                microphoneAudioRecorder: MockMicrophoneAudioRecorder(),
                fileNamer: RecordingFileNamer(homeDirectory: tempRoot),
                soundEffectPlayer: MockSoundEffectPlayer(),
                permissionProvider: permissions
            )

            await viewModel.setup()
            viewModel.selectPreset(preset)
            viewModel.selectScreenCaptureSource(source)
            viewModel.refreshDeviceState()
            await viewModel.refreshScreenRecordingOptions()

            viewModel.startRecording()
            for _ in 0..<80 where !viewModel.isRecording {
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            XCTAssertTrue(viewModel.isRecording, viewModel.errorText ?? viewModel.statusText)

            viewModel.stopRecording()
            try? await Task.sleep(nanoseconds: 100_000_000)

            XCTAssertTrue(screenProvider.stopCalled)
            XCTAssertFalse(screenProvider.isStartPending)
            XCTAssertFalse(viewModel.isRecording)
        }
    }

    func testSwitchingScreenCaptureSourceKeepsScreenPresetButUpdatesRecordingSource() async {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.selectScreenCaptureSource(.window)

        XCTAssertEqual(viewModel.selectedPreset, .horizontalScreen)
        XCTAssertEqual(viewModel.selectedRecordingSource, .window)
        XCTAssertEqual(viewModel.selectedScreenCaptureSource, .window)
    }

    func testPresetVisibilityFlagsShowOnlyRelevantControls() async {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            cameraOverlayRecorder: MockCameraOverlayRecorder(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )

        await viewModel.setup()
        XCTAssertTrue(viewModel.showsCameraControls)
        XCTAssertFalse(viewModel.showsScreenControls)
        XCTAssertFalse(viewModel.showsScreenPicker)

        viewModel.selectPreset(.horizontalScreen)
        XCTAssertFalse(viewModel.showsCameraControls)
        XCTAssertTrue(viewModel.showsScreenControls)
        XCTAssertTrue(viewModel.showsScreenPicker)
        XCTAssertFalse(viewModel.showsWindowPicker)
        XCTAssertTrue(viewModel.showsScreenOverlayControls)
        XCTAssertFalse(viewModel.showsScreenOverlayConfiguration)

        viewModel.toggleScreenCameraOverlay()
        XCTAssertTrue(viewModel.showsScreenOverlayConfiguration)
        XCTAssertEqual(viewModel.selectedScreenCameraOverlaySize, .medium)

        viewModel.selectScreenCaptureSource(.window)
        XCTAssertTrue(viewModel.showsWindowPicker)
        XCTAssertFalse(viewModel.showsScreenPicker)
    }

    func testScreenOverlayEnablesFrameCoachControls() async {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            cameraOverlayRecorder: MockCameraOverlayRecorder(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .authorized, .audio: .authorized])
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)

        XCTAssertFalse(viewModel.showsFrameCoachControls)

        viewModel.toggleScreenCameraOverlay()

        XCTAssertTrue(viewModel.showsFrameCoachControls)
    }

    func testScreenOverlayRequiresCameraSelectionWhenEnabled() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let screenProvider = MockScreenRecordingProvider(
            status: .authorized,
            displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
        )
        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            cameraOverlayRecorder: MockCameraOverlayRecorder(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.toggleScreenCameraOverlay()
        viewModel.refreshDeviceState()
        await viewModel.refreshScreenRecordingOptions()

        XCTAssertFalse(viewModel.canStartRecording)
        XCTAssertEqual(viewModel.statusText, "Kamera kutusu için kullanılabilir kamera bulunamadı.")
    }

    func testScreenOverlayStartsAndStopsCameraOverlayRecorder() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let screenProvider = MockScreenRecordingProvider(
            status: .authorized,
            displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
        )
        let overlayRecorder = MockCameraOverlayRecorder()

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            cameraOverlayRecorder: overlayRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: tempRoot),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.toggleScreenCameraOverlay()
        viewModel.selectedScreenCameraOverlaySize = .large
        viewModel.refreshDeviceState()
        await viewModel.refreshScreenRecordingOptions()

        viewModel.startRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(overlayRecorder.configuredCameraID, "cam-1")
        XCTAssertEqual(overlayRecorder.configuredMode, .horizontal1080p)
        XCTAssertNotNil(overlayRecorder.startedURL)

        viewModel.stopRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(overlayRecorder.stopCalled)
    }

    func testScreenOverlayStartErrorShowsFriendlyCameraEffectsMessage() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let screenProvider = MockScreenRecordingProvider(
            status: .authorized,
            displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
        )
        let overlayRecorder = MockCameraOverlayRecorder()
        overlayRecorder.startError = CaptureRecorderError.cameraVideoEffectsActive(["Portre", "Stüdyo Işığı"])

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            cameraOverlayRecorder: overlayRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: tempRoot),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.toggleScreenCameraOverlay()
        viewModel.refreshDeviceState()
        await viewModel.refreshScreenRecordingOptions()

        viewModel.startRecording()
        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(
            viewModel.errorText,
            "Kamera denetim merkezindeki video efektleri açık: Portre, Stüdyo Işığı. Bu efektleri kapatıp tekrar deneyin."
        )
        XCTAssertFalse(viewModel.isRecording)
    }

    func testScreenRecordingUsesSeparateMicrophoneRecorderInsteadOfEmbeddedScreenMicrophone() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let screenProvider = MockScreenRecordingProvider(
            status: .authorized,
            displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
        )
        let microphoneRecorder = MockMicrophoneAudioRecorder()

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            cameraOverlayRecorder: MockCameraOverlayRecorder(),
            systemAudioRecorder: MockSystemAudioRecorder(),
            microphoneAudioRecorder: microphoneRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: tempRoot),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.refreshDeviceState()
        await viewModel.refreshScreenRecordingOptions()

        viewModel.startRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(screenProvider.startedMicrophoneID, "")
        XCTAssertTrue(microphoneRecorder.startCalled)

        viewModel.stopRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(microphoneRecorder.stopCalled)
    }

    func testScreenRecordingStartsAndStopsCursorTrackingWhenEnabled() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let screenProvider = MockScreenRecordingProvider(
            status: .authorized,
            displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display", frame: CGRect(x: 0, y: 0, width: 1440, height: 900))]
        )
        screenProvider.shouldCompleteOnStop = true
        let cursorRecorder = MockCursorHighlightRecorder()

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            cameraOverlayRecorder: MockCameraOverlayRecorder(),
            systemAudioRecorder: MockSystemAudioRecorder(),
            microphoneAudioRecorder: MockMicrophoneAudioRecorder(),
            cursorHighlightRecorder: cursorRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: tempRoot),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.isCursorHighlightEnabled = true
        viewModel.refreshDeviceState()
        await viewModel.refreshScreenRecordingOptions()

        viewModel.startRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(cursorRecorder.startCalled)
        XCTAssertEqual(cursorRecorder.startedFrame, CGRect(x: 0, y: 0, width: 1440, height: 900))

        viewModel.stopRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(cursorRecorder.stopCalled)
    }

    func testScreenRecordingStartsAndStopsKeyboardShortcutTrackingWhenEnabled() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let screenProvider = MockScreenRecordingProvider(
            status: .authorized,
            displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display", frame: CGRect(x: 0, y: 0, width: 1440, height: 900))]
        )
        screenProvider.shouldCompleteOnStop = true
        let keyboardRecorder = MockKeyboardShortcutRecorder()

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            cameraOverlayRecorder: MockCameraOverlayRecorder(),
            systemAudioRecorder: MockSystemAudioRecorder(),
            microphoneAudioRecorder: MockMicrophoneAudioRecorder(),
            cursorHighlightRecorder: MockCursorHighlightRecorder(),
            keyboardShortcutRecorder: keyboardRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: tempRoot),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.isKeyboardShortcutOverlayEnabled = true
        viewModel.refreshDeviceState()
        await viewModel.refreshScreenRecordingOptions()

        viewModel.startRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(keyboardRecorder.startCalled)

        viewModel.stopRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(keyboardRecorder.stopCalled)
    }

    func testScreenModeVisibilityHelpersHideInactiveAudioControls() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: MockScreenRecordingProvider(
                status: .authorized,
                displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
            ),
            cameraOverlayRecorder: MockCameraOverlayRecorder(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)

        XCTAssertTrue(viewModel.showsScreenSourceSection)
        XCTAssertTrue(viewModel.showsScreenAudioSection)
        XCTAssertTrue(viewModel.showsMicrophonePicker)
        XCTAssertTrue(viewModel.showsMicrophoneVolumeControl)
        XCTAssertFalse(viewModel.showsSystemAudioVolumeControl)

        viewModel.selectedMicrophoneID = ""
        viewModel.isSystemAudioEnabled = true

        XCTAssertFalse(viewModel.showsMicrophoneVolumeControl)
        XCTAssertTrue(viewModel.showsSystemAudioVolumeControl)
    }

    func testSetupLoadsAuthorizedInputsEvenWhenOnlyOnePermissionIsGranted() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .denied]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "FaceTime HD Camera")],
            microphones: [InputDevice(id: "mic-1", name: "Built-in Microphone")]
        )

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()

        XCTAssertEqual(viewModel.cameras.map(\.id), ["cam-1"])
        XCTAssertTrue(viewModel.microphones.isEmpty)
        XCTAssertEqual(viewModel.selectedCameraID, "cam-1")
        XCTAssertEqual(viewModel.selectedMicrophoneID, "")
        XCTAssertEqual(
            viewModel.statusText,
            "Kayıt için şu izinler gerekli: mikrofon. Aşağıdaki butonlardan izin verin."
        )
    }

    func testRefreshDeviceListsReplacesMissingSelectionsWithAvailableOnes() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()

        recorder.cameras = [InputDevice(id: "cam-2", name: "External Camera")]
        recorder.microphones = [InputDevice(id: "mic-2", name: "BuiltInMicrophoneDevice")]

        viewModel.refreshDeviceState()

        XCTAssertEqual(viewModel.selectedCameraID, "cam-2")
        XCTAssertEqual(viewModel.selectedMicrophoneID, "mic-2")
        XCTAssertEqual(viewModel.statusText, "Yatay video kaydı hazır.")
    }

    func testPrivacySettingsButtonsOpenMatchingPreferencePane() {
        var openedURL: URL?
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:]),
            openURL: { openedURL = $0 }
        )

        viewModel.openPrivacySettings(for: .video)
        XCTAssertEqual(
            openedURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        )

        viewModel.openPrivacySettings(for: .audio)
        XCTAssertEqual(
            openedURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )

        viewModel.openScreenRecordingSettings()
        XCTAssertEqual(
            openedURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    func testAutomaticFrameCoachingProfileUsesVerticalProfileForSinglePerson() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectedMode = .vertical1080p
        viewModel.processFrameCoachAnalysis(
            FrameAnalysis(
                faceBoxes: [NormalizedFaceBox(rect: CGRect(x: 0.40, y: 0.31, width: 0.21, height: 0.26))],
                subjectCount: .one,
                headroomRatio: 0.29,
                bottomCoverageRatio: 0.14,
                horizontalGroupCenter: 0.505,
                spacingMetric: 0,
                confidence: 0.95
            )
        )

        XCTAssertEqual(viewModel.currentFrameCoachInstruction, nil)

        viewModel.toggleFrameCoach()
        viewModel.processFrameCoachAnalysis(
            FrameAnalysis(
                faceBoxes: [NormalizedFaceBox(rect: CGRect(x: 0.40, y: 0.31, width: 0.21, height: 0.26))],
                subjectCount: .one,
                headroomRatio: 0.29,
                bottomCoverageRatio: 0.14,
                horizontalGroupCenter: 0.505,
                spacingMetric: 0,
                confidence: 0.95
            )
        )

        XCTAssertEqual(viewModel.currentFrameCoachInstruction, "kadraj uygun")
    }

    func testAutoReframeUpdatesCropForSinglePerson() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectedMode = .horizontal1080p
        viewModel.processAutoReframeAnalysis(
            FrameAnalysis(
                faceBoxes: [NormalizedFaceBox(rect: CGRect(x: 0.18, y: 0.28, width: 0.14, height: 0.18))],
                subjectCount: .one,
                headroomRatio: 0.2,
                bottomCoverageRatio: 0.2,
                horizontalGroupCenter: 0.25,
                spacingMetric: 0,
                confidence: 0.95
            )
        )

        XCTAssertLessThan(viewModel.currentAutoReframeCrop.width, 1.0)
    }

    func testDisablingAutoReframeResetsCropToFullFrame() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.processAutoReframeAnalysis(
            FrameAnalysis(
                faceBoxes: [NormalizedFaceBox(rect: CGRect(x: 0.18, y: 0.28, width: 0.14, height: 0.18))],
                subjectCount: .one,
                headroomRatio: 0.2,
                bottomCoverageRatio: 0.2,
                horizontalGroupCenter: 0.25,
                spacingMetric: 0,
                confidence: 0.95
            )
        )

        viewModel.toggleAutoReframe()

        XCTAssertEqual(viewModel.currentAutoReframeCrop, .fullFrame)
    }

    func testAutoReframeDiagnosticsTrackStrategyAndKeyframes() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.isRecording = true
        viewModel.processAutoReframeAnalysis(
            FrameAnalysis(
                faceBoxes: [
                    NormalizedFaceBox(rect: CGRect(x: 0.22, y: 0.30, width: 0.14, height: 0.18)),
                    NormalizedFaceBox(rect: CGRect(x: 0.58, y: 0.30, width: 0.14, height: 0.18))
                ],
                subjectCount: .two,
                headroomRatio: 0.2,
                bottomCoverageRatio: 0.2,
                horizontalGroupCenter: 0.5,
                spacingMetric: 0.3,
                confidence: 0.95
            ),
            at: CMTime(seconds: 1, preferredTimescale: 600)
        )

        XCTAssertEqual(viewModel.lastAutoReframeStrategy, "iki-kisi-grup")
        XCTAssertEqual(viewModel.lastAutoReframeKeyframeCount, 1)
    }

    func testAutoReframeExportSummaryUsesKeyframeCountWhenCompositionIsApplied() {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )

        XCTAssertEqual(
            viewModel.autoReframeExportSummary(keyframeCount: 42, usedVideoComposition: true),
            "otomatik kadraj uygulandı, 42 ana kare kullanıldı"
        )
        XCTAssertEqual(
            viewModel.autoReframeExportSummary(keyframeCount: 0, usedVideoComposition: false),
            "normal export tamamlandı"
        )
    }

    func testScreenSourceCanStartWithoutCameraSelectionWhenDisplayIsReady() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .denied, .audio: .denied]
        )
        let recorder = RecorderCaptureStub(
            cameras: [],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let screenProvider = MockScreenRecordingProvider(
            status: .authorized,
            displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
        )

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectedRecordingSource = .screen
        viewModel.refreshDeviceState()
        await viewModel.refreshScreenRecordingOptions()

        XCTAssertEqual(viewModel.selectedDisplayID, "display-1")
        XCTAssertTrue(viewModel.canStartRecording)
        XCTAssertEqual(viewModel.statusText, "Yatay ekran kaydı hazır. Mikrofon ve sistem sesi kapalı.")
        XCTAssertEqual(viewModel.permissionStatusText, "Ekran kaydı izni: verildi. Mikrofon izni: reddedildi.")
    }

    func testScreenSourceUsesLoadedSourcesAsPermissionFallbackWhenPreflightLooksDenied() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .denied, .audio: .denied]
        )
        let recorder = RecorderCaptureStub(cameras: [], microphones: [])
        let screenProvider = MockScreenRecordingProvider(
            status: .denied,
            displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
        )

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectedRecordingSource = .screen
        viewModel.refreshDeviceState()
        await viewModel.refreshScreenRecordingOptions()

        XCTAssertEqual(viewModel.screenRecordingPermissionStatus, .authorized)
        XCTAssertEqual(viewModel.selectedDisplayID, "display-1")
        XCTAssertTrue(viewModel.canStartRecording)
        XCTAssertEqual(viewModel.statusText, "Yatay ekran kaydı hazır. Mikrofon ve sistem sesi kapalı.")
    }

    func testScreenSourceStillBecomesReadyWhenWindowListingFailsButDisplaysLoad() async {
        enum StubError: Error { case failed }

        let permissions = RecorderPermissionsStub(
            statuses: [.video: .denied, .audio: .denied]
        )
        let recorder = RecorderCaptureStub(cameras: [], microphones: [])
        let screenProvider = MockScreenRecordingProvider(
            status: .denied,
            displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
        )
        screenProvider.windowsError = StubError.failed

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectedRecordingSource = .screen
        viewModel.refreshDeviceState()
        await viewModel.refreshScreenRecordingOptions()

        XCTAssertEqual(viewModel.screenRecordingPermissionStatus, .authorized)
        XCTAssertEqual(viewModel.selectedDisplayID, "display-1")
        XCTAssertEqual(viewModel.availableDisplays.count, 1)
        XCTAssertTrue(viewModel.canStartRecording)
        XCTAssertEqual(viewModel.statusText, "Yatay ekran kaydı hazır. Mikrofon ve sistem sesi kapalı.")
    }

    func testWindowSourceStillBecomesReadyWhenDisplayListingFailsButWindowsLoad() async {
        enum StubError: Error { case failed }

        let permissions = RecorderPermissionsStub(
            statuses: [.video: .denied, .audio: .denied]
        )
        let recorder = RecorderCaptureStub(cameras: [], microphones: [])
        let screenProvider = MockScreenRecordingProvider(
            status: .denied,
            windows: [ScreenWindowOption(id: "window-1", name: "Safari - Docs")]
        )
        screenProvider.displaysError = StubError.failed

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectedRecordingSource = .window
        viewModel.refreshDeviceState()
        await viewModel.refreshScreenRecordingOptions()

        XCTAssertEqual(viewModel.screenRecordingPermissionStatus, .authorized)
        XCTAssertEqual(viewModel.selectedWindowID, "window-1")
        XCTAssertEqual(viewModel.availableWindows.count, 1)
        XCTAssertTrue(viewModel.canStartRecording)
        XCTAssertEqual(viewModel.statusText, "Yatay pencere kaydı hazır. Mikrofon ve sistem sesi kapalı.")
    }

    func testWindowSourceRequiresScreenPermission() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let screenProvider = MockScreenRecordingProvider(
            status: .denied,
            windows: [ScreenWindowOption(id: "window-1", name: "Safari - Docs")]
        )

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectedRecordingSource = .window
        viewModel.refreshDeviceState()

        XCTAssertFalse(viewModel.canStartRecording)
        XCTAssertEqual(viewModel.statusText, "Ekran kaydı için macOS ekran kaydı izni gerekli.")
    }

    func testScreenRecordingUsesScreenRecorderStartAndStopFlow() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .denied, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let screenProvider = MockScreenRecordingProvider(
            status: .authorized,
            displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
        )

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let microphoneRecorder = MockMicrophoneAudioRecorder()
        let systemAudioRecorder = MockSystemAudioRecorder()
        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            systemAudioRecorder: systemAudioRecorder,
            microphoneAudioRecorder: microphoneRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: tempRoot),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectedRecordingSource = .screen
        viewModel.isSystemAudioEnabled = true
        viewModel.refreshDeviceState()
        await viewModel.refreshScreenRecordingOptions()

        viewModel.startRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(screenProvider.startedTarget, .display(id: "display-1"))
        XCTAssertFalse(screenProvider.startedSystemAudioEnabled)
        XCTAssertTrue(systemAudioRecorder.startCalled)
        XCTAssertTrue(viewModel.isRecording)

        viewModel.stopRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(screenProvider.stopCalled)
    }

    func testCameraModeExplainsSystemAudioIsCurrentlyForScreenModes() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.isSystemAudioEnabled = true
        viewModel.refreshDeviceState()

        XCTAssertEqual(
            viewModel.statusText,
            "Yatay kamera kaydı hazır. Mikrofon ve sistem sesi kayda eklenecek."
        )
    }

    func testCameraRecordingStartsSystemAudioRecorderWhenEnabled() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let systemAudioRecorder = MockSystemAudioRecorder()

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: MockScreenRecordingProvider(),
            systemAudioRecorder: systemAudioRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.isSystemAudioEnabled = true
        viewModel.refreshDeviceState()

        viewModel.startRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(systemAudioRecorder.startCalled)
    }

    func testCameraRecordingStopsSystemAudioRecorderWhenEnabled() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let systemAudioRecorder = MockSystemAudioRecorder()

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: MockScreenRecordingProvider(),
            systemAudioRecorder: systemAudioRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.isSystemAudioEnabled = true
        viewModel.refreshDeviceState()

        viewModel.startRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        viewModel.stopRecording()

        XCTAssertTrue(systemAudioRecorder.stopCalled)
    }

    func testWindowScreenRecordingUsesSeparateSystemAudioRecorder() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let screenProvider = MockScreenRecordingProvider(
            status: .authorized,
            windows: [ScreenWindowOption(id: "window-1", name: "TextEdit - Not")]
        )
        let systemAudioRecorder = MockSystemAudioRecorder()
        let microphoneAudioRecorder = MockMicrophoneAudioRecorder()

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            systemAudioRecorder: systemAudioRecorder,
            microphoneAudioRecorder: microphoneAudioRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.selectScreenCaptureSource(.window)
        viewModel.isSystemAudioEnabled = true
        await viewModel.refreshScreenRecordingOptions()
        viewModel.refreshDeviceState()

        viewModel.startRecording()
        for _ in 0..<20 where !systemAudioRecorder.startCalled {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertTrue(systemAudioRecorder.startCalled)
        XCTAssertFalse(screenProvider.startedSystemAudioEnabled)
    }

    func testScreenRecordingStopsSystemAudioRecorderWhenEnabled() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let screenProvider = MockScreenRecordingProvider(
            status: .authorized,
            displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
        )
        let systemAudioRecorder = MockSystemAudioRecorder()

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            systemAudioRecorder: systemAudioRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.isSystemAudioEnabled = true
        await viewModel.refreshScreenRecordingOptions()
        viewModel.refreshDeviceState()

        viewModel.startRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        viewModel.stopRecording()

        XCTAssertTrue(systemAudioRecorder.stopCalled)
    }

    func testScreenRecordingStopCanCompleteExportAfterStopRequest() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .denied, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let screenProvider = MockScreenRecordingProvider(
            status: .authorized,
            displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
        )
        screenProvider.shouldCompleteOnStop = true

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let captureURL = tempRoot.appendingPathComponent("screen-capture-temp.mov")
        try? Data([0x00]).write(to: captureURL)
        let microphoneRecorder = MockMicrophoneAudioRecorder()

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            microphoneAudioRecorder: microphoneRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: tempRoot),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectedRecordingSource = .screen
        viewModel.refreshDeviceState()
        await viewModel.refreshScreenRecordingOptions()

        viewModel.startRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(screenProvider.isStartPending)

        viewModel.stopRecording()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(screenProvider.stopCalled)
        XCTAssertFalse(screenProvider.isStartPending)
    }

    func testAudioOnlyRecordingUsesMicrophoneAndSystemAudioRecorders() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .denied, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let microphoneRecorder = MockMicrophoneAudioRecorder()
        let systemAudioRecorder = MockSystemAudioRecorder()
        let audioExporter = MockAudioRecordingExporter()
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: MockScreenRecordingProvider(),
            systemAudioRecorder: systemAudioRecorder,
            microphoneAudioRecorder: microphoneRecorder,
            audioRecordingExporter: audioExporter,
            fileNamer: RecordingFileNamer(homeDirectory: tempRoot),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.audioOnly)
        viewModel.isSystemAudioEnabled = true
        viewModel.refreshDeviceState()

        viewModel.startRecording()
        for _ in 0..<20 where !viewModel.isRecording {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertEqual(viewModel.selectedRecordingSource, .audio)
        XCTAssertTrue(microphoneRecorder.startCalled)
        XCTAssertTrue(systemAudioRecorder.startCalled)
        XCTAssertEqual(microphoneRecorder.startedDeviceID, "mic-1")
        XCTAssertTrue(viewModel.isRecording)

        viewModel.stopRecording()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(microphoneRecorder.stopCalled)
        XCTAssertTrue(systemAudioRecorder.stopCalled)
        XCTAssertEqual(audioExporter.exportedMicrophoneURL?.path, microphoneRecorder.startedURL?.path)
        XCTAssertEqual(audioExporter.exportedSystemAudioURL?.path, systemAudioRecorder.startedURL?.path)
        XCTAssertEqual(viewModel.lastSavedURL?.pathExtension, "m4a")
        XCTAssertEqual(viewModel.completedRecording?.fileExtension, "m4a")
    }

    func testWindowSourceCanStartWithoutMicrophonePermission() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .denied]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: []
        )
        let screenProvider = MockScreenRecordingProvider(
            status: .authorized,
            windows: [ScreenWindowOption(id: "window-1", name: "Safari - Docs")]
        )

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectedRecordingSource = .window
        viewModel.refreshDeviceState()
        await viewModel.refreshScreenRecordingOptions()

        XCTAssertEqual(viewModel.selectedWindowID, "window-1")
        XCTAssertTrue(viewModel.canStartRecording)
        XCTAssertEqual(viewModel.statusText, "Yatay pencere kaydı hazır. Mikrofon ve sistem sesi kapalı.")
    }

    func testRequestingScreenPermissionCanSurfaceRestartGuidance() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let screenProvider = MockScreenRecordingProvider(status: .denied)
        screenProvider.requestResult = .grantedButRequiresRestart

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectedRecordingSource = .screen
        viewModel.refreshDeviceState()
        viewModel.requestScreenRecordingPermission()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(viewModel.screenPermissionNeedsRestart)
        XCTAssertEqual(
            viewModel.statusText,
            "Ekran kaydı izni verdiysen uygulamayı kapatıp yeniden aç. Olmazsa Sistem Ayarları > Gizlilik ve Güvenlik > Ekran Kaydı'nı kontrol et."
        )
        XCTAssertEqual(
            viewModel.permissionStatusText,
            "Ekran kaydı izni: yeniden açılış bekleniyor olabilir. Mikrofon izni: verildi. İzin verdiysen macOS değişikliği görmek için uygulamayı kapatıp yeniden açman gerekebilir."
        )
    }

    func testChoosingRecordingOutputDirectoryUpdatesStore() {
        let store = MockRecordingOutputDirectoryStore()
        let initialURL = URL(fileURLWithPath: "/tmp/Video Recorder", isDirectory: true)
        let selectedURL = URL(fileURLWithPath: "/tmp/Custom Output", isDirectory: true)
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(outputDirectory: initialURL),
            soundEffectPlayer: SoundEffectPlayer(),
            recordingOutputDirectoryStore: store,
            permissionProvider: MockMediaPermissionProvider(statuses: [:]),
            chooseOutputDirectory: { currentURL in
                XCTAssertEqual(currentURL.path, initialURL.path)
                return selectedURL
            }
        )

        viewModel.chooseRecordingOutputDirectory()

        XCTAssertEqual(viewModel.recordingOutputDirectoryURL.path, selectedURL.path)
        XCTAssertEqual(store.outputDirectoryPath, selectedURL.path)
    }

    func testRenameCompletedRecordingMovesFileAndUpdatesLastSavedURL() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let sourceURL = tempRoot.appendingPathComponent("recording.mp4")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("demo".utf8))

        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(outputDirectory: tempRoot),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )
        viewModel.lastSavedURL = sourceURL
        viewModel.completedRecording = CompletedRecordingSummary(
            url: sourceURL,
            warnings: [],
            editableName: "final-cut",
            fileExtension: "mp4"
        )

        viewModel.renameCompletedRecording()

        let renamedURL = tempRoot.appendingPathComponent("final-cut.mp4")
        XCTAssertEqual(viewModel.lastSavedURL?.path, renamedURL.path)
        XCTAssertEqual(viewModel.completedRecording?.url.path, renamedURL.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path))
    }

    func testSaveCompletedRecordingAsMovesFileToSelectedDestination() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destinationRoot = tempRoot.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        let sourceURL = tempRoot.appendingPathComponent("recording.mp4")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("demo".utf8))

        let expectedDestination = destinationRoot.appendingPathComponent("shared.mp4")
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(outputDirectory: tempRoot),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:]),
            chooseSaveDestination: { suggestedURL in
                XCTAssertEqual(suggestedURL.lastPathComponent, "recording.mp4")
                return expectedDestination
            }
        )
        viewModel.lastSavedURL = sourceURL
        viewModel.completedRecording = CompletedRecordingSummary(
            url: sourceURL,
            warnings: [],
            editableName: "recording",
            fileExtension: "mp4"
        )

        viewModel.saveCompletedRecordingAs()

        XCTAssertEqual(viewModel.lastSavedURL?.path, expectedDestination.path)
        XCTAssertEqual(viewModel.completedRecording?.url.path, expectedDestination.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedDestination.path))
    }

    func testSaveCompletedRecordingAsUsesEditedNameForSuggestedDestination() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destinationRoot = tempRoot.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        let sourceURL = tempRoot.appendingPathComponent("recording.mp4")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("demo".utf8))

        let expectedDestination = destinationRoot.appendingPathComponent("renamed.mp4")
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(outputDirectory: tempRoot),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:]),
            chooseSaveDestination: { suggestedURL in
                XCTAssertEqual(suggestedURL.lastPathComponent, "renamed.mp4")
                return expectedDestination
            }
        )
        viewModel.lastSavedURL = sourceURL
        viewModel.completedRecording = CompletedRecordingSummary(
            url: sourceURL,
            warnings: [],
            editableName: "recording",
            fileExtension: "mp4"
        )

        viewModel.saveCompletedRecordingAs(to: "renamed")

        XCTAssertEqual(viewModel.lastSavedURL?.path, expectedDestination.path)
        XCTAssertEqual(viewModel.completedRecording?.url.path, expectedDestination.path)
    }

    func testOpenCompletedRecordingUsesCompletedRecordingURL() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let completedURL = tempRoot.appendingPathComponent("completed.mp4")
        let staleLastSavedURL = tempRoot.appendingPathComponent("stale.mp4")

        var openedURL: URL?
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(outputDirectory: tempRoot),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:]),
            openURL: { openedURL = $0 }
        )
        viewModel.lastSavedURL = staleLastSavedURL
        viewModel.completedRecording = CompletedRecordingSummary(
            url: completedURL,
            warnings: [],
            editableName: "completed",
            fileExtension: "mp4"
        )

        viewModel.openCompletedRecording()

        XCTAssertEqual(openedURL?.path, completedURL.path)
    }

    func testRevealCompletedRecordingUsesCompletedRecordingURL() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let completedURL = tempRoot.appendingPathComponent("completed.mp4")
        let staleLastSavedURL = tempRoot.appendingPathComponent("stale.mp4")

        var revealedURL: URL?
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(outputDirectory: tempRoot),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:]),
            revealInFinder: { revealedURL = $0 }
        )
        viewModel.lastSavedURL = staleLastSavedURL
        viewModel.completedRecording = CompletedRecordingSummary(
            url: completedURL,
            warnings: [],
            editableName: "completed",
            fileExtension: "mp4"
        )

        viewModel.revealCompletedRecording()

        XCTAssertEqual(revealedURL?.path, completedURL.path)
    }

    func testPauseResumeDoesNothingWhenNoRecordingIsActive() {
        var soundEffectPlayer = MockSoundEffectPlayer()
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: soundEffectPlayer,
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )

        viewModel.togglePauseResume()

        XCTAssertFalse(viewModel.isPaused)
        XCTAssertEqual(soundEffectPlayer.pauseResumeCallCount, 0)
    }

    func testPauseResumeTogglesStateStatusAndSoundForVideoRecording() {
        var soundEffectPlayer = MockSoundEffectPlayer()
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: soundEffectPlayer,
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )
        viewModel.isRecording = true
        viewModel.selectedRecordingSource = .camera

        viewModel.togglePauseResume()

        XCTAssertTrue(viewModel.isPaused)
        XCTAssertEqual(viewModel.statusText, "Kayıt duraklatıldı")

        viewModel.togglePauseResume()

        XCTAssertFalse(viewModel.isPaused)
        XCTAssertEqual(viewModel.statusText, "Kayıt yapılıyor")
        XCTAssertEqual(soundEffectPlayer.pauseResumeCallCount, 2)
    }

    func testPauseStartsPauseRangeBeforePlayingTransitionSound() {
        let soundEffectPlayer = MockSoundEffectPlayer()
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: soundEffectPlayer,
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )
        viewModel.isRecording = true
        viewModel.selectedRecordingSource = .camera
        var pausedWhenSoundPlayed = false
        soundEffectPlayer.onPauseResume = {
            pausedWhenSoundPlayed = viewModel.isPaused
        }

        viewModel.togglePauseResume()

        XCTAssertTrue(pausedWhenSoundPlayed)
    }

    func testResumeKeepsPauseRangeOpenUntilTransitionSoundFinishes() async throws {
        let soundEffectPlayer = MockSoundEffectPlayer()
        soundEffectPlayer.pauseResumeDurations = [0, 0.02]
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: soundEffectPlayer,
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )
        viewModel.isRecording = true
        viewModel.selectedRecordingSource = .camera

        viewModel.togglePauseResume()
        viewModel.togglePauseResume()

        XCTAssertTrue(viewModel.isPaused)

        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(viewModel.isPaused)
        XCTAssertEqual(viewModel.statusText, "Kayıt yapılıyor")
    }

    func testPauseResumeUsesAudioStatusForAudioRecording() {
        var soundEffectPlayer = MockSoundEffectPlayer()
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: soundEffectPlayer,
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )
        viewModel.isRecording = true
        viewModel.selectedRecordingSource = .audio

        viewModel.togglePauseResume()

        XCTAssertTrue(viewModel.isPaused)
        XCTAssertEqual(viewModel.statusText, "Ses kaydı duraklatıldı")
    }

    func testRenameCompletedRecordingCollisionKeepsSummaryAndReportsError() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let sourceURL = tempRoot.appendingPathComponent("recording.mp4")
        let collisionURL = tempRoot.appendingPathComponent("final-cut.mp4")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("demo".utf8))
        FileManager.default.createFile(atPath: collisionURL.path, contents: Data("existing".utf8))

        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(outputDirectory: tempRoot),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )
        viewModel.lastSavedURL = sourceURL
        viewModel.completedRecording = CompletedRecordingSummary(
            url: sourceURL,
            warnings: [],
            editableName: "recording",
            fileExtension: "mp4"
        )

        viewModel.renameCompletedRecording(to: "final-cut")

        XCTAssertEqual(viewModel.lastSavedURL?.path, sourceURL.path)
        XCTAssertEqual(viewModel.completedRecording?.url.path, sourceURL.path)
        XCTAssertEqual(viewModel.completedRecording?.editableName, "recording")
        XCTAssertNotNil(viewModel.errorText)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    func testSaveCompletedRecordingAsCollisionKeepsSummaryAndReportsError() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let sourceURL = tempRoot.appendingPathComponent("recording.mp4")
        let collisionURL = tempRoot.appendingPathComponent("shared.mp4")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("demo".utf8))
        FileManager.default.createFile(atPath: collisionURL.path, contents: Data("existing".utf8))

        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(outputDirectory: tempRoot),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:]),
            chooseSaveDestination: { _ in collisionURL }
        )
        viewModel.lastSavedURL = sourceURL
        viewModel.completedRecording = CompletedRecordingSummary(
            url: sourceURL,
            warnings: [],
            editableName: "recording",
            fileExtension: "mp4"
        )

        viewModel.saveCompletedRecordingAs(to: "shared")

        XCTAssertEqual(viewModel.lastSavedURL?.path, sourceURL.path)
        XCTAssertEqual(viewModel.completedRecording?.url.path, sourceURL.path)
        XCTAssertEqual(viewModel.completedRecording?.editableName, "recording")
        XCTAssertNotNil(viewModel.errorText)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    func testStartSoundPlaysBeforeSystemAudioCaptureStarts() async {
        let events = RecordingStartEventLog()
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "camera-1", name: "Camera")],
            microphones: [InputDevice(id: "mic-1", name: "Microphone")]
        )
        let systemAudioRecorder = MockSystemAudioRecorder()
        systemAudioRecorder.onStart = { events.append("system-audio-start") }
        var soundEffectPlayer = MockSoundEffectPlayer()
        soundEffectPlayer.onStart = { events.append("start-sound") }

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: MockScreenRecordingProvider(),
            systemAudioRecorder: systemAudioRecorder,
            fileNamer: RecordingFileNamer(outputDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)),
            soundEffectPlayer: soundEffectPlayer,
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .authorized, .audio: .authorized])
        )
        await viewModel.setup()
        viewModel.selectedRecordingSource = .camera
        viewModel.isSystemAudioEnabled = true

        viewModel.startRecording()
        for _ in 0..<20 where events.values.count < 2 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(events.values.prefix(2), ["start-sound", "system-audio-start"])
    }

    func testPermissionHubShowsRequestActionForUndeterminedMicrophone() async throws {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .authorized])
        )

        await viewModel.setup()

        let microphoneItem = try XCTUnwrap(viewModel.permissionHubItems.first(where: { $0.id == .microphone }))
        XCTAssertEqual(microphoneItem.primaryAction, .request)
        XCTAssertFalse(microphoneItem.isSatisfied)
        XCTAssertTrue(microphoneItem.isRequired)
    }

    func testPermissionHubShowsSettingsActionForDeniedCamera() async throws {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .denied, .audio: .authorized])
        )

        await viewModel.setup()

        let cameraItem = try XCTUnwrap(viewModel.permissionHubItems.first(where: { $0.id == .camera }))
        XCTAssertEqual(cameraItem.primaryAction, .openSettings)
        XCTAssertFalse(cameraItem.isSatisfied)
        XCTAssertFalse(cameraItem.isRequired)
    }

    func testPermissionHubShowsRestartActionWhenScreenPermissionNeedsRestart() async throws {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let screenProvider = MockScreenRecordingProvider(status: .denied)
        screenProvider.requestResult = .grantedButRequiresRestart

        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: screenProvider,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.requestScreenRecordingPermission()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let screenItem = try XCTUnwrap(viewModel.permissionHubItems.first(where: { $0.id == .screenRecording }))
        XCTAssertEqual(screenItem.primaryAction, .restartApp)
        XCTAssertEqual(screenItem.secondaryAction, .openSettings)
        XCTAssertTrue(screenItem.isSatisfied)
        XCTAssertTrue(viewModel.canProceedPastOnboarding)
    }

    func testPermissionHubScreenDetailMentionsSystemAudioWhenEnabled() async throws {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(status: .denied),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .authorized, .audio: .authorized])
        )

        await viewModel.setup()
        viewModel.selectPreset(.audioOnly)
        viewModel.isSystemAudioEnabled = true

        let screenItem = try XCTUnwrap(viewModel.permissionHubItems.first(where: { $0.id == .screenRecording }))
        XCTAssertTrue(screenItem.detail.localizedCaseInsensitiveContains("sistem sesi"))
    }

    func testCanProceedPastOnboardingAllowsMissingOptionalCamera() async {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.audio: .authorized])
        )

        await viewModel.setup()

        XCTAssertTrue(viewModel.canProceedPastOnboarding)
        XCTAssertFalse(viewModel.hasBlockingPermissionIssue)
    }
}

private final class RecordingStartEventLog {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

private final class MockSoundEffectPlayer: SoundEffectPlaying {
    var onStart: () -> Void = {}
    var onPauseResume: () -> Void = {}
    var pauseResumeDurations: [TimeInterval] = [0]
    var pauseResumeCallCount = 0

    func playStart() -> TimeInterval {
        onStart()
        return 0
    }

    func playStop() -> TimeInterval { 0 }
    func playPauseResume() -> TimeInterval {
        pauseResumeCallCount += 1
        onPauseResume()
        guard !pauseResumeDurations.isEmpty else { return 0 }
        return pauseResumeDurations.removeFirst()
    }
}

private final class MockAudioRecordingExporter: AudioRecordingExporting {
    private(set) var exportedMicrophoneURL: URL?
    private(set) var exportedSystemAudioURL: URL?
    private(set) var exportedDestinationURL: URL?

    func export(
        microphoneURL: URL?,
        systemAudioURL: URL?,
        to destinationURL: URL,
        microphoneVolume: Float,
        systemAudioVolume: Float,
        pauseTimeline: RecordingPauseTimeline
    ) async throws -> URL {
        exportedMicrophoneURL = microphoneURL
        exportedSystemAudioURL = systemAudioURL
        exportedDestinationURL = destinationURL
        try Data("audio".utf8).write(to: destinationURL)
        return destinationURL
    }
}

private final class MockFrameCoachSettingsStore: FrameCoachSettingsStoring {
    var speechMode: FrameCoachSpeechMode = .automatic
    var feedbackFrequency: FrameCoachFeedbackFrequency = .balanced
    var repeatInterval: FrameCoachRepeatInterval = .medium
    var showsOnScreenText = true
}

private final class MockRecordingOutputDirectoryStore: RecordingOutputDirectoryStoring {
    var outputDirectoryPath: String?
}

private final class MockLastRecordingConfigurationStore: LastRecordingConfigurationStoring {
    var configuration: LastRecordingConfiguration?
}

private final class RecorderCaptureStub: CaptureRecording {
    let session = AVCaptureSession()
    var cameras: [InputDevice]
    var microphones: [InputDevice]
    private(set) var configuredVideoDeviceID: String?
    private(set) var configuredAudioDeviceID: String?
    private(set) var configuredMode: RecordingMode?
    private(set) var startCalled = false
    private(set) var stopCalled = false
    private(set) var startedURL: URL?
    private(set) var previewFramesEnabled = false
    private(set) var previewFrameHandler: PreviewFrameHandler?
    var shouldCompleteOnStop = true
    private var completion: ((Result<URL, Error>) -> Void)?

    init(cameras: [InputDevice] = [], microphones: [InputDevice] = []) {
        self.cameras = cameras
        self.microphones = microphones
    }

    func cameraDevices() -> [InputDevice] { cameras }
    func microphoneDevices() -> [InputDevice] { microphones }

    func configure(videoDeviceID: String, audioDeviceID: String, mode: RecordingMode) async throws {
        configuredVideoDeviceID = videoDeviceID
        configuredAudioDeviceID = audioDeviceID
        configuredMode = mode
    }

    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) async throws {
        startCalled = true
        startedURL = url
        self.completion = completion
    }

    func stopRecording() {
        stopCalled = true
        if shouldCompleteOnStop, let startedURL {
            completion?(.success(startedURL))
        }
    }

    func startSessionInBackground() {}
    func setPreviewFrameHandler(_ handler: PreviewFrameHandler?) { previewFrameHandler = handler }
    func setPreviewFramesEnabled(_ isEnabled: Bool) { previewFramesEnabled = isEnabled }
}

private struct RecorderPermissionsStub: MediaPermissionProviding {
    var statuses: [AVMediaType: AVAuthorizationStatus]

    func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        statuses[mediaType] ?? .notDetermined
    }

    func requestAccess(for mediaType: AVMediaType) async -> Bool {
        statuses[mediaType] == .authorized
    }
}

// MARK: - RecordingStatus tests
final class RecordingStatusTests: XCTestCase {
    func test_ready_label() {
        XCTAssertEqual(RecordingStatus.ready.label, "Hazır")
    }

    func test_recording_label() {
        XCTAssertEqual(RecordingStatus.recording.label, "Kayıt")
    }

    func test_paused_label() {
        XCTAssertEqual(RecordingStatus.paused.label, "Duraklatıldı")
    }

    func test_preparing_label() {
        XCTAssertEqual(RecordingStatus.preparing.label, "Hazırlanıyor")
    }

    func test_dotColors_are_distinct() {
        // All three active-state colors should be distinct objects
        let readyColor  = RecordingStatus.ready.dotColor
        let recordColor = RecordingStatus.recording.dotColor
        let pauseColor  = RecordingStatus.paused.dotColor
        XCTAssertNotEqual(readyColor, recordColor)
        XCTAssertNotEqual(readyColor, pauseColor)
        XCTAssertNotEqual(recordColor, pauseColor)
    }
}

// MARK: - RecordButtonState tests
final class RecordButtonStateTests: XCTestCase {
    func test_states_are_distinct() {
        XCTAssertNotEqual(RecordButtonState.ready,     .recording)
        XCTAssertNotEqual(RecordButtonState.ready,     .paused)
        XCTAssertNotEqual(RecordButtonState.ready,     .preparing)
        XCTAssertNotEqual(RecordButtonState.recording, .paused)
        XCTAssertNotEqual(RecordButtonState.recording, .preparing)
        XCTAssertNotEqual(RecordButtonState.paused,    .preparing)
    }

    func test_countdown_equality() {
        XCTAssertEqual(RecordButtonState.countdown, .countdown)
        XCTAssertNotEqual(RecordButtonState.countdown, .ready)
    }
}

// MARK: - FMModeSelector mapping tests
final class FMModeSelectorTests: XCTestCase {
    typealias PM  = FMModeSelector.PrimaryMode
    typealias ORI = FMModeSelector.Orientation

    // compose: PrimaryMode + Orientation → RecordingPreset

    func test_compose_cameraHorizontal() {
        XCTAssertEqual(FMModeSelector.compose(primaryMode: .camera, orientation: .horizontal), .horizontalCamera)
    }
    func test_compose_cameraVertical() {
        XCTAssertEqual(FMModeSelector.compose(primaryMode: .camera, orientation: .vertical), .verticalCamera)
    }
    func test_compose_screenHorizontal() {
        XCTAssertEqual(FMModeSelector.compose(primaryMode: .screen, orientation: .horizontal), .horizontalScreen)
    }
    func test_compose_screenVertical() {
        XCTAssertEqual(FMModeSelector.compose(primaryMode: .screen, orientation: .vertical), .verticalScreen)
    }
    func test_compose_screenCamera_alwaysHorizontalScreen() {
        XCTAssertEqual(FMModeSelector.compose(primaryMode: .screenCamera, orientation: .horizontal), .horizontalScreen)
        XCTAssertEqual(FMModeSelector.compose(primaryMode: .screenCamera, orientation: .vertical),   .horizontalScreen)
    }
    func test_compose_audio() {
        XCTAssertEqual(FMModeSelector.compose(primaryMode: .audio, orientation: .horizontal), .audioOnly)
    }

    // decompose: RecordingPreset + overlayEnabled → (PrimaryMode, Orientation)

    func test_decompose_horizontalCamera() {
        let (pm, ori) = FMModeSelector.decompose(preset: .horizontalCamera, overlayEnabled: false)
        XCTAssertEqual(pm, .camera); XCTAssertEqual(ori, .horizontal)
    }
    func test_decompose_verticalCamera() {
        let (pm, ori) = FMModeSelector.decompose(preset: .verticalCamera, overlayEnabled: false)
        XCTAssertEqual(pm, .camera); XCTAssertEqual(ori, .vertical)
    }
    func test_decompose_horizontalScreen_noOverlay() {
        let (pm, ori) = FMModeSelector.decompose(preset: .horizontalScreen, overlayEnabled: false)
        XCTAssertEqual(pm, .screen); XCTAssertEqual(ori, .horizontal)
    }
    func test_decompose_horizontalScreen_withOverlay() {
        let (pm, ori) = FMModeSelector.decompose(preset: .horizontalScreen, overlayEnabled: true)
        XCTAssertEqual(pm, .screenCamera); XCTAssertEqual(ori, .horizontal)
    }
    func test_decompose_verticalScreen() {
        let (pm, ori) = FMModeSelector.decompose(preset: .verticalScreen, overlayEnabled: false)
        XCTAssertEqual(pm, .screen); XCTAssertEqual(ori, .vertical)
    }
    func test_decompose_audioOnly() {
        let (pm, ori) = FMModeSelector.decompose(preset: .audioOnly, overlayEnabled: false)
        XCTAssertEqual(pm, .audio); XCTAssertEqual(ori, .horizontal)
    }
}
