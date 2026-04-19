import Foundation
import AVFoundation
import AppKit
import Observation
import UniformTypeIdentifiers

protocol AudioRecordingExporting: AnyObject {
    func export(
        microphoneURL: URL?,
        systemAudioURL: URL?,
        to destinationURL: URL,
        microphoneVolume: Float,
        systemAudioVolume: Float,
        pauseTimeline: RecordingPauseTimeline
    ) async throws -> URL
}

final class AudioRecordingExporter: AudioRecordingExporting {
    private let audioMixBuilder = RecordingAudioMixBuilder()

    func export(
        microphoneURL: URL?,
        systemAudioURL: URL?,
        to destinationURL: URL,
        microphoneVolume: Float,
        systemAudioVolume: Float,
        pauseTimeline: RecordingPauseTimeline
    ) async throws -> URL {
        guard microphoneURL != nil || systemAudioURL != nil else {
            throw MicrophoneAudioRecorderError.emptyRecording
        }

        let composition = AVMutableComposition()
        var microphoneTrackIDs: [CMPersistentTrackID] = []
        var systemTrackIDs: [CMPersistentTrackID] = []

        if let microphoneURL {
            microphoneTrackIDs = try await addAudioTracks(
                from: AVURLAsset(url: microphoneURL),
                to: composition,
                pauseTimeline: pauseTimeline
            )
        }
        if let systemAudioURL {
            systemTrackIDs = try await addAudioTracks(
                from: AVURLAsset(url: systemAudioURL),
                to: composition,
                pauseTimeline: pauseTimeline
            )
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw CaptureRecorderError.cannotExportMP4
        }

        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .m4a
        exportSession.audioMix = audioMixBuilder.makeAudioMix(
            composition: composition,
            microphoneTrackIDs: microphoneTrackIDs,
            systemAudioTrackIDs: systemTrackIDs,
            microphoneVolume: microphoneVolume,
            systemAudioVolume: systemAudioVolume
        )

        await exportSession.export()

        if let error = exportSession.error {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }

        guard exportSession.status == .completed else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw CaptureRecorderError.cannotExportMP4
        }

        return destinationURL
    }

    private func addAudioTracks(
        from asset: AVAsset,
        to composition: AVMutableComposition,
        pauseTimeline: RecordingPauseTimeline
    ) async throws -> [CMPersistentTrackID] {
        let duration = try await asset.load(.duration)
        guard duration > .zero else { return [] }
        let segments = pauseTimeline.segments(for: duration)
        guard !segments.isEmpty else { return [] }

        var trackIDs: [CMPersistentTrackID] = []
        for audioTrack in try await asset.loadTracks(withMediaType: .audio) {
            guard let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                continue
            }

            for segment in segments {
                try compositionTrack.insertTimeRange(segment.sourceRange, of: audioTrack, at: segment.destinationStart)
            }
            trackIDs.append(compositionTrack.trackID)
        }
        return trackIDs
    }
}

enum FrameCoachSpeechMode: String, CaseIterable, Identifiable {
    case automatic
    case voiceOver
    case appVoice
    case silent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic:
            return String(localized: "Otomatik")
        case .voiceOver:
            return String(localized: "VoiceOver")
        case .appVoice:
            return String(localized: "Uygulama sesi")
        case .silent:
            return String(localized: "Sessiz")
        }
    }
}

enum FrameCoachFeedbackFrequency: String, CaseIterable, Identifiable {
    case minimal
    case balanced
    case frequent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minimal:
            return String(localized: "Minimal")
        case .balanced:
            return String(localized: "Dengeli")
        case .frequent:
            return String(localized: "Sık")
        }
    }

    var minimumInterval: TimeInterval {
        switch self {
        case .minimal:
            return 3.0
        case .balanced:
            return 1.5
        case .frequent:
            return 0
        }
    }
}

enum FrameCoachRepeatInterval: Double, CaseIterable, Identifiable {
    case short = 2
    case medium = 5
    case long = 8

    var id: Double { rawValue }

    var label: String {
        String(localized: "\(Int(rawValue)) saniye")
    }

    var seconds: TimeInterval { rawValue }
}

struct FrameCoachPreferences: Equatable {
    var speechMode: FrameCoachSpeechMode
    var feedbackFrequency: FrameCoachFeedbackFrequency
    var repeatInterval: FrameCoachRepeatInterval
    var showsOnScreenText: Bool
    /// Spatial audio direction tones for frame coach guidance.
    var spatialAudioMode: FrameCoachSpatialAudioMode
    /// Whether to play a confirmation tone when the subject is centered.
    var playsCenterConfirmation: Bool

    static let `default` = FrameCoachPreferences(
        speechMode: .automatic,
        feedbackFrequency: .balanced,
        repeatInterval: .medium,
        showsOnScreenText: true,
        spatialAudioMode: .off,
        playsCenterConfirmation: true
    )
}

enum RecordingCountdown: Int, CaseIterable, Identifiable {
    case none = 0
    case three = 3
    case five = 5
    case ten = 10

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none: return String(localized: "Yok")
        case .three: return String(localized: "3 saniye")
        case .five: return String(localized: "5 saniye")
        case .ten: return String(localized: "10 saniye")
        }
    }
}

enum MaxRecordingDuration: Int, CaseIterable, Identifiable {
    case unlimited = 0
    case five = 5
    case ten = 10
    case fifteen = 15
    case thirty = 30
    case sixty = 60

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .unlimited: return String(localized: "Sınırsız")
        case .five: return String(localized: "5 dakika")
        case .ten: return String(localized: "10 dakika")
        case .fifteen: return String(localized: "15 dakika")
        case .thirty: return String(localized: "30 dakika")
        case .sixty: return String(localized: "60 dakika")
        }
    }

    var seconds: TimeInterval? {
        rawValue == 0 ? nil : TimeInterval(rawValue * 60)
    }
}

enum PermissionKind: String, CaseIterable, Identifiable {
    case camera
    case microphone
    case screenRecording

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: return String(localized: "Kamera")
        case .microphone: return String(localized: "Mikrofon")
        case .screenRecording: return String(localized: "Ekran Kaydı")
        }
    }

    var symbolName: String {
        switch self {
        case .camera: return "camera"
        case .microphone: return "mic"
        case .screenRecording: return "lock.rectangle"
        }
    }
}

enum PermissionAction: Equatable {
    case request
    case openSettings
    case restartApp
    case none

    var buttonTitle: String? {
        switch self {
        case .request: return String(localized: "İzin Ver")
        case .openSettings: return String(localized: "Ayarları Aç")
        case .restartApp: return String(localized: "Yeniden Aç")
        case .none: return nil
        }
    }
}

enum PermissionInteractionState: Equatable {
    case idle
    case requesting
    case granted
    case denied
    case needsRestart
}

struct PermissionHubItem: Identifiable, Equatable {
    let id: PermissionKind
    let title: String
    let detail: String
    let statusLabel: String
    let helperText: String?
    let isRequired: Bool
    let isSatisfied: Bool
    let isRequestInFlight: Bool
    let primaryAction: PermissionAction
    let secondaryAction: PermissionAction?

    var symbolName: String { id.symbolName }
}

protocol FrameCoachSettingsStoring: AnyObject {
    var speechMode: FrameCoachSpeechMode { get set }
    var feedbackFrequency: FrameCoachFeedbackFrequency { get set }
    var repeatInterval: FrameCoachRepeatInterval { get set }
    var showsOnScreenText: Bool { get set }
}

protocol RecordingOutputDirectoryStoring: AnyObject {
    var outputDirectoryPath: String? { get set }
}

struct LastRecordingConfiguration: Codable, Equatable {
    var selectedPreset: RecordingPreset
    var selectedScreenCaptureSource: ScreenCaptureSource
    var isScreenCameraOverlayEnabled: Bool
    var isSystemAudioEnabled: Bool
    var isCursorHighlightEnabled: Bool
    var isKeyboardShortcutOverlayEnabled: Bool
    var isAutoReframeEnabled: Bool
    var isFrameCoachEnabled: Bool
    var selectedCameraID: String
    var selectedMicrophoneID: String
    var selectedDisplayID: String
    var selectedWindowID: String
}

protocol LastRecordingConfigurationStoring: AnyObject {
    var configuration: LastRecordingConfiguration? { get set }
}

final class UserDefaultsRecordingOutputDirectoryStore: RecordingOutputDirectoryStoring {
    private let defaults: UserDefaults
    private let key = "recording.outputDirectoryPath"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var outputDirectoryPath: String? {
        get { defaults.string(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}

final class UserDefaultsLastRecordingConfigurationStore: LastRecordingConfigurationStoring {
    private let defaults: UserDefaults
    private let key = "recording.lastConfiguration"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var configuration: LastRecordingConfiguration? {
        get {
            guard let data = defaults.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(LastRecordingConfiguration.self, from: data)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: key)
                return
            }

            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: key)
            }
        }
    }
}

struct CompletedRecordingSummary: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    var warnings: [String]
    var editableName: String
    let fileExtension: String

    var filename: String {
        if editableName.isEmpty {
            return "recording.\(fileExtension)"
        }
        return "\(editableName).\(fileExtension)"
    }
}

final class UserDefaultsFrameCoachSettingsStore: FrameCoachSettingsStoring {
    private enum Key {
        static let speechMode = "frameCoach.speechMode"
        static let feedbackFrequency = "frameCoach.feedbackFrequency"
        static let repeatInterval = "frameCoach.repeatInterval"
        static let showsOnScreenText = "frameCoach.showsOnScreenText"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var speechMode: FrameCoachSpeechMode {
        get {
            FrameCoachSpeechMode(rawValue: defaults.string(forKey: Key.speechMode) ?? "") ?? .automatic
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.speechMode)
        }
    }

    var feedbackFrequency: FrameCoachFeedbackFrequency {
        get {
            FrameCoachFeedbackFrequency(rawValue: defaults.string(forKey: Key.feedbackFrequency) ?? "") ?? .balanced
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.feedbackFrequency)
        }
    }

    var repeatInterval: FrameCoachRepeatInterval {
        get {
            FrameCoachRepeatInterval(rawValue: defaults.double(forKey: Key.repeatInterval)) ?? .medium
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.repeatInterval)
        }
    }

    var showsOnScreenText: Bool {
        get {
            if defaults.object(forKey: Key.showsOnScreenText) == nil {
                return true
            }
            return defaults.bool(forKey: Key.showsOnScreenText)
        }
        set {
            defaults.set(newValue, forKey: Key.showsOnScreenText)
        }
    }
}

@MainActor
@Observable
final class RecorderViewModel {
    var selectedPreset: RecordingPreset = .horizontalCamera {
        didSet { persistLastRecordingConfiguration() }
    }
    var selectedScreenCaptureSource: ScreenCaptureSource = .screen {
        didSet { persistLastRecordingConfiguration() }
    }
    var isScreenCameraOverlayEnabled = false {
        didSet { persistLastRecordingConfiguration() }
    }
    var selectedScreenCameraOverlayPosition: ScreenCameraOverlayPosition = .bottomRight
    var selectedScreenCameraOverlaySize: ScreenCameraOverlaySize = .medium
    var isSystemAudioEnabled = false {
        didSet { persistLastRecordingConfiguration() }
    }
    var isCursorHighlightEnabled = false {
        didSet { persistLastRecordingConfiguration() }
    }
    var isKeyboardShortcutOverlayEnabled = false {
        didSet { persistLastRecordingConfiguration() }
    }
    var microphoneVolume: Float = 1.0
    var systemAudioVolume: Float = 1.0
    var selectedRecordingSource: RecordingSource = .camera {
        didSet { persistLastRecordingConfiguration() }
    }
    var cameras: [InputDevice] = []
    var microphones: [InputDevice] = []
    var availableDisplays: [ScreenDisplayOption] = []
    var availableWindows: [ScreenWindowOption] = []
    var selectedCameraID: String = "" {
        didSet { persistLastRecordingConfiguration() }
    }
    var selectedMicrophoneID: String = "" {
        didSet { persistLastRecordingConfiguration() }
    }
    var selectedDisplayID: String = "" {
        didSet { persistLastRecordingConfiguration() }
    }
    var selectedWindowID: String = "" {
        didSet { persistLastRecordingConfiguration() }
    }
    var selectedMode: RecordingMode = .horizontal1080p {
        didSet { persistLastRecordingConfiguration() }
    }
    var isRecording = false
    var isPaused = false
    var isPreparingRecording = false
    var countdownRemaining: Int = 0
    var recordingCountdown: RecordingCountdown = .none {
        didSet { UserDefaults.standard.set(recordingCountdown.rawValue, forKey: "recording.countdown") }
    }
    var maxRecordingDuration: MaxRecordingDuration = .unlimited {
        didSet { UserDefaults.standard.set(maxRecordingDuration.rawValue, forKey: "recording.maxDuration") }
    }
    var isAutoReframeEnabled = true {
        didSet { persistLastRecordingConfiguration() }
    }
    var isFrameCoachEnabled = false {
        didSet { persistLastRecordingConfiguration() }
    }
    var statusText = String(localized: "Hazır")
    var permissionStatusText = String(localized: "İzin durumu kontrol edilmedi")
    var currentFrameCoachInstruction: String?
    var frameCoachSpeechMode: FrameCoachSpeechMode = .automatic {
        didSet { frameCoachSettingsStore.speechMode = frameCoachSpeechMode }
    }
    var frameCoachFeedbackFrequency: FrameCoachFeedbackFrequency = .balanced {
        didSet { frameCoachSettingsStore.feedbackFrequency = frameCoachFeedbackFrequency }
    }
    var frameCoachRepeatInterval: FrameCoachRepeatInterval = .medium {
        didSet { frameCoachSettingsStore.repeatInterval = frameCoachRepeatInterval }
    }
    var showsFrameCoachTextOnScreen = true {
        didSet { frameCoachSettingsStore.showsOnScreenText = showsFrameCoachTextOnScreen }
    }
    var frameCoachSpatialAudioMode: FrameCoachSpatialAudioMode = .off {
        didSet { UserDefaults.standard.set(frameCoachSpatialAudioMode.rawValue, forKey: "frameCoach.spatialAudioMode") }
    }
    var playsFrameCoachCenterConfirmation = true {
        didSet { UserDefaults.standard.set(playsFrameCoachCenterConfirmation, forKey: "frameCoach.playsCenterConfirmation") }
    }

    var currentAutoReframeCrop: AutoReframeCrop = .fullFrame
    var lastAutoReframeKeyframeCount = 0
    var lastAutoReframeUsedVideoComposition = false
    var lastAutoReframeUsedFallbackExport = false
    var lastAutoReframeStrategy = String(localized: "hazır")
    var lastSavedURL: URL?
    var completedRecording: CompletedRecordingSummary?
    var appAccessState: AppAccessState = .default
    var isPaywallPresented = false
    var purchasingPlan: AppAccessPlan?
    var isRestoringPurchases = false
    var paywallMessageText: String?
    var errorText: String?
    var screenPermissionNeedsRestart = false
    var permissionInteractionStates: [PermissionKind: PermissionInteractionState] = [:]
    private var screenPermissionConfirmedBySourceFetch = false
    var recordingOutputDirectoryURL: URL {
        didSet {
            recordingOutputDirectoryStore.outputDirectoryPath = recordingOutputDirectoryURL.path
        }
    }

    var recordingOutputDirectoryPath: String {
        recordingOutputDirectoryURL.path
    }

    var currentRecordingDuration: TimeInterval? {
        guard isRecording, let recordingStartUptime else { return nil }
        let elapsed = ProcessInfo.processInfo.systemUptime - recordingStartUptime
        let pausedOffset = currentPauseStartOffset.map { max(0, elapsed - $0) } ?? 0
        return max(0, elapsed - recordingPauseTimeline.totalPausedDuration - pausedOffset)
    }

    var cameraPermissionStatus: AVAuthorizationStatus {
        permissionProvider.authorizationStatus(for: .video)
    }

    var microphonePermissionStatus: AVAuthorizationStatus {
        permissionProvider.authorizationStatus(for: .audio)
    }

    var screenRecordingPermissionStatus: ScreenRecordingAuthorizationStatus {
        if screenPermissionConfirmedBySourceFetch {
            return .authorized
        }
        return screenRecordingProvider.authorizationStatus()
    }

    var permissionHubItems: [PermissionHubItem] {
        [
            makeCameraPermissionItem(),
            makeMicrophonePermissionItem(),
            makeScreenRecordingPermissionItem()
        ]
    }

    var accessibilitySetupSummary: String {
        switch selectedPreset {
        case .horizontalCamera, .verticalCamera:
            var parts = [
                String(localized: "Kamera \(selectedCameraNameOrFallback)"),
                String(localized: "mikrofon \(selectedMicrophoneNameOrFallback(required: true))"),
                isSystemAudioEnabled
                    ? String(localized: "sistem sesi açık")
                    : String(localized: "sistem sesi kapalı")
            ]
            if showsFrameCoachControls {
                parts.append(
                    isFrameCoachEnabled
                        ? String(localized: "kadraj koçu açık")
                        : String(localized: "kadraj koçu kapalı")
                )
            }
            return parts.joined(separator: ", ") + "."
        case .horizontalScreen, .verticalScreen:
            var parts = [
                selectedScreenCaptureSource == .screen
                    ? String(localized: "Kaynak tam ekran")
                    : String(localized: "Kaynak pencere")
            ]
            if selectedScreenCaptureSource == .screen {
                parts.append(String(localized: "ekran \(selectedDisplayNameOrFallback)"))
            } else {
                parts.append(String(localized: "pencere \(selectedWindowNameOrFallback)"))
            }
            parts.append(String(localized: "mikrofon \(selectedMicrophoneNameOrFallback(required: false))"))
            parts.append(
                isSystemAudioEnabled
                    ? String(localized: "sistem sesi açık")
                    : String(localized: "sistem sesi kapalı")
            )
            if showsScreenControls {
                parts.append(
                    isCursorHighlightEnabled
                        ? String(localized: "imleç vurgusu açık")
                        : String(localized: "imleç vurgusu kapalı")
                )
            }
            if isKeyboardShortcutOverlayEnabled {
                parts.append(String(localized: "klavye kısayolları açık"))
            }
            if isScreenCameraOverlayEnabled {
                parts.append(String(localized: "kamera kutusu açık"))
            }
            return parts.joined(separator: ", ") + "."
        case .audioOnly:
            return [
                String(localized: "Mikrofon \(selectedMicrophoneNameOrFallback(required: false))"),
                isSystemAudioEnabled
                    ? String(localized: "sistem sesi açık")
                    : String(localized: "sistem sesi kapalı")
            ].joined(separator: ", ") + "."
        }
    }

    var accessibilityPermissionSummary: String? {
        guard hasBlockingPermissionIssue else { return nil }
        let pendingTitles = requiredPermissionItems
            .filter { !$0.isSatisfied }
            .sorted { permissionPriority($0.id) < permissionPriority($1.id) }
            .map { $0.title.lowercased() }
        guard !pendingTitles.isEmpty else { return nil }
        return String(localized: "Eksik izinler: \(pendingTitles.joined(separator: ", ")).")
    }

    private func permissionPriority(_ kind: PermissionKind) -> Int {
        switch (selectedRecordingSource, kind) {
        case (.screen, .screenRecording), (.window, .screenRecording):
            return 0
        case (.camera, .camera):
            return 0
        case (_, .camera):
            return 1
        case (_, .microphone):
            return 2
        case (_, .screenRecording):
            return 3
        }
    }

    var requiredPermissionItems: [PermissionHubItem] {
        permissionHubItems.filter(\.isRequired)
    }

    var hasBlockingPermissionIssue: Bool {
        requiredPermissionItems.contains(where: { !$0.isSatisfied })
    }

    var canProceedPastOnboarding: Bool {
        !hasBlockingPermissionIssue
    }

    var shouldShowPermissionHub: Bool {
        true
    }

    var shouldShowPrivacySettingsButton: Bool {
        cameraPermissionStatus == .denied || microphonePermissionStatus == .denied
    }

    var previewSession: AVCaptureSession {
        recorder.session
    }

    var screenOverlayPreviewSession: AVCaptureSession {
        cameraOverlayRecorder.session
    }

    var canChooseCamera: Bool {
        cameraPermissionStatus == .authorized && !cameras.isEmpty
    }

    var canChooseMicrophone: Bool {
        microphonePermissionStatus == .authorized && !microphones.isEmpty
    }

    var showsCameraControls: Bool {
        selectedPreset.isCameraPreset
    }

    var showsScreenControls: Bool {
        selectedPreset.isScreenPreset
    }

    var showsScreenSourcePicker: Bool {
        selectedPreset.isScreenPreset
    }

    var showsScreenPicker: Bool {
        selectedPreset.isScreenPreset && selectedScreenCaptureSource == .screen
    }

    var showsWindowPicker: Bool {
        selectedPreset.isScreenPreset && selectedScreenCaptureSource == .window
    }

    var showsFrameCoachControls: Bool {
        selectedPreset.isCameraPreset || (selectedPreset.isScreenPreset && isScreenCameraOverlayEnabled)
    }

    var showsScreenOverlayControls: Bool {
        selectedPreset.isScreenPreset
    }

    var showsScreenOverlayConfiguration: Bool {
        selectedPreset.isScreenPreset && isScreenCameraOverlayEnabled
    }

    var showsScreenSourceSection: Bool {
        showsScreenControls
    }

    var showsScreenAudioSection: Bool {
        showsScreenControls
    }

    var showsMicrophonePicker: Bool {
        true
    }

    var showsMicrophoneVolumeControl: Bool {
        microphonePermissionStatus == .authorized && !selectedMicrophoneID.isEmpty
    }

    var showsSystemAudioVolumeControl: Bool {
        isSystemAudioEnabled
    }

    var currentPresetReadinessLabel: String {
        switch selectedRecordingSource {
        case .camera:
            return selectedPreset.readinessLabel
        case .screen:
            return selectedMode == .vertical1080p ? String(localized: "Dikey ekran kaydı") : String(localized: "Yatay ekran kaydı")
        case .window:
            return selectedMode == .vertical1080p ? String(localized: "Dikey pencere kaydı") : String(localized: "Yatay pencere kaydı")
        case .audio:
            return String(localized: "Ses kaydı")
        }
    }

    var canStartRecording: Bool {
        switch selectedRecordingSource {
        case .camera:
            return hasRequiredPermissions
                && (!isSystemAudioEnabled || screenRecordingPermissionStatus == .authorized)
                && !selectedCameraID.isEmpty
                && !selectedMicrophoneID.isEmpty
                && !isPreparingRecording
                && !isCountingDown
        case .screen:
            return screenRecordingPermissionStatus == .authorized
                && !selectedDisplayID.isEmpty
                && screenOverlayReadiness.isReady
                && !isPreparingRecording
                && !isCountingDown
        case .window:
            return screenRecordingPermissionStatus == .authorized
                && !selectedWindowID.isEmpty
                && screenOverlayReadiness.isReady
                && !isPreparingRecording
                && !isCountingDown
        case .audio:
            return (!selectedMicrophoneID.isEmpty || isSystemAudioEnabled)
                && (selectedMicrophoneID.isEmpty || microphonePermissionStatus == .authorized)
                && (!isSystemAudioEnabled || screenRecordingPermissionStatus == .authorized)
                && !isPreparingRecording
                && !isCountingDown
        }
    }

    var canPauseRecording: Bool {
        isRecording && !isPreparingRecording && pauseResumeTask == nil
    }

    var pauseResumeButtonTitle: String {
        isPaused ? String(localized: "Devam Et") : String(localized: "Duraklat")
    }

    var isCountingDown: Bool { countdownRemaining > 0 }

    private let recorder: any CaptureRecording
    private let screenRecordingProvider: any ScreenRecordingProviding
    private let cameraOverlayRecorder: any CameraOverlayRecording
    private let systemAudioRecorder: any SystemAudioRecordingProviding
    private let microphoneAudioRecorder: any MicrophoneAudioRecordingProviding
    private let audioRecordingExporter: any AudioRecordingExporting
    private let cursorHighlightRecorder: any CursorHighlightRecordingProviding
    private let keyboardShortcutRecorder: any KeyboardShortcutRecordingProviding

    private var hasSetUp = false
    private var isRecorderConfigured = false
    private var lastAnnouncedSubjectCount: FrameSubjectCount?
    private var consecutiveMissingFaceAnalyses = 0
    private var lastGoodFrameAt: Date?
    private var lastGoodInstruction: String?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var recordingDurationTask: Task<Void, Never>?
    @ObservationIgnored private var pauseResumeTask: Task<Void, Never>?
    @ObservationIgnored private var sleepPreventer = SleepPreventer()
    private var autoReframeSmoother = AutoReframeSmoother()
    private var autoReframeTimeline = AutoReframeTimeline()
    private let fileNamer: RecordingFileNamer
    private let frameAnalysisService: FrameAnalysisService
    private let frameCoachingEngine: FrameCoachingEngine
    private let captureCoachingEngine: CaptureCoachingEngine
    private let frameLightingAnalyzer = FrameLightingAnalyzer()
    private let autoReframeEngine: AutoReframeEngine
    private let autoReframeCompositionBuilder: AutoReframeCompositionBuilder
    private let recordingAudioMixBuilder: RecordingAudioMixBuilder
    private let screenCameraOverlayCompositionBuilder: ScreenCameraOverlayCompositionBuilder
    private let soundEffectPlayer: any SoundEffectPlaying
    private let speechCuePlayer: SpeechCuePlayer
    private let spatialCuePlayer: any SpatialCuePlaying
    private let frameCoachSettingsStore: any FrameCoachSettingsStoring
    private let recordingOutputDirectoryStore: any RecordingOutputDirectoryStoring
    private let lastRecordingConfigurationStore: any LastRecordingConfigurationStoring
    private let permissionProvider: any MediaPermissionProviding
    private let appAccessManager: any AppAccessManaging
    private let isAccessibilityPermissionGranted: () -> Bool
    private let openURL: (URL) -> Void
    private let revealInFinder: (URL) -> Void
    private let chooseOutputDirectory: (URL) -> URL?
    private let chooseSaveDestination: (URL) -> URL?
    private var pendingScreenRecordingFinalURL: URL?
    private var pendingScreenCaptureResult: Result<URL, Error>?
    private var pendingOverlayCaptureResult: Result<URL?, Error>?
    private var pendingScreenOverlayPosition: ScreenCameraOverlayPosition = .bottomRight
    private var pendingScreenOverlaySize: ScreenCameraOverlaySize = .medium
    private var pendingScreenOverlayCaptureURL: URL?
    private var pendingScreenRecordingMode: RecordingMode = .horizontal1080p
    private var pendingScreenMicrophoneCaptureResult: Result<URL?, Error>?
    private var pendingScreenMicrophoneCaptureURL: URL?
    private var pendingScreenMicrophoneWarning: String?
    private var pendingScreenSystemAudioCaptureResult: Result<URL?, Error>?
    private var pendingScreenSystemAudioCaptureURL: URL?
    private var pendingScreenSystemAudioWarning: String?
    private var pendingScreenCursorTimeline = CursorHighlightTimeline.empty
    private var pendingScreenKeyboardShortcutTimeline = KeyboardShortcutTimeline.empty
    private var pendingCameraRecordingFinalURL: URL?
    private var pendingCameraCaptureResult: Result<URL, Error>?
    private var pendingCameraSystemAudioCaptureResult: Result<URL?, Error>?
    private var pendingCameraSystemAudioCaptureURL: URL?
    private var pendingCameraSystemAudioWarning: String?
    private var pendingAudioRecordingFinalURL: URL?
    private var pendingAudioMicrophoneCaptureResult: Result<URL?, Error>?
    private var pendingAudioMicrophoneCaptureURL: URL?
    private var pendingAudioMicrophoneWarning: String?
    private var pendingAudioSystemAudioCaptureResult: Result<URL?, Error>?
    private var pendingAudioSystemAudioCaptureURL: URL?
    private var pendingAudioSystemAudioWarning: String?
    private var isRestoringLastRecordingConfiguration = false
    private var recordingStartUptime: TimeInterval?
    private var currentPauseStartOffset: TimeInterval?
    private var recordingPauseTimeline = RecordingPauseTimeline()

    init(
        recorder: any CaptureRecording = CaptureRecorder(),
        screenRecordingProvider: any ScreenRecordingProviding = ScreenRecorder(),
        cameraOverlayRecorder: any CameraOverlayRecording = CameraOverlayRecorder(),
        systemAudioRecorder: any SystemAudioRecordingProviding = SystemAudioRecorder(),
        microphoneAudioRecorder: any MicrophoneAudioRecordingProviding = MicrophoneAudioRecorder(),
        audioRecordingExporter: any AudioRecordingExporting = AudioRecordingExporter(),
        cursorHighlightRecorder: any CursorHighlightRecordingProviding = CursorHighlightRecorder(),
        keyboardShortcutRecorder: any KeyboardShortcutRecordingProviding = KeyboardShortcutRecorder(),
        fileNamer: RecordingFileNamer = RecordingFileNamer(),
        frameAnalysisService: FrameAnalysisService = FrameAnalysisService(),
        frameCoachingEngine: FrameCoachingEngine = FrameCoachingEngine(),
        autoReframeEngine: AutoReframeEngine = AutoReframeEngine(),
        autoReframeCompositionBuilder: AutoReframeCompositionBuilder = AutoReframeCompositionBuilder(),
        recordingAudioMixBuilder: RecordingAudioMixBuilder = RecordingAudioMixBuilder(),
        screenCameraOverlayCompositionBuilder: ScreenCameraOverlayCompositionBuilder = ScreenCameraOverlayCompositionBuilder(),
        soundEffectPlayer: any SoundEffectPlaying = SoundEffectPlayer(),
        frameCoachSettingsStore: any FrameCoachSettingsStoring = UserDefaultsFrameCoachSettingsStore(),
        recordingOutputDirectoryStore: any RecordingOutputDirectoryStoring = UserDefaultsRecordingOutputDirectoryStore(),
        lastRecordingConfigurationStore: any LastRecordingConfigurationStoring = UserDefaultsLastRecordingConfigurationStore(),
        permissionProvider: any MediaPermissionProviding = SystemMediaPermissionProvider(),
        appAccessManager: (any AppAccessManaging)? = nil,
        isAccessibilityPermissionGranted: @escaping () -> Bool = { AXIsProcessTrusted() },
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        revealInFinder: @escaping (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
        chooseOutputDirectory: @escaping (URL) -> URL? = { currentURL in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.directoryURL = currentURL
            panel.prompt = String(localized: "Klasörü Seç")
            return panel.runModal() == .OK ? panel.url : nil
        },
        chooseSaveDestination: @escaping (URL) -> URL? = { suggestedURL in
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = suggestedURL.lastPathComponent
            panel.directoryURL = suggestedURL.deletingLastPathComponent()
            panel.allowedContentTypes = suggestedURL.pathExtension.lowercased() == "m4a" ? [.audio] : [.mpeg4Movie]
            return panel.runModal() == .OK ? panel.url : nil
        },
        speechCuePlayer: SpeechCuePlayer = SpeechCuePlayer(),
        spatialCuePlayer: any SpatialCuePlaying = SpatialCoachCuePlayer()
    ) {
        self.recorder = recorder
        self.screenRecordingProvider = screenRecordingProvider
        self.cameraOverlayRecorder = cameraOverlayRecorder
        self.systemAudioRecorder = systemAudioRecorder
        self.microphoneAudioRecorder = microphoneAudioRecorder
        self.audioRecordingExporter = audioRecordingExporter
        self.cursorHighlightRecorder = cursorHighlightRecorder
        self.keyboardShortcutRecorder = keyboardShortcutRecorder
        self.fileNamer = fileNamer
        self.frameAnalysisService = frameAnalysisService
        self.frameCoachingEngine = frameCoachingEngine
        self.captureCoachingEngine = CaptureCoachingEngine(frameCoachingEngine: frameCoachingEngine)
        self.autoReframeEngine = autoReframeEngine
        self.autoReframeCompositionBuilder = autoReframeCompositionBuilder
        self.recordingAudioMixBuilder = recordingAudioMixBuilder
        self.screenCameraOverlayCompositionBuilder = screenCameraOverlayCompositionBuilder
        self.soundEffectPlayer = soundEffectPlayer
        self.frameCoachSettingsStore = frameCoachSettingsStore
        self.recordingOutputDirectoryStore = recordingOutputDirectoryStore
        self.lastRecordingConfigurationStore = lastRecordingConfigurationStore
        self.permissionProvider = permissionProvider
        self.appAccessManager = appAccessManager ?? AppAccessManager()
        self.isAccessibilityPermissionGranted = isAccessibilityPermissionGranted
        self.openURL = openURL
        self.revealInFinder = revealInFinder
        self.chooseOutputDirectory = chooseOutputDirectory
        self.chooseSaveDestination = chooseSaveDestination
        self.speechCuePlayer = speechCuePlayer
        self.spatialCuePlayer = spatialCuePlayer
        self.frameCoachSpeechMode = frameCoachSettingsStore.speechMode
        self.frameCoachFeedbackFrequency = frameCoachSettingsStore.feedbackFrequency
        self.frameCoachRepeatInterval = frameCoachSettingsStore.repeatInterval
        self.showsFrameCoachTextOnScreen = frameCoachSettingsStore.showsOnScreenText
        self.frameCoachSpatialAudioMode = FrameCoachSpatialAudioMode(
            rawValue: UserDefaults.standard.string(forKey: "frameCoach.spatialAudioMode") ?? ""
        ) ?? .off
        self.playsFrameCoachCenterConfirmation = UserDefaults.standard.object(forKey: "frameCoach.playsCenterConfirmation") as? Bool ?? true
        if let storedOutputPath = recordingOutputDirectoryStore.outputDirectoryPath {
            self.recordingOutputDirectoryURL = URL(fileURLWithPath: storedOutputPath, isDirectory: true)
        } else {
            self.recordingOutputDirectoryURL = fileNamer.outputDirectory
        }
        if let configuration = lastRecordingConfigurationStore.configuration {
            restoreLastRecordingConfiguration(configuration)
        }
    }

    convenience init(
        recorder: any CaptureRecording = CaptureRecorder(),
        screenRecordingProvider: any ScreenRecordingProviding = ScreenRecorder(),
        cameraOverlayRecorder: any CameraOverlayRecording = CameraOverlayRecorder(),
        systemAudioRecorder: any SystemAudioRecordingProviding = SystemAudioRecorder(),
        microphoneAudioRecorder: any MicrophoneAudioRecordingProviding = MicrophoneAudioRecorder(),
        audioRecordingExporter: any AudioRecordingExporting = AudioRecordingExporter(),
        cursorHighlightRecorder: any CursorHighlightRecordingProviding = CursorHighlightRecorder(),
        keyboardShortcutRecorder: any KeyboardShortcutRecordingProviding = KeyboardShortcutRecorder(),
        fileNamer: RecordingFileNamer = RecordingFileNamer(),
        frameAnalysisService: FrameAnalysisService = FrameAnalysisService(),
        frameCoachingEngine: FrameCoachingEngine = FrameCoachingEngine(),
        autoReframeEngine: AutoReframeEngine = AutoReframeEngine(),
        autoReframeCompositionBuilder: AutoReframeCompositionBuilder = AutoReframeCompositionBuilder(),
        recordingAudioMixBuilder: RecordingAudioMixBuilder = RecordingAudioMixBuilder(),
        screenCameraOverlayCompositionBuilder: ScreenCameraOverlayCompositionBuilder = ScreenCameraOverlayCompositionBuilder(),
        soundEffectPlayer: any SoundEffectPlaying = SoundEffectPlayer(),
        frameCoachSettingsStore: any FrameCoachSettingsStoring = UserDefaultsFrameCoachSettingsStore(),
        permissionProvider: any MediaPermissionProviding = SystemMediaPermissionProvider(),
        isAccessibilityPermissionGranted: @escaping () -> Bool = { AXIsProcessTrusted() },
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        speechCuePlayer: SpeechCuePlayer = SpeechCuePlayer(),
        spatialCuePlayer: any SpatialCuePlaying = SpatialCoachCuePlayer()
    ) {
        self.init(
            recorder: recorder,
            screenRecordingProvider: screenRecordingProvider,
            cameraOverlayRecorder: cameraOverlayRecorder,
            systemAudioRecorder: systemAudioRecorder,
            microphoneAudioRecorder: microphoneAudioRecorder,
            audioRecordingExporter: audioRecordingExporter,
            cursorHighlightRecorder: cursorHighlightRecorder,
            keyboardShortcutRecorder: keyboardShortcutRecorder,
            fileNamer: fileNamer,
            frameAnalysisService: frameAnalysisService,
            frameCoachingEngine: frameCoachingEngine,
            autoReframeEngine: autoReframeEngine,
            autoReframeCompositionBuilder: autoReframeCompositionBuilder,
            recordingAudioMixBuilder: recordingAudioMixBuilder,
            screenCameraOverlayCompositionBuilder: screenCameraOverlayCompositionBuilder,
            soundEffectPlayer: soundEffectPlayer,
            frameCoachSettingsStore: frameCoachSettingsStore,
            recordingOutputDirectoryStore: UserDefaultsRecordingOutputDirectoryStore(),
            permissionProvider: permissionProvider,
            isAccessibilityPermissionGranted: isAccessibilityPermissionGranted,
            openURL: openURL,
            revealInFinder: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
            chooseOutputDirectory: { currentURL in
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.canCreateDirectories = true
                panel.directoryURL = currentURL
                panel.prompt = String(localized: "Klasörü Seç")
                return panel.runModal() == .OK ? panel.url : nil
            },
            chooseSaveDestination: { suggestedURL in
                let panel = NSSavePanel()
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = suggestedURL.lastPathComponent
                panel.directoryURL = suggestedURL.deletingLastPathComponent()
                panel.allowedContentTypes = suggestedURL.pathExtension.lowercased() == "m4a" ? [.audio] : [.mpeg4Movie]
                return panel.runModal() == .OK ? panel.url : nil
            },
            speechCuePlayer: speechCuePlayer,
            spatialCuePlayer: spatialCuePlayer
        )
    }

    convenience init(
        recorder: any CaptureRecording = CaptureRecorder(),
        screenRecordingProvider: any ScreenRecordingProviding = ScreenRecorder(),
        cameraOverlayRecorder: any CameraOverlayRecording = CameraOverlayRecorder(),
        microphoneAudioRecorder: any MicrophoneAudioRecordingProviding = MicrophoneAudioRecorder(),
        audioRecordingExporter: any AudioRecordingExporting = AudioRecordingExporter(),
        cursorHighlightRecorder: any CursorHighlightRecordingProviding = CursorHighlightRecorder(),
        keyboardShortcutRecorder: any KeyboardShortcutRecordingProviding = KeyboardShortcutRecorder(),
        fileNamer: RecordingFileNamer = RecordingFileNamer(),
        frameAnalysisService: FrameAnalysisService = FrameAnalysisService(),
        frameCoachingEngine: FrameCoachingEngine = FrameCoachingEngine(),
        autoReframeEngine: AutoReframeEngine = AutoReframeEngine(),
        autoReframeCompositionBuilder: AutoReframeCompositionBuilder = AutoReframeCompositionBuilder(),
        recordingAudioMixBuilder: RecordingAudioMixBuilder = RecordingAudioMixBuilder(),
        screenCameraOverlayCompositionBuilder: ScreenCameraOverlayCompositionBuilder = ScreenCameraOverlayCompositionBuilder(),
        soundEffectPlayer: any SoundEffectPlaying = SoundEffectPlayer(),
        frameCoachSettingsStore: any FrameCoachSettingsStoring = UserDefaultsFrameCoachSettingsStore(),
        recordingOutputDirectoryStore: any RecordingOutputDirectoryStoring = UserDefaultsRecordingOutputDirectoryStore(),
        permissionProvider: any MediaPermissionProviding = SystemMediaPermissionProvider(),
        isAccessibilityPermissionGranted: @escaping () -> Bool = { AXIsProcessTrusted() },
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        revealInFinder: @escaping (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
        chooseOutputDirectory: @escaping (URL) -> URL? = { currentURL in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.directoryURL = currentURL
            panel.prompt = String(localized: "Klasörü Seç")
            return panel.runModal() == .OK ? panel.url : nil
        },
        chooseSaveDestination: @escaping (URL) -> URL? = { suggestedURL in
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = suggestedURL.lastPathComponent
            panel.directoryURL = suggestedURL.deletingLastPathComponent()
            panel.allowedContentTypes = suggestedURL.pathExtension.lowercased() == "m4a" ? [.audio] : [.mpeg4Movie]
            return panel.runModal() == .OK ? panel.url : nil
        },
        speechCuePlayer: SpeechCuePlayer = SpeechCuePlayer(),
        spatialCuePlayer: any SpatialCuePlaying = SpatialCoachCuePlayer()
    ) {
        self.init(
            recorder: recorder,
            screenRecordingProvider: screenRecordingProvider,
            cameraOverlayRecorder: cameraOverlayRecorder,
            systemAudioRecorder: SystemAudioRecorder(),
            microphoneAudioRecorder: microphoneAudioRecorder,
            audioRecordingExporter: audioRecordingExporter,
            cursorHighlightRecorder: cursorHighlightRecorder,
            keyboardShortcutRecorder: keyboardShortcutRecorder,
            fileNamer: fileNamer,
            frameAnalysisService: frameAnalysisService,
            frameCoachingEngine: frameCoachingEngine,
            autoReframeEngine: autoReframeEngine,
            autoReframeCompositionBuilder: autoReframeCompositionBuilder,
            recordingAudioMixBuilder: recordingAudioMixBuilder,
            screenCameraOverlayCompositionBuilder: screenCameraOverlayCompositionBuilder,
            soundEffectPlayer: soundEffectPlayer,
            frameCoachSettingsStore: frameCoachSettingsStore,
            recordingOutputDirectoryStore: recordingOutputDirectoryStore,
            permissionProvider: permissionProvider,
            isAccessibilityPermissionGranted: isAccessibilityPermissionGranted,
            openURL: openURL,
            revealInFinder: revealInFinder,
            chooseOutputDirectory: chooseOutputDirectory,
            chooseSaveDestination: chooseSaveDestination,
            speechCuePlayer: speechCuePlayer,
            spatialCuePlayer: spatialCuePlayer
        )
    }

    convenience init(
        recorder: any CaptureRecording = CaptureRecorder(),
        screenRecordingProvider: any ScreenRecordingProviding = ScreenRecorder(),
        cameraOverlayRecorder: any CameraOverlayRecording = CameraOverlayRecorder(),
        microphoneAudioRecorder: any MicrophoneAudioRecordingProviding = MicrophoneAudioRecorder(),
        audioRecordingExporter: any AudioRecordingExporting = AudioRecordingExporter(),
        cursorHighlightRecorder: any CursorHighlightRecordingProviding = CursorHighlightRecorder(),
        keyboardShortcutRecorder: any KeyboardShortcutRecordingProviding = KeyboardShortcutRecorder(),
        fileNamer: RecordingFileNamer = RecordingFileNamer(),
        frameAnalysisService: FrameAnalysisService = FrameAnalysisService(),
        frameCoachingEngine: FrameCoachingEngine = FrameCoachingEngine(),
        autoReframeEngine: AutoReframeEngine = AutoReframeEngine(),
        autoReframeCompositionBuilder: AutoReframeCompositionBuilder = AutoReframeCompositionBuilder(),
        recordingAudioMixBuilder: RecordingAudioMixBuilder = RecordingAudioMixBuilder(),
        screenCameraOverlayCompositionBuilder: ScreenCameraOverlayCompositionBuilder = ScreenCameraOverlayCompositionBuilder(),
        soundEffectPlayer: any SoundEffectPlaying = SoundEffectPlayer(),
        frameCoachSettingsStore: any FrameCoachSettingsStoring = UserDefaultsFrameCoachSettingsStore(),
        permissionProvider: any MediaPermissionProviding = SystemMediaPermissionProvider(),
        isAccessibilityPermissionGranted: @escaping () -> Bool = { AXIsProcessTrusted() },
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        speechCuePlayer: SpeechCuePlayer = SpeechCuePlayer(),
        spatialCuePlayer: any SpatialCuePlaying = SpatialCoachCuePlayer()
    ) {
        self.init(
            recorder: recorder,
            screenRecordingProvider: screenRecordingProvider,
            cameraOverlayRecorder: cameraOverlayRecorder,
            microphoneAudioRecorder: microphoneAudioRecorder,
            audioRecordingExporter: audioRecordingExporter,
            cursorHighlightRecorder: cursorHighlightRecorder,
            keyboardShortcutRecorder: keyboardShortcutRecorder,
            fileNamer: fileNamer,
            frameAnalysisService: frameAnalysisService,
            frameCoachingEngine: frameCoachingEngine,
            autoReframeEngine: autoReframeEngine,
            autoReframeCompositionBuilder: autoReframeCompositionBuilder,
            recordingAudioMixBuilder: recordingAudioMixBuilder,
            screenCameraOverlayCompositionBuilder: screenCameraOverlayCompositionBuilder,
            soundEffectPlayer: soundEffectPlayer,
            frameCoachSettingsStore: frameCoachSettingsStore,
            recordingOutputDirectoryStore: UserDefaultsRecordingOutputDirectoryStore(),
            permissionProvider: permissionProvider,
            isAccessibilityPermissionGranted: isAccessibilityPermissionGranted,
            openURL: openURL,
            revealInFinder: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
            chooseOutputDirectory: { currentURL in
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.canCreateDirectories = true
                panel.directoryURL = currentURL
                panel.prompt = String(localized: "Klasörü Seç")
                return panel.runModal() == .OK ? panel.url : nil
            },
            chooseSaveDestination: { suggestedURL in
                let panel = NSSavePanel()
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = suggestedURL.lastPathComponent
                panel.directoryURL = suggestedURL.deletingLastPathComponent()
                panel.allowedContentTypes = suggestedURL.pathExtension.lowercased() == "m4a" ? [.audio] : [.mpeg4Movie]
                return panel.runModal() == .OK ? panel.url : nil
            },
            speechCuePlayer: speechCuePlayer,
            spatialCuePlayer: spatialCuePlayer
        )
    }

    var frameCoachPreferences: FrameCoachPreferences {
        FrameCoachPreferences(
            speechMode: frameCoachSpeechMode,
            feedbackFrequency: frameCoachFeedbackFrequency,
            repeatInterval: frameCoachRepeatInterval,
            showsOnScreenText: showsFrameCoachTextOnScreen,
            spatialAudioMode: frameCoachSpatialAudioMode,
            playsCenterConfirmation: playsFrameCoachCenterConfirmation
        )
    }

    /// Warning message shown when keyboard shortcut overlay is enabled but
    /// macOS Accessibility permission has not been granted.
    var keyboardShortcutAccessibilityWarning: String? {
        guard isKeyboardShortcutOverlayEnabled else { return nil }
        guard !isAccessibilityPermissionGranted() else { return nil }
        return String(localized: "Klavye kısayollarını görmek için Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik'ten FrameMate'e izin ver.")
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        openURL(url)
    }

    private var activeFileNamer: RecordingFileNamer {
        RecordingFileNamer(outputDirectory: recordingOutputDirectoryURL)
    }

    func setup() async {
        guard !hasSetUp else { return }
        hasSetUp = true

        await refreshAppAccess()
        applyPresetSelection(refresh: false)
        recordingCountdown = RecordingCountdown(rawValue: UserDefaults.standard.integer(forKey: "recording.countdown")) ?? .none
        maxRecordingDuration = MaxRecordingDuration(rawValue: UserDefaults.standard.integer(forKey: "recording.maxDuration")) ?? .unlimited
        configureFrameCoachFeed()
        refreshDeviceState()
    }

    func refreshAppAccess() async {
        await appAccessManager.refresh()
        syncAppAccessState()
    }

    func requestCameraPermission() {
        permissionInteractionStates[.camera] = .requesting
        Task {
            let granted = await permissionProvider.requestAccess(for: .video)
            permissionInteractionStates[.camera] = granted ? .granted : .denied
            refreshDeviceState()
        }
    }

    func requestMicrophonePermission() {
        permissionInteractionStates[.microphone] = .requesting
        Task {
            let granted = await permissionProvider.requestAccess(for: .audio)
            permissionInteractionStates[.microphone] = granted ? .granted : .denied
            refreshDeviceState()
        }
    }

    func requestScreenRecordingPermission() {
        permissionInteractionStates[.screenRecording] = .requesting
        Task {
            let result = await screenRecordingProvider.requestAccess()
            screenPermissionNeedsRestart = (result == .grantedButRequiresRestart)
            switch result {
            case .granted:
                permissionInteractionStates[.screenRecording] = .granted
            case .denied:
                permissionInteractionStates[.screenRecording] = .denied
            case .grantedButRequiresRestart:
                permissionInteractionStates[.screenRecording] = .needsRestart
            }
            refreshDeviceState()
        }
    }

    func refreshDeviceState() {
        syncPresetFromCurrentSelection()
        if screenRecordingPermissionStatus == .authorized {
            screenPermissionNeedsRestart = false
        }
        refreshPermissionStatus()
        syncAvailableDevices()
        statusText = makeStatusText()
        if !hasRequiredPermissions {
            isRecorderConfigured = false
        }
        Task {
            await refreshScreenRecordingSources()
        }
        if isFrameCoachEnabled || isAutoReframeEnabled {
            Task {
                await prepareAnalysisPreviewIfPossible()
            }
        }
        updateScreenOverlayPreviewState()
    }

    func applySelectedInputs() {
        guard hasSetUp, !isRecording else { return }
        guard selectedPreset.isCameraPreset else {
            statusText = makeStatusText()
            errorText = nil
            updateScreenOverlayPreviewState()
            return
        }

        Task {
            do {
                try await configureRecorder()
                if isFrameCoachEnabled || isAutoReframeEnabled {
                    recorder.startSessionInBackground()
                }
                statusText = String(localized: "\(currentPresetReadinessLabel) hazır.")
                errorText = nil
            } catch {
                report(error)
            }
        }
    }

    func configureRecorder() async throws {
        try validateRecordingReadiness()

        guard !selectedCameraID.isEmpty else {
            throw CaptureRecorderError.cameraNotFound
        }
        guard !selectedMicrophoneID.isEmpty else {
            throw CaptureRecorderError.microphoneNotFound
        }

        try await recorder.configure(
            videoDeviceID: selectedCameraID,
            audioDeviceID: selectedMicrophoneID,
            mode: selectedMode
        )
        isRecorderConfigured = true
    }

    func toggleRecording() {
        guard !isPreparingRecording else { return }

        if isRecording {
            stopRecording()
            return
        }

        if isCountingDown {
            cancelCountdown()
            return
        }

        guard ensureRecordingAccess() else { return }
        guard ensureSelectedRecordingCanStart() else { return }

        if recordingCountdown == .none {
            startRecording()
        } else {
            beginCountdown()
        }
    }

    func togglePauseResume() {
        guard canPauseRecording else { return }

        if isPaused {
            completeResumeAfterTransitionSound(duration: soundEffectPlayer.playPauseResume())
        } else {
            beginCurrentPauseRange()
            isPaused = true
            soundEffectPlayer.playPauseResume()
            statusText = selectedRecordingSource == .audio
                ? String(localized: "Ses kaydı duraklatıldı")
                : String(localized: "Kayıt duraklatıldı")
            sleepPreventer.allow()
            recordingDurationTask?.cancel()
            recordingDurationTask = nil
        }
    }

    private func beginPauseTracking() {
        pauseResumeTask?.cancel()
        pauseResumeTask = nil
        recordingStartUptime = ProcessInfo.processInfo.systemUptime
        currentPauseStartOffset = nil
        recordingPauseTimeline = .empty
        isPaused = false
    }

    private func completeResumeAfterTransitionSound(duration: TimeInterval) {
        pauseResumeTask?.cancel()
        let delay = max(0, duration)
        guard delay > 0 else {
            completeResumeFromPause()
            return
        }

        pauseResumeTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            await MainActor.run {
                self?.completeResumeFromPause()
            }
        }
    }

    private func completeResumeFromPause() {
        pauseResumeTask = nil
        guard isRecording, isPaused else { return }

        finishCurrentPauseRange()
        isPaused = false
        statusText = selectedRecordingSource == .audio ? String(localized: "Ses kaydı yapılıyor") : String(localized: "Kayıt yapılıyor")
        sleepPreventer.prevent(reason: selectedRecordingSource == .audio ? String(localized: "Ses kaydı devam ediyor") : String(localized: "Video kaydı devam ediyor"))
        startMaxDurationTimer()
    }

    private func beginCurrentPauseRange() {
        guard let recordingStartUptime else { return }
        currentPauseStartOffset = max(0, ProcessInfo.processInfo.systemUptime - recordingStartUptime)
    }

    private func finishCurrentPauseRange() {
        guard let pauseStart = currentPauseStartOffset,
              let recordingStartUptime else {
            return
        }

        let pauseEnd = max(pauseStart, ProcessInfo.processInfo.systemUptime - recordingStartUptime)
        if pauseEnd > pauseStart {
            recordingPauseTimeline.ranges.append(RecordingPauseRange(start: pauseStart, end: pauseEnd))
        }
        currentPauseStartOffset = nil
    }

    private func beginCountdown() {
        countdownRemaining = recordingCountdown.rawValue
        statusText = String(localized: "Kayıt \(countdownRemaining) saniye sonra başlıyor…")
        countdownTask = Task { [weak self] in
            guard let self else { return }
            do {
                while await MainActor.run(body: { self.countdownRemaining }) > 0 {
                    let remaining = await MainActor.run(body: { self.countdownRemaining })
                    await MainActor.run {
                        self.speechCuePlayer.speakIfNeeded(
                            "\(remaining)",
                            isEnabled: true,
                            key: "countdown-\(remaining)"
                        )
                    }
                    try await Task.sleep(for: .seconds(1))
                    await MainActor.run { self.countdownRemaining -= 1 }
                    await MainActor.run {
                        if self.countdownRemaining > 0 {
                            self.statusText = String(localized: "Kayıt \(self.countdownRemaining) saniye sonra başlıyor…")
                        }
                    }
                }
                await MainActor.run { self.startRecording() }
            } catch {
                // CancellationError: cancelled via cancelCountdown()
                await MainActor.run {
                    self.countdownRemaining = 0
                    self.statusText = String(localized: "İptal edildi")
                    self.speechCuePlayer.speakIfNeeded(String(localized: "iptal edildi"), isEnabled: true, key: "countdown-cancel")
                }
            }
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdownRemaining = 0
        // statusText is reset inside the task's catch block (if a task was running).
        // countdownRemaining is reset here synchronously so that callers can observe
        // the change immediately (e.g., in tests where no Task was started).
    }

    func toggleFrameCoach() {
        isFrameCoachEnabled.toggle()
        updatePreviewAnalysisState()

        if isFrameCoachEnabled {
            currentFrameCoachInstruction = String(localized: "Kadraj koçu açık")
            speechCuePlayer.reset()
            lastAnnouncedSubjectCount = nil
            consecutiveMissingFaceAnalyses = 0
            lastGoodFrameAt = nil
            lastGoodInstruction = nil
            speechCuePlayer.speakIfNeeded(String(localized: "Kadraj koçu açık"), isEnabled: true, settings: frameCoachPreferences)
            Task {
                await prepareAnalysisPreviewIfPossible()
            }
        } else {
            currentFrameCoachInstruction = nil
            speechCuePlayer.reset()
            spatialCuePlayer.reset()
            consecutiveMissingFaceAnalyses = 0
            lastGoodFrameAt = nil
            lastGoodInstruction = nil
            speechCuePlayer.speakIfNeeded(String(localized: "Kadraj koçu kapalı"), isEnabled: true, settings: frameCoachPreferences)
        }
    }

    func toggleAutoReframe() {
        isAutoReframeEnabled.toggle()

        if isAutoReframeEnabled {
            updatePreviewAnalysisState()
            Task {
                await prepareAnalysisPreviewIfPossible()
            }
        } else {
            autoReframeSmoother.reset()
            currentAutoReframeCrop = .fullFrame
            updatePreviewAnalysisState()
        }
    }

    func updateFrameCoachInstruction(_ instruction: String) {
        guard isFrameCoachEnabled else { return }

        currentFrameCoachInstruction = instruction
        speechCuePlayer.speakIfNeeded(instruction, isEnabled: isFrameCoachEnabled, key: instruction, settings: frameCoachPreferences)
    }

    func processFrameCoachAnalysis(_ analysis: FrameAnalysis?) {
        processCaptureCoachAnalysis(frameAnalysis: analysis, lightingAnalysis: nil)
    }

    func processCaptureCoachAnalysis(
        frameAnalysis analysis: FrameAnalysis?,
        lightingAnalysis: FrameLightingAnalysis?
    ) {
        guard isFrameCoachEnabled else { return }
        let spatialCueResolver = FrameCoachSpatialCueResolver()

        guard let analysis else {
            if lightingAnalysis?.isLowLight == true {
                currentFrameCoachInstruction = CaptureCoachingEngine.lowLightInstruction
                speechCuePlayer.speakIfNeeded(
                    CaptureCoachingEngine.lowLightInstruction.sentenceCased,
                    isEnabled: true,
                    settings: frameCoachPreferences
                )
                return
            }

            consecutiveMissingFaceAnalyses += 1
            guard consecutiveMissingFaceAnalyses >= 3 else { return }
            currentFrameCoachInstruction = String(localized: "Yüz algılanamıyor")
            speechCuePlayer.speakIfNeeded(String(localized: "Yüz algılanamıyor"), isEnabled: true, settings: frameCoachPreferences)
            return
        }

        consecutiveMissingFaceAnalyses = 0
        let guidance = captureCoachingEngine.instruction(
            frameAnalysis: analysis,
            lightingAnalysis: lightingAnalysis,
            mode: selectedMode,
            profile: automaticFrameCoachingProfile(for: analysis)
        )
        if let cue = spatialCueResolver.cue(for: analysis, guidance: guidance, mode: selectedMode) {
            spatialCuePlayer.play(cue, preferences: frameCoachPreferences)
        }

        if guidance == CaptureCoachingEngine.lowLightInstruction {
            currentFrameCoachInstruction = guidance
            speechCuePlayer.speakIfNeeded(guidance.sentenceCased, isEnabled: true, settings: frameCoachPreferences)
            return
        }

        let isGood = guidance == "kadraj uygun" || guidance == "kadraj dengeli"
        if isGood {
            lastGoodFrameAt = Date()
            lastGoodInstruction = guidance
        }

        // "İyi duruma kilitle": son 10 saniyede kadraj iyiydi ve şu anki şikayet hafifse — sessiz kal.
        let isLockedGood: Bool
        if let lastGood = lastGoodFrameAt, !isGood, Date().timeIntervalSince(lastGood) < 10 {
            isLockedGood = !isHardFrameCoachInstruction(guidance)
        } else {
            isLockedGood = false
        }

        currentFrameCoachInstruction = isLockedGood ? (lastGoodInstruction ?? guidance) : guidance

        guard !isLockedGood else { return }

        if lastAnnouncedSubjectCount != analysis.subjectCount {
            let countAnnouncement = frameCoachingEngine.subjectCountAnnouncement(for: analysis.subjectCount)
            let composite = "\(countAnnouncement). \(guidance.sentenceCased)"
            lastAnnouncedSubjectCount = analysis.subjectCount
            speechCuePlayer.speakIfNeeded(composite, isEnabled: true, key: guidance.sentenceCased, settings: frameCoachPreferences)
            return
        }

        speechCuePlayer.speakIfNeeded(guidance.sentenceCased, isEnabled: true, key: guidance.sentenceCased, settings: frameCoachPreferences)
    }

    /// Matches against Turkish coaching phrases produced by the frame coach engine.
    /// These are pattern strings used for internal matching — intentionally not localized.
    private func isHardFrameCoachInstruction(_ instruction: String) -> Bool {
        let hardKeywords = ["algılanam", "tam girmiyor", "arkada kalmış", "daha yakın", "Çok yakınsın", "Çok uzaktasın", "Çok uzaktasınız"]
        return hardKeywords.contains { instruction.contains($0) }
    }

    func startRecording() {
        Task {
            await startRecordingAsync()
        }
    }

    func selectPreset(_ preset: RecordingPreset) {
        guard canChangeRecordingSettings else { return }
        selectedPreset = preset
        applyPresetSelection(refresh: hasSetUp)
    }

    func toggleAudioRecording() {
        if isRecording || isCountingDown {
            guard selectedRecordingSource == .audio else { return }
            if isCountingDown {
                cancelCountdown()
            } else {
                stopRecording()
            }
            return
        }

        guard !isPreparingRecording else { return }
        selectPreset(.audioOnly)
        guard ensureRecordingAccess() else { return }
        guard ensureSelectedRecordingCanStart() else { return }

        if recordingCountdown == .none {
            startRecording()
        } else {
            beginCountdown()
        }
    }

    func selectScreenCaptureSource(_ source: ScreenCaptureSource) {
        guard canChangeRecordingSettings else { return }
        selectedScreenCaptureSource = source
        if selectedPreset.isScreenPreset {
            selectedRecordingSource = source.recordingSource
        }

        guard hasSetUp else { return }
        refreshDeviceState()
    }

    func toggleScreenCameraOverlay() {
        guard canChangeRecordingSettings else { return }
        isScreenCameraOverlayEnabled.toggle()
        refreshDeviceState()
    }

    private var canChangeRecordingSettings: Bool {
        !isRecording && !isPreparingRecording && !isCountingDown
    }

    private func startRecordingAsync() async {
        guard ensureRecordingAccess() else { return }
        guard ensureSelectedRecordingCanStart() else { return }

        do {
            let fileNamer = try resolvedActiveFileNamer()
            isPreparingRecording = true
            statusText = String(localized: "Kayıt hazırlanıyor")
            errorText = nil

            if selectedRecordingSource == .audio {
                try await startAudioRecording()
                return
            }

            guard selectedRecordingSource == .camera else {
                try await startScreenRecording()
                return
            }

            try await configureRecorder()
            autoReframeTimeline.reset()
            autoReframeSmoother.reset()
            currentAutoReframeCrop = .fullFrame
            resetAutoReframeDebugState()

            let captureURL = fileNamer.temporaryMovieURL()
            let finalURL = fileNamer.recordingURL(source: .camera)
            let systemAudioURL = fileNamer.temporaryAudioURL(stem: "system-audio")
            try removeExistingFileIfNeeded(at: captureURL)
            try removeExistingFileIfNeeded(at: finalURL)
            try removeExistingFileIfNeeded(at: systemAudioURL)

            pendingCameraRecordingFinalURL = finalURL
            pendingCameraCaptureResult = nil
            pendingCameraSystemAudioCaptureURL = nil
            pendingCameraSystemAudioWarning = nil
            pendingCameraSystemAudioCaptureResult = isSystemAudioEnabled ? nil : .success(nil)

            await playStartSoundBeforeCapture()

            if isSystemAudioEnabled {
                try await systemAudioRecorder.startRecording(to: systemAudioURL) { [weak self] result in
                    Task { @MainActor in
                        self?.handleCameraSystemAudioRecordingCompletion(result)
                    }
                }
                pendingCameraSystemAudioCaptureURL = systemAudioURL
            }

            do {
                try await recorder.startRecording(to: captureURL) { [weak self] result in
                    Task { @MainActor in
                        self?.handleCameraRecordingCompletion(result, finalURL: finalURL)
                    }
                }
            } catch {
                if isSystemAudioEnabled {
                    systemAudioRecorder.stopRecording()
                }
                resetPendingCameraRecordingState()
                throw error
            }

            isRecording = true
            beginPauseTracking()
            isPreparingRecording = false
            lastSavedURL = nil
            completedRecording = nil
            errorText = nil
            statusText = String(localized: "Kayıt yapılıyor")
            sleepPreventer.prevent(reason: "Video kaydı devam ediyor")
            startMaxDurationTimer()
        } catch {
            report(error)
        }
    }

    func stopRecording() {
        finishCurrentPauseRange()
        if selectedRecordingSource == .audio {
            if pendingAudioMicrophoneCaptureResult == nil {
                microphoneAudioRecorder.stopRecording()
            }
            if pendingAudioSystemAudioCaptureResult == nil {
                systemAudioRecorder.stopRecording()
            }
        } else if selectedRecordingSource == .camera {
            recorder.stopRecording()
            if isSystemAudioEnabled {
                systemAudioRecorder.stopRecording()
            }
        } else {
            if isScreenCameraOverlayEnabled {
                cameraOverlayRecorder.stopRecording()
            }
            if pendingScreenMicrophoneCaptureResult == nil {
                microphoneAudioRecorder.stopRecording()
            }
            if pendingScreenSystemAudioCaptureResult == nil {
                systemAudioRecorder.stopRecording()
            }
            pendingScreenCursorTimeline = cursorHighlightRecorder.stopTracking()
            pendingScreenKeyboardShortcutTimeline = keyboardShortcutRecorder.stopTracking()
            screenRecordingProvider.stopRecording()
        }
        isRecording = false
        isPaused = false
        pauseResumeTask?.cancel()
        pauseResumeTask = nil
        statusText = String(localized: "Kayıt durduruluyor")
        soundEffectPlayer.playStop()
        sleepPreventer.allow()
        recordingDurationTask?.cancel()
        recordingDurationTask = nil
    }

    private func startMaxDurationTimer() {
        guard let limit = maxRecordingDuration.seconds else { return }
        recordingDurationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(limit))
                await MainActor.run { [weak self] in
                    guard let self, self.isRecording else { return }
                    self.speechCuePlayer.speakIfNeeded(
                        String(localized: "Maksimum kayıt süresine ulaşıldı, kayıt durduruluyor"),
                        isEnabled: true,
                        key: "max-duration-stop"
                    )
                    self.stopRecording()
                }
            } catch {
                // Cancelled when stopRecording() is called manually — normal
            }
        }
    }

    private func playStartSoundBeforeCapture() async {
        let duration = soundEffectPlayer.playStart()
        guard duration > 0 else { return }

        do {
            try await Task.sleep(nanoseconds: UInt64(min(duration, 1.5) * 1_000_000_000))
        } catch {
            // If start is cancelled while the cue is playing, continue cleanup through the caller.
        }
    }

    private func startAudioRecording() async throws {
        let fileNamer = try resolvedActiveFileNamer()

        let finalURL = fileNamer.audioRecordingURL()
        let microphoneCaptureURL = fileNamer.temporaryAudioURL(stem: "audio-microphone")
        let systemAudioCaptureURL = fileNamer.temporaryAudioURL(stem: "audio-system")
        try removeExistingFileIfNeeded(at: finalURL)
        try removeExistingFileIfNeeded(at: microphoneCaptureURL)
        try removeExistingFileIfNeeded(at: systemAudioCaptureURL)

        pendingAudioRecordingFinalURL = finalURL
        pendingAudioMicrophoneCaptureResult = selectedMicrophoneID.isEmpty ? .success(nil) : nil
        pendingAudioMicrophoneCaptureURL = nil
        pendingAudioMicrophoneWarning = nil
        pendingAudioSystemAudioCaptureResult = isSystemAudioEnabled ? nil : .success(nil)
        pendingAudioSystemAudioCaptureURL = nil
        pendingAudioSystemAudioWarning = nil

        await playStartSoundBeforeCapture()

        do {
            if !selectedMicrophoneID.isEmpty {
                try await microphoneAudioRecorder.startRecording(deviceID: selectedMicrophoneID, to: microphoneCaptureURL) { [weak self] result in
                    Task { @MainActor in
                        self?.handleAudioMicrophoneCaptureCompletion(result)
                    }
                }
                pendingAudioMicrophoneCaptureURL = microphoneCaptureURL
            }

            if isSystemAudioEnabled {
                try await systemAudioRecorder.startRecording(to: systemAudioCaptureURL) { [weak self] result in
                    Task { @MainActor in
                        self?.handleAudioSystemAudioCaptureCompletion(result)
                    }
                }
                pendingAudioSystemAudioCaptureURL = systemAudioCaptureURL
            }
        } catch {
            if pendingAudioMicrophoneCaptureURL != nil {
                microphoneAudioRecorder.stopRecording()
            }
            if pendingAudioSystemAudioCaptureURL != nil {
                systemAudioRecorder.stopRecording()
            }
            resetPendingAudioRecordingState()
            throw error
        }

        isRecording = true
        beginPauseTracking()
        isPreparingRecording = false
        lastSavedURL = nil
        completedRecording = nil
        errorText = nil
        statusText = String(localized: "Ses kaydı yapılıyor")
        sleepPreventer.prevent(reason: "Ses kaydı devam ediyor")
        startMaxDurationTimer()
    }

    private func startScreenRecording() async throws {
        let fileNamer = try resolvedActiveFileNamer()

        let captureURL = fileNamer.temporaryMovieURL()
        let finalURL = fileNamer.recordingURL(source: selectedRecordingSource)
        let overlayCaptureURL = fileNamer.temporaryMovieURL(stem: "camera-overlay")
        let microphoneCaptureURL = fileNamer.temporaryAudioURL(stem: "screen-microphone")
        let systemAudioCaptureURL = fileNamer.temporaryAudioURL(stem: "screen-system-audio")
        try removeExistingFileIfNeeded(at: captureURL)
        try removeExistingFileIfNeeded(at: finalURL)
        try removeExistingFileIfNeeded(at: overlayCaptureURL)
        try removeExistingFileIfNeeded(at: microphoneCaptureURL)
        try removeExistingFileIfNeeded(at: systemAudioCaptureURL)

        let target: ScreenRecordingTarget
        switch selectedRecordingSource {
        case .screen:
            target = .display(id: selectedDisplayID)
        case .window:
            target = .window(id: selectedWindowID)
        case .camera, .audio:
            target = .display(id: "")
        }

        pendingScreenRecordingFinalURL = finalURL
        pendingScreenCaptureResult = nil
        pendingScreenOverlayPosition = selectedScreenCameraOverlayPosition
        pendingScreenOverlaySize = selectedScreenCameraOverlaySize
        pendingScreenOverlayCaptureURL = nil
        pendingScreenRecordingMode = selectedMode
        pendingScreenMicrophoneCaptureResult = selectedMicrophoneID.isEmpty ? .success(nil) : nil
        pendingScreenMicrophoneCaptureURL = nil
        pendingScreenMicrophoneWarning = nil
        pendingScreenSystemAudioCaptureResult = isSystemAudioEnabled ? nil : .success(nil)
        pendingScreenSystemAudioCaptureURL = nil
        pendingScreenSystemAudioWarning = nil
        pendingScreenCursorTimeline = .empty
        pendingScreenKeyboardShortcutTimeline = .empty
        pendingOverlayCaptureResult = isScreenCameraOverlayEnabled ? nil : .success(nil)

        await playStartSoundBeforeCapture()

        if isCursorHighlightEnabled, let targetFrame = currentScreenCaptureTargetFrame() {
            cursorHighlightRecorder.startTracking(targetFrame: targetFrame)
        }
        if isKeyboardShortcutOverlayEnabled {
            keyboardShortcutRecorder.startTracking()
        }

        if isScreenCameraOverlayEnabled {
            try await cameraOverlayRecorder.configure(cameraDeviceID: selectedCameraID, mode: selectedMode)
            try await cameraOverlayRecorder.startRecording(to: overlayCaptureURL) { [weak self] result in
                Task { @MainActor in
                    self?.handleScreenOverlayCaptureCompletion(result)
                }
            }
            pendingScreenOverlayCaptureURL = overlayCaptureURL
        }

        if !selectedMicrophoneID.isEmpty {
            try await microphoneAudioRecorder.startRecording(deviceID: selectedMicrophoneID, to: microphoneCaptureURL) { [weak self] result in
                Task { @MainActor in
                    self?.handleScreenMicrophoneCaptureCompletion(result)
                }
            }
            pendingScreenMicrophoneCaptureURL = microphoneCaptureURL
        }

        if isSystemAudioEnabled {
            try await systemAudioRecorder.startRecording(to: systemAudioCaptureURL) { [weak self] result in
                Task { @MainActor in
                    self?.handleScreenSystemAudioCaptureCompletion(result)
                }
            }
            pendingScreenSystemAudioCaptureURL = systemAudioCaptureURL
        }

        do {
            try await screenRecordingProvider.startRecording(
                target: target,
                microphoneDeviceID: "",
                includeSystemAudio: false,
                to: captureURL
            ) { [weak self] result in
                Task { @MainActor in
                    self?.handleScreenRecordingCompletion(result, finalURL: finalURL)
                }
            }
        } catch {
            if isScreenCameraOverlayEnabled {
                cameraOverlayRecorder.stopRecording()
                cameraOverlayRecorder.stopSession()
            }
            if pendingScreenMicrophoneCaptureURL != nil {
                microphoneAudioRecorder.stopRecording()
            }
            if pendingScreenSystemAudioCaptureURL != nil {
                systemAudioRecorder.stopRecording()
            }
            _ = cursorHighlightRecorder.stopTracking()
            _ = keyboardShortcutRecorder.stopTracking()
            resetPendingScreenRecordingState()
            throw error
        }

        isRecording = true
        beginPauseTracking()
        isPreparingRecording = false
        lastSavedURL = nil
        completedRecording = nil
        errorText = nil
        statusText = String(localized: "Kayıt yapılıyor")
            sleepPreventer.prevent(reason: "Ekran kaydı devam ediyor")
            startMaxDurationTimer()
    }

    private func handleCameraRecordingCompletion(_ result: Result<URL, Error>, finalURL: URL) {
        pendingCameraRecordingFinalURL = finalURL
        pendingCameraCaptureResult = result
        completeCameraRecordingIfReady()
    }

    private func handleCameraSystemAudioRecordingCompletion(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            pendingCameraSystemAudioCaptureResult = .success(url)
        case .failure(let error):
            if let screenError = error as? ScreenRecordingError, screenError == .emptyRecording {
                pendingCameraSystemAudioCaptureResult = .success(nil)
            } else {
                pendingCameraSystemAudioWarning = String(localized: "sistem sesi eklenemedi")
                pendingCameraSystemAudioCaptureResult = .success(nil)
            }
        }
        completeCameraRecordingIfReady()
    }

    private func completeCameraRecordingIfReady() {
        guard let finalURL = pendingCameraRecordingFinalURL,
              let captureResult = pendingCameraCaptureResult,
              let systemAudioResult = pendingCameraSystemAudioCaptureResult else {
            return
        }

        let systemAudioURL: URL?
        switch systemAudioResult {
        case .success(let url):
            systemAudioURL = url
        case .failure:
            systemAudioURL = nil
        }

        let warning = pendingCameraSystemAudioWarning
        resetPendingCameraRecordingState()
        handleRecordingCompletion(
            captureResult,
            finalURL: finalURL,
            systemAudioURL: systemAudioURL,
            warningText: warning
        )
    }

    private func handleRecordingCompletion(
        _ result: Result<URL, Error>,
        finalURL: URL,
        systemAudioURL: URL? = nil,
        warningText: String? = nil
    ) {
        let pauseTimeline = recordingPauseTimeline
        isRecording = false
        isPaused = false

        switch result {
        case .success(let captureURL):
            statusText = String(localized: "MP4 hazırlanıyor")
            Task {
                do {
                    let exportResult = try await exportMP4(
                        from: captureURL,
                        to: finalURL,
                        timeline: isAutoReframeEnabled ? autoReframeTimeline.shifted(by: pauseTimeline) : AutoReframeTimeline(),
                        cameraMode: selectedMode,
                        systemAudioURL: systemAudioURL,
                        pauseTimeline: pauseTimeline
                    )
                    try? FileManager.default.removeItem(at: captureURL)
                    if let systemAudioURL {
                        try? FileManager.default.removeItem(at: systemAudioURL)
                    }
                    await MainActor.run {
                        lastSavedURL = exportResult.url
                        completedRecording = makeCompletedRecordingSummary(for: exportResult.url, warnings: warningText.map { [$0] } ?? [])
                        lastAutoReframeKeyframeCount = exportResult.keyframeCount
                        lastAutoReframeUsedVideoComposition = exportResult.usedVideoComposition
                        lastAutoReframeUsedFallbackExport = exportResult.usedFallbackExport
                        lastAutoReframeStrategy = exportResult.strategy
                        let summary = autoReframeExportSummary(
                            keyframeCount: exportResult.keyframeCount,
                            usedVideoComposition: exportResult.usedVideoComposition
                        )
                        if let warningText {
                            statusText = String(localized: "Kaydedildi: \(exportResult.url.path) (\(summary), \(warningText))")
                        } else {
                            statusText = String(localized: "Kaydedildi: \(exportResult.url.path) (\(summary))")
                        }
                        speechCuePlayer.reset()
                        speechCuePlayer.speakIfNeeded(
                            summary.sentenceCased,
                            isEnabled: true,
                            key: "export-\(exportResult.usedVideoComposition)-\(exportResult.keyframeCount)-\(exportResult.strategy)",
                            settings: frameCoachPreferences
                        )
                    }
                } catch {
                    await MainActor.run {
                        report(error)
                    }
                }
            }
        case .failure(let error):
            report(error)
        }
    }

    private func handleScreenRecordingCompletion(_ result: Result<URL, Error>, finalURL: URL) {
        pendingScreenCaptureResult = result
        pendingScreenRecordingFinalURL = finalURL
        maybeFinalizeScreenRecordingExport()
    }

    private func handleScreenOverlayCaptureCompletion(_ result: Result<URL, Error>) {
        pendingOverlayCaptureResult = result.map(Optional.some)
        maybeFinalizeScreenRecordingExport()
    }

    private func handleScreenMicrophoneCaptureCompletion(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            pendingScreenMicrophoneCaptureResult = .success(url)
        case .failure(let error):
            if let microphoneError = error as? MicrophoneAudioRecorderError, microphoneError == .emptyRecording {
                pendingScreenMicrophoneCaptureResult = .success(nil)
            } else {
                pendingScreenMicrophoneWarning = String(localized: "mikrofon sesi eklenemedi")
                pendingScreenMicrophoneCaptureResult = .success(nil)
            }
        }
        maybeFinalizeScreenRecordingExport()
    }

    private func handleScreenSystemAudioCaptureCompletion(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            pendingScreenSystemAudioCaptureResult = .success(url)
        case .failure(let error):
            if let screenError = error as? ScreenRecordingError, screenError == .emptyRecording {
                pendingScreenSystemAudioCaptureResult = .success(nil)
            } else {
                pendingScreenSystemAudioWarning = String(localized: "sistem sesi eklenemedi")
                pendingScreenSystemAudioCaptureResult = .success(nil)
            }
        }
        maybeFinalizeScreenRecordingExport()
    }

    private func handleAudioMicrophoneCaptureCompletion(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            pendingAudioMicrophoneCaptureResult = .success(url)
        case .failure(let error):
            if let microphoneError = error as? MicrophoneAudioRecorderError, microphoneError == .emptyRecording {
                pendingAudioMicrophoneCaptureResult = .success(nil)
            } else {
                pendingAudioMicrophoneWarning = String(localized: "mikrofon sesi eklenemedi")
                pendingAudioMicrophoneCaptureResult = .success(nil)
            }
        }
        maybeFinalizeAudioRecordingExport()
    }

    private func handleAudioSystemAudioCaptureCompletion(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            pendingAudioSystemAudioCaptureResult = .success(url)
        case .failure(let error):
            if let screenError = error as? ScreenRecordingError, screenError == .emptyRecording {
                pendingAudioSystemAudioCaptureResult = .success(nil)
            } else {
                pendingAudioSystemAudioWarning = String(localized: "sistem sesi eklenemedi")
                pendingAudioSystemAudioCaptureResult = .success(nil)
            }
        }
        maybeFinalizeAudioRecordingExport()
    }

    private func maybeFinalizeAudioRecordingExport() {
        guard let finalURL = pendingAudioRecordingFinalURL,
              let microphoneResult = pendingAudioMicrophoneCaptureResult,
              let systemAudioResult = pendingAudioSystemAudioCaptureResult else {
            return
        }

        let microphoneWarning = pendingAudioMicrophoneWarning
        let systemAudioWarning = pendingAudioSystemAudioWarning
        let pauseTimeline = recordingPauseTimeline
        resetPendingAudioRecordingState()
        isRecording = false
        isPaused = false

        switch (microphoneResult, systemAudioResult) {
        case (.failure(let error), _), (_, .failure(let error)):
            report(error)
        case (.success(let microphoneURL), .success(let systemAudioURL)):
            statusText = String(localized: "M4A hazırlanıyor")
            Task {
                do {
                    let exportURL = try await audioRecordingExporter.export(
                        microphoneURL: microphoneURL,
                        systemAudioURL: systemAudioURL,
                        to: finalURL,
                        microphoneVolume: microphoneVolume,
                        systemAudioVolume: systemAudioVolume,
                        pauseTimeline: pauseTimeline
                    )
                    if let microphoneURL {
                        try? FileManager.default.removeItem(at: microphoneURL)
                    }
                    if let systemAudioURL {
                        try? FileManager.default.removeItem(at: systemAudioURL)
                    }
                    await MainActor.run {
                        let warnings = [microphoneWarning, systemAudioWarning].compactMap { $0 }
                        lastSavedURL = exportURL
                        completedRecording = makeCompletedRecordingSummary(for: exportURL, warnings: warnings)
                        if warnings.isEmpty {
                            statusText = String(localized: "Kaydedildi: \(exportURL.path)")
                        } else {
                            statusText = String(localized: "Kaydedildi: \(exportURL.path) (\(warnings.joined(separator: ", ")))")
                        }
                    }
                } catch {
                    await MainActor.run {
                        report(error)
                    }
                }
            }
        }
    }

    private func maybeFinalizeScreenRecordingExport() {
        guard let screenResult = pendingScreenCaptureResult,
              let finalURL = pendingScreenRecordingFinalURL else {
            return
        }

        guard let overlayResult = pendingOverlayCaptureResult else {
            return
        }

        guard let microphoneResult = pendingScreenMicrophoneCaptureResult else {
            return
        }

        guard let systemAudioResult = pendingScreenSystemAudioCaptureResult else {
            return
        }

        let overlayPosition = pendingScreenOverlayPosition
        let overlaySize = pendingScreenOverlaySize
        let recordingMode = pendingScreenRecordingMode
        let microphoneWarning = pendingScreenMicrophoneWarning
        let systemAudioWarning = pendingScreenSystemAudioWarning
        let pauseTimeline = recordingPauseTimeline
        let cursorTimeline = pendingScreenCursorTimeline.shifted(by: pauseTimeline)
        let keyboardShortcutTimeline = pendingScreenKeyboardShortcutTimeline.shifted(by: pauseTimeline)
        resetPendingScreenRecordingState()
        cameraOverlayRecorder.stopSession()
        isRecording = false
        isPaused = false

        switch (screenResult, overlayResult, microphoneResult, systemAudioResult) {
        case (.failure(let error), _, _, _):
            report(error)
        case (_, .failure(let error), _, _):
            report(error)
        case (_, _, .failure(let error), _):
            report(error)
        case (_, _, _, .failure(let error)):
            report(error)
        case (.success(let captureURL), .success(let overlayURL), .success(let microphoneURL), .success(let systemAudioURL)):
            statusText = String(localized: "MP4 hazırlanıyor")
            Task {
                do {
                    let exportResult = try await exportMP4(
                        from: captureURL,
                        to: finalURL,
                        timeline: AutoReframeTimeline(),
                        screenExportMode: recordingMode,
                        screenMicrophoneURL: microphoneURL,
                        screenSystemAudioURL: systemAudioURL,
                        overlayURL: overlayURL,
                        overlayPosition: overlayPosition,
                        overlaySize: overlaySize,
                        cursorTimeline: cursorTimeline,
                        keyboardShortcutTimeline: keyboardShortcutTimeline,
                        pauseTimeline: pauseTimeline
                    )
                    try? FileManager.default.removeItem(at: captureURL)
                    if let overlayURL {
                        try? FileManager.default.removeItem(at: overlayURL)
                    }
                    if let microphoneURL {
                        try? FileManager.default.removeItem(at: microphoneURL)
                    }
                    if let systemAudioURL {
                        try? FileManager.default.removeItem(at: systemAudioURL)
                    }
                    await MainActor.run {
                        let warnings = [microphoneWarning, systemAudioWarning].compactMap { $0 }
                        lastSavedURL = exportResult.url
                        completedRecording = makeCompletedRecordingSummary(for: exportResult.url, warnings: warnings)
                        lastAutoReframeKeyframeCount = exportResult.keyframeCount
                        lastAutoReframeUsedVideoComposition = exportResult.usedVideoComposition
                        lastAutoReframeUsedFallbackExport = exportResult.usedFallbackExport
                        lastAutoReframeStrategy = exportResult.strategy
                        if warnings.isEmpty {
                            statusText = String(localized: "Kaydedildi: \(exportResult.url.path)")
                        } else {
                            statusText = String(localized: "Kaydedildi: \(exportResult.url.path) (\(warnings.joined(separator: ", ")))")
                        }
                    }
                } catch {
                    await MainActor.run {
                        report(error)
                    }
                }
            }
        }
    }

    private func exportMP4(
        from sourceURL: URL,
        to destinationURL: URL,
        timeline: AutoReframeTimeline,
        cameraMode: RecordingMode = .horizontal1080p,
        systemAudioURL: URL? = nil,
        screenExportMode: RecordingMode? = nil,
        screenMicrophoneURL: URL? = nil,
        screenSystemAudioURL: URL? = nil,
        overlayURL: URL? = nil,
        overlayPosition: ScreenCameraOverlayPosition = .bottomRight,
        overlaySize: ScreenCameraOverlaySize = .medium,
        cursorTimeline: CursorHighlightTimeline = .empty,
        keyboardShortcutTimeline: KeyboardShortcutTimeline = .empty,
        pauseTimeline: RecordingPauseTimeline = .empty
    ) async throws -> (url: URL, keyframeCount: Int, usedVideoComposition: Bool, usedFallbackExport: Bool, strategy: String) {
        let sourceAsset = AVURLAsset(url: sourceURL)

        if let screenExportMode {
            let overlayAsset = overlayURL.map { AVURLAsset(url: $0) }
            let microphoneAsset = screenMicrophoneURL.map { AVURLAsset(url: $0) }
            let systemAudioAsset = screenSystemAudioURL.map { AVURLAsset(url: $0) }
            let overlayComposition = try await screenCameraOverlayCompositionBuilder.makeComposition(
                screenAsset: sourceAsset,
                mode: screenExportMode,
                overlayAsset: overlayAsset,
                position: overlayPosition,
                overlaySize: overlaySize,
                cursorTimeline: cursorTimeline,
                keyboardShortcutTimeline: keyboardShortcutTimeline,
                microphoneAsset: microphoneAsset,
                systemAudioAsset: systemAudioAsset,
                microphoneVolume: microphoneVolume,
                systemAudioVolume: systemAudioVolume,
                pauseTimeline: pauseTimeline
            )

            guard let exportSession = AVAssetExportSession(asset: overlayComposition.composition, presetName: AVAssetExportPresetHighestQuality) else {
                throw CaptureRecorderError.cannotExportMP4
            }

            exportSession.outputURL = destinationURL
            exportSession.outputFileType = .mp4
            exportSession.shouldOptimizeForNetworkUse = true
            exportSession.videoComposition = overlayComposition.videoComposition
            exportSession.audioMix = overlayComposition.audioMix

            await exportSession.export()

            if let error = exportSession.error {
                runtimeDebugLog("Screen export failed with error: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: destinationURL)
                throw error
            }

            guard exportSession.status == .completed else {
                runtimeDebugLog("Screen export ended with status \(exportSession.status.rawValue)")
                try? FileManager.default.removeItem(at: destinationURL)
                throw CaptureRecorderError.cannotExportMP4
            }

            return (
                destinationURL,
                timeline.keyframes.count,
                true,
                false,
                overlayURL == nil ? "ekran-1080p" : "ekran-kamera-overlay"
            )
        }

        let exportPackage = try await makeCameraExportAsset(
            sourceAsset: sourceAsset,
            systemAudioURL: systemAudioURL,
            pauseTimeline: pauseTimeline
        )

        guard let exportSession = AVAssetExportSession(asset: exportPackage.asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw CaptureRecorderError.cannotExportMP4
        }

        let composition = await autoReframeCompositionBuilder.makeVideoComposition(
            for: exportPackage.asset,
            timeline: timeline,
            mode: cameraMode
        )

        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = composition
        exportSession.audioMix = exportPackage.audioMix

        await exportSession.export()

        if let error = exportSession.error {
            runtimeDebugLog("Camera export failed with error: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }

        guard exportSession.status == .completed else {
            runtimeDebugLog("Camera export ended with status \(exportSession.status.rawValue)")
            try? FileManager.default.removeItem(at: destinationURL)
            throw CaptureRecorderError.cannotExportMP4
        }

        return (
            destinationURL,
            timeline.keyframes.count,
            composition != nil,
            composition == nil,
            timeline.keyframes.isEmpty ? "full-frame" : "zaman-cizelgesi"
        )
    }

    private func makeCameraExportAsset(
        sourceAsset: AVAsset,
        systemAudioURL: URL?,
        pauseTimeline: RecordingPauseTimeline
    ) async throws -> (asset: AVAsset, audioMix: AVAudioMix?) {
        let composition = AVMutableComposition()
        let duration = try await sourceAsset.load(.duration)
        let sourceSegments = pauseTimeline.segments(for: duration)
        guard !sourceSegments.isEmpty else {
            throw CaptureRecorderError.cannotExportMP4
        }

        guard let sourceVideoTrack = try await sourceAsset.loadTracks(withMediaType: .video).first,
              let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CaptureRecorderError.cannotExportMP4
        }

        try insertSegments(sourceSegments, of: sourceVideoTrack, into: compositionVideoTrack)
        compositionVideoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        let sourceAudioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
        var microphoneTrackIDs: [CMPersistentTrackID] = []
        for sourceAudioTrack in sourceAudioTracks {
            guard let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                continue
            }
            try insertSegments(sourceSegments, of: sourceAudioTrack, into: compositionAudioTrack)
            microphoneTrackIDs.append(compositionAudioTrack.trackID)
        }

        var systemTrackIDs: [CMPersistentTrackID] = []
        if let systemAudioURL {
            let systemAudioAsset = AVURLAsset(url: systemAudioURL)
            let systemAudioDuration = try await systemAudioAsset.load(.duration)
            let insertDuration = min(duration, systemAudioDuration)
            let systemSegments = pauseTimeline.segments(for: insertDuration)
            let systemAudioTracks = try await systemAudioAsset.loadTracks(withMediaType: .audio)

            for systemAudioTrack in systemAudioTracks {
                guard insertDuration > .zero,
                      !systemSegments.isEmpty,
                      let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    continue
                }
                try insertSegments(systemSegments, of: systemAudioTrack, into: compositionAudioTrack)
                systemTrackIDs.append(compositionAudioTrack.trackID)
            }
        }

        let audioMix = recordingAudioMixBuilder.makeAudioMix(
            composition: composition,
            microphoneTrackIDs: microphoneTrackIDs,
            systemAudioTrackIDs: systemTrackIDs,
            microphoneVolume: microphoneVolume,
            systemAudioVolume: systemAudioVolume
        )

        return (composition, audioMix)
    }

    private func insertSegments(
        _ segments: [RecordingSegment],
        of sourceTrack: AVAssetTrack,
        into compositionTrack: AVMutableCompositionTrack
    ) throws {
        for segment in segments {
            try compositionTrack.insertTimeRange(segment.sourceRange, of: sourceTrack, at: segment.destinationStart)
        }
    }

    private func makeCompletedRecordingSummary(for url: URL, warnings: [String]) -> CompletedRecordingSummary {
        CompletedRecordingSummary(
            url: url,
            warnings: warnings,
            editableName: url.deletingPathExtension().lastPathComponent,
            fileExtension: url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        )
    }

    func updateCompletedRecordingName(_ name: String) {
        guard var completedRecording else { return }
        completedRecording.editableName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.completedRecording = completedRecording
    }

    func dismissCompletedRecordingSummary() {
        completedRecording = nil
    }

    func dismissPaywall() {
        isPaywallPresented = false
        paywallMessageText = nil
    }

    func presentPaywall() {
        isPaywallPresented = true
        paywallMessageText = nil
    }

    func purchaseAccess(plan: AppAccessPlan) async {
        purchasingPlan = plan
        paywallMessageText = nil
        let result = await appAccessManager.purchase(plan: plan)
        purchasingPlan = nil
        syncAppAccessState()

        switch result {
        case .success:
            if appAccessState.canStartRecording {
                isPaywallPresented = false
                statusText = String(localized: "Pro erişim açıldı")
            }
        case .pending:
            paywallMessageText = String(localized: "Satın alma onayı bekleniyor.")
        case .userCancelled:
            paywallMessageText = String(localized: "Satın alma iptal edildi.")
        }
    }

    func restorePurchases() async {
        isRestoringPurchases = true
        paywallMessageText = nil
        await appAccessManager.restorePurchases()
        isRestoringPurchases = false
        syncAppAccessState()

        if appAccessState.canStartRecording {
            isPaywallPresented = false
            statusText = String(localized: "Satın alımlar geri yüklendi")
        } else {
            paywallMessageText = String(localized: "Etkin bir satın alma bulunamadı.")
        }
    }

    func offer(for plan: AppAccessPlan) -> AppAccessOffer? {
        appAccessState.offers.first(where: { $0.plan == plan })
    }

    var accessStatusTitle: String {
        switch appAccessState.accessKind {
        case .trial:
            if appAccessState.trialDaysRemaining == 1 {
                return String(localized: "Deneme: son 1 gün")
            }
            return String(localized: "Deneme: \(appAccessState.trialDaysRemaining) gün kaldı")
        case .yearly:
            return String(localized: "Pro: yıllık plan aktif")
        case .lifetime:
            return String(localized: "Pro: ömür boyu erişim aktif")
        case .expired:
            return String(localized: "Pro plan gerekli")
        }
    }

    var accessStatusDetail: String {
        switch appAccessState.accessKind {
        case .trial:
            return String(localized: "Şimdilik tüm kayıt özellikleri açık. Süre bitince plan seçebilirsin.")
        case .yearly:
            return String(localized: "Yıllık plan veya Apple deneme süresiyle tüm Pro kayıt özellikleri açık.")
        case .lifetime:
            return String(localized: "Tek seferlik satın alımla tüm Pro kayıt özellikleri açık.")
        case .expired:
            return String(localized: "14 günlük ücretsiz deneme için yıllık planı veya kalıcı erişim için ömür boyu planı seç.")
        }
    }

    func openLastSavedRecording() {
        guard let url = lastSavedURL else { return }
        openURL(url)
    }

    func openCompletedRecording() {
        guard let url = completedRecording?.url ?? lastSavedURL else { return }
        openURL(url)
    }

    func revealLastSavedRecording() {
        guard let url = lastSavedURL else { return }
        revealInFinder(url)
    }

    func revealCompletedRecording() {
        guard let url = completedRecording?.url ?? lastSavedURL else { return }
        revealInFinder(url)
    }

    func chooseRecordingOutputDirectory() {
        guard let selectedURL = chooseOutputDirectory(recordingOutputDirectoryURL) else { return }
        recordingOutputDirectoryURL = selectedURL
        statusText = String(localized: "Varsayılan kayıt klasörü: \(selectedURL.path)")
    }

    func renameCompletedRecording() {
        guard let completedRecording else { return }
        renameCompletedRecording(to: completedRecording.editableName)
    }

    func renameCompletedRecording(to editableName: String) {
        guard let completedRecording else { return }

        let sanitizedName = sanitizedFilenameStem(from: editableName)
        let renamedURL = completedRecording.url
            .deletingLastPathComponent()
            .appendingPathComponent(sanitizedName)
            .appendingPathExtension(completedRecording.fileExtension)

        do {
            try moveRecordingFile(from: completedRecording.url, to: renamedURL)
            lastSavedURL = renamedURL
            self.completedRecording = makeCompletedRecordingSummary(for: renamedURL, warnings: completedRecording.warnings)
            statusText = String(localized: "Yeniden adlandırıldı: \(renamedURL.lastPathComponent)")
        } catch {
            report(error)
            self.completedRecording = completedRecording
        }
    }

    func saveCompletedRecordingAs() {
        guard let completedRecording else { return }
        saveCompletedRecordingAs(to: completedRecording.editableName)
    }

    func saveCompletedRecordingAs(to editableName: String) {
        guard let completedRecording else { return }

        let suggestedURL = completedRecording.url
            .deletingLastPathComponent()
            .appendingPathComponent(sanitizedFilenameStem(from: editableName))
            .appendingPathExtension(completedRecording.fileExtension)

        guard let selectedURL = chooseSaveDestination(suggestedURL) else { return }
        let destinationURL = normalizedMovieURL(from: selectedURL, fileExtension: completedRecording.fileExtension)

        do {
            try moveRecordingFile(from: completedRecording.url, to: destinationURL)
            lastSavedURL = destinationURL
            self.completedRecording = makeCompletedRecordingSummary(for: destinationURL, warnings: completedRecording.warnings)
            statusText = String(localized: "Farklı kaydedildi: \(destinationURL.path)")
        } catch {
            report(error)
            self.completedRecording = completedRecording
        }
    }

    private func sanitizedFilenameStem(from rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "recording"
        }

        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let components = trimmed.components(separatedBy: invalidCharacters)
        let sanitized = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "recording" : sanitized
    }

    private func normalizedMovieURL(from url: URL, fileExtension: String) -> URL {
        if url.pathExtension.isEmpty {
            return url.appendingPathExtension(fileExtension)
        }
        return url
    }

    private func syncAppAccessState() {
        appAccessState = appAccessManager.state
        if appAccessState.canStartRecording {
            paywallMessageText = nil
        }
    }

    private func ensureRecordingAccess() -> Bool {
        guard appAccessState.canStartRecording else {
            isPaywallPresented = true
            paywallMessageText = nil
            errorText = nil
            statusText = String(localized: "Kayıt başlatmak için Pro plan seç")
            return false
        }

        return true
    }

    private func ensureSelectedRecordingCanStart() -> Bool {
        guard canStartRecording else {
            refreshDeviceState()
            errorText = nil
            statusText = makeStatusText()
            return false
        }

        return true
    }

    private func moveRecordingFile(from sourceURL: URL, to destinationURL: URL) throws {
        guard sourceURL != destinationURL else { return }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            throw NSError(
                domain: "VideoRecorderApp.RecordingFileMove",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Hedefte aynı isimde bir dosya zaten var.")]
            )
        }

        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    private func removeExistingFileIfNeeded(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func resetPendingCameraRecordingState() {
        pendingCameraRecordingFinalURL = nil
        pendingCameraCaptureResult = nil
        pendingCameraSystemAudioCaptureResult = nil
        pendingCameraSystemAudioCaptureURL = nil
        pendingCameraSystemAudioWarning = nil
    }

    private func resetPendingAudioRecordingState() {
        pendingAudioRecordingFinalURL = nil
        pendingAudioMicrophoneCaptureResult = nil
        pendingAudioMicrophoneCaptureURL = nil
        pendingAudioMicrophoneWarning = nil
        pendingAudioSystemAudioCaptureResult = nil
        pendingAudioSystemAudioCaptureURL = nil
        pendingAudioSystemAudioWarning = nil
    }

    private func preferredMicrophoneID() -> String {
        if let defaultMicrophoneID = AVCaptureDevice.default(for: .audio)?.uniqueID,
           microphones.contains(where: { $0.id == defaultMicrophoneID }) {
            return defaultMicrophoneID
        }

        let preferredIDs = [
            "BuiltInHeadphoneInputDevice",
            "BuiltInMicrophoneDevice"
        ]

        for id in preferredIDs {
            if microphones.contains(where: { $0.id == id }) {
                return id
            }
        }

        return microphones.first { device in
            !device.name.localizedCaseInsensitiveContains("zoom")
                && !device.name.localizedCaseInsensitiveContains("blackhole")
                && !device.name.localizedCaseInsensitiveContains("boom")
                && !device.name.localizedCaseInsensitiveContains("camo")
                && !device.name.localizedCaseInsensitiveContains("aggregate")
                && !device.name.localizedCaseInsensitiveContains("kümesi")
        }?.id ?? microphones.first?.id ?? ""
    }

    private func resolvedActiveFileNamer() throws -> RecordingFileNamer {
        let configuredFileNamer = activeFileNamer

        do {
            try configuredFileNamer.ensureOutputDirectoryExists()
            return configuredFileNamer
        } catch {
            let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            let fallbackDirectory = downloadsDirectory.appendingPathComponent("FrameMate", isDirectory: true)
            let fallbackFileNamer = RecordingFileNamer(outputDirectory: fallbackDirectory)
            try fallbackFileNamer.ensureOutputDirectoryExists()

            if recordingOutputDirectoryURL != fallbackDirectory {
                recordingOutputDirectoryURL = fallbackDirectory
                statusText = String(localized: "Kayıt klasörü otomatik olarak İndirilenler/FrameMate olarak güncellendi.")
            }

            return fallbackFileNamer
        }
    }

    private func report(_ error: Error) {
        refreshPermissionStatus()
        errorText = error.localizedDescription
        statusText = "Hata: \(error.localizedDescription)"
        isRecording = false
        isPaused = false
        isPreparingRecording = false
        completedRecording = nil
        if error is CaptureRecorderError {
            isRecorderConfigured = false
        }
    }

    func openPrivacySettings(for mediaType: AVMediaType) {
        let preferencePane: String
        switch mediaType {
        case .video:
            preferencePane = "Privacy_Camera"
        case .audio:
            preferencePane = "Privacy_Microphone"
        default:
            return
        }

        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(preferencePane)") else {
            return
        }
        openURL(url)
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        openURL(url)
    }

    func performPrimaryPermissionAction(for kind: PermissionKind) {
        switch kind {
        case .camera:
            switch makeCameraPermissionItem().primaryAction {
            case .request: requestCameraPermission()
            case .openSettings: openPrivacySettings(for: .video)
            case .restartApp: NSApp.terminate(nil)
            case .none: break
            }
        case .microphone:
            switch makeMicrophonePermissionItem().primaryAction {
            case .request: requestMicrophonePermission()
            case .openSettings: openPrivacySettings(for: .audio)
            case .restartApp: NSApp.terminate(nil)
            case .none: break
            }
        case .screenRecording:
            switch makeScreenRecordingPermissionItem().primaryAction {
            case .request: requestScreenRecordingPermission()
            case .openSettings: openScreenRecordingSettings()
            case .restartApp: NSApp.terminate(nil)
            case .none: break
            }
        }
    }

    func performSecondaryPermissionAction(for kind: PermissionKind) {
        let action: PermissionAction?
        switch kind {
        case .camera:
            action = makeCameraPermissionItem().secondaryAction
        case .microphone:
            action = makeMicrophonePermissionItem().secondaryAction
        case .screenRecording:
            action = makeScreenRecordingPermissionItem().secondaryAction
        }

        switch action {
        case .request: performPrimaryPermissionAction(for: kind)
        case .openSettings: kind == .screenRecording ? openScreenRecordingSettings() : openPrivacySettings(for: kind == .camera ? .video : .audio)
        case .restartApp: NSApp.terminate(nil)
        case .some(.none), nil: break
        }
    }

    private var hasRequiredPermissions: Bool {
        cameraPermissionStatus == .authorized && microphonePermissionStatus == .authorized
    }

    private func makeCameraPermissionItem() -> PermissionHubItem {
        let isRequired = selectedRecordingSource == .camera || showsScreenOverlayConfiguration
        let isAuthorized = cameraPermissionStatus == .authorized
        let isSatisfied = isAuthorized || !isRequired
        let detail = isRequired
            ? String(localized: "Kamera kaydı veya kamera kutusu için gerekli")
            : String(localized: "Yalnızca kamera içeren modlarda gerekli")
        let interactionState = permissionInteractionStates[.camera] ?? .idle

        switch (cameraPermissionStatus, interactionState) {
        case (_, .requesting):
            return PermissionHubItem(
                id: .camera,
                title: PermissionKind.camera.title,
                detail: detail,
                statusLabel: String(localized: "İzin penceresi açık olabilir"),
                helperText: String(localized: "macOS izin penceresini kontrol et. Kararını orada vereceksin."),
                isRequired: isRequired,
                isSatisfied: false,
                isRequestInFlight: true,
                primaryAction: .none,
                secondaryAction: nil
            )
        case (.authorized, _):
            return PermissionHubItem(
                id: .camera,
                title: PermissionKind.camera.title,
                detail: detail,
                statusLabel: String(localized: "Verildi"),
                helperText: interactionState == .granted ? String(localized: "Kamera izni verildi.") : nil,
                isRequired: isRequired,
                isSatisfied: isSatisfied,
                isRequestInFlight: false,
                primaryAction: .none,
                secondaryAction: nil
            )
        case (.denied, _), (.restricted, _):
            return PermissionHubItem(
                id: .camera,
                title: PermissionKind.camera.title,
                detail: detail,
                statusLabel: String(localized: "Reddedildi"),
                helperText: String(localized: "Kamera izni verilmedi. Sağdaki düğmeyle Sistem Ayarları'nı açabilirsin."),
                isRequired: isRequired,
                isSatisfied: isSatisfied,
                isRequestInFlight: false,
                primaryAction: .openSettings,
                secondaryAction: nil
            )
        case (.notDetermined, _):
            return PermissionHubItem(
                id: .camera,
                title: PermissionKind.camera.title,
                detail: detail,
                statusLabel: String(localized: "İzin bekleniyor"),
                helperText: String(localized: "Sağdaki düğme tıklanabilir. İzin penceresini açar."),
                isRequired: isRequired,
                isSatisfied: isSatisfied,
                isRequestInFlight: false,
                primaryAction: .request,
                secondaryAction: nil
            )
        @unknown default:
            return PermissionHubItem(
                id: .camera,
                title: PermissionKind.camera.title,
                detail: detail,
                statusLabel: String(localized: "Durum bilinmiyor"),
                helperText: nil,
                isRequired: isRequired,
                isSatisfied: isSatisfied,
                isRequestInFlight: false,
                primaryAction: .openSettings,
                secondaryAction: nil
            )
        }
    }

    private func makeMicrophonePermissionItem() -> PermissionHubItem {
        let isRequired = true
        let detail = String(localized: "Sesli kayıt akışları için gerekli")
        let interactionState = permissionInteractionStates[.microphone] ?? .idle

        switch (microphonePermissionStatus, interactionState) {
        case (_, .requesting):
            return PermissionHubItem(
                id: .microphone,
                title: PermissionKind.microphone.title,
                detail: detail,
                statusLabel: String(localized: "İzin penceresi açık olabilir"),
                helperText: String(localized: "macOS izin penceresini kontrol et. Kararını orada vereceksin."),
                isRequired: isRequired,
                isSatisfied: false,
                isRequestInFlight: true,
                primaryAction: .none,
                secondaryAction: nil
            )
        case (.authorized, _):
            return PermissionHubItem(
                id: .microphone,
                title: PermissionKind.microphone.title,
                detail: detail,
                statusLabel: String(localized: "Verildi"),
                helperText: interactionState == .granted ? String(localized: "Mikrofon izni verildi.") : nil,
                isRequired: isRequired,
                isSatisfied: true,
                isRequestInFlight: false,
                primaryAction: .none,
                secondaryAction: nil
            )
        case (.denied, _), (.restricted, _):
            return PermissionHubItem(
                id: .microphone,
                title: PermissionKind.microphone.title,
                detail: detail,
                statusLabel: String(localized: "Reddedildi"),
                helperText: String(localized: "Mikrofon izni verilmedi. Sağdaki düğmeyle Sistem Ayarları'nı açabilirsin."),
                isRequired: isRequired,
                isSatisfied: false,
                isRequestInFlight: false,
                primaryAction: .openSettings,
                secondaryAction: nil
            )
        case (.notDetermined, _):
            return PermissionHubItem(
                id: .microphone,
                title: PermissionKind.microphone.title,
                detail: detail,
                statusLabel: String(localized: "İzin bekleniyor"),
                helperText: String(localized: "Sağdaki düğme tıklanabilir. İzin penceresini açar."),
                isRequired: isRequired,
                isSatisfied: false,
                isRequestInFlight: false,
                primaryAction: .request,
                secondaryAction: nil
            )
        @unknown default:
            return PermissionHubItem(
                id: .microphone,
                title: PermissionKind.microphone.title,
                detail: detail,
                statusLabel: String(localized: "Durum bilinmiyor"),
                helperText: nil,
                isRequired: isRequired,
                isSatisfied: false,
                isRequestInFlight: false,
                primaryAction: .openSettings,
                secondaryAction: nil
            )
        }
    }

    private func makeScreenRecordingPermissionItem() -> PermissionHubItem {
        let isRequired = selectedRecordingSource == .screen || selectedRecordingSource == .window || isSystemAudioEnabled
        let detail = isSystemAudioEnabled
            ? String(localized: "Ekran ve sistem sesi kaydı için gerekli")
            : String(localized: "Ekran veya pencere kaydı için gerekli")
        let interactionState = permissionInteractionStates[.screenRecording] ?? .idle

        if interactionState == .requesting {
            return PermissionHubItem(
                id: .screenRecording,
                title: PermissionKind.screenRecording.title,
                detail: detail,
                statusLabel: String(localized: "İzin penceresi veya sistem ayarı açık olabilir"),
                helperText: String(localized: "Ekran kaydı izni bazen ayrı bir sistem penceresinde görünür. Arkada kalmış olabilir; Sistem Ayarları'nı da kontrol et."),
                isRequired: isRequired,
                isSatisfied: false,
                isRequestInFlight: true,
                primaryAction: .none,
                secondaryAction: nil
            )
        }

        if screenPermissionNeedsRestart {
            return PermissionHubItem(
                id: .screenRecording,
                title: PermissionKind.screenRecording.title,
                detail: detail,
                statusLabel: String(localized: "Yeniden açılmalı"),
                helperText: String(localized: "İzin verildi. Değişikliğin aktif olması için uygulamayı kapatıp yeniden aç."),
                isRequired: isRequired,
                isSatisfied: true,
                isRequestInFlight: false,
                primaryAction: .restartApp,
                secondaryAction: .openSettings
            )
        }

        switch screenRecordingPermissionStatus {
        case .authorized:
            return PermissionHubItem(
                id: .screenRecording,
                title: PermissionKind.screenRecording.title,
                detail: detail,
                statusLabel: String(localized: "Verildi"),
                helperText: interactionState == .granted ? String(localized: "Ekran kaydı izni verildi.") : nil,
                isRequired: isRequired,
                isSatisfied: true,
                isRequestInFlight: false,
                primaryAction: .none,
                secondaryAction: nil
            )
        case .denied:
            return PermissionHubItem(
                id: .screenRecording,
                title: PermissionKind.screenRecording.title,
                detail: detail,
                statusLabel: String(localized: "Gerekli"),
                helperText: String(localized: "Sağdaki düğmeler izin istemek veya Sistem Ayarları'nı açmak içindir."),
                isRequired: isRequired,
                isSatisfied: !isRequired,
                isRequestInFlight: false,
                primaryAction: .openSettings,
                secondaryAction: .request
            )
        }
    }

    private func refreshPermissionStatus() {
        switch selectedRecordingSource {
        case .camera:
            var lines = [
                String(localized: "Kamera izni: \(permissionLabel(for: .video)). Mikrofon izni: \(permissionLabel(for: .audio)).")
            ]
            if isSystemAudioEnabled {
                lines.append(String(localized: "Sistem sesi için ekran kaydı izni: \(screenPermissionLabel())."))
            }
            permissionStatusText = lines.joined(separator: " ")
        case .screen, .window:
            var lines = [String(localized: "Ekran kaydı izni: \(screenPermissionLabel()).")]
            lines.append(String(localized: "Mikrofon izni: \(permissionLabel(for: .audio))."))
            if isScreenCameraOverlayEnabled {
                lines.append(String(localized: "Kamera kutusu için kamera izni: \(permissionLabel(for: .video))."))
            }
            if screenPermissionNeedsRestart {
                lines.append(String(localized: "İzin verdiysen macOS değişikliği görmek için uygulamayı kapatıp yeniden açman gerekebilir."))
            }
            permissionStatusText = lines.joined(separator: " ")
        case .audio:
            var lines = [String(localized: "Mikrofon izni: \(permissionLabel(for: .audio)).")]
            if isSystemAudioEnabled {
                lines.append(String(localized: "Sistem sesi için ekran kaydı izni: \(screenPermissionLabel())."))
            }
            permissionStatusText = lines.joined(separator: " ")
        }
    }

    /// Announces the current recording settings summary via VoiceOver.
    func announceCurrentSettings() {
        var parts = [String(localized: "Mod \(currentPresetReadinessLabel)."), accessibilitySetupSummary]
        if let permissionSummary = accessibilityPermissionSummary {
            parts.append(permissionSummary)
        }
        if let keyboardShortcutWarning = keyboardShortcutAccessibilityWarning {
            parts.append(keyboardShortcutWarning)
        }
        let announcement = parts.joined(separator: " ")
        let settings = FrameCoachPreferences(
            speechMode: .automatic,
            feedbackFrequency: frameCoachFeedbackFrequency,
            repeatInterval: frameCoachRepeatInterval,
            showsOnScreenText: showsFrameCoachTextOnScreen,
            spatialAudioMode: frameCoachSpatialAudioMode,
            playsCenterConfirmation: playsFrameCoachCenterConfirmation
        )
        speechCuePlayer.speakIfNeeded(announcement, isEnabled: true, key: announcement, settings: settings)
    }

    func announceText(_ text: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(
            element: app,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: text,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    private func permissionLabel(for mediaType: AVMediaType) -> String {
        switch permissionProvider.authorizationStatus(for: mediaType) {
        case .authorized:
            return String(localized: "verildi")
        case .notDetermined:
            return String(localized: "henüz sorulmadı")
        case .denied:
            return String(localized: "reddedildi")
        case .restricted:
            return String(localized: "kısıtlı")
        @unknown default:
            return String(localized: "bilinmiyor")
        }
    }

    private func syncAvailableDevices() {
        let previousCameraID = selectedCameraID
        let previousMicrophoneID = selectedMicrophoneID

        cameras = cameraPermissionStatus == .authorized ? recorder.cameraDevices() : []
        microphones = microphonePermissionStatus == .authorized ? recorder.microphoneDevices() : []

        selectedCameraID = resolveSelection(
            preferredID: previousCameraID,
            devices: cameras,
            fallback: { $0.first?.id ?? "" }
        )
        selectedMicrophoneID = resolveSelection(
            preferredID: previousMicrophoneID,
            devices: microphones,
            fallback: { _ in preferredMicrophoneID() }
        )

        if selectedCameraID != previousCameraID || selectedMicrophoneID != previousMicrophoneID {
            isRecorderConfigured = false
        }
    }

    private func resolveSelection(
        preferredID: String,
        devices: [InputDevice],
        fallback: ([InputDevice]) -> String
    ) -> String {
        guard !devices.isEmpty else { return "" }
        if devices.contains(where: { $0.id == preferredID }) {
            return preferredID
        }
        return fallback(devices)
    }

    private var selectedCameraNameOrFallback: String {
        cameras.first(where: { $0.id == selectedCameraID })?.name
            ?? cameras.first?.name
            ?? String(localized: "seçilmedi")
    }

    private func selectedMicrophoneNameOrFallback(required: Bool) -> String {
        if selectedMicrophoneID.isEmpty {
            return required ? String(localized: "seçilmedi") : String(localized: "kapalı")
        }
        return microphones.first(where: { $0.id == selectedMicrophoneID })?.name
            ?? String(localized: "seçilmedi")
    }

    private var selectedDisplayNameOrFallback: String {
        availableDisplays.first(where: { $0.id == selectedDisplayID })?.name
            ?? String(localized: "seçilmedi")
    }

    private var selectedWindowNameOrFallback: String {
        availableWindows.first(where: { $0.id == selectedWindowID })?.name
            ?? String(localized: "seçilmedi")
    }

    private func makeStatusText() -> String {
        if selectedRecordingSource == .audio {
            return makeAudioRecordingStatusText()
        }

        if selectedRecordingSource != .camera {
            return makeScreenRecordingStatusText()
        }

        let missingPermissions = missingPermissionNames()
        if !missingPermissions.isEmpty {
            return String(localized: "Kayıt için şu izinler gerekli: \(missingPermissions.joined(separator: ", ")). Aşağıdaki butonlardan izin verin.")
        }

        if cameras.isEmpty {
            return String(localized: "Kamera bulunduğunda seçim burada görünecek.")
        }

        if microphones.isEmpty {
            return String(localized: "Mikrofon bulunduğunda seçim burada görünecek.")
        }

        if isSystemAudioEnabled {
            guard screenRecordingPermissionStatus == .authorized else {
                return String(localized: "Sistem sesi için macOS ekran kaydı izni gerekli.")
            }
            return String(localized: "\(currentPresetReadinessLabel) hazır. Mikrofon ve sistem sesi kayda eklenecek.")
        }

        return String(localized: "\(currentPresetReadinessLabel) hazır.")
    }

    private func makeScreenRecordingStatusText() -> String {
        guard screenRecordingPermissionStatus == .authorized else {
            if screenPermissionNeedsRestart {
                return String(localized: "Ekran kaydı izni verdiysen uygulamayı kapatıp yeniden aç. Olmazsa Sistem Ayarları > Gizlilik ve Güvenlik > Ekran Kaydı'nı kontrol et.")
            }
            return String(localized: "Ekran kaydı için macOS ekran kaydı izni gerekli.")
        }

        if let overlayProblem = screenOverlayReadiness.message {
            return overlayProblem
        }

        let audioSummary = screenAudioSummary

        switch selectedRecordingSource {
        case .screen:
            if availableDisplays.isEmpty {
                return String(localized: "Paylaşılabilir ekran bulunamadı.")
            }
            if selectedDisplayID.isEmpty {
                return String(localized: "Kayıt için bir ekran seçin.")
            }
            return String(localized: "\(currentPresetReadinessLabel) hazır. \(audioSummary)")
        case .window:
            if availableWindows.isEmpty {
                return String(localized: "Paylaşılabilir pencere bulunamadı.")
            }
            if selectedWindowID.isEmpty {
                return String(localized: "Kayıt için bir pencere seçin.")
            }
            return String(localized: "\(currentPresetReadinessLabel) hazır. \(audioSummary)")
        case .camera, .audio:
            return String(localized: "Hazır")
        }
    }

    private func makeAudioRecordingStatusText() -> String {
        if !selectedMicrophoneID.isEmpty && microphonePermissionStatus != .authorized {
            return String(localized: "Ses kaydı için mikrofon izni gerekli.")
        }

        if !isSystemAudioEnabled && selectedMicrophoneID.isEmpty {
            return String(localized: "Ses kaydı için bir mikrofon seçin ya da sistem sesini dahil edin.")
        }

        if isSystemAudioEnabled && screenRecordingPermissionStatus != .authorized {
            return String(localized: "Sistem sesi için macOS ekran kaydı izni gerekli.")
        }

        return String(localized: "\(currentPresetReadinessLabel) hazır. \(screenAudioSummary)")
    }

    private var screenAudioSummary: String {
        let usesMicrophone = !selectedMicrophoneID.isEmpty

        switch (usesMicrophone, isSystemAudioEnabled) {
        case (true, true):
            return String(localized: "Mikrofon ve sistem sesi kayda eklenecek.")
        case (true, false):
            return String(localized: "Yalnızca mikrofon kayda eklenecek.")
        case (false, true):
            return String(localized: "Yalnızca sistem sesi kayda eklenecek.")
        case (false, false):
            return String(localized: "Mikrofon ve sistem sesi kapalı.")
        }
    }

    private func missingPermissionNames() -> [String] {
        var names: [String] = []
        if cameraPermissionStatus != .authorized {
            names.append(String(localized: "kamera"))
        }
        if microphonePermissionStatus != .authorized {
            names.append(String(localized: "mikrofon"))
        }
        return names
    }

    private var screenOverlayReadiness: (isReady: Bool, message: String?) {
        guard isScreenCameraOverlayEnabled else {
            return (true, nil)
        }

        guard cameraPermissionStatus == .authorized else {
            return (false, String(localized: "Kamera kutusu için kamera izni gerekli."))
        }

        guard !cameras.isEmpty else {
            return (false, String(localized: "Kamera kutusu için kullanılabilir kamera bulunamadı."))
        }

        guard !selectedCameraID.isEmpty else {
            return (false, String(localized: "Kamera kutusu için bir kamera seçin."))
        }

        if let camera = AVCaptureDevice(uniqueID: selectedCameraID) {
            let effectNames = CameraVideoEffectsGuard.activeEffectNames(for: camera)
            if !effectNames.isEmpty {
                return (
                    false,
                    String(localized: "Kamera denetim merkezindeki video efektleri açık: \(effectNames.joined(separator: ", ")). Bu efektleri kapatıp tekrar deneyin.")
                )
            }
        }

        return (true, nil)
    }

    private func validateRecordingReadiness() throws {
        if cameraPermissionStatus != .authorized {
            throw CaptureRecorderError.cameraPermissionDenied
        }
        if microphonePermissionStatus != .authorized {
            throw CaptureRecorderError.microphonePermissionDenied
        }
        if isSystemAudioEnabled && screenRecordingPermissionStatus != .authorized {
            throw ScreenRecordingError.cannotStartStream
        }
    }

    private func configureFrameCoachFeed() {
        recorder.setPreviewFrameHandler { [weak self, frameAnalysisService, frameLightingAnalyzer] pixelBuffer, presentationTime in
            Task.detached(priority: .utility) {
                let analysis = frameAnalysisService.analyze(pixelBuffer: pixelBuffer)
                let lightingAnalysis = frameLightingAnalyzer.analyze(pixelBuffer: pixelBuffer)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.processAutoReframeAnalysis(analysis, at: presentationTime)
                    self.processCaptureCoachAnalysis(frameAnalysis: analysis, lightingAnalysis: lightingAnalysis)
                }
            }
        }
        cameraOverlayRecorder.setPreviewFrameHandler { [weak self, frameAnalysisService, frameLightingAnalyzer] pixelBuffer, _ in
            Task.detached(priority: .utility) {
                let analysis = frameAnalysisService.analyze(pixelBuffer: pixelBuffer)
                let lightingAnalysis = frameLightingAnalyzer.analyze(pixelBuffer: pixelBuffer)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.processCaptureCoachAnalysis(frameAnalysis: analysis, lightingAnalysis: lightingAnalysis)
                }
            }
        }
        updatePreviewAnalysisState()
    }

    private func prepareAnalysisPreviewIfPossible() async {
        if selectedRecordingSource == .camera {
            guard isFrameCoachEnabled || isAutoReframeEnabled else { return }
            guard hasRequiredPermissions else { return }
            guard !selectedCameraID.isEmpty, !selectedMicrophoneID.isEmpty else { return }

            do {
                try await configureRecorder()
                recorder.startSessionInBackground()
            } catch {
                report(error)
            }
            return
        }

        guard selectedPreset.isScreenPreset, isScreenCameraOverlayEnabled, isFrameCoachEnabled else { return }
        await prepareScreenOverlayPreviewIfPossible()
    }

    private var isScreenOverlayFrameCoachActive: Bool {
        selectedPreset.isScreenPreset && isScreenCameraOverlayEnabled && isFrameCoachEnabled
    }

    private var isCameraPreviewAnalysisActive: Bool {
        selectedRecordingSource == .camera && (isFrameCoachEnabled || isAutoReframeEnabled)
    }

    private var isAnyPreviewAnalysisActive: Bool {
        isCameraPreviewAnalysisActive || isScreenOverlayFrameCoachActive
    }

    private func resetFrameCoachAnalysisState() {
        consecutiveMissingFaceAnalyses = 0
        lastAnnouncedSubjectCount = nil
        lastGoodFrameAt = nil
        lastGoodInstruction = nil
        if !isFrameCoachEnabled {
            currentFrameCoachInstruction = nil
        }
    }

    private func updateScreenOverlayPreviewState() {
        guard showsScreenOverlayConfiguration else {
            cameraOverlayRecorder.stopSession()
            return
        }

        Task {
            await prepareScreenOverlayPreviewIfPossible()
        }
    }

    private func prepareScreenOverlayPreviewIfPossible() async {
        guard showsScreenOverlayConfiguration else { return }
        guard cameraPermissionStatus == .authorized else { return }
        guard !selectedCameraID.isEmpty else { return }

        do {
            try await cameraOverlayRecorder.configure(cameraDeviceID: selectedCameraID, mode: selectedMode)
            cameraOverlayRecorder.startSessionInBackground()
        } catch {
            report(error)
        }
    }

    func processAutoReframeAnalysis(_ analysis: FrameAnalysis?, at time: CMTime = .zero) {
        guard isAutoReframeEnabled else {
            currentAutoReframeCrop = .fullFrame
            return
        }

        let targetCrop: AutoReframeCrop
        if selectedMode == .vertical1080p {
            targetCrop = autoReframeEngine.portraitCrop(for: analysis)
        } else {
            targetCrop = autoReframeEngine.crop(for: analysis, mode: selectedMode)
        }
        currentAutoReframeCrop = autoReframeSmoother.step(towards: targetCrop)

        if isRecording {
            autoReframeTimeline.append(crop: currentAutoReframeCrop, at: time)
            lastAutoReframeKeyframeCount = autoReframeTimeline.keyframes.count
            lastAutoReframeUsedVideoComposition = false
            lastAutoReframeUsedFallbackExport = false
            lastAutoReframeStrategy = autoReframeEngine.strategyDescription(for: analysis)
        }
    }

    private func resetAutoReframeDebugState() {
        lastAutoReframeKeyframeCount = 0
        lastAutoReframeUsedVideoComposition = false
        lastAutoReframeUsedFallbackExport = false
        lastAutoReframeStrategy = String(localized: "hazır")
    }

    private func resetPendingScreenRecordingState() {
        pendingScreenRecordingFinalURL = nil
        pendingScreenCaptureResult = nil
        pendingOverlayCaptureResult = nil
        pendingScreenOverlayCaptureURL = nil
        pendingScreenOverlayPosition = .bottomRight
        pendingScreenOverlaySize = .medium
        pendingScreenRecordingMode = .horizontal1080p
        pendingScreenMicrophoneCaptureResult = nil
        pendingScreenMicrophoneCaptureURL = nil
        pendingScreenMicrophoneWarning = nil
        pendingScreenSystemAudioCaptureResult = nil
        pendingScreenSystemAudioCaptureURL = nil
        pendingScreenSystemAudioWarning = nil
        pendingScreenCursorTimeline = .empty
        pendingScreenKeyboardShortcutTimeline = .empty
    }

    private func updatePreviewAnalysisState() {
        recorder.setPreviewFramesEnabled(isCameraPreviewAnalysisActive)
        cameraOverlayRecorder.setPreviewFramesEnabled(isScreenOverlayFrameCoachActive)

        if !isAnyPreviewAnalysisActive {
            resetFrameCoachAnalysisState()
        }
    }

    func autoReframeExportSummary(keyframeCount: Int, usedVideoComposition: Bool) -> String {
        guard usedVideoComposition else {
            return String(localized: "normal export tamamlandı")
        }

        return String(localized: "otomatik kadraj uygulandı, \(keyframeCount) ana kare kullanıldı")
    }

    private func automaticFrameCoachingProfile(for analysis: FrameAnalysis) -> FrameCoachingProfile {
        if selectedPreset.isScreenPreset {
            return .screenGuide
        }

        if analysis.subjectCount != .one {
            return selectedMode == .vertical1080p ? .verticalConversation : .twoPersonPodcast
        }

        if selectedMode == .vertical1080p {
            return .verticalSocialVideo
        }

        return .singleDeskSpeaker
    }

    func refreshScreenRecordingOptions() async {
        await refreshScreenRecordingSources()
    }

    private func refreshScreenRecordingSources() async {
        guard selectedRecordingSource != .camera && selectedRecordingSource != .audio else {
            availableDisplays = []
            availableWindows = []
            selectedDisplayID = ""
            selectedWindowID = ""
            screenPermissionConfirmedBySourceFetch = false
            errorText = nil
            statusText = makeStatusText()
            return
        }

        // SCShareableContent.excludingDesktopWindows, ekran kaydı izni olmadan
        // sistemde permission prompt tetikleyebilir veya asılı kalabilir.
        // İzin verilmemişse listeleri boş bırak, statusText'i güncelle.
        guard screenRecordingPermissionStatus == .authorized else {
            availableDisplays = []
            availableWindows = []
            selectedDisplayID = ""
            selectedWindowID = ""
            screenPermissionConfirmedBySourceFetch = false
            statusText = makeStatusText()
            return
        }

        async let displays = loadAvailableDisplays()
        async let windows = loadAvailableWindows()

        let resolvedDisplays = await displays
        let resolvedWindows = await windows

        availableDisplays = resolvedDisplays
        availableWindows = resolvedWindows
        selectedDisplayID = resolveScreenSelection(preferredID: selectedDisplayID, options: resolvedDisplays)
        selectedWindowID = resolveScreenSelection(preferredID: selectedWindowID, options: resolvedWindows)

        let hasUsableSources: Bool
        switch selectedRecordingSource {
        case .screen:
            hasUsableSources = !resolvedDisplays.isEmpty
        case .window:
            hasUsableSources = !resolvedWindows.isEmpty
        case .camera, .audio:
            hasUsableSources = false
        }

        screenPermissionConfirmedBySourceFetch = hasUsableSources
        if hasUsableSources {
            screenPermissionNeedsRestart = false
        }

        errorText = nil
        statusText = makeStatusText()
    }

    private func loadAvailableDisplays() async -> [ScreenDisplayOption] {
        do {
            return try await screenRecordingProvider.availableDisplays()
        } catch {
            return []
        }
    }

    private func loadAvailableWindows() async -> [ScreenWindowOption] {
        do {
            return try await screenRecordingProvider.availableWindows()
        } catch {
            return []
        }
    }

    private func resolveScreenSelection<T: Identifiable & Hashable>(
        preferredID: String,
        options: [T]
    ) -> String where T.ID == String {
        guard !options.isEmpty else { return "" }
        if options.contains(where: { $0.id == preferredID }) {
            return preferredID
        }
        return options.first?.id ?? ""
    }

    private func screenPermissionLabel() -> String {
        switch screenRecordingPermissionStatus {
        case .authorized:
            return String(localized: "verildi")
        case .denied:
            return screenPermissionNeedsRestart
                ? String(localized: "yeniden açılış bekleniyor olabilir")
                : String(localized: "gerekli")
        }
    }

    private func currentScreenCaptureTargetFrame() -> CGRect? {
        switch selectedRecordingSource {
        case .screen:
            return availableDisplays.first(where: { $0.id == selectedDisplayID })?.frame
        case .window:
            return availableWindows.first(where: { $0.id == selectedWindowID })?.frame
        case .camera, .audio:
            return nil
        }
    }

    private func applyPresetSelection(refresh: Bool) {
        selectedMode = selectedPreset.recordingMode
        if selectedPreset.isAudioPreset {
            selectedRecordingSource = .audio
        } else {
            selectedRecordingSource = selectedPreset.isCameraPreset ? .camera : selectedScreenCaptureSource.recordingSource
        }

        guard refresh else { return }
        refreshDeviceState()
    }

    private func restoreLastRecordingConfiguration(_ configuration: LastRecordingConfiguration) {
        isRestoringLastRecordingConfiguration = true
        defer { isRestoringLastRecordingConfiguration = false }

        selectedPreset = configuration.selectedPreset
        selectedScreenCaptureSource = configuration.selectedScreenCaptureSource
        isScreenCameraOverlayEnabled = configuration.isScreenCameraOverlayEnabled
        isSystemAudioEnabled = configuration.isSystemAudioEnabled
        isCursorHighlightEnabled = configuration.isCursorHighlightEnabled
        isKeyboardShortcutOverlayEnabled = configuration.isKeyboardShortcutOverlayEnabled
        isAutoReframeEnabled = configuration.isAutoReframeEnabled
        isFrameCoachEnabled = configuration.isFrameCoachEnabled
        selectedCameraID = configuration.selectedCameraID
        selectedMicrophoneID = configuration.selectedMicrophoneID
        selectedDisplayID = configuration.selectedDisplayID
        selectedWindowID = configuration.selectedWindowID
    }

    private func persistLastRecordingConfiguration() {
        guard !isRestoringLastRecordingConfiguration else { return }

        lastRecordingConfigurationStore.configuration = LastRecordingConfiguration(
            selectedPreset: selectedPreset,
            selectedScreenCaptureSource: selectedScreenCaptureSource,
            isScreenCameraOverlayEnabled: isScreenCameraOverlayEnabled,
            isSystemAudioEnabled: isSystemAudioEnabled,
            isCursorHighlightEnabled: isCursorHighlightEnabled,
            isKeyboardShortcutOverlayEnabled: isKeyboardShortcutOverlayEnabled,
            isAutoReframeEnabled: isAutoReframeEnabled,
            isFrameCoachEnabled: isFrameCoachEnabled,
            selectedCameraID: selectedCameraID,
            selectedMicrophoneID: selectedMicrophoneID,
            selectedDisplayID: selectedDisplayID,
            selectedWindowID: selectedWindowID
        )
    }

    private func syncPresetFromCurrentSelection() {
        switch selectedRecordingSource {
        case .camera:
            selectedPreset = selectedMode == .vertical1080p ? .verticalCamera : .horizontalCamera
        case .screen:
            selectedScreenCaptureSource = .screen
            selectedPreset = selectedMode == .vertical1080p ? .verticalScreen : .horizontalScreen
        case .window:
            selectedScreenCaptureSource = .window
            selectedPreset = selectedMode == .vertical1080p ? .verticalScreen : .horizontalScreen
        case .audio:
            selectedPreset = .audioOnly
        }
    }
}

private extension String {
    var sentenceCased: String {
        guard let first else { return self }
        return String(first).uppercased(with: Locale(identifier: "tr_TR")) + dropFirst()
    }
}
