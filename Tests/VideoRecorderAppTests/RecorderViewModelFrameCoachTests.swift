import XCTest
import AVFoundation
import CoreVideo
@testable import VideoRecorderApp

@MainActor
final class RecorderViewModelFrameCoachTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "recording.lastConfiguration")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "recording.lastConfiguration")
        super.tearDown()
    }

    func testToggleFrameCoachEnablesCoachAndAnnouncesState() async {
        let speaker = MockInstructionSpeaker()
        let recorder = FrameCoachMockCaptureRecorder(
            cameras: [InputDevice(id: "cam-1", name: "Camera")],
            microphones: [InputDevice(id: "mic-1", name: "Mic")]
        )
        let viewModel = makeViewModel(speaker: speaker, recorder: recorder)

        await viewModel.setup()

        viewModel.toggleFrameCoach()
        await Task.yield()

        XCTAssertTrue(viewModel.isFrameCoachEnabled)
        XCTAssertEqual(viewModel.currentFrameCoachInstruction, "Kadraj koçu açık")
        XCTAssertEqual(speaker.spokenTexts, ["Kadraj koçu açık"])
        XCTAssertEqual(recorder.startSessionInBackgroundCallCount, 2)
    }

    func testToggleFrameCoachDisablesCoachAndClearsInstruction() {
        let speaker = MockInstructionSpeaker()
        let viewModel = makeViewModel(speaker: speaker)

        viewModel.toggleFrameCoach()
        viewModel.toggleFrameCoach()

        XCTAssertFalse(viewModel.isFrameCoachEnabled)
        XCTAssertNil(viewModel.currentFrameCoachInstruction)
        XCTAssertEqual(speaker.spokenTexts, ["Kadraj koçu açık", "Kadraj koçu kapalı"])
    }

    func testFrameCoachDoesNotSpeakWhenDisabled() {
        let speaker = MockInstructionSpeaker()
        let viewModel = makeViewModel(speaker: speaker)

        viewModel.updateFrameCoachInstruction("Biraz sola")

        XCTAssertNil(viewModel.currentFrameCoachInstruction)
        XCTAssertTrue(speaker.spokenTexts.isEmpty)
    }

    func testFrameCoachAnnouncesSubjectCountOnlyWhenItChanges() {
        let speaker = MockInstructionSpeaker()
        let viewModel = makeViewModel(
            speaker: speaker,
            speechCuePlayer: SpeechCuePlayer(
                speaker: speaker,
                now: Date.init,
                cooldown: 0,
                isVoiceOverEnabled: { false }
            )
        )

        viewModel.toggleFrameCoach()
        viewModel.processFrameCoachAnalysis(makeSinglePersonAnalysis(x: 0.42, y: 0.30))
        viewModel.processFrameCoachAnalysis(makeSinglePersonAnalysis(x: 0.14, y: 0.28))
        viewModel.processFrameCoachAnalysis(makeTwoPersonAnalysis())

        XCTAssertEqual(
            speaker.spokenTexts,
            [
                "Kadraj koçu açık",
                "Bir kişi görünüyor. Kadraj uygun",
                "İki kişi görünüyor. Kadraj dengeli"
            ]
        )
    }

    func testFrameCoachIgnoresBriefFaceLossBeforeSpeakingNoFace() {
        let speaker = MockInstructionSpeaker()
        let viewModel = makeViewModel(
            speaker: speaker,
            speechCuePlayer: SpeechCuePlayer(
                speaker: speaker,
                now: Date.init,
                cooldown: 0,
                isVoiceOverEnabled: { false }
            )
        )

        viewModel.toggleFrameCoach()
        viewModel.processFrameCoachAnalysis(makeSinglePersonAnalysis(x: 0.14, y: 0.28))
        viewModel.processFrameCoachAnalysis(nil)
        viewModel.processFrameCoachAnalysis(nil)

        XCTAssertEqual(viewModel.currentFrameCoachInstruction, "biraz sağa geç")
        XCTAssertEqual(
            speaker.spokenTexts,
            [
                "Kadraj koçu açık",
                "Bir kişi görünüyor. Biraz sağa geç"
            ]
        )

        viewModel.processFrameCoachAnalysis(nil)

        XCTAssertEqual(viewModel.currentFrameCoachInstruction, "Yüz algılanamıyor")
        XCTAssertEqual(
            speaker.spokenTexts,
            [
                "Kadraj koçu açık",
                "Bir kişi görünüyor. Biraz sağa geç",
                "Yüz algılanamıyor"
            ]
        )
    }

    func testFrameCoachUsesSelectedRecordingModeForGuidance() {
        let speaker = MockInstructionSpeaker()
        let viewModel = makeViewModel(
            speaker: speaker,
            speechCuePlayer: SpeechCuePlayer(
                speaker: speaker,
                now: Date.init,
                cooldown: 0,
                isVoiceOverEnabled: { false }
            )
        )

        viewModel.selectedMode = .vertical1080p
        viewModel.toggleFrameCoach()
        viewModel.processFrameCoachAnalysis(
            FrameAnalysis(
                faceBoxes: [NormalizedFaceBox(rect: CGRect(x: 0.385, y: 0.28, width: 0.23, height: 0.29))],
                subjectCount: .one,
                headroomRatio: 0.28,
                bottomCoverageRatio: 0.12,
                horizontalGroupCenter: 0.50,
                spacingMetric: 0,
                confidence: 0.95
            )
        )

        XCTAssertEqual(viewModel.currentFrameCoachInstruction, "kadraj uygun")
        XCTAssertEqual(
            speaker.spokenTexts,
            [
                "Kadraj koçu açık",
                "Bir kişi görünüyor. Kadraj uygun"
            ]
        )
    }

    func testFrameCoachDoesNotRepeatSameGuidanceAfterSubjectCountAnnouncement() {
        let speaker = MockInstructionSpeaker()
        let viewModel = makeViewModel(
            speaker: speaker,
            speechCuePlayer: SpeechCuePlayer(
                speaker: speaker,
                now: Date.init,
                cooldown: 5,
                isVoiceOverEnabled: { false }
            )
        )

        viewModel.selectedMode = .vertical1080p
        viewModel.toggleFrameCoach()

        let analysis = FrameAnalysis(
            faceBoxes: [NormalizedFaceBox(rect: CGRect(x: 0.385, y: 0.28, width: 0.23, height: 0.29))],
            subjectCount: .one,
            headroomRatio: 0.28,
            bottomCoverageRatio: 0.12,
            horizontalGroupCenter: 0.50,
            spacingMetric: 0,
            confidence: 0.95
        )

        viewModel.processFrameCoachAnalysis(analysis)
        viewModel.processFrameCoachAnalysis(analysis)

        XCTAssertEqual(
            speaker.spokenTexts,
            [
                "Kadraj koçu açık",
                "Bir kişi görünüyor. Kadraj uygun"
            ]
        )
    }

    func testFrameCoachAutomaticallyUsesTwoPersonProfileForGuidance() {
        let speaker = MockInstructionSpeaker()
        let viewModel = makeViewModel(
            speaker: speaker,
            speechCuePlayer: SpeechCuePlayer(
                speaker: speaker,
                now: Date.init,
                cooldown: 0,
                isVoiceOverEnabled: { false }
            )
        )

        viewModel.selectedMode = .horizontal1080p
        viewModel.toggleFrameCoach()
        viewModel.processFrameCoachAnalysis(
            FrameAnalysis(
                faceBoxes: [
                    NormalizedFaceBox(rect: CGRect(x: 0.18, y: 0.29, width: 0.14, height: 0.18)),
                    NormalizedFaceBox(rect: CGRect(x: 0.63, y: 0.30, width: 0.14, height: 0.18))
                ],
                subjectCount: .two,
                headroomRatio: 0.20,
                bottomCoverageRatio: 0.24,
                horizontalGroupCenter: 0.475,
                spacingMetric: 0.54,
                confidence: 0.95
            )
        )

        XCTAssertEqual(viewModel.currentFrameCoachInstruction, "aranız biraz açık, birbirinize yaklaşın")
        XCTAssertEqual(
            speaker.spokenTexts,
            [
                "Kadraj koçu açık",
                "İki kişi görünüyor. Aranız biraz açık, birbirinize yaklaşın"
            ]
        )
    }

    func testFrameCoachUsesVerticalConversationProfileForVerticalCamera() {
        let speaker = MockInstructionSpeaker()
        let viewModel = makeViewModel(
            speaker: speaker,
            speechCuePlayer: SpeechCuePlayer(
                speaker: speaker,
                now: Date.init,
                cooldown: 0,
                isVoiceOverEnabled: { false }
            )
        )

        viewModel.selectPreset(.verticalCamera)
        viewModel.toggleFrameCoach()
        viewModel.processFrameCoachAnalysis(
            FrameAnalysis(
                faceBoxes: [
                    NormalizedFaceBox(rect: CGRect(x: 0.22, y: 0.29, width: 0.14, height: 0.18)),
                    NormalizedFaceBox(rect: CGRect(x: 0.62, y: 0.30, width: 0.14, height: 0.18))
                ],
                subjectCount: .two,
                headroomRatio: 0.20,
                bottomCoverageRatio: 0.24,
                horizontalGroupCenter: 0.49,
                spacingMetric: 0.50,
                confidence: 0.95
            )
        )

        XCTAssertEqual(viewModel.currentFrameCoachInstruction, "aranız biraz açık, birbirinize yaklaşın")
        XCTAssertEqual(
            speaker.spokenTexts,
            [
                "Kadraj koçu açık",
                "İki kişi görünüyor. Aranız biraz açık, birbirinize yaklaşın"
            ]
        )
    }

    func testFrameCoachUsesScreenGuideProfileForScreenOverlay() {
        let speaker = MockInstructionSpeaker()
        let viewModel = makeViewModel(
            speaker: speaker,
            speechCuePlayer: SpeechCuePlayer(
                speaker: speaker,
                now: Date.init,
                cooldown: 0,
                isVoiceOverEnabled: { false }
            )
        )

        viewModel.selectPreset(.horizontalScreen)
        viewModel.toggleScreenCameraOverlay()
        viewModel.toggleFrameCoach()
        viewModel.processFrameCoachAnalysis(
            FrameAnalysis(
                faceBoxes: [NormalizedFaceBox(rect: CGRect(x: 0.40, y: 0.17, width: 0.18, height: 0.22))],
                subjectCount: .one,
                headroomRatio: 0.43,
                bottomCoverageRatio: 0.12,
                horizontalGroupCenter: 0.50,
                spacingMetric: 0,
                confidence: 0.95
            )
        )

        XCTAssertEqual(viewModel.currentFrameCoachInstruction, "kadraj uygun")
        XCTAssertEqual(
            speaker.spokenTexts,
            [
                "Kadraj koçu açık",
                "Bir kişi görünüyor. Kadraj uygun"
            ]
        )
    }

    func testFrameCoachPrioritizesLowLightGuidance() {
        let speaker = MockInstructionSpeaker()
        let viewModel = makeViewModel(
            speaker: speaker,
            speechCuePlayer: SpeechCuePlayer(
                speaker: speaker,
                now: Date.init,
                cooldown: 0,
                isVoiceOverEnabled: { false }
            )
        )

        viewModel.toggleFrameCoach()
        viewModel.processCaptureCoachAnalysis(
            frameAnalysis: makeSinglePersonAnalysis(x: 0.42, y: 0.30),
            lightingAnalysis: FrameLightingAnalysis(averageLuma: 0.12)
        )

        XCTAssertEqual(viewModel.currentFrameCoachInstruction, "ışık düşük, lambayı aç veya ekran parlaklığını artır")
        XCTAssertEqual(
            speaker.spokenTexts,
            [
                "Kadraj koçu açık",
                "Işık düşük, lambayı aç veya ekran parlaklığını artır"
            ]
        )
    }

    func testPreviewFrameHandlerFeedsLowLightGuidance() async throws {
        let speaker = MockInstructionSpeaker()
        let recorder = FrameCoachMockCaptureRecorder(
            cameras: [InputDevice(id: "cam-1", name: "Camera")],
            microphones: [InputDevice(id: "mic-1", name: "Mic")]
        )
        let viewModel = makeViewModel(
            speaker: speaker,
            recorder: recorder,
            frameAnalysisService: FrameAnalysisService(detector: StubFaceDetector(faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.42, y: 0.30, width: 0.16, height: 0.20))
            ])),
            speechCuePlayer: SpeechCuePlayer(
                speaker: speaker,
                now: Date.init,
                cooldown: 0,
                isVoiceOverEnabled: { false }
            )
        )

        await viewModel.setup()
        viewModel.toggleFrameCoach()
        recorder.previewFrameHandler?(try makePixelBuffer(red: 10, green: 10, blue: 10), .zero)
        for _ in 0..<20 where viewModel.currentFrameCoachInstruction != "ışık düşük, lambayı aç veya ekran parlaklığını artır" {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(viewModel.currentFrameCoachInstruction, "ışık düşük, lambayı aç veya ekran parlaklığını artır")
        XCTAssertTrue(speaker.spokenTexts.contains("Işık düşük, lambayı aç veya ekran parlaklığını artır"))
    }

    private func makeViewModel(
        speaker: InstructionSpeaking,
        recorder: FrameCoachMockCaptureRecorder = FrameCoachMockCaptureRecorder(),
        frameAnalysisService: FrameAnalysisService = FrameAnalysisService(),
        speechCuePlayer: SpeechCuePlayer? = nil
    ) -> RecorderViewModel {
        let settingsStore = FrameCoachSettingsStoreStub()
        settingsStore.feedbackFrequency = .frequent
        return RecorderViewModel(
            recorder: recorder,
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            frameAnalysisService: frameAnalysisService,
            soundEffectPlayer: SoundEffectPlayer(),
            frameCoachSettingsStore: settingsStore,
            permissionProvider: FrameCoachMockMediaPermissionProvider(statuses: [.video: .authorized, .audio: .authorized]),
            openURL: { _ in },
            speechCuePlayer: speechCuePlayer ?? SpeechCuePlayer(speaker: speaker, announcer: nil, isVoiceOverEnabled: { false })
        )
    }

    private func makeSinglePersonAnalysis(x: CGFloat, y: CGFloat) -> FrameAnalysis {
        FrameAnalysis(
            faceBoxes: [NormalizedFaceBox(rect: CGRect(x: x, y: y, width: 0.16, height: 0.20))],
            subjectCount: .one,
            headroomRatio: 0.18,
            bottomCoverageRatio: 0.22,
            horizontalGroupCenter: Double(x + 0.08),
            spacingMetric: 0,
            confidence: 0.95
        )
    }

    private func makeTwoPersonAnalysis() -> FrameAnalysis {
        FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.24, y: 0.30, width: 0.16, height: 0.20)),
                NormalizedFaceBox(rect: CGRect(x: 0.56, y: 0.30, width: 0.16, height: 0.20))
            ],
            subjectCount: .two,
            headroomRatio: 0.18,
            bottomCoverageRatio: 0.22,
            horizontalGroupCenter: 0.48,
            spacingMetric: 0.32,
            confidence: 0.95
        )
    }

    private func makePixelBuffer(red: UInt8, green: UInt8, blue: UInt8) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            4,
            4,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        let unwrapped = try XCTUnwrap(pixelBuffer)

        CVPixelBufferLockBaseAddress(unwrapped, [])
        defer { CVPixelBufferUnlockBaseAddress(unwrapped, []) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(unwrapped)
        let height = CVPixelBufferGetHeight(unwrapped)
        let width = CVPixelBufferGetWidth(unwrapped)
        let baseAddress = try XCTUnwrap(CVPixelBufferGetBaseAddress(unwrapped))
        let bytes = baseAddress.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                bytes[offset] = blue
                bytes[offset + 1] = green
                bytes[offset + 2] = red
                bytes[offset + 3] = 255
            }
        }

        return unwrapped
    }
}

private struct StubFaceDetector: FaceDetecting {
    let faceBoxes: [NormalizedFaceBox]

    func detectFaces(in pixelBuffer: CVPixelBuffer) throws -> [NormalizedFaceBox] {
        faceBoxes
    }
}

private final class FrameCoachMockCaptureRecorder: CaptureRecording {
    let session = AVCaptureSession()
    var cameras: [InputDevice]
    var microphones: [InputDevice]
    private(set) var previewFramesEnabled = false
    private(set) var previewFrameHandler: PreviewFrameHandler?
    private(set) var startSessionInBackgroundCallCount = 0

    init(cameras: [InputDevice] = [], microphones: [InputDevice] = []) {
        self.cameras = cameras
        self.microphones = microphones
    }

    func cameraDevices() -> [InputDevice] { cameras }
    func microphoneDevices() -> [InputDevice] { microphones }
    func configure(videoDeviceID: String, audioDeviceID: String, mode: RecordingMode) async throws {}
    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) async throws {}
    func stopRecording() {}
    func setPreviewFrameHandler(_ handler: PreviewFrameHandler?) { previewFrameHandler = handler }
    func setPreviewFramesEnabled(_ isEnabled: Bool) { previewFramesEnabled = isEnabled }
    func startSessionInBackground() { startSessionInBackgroundCallCount += 1 }
}

private struct FrameCoachMockMediaPermissionProvider: MediaPermissionProviding {
    var statuses: [AVMediaType: AVAuthorizationStatus]

    func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        statuses[mediaType] ?? .notDetermined
    }

    func requestAccess(for mediaType: AVMediaType) async -> Bool {
        statuses[mediaType] == .authorized
    }
}

private final class FrameCoachSettingsStoreStub: FrameCoachSettingsStoring {
    var speechMode: FrameCoachSpeechMode = .appVoice
    var feedbackFrequency: FrameCoachFeedbackFrequency = .frequent
    var repeatInterval: FrameCoachRepeatInterval = .short
    var showsOnScreenText = true
}
