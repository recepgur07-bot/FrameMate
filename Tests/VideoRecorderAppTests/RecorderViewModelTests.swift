import XCTest
import AVFoundation
@testable import FrameMate

@MainActor
final class RecorderViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "recording.lastConfiguration")
        UserDefaults.standard.removeObject(forKey: "recording.countdown")
        UserDefaults.standard.removeObject(forKey: "recording.maxDuration")
        UserDefaults.standard.removeObject(forKey: "recording.sound.commandReceived")
        UserDefaults.standard.removeObject(forKey: "recording.sound.start")
        UserDefaults.standard.removeObject(forKey: "recording.sound.stop")
        UserDefaults.standard.removeObject(forKey: "recording.sound.pauseResume")
        UserDefaults.standard.removeObject(forKey: "appAccess.trialStartDate")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "recording.lastConfiguration")
        UserDefaults.standard.removeObject(forKey: "recording.countdown")
        UserDefaults.standard.removeObject(forKey: "recording.maxDuration")
        UserDefaults.standard.removeObject(forKey: "recording.sound.commandReceived")
        UserDefaults.standard.removeObject(forKey: "recording.sound.start")
        UserDefaults.standard.removeObject(forKey: "recording.sound.stop")
        UserDefaults.standard.removeObject(forKey: "recording.sound.pauseResume")
        UserDefaults.standard.removeObject(forKey: "appAccess.trialStartDate")
        super.tearDown()
    }

    private func waitForAudioCompletion(_ vm: RecorderViewModel) async {
        for _ in 0..<200 where vm.completedRecording == nil {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
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

    func testAudioShortcutUsesConfiguredCountdownBeforeStarting() async {
        let microphoneRecorder = MockMicrophoneAudioRecorder()
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(
                microphones: [InputDevice(id: "mic-1", name: "Built-in Mic")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(),
            microphoneAudioRecorder: microphoneRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.audio: .authorized])
        )

        await viewModel.setup()
        viewModel.recordingCountdown = .three
        viewModel.toggleAudioRecording()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.selectedRecordingSource, .audio)
        XCTAssertTrue(viewModel.isCountingDown)
        XCTAssertFalse(microphoneRecorder.startCalled)
        XCTAssertFalse(viewModel.isRecording)
    }

    func testAudioShortcutCancelsAudioCountdownWhenPressedAgain() async {
        let microphoneRecorder = MockMicrophoneAudioRecorder()
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(
                microphones: [InputDevice(id: "mic-1", name: "Built-in Mic")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(),
            microphoneAudioRecorder: microphoneRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.audio: .authorized])
        )

        await viewModel.setup()
        viewModel.recordingCountdown = .three
        viewModel.toggleAudioRecording()
        viewModel.toggleAudioRecording()

        XCTAssertEqual(viewModel.countdownRemaining, 0)
        XCTAssertFalse(viewModel.isCountingDown)
        XCTAssertFalse(microphoneRecorder.startCalled)
        XCTAssertFalse(viewModel.isRecording)
    }

    func testDirectStartDoesNotBeginScreenRecordingWithoutScreenPermission() async {
        let screenProvider = MockScreenRecordingProvider(
            status: .denied,
            displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
        )
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: screenProvider,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .denied, .audio: .denied])
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.selectScreenCaptureSource(.screen)
        viewModel.refreshDeviceState()

        viewModel.startRecording()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(screenProvider.startedTarget)
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertFalse(viewModel.isPreparingRecording)
        XCTAssertEqual(viewModel.statusText, "Ekran kaydı için macOS ekran kaydı izni gerekli.")
    }

    func testGlobalToggleDoesNotBeginCountdownWhenSelectedModeCannotStart() async {
        let screenProvider = MockScreenRecordingProvider(
            status: .denied,
            displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
        )
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: screenProvider,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .denied, .audio: .denied])
        )

        await viewModel.setup()
        viewModel.recordingCountdown = .three
        viewModel.selectPreset(.horizontalScreen)
        viewModel.selectScreenCaptureSource(.screen)
        viewModel.refreshDeviceState()

        viewModel.toggleRecording()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.countdownRemaining, 0)
        XCTAssertNil(screenProvider.startedTarget)
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertEqual(viewModel.statusText, "Ekran kaydı için macOS ekran kaydı izni gerekli.")
    }

    func testAudioShortcutDoesNotStartWhenMicrophonePermissionIsDenied() async {
        let microphoneRecorder = MockMicrophoneAudioRecorder()
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(
                microphones: [InputDevice(id: "mic-1", name: "Built-in Mic")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(),
            microphoneAudioRecorder: microphoneRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.audio: .denied])
        )

        await viewModel.setup()
        viewModel.toggleAudioRecording()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(microphoneRecorder.startCalled)
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertFalse(viewModel.isPreparingRecording)
        XCTAssertNotEqual(viewModel.statusText, "Ses kaydı yapılıyor")
    }

    func testAccessibilitySetupSummaryForVerticalCameraDescribesSelectedInputs() async {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(
                cameras: [InputDevice(id: "cam-1", name: "FaceTime HD")],
                microphones: [InputDevice(id: "mic-1", name: "MacBook Mikrofonu")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .authorized, .audio: .authorized])
        )

        await viewModel.setup()
        viewModel.selectPreset(.verticalCamera)
        viewModel.selectedCameraID = "cam-1"
        viewModel.selectedMicrophoneID = "mic-1"
        viewModel.isSystemAudioEnabled = false

        XCTAssertEqual(
            viewModel.accessibilitySetupSummary,
            "Kamera FaceTime HD, mikrofon MacBook Mikrofonu, sistem sesi kapalı, kadraj koçu kapalı."
        )
    }

    func testAccessibilitySetupSummaryUsesFrameCoachToggleInsteadOfAutoReframeToggle() async {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(
                cameras: [InputDevice(id: "cam-1", name: "FaceTime HD")],
                microphones: [InputDevice(id: "mic-1", name: "MacBook Mikrofonu")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .authorized, .audio: .authorized])
        )

        await viewModel.setup()
        viewModel.selectPreset(.verticalCamera)
        viewModel.selectedCameraID = "cam-1"
        viewModel.selectedMicrophoneID = "mic-1"
        viewModel.isAutoReframeEnabled = true
        viewModel.isFrameCoachEnabled = false

        XCTAssertTrue(viewModel.accessibilitySetupSummary.contains("kadraj koçu kapalı"))

        viewModel.isFrameCoachEnabled = true

        XCTAssertTrue(viewModel.accessibilitySetupSummary.contains("kadraj koçu açık"))
    }

    func testAccessibilitySetupSummaryForHorizontalScreenDescribesSourceAndEnabledOptions() async {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(
                microphones: [InputDevice(id: "mic-1", name: "MacBook Mikrofonu")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(
                status: .authorized,
                displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Retina Display")],
                windows: []
            ),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.audio: .authorized])
        )

        await viewModel.setup()
        viewModel.selectPreset(RecordingPreset.horizontalScreen)
        viewModel.selectScreenCaptureSource(ScreenCaptureSource.screen)
        viewModel.selectedDisplayID = "display-1"
        viewModel.selectedMicrophoneID = "mic-1"
        viewModel.isSystemAudioEnabled = true
        viewModel.isCursorHighlightEnabled = true

        XCTAssertEqual(
            viewModel.accessibilitySetupSummary,
            "Kaynak tam ekran, ekran seçilmedi, mikrofon MacBook Mikrofonu, sistem sesi açık, imleç vurgusu açık."
        )
    }

    func testAnnounceCurrentSettingsFallsBackToAppVoiceWhenVoiceOverIsNotRunning() async {
        let speaker = MockInstructionSpeaker()
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(
                cameras: [InputDevice(id: "cam-1", name: "FaceTime HD")],
                microphones: [InputDevice(id: "mic-1", name: "MacBook Mikrofonu")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .authorized, .audio: .authorized]),
            speechCuePlayer: SpeechCuePlayer(speaker: speaker, announcer: nil, isVoiceOverEnabled: { false })
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalCamera)
        viewModel.selectedCameraID = "cam-1"
        viewModel.selectedMicrophoneID = "mic-1"
        viewModel.isSystemAudioEnabled = false
        viewModel.isFrameCoachEnabled = false

        viewModel.announceCurrentSettings()

        XCTAssertEqual(
            speaker.spokenTexts,
            ["Mod Yatay video kaydı. Kamera FaceTime HD, mikrofon MacBook Mikrofonu, sistem sesi kapalı, kadraj koçu kapalı."]
        )
    }

    func testAnnounceCurrentSettingsUsesVoiceOverWhenRunning() async {
        let speaker = MockInstructionSpeaker()
        let announcer = MockInstructionAnnouncer()
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(
                cameras: [InputDevice(id: "cam-1", name: "FaceTime HD")],
                microphones: [InputDevice(id: "mic-1", name: "MacBook Mikrofonu")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .authorized, .audio: .authorized]),
            speechCuePlayer: SpeechCuePlayer(speaker: speaker, announcer: announcer, isVoiceOverEnabled: { true })
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalCamera)
        viewModel.selectedCameraID = "cam-1"
        viewModel.selectedMicrophoneID = "mic-1"
        viewModel.isSystemAudioEnabled = false

        viewModel.announceCurrentSettings()

        XCTAssertTrue(speaker.spokenTexts.isEmpty)
        XCTAssertEqual(
            announcer.announcements,
            ["Mod Yatay video kaydı. Kamera FaceTime HD, mikrofon MacBook Mikrofonu, sistem sesi kapalı, kadraj koçu kapalı."]
        )
    }

    func testAnnounceCurrentSettingsIsFullyEnglishWhenTestLanguageIsEnglish() async throws {
        try XCTSkipUnless(
            Locale.current.language.languageCode?.identifier == "en",
            "English-only localization regression runs with -testLanguage en."
        )

        let speaker = MockInstructionSpeaker()
        let announcer = MockInstructionAnnouncer()
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(
                cameras: [InputDevice(id: "cam-1", name: "FaceTime HD Camera")],
                microphones: [InputDevice(id: "mic-1", name: "External Microphone")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .authorized, .audio: .authorized]),
            speechCuePlayer: SpeechCuePlayer(speaker: speaker, announcer: announcer, isVoiceOverEnabled: { true })
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalCamera)
        viewModel.selectedCameraID = "cam-1"
        viewModel.selectedMicrophoneID = "mic-1"
        viewModel.isSystemAudioEnabled = true

        viewModel.announceCurrentSettings()

        XCTAssertTrue(speaker.spokenTexts.isEmpty)
        let announcement = try XCTUnwrap(announcer.announcements.first)
        XCTAssertEqual(
            announcement,
            "Mode Horizontal video recording. Camera FaceTime HD Camera, microphone External Microphone, system audio on, Frame Coach off."
        )
        XCTAssertFalse(announcement.contains("Yatay"))
        XCTAssertFalse(announcement.contains("Kamera "))
        XCTAssertFalse(announcement.contains("mikrofon "))
        XCTAssertFalse(announcement.contains("kadraj"))
    }

    func testScreenRecordingReadinessIsFullyEnglishWhenTestLanguageIsEnglish() async throws {
        try XCTSkipUnless(
            Locale.current.language.languageCode?.identifier == "en",
            "English-only localization regression runs with -testLanguage en."
        )

        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(
                cameras: [InputDevice(id: "cam-1", name: "FaceTime HD Camera")],
                microphones: [InputDevice(id: "mic-1", name: "External Microphone")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(
                displays: [ScreenDisplayOption(id: "display-1", name: "Ekran 1")]
            ),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .authorized, .audio: .authorized])
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.selectScreenCaptureSource(.screen)
        viewModel.selectedDisplayID = "display-1"
        viewModel.selectedMicrophoneID = "mic-1"
        viewModel.isSystemAudioEnabled = true
        await viewModel.refreshScreenRecordingOptions()

        XCTAssertEqual(ScreenCaptureSource.screen.label, "Full Screen")
        XCTAssertEqual(viewModel.availableDisplays.first?.localizedName, "Screen 1")
        XCTAssertEqual(
            viewModel.accessibilitySetupSummary,
            "source: full screen, screen 1, microphone External Microphone, system audio on, cursor highlight off."
        )
        XCTAssertEqual(
            viewModel.statusText,
            "Horizontal screen recording is ready. Microphone and system audio will be included."
        )
    }

    func testAnnounceCurrentSettingsIncludesModeSpecificMissingPermissionsAtEnd() async {
        let speaker = MockInstructionSpeaker()
        let announcer = MockInstructionAnnouncer()
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(
                cameras: [InputDevice(id: "cam-1", name: "FaceTime HD")],
                microphones: [InputDevice(id: "mic-1", name: "MacBook Mikrofonu")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(status: .denied),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .denied, .audio: .authorized]),
            speechCuePlayer: SpeechCuePlayer(speaker: speaker, announcer: announcer, isVoiceOverEnabled: { true })
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.selectScreenCaptureSource(.window)
        viewModel.selectedWindowID = "window-1"
        viewModel.selectedMicrophoneID = "mic-1"
        viewModel.isScreenCameraOverlayEnabled = true

        viewModel.announceCurrentSettings()

        XCTAssertTrue(speaker.spokenTexts.isEmpty)
        XCTAssertEqual(
            announcer.announcements,
            ["Mod Yatay pencere kaydı. Kaynak pencere, pencere seçilmedi, mikrofon MacBook Mikrofonu, sistem sesi kapalı, imleç vurgusu kapalı, kamera kutusu açık. Eksik izinler: ekran kaydı, kamera."]
        )
    }

    func testAnnounceCurrentSettingsIncludesKeyboardShortcutAccessibilityWarning() async {
        let speaker = MockInstructionSpeaker()
        let announcer = MockInstructionAnnouncer()
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(
                microphones: [InputDevice(id: "mic-1", name: "MacBook Mikrofonu")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(status: .authorized),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.audio: .authorized]),
            isAccessibilityPermissionGranted: { false },
            openURL: { _ in },
            speechCuePlayer: SpeechCuePlayer(speaker: speaker, announcer: announcer, isVoiceOverEnabled: { true })
        )

        await viewModel.setup()
        viewModel.selectPreset(RecordingPreset.horizontalScreen)
        viewModel.selectScreenCaptureSource(ScreenCaptureSource.screen)
        viewModel.isSystemAudioEnabled = false
        viewModel.isCursorHighlightEnabled = false
        viewModel.isKeyboardShortcutOverlayEnabled = true
        viewModel.isScreenCameraOverlayEnabled = true

        viewModel.announceCurrentSettings()

        XCTAssertTrue(speaker.spokenTexts.isEmpty)
        XCTAssertEqual(
            announcer.announcements,
            ["Mod Yatay ekran kaydı. Kaynak tam ekran, ekran seçilmedi, mikrofon MacBook Mikrofonu, sistem sesi kapalı, imleç vurgusu kapalı, klavye kısayolları açık, kamera kutusu açık. Eksik izinler: kamera. Ekran kaydında klavye kısayollarını göstermek ve Cmd+I ayar duyurusunu güvenilir almak için Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik'ten FrameMate'e izin ver."]
        )
    }

    func testKeyboardShortcutAccessibilityWarningShownWhenOverlayEnabledWithoutPermission() async {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(status: .authorized),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:]),
            isAccessibilityPermissionGranted: { false },
            openURL: { _ in }
        )

        await viewModel.setup()
        viewModel.selectPreset(RecordingPreset.horizontalScreen)
        viewModel.isKeyboardShortcutOverlayEnabled = true

        XCTAssertEqual(
            viewModel.keyboardShortcutAccessibilityWarning,
            "Ekran kaydında klavye kısayollarını göstermek ve Cmd+I ayar duyurusunu güvenilir almak için Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik'ten FrameMate'e izin ver."
        )
    }

    func testOpeningAccessibilitySettingsRequestsSystemPromptFirst() async {
        var didRequestPrompt = false
        var openedURL: URL?
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(status: .authorized),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            lastRecordingConfigurationStore: MockLastRecordingConfigurationStore(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:]),
            isAccessibilityPermissionGranted: { false },
            requestAccessibilityPermissionPrompt: { didRequestPrompt = true },
            openURL: { openedURL = $0 }
        )

        await viewModel.setup()
        viewModel.openAccessibilitySettings()

        XCTAssertTrue(didRequestPrompt)
        XCTAssertEqual(openedURL?.absoluteString, "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func testEnablingKeyboardShortcutOverlayRequestsAccessibilityPromptWhenMissing() async {
        var didRequestPrompt = false
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(status: .authorized),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            lastRecordingConfigurationStore: MockLastRecordingConfigurationStore(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:]),
            isAccessibilityPermissionGranted: { false },
            requestAccessibilityPermissionPrompt: { didRequestPrompt = true },
            openURL: { _ in }
        )

        await viewModel.setup()
        viewModel.isKeyboardShortcutOverlayEnabled = true

        XCTAssertTrue(didRequestPrompt)
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
        XCTAssertFalse(viewModel.isKeyboardShortcutOverlayEnabled)
        XCTAssertFalse(viewModel.isAutoReframeEnabled)
        XCTAssertTrue(viewModel.isFrameCoachEnabled)
        XCTAssertEqual(viewModel.selectedCameraID, "cam-2")
        XCTAssertEqual(viewModel.selectedMicrophoneID, "mic-2")
    }

    func testRestoredKeyboardShortcutOverlayStaysDisabledForRelease() async {
        let store = MockLastRecordingConfigurationStore()
        store.configuration = LastRecordingConfiguration(
            selectedPreset: .horizontalScreen,
            selectedScreenCaptureSource: .screen,
            isScreenCameraOverlayEnabled: false,
            isSystemAudioEnabled: false,
            isCursorHighlightEnabled: true,
            isKeyboardShortcutOverlayEnabled: true,
            isAutoReframeEnabled: false,
            isFrameCoachEnabled: false,
            selectedCameraID: "",
            selectedMicrophoneID: "",
            selectedDisplayID: "display-1",
            selectedWindowID: ""
        )
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            lastRecordingConfigurationStore: store,
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )

        await viewModel.setup()

        XCTAssertFalse(viewModel.isKeyboardShortcutOverlayEnabled)
        XCTAssertTrue(viewModel.isCursorHighlightEnabled)
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
                isKeyboardShortcutOverlayEnabled: false,
                isAutoReframeEnabled: false,
                isFrameCoachEnabled: true,
                selectedCameraID: "cam-1",
                selectedMicrophoneID: "mic-1",
                selectedDisplayID: "",
                selectedWindowID: ""
            )
        )
    }

    func testSelectingVerticalScreenPresetFallsBackToHorizontalScreen() async {
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
            (.horizontalScreen, .horizontal1080p, .screen),
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
        XCTAssertEqual(RecordingPreset.audioOnly.commandKey, "3")
    }

    func testCameraPresetMatrixStartsRecorderWithExpectedMode() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        let expectations: [(RecordingPreset, RecordingMode)] = [
            (.horizontalCamera, .horizontal1080p)
        ]

        for (preset, expectedMode) in expectations {
            let recorder = RecorderCaptureStub(
                cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
                microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
            )
            let viewModel = RecorderViewModel(
                recorder: recorder,
                screenRecordingProvider: MockScreenRecordingProvider(),
                systemAudioRecorder: MockSystemAudioRecorder(),
                fileNamer: RecordingFileNamer(homeDirectory: tempRoot),
                soundEffectPlayer: MockSoundEffectPlayer(),
                permissionProvider: permissions
            )

            await viewModel.setup()
            viewModel.selectPreset(preset)
            viewModel.isSystemAudioEnabled = false
            viewModel.refreshDeviceState()

            XCTAssertTrue(viewModel.canStartRecording)

            viewModel.startRecording()
            for _ in 0..<40 where !recorder.startCalled || !viewModel.isRecording {
                try? await Task.sleep(nanoseconds: 25_000_000)
            }

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

    func testVerticalScreenPresetFallsBackToHorizontalScreenWhenSwitchingToWindowSource() async {
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
            (.horizontalScreen, .window, .horizontal1080p, .window(id: "window-1"))
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
            XCTAssertEqual(viewModel.currentPresetReadinessLabel, source == .window ? "Yatay pencere kaydı" : "Yatay ekran kaydı")
        }
    }

    func testScreenPresetMatrixStopsCleanlyAcrossOrientations() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        let expectations: [(RecordingPreset, ScreenCaptureSource)] = [
            (.horizontalScreen, .screen),
            (.horizontalScreen, .window)
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
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .authorized, .audio: .authorized])
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalCamera)
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

    func testScreenOverlayWithFrameCoachUsesSinglePreviewPreparationPath() async {
        let overlayRecorder = MockCameraOverlayRecorder()
        let viewModel = RecorderViewModel(
            recorder: RecorderCaptureStub(
                cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
                microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(
                status: .authorized,
                displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
            ),
            cameraOverlayRecorder: overlayRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: RecorderPermissionsStub(statuses: [.video: .authorized, .audio: .authorized])
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.isFrameCoachEnabled = true

        viewModel.toggleScreenCameraOverlay()
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertTrue(viewModel.showsScreenOverlayConfiguration)
        XCTAssertEqual(overlayRecorder.configureCallCount, 1)
    }

    func testEnablingFrameCoachForActiveScreenOverlayDoesNotReconfigureOverlayPreview() async {
        let overlayRecorder = MockCameraOverlayRecorder()
        let viewModel = RecorderViewModel(
            recorder: RecorderCaptureStub(
                cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
                microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(
                status: .authorized,
                displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
            ),
            cameraOverlayRecorder: overlayRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: RecorderPermissionsStub(statuses: [.video: .authorized, .audio: .authorized])
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.toggleScreenCameraOverlay()
        try? await Task.sleep(nanoseconds: 100_000_000)
        let configureCountAfterOverlayEnable = overlayRecorder.configureCallCount

        viewModel.toggleFrameCoach()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(viewModel.isFrameCoachEnabled)
        XCTAssertEqual(overlayRecorder.configureCallCount, configureCountAfterOverlayEnable)
        XCTAssertTrue(overlayRecorder.previewFramesEnabled)
    }

    func testDisablingScreenOverlayCancelsPendingPreviewStart() async {
        let overlayRecorder = MockCameraOverlayRecorder()
        overlayRecorder.configureDelayNanoseconds = 200_000_000
        var didStartConfiguring = false
        overlayRecorder.onConfigureStarted = {
            didStartConfiguring = true
        }
        let viewModel = RecorderViewModel(
            recorder: RecorderCaptureStub(
                cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
                microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(
                status: .authorized,
                displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")]
            ),
            cameraOverlayRecorder: overlayRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .authorized, .audio: .authorized])
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.toggleScreenCameraOverlay()
        for _ in 0..<40 where !didStartConfiguring {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(didStartConfiguring)

        viewModel.toggleScreenCameraOverlay()
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertTrue(overlayRecorder.stopSessionCalled)
        XCTAssertFalse(overlayRecorder.startSessionCalled)
        XCTAssertFalse(viewModel.showsScreenOverlayConfiguration)
    }

    func testScreenOverlayAddRemoveAddStartsSessionAndDoesNotCrash() async {
        let overlayRecorder = MockCameraOverlayRecorder()
        overlayRecorder.configureDelayNanoseconds = 50_000_000
        var configureCount = 0
        overlayRecorder.onConfigureStarted = { configureCount += 1 }
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
        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            cameraOverlayRecorder: overlayRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)

        // ADD
        viewModel.toggleScreenCameraOverlay()
        try? await Task.sleep(nanoseconds: 100_000_000)

        // REMOVE (while configure may still be in-flight)
        viewModel.toggleScreenCameraOverlay()
        try? await Task.sleep(nanoseconds: 10_000_000)

        // ADD again — must not crash, session must start
        viewModel.toggleScreenCameraOverlay()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(viewModel.showsScreenOverlayConfiguration)
        XCTAssertTrue(overlayRecorder.startSessionCalled, "Session must start after re-enabling overlay")
        XCTAssertGreaterThanOrEqual(configureCount, 2, "Overlay must be configured at least twice")
    }

    func testScreenOverlayAddRemoveAddRapidlyDoesNotLeaveSessionStopped() async {
        let overlayRecorder = MockCameraOverlayRecorder()
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
        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            cameraOverlayRecorder: overlayRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)

        // Rapid ADD → REMOVE → ADD without waiting
        viewModel.toggleScreenCameraOverlay()
        viewModel.toggleScreenCameraOverlay()
        viewModel.toggleScreenCameraOverlay()
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(viewModel.showsScreenOverlayConfiguration)
        XCTAssertTrue(overlayRecorder.startSessionCalled)
    }

    func testSettingScreenOverlayToSameValueDoesNotReconfigurePreview() async {
        let overlayRecorder = MockCameraOverlayRecorder()
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
        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            cameraOverlayRecorder: overlayRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)

        viewModel.setScreenCameraOverlayEnabled(true)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let configureCountAfterFirstEnable = overlayRecorder.configureCallCount

        viewModel.setScreenCameraOverlayEnabled(true)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(viewModel.showsScreenOverlayConfiguration)
        XCTAssertEqual(overlayRecorder.configureCallCount, configureCountAfterFirstEnable)
    }

    func testSelectingScreenModeStopsCameraPreviewSessionBeforeOverlayUsesCamera() async {
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
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalCamera)
        viewModel.isFrameCoachEnabled = true
        viewModel.refreshDeviceState()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(recorder.startSessionInBackgroundCalled)

        viewModel.selectPreset(.horizontalScreen)

        XCTAssertTrue(recorder.stopSessionCalled)
    }

    func testSetupDoesNotStartCameraPreviewForAutoReframeOnly() async {
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "FaceTime HD")],
            microphones: [InputDevice(id: "mic-1", name: "Built-in Mic")]
        )
        let permissions = RecorderPermissionsStub(statuses: [.video: .authorized, .audio: .authorized])
        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(viewModel.isAutoReframeEnabled)
        XCTAssertFalse(viewModel.isFrameCoachEnabled)
        XCTAssertFalse(recorder.startSessionInBackgroundCalled)
        XCTAssertFalse(recorder.previewFramesEnabled)
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
            systemAudioRecorder: MockSystemAudioRecorder(),
            microphoneAudioRecorder: MockMicrophoneAudioRecorder(),
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
        for _ in 0..<40 where overlayRecorder.startedURL == nil || !viewModel.isRecording {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertEqual(overlayRecorder.configuredCameraID, "cam-1")
        XCTAssertEqual(overlayRecorder.configuredMode, .horizontal1080p)
        XCTAssertNotNil(overlayRecorder.startedURL)

        viewModel.stopRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(overlayRecorder.stopCalled)
    }

    func testStartingScreenOverlayRecordingCancelsPendingPreviewPreparation() async {
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
        overlayRecorder.configureDelayNanoseconds = 200_000_000
        var didStartPreviewConfiguration = false
        overlayRecorder.onConfigureStarted = {
            didStartPreviewConfiguration = true
        }

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            cameraOverlayRecorder: overlayRecorder,
            systemAudioRecorder: MockSystemAudioRecorder(),
            microphoneAudioRecorder: MockMicrophoneAudioRecorder(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.toggleScreenCameraOverlay()
        for _ in 0..<40 where !didStartPreviewConfiguration {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(didStartPreviewConfiguration)

        viewModel.startRecording()
        for _ in 0..<40 where overlayRecorder.startedURL == nil || !viewModel.isRecording {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertNotNil(overlayRecorder.startedURL, viewModel.errorText ?? viewModel.statusText)
        XCTAssertTrue(viewModel.isRecording, viewModel.errorText ?? viewModel.statusText)
        XCTAssertFalse(overlayRecorder.startSessionCalled)

        viewModel.stopRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    func testScreenOverlayStartupFailureCleansStartedCompanionRecorders() async {
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
        let overlayRecorder = MockCameraOverlayRecorder()
        let microphoneRecorder = MockMicrophoneAudioRecorder()
        microphoneRecorder.startError = CaptureRecorderError.microphoneNotFound
        let cursorRecorder = MockCursorHighlightRecorder()

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            cameraOverlayRecorder: overlayRecorder,
            systemAudioRecorder: MockSystemAudioRecorder(),
            microphoneAudioRecorder: microphoneRecorder,
            cursorHighlightRecorder: cursorRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.toggleScreenCameraOverlay()
        viewModel.isCursorHighlightEnabled = true
        await viewModel.refreshScreenRecordingOptions()

        viewModel.startRecording()
        for _ in 0..<40 where overlayRecorder.startedURL == nil && viewModel.errorText == nil {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        for _ in 0..<40 where viewModel.isPreparingRecording {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertNotNil(overlayRecorder.startedURL)
        XCTAssertTrue(overlayRecorder.stopCalled)
        XCTAssertTrue(overlayRecorder.stopSessionCalled)
        XCTAssertTrue(cursorRecorder.stopCalled)
        XCTAssertNil(screenProvider.startedURL)
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertFalse(viewModel.isPreparingRecording)
    }

    func testRecordingSettingsDoNotChangeDuringActiveScreenOverlayRecording() async {
        let permissions = RecorderPermissionsStub(
            statuses: [.video: .authorized, .audio: .authorized]
        )
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "Front Camera")],
            microphones: [InputDevice(id: "mic-1", name: "USB Mic")]
        )
        let screenProvider = MockScreenRecordingProvider(
            status: .authorized,
            displays: [ScreenDisplayOption(id: "display-1", name: "Built-in Display")],
            windows: [ScreenWindowOption(id: "window-1", name: "Safari - Docs")]
        )
        let overlayRecorder = MockCameraOverlayRecorder()

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            cameraOverlayRecorder: overlayRecorder,
            systemAudioRecorder: MockSystemAudioRecorder(),
            microphoneAudioRecorder: MockMicrophoneAudioRecorder(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.selectScreenCaptureSource(.screen)
        viewModel.toggleScreenCameraOverlay()
        await viewModel.refreshScreenRecordingOptions()

        viewModel.startRecording()
        for _ in 0..<40 where overlayRecorder.startedURL == nil || !viewModel.isRecording {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertTrue(viewModel.isRecording, viewModel.errorText ?? viewModel.statusText)

        viewModel.toggleScreenCameraOverlay()
        viewModel.selectScreenCaptureSource(.window)
        viewModel.selectPreset(.audioOnly)

        XCTAssertTrue(viewModel.isScreenCameraOverlayEnabled)
        XCTAssertEqual(viewModel.selectedScreenCaptureSource, .screen)
        XCTAssertEqual(viewModel.selectedRecordingSource, .screen)
        XCTAssertEqual(viewModel.selectedPreset, .horizontalScreen)

        viewModel.stopRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(overlayRecorder.stopCalled)
        XCTAssertTrue(screenProvider.stopCalled)
        XCTAssertFalse(viewModel.isRecording)
    }

    func testRecordingSettingsDoNotChangeDuringCountdown() async {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .authorized, .audio: .authorized])
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.selectScreenCaptureSource(.screen)
        viewModel.countdownRemaining = 3

        viewModel.toggleScreenCameraOverlay()
        viewModel.selectScreenCaptureSource(.window)
        viewModel.selectPreset(.audioOnly)

        XCTAssertFalse(viewModel.isScreenCameraOverlayEnabled)
        XCTAssertEqual(viewModel.selectedScreenCaptureSource, .screen)
        XCTAssertEqual(viewModel.selectedRecordingSource, .screen)
        XCTAssertEqual(viewModel.selectedPreset, .horizontalScreen)
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
            systemAudioRecorder: MockSystemAudioRecorder(),
            microphoneAudioRecorder: MockMicrophoneAudioRecorder(),
            fileNamer: RecordingFileNamer(homeDirectory: tempRoot),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.isSystemAudioEnabled = false
        viewModel.isScreenCameraOverlayEnabled = true
        viewModel.refreshDeviceState()
        await viewModel.refreshScreenRecordingOptions()

        viewModel.startRecording()
        for _ in 0..<40 where viewModel.errorText == nil && !viewModel.isRecording {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertEqual(
            viewModel.errorText,
            "Kamera denetim merkezindeki video efektleri açık: Portre, Stüdyo Işığı. Bu efektleri kapatıp tekrar deneyin."
        )
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertFalse(viewModel.isPreparingRecording)
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
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.refreshDeviceState()
        await viewModel.refreshScreenRecordingOptions()

        viewModel.startRecording()
        for _ in 0..<40 where screenProvider.startedMicrophoneID == nil || !microphoneRecorder.startCalled {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertEqual(screenProvider.startedMicrophoneID, "", viewModel.errorText ?? viewModel.statusText)
        XCTAssertTrue(microphoneRecorder.startCalled, viewModel.errorText ?? viewModel.statusText)

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
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.isCursorHighlightEnabled = true
        viewModel.refreshDeviceState()
        await viewModel.refreshScreenRecordingOptions()

        viewModel.startRecording()
        for _ in 0..<40 where !cursorRecorder.startCalled || !viewModel.isRecording {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertTrue(cursorRecorder.startCalled, viewModel.errorText ?? viewModel.statusText)
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
            soundEffectPlayer: MockSoundEffectPlayer(),
            lastRecordingConfigurationStore: MockLastRecordingConfigurationStore(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.isKeyboardShortcutOverlayEnabled = true
        viewModel.refreshDeviceState()
        await viewModel.refreshScreenRecordingOptions()

        viewModel.startRecording()
        for _ in 0..<40 where !keyboardRecorder.startCalled || !viewModel.isRecording {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertTrue(keyboardRecorder.startCalled, viewModel.errorText ?? viewModel.statusText)

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
            "dışa aktarım tamamlandı"
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

        XCTAssertEqual(viewModel.screenRecordingPermissionStatus, .denied)
        XCTAssertEqual(viewModel.selectedDisplayID, "")
        XCTAssertFalse(viewModel.canStartRecording)
        XCTAssertEqual(viewModel.statusText, "Ekran kaydı için macOS ekran kaydı izni gerekli.")
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

        XCTAssertEqual(viewModel.screenRecordingPermissionStatus, .denied)
        XCTAssertEqual(viewModel.selectedDisplayID, "")
        XCTAssertEqual(viewModel.availableDisplays.count, 0)
        XCTAssertFalse(viewModel.canStartRecording)
        XCTAssertEqual(viewModel.statusText, "Ekran kaydı için macOS ekran kaydı izni gerekli.")
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

        XCTAssertEqual(viewModel.screenRecordingPermissionStatus, .denied)
        XCTAssertEqual(viewModel.selectedWindowID, "")
        XCTAssertEqual(viewModel.availableWindows.count, 0)
        XCTAssertFalse(viewModel.canStartRecording)
        XCTAssertEqual(viewModel.statusText, "Ekran kaydı için macOS ekran kaydı izni gerekli.")
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
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.isSystemAudioEnabled = true
        viewModel.refreshDeviceState()
        await viewModel.refreshScreenRecordingOptions()

        viewModel.startRecording()
        for _ in 0..<40 where screenProvider.startedTarget == nil || !systemAudioRecorder.startCalled || !viewModel.isRecording {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertEqual(screenProvider.startedTarget, .display(id: "display-1"), viewModel.errorText ?? viewModel.statusText)
        XCTAssertFalse(screenProvider.startedSystemAudioEnabled)
        XCTAssertTrue(systemAudioRecorder.startCalled, viewModel.errorText ?? viewModel.statusText)
        XCTAssertTrue(viewModel.isRecording, viewModel.errorText ?? viewModel.statusText)

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
        viewModel.selectPreset(.horizontalCamera)
        viewModel.isSystemAudioEnabled = true
        viewModel.refreshDeviceState()

        XCTAssertEqual(
            viewModel.statusText,
            "Yatay video kaydı hazır. Mikrofon ve sistem sesi kayda eklenecek."
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
            screenRecordingProvider: MockScreenRecordingProvider(status: .authorized),
            systemAudioRecorder: systemAudioRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.isSystemAudioEnabled = true
        viewModel.refreshDeviceState()

        viewModel.startRecording()
        for _ in 0..<40 where !systemAudioRecorder.startCalled {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertTrue(systemAudioRecorder.startCalled, viewModel.errorText ?? viewModel.statusText)
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
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.selectScreenCaptureSource(.window)
        viewModel.isSystemAudioEnabled = true
        await viewModel.refreshScreenRecordingOptions()
        viewModel.refreshDeviceState()

        viewModel.startRecording()
        for _ in 0..<40 where !systemAudioRecorder.startCalled || screenProvider.startedTarget == nil {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertTrue(systemAudioRecorder.startCalled, viewModel.errorText ?? viewModel.statusText)
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
        await waitForAudioCompletion(viewModel)

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
        await waitForAudioCompletion(viewModel)

        XCTAssertTrue(microphoneRecorder.completionCalled)
        XCTAssertTrue(systemAudioRecorder.completionCalled)
        XCTAssertTrue(microphoneRecorder.stopCalled)
        XCTAssertTrue(systemAudioRecorder.stopCalled)
        XCTAssertEqual(audioExporter.exportedMicrophoneURL?.path, microphoneRecorder.startedURL?.path)
        XCTAssertEqual(audioExporter.exportedSystemAudioURL?.path, systemAudioRecorder.startedURL?.path)
        XCTAssertEqual(audioExporter.exportedDestinationURL?.pathExtension, "m4a")
        XCTAssertTrue(viewModel.didEnterAudioRecordingFinalize)
        XCTAssertTrue(viewModel.didCompleteAudioRecordingExport)
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

    func testDefaultRecordingOutputDirectoryUsesVisibleMoviesFolder() {
        let store = MockRecordingOutputDirectoryStore()
        let expectedDirectory = RecordingFileNamer().outputDirectory

        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            soundEffectPlayer: SoundEffectPlayer(),
            recordingOutputDirectoryStore: store,
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )

        XCTAssertEqual(viewModel.recordingOutputDirectoryURL.path, expectedDirectory.path)
        XCTAssertEqual(store.outputDirectoryPath, expectedDirectory.path)
    }

    func testInternalSandboxFallbackOutputDirectoryIsNotRestored() {
        let store = MockRecordingOutputDirectoryStore()
        store.outputDirectoryPath = "/Users/example/Library/Containers/com.recepgur.VideoRecorder/Data/Downloads/FrameMate"
        let defaultURL = URL(fileURLWithPath: "/tmp/Video Recorder", isDirectory: true)

        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(outputDirectory: defaultURL),
            soundEffectPlayer: SoundEffectPlayer(),
            recordingOutputDirectoryStore: store,
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )

        XCTAssertEqual(viewModel.recordingOutputDirectoryURL.path, defaultURL.path)
        XCTAssertEqual(store.outputDirectoryPath, defaultURL.path)
    }

    func testRecordingFallbackUsesVisibleMoviesFolderWhenConfiguredDirectoryCannotBeCreated() async {
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "camera-1", name: "Camera")],
            microphones: [InputDevice(id: "mic-1", name: "Microphone")]
        )
        let forbiddenDirectory = URL(
            fileURLWithPath: "/System/Library/FrameMate-\(UUID().uuidString)",
            isDirectory: true
        )
        let expectedFallbackDirectory = RecordingFileNamer().outputDirectory

        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(outputDirectory: forbiddenDirectory),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: RecorderPermissionsStub(statuses: [.video: .authorized, .audio: .authorized]),
            appAccessManager: MockAppAccessManager(
                state: AppAccessState(accessKind: .trial, trialDaysRemaining: 14, offers: [])
            )
        )
        await viewModel.setup()
        viewModel.selectedCameraID = "camera-1"
        viewModel.selectedMicrophoneID = "mic-1"

        viewModel.startRecording()

        for _ in 0..<20 where recorder.startedURL == nil {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertEqual(
            recorder.startedURL?.deletingLastPathComponent().path,
            expectedFallbackDirectory.path
        )
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
        let soundEffectPlayer = MockSoundEffectPlayer()
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

    func testPauseResumeTogglesStateStatusAndTransitionSound() {
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
        XCTAssertEqual(soundEffectPlayer.pauseResumeCallCount, 2)
    }

    func testPauseResumeUsesAudioStatusForAudioRecording() {
        let soundEffectPlayer = MockSoundEffectPlayer()
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
        let soundEffectPlayer = MockSoundEffectPlayer()
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

    func testToggleRecordingPlaysCommandSoundBeforeCountdown() async {
        let soundEffectPlayer = MockSoundEffectPlayer()
        let viewModel = RecorderViewModel(
            recorder: RecorderCaptureStub(
                cameras: [InputDevice(id: "camera-1", name: "Camera")],
                microphones: [InputDevice(id: "mic-1", name: "Microphone")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(outputDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)),
            soundEffectPlayer: soundEffectPlayer,
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .authorized, .audio: .authorized])
        )
        await viewModel.setup()
        viewModel.recordingCountdown = .three

        viewModel.toggleRecording()

        XCTAssertEqual(soundEffectPlayer.commandReceivedCallCount, 1)
        XCTAssertTrue(viewModel.isCountingDown)
        XCTAssertFalse(viewModel.isRecording)
    }

    func testRecordingCommandSoundCanBeDisabled() async {
        let soundEffectPlayer = MockSoundEffectPlayer()
        let viewModel = RecorderViewModel(
            recorder: RecorderCaptureStub(
                cameras: [InputDevice(id: "camera-1", name: "Camera")],
                microphones: [InputDevice(id: "mic-1", name: "Microphone")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(outputDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)),
            soundEffectPlayer: soundEffectPlayer,
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .authorized, .audio: .authorized])
        )
        await viewModel.setup()
        viewModel.isRecordingCommandSoundEnabled = false

        viewModel.toggleRecording()

        XCTAssertEqual(soundEffectPlayer.commandReceivedCallCount, 0)
    }

    func testNoCountdownWaitsForCommandSoundBeforeStartCue() async {
        let events = RecordingStartEventLog()
        let soundEffectPlayer = MockSoundEffectPlayer()
        soundEffectPlayer.commandReceivedDurations = [0.12]
        soundEffectPlayer.onCommandReceived = { events.append("command") }
        soundEffectPlayer.onStart = { events.append("start") }
        let viewModel = RecorderViewModel(
            recorder: RecorderCaptureStub(
                cameras: [InputDevice(id: "camera-1", name: "Camera")],
                microphones: [InputDevice(id: "mic-1", name: "Microphone")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(outputDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)),
            soundEffectPlayer: soundEffectPlayer,
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .authorized, .audio: .authorized])
        )
        await viewModel.setup()
        viewModel.selectedRecordingSource = .camera
        viewModel.selectedCameraID = "camera-1"
        viewModel.selectedMicrophoneID = "mic-1"
        viewModel.recordingCountdown = .none

        viewModel.toggleRecording()
        try? await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertFalse(viewModel.isRecording)
        XCTAssertEqual(events.values, ["command"])

        for _ in 0..<20 where !viewModel.isRecording {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertTrue(viewModel.isRecording)
        XCTAssertEqual(events.values, ["command", "start"])
    }

    func testStartSoundCanBeDisabled() async {
        let soundEffectPlayer = MockSoundEffectPlayer()
        let viewModel = RecorderViewModel(
            recorder: RecorderCaptureStub(
                cameras: [InputDevice(id: "camera-1", name: "Camera")],
                microphones: [InputDevice(id: "mic-1", name: "Microphone")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(outputDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)),
            soundEffectPlayer: soundEffectPlayer,
            permissionProvider: MockMediaPermissionProvider(statuses: [.video: .authorized, .audio: .authorized])
        )
        await viewModel.setup()
        viewModel.selectedRecordingSource = .camera
        viewModel.selectedCameraID = "camera-1"
        viewModel.selectedMicrophoneID = "mic-1"
        viewModel.isRecordingStartSoundEnabled = false

        viewModel.startRecording()
        for _ in 0..<20 where !viewModel.isRecording {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertTrue(viewModel.isRecording)
        XCTAssertEqual(soundEffectPlayer.startCallCount, 0)
    }

    func testStopSoundCanBeDisabled() {
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
        viewModel.isRecordingStopSoundEnabled = false

        viewModel.stopRecording()

        XCTAssertEqual(soundEffectPlayer.stopCallCount, 0)
    }

    func testPauseResumeSoundCanBeDisabled() {
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
        viewModel.isRecordingPauseResumeSoundEnabled = false

        viewModel.togglePauseResume()
        viewModel.togglePauseResume()

        XCTAssertEqual(soundEffectPlayer.pauseResumeCallCount, 0)
        XCTAssertFalse(viewModel.isPaused)
    }

    func testStopRecordingPlaysCommandSoundAfterCaptureStop() {
        let events = RecordingStartEventLog()
        let recorder = MockCaptureRecorder()
        recorder.onStop = { events.append("capture-stop") }
        let soundEffectPlayer = MockSoundEffectPlayer()
        soundEffectPlayer.onCommandReceived = { events.append("stop-command-sound") }
        soundEffectPlayer.onStop = { events.append("stop-sound") }
        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: soundEffectPlayer,
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )
        viewModel.isRecording = true
        viewModel.selectedRecordingSource = .camera

        viewModel.stopRecording()

        XCTAssertEqual(soundEffectPlayer.stopCallCount, 0)
        XCTAssertEqual(soundEffectPlayer.commandReceivedCallCount, 1)
        XCTAssertEqual(events.values, ["capture-stop", "stop-command-sound"])
        XCTAssertEqual(viewModel.statusText, "Kayıt durdu. Dosya hazırlanıyor")
    }

    func testAudioStopShowsPreparingStatusUntilExportCompletes() async {
        let exporter = MockAudioRecordingExporter()
        exporter.delayNanoseconds = 120_000_000
        let viewModel = RecorderViewModel(
            recorder: RecorderCaptureStub(cameras: [], microphones: [InputDevice(id: "mic-1", name: "USB Mic")]),
            screenRecordingProvider: MockScreenRecordingProvider(),
            systemAudioRecorder: MockSystemAudioRecorder(),
            microphoneAudioRecorder: MockMicrophoneAudioRecorder(),
            audioRecordingExporter: exporter,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)),
            soundEffectPlayer: MockSoundEffectPlayer(),
            lastRecordingConfigurationStore: MockLastRecordingConfigurationStore(),
            permissionProvider: RecorderPermissionsStub(statuses: [.audio: .authorized])
        )
        await viewModel.setup()
        viewModel.selectPreset(RecordingPreset.audioOnly)
        viewModel.refreshDeviceState()

        viewModel.startRecording()
        for _ in 0..<20 where !viewModel.isRecording {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        viewModel.stopRecording()
        try? await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(viewModel.statusText, "Ses dosyası hazırlanıyor")
        XCTAssertNil(viewModel.completedRecording)

        await waitForAudioCompletion(viewModel)

        XCTAssertNotNil(exporter.exportedDestinationURL)
        XCTAssertNotNil(viewModel.completedRecording)
        XCTAssertTrue(viewModel.statusText.hasPrefix("Kaydedildi:"))
    }

    func testStopSoundPlaysWhenAudioFileIsReady() async {
        let soundEffectPlayer = MockSoundEffectPlayer()
        let exporter = MockAudioRecordingExporter()
        let viewModel = RecorderViewModel(
            recorder: RecorderCaptureStub(cameras: [], microphones: [InputDevice(id: "mic-1", name: "USB Mic")]),
            screenRecordingProvider: MockScreenRecordingProvider(),
            systemAudioRecorder: MockSystemAudioRecorder(),
            microphoneAudioRecorder: MockMicrophoneAudioRecorder(),
            audioRecordingExporter: exporter,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)),
            soundEffectPlayer: soundEffectPlayer,
            lastRecordingConfigurationStore: MockLastRecordingConfigurationStore(),
            permissionProvider: RecorderPermissionsStub(statuses: [.audio: .authorized])
        )
        await viewModel.setup()
        viewModel.selectPreset(RecordingPreset.audioOnly)
        viewModel.refreshDeviceState()

        viewModel.startRecording()
        for _ in 0..<20 where !viewModel.isRecording {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        viewModel.stopRecording()
        XCTAssertEqual(soundEffectPlayer.stopCallCount, 0)

        await waitForAudioCompletion(viewModel)

        XCTAssertNotNil(exporter.exportedDestinationURL)
        XCTAssertNotNil(viewModel.completedRecording)
        XCTAssertEqual(soundEffectPlayer.stopCallCount, 1)
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
        XCTAssertEqual(microphoneItem.primaryAction.buttonTitle, "Devam")
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
        viewModel.selectPreset(.audioOnly)

        let cameraItem = try XCTUnwrap(viewModel.permissionHubItems.first(where: { $0.id == .camera }))
        XCTAssertEqual(cameraItem.primaryAction, .openSettings)
        XCTAssertTrue(cameraItem.isSatisfied)
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

    func testAudioStatusClarifiesMicrophoneIsAlreadyGrantedWhenSystemAudioNeedsScreenPermission() async {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(
                microphones: [InputDevice(id: "mic-1", name: "MacBook Mikrofonu")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(status: .denied),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.audio: .authorized])
        )

        await viewModel.setup()
        viewModel.selectPreset(.audioOnly)
        viewModel.selectedMicrophoneID = "mic-1"
        viewModel.isSystemAudioEnabled = true

        XCTAssertEqual(
            viewModel.statusText,
            "Mikrofon izni verildi. Sorun mikrofon değil; sistem sesi için macOS ekran kaydı izni gerekli."
        )
    }

    func testPermissionReadinessSummaryShowsGrantedAndMissingItems() async {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(
                microphones: [InputDevice(id: "mic-1", name: "MacBook Mikrofonu")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(status: .denied),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.audio: .authorized, .video: .notDetermined])
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)

        XCTAssertEqual(
            viewModel.permissionReadinessSummary,
            "Hazır durumu: Mikrofon tamam. Ekran kaydı eksik. Kamera şu anda gerekmiyor."
        )
    }

    func testPermissionReadinessSummaryIncludesAccessibilityWhenShortcutOverlayIsEnabled() async {
        let viewModel = RecorderViewModel(
            recorder: MockCaptureRecorder(
                microphones: [InputDevice(id: "mic-1", name: "MacBook Mikrofonu")]
            ),
            screenRecordingProvider: MockScreenRecordingProvider(status: .authorized),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [.audio: .authorized, .video: .authorized]),
            isAccessibilityPermissionGranted: { false }
        )

        await viewModel.setup()
        viewModel.selectPreset(.horizontalScreen)
        viewModel.isKeyboardShortcutOverlayEnabled = true

        XCTAssertEqual(
            viewModel.permissionReadinessSummary,
            "Hazır durumu: Mikrofon tamam. Ekran kaydı tamam. Kamera şu anda gerekmiyor. Erişilebilirlik eksik."
        )
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
        viewModel.selectPreset(.audioOnly)

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
    var onCommandReceived: () -> Void = {}
    var onStart: () -> Void = {}
    var onStop: () -> Void = {}
    var onPauseResume: () -> Void = {}
    var commandReceivedDurations: [TimeInterval] = [0]
    var pauseResumeDurations: [TimeInterval] = [0]
    var commandReceivedCallCount = 0
    var startCallCount = 0
    var pauseResumeCallCount = 0
    var stopCallCount = 0

    func playCommandReceived() -> TimeInterval {
        commandReceivedCallCount += 1
        onCommandReceived()
        guard !commandReceivedDurations.isEmpty else { return 0 }
        return commandReceivedDurations.removeFirst()
    }

    func playStart() -> TimeInterval {
        startCallCount += 1
        onStart()
        return 0
    }

    func playStop() -> TimeInterval {
        stopCallCount += 1
        onStop()
        return 0
    }
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
    var delayNanoseconds: UInt64 = 0

    func export(
        microphoneURL: URL?,
        systemAudioURL: URL?,
        to destinationURL: URL,
        microphoneVolume: Float,
        systemAudioVolume: Float,
        pauseTimeline: RecordingPauseTimeline
    ) async throws -> URL {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
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
    var spatialAudioMode: FrameCoachSpatialAudioMode = .off
    var playsCenterConfirmation = true
}

private final class MockRecordingOutputDirectoryStore: RecordingOutputDirectoryStoring {
    var outputDirectoryPath: String?
    var outputDirectoryBookmarkData: Data?
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
    private(set) var startSessionInBackgroundCalled = false
    private(set) var stopSessionCalled = false
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

    func startSessionInBackground() { startSessionInBackgroundCalled = true }
    func stopSession() { stopSessionCalled = true }
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
    func test_labels_are_explicit_and_distinct() {
        XCTAssertEqual(RecordingPreset.horizontalCamera.label, "Yatay video kaydı")
        XCTAssertEqual(RecordingPreset.horizontalScreen.label, "Yatay ekran kaydı")
        XCTAssertEqual(RecordingPreset.audioOnly.label, "Ses kaydı")
    }

    func test_shortDescriptions_match_visible_mode_purpose() {
        XCTAssertEqual(RecordingPreset.horizontalCamera.shortDescription, "Kamera ile yatay video çek")
        XCTAssertEqual(RecordingPreset.horizontalScreen.shortDescription, "Yatay ekran veya pencere kaydet")
        XCTAssertEqual(RecordingPreset.audioOnly.shortDescription, "Sadece ses kaydı al")
    }

    func test_commandKeys_follow_announced_order() {
        XCTAssertEqual(RecordingPreset.horizontalCamera.commandKey, "1")
        XCTAssertEqual(RecordingPreset.horizontalScreen.commandKey, "2")
        XCTAssertEqual(RecordingPreset.audioOnly.commandKey, "3")
    }

    func test_recordingModes_match_supported_release_modes() {
        XCTAssertEqual(RecordingPreset.horizontalCamera.recordingMode, .horizontal1080p)
        XCTAssertEqual(RecordingPreset.horizontalScreen.recordingMode, .horizontal1080p)
        XCTAssertEqual(RecordingPreset.audioOnly.recordingMode, .horizontal1080p)
    }
}

// MARK: - Recording lifecycle scenario tests
@MainActor
final class RecordingLifecycleTests: XCTestCase {

    // MARK: Helpers

    private struct RecordingScenario {
        let name: String
        let preset: RecordingPreset
        var screenSource: ScreenCaptureSource = .screen
        var includesMicrophone = true
        var includesSystemAudio = false
        var includesCameraOverlay = false
        var includesCursorHighlight = false
        var includesKeyboardShortcuts = false
    }

    private struct RichRecordingHarness {
        let viewModel: RecorderViewModel
        let recorder: RecorderCaptureStub
        let screenProvider: MockScreenRecordingProvider
        let cameraOverlayRecorder: MockCameraOverlayRecorder
        let microphoneRecorder: MockMicrophoneAudioRecorder
        let systemAudioRecorder: MockSystemAudioRecorder
        let cursorRecorder: MockCursorHighlightRecorder
        let keyboardRecorder: MockKeyboardShortcutRecorder
    }

    private func makeRichRecordingHarness() -> RichRecordingHarness {
        let recorder = RecorderCaptureStub(
            cameras: [InputDevice(id: "cam-1", name: "FaceTime HD")],
            microphones: [InputDevice(id: "mic-1", name: "Built-in Mic")]
        )
        let screenProvider = MockScreenRecordingProvider(
            status: .authorized,
            displays: [
                ScreenDisplayOption(
                    id: "display-1",
                    name: "Built-in Display",
                    frame: CGRect(x: 0, y: 0, width: 1440, height: 900)
                )
            ],
            windows: [
                ScreenWindowOption(
                    id: "window-1",
                    name: "Safari - Docs",
                    frame: CGRect(x: 20, y: 20, width: 1200, height: 800)
                )
            ]
        )
        screenProvider.shouldCompleteOnStop = true
        let cameraOverlayRecorder = MockCameraOverlayRecorder()
        let microphoneRecorder = MockMicrophoneAudioRecorder()
        let systemAudioRecorder = MockSystemAudioRecorder()
        let cursorRecorder = MockCursorHighlightRecorder()
        let keyboardRecorder = MockKeyboardShortcutRecorder()
        let permissions = RecorderPermissionsStub(statuses: [.video: .authorized, .audio: .authorized])
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let viewModel = RecorderViewModel(
            recorder: recorder,
            screenRecordingProvider: screenProvider,
            cameraOverlayRecorder: cameraOverlayRecorder,
            systemAudioRecorder: systemAudioRecorder,
            microphoneAudioRecorder: microphoneRecorder,
            cursorHighlightRecorder: cursorRecorder,
            keyboardShortcutRecorder: keyboardRecorder,
            fileNamer: RecordingFileNamer(homeDirectory: tempRoot),
            soundEffectPlayer: MockSoundEffectPlayer(),
            permissionProvider: permissions
        )
        return RichRecordingHarness(
            viewModel: viewModel,
            recorder: recorder,
            screenProvider: screenProvider,
            cameraOverlayRecorder: cameraOverlayRecorder,
            microphoneRecorder: microphoneRecorder,
            systemAudioRecorder: systemAudioRecorder,
            cursorRecorder: cursorRecorder,
            keyboardRecorder: keyboardRecorder
        )
    }

    private func makeAudioViewModel() -> (RecorderViewModel, MockMicrophoneAudioRecorder, MockSystemAudioRecorder, MockAudioRecordingExporter) {
        let mic = MockMicrophoneAudioRecorder()
        let sys = MockSystemAudioRecorder()
        let exporter = MockAudioRecordingExporter()
        let permissions = RecorderPermissionsStub(statuses: [.audio: .authorized])
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let vm = RecorderViewModel(
            recorder: RecorderCaptureStub(cameras: [], microphones: [InputDevice(id: "mic-1", name: "USB Mic")]),
            screenRecordingProvider: MockScreenRecordingProvider(),
            systemAudioRecorder: sys,
            microphoneAudioRecorder: mic,
            audioRecordingExporter: exporter,
            fileNamer: RecordingFileNamer(homeDirectory: tempRoot),
            soundEffectPlayer: MockSoundEffectPlayer(),
            lastRecordingConfigurationStore: MockLastRecordingConfigurationStore(),
            permissionProvider: permissions
        )
        return (vm, mic, sys, exporter)
    }

    private func makeCameraViewModel() -> (RecorderViewModel, RecorderCaptureStub) {
        let stub = RecorderCaptureStub(
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
            lastRecordingConfigurationStore: MockLastRecordingConfigurationStore(),
            permissionProvider: permissions
        )
        return (vm, stub)
    }

    private func makeScreenViewModel() -> (RecorderViewModel, MockScreenRecordingProvider) {
        let provider = MockScreenRecordingProvider(
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
            lastRecordingConfigurationStore: MockLastRecordingConfigurationStore(),
            permissionProvider: permissions
        )
        return (vm, provider)
    }

    private func waitForRecording(_ vm: RecorderViewModel) async {
        for _ in 0..<20 where !vm.isRecording {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    private func waitForIdle(_ vm: RecorderViewModel) async {
        try? await Task.sleep(nanoseconds: 150_000_000)
    }

    fileprivate func waitForCompletedRecording(_ vm: RecorderViewModel) async {
        for _ in 0..<40 where vm.completedRecording == nil {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    private func runScenario(_ scenario: RecordingScenario, file: StaticString = #filePath, line: UInt = #line) async {
        let harness = makeRichRecordingHarness()
        let vm = harness.viewModel
        await vm.setup()
        vm.selectPreset(scenario.preset)
        if scenario.preset.isScreenPreset {
            await vm.refreshScreenRecordingOptions()
            vm.selectScreenCaptureSource(scenario.screenSource)
        }
        vm.selectedCameraID = "cam-1"
        vm.selectedMicrophoneID = scenario.includesMicrophone ? "mic-1" : ""
        vm.isSystemAudioEnabled = scenario.includesSystemAudio
        vm.isScreenCameraOverlayEnabled = scenario.includesCameraOverlay
        vm.isCursorHighlightEnabled = scenario.includesCursorHighlight
        vm.isKeyboardShortcutOverlayEnabled = scenario.includesKeyboardShortcuts
        vm.refreshDeviceState()

        vm.startRecording()
        await waitForRecording(vm)

        XCTAssertTrue(vm.isRecording, "\(scenario.name): should start recording. \(vm.errorText ?? vm.statusText)", file: file, line: line)
        XCTAssertFalse(vm.isPreparingRecording, "\(scenario.name): should leave preparing state", file: file, line: line)
        XCTAssertNil(vm.errorText, "\(scenario.name): should not report an error", file: file, line: line)

        vm.stopRecording()
        await waitForIdle(vm)

        XCTAssertFalse(vm.isRecording, "\(scenario.name): should stop recording", file: file, line: line)
        XCTAssertFalse(vm.isPaused, "\(scenario.name): should clear pause state", file: file, line: line)
        XCTAssertFalse(vm.isPreparingRecording, "\(scenario.name): should not be stuck preparing", file: file, line: line)
        XCTAssertFalse(vm.isCountingDown, "\(scenario.name): should not leave a countdown running", file: file, line: line)

        if scenario.includesMicrophone, !scenario.preset.isCameraPreset {
            XCTAssertTrue(harness.microphoneRecorder.stopCalled, "\(scenario.name): microphone recorder should stop", file: file, line: line)
        }
        if scenario.includesSystemAudio {
            XCTAssertTrue(harness.systemAudioRecorder.stopCalled, "\(scenario.name): system audio recorder should stop", file: file, line: line)
        }
        if scenario.includesCameraOverlay {
            XCTAssertTrue(harness.cameraOverlayRecorder.stopCalled, "\(scenario.name): camera overlay recorder should stop", file: file, line: line)
            XCTAssertTrue(harness.cameraOverlayRecorder.stopSessionCalled, "\(scenario.name): camera overlay session should stop", file: file, line: line)
        }
        if scenario.includesCursorHighlight {
            XCTAssertTrue(harness.cursorRecorder.stopCalled, "\(scenario.name): cursor tracker should stop", file: file, line: line)
        }
        if scenario.includesKeyboardShortcuts {
            XCTAssertTrue(harness.keyboardRecorder.stopCalled, "\(scenario.name): keyboard tracker should stop", file: file, line: line)
        }
    }

    // MARK: Audio: start → stop

    func testAudioStartStop_setsCompletedRecording() async {
        let (vm, _, _, _) = makeAudioViewModel()
        await vm.setup()
        vm.selectPreset(.audioOnly)
        vm.refreshDeviceState()

        XCTAssertNil(vm.completedRecording)

        vm.startRecording()
        await waitForRecording(vm)

        XCTAssertTrue(vm.isRecording)
        XCTAssertFalse(vm.isPaused)
        XCTAssertNil(vm.completedRecording)

        vm.stopRecording()
        await waitForIdle(vm)

        XCTAssertFalse(vm.isRecording)
        XCTAssertFalse(vm.isPaused)
        XCTAssertNotNil(vm.completedRecording)
        XCTAssertEqual(vm.completedRecording?.fileExtension, "m4a")
    }

    // MARK: Audio: start → pause → stop

    func testAudioStartPauseStop_setsCompletedRecording() async {
        let (vm, _, _, _) = makeAudioViewModel()
        await vm.setup()
        vm.selectPreset(.audioOnly)
        vm.refreshDeviceState()

        vm.startRecording()
        await waitForRecording(vm)

        vm.togglePauseResume()
        XCTAssertTrue(vm.isPaused)

        vm.stopRecording()
        await waitForIdle(vm)

        XCTAssertFalse(vm.isRecording)
        XCTAssertFalse(vm.isPaused)
        XCTAssertNotNil(vm.completedRecording)
    }

    // MARK: Audio: start → pause → resume → stop

    func testAudioStartPauseResumeStop_setsCompletedRecording() async {
        let (vm, _, _, _) = makeAudioViewModel()
        await vm.setup()
        vm.selectPreset(.audioOnly)
        vm.refreshDeviceState()

        vm.startRecording()
        await waitForRecording(vm)

        vm.togglePauseResume()
        XCTAssertTrue(vm.isPaused)

        vm.togglePauseResume()
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertFalse(vm.isPaused)
        XCTAssertTrue(vm.isRecording)

        vm.stopRecording()
        await waitForIdle(vm)

        XCTAssertFalse(vm.isRecording)
        XCTAssertNotNil(vm.completedRecording)
    }

    // MARK: Audio: multi-cycle pause/resume → stop

    func testAudioMultiCyclePauseResume_setsCompletedRecording() async {
        let (vm, _, _, _) = makeAudioViewModel()
        await vm.setup()
        vm.selectPreset(.audioOnly)
        vm.refreshDeviceState()

        vm.startRecording()
        await waitForRecording(vm)

        for _ in 0..<3 {
            vm.togglePauseResume()
            XCTAssertTrue(vm.isPaused)
            vm.togglePauseResume()
            try? await Task.sleep(nanoseconds: 60_000_000)
            XCTAssertFalse(vm.isPaused)
        }

        vm.stopRecording()
        await waitForIdle(vm)

        XCTAssertFalse(vm.isRecording)
        XCTAssertFalse(vm.isPaused)
        XCTAssertNotNil(vm.completedRecording)
    }

    // MARK: Audio: completedRecording nil before and during recording

    func testAudioCompletedRecordingIsNilBeforeAndDuringRecording() async {
        let (vm, _, _, _) = makeAudioViewModel()
        await vm.setup()
        vm.selectPreset(.audioOnly)
        vm.refreshDeviceState()

        XCTAssertNil(vm.completedRecording, "Should be nil before recording starts")

        vm.startRecording()
        await waitForRecording(vm)

        XCTAssertNil(vm.completedRecording, "Should be nil while recording is active")
    }

    // MARK: Audio: second start clears previous completedRecording

    func testAudioSecondStart_clearsPreviousCompletedRecording() async {
        let (vm, _, _, _) = makeAudioViewModel()
        await vm.setup()
        vm.selectPreset(.audioOnly)
        vm.refreshDeviceState()

        vm.startRecording()
        await waitForRecording(vm)
        vm.stopRecording()
        await waitForIdle(vm)

        XCTAssertNotNil(vm.completedRecording)

        vm.startRecording()
        await waitForRecording(vm)

        XCTAssertNil(vm.completedRecording, "Should be cleared when new recording starts")
    }

    // MARK: Camera: start → stop

    func testCameraStartStop_stateIsCleanAfterStop() async {
        let (vm, _) = makeCameraViewModel()
        await vm.setup()
        vm.selectPreset(.horizontalCamera)
        vm.selectedCameraID = "cam-1"
        vm.refreshDeviceState()

        vm.startRecording()
        await waitForRecording(vm)

        XCTAssertTrue(vm.isRecording)
        XCTAssertFalse(vm.isPaused)

        vm.stopRecording()
        await waitForIdle(vm)

        XCTAssertFalse(vm.isRecording)
        XCTAssertFalse(vm.isPaused)
        XCTAssertFalse(vm.isPreparingRecording)
    }

    // MARK: Camera: start → pause → stop

    func testCameraStartPauseStop_stateIsCleanAfterStop() async {
        let (vm, _) = makeCameraViewModel()
        await vm.setup()
        vm.selectPreset(.horizontalCamera)
        vm.selectedCameraID = "cam-1"
        vm.refreshDeviceState()

        vm.startRecording()
        await waitForRecording(vm)

        vm.togglePauseResume()
        XCTAssertTrue(vm.isPaused)

        vm.stopRecording()
        await waitForIdle(vm)

        XCTAssertFalse(vm.isRecording)
        XCTAssertFalse(vm.isPaused)
        XCTAssertFalse(vm.isPreparingRecording)
    }

    // MARK: Camera: start → pause → resume → stop

    func testCameraStartPauseResumeStop_stateIsCleanAfterStop() async {
        let (vm, _) = makeCameraViewModel()
        await vm.setup()
        vm.selectPreset(.horizontalCamera)
        vm.selectedCameraID = "cam-1"
        vm.refreshDeviceState()

        vm.startRecording()
        await waitForRecording(vm)

        vm.togglePauseResume()
        XCTAssertTrue(vm.isPaused)

        vm.togglePauseResume()
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertFalse(vm.isPaused)
        XCTAssertTrue(vm.isRecording)

        vm.stopRecording()
        await waitForIdle(vm)

        XCTAssertFalse(vm.isRecording)
        XCTAssertFalse(vm.isPaused)
        XCTAssertFalse(vm.isPreparingRecording)
    }

    // MARK: Camera: multi-cycle pause/resume → stop

    func testCameraMultiCyclePauseResume_stateIsCleanAfterStop() async {
        let (vm, _) = makeCameraViewModel()
        await vm.setup()
        vm.selectPreset(.horizontalCamera)
        vm.selectedCameraID = "cam-1"
        vm.refreshDeviceState()

        vm.startRecording()
        await waitForRecording(vm)

        for _ in 0..<3 {
            vm.togglePauseResume()
            XCTAssertTrue(vm.isPaused)
            vm.togglePauseResume()
            try? await Task.sleep(nanoseconds: 60_000_000)
            XCTAssertFalse(vm.isPaused)
        }

        vm.stopRecording()
        await waitForIdle(vm)

        XCTAssertFalse(vm.isRecording)
        XCTAssertFalse(vm.isPaused)
        XCTAssertFalse(vm.isPreparingRecording)
    }

    // MARK: Screen: start → stop

    func testScreenStartStop_stateIsCleanAfterStop() async {
        let (vm, _) = makeScreenViewModel()
        await vm.setup()
        vm.selectPreset(.horizontalScreen)
        vm.selectScreenCaptureSource(.screen)
        vm.selectedMicrophoneID = ""
        vm.isSystemAudioEnabled = false
        vm.isScreenCameraOverlayEnabled = false
        vm.isCursorHighlightEnabled = false
        vm.isKeyboardShortcutOverlayEnabled = false
        await vm.refreshScreenRecordingOptions()
        vm.refreshDeviceState()

        vm.startRecording()
        await waitForRecording(vm)

        XCTAssertTrue(vm.isRecording)

        vm.stopRecording()
        await waitForIdle(vm)

        XCTAssertFalse(vm.isRecording)
        XCTAssertFalse(vm.isPaused)
        XCTAssertFalse(vm.isPreparingRecording)
    }

    // MARK: Screen: start → pause → resume → stop

    func testScreenStartPauseResumeStop_stateIsCleanAfterStop() async {
        let (vm, _) = makeScreenViewModel()
        await vm.setup()
        vm.selectPreset(.horizontalScreen)
        vm.selectScreenCaptureSource(.screen)
        vm.selectedMicrophoneID = ""
        vm.isSystemAudioEnabled = false
        vm.isScreenCameraOverlayEnabled = false
        vm.isCursorHighlightEnabled = false
        vm.isKeyboardShortcutOverlayEnabled = false
        await vm.refreshScreenRecordingOptions()
        vm.refreshDeviceState()

        vm.startRecording()
        await waitForRecording(vm)

        vm.togglePauseResume()
        XCTAssertTrue(vm.isPaused)

        vm.togglePauseResume()
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertFalse(vm.isPaused)

        vm.stopRecording()
        await waitForIdle(vm)

        XCTAssertFalse(vm.isRecording)
        XCTAssertFalse(vm.isPaused)
        XCTAssertFalse(vm.isPreparingRecording)
    }

    // MARK: Representative option matrix

    func testRepresentativeRecordingOptionMatrixStartsAndStopsCleanly() async {
        let scenarios: [RecordingScenario] = [
            RecordingScenario(
                name: "camera with microphone",
                preset: .horizontalCamera,
                includesMicrophone: true
            ),
            RecordingScenario(
                name: "camera with microphone and system audio",
                preset: .horizontalCamera,
                includesMicrophone: true,
                includesSystemAudio: true
            ),
            RecordingScenario(
                name: "screen display base",
                preset: .horizontalScreen,
                screenSource: .screen,
                includesMicrophone: false
            ),
            RecordingScenario(
                name: "screen display with microphone and system audio",
                preset: .horizontalScreen,
                screenSource: .screen,
                includesMicrophone: true,
                includesSystemAudio: true
            ),
            RecordingScenario(
                name: "screen display with all overlays",
                preset: .horizontalScreen,
                screenSource: .screen,
                includesMicrophone: true,
                includesSystemAudio: true,
                includesCameraOverlay: true,
                includesCursorHighlight: true,
                includesKeyboardShortcuts: true
            ),
            RecordingScenario(
                name: "window with camera overlay and keyboard shortcuts",
                preset: .horizontalScreen,
                screenSource: .window,
                includesMicrophone: false,
                includesCameraOverlay: true,
                includesKeyboardShortcuts: true
            ),
            RecordingScenario(
                name: "audio microphone only",
                preset: .audioOnly,
                includesMicrophone: true
            ),
            RecordingScenario(
                name: "audio system only",
                preset: .audioOnly,
                includesMicrophone: false,
                includesSystemAudio: true
            ),
            RecordingScenario(
                name: "audio microphone and system",
                preset: .audioOnly,
                includesMicrophone: true,
                includesSystemAudio: true
            )
        ]

        for scenario in scenarios {
            await runScenario(scenario)
        }
    }

    // MARK: State integrity

    func testStateFullyResetAfterAudioStop() async {
        let (vm, _, _, _) = makeAudioViewModel()
        await vm.setup()
        vm.selectPreset(.audioOnly)
        vm.refreshDeviceState()

        vm.startRecording()
        await waitForRecording(vm)
        vm.togglePauseResume()
        vm.stopRecording()
        await waitForIdle(vm)

        XCTAssertFalse(vm.isRecording)
        XCTAssertFalse(vm.isPaused)
        XCTAssertFalse(vm.isPreparingRecording)
        XCTAssertFalse(vm.isCountingDown)
    }

    // MARK: Guard: toggleAudioRecording ignored when camera is active

    func testAudioToggleIsGuardedWhenCameraRecordingIsActive() async {
        let (vm, _) = makeCameraViewModel()
        await vm.setup()
        vm.selectPreset(.horizontalCamera)
        vm.selectedCameraID = "cam-1"
        vm.refreshDeviceState()

        vm.startRecording()
        await waitForRecording(vm)

        XCTAssertTrue(vm.isRecording)
        XCTAssertEqual(vm.selectedRecordingSource, .camera)

        vm.toggleAudioRecording()
        try? await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertEqual(vm.selectedRecordingSource, .camera)
        XCTAssertTrue(vm.isRecording)
    }
}
