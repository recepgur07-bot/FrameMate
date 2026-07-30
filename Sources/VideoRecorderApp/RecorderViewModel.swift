import Foundation
import AVFoundation
import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
private func presentOutputDirectoryPanel(currentURL: URL) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.directoryURL = currentURL
    panel.prompt = String(localized: "Klasörü Seç")
    return panel.runModal() == .OK ? panel.url : nil
}

@MainActor
private func presentSaveDestinationPanel(suggestedURL: URL) -> URL? {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = suggestedURL.lastPathComponent
    panel.directoryURL = suggestedURL.deletingLastPathComponent()
    panel.allowedContentTypes = suggestedURL.pathExtension.lowercased() == "m4a" ? [.audio] : [.mpeg4Movie]
    return panel.runModal() == .OK ? panel.url : nil
}

private func defaultChooseOutputDirectory(currentURL: URL) -> URL? {
    MainActor.assumeIsolated {
        presentOutputDirectoryPanel(currentURL: currentURL)
    }
}

private func defaultRecordingDirectory() -> URL {
    RecordingFileNamer(homeDirectory: FileManager.default.homeDirectoryForCurrentUser).outputDirectory
}

private func defaultChooseSaveDestination(suggestedURL: URL) -> URL? {
    MainActor.assumeIsolated {
        presentSaveDestinationPanel(suggestedURL: suggestedURL)
    }
}

protocol AudioRecordingExporting: AnyObject {
    func export(
        microphoneURL: URL?,
        systemAudioURL: URL?,
        to destinationURL: URL,
        microphoneVolume: Float,
        systemAudioVolume: Float,
        pauseTimeline: RecordingPauseTimeline,
        microphoneOffsetSeconds: TimeInterval,
        systemAudioOffsetSeconds: TimeInterval
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
        pauseTimeline: RecordingPauseTimeline,
        microphoneOffsetSeconds: TimeInterval = 0,
        systemAudioOffsetSeconds: TimeInterval = 0
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
                pauseTimeline: pauseTimeline,
                offsetSeconds: microphoneOffsetSeconds
            )
        }
        if let systemAudioURL {
            systemTrackIDs = try await addAudioTracks(
                from: AVURLAsset(url: systemAudioURL),
                to: composition,
                pauseTimeline: pauseTimeline,
                offsetSeconds: systemAudioOffsetSeconds
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
        pauseTimeline: RecordingPauseTimeline,
        offsetSeconds: TimeInterval = 0
    ) async throws -> [CMPersistentTrackID] {
        let duration = try await asset.load(.duration)
        guard duration > .zero else { return [] }
        let segments = pauseTimeline.segments(for: duration, offsetSeconds: offsetSeconds)
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
        repeatInterval: .short,
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

enum AudioChannelMode: String, CaseIterable, Identifiable {
    case automatic
    case mono
    case stereo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return String(localized: "Otomatik (mikrofona göre)")
        case .mono: return String(localized: "Mono")
        case .stereo: return String(localized: "Stereo")
        }
    }
}

enum MaxRecordingDuration: Int, CaseIterable, Identifiable {
    case unlimited = 0
    case ninetySeconds = 91  // sentinel — saniye cinsinden, rawValue * 60 değil
    case two = 2
    case three = 3
    case five = 5
    case ten = 10
    case fifteen = 15
    case thirty = 30
    case sixty = 60
    case custom = -1  // sentinel — gerçek süre customMaxRecordingDurationSeconds'ta tutulur

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .unlimited:      return String(localized: "Sınırsız")
        case .ninetySeconds:  return String(localized: "90 saniye")
        case .two:            return String(localized: "2 dakika")
        case .three:          return String(localized: "3 dakika")
        case .five:           return String(localized: "5 dakika")
        case .ten:            return String(localized: "10 dakika")
        case .fifteen:        return String(localized: "15 dakika")
        case .thirty:         return String(localized: "30 dakika")
        case .sixty:          return String(localized: "60 dakika")
        case .custom:         return String(localized: "Özel süre")
        }
    }

    /// nil for `.unlimited` (no cap) and `.custom` (resolved separately from
    /// `RecorderViewModel.customMaxRecordingDurationSeconds`, since a fixed enum
    /// case can't carry a user-entered value).
    var seconds: TimeInterval? {
        switch self {
        case .unlimited:     return nil
        case .ninetySeconds: return 90
        case .custom:        return nil
        default:             return TimeInterval(rawValue * 60)
        }
    }
}

enum RecordingEndWarningLeadTime: Int, CaseIterable, Identifiable {
    case none = 0
    case threeSeconds = 3
    case fiveSeconds = 5
    case tenSeconds = 10

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none:         return String(localized: "Kapalı")
        case .threeSeconds: return String(localized: "Son 3 saniye")
        case .fiveSeconds:  return String(localized: "Son 5 saniye")
        case .tenSeconds:   return String(localized: "Son 10 saniye")
        }
    }
}

enum ElapsedTimeAnnouncementMode: String, CaseIterable, Identifiable {
    case voiceOver
    case soundEffect

    var id: String { rawValue }

    var label: String {
        switch self {
        case .voiceOver:   return String(localized: "Sesli okuma (VoiceOver)")
        case .soundEffect: return String(localized: "Ses efekti")
        }
    }
}

enum ElapsedTimeAnnouncementInterval: Int, CaseIterable, Identifiable {
    case tenSeconds = 10
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case oneMinute = 60
    case twoMinutes = 120
    case threeMinutes = 180
    case fiveMinutes = 300

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .tenSeconds:    return String(localized: "10 saniyede bir")
        case .fifteenSeconds: return String(localized: "15 saniyede bir")
        case .thirtySeconds: return String(localized: "30 saniyede bir")
        case .oneMinute:     return String(localized: "1 dakikada bir")
        case .twoMinutes:    return String(localized: "2 dakikada bir")
        case .threeMinutes:  return String(localized: "3 dakikada bir")
        case .fiveMinutes:   return String(localized: "5 dakikada bir")
        }
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
        case .request: return String(localized: "Devam")
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
    var outputDirectoryBookmarkData: Data? { get set }
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
    private let bookmarkKey = "recording.outputDirectoryBookmarkData"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var outputDirectoryPath: String? {
        get { defaults.string(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }

    var outputDirectoryBookmarkData: Data? {
        get { defaults.data(forKey: bookmarkKey) }
        set { defaults.set(newValue, forKey: bookmarkKey) }
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

private struct RestoredOutputDirectoryState {
    let url: URL
    let bookmarkData: Data?
    let accessedSecurityScopedOutputDirectoryURL: URL?
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

enum RecordingSafetyError: LocalizedError {
    case insufficientDiskSpace
    case stopWatchdogTimedOut

    var errorDescription: String? {
        switch self {
        case .insufficientDiskSpace:
            return String(localized: "Kayıt için yeterli boş disk alanı yok.")
        case .stopWatchdogTimedOut:
            return String(localized: "Kayıt durdurma zaman aşımına uğradı; bileşenlerden biri yanıt vermediği için kayıt zorla sonlandırıldı.")
        }
    }
}

enum RecordingDiskSpace {
    static let minimumStartBytes: Int64 = 500 * 1_024 * 1_024
    static let warningBytes: Int64 = 1_024 * 1_024 * 1_024
    static let criticalBytes: Int64 = 250 * 1_024 * 1_024

    static func availableBytes(at directory: URL) -> Int64? {
        guard let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return capacity
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
        didSet {
            persistLastRecordingConfiguration()
            guard hasSetUp else { return }
            synchronizeRecordingSourceWithPreset()
            refreshPermissionStatus()
            statusText = makeStatusText()
        }
    }
    var isCursorHighlightEnabled = false {
        didSet { persistLastRecordingConfiguration() }
    }
    var isKeyboardShortcutOverlayEnabled = false {
        didSet {
            persistLastRecordingConfiguration()
            requestAccessibilityPromptIfNeededForKeyboardShortcuts(wasEnabled: oldValue)
        }
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
    /// True while `isPaused` is true *because* the selected microphone disconnected
    /// mid-recording (see `handleCaptureDeviceDisconnect`), as opposed to a manual
    /// pause. Drives a distinct reconnect prompt in the recording UI instead of the
    /// generic "duraklatıldı" label. Cleared on resume or when recording stops.
    var isPausedForMicrophoneReconnect = false
    var isPreparingRecording = false
    /// True from the moment recording stops until the exported file is ready.
    /// Drives a focused "Video hazırlanıyor" panel so a VoiceOver user knows
    /// processing is still happening without needing to press anything else.
    var isFinalizingRecording = false
    var countdownRemaining: Int = 0
    var recordingCountdown: RecordingCountdown = .none {
        didSet { UserDefaults.standard.set(recordingCountdown.rawValue, forKey: "recording.countdown") }
    }
    var maxRecordingDuration: MaxRecordingDuration = .unlimited {
        didSet { UserDefaults.standard.set(maxRecordingDuration.rawValue, forKey: "recording.maxDuration") }
    }
    /// Only used when `maxRecordingDuration == .custom`; the user-entered cap, in seconds.
    var customMaxRecordingDurationSeconds: Int = 120 {
        didSet { UserDefaults.standard.set(customMaxRecordingDurationSeconds, forKey: "recording.maxDuration.custom") }
    }
    var recordingEndWarningLeadTime: RecordingEndWarningLeadTime = .none {
        didSet { UserDefaults.standard.set(recordingEndWarningLeadTime.rawValue, forKey: "recording.endWarning.leadTime") }
    }
    var audioChannelMode: AudioChannelMode = .automatic {
        didSet { UserDefaults.standard.set(audioChannelMode.rawValue, forKey: "recording.audioChannelMode") }
    }
    var isRecordingCommandSoundEnabled = true {
        didSet { UserDefaults.standard.set(isRecordingCommandSoundEnabled, forKey: "recording.sound.commandReceived") }
    }
    var isRecordingStartSoundEnabled = true {
        didSet { UserDefaults.standard.set(isRecordingStartSoundEnabled, forKey: "recording.sound.start") }
    }
    var isRecordingStopSoundEnabled = true {
        didSet { UserDefaults.standard.set(isRecordingStopSoundEnabled, forKey: "recording.sound.stop") }
    }
    var isRecordingPauseResumeSoundEnabled = true {
        didSet { UserDefaults.standard.set(isRecordingPauseResumeSoundEnabled, forKey: "recording.sound.pauseResume") }
    }
    var isElapsedTimeAnnouncementEnabled = true {
        didSet { UserDefaults.standard.set(isElapsedTimeAnnouncementEnabled, forKey: "recording.elapsedAnnouncement.enabled") }
    }
    var elapsedTimeAnnouncementMode: ElapsedTimeAnnouncementMode = .voiceOver {
        didSet { UserDefaults.standard.set(elapsedTimeAnnouncementMode.rawValue, forKey: "recording.elapsedAnnouncement.mode") }
    }
    var elapsedTimeAnnouncementInterval: ElapsedTimeAnnouncementInterval = .thirtySeconds {
        didSet { UserDefaults.standard.set(elapsedTimeAnnouncementInterval.rawValue, forKey: "recording.elapsedAnnouncement.interval") }
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
    /// Temporary captures found after an unexpected quit are retained for recovery.
    var recoveredTemporaryRecordingURLs: [URL] = []
    private(set) var didCompleteAudioRecordingExport = false
    private(set) var didEnterAudioRecordingFinalize = false
    var appAccessState: AppAccessState = .default
    var isPaywallPresented = false
    var purchasingPlan: AppAccessPlan?
    var isRestoringPurchases = false
    var paywallMessageText: String?
    var errorText: String?
    var screenPermissionNeedsRestart = false
    var permissionInteractionStates: [PermissionKind: PermissionInteractionState] = [:]
    private var screenPermissionConfirmedBySourceFetch = false
    private var accessedSecurityScopedOutputDirectoryURL: URL?
    var recordingOutputDirectoryURL: URL

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

    /// Step-by-step instructions announced via VoiceOver when screen recording permission is not granted.
    var screenRecordingPermissionGuide: String? {
        guard screenRecordingPermissionStatus == .denied, !screenPermissionNeedsRestart else { return nil }
        return String(localized: "Ekran kaydı izni gerekli. Adımlar: 1. Sistem Ayarları'nı aç. 2. Gizlilik ve Güvenlik bölümüne git. 3. Ekran Kaydı'nı seç. 4. FrameMate listede varsa aç. Listede yoksa artı düğmesine bas, Uygulamalar'dan FrameMate'i seç ve ekle. 5. FrameMate'i açıp uygulamayı yeniden başlat.")
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
                parts.append(String(localized: "ekran \(selectedDisplaySummaryNameOrFallback)"))
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
        // Block only if a required permission is still undecided (notDetermined).
        // A denied permission means the user made a conscious choice; let them proceed
        // and surface an error when they actually attempt to record.
        let undecidedRequired = requiredPermissionItems.contains { item in
            guard !item.isSatisfied else { return false }
            switch item.id {
            case .microphone:
                return microphonePermissionStatus == .notDetermined
            case .camera:
                return cameraPermissionStatus == .notDetermined
            case .screenRecording:
                return false // ScreenRecordingAuthorizationStatus has no notDetermined; always let user proceed
            }
        }
        return !undecidedRequired
    }

    var shouldShowPermissionHub: Bool {
        true
    }

    var permissionReadinessSummary: String {
        let microphoneSummary: String
        if microphonePermissionStatus == .authorized {
            microphoneSummary = String(localized: "Mikrofon tamam")
        } else {
            microphoneSummary = String(localized: "Mikrofon eksik")
        }

        let screenSummary: String
        if selectedPreset.isScreenPreset || isSystemAudioEnabled {
            screenSummary = screenRecordingPermissionStatus == .authorized || screenPermissionNeedsRestart
                ? String(localized: "Ekran kaydı tamam")
                : String(localized: "Ekran kaydı eksik")
        } else {
            screenSummary = String(localized: "Ekran kaydı şu anda gerekmiyor")
        }

        let cameraSummary: String
        if selectedPreset == .horizontalCamera || selectedPreset == .verticalCamera || isScreenCameraOverlayEnabled {
            cameraSummary = cameraPermissionStatus == .authorized
                ? String(localized: "Kamera tamam")
                : String(localized: "Kamera eksik")
        } else {
            cameraSummary = String(localized: "Kamera şu anda gerekmiyor")
        }

        var summaries = [microphoneSummary, screenSummary, cameraSummary]
        if isKeyboardShortcutOverlayEnabled {
            let accessibilitySummary = isAccessibilityPermissionGranted()
                ? String(localized: "Erişilebilirlik tamam")
                : String(localized: "Erişilebilirlik eksik")
            summaries.append(accessibilitySummary)
        }
        return String(localized: "Hazır durumu: \(summaries.joined(separator: ". ")).")
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

    /// The same user-facing explanation shown beside a disabled record button
    /// and exposed as its VoiceOver hint. `statusText` is refreshed whenever
    /// permissions, inputs, or the selected recording mode changes.
    var recordingStartBlocker: String? {
        guard !isRecording, !isPreparingRecording, !isCountingDown, !canStartRecording else {
            return nil
        }
        return statusText
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
    private var lastConfiguredVideoDeviceID: String?
    private var lastConfiguredAudioDeviceID: String?
    private var lastConfiguredMode: RecordingMode?
    private var lastConfiguredAudioChannelMode: AudioChannelMode?
    private var lastAnnouncedSubjectCount: FrameSubjectCount?
    private var lastAnnouncedSubjectCountWasOverflow = false
    private var pendingSubjectCount: FrameSubjectCount?
    private var pendingSubjectCountIsOverflowing = false
    private var pendingSubjectCountStreak = 0
    private var consecutiveMissingFaceAnalyses = 0
    private var lastGoodFrameAt: Date?
    private var lastGoodInstruction: String?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var recordingDurationTask: Task<Void, Never>?
    @ObservationIgnored private var pauseResumeTask: Task<Void, Never>?
    @ObservationIgnored private var frameCoachPreviewTask: Task<Void, Never>?
    @ObservationIgnored private var screenOverlayPreviewTask: Task<Void, Never>?
    @ObservationIgnored private var recordingSafetyTask: Task<Void, Never>?
    @ObservationIgnored private var stopWatchdogTask: Task<Void, Never>?
    /// How long stopRecording() waits for every component's completion callback before
    /// forcing the still-pending ones and re-entering finalize, so a component that never
    /// calls back (e.g. a delegate that silently drops) cannot leave the lifecycle stuck
    /// in `.stopping` forever. Overridable only for tests — production always uses the
    /// default.
    private let stopWatchdogTimeout: Duration
    @ObservationIgnored private var sleepPreventer = SleepPreventer()
    @ObservationIgnored private var workspaceObserverTokens: [NSObjectProtocol] = []
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
    private let requestAccessibilityPermissionPrompt: () -> Void
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
    private var recordingLifecycle = RecordingLifecycleState()
    /// Monotonic counter identifying the current recording attempt (Phase 5). Captured by
    /// each finalize/export task at stop time so a stale task from a previous recording
    /// can detect it's no longer current and skip writing UI state.
    private var recordingGeneration = 0
    private var isRestoringLastRecordingConfiguration = false
    private var recordingStartUptime: TimeInterval?
    private var commandSoundEndUptime: TimeInterval?
    /// The recording's single time base (Phase 2 of the recording-timing fix): resolved
    /// once the primary component's first sample has actually arrived. Pause ranges are
    /// expressed in this clock's seconds, not in wall-clock uptime, so they line up with
    /// where each component's file actually starts (t=0 = that file's own first sample).
    private var recordingSessionClock: RecordingSessionClock?
    private var isCameraSessionWarmed = false
    private var currentPauseStartOffset: TimeInterval?
    private var recordingPauseTimeline = RecordingPauseTimeline()
    @ObservationIgnored private var elapsedTimeAnnouncer = RecordingElapsedTimeAnnouncer()
    /// Duration of the most recently completed recording, set just before stopping so
    /// ContentView can include it in the VoiceOver completion announcement.
    var lastCompletedRecordingDuration: TimeInterval?

    init(
        recorder: any CaptureRecording = CaptureRecorder(),
        screenRecordingProvider: any ScreenRecordingProviding = ScreenRecorder(),
        cameraOverlayRecorder: any CameraOverlayRecording = CameraOverlayRecorder(),
        systemAudioRecorder: any SystemAudioRecordingProviding = SystemAudioRecorder(),
        microphoneAudioRecorder: any MicrophoneAudioRecordingProviding = MicrophoneAudioRecorder(),
        audioRecordingExporter: any AudioRecordingExporting = AudioRecordingExporter(),
        cursorHighlightRecorder: any CursorHighlightRecordingProviding = CursorHighlightRecorder(),
        keyboardShortcutRecorder: any KeyboardShortcutRecordingProviding = KeyboardShortcutRecorder(),
        fileNamer: RecordingFileNamer = RecordingFileNamer(outputDirectory: defaultRecordingDirectory()),
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
        requestAccessibilityPermissionPrompt: @escaping () -> Void = {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        },
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        revealInFinder: @escaping (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
        chooseOutputDirectory: @escaping (URL) -> URL? = defaultChooseOutputDirectory,
        chooseSaveDestination: @escaping (URL) -> URL? = defaultChooseSaveDestination,
        speechCuePlayer: SpeechCuePlayer = SpeechCuePlayer(),
        spatialCuePlayer: any SpatialCuePlaying = SpatialCoachCuePlayer(),
        stopWatchdogTimeout: Duration = .seconds(15)
    ) {
        self.stopWatchdogTimeout = stopWatchdogTimeout
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
        self.requestAccessibilityPermissionPrompt = requestAccessibilityPermissionPrompt
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
        if let restoredOutputDirectoryState = Self.restoreStoredOutputDirectory(
            from: recordingOutputDirectoryStore,
            defaultRecordingDirectory: fileNamer.outputDirectory
        ) {
            self.recordingOutputDirectoryURL = restoredOutputDirectoryState.url
            self.accessedSecurityScopedOutputDirectoryURL = restoredOutputDirectoryState.accessedSecurityScopedOutputDirectoryURL
            recordingOutputDirectoryStore.outputDirectoryPath = restoredOutputDirectoryState.url.path
            recordingOutputDirectoryStore.outputDirectoryBookmarkData = restoredOutputDirectoryState.bookmarkData
        } else {
            self.recordingOutputDirectoryURL = fileNamer.outputDirectory
            recordingOutputDirectoryStore.outputDirectoryPath = fileNamer.outputDirectory.path
            recordingOutputDirectoryStore.outputDirectoryBookmarkData = nil
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
        fileNamer: RecordingFileNamer = RecordingFileNamer(outputDirectory: defaultRecordingDirectory()),
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
        requestAccessibilityPermissionPrompt: @escaping () -> Void = {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        },
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
            requestAccessibilityPermissionPrompt: requestAccessibilityPermissionPrompt,
            openURL: openURL,
            revealInFinder: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
            chooseOutputDirectory: defaultChooseOutputDirectory,
            chooseSaveDestination: defaultChooseSaveDestination,
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
        requestAccessibilityPermissionPrompt: @escaping () -> Void = {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        },
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        revealInFinder: @escaping (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
        chooseOutputDirectory: @escaping (URL) -> URL? = defaultChooseOutputDirectory,
        chooseSaveDestination: @escaping (URL) -> URL? = defaultChooseSaveDestination,
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
            requestAccessibilityPermissionPrompt: requestAccessibilityPermissionPrompt,
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
        requestAccessibilityPermissionPrompt: @escaping () -> Void = {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        },
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
            requestAccessibilityPermissionPrompt: requestAccessibilityPermissionPrompt,
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
        return String(localized: "Ekran kaydında klavye kısayollarını göstermek ve Cmd+I ayar duyurusunu güvenilir almak için Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik'ten FrameMate'e izin ver.")
    }

    private func requestAccessibilityPromptIfNeededForKeyboardShortcuts(wasEnabled: Bool) {
        guard hasSetUp, !isRestoringLastRecordingConfiguration else { return }
        guard isKeyboardShortcutOverlayEnabled, !wasEnabled else { return }
        guard !isAccessibilityPermissionGranted() else { return }
        requestAccessibilityPermissionPrompt()
    }

    func openAccessibilitySettings() {
        requestAccessibilityPermissionPrompt()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        openURL(url)
    }

    private var activeFileNamer: RecordingFileNamer {
        RecordingFileNamer(outputDirectory: recordingOutputDirectoryURL)
    }

    private func userDefaultBool(forKey key: String, defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }

    func setup() async {
        guard !hasSetUp else { return }
        hasSetUp = true

        findRecoverableTempFiles()
        installRecordingSafetyObservers()
        await refreshAppAccess()
        applyPresetSelection(refresh: false)
        recordingCountdown = RecordingCountdown(rawValue: UserDefaults.standard.integer(forKey: "recording.countdown")) ?? .none
        maxRecordingDuration = MaxRecordingDuration(rawValue: UserDefaults.standard.integer(forKey: "recording.maxDuration")) ?? .unlimited
        if let storedCustomDuration = UserDefaults.standard.object(forKey: "recording.maxDuration.custom") as? Int {
            customMaxRecordingDurationSeconds = storedCustomDuration
        }
        recordingEndWarningLeadTime = RecordingEndWarningLeadTime(rawValue: UserDefaults.standard.integer(forKey: "recording.endWarning.leadTime")) ?? .none
        audioChannelMode = UserDefaults.standard.string(forKey: "recording.audioChannelMode").flatMap(AudioChannelMode.init(rawValue:)) ?? .automatic
        isRecordingCommandSoundEnabled = userDefaultBool(forKey: "recording.sound.commandReceived", defaultValue: true)
        isRecordingStartSoundEnabled = userDefaultBool(forKey: "recording.sound.start", defaultValue: true)
        isRecordingStopSoundEnabled = userDefaultBool(forKey: "recording.sound.stop", defaultValue: true)
        isRecordingPauseResumeSoundEnabled = userDefaultBool(forKey: "recording.sound.pauseResume", defaultValue: true)
        isElapsedTimeAnnouncementEnabled = userDefaultBool(forKey: "recording.elapsedAnnouncement.enabled", defaultValue: true)
        elapsedTimeAnnouncementMode = UserDefaults.standard.string(forKey: "recording.elapsedAnnouncement.mode").flatMap(ElapsedTimeAnnouncementMode.init(rawValue:)) ?? .voiceOver
        elapsedTimeAnnouncementInterval = ElapsedTimeAnnouncementInterval(rawValue: UserDefaults.standard.integer(forKey: "recording.elapsedAnnouncement.interval")) ?? .thirtySeconds
        configureFrameCoachFeed()
        refreshDeviceState()
        // A restored/default camera preset must warm the same capture session that
        // Frame Coach uses. Previously this only happened after an explicit picker
        // change or when Frame Coach was enabled, leaving the first normal video
        // recording to cold-start the camera pipeline.
        applySelectedInputs()
        if !recoveredTemporaryRecordingURLs.isEmpty {
            statusText = String(localized: "Önceki oturumdan kurtarılabilir kayıt dosyaları bulundu.")
        }
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

        // ScreenCaptureKit'in paylaşılabilir ekran/pencere listesini ilk kez istemesi
        // bazı Mac'lerde birkaç saniye sürebiliyor. Bu iş daha önce kayıt düğmesine
        // basıldıktan sonra başlatılıyordu; ses kaydı yolunda bulunmayan bu bekleme,
        // video kaydının geç başladığı izlenimini veriyordu. Kullanıcı ekran/pencere
        // modunu seçtiğinde içeriği önceden ısıtıyoruz; kayıt anı yalnızca hazır sonucu
        // kullanır. İzin yokken çağırmıyoruz, böylece açılışta beklenmedik bir sistem
        // izni istemi oluşturmayız.
        if screenRecordingPermissionStatus == .authorized {
            switch selectedRecordingSource {
            case .screen, .window:
                screenRecordingProvider.prefetchShareableContent()
            case .camera, .audio:
                break
            }
            if isSystemAudioEnabled {
                systemAudioRecorder.prefetchShareableContent()
            }
        }

        Task {
            // The user has explicitly selected screen/window capture. On recent
            // macOS releases the preflight API may retain a denied answer after
            // the user enables “Screen & System Audio Recording”, while the
            // ScreenCaptureKit query succeeds. Validate with the actual capture
            // capability instead of leaving the UI stuck on the cached result.
            await refreshScreenRecordingSources(
                forceSourceFetch: selectedRecordingSource == .screen || selectedRecordingSource == .window
            )
        }
        updatePreviewAnalysisState()
        updateScreenOverlayPreviewState()
    }

    func applySelectedInputs() {
        guard hasSetUp, !isRecording else { return }
        guard selectedPreset.isCameraPreset else {
            stopCameraSessionIfNeeded()
            statusText = makeStatusText()
            errorText = nil
            updateScreenOverlayPreviewState()
            return
        }

        Task {
            do {
                // Bu yalnızca kamera önizleme oturumunu hazırlar, gerçek kaydı
                // başlatmaz; sistem sesi izni burada zorunlu değil (bkz.
                // prepareAnalysisPreviewIfPossible ile aynı gerekçe).
                try await configureRecorder(requireSystemAudioReadiness: false)
                // Movie output'un ilk ses/video örnekleri gelmeden önce kayda başlamış
                // görünmesini önlemek için kamera akışını seçili kamera modunda önceden
                // ısıtıyoruz. Bu, analiz karelerini açmaz; yalnızca donanım hattını
                // kayıt düğmesine basılmadan hazırlar.
                guard self.selectedPreset.isCameraPreset, !self.isRecording else { return }
                self.startCameraSessionIfNeeded()
                statusText = String(localized: "\(currentPresetReadinessLabel) hazır.")
                errorText = nil
            } catch {
                report(error)
            }
        }
    }

    func configureRecorder(requireSystemAudioReadiness: Bool = true) async throws {
        try validateRecordingReadiness(requireSystemAudioReadiness: requireSystemAudioReadiness)

        guard !selectedCameraID.isEmpty else {
            throw CaptureRecorderError.cameraNotFound
        }
        guard !selectedMicrophoneID.isEmpty else {
            throw CaptureRecorderError.microphoneNotFound
        }

        // Re-adding identical inputs to a running AVCaptureSession forces the camera
        // to re-negotiate exposure/focus, which is a visible multi-second stall right
        // before recording starts. Skip the rebuild when nothing actually changed.
        if isRecorderConfigured,
           lastConfiguredVideoDeviceID == selectedCameraID,
           lastConfiguredAudioDeviceID == selectedMicrophoneID,
           lastConfiguredMode == selectedMode,
           lastConfiguredAudioChannelMode == audioChannelMode {
            return
        }

        stopCameraSessionIfNeeded()
        try await recorder.configure(
            videoDeviceID: selectedCameraID,
            audioDeviceID: selectedMicrophoneID,
            mode: selectedMode,
            audioChannelMode: audioChannelMode
        )
        isRecorderConfigured = true
        lastConfiguredVideoDeviceID = selectedCameraID
        lastConfiguredAudioDeviceID = selectedMicrophoneID
        lastConfiguredMode = selectedMode
        lastConfiguredAudioChannelMode = audioChannelMode
    }

    private func startCameraSessionIfNeeded() {
        guard !isCameraSessionWarmed else { return }
        recorder.startSessionInBackground()
        isCameraSessionWarmed = true
    }

    private func stopCameraSessionIfNeeded() {
        guard isCameraSessionWarmed else { return }
        recorder.stopSession()
        isCameraSessionWarmed = false
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

        let commandSoundDelay = playCommandReceivedSoundIfEnabled()

        if recordingCountdown == .none {
            startRecording(afterCommandSoundDelay: commandSoundDelay)
        } else {
            beginCountdown()
        }
    }

    func togglePauseResume() {
        guard canPauseRecording else { return }

        if isPaused {
            let soundDuration = playPauseResumeSoundIfEnabled()
            completeResumeAfterTransitionSound(duration: soundDuration)
        } else {
            beginCurrentPauseRange()
            isPaused = true
            _ = playPauseResumeSoundIfEnabled()
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
        // Display-only: currentRecordingDuration and the UI elapsed timer read this, but
        // it must never feed the pause timeline — see recordingSessionClock for that.
        recordingStartUptime = ProcessInfo.processInfo.systemUptime
        recordingSessionClock = nil
        currentPauseStartOffset = nil
        recordingPauseTimeline = .empty
        isPaused = false
        isPausedForMicrophoneReconnect = false
    }

    /// The component whose first sample defines this recording's session clock: the
    /// screen/camera video for those modes, or whichever audio component is actually
    /// running in audio-only mode (microphone if selected, otherwise system audio).
    private func primaryComponentFirstSampleTime() -> CMTime? {
        switch selectedRecordingSource {
        case .camera:
            return recorder.firstSamplePresentationTime
        case .screen, .window:
            return screenRecordingProvider.firstSamplePresentationTime
        case .audio:
            return selectedMicrophoneID.isEmpty
                ? systemAudioRecorder.firstSamplePresentationTime
                : microphoneAudioRecorder.firstSamplePresentationTime
        }
    }

    /// Resolves `recordingSessionClock` the first time the primary component's first
    /// sample becomes observable. A no-op once resolved, and a no-op if the first sample
    /// hasn't landed yet — callers must treat "not yet resolved" as session time 0
    /// (see beginCurrentPauseRange/finishCurrentPauseRange), never fall back to wall time.
    private func resolveSessionClockIfPossible() {
        guard recordingSessionClock == nil else { return }
        guard let firstSampleTime = primaryComponentFirstSampleTime(), firstSampleTime.isValid else { return }
        recordingSessionClock = RecordingSessionClock(sessionZero: firstSampleTime)
    }

    /// A secondary (non-primary) component's start offset relative to session zero, for
    /// Phase 3's per-track alignment. Falls back to 0 (assume it started with the
    /// primary) if the session clock or this component's first sample was never
    /// resolved — degrading to the old, "everything starts together" behavior rather
    /// than producing a nonsensical export.
    /// Phase 5: whether `generation` (captured by a finalize/export task at stop time)
    /// still matches the live recording attempt. A mismatch means a newer recording has
    /// since started and this task's result must not overwrite its UI state.
    private func isCurrentGeneration(_ generation: Int) -> Bool {
        generation == recordingGeneration
    }

    private func secondaryOffsetSeconds(for firstSampleTime: CMTime?) -> TimeInterval {
        guard let firstSampleTime, firstSampleTime.isValid, let recordingSessionClock else {
            runtimeDebugLog("Recording session timing: a secondary component's first sample was never observed; treating its offset as 0")
            return 0
        }
        let offset = recordingSessionClock.signedSessionSeconds(at: firstSampleTime)
        runtimeDebugLog("Recording session timing: secondary component offset = \(offset)s (first sample host time \(firstSampleTime.seconds)s)")
        return offset
    }

    /// Phase 6 instrumentation: a handful of diagnostic lines at finalize time so a
    /// residual timing issue is measurable from the user's own runtime debug log instead
    /// of only guessed at. Logs session zero and every pause range in session seconds;
    /// per-component offsets are logged at their own call sites right before export.
    private func logSessionTimingSummary(pauseTimeline: RecordingPauseTimeline) {
        guard let recordingSessionClock else {
            runtimeDebugLog("Recording session timing: session clock never resolved (primary component's first sample never arrived)")
            return
        }
        runtimeDebugLog("Recording session timing: session zero (host time) = \(recordingSessionClock.sessionZero.seconds)")
        if pauseTimeline.ranges.isEmpty {
            runtimeDebugLog("Recording session timing: no pauses")
        } else {
            for range in pauseTimeline.ranges {
                runtimeDebugLog("Recording session timing: pause [\(range.start)s, \(range.end)s] in session time")
            }
        }
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
        isPausedForMicrophoneReconnect = false
        statusText = selectedRecordingSource == .audio ? String(localized: "Ses kaydı yapılıyor") : String(localized: "Kayıt yapılıyor")
        sleepPreventer.prevent(reason: selectedRecordingSource == .audio ? String(localized: "Ses kaydı devam ediyor") : String(localized: "Video kaydı devam ediyor"))
        startMaxDurationTimer()
    }

    private func beginCurrentPauseRange() {
        resolveSessionClockIfPossible()
        // If the primary component's first sample hasn't arrived yet, this pause has no
        // meaningful session time other than 0 — there is no "before" in a clock that
        // hasn't started. Falling back to wall-clock uptime here is exactly the Phase 2
        // bug (a pause measured from a different clock than the one the cut is applied
        // to), so we deliberately don't.
        currentPauseStartOffset = recordingSessionClock?.sessionSeconds(at: RecordingSessionClock.now()) ?? 0
    }

    private func finishCurrentPauseRange() {
        guard let pauseStart = currentPauseStartOffset else { return }
        resolveSessionClockIfPossible()

        let pauseEnd = max(pauseStart, recordingSessionClock?.sessionSeconds(at: RecordingSessionClock.now()) ?? pauseStart)
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
                        self.soundEffectPlayer.playCountdownTick(
                            remaining: remaining,
                            total: self.recordingCountdown.rawValue
                        )
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
            resetSubjectCountTracking()
            consecutiveMissingFaceAnalyses = 0
            lastGoodFrameAt = nil
            lastGoodInstruction = nil
            speechCuePlayer.speakIfNeeded(
                String(localized: "Kadraj koçu açık"),
                isEnabled: allowsAudibleFrameCoachFeedback,
                settings: frameCoachPreferences
            )
            // "Kadraj koçu açık" duyurulduktan sonra frekans kapısını sıfırla ki
            // ilk analiz talimatı gecikme yaşamadan hemen söylensin.
            speechCuePlayer.resetFrequencyGate()
        } else {
            currentFrameCoachInstruction = nil
            speechCuePlayer.reset()
            spatialCuePlayer.reset()
            consecutiveMissingFaceAnalyses = 0
            lastGoodFrameAt = nil
            lastGoodInstruction = nil
            speechCuePlayer.speakIfNeeded(
                String(localized: "Kadraj koçu kapalı"),
                isEnabled: allowsAudibleFrameCoachFeedback,
                settings: frameCoachPreferences
            )
        }
    }

    private func resetSubjectCountTracking() {
        lastAnnouncedSubjectCount = nil
        lastAnnouncedSubjectCountWasOverflow = false
        pendingSubjectCount = nil
        pendingSubjectCountIsOverflowing = false
        pendingSubjectCountStreak = 0
    }

    func toggleAutoReframe() {
        isAutoReframeEnabled.toggle()

        if isAutoReframeEnabled {
            updatePreviewAnalysisState()
        } else {
            autoReframeSmoother.reset()
            currentAutoReframeCrop = .fullFrame
            updatePreviewAnalysisState()
        }
    }

    func updateFrameCoachInstruction(_ instruction: String) {
        guard isFrameCoachEnabled else { return }

        currentFrameCoachInstruction = instruction
        speechCuePlayer.speakIfNeeded(
            instruction,
            isEnabled: isFrameCoachEnabled && allowsAudibleFrameCoachFeedback,
            key: instruction,
            settings: frameCoachPreferences
        )
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
                    isEnabled: allowsAudibleFrameCoachFeedback,
                    settings: frameCoachPreferences
                )
                return
            }

            consecutiveMissingFaceAnalyses += 1
            guard consecutiveMissingFaceAnalyses >= 3 else { return }
            currentFrameCoachInstruction = FrameCoachingEngine.noFaceInstruction
            // Yüz kaybolunca kısa aralıkla tekrar et (2s) — kör kullanıcı hızlıca uyarılmalı.
            var urgentPreferences = frameCoachPreferences
            urgentPreferences.repeatInterval = .short
            speechCuePlayer.speakIfNeeded(
                FrameCoachingEngine.noFaceInstruction,
                isEnabled: allowsAudibleFrameCoachFeedback,
                settings: urgentPreferences
            )
            return
        }

        consecutiveMissingFaceAnalyses = 0
        let guidanceDetail = captureCoachingEngine.instructionDetail(
            frameAnalysis: analysis,
            lightingAnalysis: lightingAnalysis,
            mode: selectedMode,
            profile: automaticFrameCoachingProfile(for: analysis)
        )
        let guidance = guidanceDetail.text
        if allowsAudibleFrameCoachFeedback,
           let cue = spatialCueResolver.cue(for: analysis, guidance: guidanceDetail, mode: selectedMode) {
            spatialCuePlayer.play(cue, preferences: frameCoachPreferences)
        }

        if guidanceDetail.kind == .lowLight {
            currentFrameCoachInstruction = guidance
            speechCuePlayer.speakIfNeeded(
                guidance.sentenceCased,
                isEnabled: allowsAudibleFrameCoachFeedback,
                settings: frameCoachPreferences
            )
            return
        }

        let isGood = guidanceDetail.kind == .balanced
        if isGood {
            lastGoodFrameAt = Date()
            lastGoodInstruction = guidance
        }

        // "İyi duruma kilitle": son 3 saniyede kadraj iyiydi ve şu anki şikayet hafifse — sessiz kal.
        // 3 saniye: kör kullanıcı pozisyon değişikliğini hızlıca öğrenmeli.
        let isLockedGood: Bool
        if let lastGood = lastGoodFrameAt, !isGood, Date().timeIntervalSince(lastGood) < 3 {
            isLockedGood = guidanceDetail.kind == .softAdjustment
        } else {
            isLockedGood = false
        }

        currentFrameCoachInstruction = isLockedGood ? (lastGoodInstruction ?? guidance) : guidance

        guard !isLockedGood else { return }

        let countChanged = lastAnnouncedSubjectCount != analysis.subjectCount
            || lastAnnouncedSubjectCountWasOverflow != analysis.isOverflowing
        if countChanged {
            let isFirstEverAnnouncement = lastAnnouncedSubjectCount == nil
            let matchesPendingCandidate = pendingSubjectCount == analysis.subjectCount
                && pendingSubjectCountIsOverflowing == analysis.isOverflowing
            if matchesPendingCandidate {
                pendingSubjectCountStreak += 1
            } else {
                pendingSubjectCount = analysis.subjectCount
                pendingSubjectCountIsOverflowing = analysis.isOverflowing
                pendingSubjectCountStreak = 1
            }

            // Kararlılık eşiği: gürültülü tespitte 1↔2 gibi anlık çırpınmayı önlemek için
            // yeni sayı en az 2 ardışık analizde aynı olmalı. Koç yeni açıldığındaki ilk
            // anons bu eşikten muaftır, kör kullanıcı ilk durumu gecikmeden duymalı.
            guard isFirstEverAnnouncement || pendingSubjectCountStreak >= 2 else {
                // Eşik henüz dolmadı: sayı değişikliği doğrulanana kadar sessiz kal
                // (ekrandaki metin zaten güncellendi, yalnız henüz seslendirilmiyor).
                return
            }

            let countAnnouncement = frameCoachingEngine.subjectCountAnnouncement(for: analysis)
            let composite = "\(countAnnouncement). \(guidance.sentenceCased)"
            lastAnnouncedSubjectCount = analysis.subjectCount
            lastAnnouncedSubjectCountWasOverflow = analysis.isOverflowing
            pendingSubjectCount = nil
            pendingSubjectCountStreak = 0
            speechCuePlayer.speakIfNeeded(
                composite,
                isEnabled: allowsAudibleFrameCoachFeedback,
                key: guidance.sentenceCased,
                settings: frameCoachPreferences
            )
            return
        } else {
            pendingSubjectCount = nil
            pendingSubjectCountStreak = 0
        }

        // İyi konumdayken periyodik sesli onay: kör kullanıcı hâlâ doğru yerde olduğunu bilmeli.
        // "Kadraj uygun" için repeatInterval'ı kısalt (3s), yönlendirme için varsayılanı kullan.
        if isGood {
            var confirmPreferences = frameCoachPreferences
            confirmPreferences.repeatInterval = .short
            speechCuePlayer.speakIfNeeded(
                guidance.sentenceCased,
                isEnabled: allowsAudibleFrameCoachFeedback,
                key: guidance.sentenceCased,
                settings: confirmPreferences
            )
        } else {
            speechCuePlayer.speakIfNeeded(
                guidance.sentenceCased,
                isEnabled: allowsAudibleFrameCoachFeedback,
                key: guidance.sentenceCased,
                settings: frameCoachPreferences
            )
        }
    }

    private var allowsAudibleFrameCoachFeedback: Bool {
        !isRecording && !isPreparingRecording
    }

    func startRecording(afterCommandSoundDelay commandSoundDelay: TimeInterval = 0) {
        Task {
            if commandSoundDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(commandSoundDelay * 1_000_000_000))
            }
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

        let commandSoundDelay = playCommandReceivedSoundIfEnabled()

        if recordingCountdown == .none {
            startRecording(afterCommandSoundDelay: commandSoundDelay)
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
        setScreenCameraOverlayEnabled(!isScreenCameraOverlayEnabled)
    }

    func setScreenCameraOverlayEnabled(_ isEnabled: Bool) {
        guard canChangeRecordingSettings else { return }
        guard isScreenCameraOverlayEnabled != isEnabled else { return }
        isScreenCameraOverlayEnabled = isEnabled
        refreshDeviceState()
    }

    private var canChangeRecordingSettings: Bool {
        !isRecording && !isPreparingRecording && !isCountingDown
    }

    private func startRecordingAsync() async {
        guard ensureRecordingAccess() else { return }
        guard ensureSelectedRecordingCanStart() else { return }
        guard hasEnoughDiskSpaceToStartRecording() else { return }
        guard beginRecordingPreparation() else { return }
        cancelFrameCoachPreviewPreparation()

        do {
            let fileNamer = try resolvedActiveFileNamer()
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
            recorder.setPreviewFramesEnabled(isFrameCoachEnabled || isAutoReframeEnabled)
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

            markRecordingStarted(
                statusText: String(localized: "Kayıt yapılıyor"),
                sleepReason: "Video kaydı devam ediyor"
            )

            // The capture must already be accepting microphone samples before its
            // audible start cue. Previously this cue was played *before* starting
            // the camera pipeline, inviting the user to speak while the first
            // seconds of the recording were still unavailable.
            if isSystemAudioEnabled {
                systemAudioRecorder.prefetchShareableContent()
                do {
                    try await systemAudioRecorder.startRecording(to: systemAudioURL) { [weak self] result in
                        Task { @MainActor in
                            self?.handleCameraSystemAudioRecordingCompletion(result)
                        }
                    }
                    pendingCameraSystemAudioCaptureURL = systemAudioURL
                } catch {
                    // The camera movie is already recording. Treat a late system-audio
                    // setup failure as an optional-track warning rather than abandoning
                    // a valid camera recording after the user has started speaking.
                    pendingCameraSystemAudioCaptureResult = .success(nil)
                    pendingCameraSystemAudioWarning = error.localizedDescription
                }
            }
            await playStartSoundBeforeCapture()
        } catch {
            report(error)
        }
    }

    func stopRecording() {
        // Reject a second stopRecording() call while one is already in flight (double
        // keyboard shortcut press, a race between the max-duration timer and a manual
        // stop, etc.) so component teardown is never repeated against components that
        // are already stopping. This intentionally does not require the lifecycle to
        // have reached `.recording` first — startup does real async work before that,
        // and a stop requested during `.preparing` must still tear down whatever has
        // already started.
        guard !recordingLifecycle.isStopping else { return }
        lastCompletedRecordingDuration = currentRecordingDuration
        if appAccessState.accessKind == .freeTier {
            appAccessManager.consumeFreeTierUsage(seconds: currentRecordingDuration ?? 0)
            Task { await refreshAppAccess() }
        }
        elapsedTimeAnnouncer.stop()
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
        markRecordingStopping()
        pauseResumeTask?.cancel()
        pauseResumeTask = nil
        setRecordingFinishingStatus(String(localized: "Kayıt durdu. Dosya hazırlanıyor"), key: "recording-file-preparing")
        sleepPreventer.allow()
        recordingDurationTask?.cancel()
        recordingDurationTask = nil
    }

    private func startElapsedAnnouncer() {
        guard isElapsedTimeAnnouncementEnabled else { return }
        elapsedTimeAnnouncer.start(
            intervalSeconds: elapsedTimeAnnouncementInterval.rawValue,
            elapsedProvider: { [weak self] in self?.currentRecordingDuration },
            onTick: { [weak self] elapsed in self?.handleElapsedTimeAnnouncementTick(elapsed) }
        )
    }

    private func handleElapsedTimeAnnouncementTick(_ elapsed: TimeInterval) {
        switch elapsedTimeAnnouncementMode {
        case .voiceOver:
            let minutes = Int(elapsed) / 60
            let seconds = Int(elapsed) % 60
            let text = minutes > 0
                ? String(localized: "Kayıt süresi: \(minutes) dakika \(seconds) saniye")
                : String(localized: "Kayıt süresi: \(seconds) saniye")
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    NSAccessibility.NotificationUserInfoKey.announcement: text,
                    NSAccessibility.NotificationUserInfoKey.priority:
                        NSAccessibilityPriorityLevel.medium.rawValue
                ]
            )
        case .soundEffect:
            soundEffectPlayer.playElapsedTimeReminder()
        }
    }

    private func startMaxDurationTimer() {
        let configuredLimit: TimeInterval? = maxRecordingDuration == .custom
            ? TimeInterval(max(1, customMaxRecordingDurationSeconds))
            : maxRecordingDuration.seconds
        let quotaLimit: TimeInterval? = appAccessState.accessKind == .freeTier
            ? TimeInterval(appAccessState.freeTierSecondsRemaining)
            : nil
        let limit: TimeInterval?
        switch (configuredLimit, quotaLimit) {
        case let (configured?, quota?):
            limit = min(configured, quota)
        case let (configured?, nil):
            limit = configured
        case let (nil, quota?):
            limit = quota
        case (nil, nil):
            limit = nil
        }
        guard let limit else { return }

        let leadTime = TimeInterval(recordingEndWarningLeadTime.rawValue)

        recordingDurationTask = Task { [weak self] in
            do {
                if leadTime > 0, limit > leadTime {
                    try await Task.sleep(for: .seconds(limit - leadTime))
                    var remaining = Int(leadTime)
                    while remaining > 0 {
                        await MainActor.run { [weak self] in
                            guard let self, self.isRecording else { return }
                            self.soundEffectPlayer.playCountdownTick(remaining: remaining, total: Int(leadTime))
                            self.speechCuePlayer.speakIfNeeded(
                                "\(remaining)",
                                isEnabled: true,
                                key: "max-duration-warning-\(remaining)"
                            )
                        }
                        try await Task.sleep(for: .seconds(1))
                        remaining -= 1
                    }
                } else {
                    try await Task.sleep(for: .seconds(limit))
                }
                await MainActor.run { [weak self] in
                    guard let self, self.isRecording else { return }
                    let message = self.appAccessState.accessKind == .freeTier
                        ? String(localized: "Bu ayki ücretsiz kayıt süreniz doldu, kayıt durduruluyor")
                        : String(localized: "Maksimum kayıt süresine ulaşıldı, kayıt durduruluyor")
                    self.speechCuePlayer.speakIfNeeded(message, isEnabled: true, key: "max-duration-stop")
                    self.stopRecording()
                }
            } catch {
                // Cancelled when stopRecording() is called manually — normal
            }
        }
    }

    private func startRecordingSafetyMonitor() {
        recordingSafetyTask?.cancel()
        recordingSafetyTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.checkRemainingDiskSpaceWhileRecording() }
            }
        }
    }

    private func hasEnoughDiskSpaceToStartRecording() -> Bool {
        guard let bytes = RecordingDiskSpace.availableBytes(at: recordingOutputDirectoryURL) else { return true }
        guard bytes >= RecordingDiskSpace.minimumStartBytes else {
            report(RecordingSafetyError.insufficientDiskSpace)
            return false
        }
        return true
    }

    private func checkRemainingDiskSpaceWhileRecording() {
        guard isRecording, let bytes = RecordingDiskSpace.availableBytes(at: recordingOutputDirectoryURL) else { return }
        if bytes < RecordingDiskSpace.criticalBytes {
            let message = String(localized: "Disk alanı kritik düzeyde. Kayıt güvenle durduruluyor.")
            statusText = message
            speechCuePlayer.reset()
            speechCuePlayer.speakIfNeeded(message, isEnabled: true, key: "critical-disk-space")
            stopRecording()
        } else if bytes < RecordingDiskSpace.warningBytes {
            speechCuePlayer.speakIfNeeded(
                String(localized: "Disk alanı azalıyor."),
                isEnabled: true,
                key: "low-disk-space"
            )
        }
    }

    private func playStartSoundBeforeCapture() async {
        guard isRecordingStartSoundEnabled else { return }
        await waitForCommandSoundToFinishIfNeeded()
        let duration = soundEffectPlayer.playStart()
        guard duration > 0 else { return }

        do {
            try await Task.sleep(nanoseconds: UInt64(min(duration, 1.5) * 1_000_000_000))
        } catch {
            // If start is cancelled while the cue is playing, continue cleanup through the caller.
        }
    }

    @discardableResult
    private func playCommandReceivedSoundIfEnabled() -> TimeInterval {
        guard isRecordingCommandSoundEnabled else { return 0 }
        let duration = soundEffectPlayer.playCommandReceived()
        if duration > 0 {
            commandSoundEndUptime = ProcessInfo.processInfo.systemUptime + duration
        }
        return duration
    }

    private func waitForCommandSoundToFinishIfNeeded() async {
        guard let commandSoundEndUptime else { return }
        let remaining = commandSoundEndUptime - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { return }

        do {
            try await Task.sleep(nanoseconds: UInt64(min(remaining, 3.5) * 1_000_000_000))
        } catch {
            // If start is cancelled while the command cue is playing, continue cleanup through the caller.
        }
    }

    @discardableResult
    private func playPauseResumeSoundIfEnabled() -> TimeInterval {
        guard isRecordingPauseResumeSoundEnabled else { return 0 }
        return soundEffectPlayer.playPauseResume()
    }

    private func playStopSoundIfEnabled() {
        guard isRecordingStopSoundEnabled else { return }
        _ = soundEffectPlayer.playStop()
    }

    private func setRecordingFinishingStatus(_ text: String, key: String) {
        statusText = text
        isFinalizingRecording = true
    }

    private func markRecordingFileReady() {
        isFinalizingRecording = false
        playStopSoundIfEnabled()
        announceCompletedRecordingForVoiceOver()
    }

    private func announceCompletedRecordingForVoiceOver() {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }

        let filename = completedRecording?.url.lastPathComponent ?? lastSavedURL?.lastPathComponent
        let message: String
        if let filename, !filename.isEmpty {
            message = String(localized: "Kayıt tamamlandı, dosya hazır: \(filename)")
        } else {
            message = String(localized: "Kayıt tamamlandı, dosya hazır")
        }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: message,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    private func beginRecordingPreparation() -> Bool {
        guard recordingLifecycle.beginPreparing() else { return false }
        isPreparingRecording = true
        // A previous recording's export may still be finalizing (stale generation) —
        // starting a new one makes that panel meaningless, so hide it now.
        isFinalizingRecording = false
        // Phase 5: every start attempt gets a new generation, so a finalize/export task
        // from a previous recording — still running when this one begins, since finalize
        // is driven by async callbacks decoupled from the view model's live state — can
        // recognize it is stale and must not overwrite this recording's UI state.
        recordingGeneration += 1
        runtimeDebugLog("=== YENİ KAYIT OTURUMU BAŞLADI (generation \(recordingGeneration)) ===")
        return true
    }

    private func markRecordingStarted(statusText: String, sleepReason: String) {
        _ = recordingLifecycle.markStarted()
        isRecording = true
        beginPauseTracking()
        isPreparingRecording = false
        lastSavedURL = nil
        completedRecording = nil
        errorText = nil
        self.statusText = statusText
        speechCuePlayer.isOutputSuppressed = true
        spatialCuePlayer.reset()
        sleepPreventer.prevent(reason: sleepReason)
        startMaxDurationTimer()
        startElapsedAnnouncer()
        startRecordingSafetyMonitor()
    }

    private func markRecordingStopping() {
        _ = recordingLifecycle.beginStopping()
        isRecording = false
        isPaused = false
        isPausedForMicrophoneReconnect = false
        updatePreviewAnalysisState()
        scheduleStopWatchdog()
    }

    private func finishRecordingLifecycle() {
        recordingLifecycle.finish()
        isRecording = false
        isPaused = false
        isPausedForMicrophoneReconnect = false
        isPreparingRecording = false
        speechCuePlayer.isOutputSuppressed = false
        recordingSafetyTask?.cancel()
        recordingSafetyTask = nil
        stopWatchdogTask?.cancel()
        stopWatchdogTask = nil
        sleepPreventer.allow()
        updatePreviewAnalysisState()
    }

    /// Bounds how long a recording can stay stuck in `.stopping`: if some component's
    /// completion callback never arrives (a delegate that silently drops, a race in the
    /// underlying framework), the corresponding pending result is forced and the finalize
    /// path is re-entered, so the lifecycle always returns to `.idle` and the next
    /// recording can start.
    private func scheduleStopWatchdog() {
        stopWatchdogTask?.cancel()
        stopWatchdogTask = Task { [weak self, stopWatchdogTimeout] in
            try? await Task.sleep(for: stopWatchdogTimeout)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.forceStuckRecordingFinalizeIfNeeded() }
        }
    }

    private func forceStuckRecordingFinalizeIfNeeded() {
        guard recordingLifecycle.isStopping else { return }

        switch selectedRecordingSource {
        case .audio:
            if pendingAudioMicrophoneCaptureResult == nil {
                runtimeDebugLog("Stop watchdog: forcing pendingAudioMicrophoneCaptureResult after timeout")
                pendingAudioMicrophoneCaptureResult = .success(nil)
            }
            if pendingAudioSystemAudioCaptureResult == nil {
                runtimeDebugLog("Stop watchdog: forcing pendingAudioSystemAudioCaptureResult after timeout")
                pendingAudioSystemAudioCaptureResult = .success(nil)
            }
            Task { await maybeFinalizeAudioRecordingExport() }
        case .camera:
            if pendingCameraCaptureResult == nil {
                runtimeDebugLog("Stop watchdog: forcing pendingCameraCaptureResult after timeout")
                pendingCameraCaptureResult = .failure(RecordingSafetyError.stopWatchdogTimedOut)
            }
            if pendingCameraSystemAudioCaptureResult == nil {
                runtimeDebugLog("Stop watchdog: forcing pendingCameraSystemAudioCaptureResult after timeout")
                pendingCameraSystemAudioCaptureResult = .success(nil)
            }
            completeCameraRecordingIfReady()
        case .screen, .window:
            if pendingScreenCaptureResult == nil {
                runtimeDebugLog("Stop watchdog: forcing pendingScreenCaptureResult after timeout")
                pendingScreenCaptureResult = .failure(RecordingSafetyError.stopWatchdogTimedOut)
            }
            if pendingOverlayCaptureResult == nil {
                runtimeDebugLog("Stop watchdog: forcing pendingOverlayCaptureResult after timeout")
                pendingOverlayCaptureResult = .success(nil)
            }
            if pendingScreenMicrophoneCaptureResult == nil {
                runtimeDebugLog("Stop watchdog: forcing pendingScreenMicrophoneCaptureResult after timeout")
                pendingScreenMicrophoneCaptureResult = .success(nil)
            }
            if pendingScreenSystemAudioCaptureResult == nil {
                runtimeDebugLog("Stop watchdog: forcing pendingScreenSystemAudioCaptureResult after timeout")
                pendingScreenSystemAudioCaptureResult = .success(nil)
            }
            maybeFinalizeScreenRecordingExport()
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

        if isSystemAudioEnabled {
            systemAudioRecorder.prefetchShareableContent()
        }
        await playStartSoundBeforeCapture()

        do {
            if !selectedMicrophoneID.isEmpty {
                try await microphoneAudioRecorder.startRecording(deviceID: selectedMicrophoneID, to: microphoneCaptureURL, audioChannelMode: audioChannelMode) { [weak self] result in
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

        markRecordingStarted(
            statusText: String(localized: "Ses kaydı yapılıyor"),
            sleepReason: "Ses kaydı devam ediyor"
        )
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

        // Normalde refreshDeviceState() bu işi ekran modu seçilir seçilmez başlatır.
        // Bu çağrı yalnızca uygulama kaynaktan henüz ısınmadan kayıt başlatılırsa
        // güvenlik ağıdır; sağlayıcı aynı işi ikinci kez başlatmaz.
        screenRecordingProvider.prefetchShareableContent()
        if isSystemAudioEnabled {
            systemAudioRecorder.prefetchShareableContent()
        }

        do {
            await playStartSoundBeforeCapture()

            runtimeDebugLog("Screen recording start: start cue finished; preparing optional tracks")

            if isCursorHighlightEnabled, let targetFrame = currentScreenCaptureTargetFrame() {
                cursorHighlightRecorder.startTracking(targetFrame: targetFrame)
            }
            if isKeyboardShortcutOverlayEnabled {
                keyboardShortcutRecorder.startTracking()
            }

            if isScreenCameraOverlayEnabled {
                cancelScreenOverlayPreview(stopSession: false)
                try await cameraOverlayRecorder.configure(cameraDeviceID: selectedCameraID, mode: selectedMode)
                try await cameraOverlayRecorder.startRecording(to: overlayCaptureURL) { [weak self] result in
                    Task { @MainActor in
                        self?.handleScreenOverlayCaptureCompletion(result)
                    }
                }
                pendingScreenOverlayCaptureURL = overlayCaptureURL
                runtimeDebugLog("Screen recording start: camera overlay started")
            }

            if !selectedMicrophoneID.isEmpty {
                try await microphoneAudioRecorder.startRecording(deviceID: selectedMicrophoneID, to: microphoneCaptureURL, audioChannelMode: audioChannelMode) { [weak self] result in
                    Task { @MainActor in
                        self?.handleScreenMicrophoneCaptureCompletion(result)
                    }
                }
                pendingScreenMicrophoneCaptureURL = microphoneCaptureURL
                runtimeDebugLog("Screen recording start: microphone track started")
            }

            if isSystemAudioEnabled {
                try await systemAudioRecorder.startRecording(to: systemAudioCaptureURL) { [weak self] result in
                    Task { @MainActor in
                        self?.handleScreenSystemAudioCaptureCompletion(result)
                    }
                }
                pendingScreenSystemAudioCaptureURL = systemAudioCaptureURL
                runtimeDebugLog("Screen recording start: system-audio track started")
            }

            runtimeDebugLog("Screen recording start: starting ScreenCaptureKit stream")
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
            runtimeDebugLog("Screen recording start: ScreenCaptureKit startCapture returned")
        } catch {
            cleanupFailedScreenRecordingStart()
            throw error
        }

        markRecordingStarted(
            statusText: String(localized: "Kayıt yapılıyor"),
            sleepReason: "Ekran kaydı devam ediyor"
        )
    }

    private func cleanupFailedScreenRecordingStart() {
        if isScreenCameraOverlayEnabled || pendingScreenOverlayCaptureURL != nil {
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
    }

    private func handleCameraRecordingCompletion(_ result: Result<URL, Error>, finalURL: URL) {
        pendingCameraRecordingFinalURL = finalURL
        pendingCameraCaptureResult = result
        completeCameraRecordingIfReady()
    }

    private func handleCameraSystemAudioRecordingCompletion(_ result: Result<URL, Error>) {
        let componentResult = RecordingComponentResult.systemAudio(from: result)
        pendingCameraSystemAudioCaptureResult = componentResult.value
        pendingCameraSystemAudioWarning = componentResult.warning
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
        // The camera is this mode's primary component (offset 0); the system audio track
        // started independently (usually slightly before the camera) and needs its own
        // actual offset from session zero (Phase 3.2).
        let systemAudioOffsetSeconds = secondaryOffsetSeconds(for: systemAudioRecorder.firstSamplePresentationTime)
        logSessionTimingSummary(pauseTimeline: recordingPauseTimeline)
        resetPendingCameraRecordingState()
        handleRecordingCompletion(
            captureResult,
            finalURL: finalURL,
            systemAudioURL: systemAudioURL,
            systemAudioOffsetSeconds: systemAudioOffsetSeconds,
            warningText: warning
        )
    }

    private func handleRecordingCompletion(
        _ result: Result<URL, Error>,
        finalURL: URL,
        systemAudioURL: URL? = nil,
        systemAudioOffsetSeconds: TimeInterval = 0,
        warningText: String? = nil
    ) {
        let pauseTimeline = recordingPauseTimeline
        // Captured before finishRecordingLifecycle() advances state, so this export's
        // eventual completion can tell whether a newer recording has since started
        // (Phase 5) — finalize is driven by this async Task, decoupled from whatever the
        // view model's live properties say by the time it completes.
        let generation = recordingGeneration
        finishRecordingLifecycle()

        switch result {
        case .success(let captureURL):
            setRecordingFinishingStatus(String(localized: "Video dosyası hazırlanıyor"), key: "camera-video-file-preparing")
            Task {
                do {
                    let exportResult = try await exportMP4(
                        from: captureURL,
                        to: finalURL,
                        timeline: isAutoReframeEnabled ? autoReframeTimeline.shifted(by: pauseTimeline) : AutoReframeTimeline(),
                        cameraMode: selectedMode,
                        systemAudioURL: systemAudioURL,
                        pauseTimeline: pauseTimeline,
                        cameraSystemAudioOffsetSeconds: systemAudioOffsetSeconds
                    )
                    try? FileManager.default.removeItem(at: captureURL)
                    if let systemAudioURL {
                        try? FileManager.default.removeItem(at: systemAudioURL)
                    }
                    await MainActor.run {
                        guard isCurrentGeneration(generation) else {
                            runtimeDebugLog("Camera export finished for a stale generation; discarding its result")
                            return
                        }
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
                        markRecordingFileReady()
                    }
                } catch {
                    await MainActor.run {
                        guard isCurrentGeneration(generation) else {
                            runtimeDebugLog("Camera export failed for a stale generation; not reporting: \(error.localizedDescription)")
                            return
                        }
                        report(error)
                    }
                }
            }
        case .failure(let error):
            guard isCurrentGeneration(generation) else {
                runtimeDebugLog("Camera capture failed for a stale generation; not reporting: \(error.localizedDescription)")
                return
            }
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
        let componentResult = RecordingComponentResult.microphone(from: result)
        pendingScreenMicrophoneCaptureResult = componentResult.value
        pendingScreenMicrophoneWarning = componentResult.warning
        maybeFinalizeScreenRecordingExport()
    }

    private func handleScreenSystemAudioCaptureCompletion(_ result: Result<URL, Error>) {
        let componentResult = RecordingComponentResult.systemAudio(from: result)
        pendingScreenSystemAudioCaptureResult = componentResult.value
        pendingScreenSystemAudioWarning = componentResult.warning
        maybeFinalizeScreenRecordingExport()
    }

    private func handleAudioMicrophoneCaptureCompletion(_ result: Result<URL, Error>) {
        let componentResult = RecordingComponentResult.microphone(from: result)
        pendingAudioMicrophoneCaptureResult = componentResult.value
        pendingAudioMicrophoneWarning = componentResult.warning
        Task { [weak self] in
            await self?.maybeFinalizeAudioRecordingExport()
        }
    }

    private func handleAudioSystemAudioCaptureCompletion(_ result: Result<URL, Error>) {
        let componentResult = RecordingComponentResult.systemAudio(from: result)
        pendingAudioSystemAudioCaptureResult = componentResult.value
        pendingAudioSystemAudioWarning = componentResult.warning
        Task { [weak self] in
            await self?.maybeFinalizeAudioRecordingExport()
        }
    }

    @MainActor
    private func maybeFinalizeAudioRecordingExport() async {
        didEnterAudioRecordingFinalize = true
        guard let finalURL = pendingAudioRecordingFinalURL,
              let microphoneResult = pendingAudioMicrophoneCaptureResult,
              let systemAudioResult = pendingAudioSystemAudioCaptureResult else {
            return
        }

        let microphoneWarning = pendingAudioMicrophoneWarning
        let systemAudioWarning = pendingAudioSystemAudioWarning
        let pauseTimeline = recordingPauseTimeline
        // The microphone is the primary component whenever one is selected (see
        // primaryComponentFirstSampleTime()), so its own file is already at offset 0;
        // only the other component's actual start needs aligning against it.
        let isMicrophonePrimary = !selectedMicrophoneID.isEmpty
        let microphoneOffsetSeconds: TimeInterval = isMicrophonePrimary ? 0 : secondaryOffsetSeconds(for: microphoneAudioRecorder.firstSamplePresentationTime)
        let systemAudioOffsetSeconds: TimeInterval = isMicrophonePrimary ? secondaryOffsetSeconds(for: systemAudioRecorder.firstSamplePresentationTime) : 0
        logSessionTimingSummary(pauseTimeline: pauseTimeline)
        // Captured before finishRecordingLifecycle(): this function stays suspended across
        // the `await` below, during which a new recording can start and bump the
        // generation (Phase 5) — every write of UI state after that await must check it's
        // still describing the recording the user is currently looking at.
        let generation = recordingGeneration
        resetPendingAudioRecordingState()
        finishRecordingLifecycle()

        switch (microphoneResult, systemAudioResult) {
        case (.failure(let error), _), (_, .failure(let error)):
            guard isCurrentGeneration(generation) else {
                runtimeDebugLog("Audio capture failed for a stale generation; not reporting: \(error.localizedDescription)")
                return
            }
            report(error)
        case (.success(let microphoneURL), .success(let systemAudioURL)):
            setRecordingFinishingStatus(String(localized: "Ses dosyası hazırlanıyor"), key: "audio-file-preparing")
            do {
                let exportURL = try await audioRecordingExporter.export(
                    microphoneURL: microphoneURL,
                    systemAudioURL: systemAudioURL,
                    to: finalURL,
                    microphoneVolume: microphoneVolume,
                    systemAudioVolume: systemAudioVolume,
                    pauseTimeline: pauseTimeline,
                    microphoneOffsetSeconds: microphoneOffsetSeconds,
                    systemAudioOffsetSeconds: systemAudioOffsetSeconds
                )
                if let microphoneURL {
                    try? FileManager.default.removeItem(at: microphoneURL)
                }
                if let systemAudioURL {
                    try? FileManager.default.removeItem(at: systemAudioURL)
                }
                didCompleteAudioRecordingExport = true
                guard isCurrentGeneration(generation) else {
                    runtimeDebugLog("Audio export finished for a stale generation; discarding its result")
                    return
                }
                let warnings = [microphoneWarning, systemAudioWarning].compactMap { $0 }
                lastSavedURL = exportURL
                completedRecording = makeCompletedRecordingSummary(for: exportURL, warnings: warnings)
                if warnings.isEmpty {
                    statusText = String(localized: "Kaydedildi: \(exportURL.path)")
                } else {
                    statusText = String(localized: "Kaydedildi: \(exportURL.path) (\(warnings.joined(separator: ", ")))")
                }
                speechCuePlayer.reset()
                markRecordingFileReady()
            } catch {
                guard isCurrentGeneration(generation) else {
                    runtimeDebugLog("Audio export failed for a stale generation; not reporting: \(error.localizedDescription)")
                    return
                }
                report(error)
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
        // The screen/window capture is always this mode's primary component (offset 0);
        // the overlay, microphone and system audio each started independently and need
        // their own actual offset from session zero (Phase 3).
        let overlayOffsetSeconds = secondaryOffsetSeconds(for: cameraOverlayRecorder.firstSamplePresentationTime)
        let screenMicrophoneOffsetSeconds = secondaryOffsetSeconds(for: microphoneAudioRecorder.firstSamplePresentationTime)
        let screenSystemAudioOffsetSeconds = secondaryOffsetSeconds(for: systemAudioRecorder.firstSamplePresentationTime)
        logSessionTimingSummary(pauseTimeline: pauseTimeline)
        let generation = recordingGeneration
        resetPendingScreenRecordingState()
        cameraOverlayRecorder.stopSession()
        finishRecordingLifecycle()

        switch (screenResult, overlayResult, microphoneResult, systemAudioResult) {
        case (.failure(let error), _, _, _):
            guard isCurrentGeneration(generation) else {
                runtimeDebugLog("Screen capture failed for a stale generation; not reporting: \(error.localizedDescription)")
                return
            }
            report(error)
        case (.success(let captureURL), let overlayResult, let microphoneResult, let systemAudioResult):
            let overlayURL = (try? overlayResult.get()) ?? nil
            let microphoneURL = (try? microphoneResult.get()) ?? nil
            let systemAudioURL = (try? systemAudioResult.get()) ?? nil
            var warnings = [microphoneWarning, systemAudioWarning].compactMap { $0 }
            if case .failure(let error) = overlayResult { warnings.append(String(localized: "Kamera katmanı kaydedilemedi: \(error.localizedDescription)")) }
            if case .failure(let error) = microphoneResult { warnings.append(String(localized: "Mikrofon kaydedilemedi: \(error.localizedDescription)")) }
            if case .failure(let error) = systemAudioResult { warnings.append(String(localized: "Sistem sesi kaydedilemedi: \(error.localizedDescription)")) }
            let isPartialRecovery = !warnings.isEmpty
            setRecordingFinishingStatus(
                isPartialRecovery
                    ? String(localized: "Kısmi ekran kaydı dosyası hazırlanıyor")
                    : String(localized: "Ekran kaydı dosyası hazırlanıyor"),
                key: isPartialRecovery ? "screen-partial-video-file-preparing" : "screen-video-file-preparing"
            )
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
                        pauseTimeline: pauseTimeline,
                        overlayOffsetSeconds: overlayOffsetSeconds,
                        screenMicrophoneOffsetSeconds: screenMicrophoneOffsetSeconds,
                        screenSystemAudioOffsetSeconds: screenSystemAudioOffsetSeconds
                    )
                    try? FileManager.default.removeItem(at: captureURL)
                    if let overlayURL { try? FileManager.default.removeItem(at: overlayURL) }
                    if let microphoneURL { try? FileManager.default.removeItem(at: microphoneURL) }
                    if let systemAudioURL { try? FileManager.default.removeItem(at: systemAudioURL) }
                    await MainActor.run {
                        guard isCurrentGeneration(generation) else {
                            runtimeDebugLog("Screen export finished for a stale generation; discarding its result")
                            return
                        }
                        lastSavedURL = exportResult.url
                        completedRecording = makeCompletedRecordingSummary(for: exportResult.url, warnings: warnings)
                        statusText = isPartialRecovery
                            ? String(localized: "Kısmi kayıt kaydedildi: \(exportResult.url.path)")
                            : String(localized: "Kaydedildi: \(exportResult.url.path)")
                        markRecordingFileReady()
                    }
                } catch {
                    await MainActor.run {
                        guard isCurrentGeneration(generation) else {
                            runtimeDebugLog("Screen export failed for a stale generation; not reporting: \(error.localizedDescription)")
                            return
                        }
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
        pauseTimeline: RecordingPauseTimeline = .empty,
        overlayOffsetSeconds: TimeInterval = 0,
        screenMicrophoneOffsetSeconds: TimeInterval = 0,
        screenSystemAudioOffsetSeconds: TimeInterval = 0,
        cameraSystemAudioOffsetSeconds: TimeInterval = 0
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
                pauseTimeline: pauseTimeline,
                overlayOffsetSeconds: overlayOffsetSeconds,
                microphoneOffsetSeconds: screenMicrophoneOffsetSeconds,
                systemAudioOffsetSeconds: screenSystemAudioOffsetSeconds
            )

            let overlayPresetName = await Self.bestAvailableExportPreset(for: overlayComposition.composition)
            guard let exportSession = AVAssetExportSession(asset: overlayComposition.composition, presetName: overlayPresetName) else {
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
            pauseTimeline: pauseTimeline,
            systemAudioOffsetSeconds: cameraSystemAudioOffsetSeconds
        )

        let cameraPresetName = await Self.bestAvailableExportPreset(for: exportPackage.asset)
        guard let exportSession = AVAssetExportSession(asset: exportPackage.asset, presetName: cameraPresetName) else {
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

    private static func bestAvailableExportPreset(for asset: AVAsset) async -> String {
        let candidates = [AVAssetExportPresetHEVCHighestQuality, AVAssetExportPresetHighestQuality]
        for preset in candidates {
            if await AVAssetExportSession.compatibility(
                ofExportPreset: preset,
                with: asset,
                outputFileType: .mp4
            ) {
                return preset
            }
        }

        return AVAssetExportPresetHighestQuality
    }

    private func makeCameraExportAsset(
        sourceAsset: AVAsset,
        systemAudioURL: URL?,
        pauseTimeline: RecordingPauseTimeline,
        systemAudioOffsetSeconds: TimeInterval = 0
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
            let systemSegments = pauseTimeline.segments(for: insertDuration, offsetSeconds: systemAudioOffsetSeconds)
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
        case .localTrial:
            if appAccessState.localTrialDaysRemaining == 1 {
                return String(localized: "Sınırsız Deneme: son 1 gün")
            }
            return String(localized: "Sınırsız Deneme: \(appAccessState.localTrialDaysRemaining) gün kaldı")
        case .freeTier:
            return String(localized: "Ücretsiz Kademe")
        case .freeTierExhausted:
            return String(localized: "Bu Ayki Süre Doldu")
        case .yearly:
            return String(localized: "Pro: yıllık plan aktif")
        case .lifetime:
            return String(localized: "Pro: ömür boyu erişim aktif")
        }
    }

    var accessStatusDetail: String {
        switch appAccessState.accessKind {
        case .localTrial:
            return String(localized: "Şimdilik tüm kayıt özellikleri açık, hesap gerekmez. Deneme bitince her ay 7 dakika ücretsiz kaydın olacak.")
        case .freeTier:
            let minutes = appAccessState.freeTierSecondsRemaining / 60
            let seconds = appAccessState.freeTierSecondsRemaining % 60
            return String(localized: "Bu ay \(minutes) dk \(seconds) sn kaldı. Kota her ayın başında yenilenir.")
        case .freeTierExhausted:
            return String(localized: "Yeni kota bir sonraki ay yenilenecek. Sınırsız için Pro'ya geçebilirsin.")
        case .yearly:
            return String(localized: "Yıllık plan ile tüm Pro kayıt özellikleri açık.")
        case .lifetime:
            return String(localized: "Tek seferlik satın alımla tüm Pro kayıt özellikleri açık.")
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
        persistOutputDirectoryState(for: selectedURL)
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
            let fallbackDirectory = defaultRecordingDirectory()
            let fallbackFileNamer = RecordingFileNamer(outputDirectory: fallbackDirectory)
            try fallbackFileNamer.ensureOutputDirectoryExists()

            if recordingOutputDirectoryURL != fallbackDirectory {
                recordingOutputDirectoryURL = fallbackDirectory
                persistOutputDirectoryState(for: fallbackDirectory)
                statusText = String(localized: "Kayıt klasörü kullanıcıya görünür varsayılan klasöre güncellendi.")
            }

            return fallbackFileNamer
        }
    }

    private static func isInternalSandboxFallbackOutputDirectory(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        guard let containersIndex = components.firstIndex(of: "Containers"),
              components.indices.contains(containersIndex + 1),
              components[containersIndex + 1] == "com.recepgur.VideoRecorder" else {
            return false
        }

        let suffix = Array(components.suffix(3))
        return suffix == ["Data", "Downloads", "FrameMate"]
    }

    private static func restoreStoredOutputDirectory(
        from store: RecordingOutputDirectoryStoring,
        defaultRecordingDirectory: URL
    ) -> RestoredOutputDirectoryState? {
        if let bookmarkData = store.outputDirectoryBookmarkData {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                let accessedSecurityScopedOutputDirectoryURL = url.startAccessingSecurityScopedResource() ? url : nil
                var resolvedBookmarkData = bookmarkData
                if isStale,
                   let refreshedBookmarkData = try? url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                   ) {
                    resolvedBookmarkData = refreshedBookmarkData
                }
                return RestoredOutputDirectoryState(
                    url: url,
                    bookmarkData: resolvedBookmarkData,
                    accessedSecurityScopedOutputDirectoryURL: accessedSecurityScopedOutputDirectoryURL
                )
            } catch {
                return nil
            }
        }

        guard let storedOutputPath = store.outputDirectoryPath else {
            return nil
        }

        let storedOutputURL = URL(fileURLWithPath: storedOutputPath, isDirectory: true)
        if Self.isInternalSandboxFallbackOutputDirectory(storedOutputURL) {
            return nil
        }

        if storedOutputURL.standardizedFileURL != defaultRecordingDirectory.standardizedFileURL {
            return nil
        }

        return RestoredOutputDirectoryState(
            url: storedOutputURL,
            bookmarkData: nil,
            accessedSecurityScopedOutputDirectoryURL: nil
        )
    }

    private func persistOutputDirectoryBookmarkIfNeeded(for url: URL) {
        if url.standardizedFileURL == defaultRecordingDirectory().standardizedFileURL {
            recordingOutputDirectoryStore.outputDirectoryBookmarkData = nil
            return
        }

        guard let bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            recordingOutputDirectoryStore.outputDirectoryBookmarkData = nil
            return
        }

        recordingOutputDirectoryStore.outputDirectoryBookmarkData = bookmarkData
    }

    private func persistOutputDirectoryState(for url: URL) {
        recordingOutputDirectoryStore.outputDirectoryPath = url.path
        updateSecurityScopedOutputDirectoryAccess(to: url)
        persistOutputDirectoryBookmarkIfNeeded(for: url)
    }

    private func updateSecurityScopedOutputDirectoryAccess(to url: URL) {
        stopAccessingSecurityScopedOutputDirectory()

        if url.startAccessingSecurityScopedResource() {
            accessedSecurityScopedOutputDirectoryURL = url
        }
    }

    private func stopAccessingSecurityScopedOutputDirectory() {
        accessedSecurityScopedOutputDirectoryURL?.stopAccessingSecurityScopedResource()
        accessedSecurityScopedOutputDirectoryURL = nil
    }

    private func findRecoverableTempFiles() {
        let directory = activeFileNamer.outputDirectory
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let tempPrefixes = ["tmp-", "camera-overlay-", "audio-microphone-", "audio-system-", "screen-microphone-", "screen-system-audio-", "system-audio-"]
        recoveredTemporaryRecordingURLs = items.filter { item in
            tempPrefixes.contains { item.lastPathComponent.hasPrefix($0) }
        }
    }

    private func report(_ error: Error) {
        runtimeDebugLog("HATA gösterildi (generation \(recordingGeneration)): \(error.localizedDescription)")
        refreshPermissionStatus()
        errorText = error.localizedDescription
        statusText = "Hata: \(error.localizedDescription)"
        isFinalizingRecording = false
        finishRecordingLifecycle()
        completedRecording = nil
        if error is CaptureRecorderError {
            isRecorderConfigured = false
        }
        // ContentView owns the VoiceOver error announcement. Use app voice only
        // when VoiceOver is off, otherwise the same error would be announced twice.
        speechCuePlayer.reset()
        speechCuePlayer.speakUsingAppVoiceWhenVoiceOverIsOff(
            String(localized: "Hata: \(error.localizedDescription)"),
            key: "recording-error"
        )
    }

    func revealRecoveredTemporaryRecordings() {
        guard let first = recoveredTemporaryRecordingURLs.first else { return }
        revealInFinder(first)
    }

    private func installRecordingSafetyObservers() {
        guard workspaceObserverTokens.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let sleepToken = workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSystemInterruption(String(localized: "Mac uykuya geçiyor. Kayıt güvenle durduruluyor."))
            }
        }
        let disconnectToken = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let device = notification.object as? AVCaptureDevice else { return }
            Task { @MainActor in self?.handleCaptureDeviceDisconnect(device) }
        }
        workspaceObserverTokens = [sleepToken, disconnectToken]
    }

    private func handleSystemInterruption(_ message: String) {
        guard isRecording || isPreparingRecording else { return }
        statusText = message
        speechCuePlayer.reset()
        speechCuePlayer.speakIfNeeded(message, isEnabled: true, key: "system-sleep-interruption")
        if isRecording { stopRecording() } else { finishRecordingLifecycle() }
    }

    private func handleCaptureDeviceDisconnect(_ device: AVCaptureDevice) {
        guard isRecording,
              device.uniqueID == selectedCameraID || device.uniqueID == selectedMicrophoneID else { return }

        // Mikrofon kaybı, kamera/ekran görüntüsünü etkilemez — kayıt bileşenleri arka
        // planda sessizce çalışmaya devam eder (bkz. MicrophoneAudioRecorder/CaptureRecorder:
        // ikisi de kendi ses örneklerini ayrı bir AVCaptureAudioDataOutput'tan alır, video
        // hattına bağımlı değildir). Bu yüzden çekimi tamamen bitirmek yerine mevcut
        // duraklat/kes mekanizmasını (aynı zaman aralığı export'ta kırpılır) devreye sokup
        // kullanıcıya mikrofonu yeniden takma şansı veriyoruz. Kamera koptuğunda ise asıl
        // görüntü kaynağı kaybolduğu için güvenli durdurma davranışı korunuyor.
        if device.hasMediaType(.audio), device.uniqueID == selectedMicrophoneID {
            pauseRecordingForMicrophoneReconnect()
            return
        }

        let message = String(localized: "Kamera bağlantısı kesildi. Kayıt güvenle durduruluyor.")
        runtimeDebugLog("HATA gösterildi (generation \(recordingGeneration)): \(message)")
        errorText = message
        statusText = message
        speechCuePlayer.reset()
        speechCuePlayer.speakIfNeeded(message, isEnabled: true, key: "capture-device-disconnected")
        stopRecording()
    }

    private func pauseRecordingForMicrophoneReconnect() {
        guard isRecording, !isPaused else { return }
        let message = String(localized: "Mikrofon bağlantısı kesildi. Kayıt duraklatıldı — mikrofonu yeniden takıp Devam Et'e basabilirsin.")
        runtimeDebugLog("Mikrofon koptu (generation \(recordingGeneration)): kayıt duraklatıldı, durdurulmadı.")
        beginCurrentPauseRange()
        isPaused = true
        isPausedForMicrophoneReconnect = true
        statusText = message
        sleepPreventer.allow()
        recordingDurationTask?.cancel()
        recordingDurationTask = nil
        speechCuePlayer.reset()
        speechCuePlayer.speakIfNeeded(message, isEnabled: true, key: "microphone-disconnected-paused")
    }

    deinit {
        for token in workspaceObserverTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
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

    func openSupportPage() {
        guard let url = URL(string: "https://recepgur07-bot.github.io/oneday-support/framemate-support") else {
            return
        }
        openURL(url)
    }

    func openPrivacyPolicyPage() {
        guard let url = URL(string: "https://recepgur07-bot.github.io/oneday-support/framemate-privacy") else {
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
                helperText: String(localized: "İzin vermek için: 1. Sistem Ayarları'nı aç. 2. Gizlilik ve Güvenlik bölümüne git. 3. Ekran Kaydı'nı seç. 4. FrameMate listede varsa aç. Listede yoksa artı düğmesine bas, Uygulamalar'dan FrameMate'i seç ve ekle. 5. FrameMate'i yeniden başlat. Aşağıdaki 'Ayarları Aç' veya 'Devam' düğmelerini kullanabilirsin."),
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
        guard !isRecording && !isPreparingRecording else { return }
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
        cameras.first(where: { $0.id == selectedCameraID })?.localizedName
            ?? cameras.first?.localizedName
            ?? String(localized: "seçilmedi")
    }

    private func selectedMicrophoneNameOrFallback(required: Bool) -> String {
        if selectedMicrophoneID.isEmpty {
            return required ? String(localized: "seçilmedi") : String(localized: "kapalı")
        }
        return microphones.first(where: { $0.id == selectedMicrophoneID })?.localizedName
            ?? String(localized: "seçilmedi")
    }

    private var selectedDisplayNameOrFallback: String {
        availableDisplays.first(where: { $0.id == selectedDisplayID })?.localizedName
            ?? String(localized: "seçilmedi")
    }

    private var selectedDisplaySummaryNameOrFallback: String {
        availableDisplays.first(where: { $0.id == selectedDisplayID })?.localizedSummaryName
            ?? String(localized: "seçilmedi")
    }

    private var selectedWindowNameOrFallback: String {
        availableWindows.first(where: { $0.id == selectedWindowID })?.name
            ?? String(localized: "seçilmedi")
    }

    private func makeStatusText() -> String {
        if selectedPreset.isAudioPreset {
            return makeAudioRecordingStatusText()
        }

        if selectedPreset.isScreenPreset {
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
            return readyStatusText(for: currentPresetReadinessLabel, detail: String(localized: "Mikrofon ve sistem sesi kayda eklenecek."))
        }

        return readyStatusText(for: currentPresetReadinessLabel)
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
            return readyStatusText(for: currentPresetReadinessLabel, detail: audioSummary)
        case .window:
            if availableWindows.isEmpty {
                return String(localized: "Paylaşılabilir pencere bulunamadı.")
            }
            if selectedWindowID.isEmpty {
                return String(localized: "Kayıt için bir pencere seçin.")
            }
            return readyStatusText(for: currentPresetReadinessLabel, detail: audioSummary)
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
            if microphonePermissionStatus == .authorized && !selectedMicrophoneID.isEmpty {
                return String(localized: "Mikrofon izni verildi. Sorun mikrofon değil; sistem sesi için macOS ekran kaydı izni gerekli.")
            }
            return String(localized: "Sistem sesi için macOS ekran kaydı izni gerekli.")
        }

        return readyStatusText(for: currentPresetReadinessLabel, detail: screenAudioSummary)
    }

    private func readyStatusText(for subject: String, detail: String? = nil) -> String {
        if let detail {
            return String(format: String(localized: "%@ hazır. %@"), subject, detail)
        }
        return String(format: String(localized: "%@ hazır."), subject)
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
        if selectedRecordingSource == .camera,
           isSystemAudioEnabled,
           screenRecordingPermissionStatus != .authorized {
            names.append(String(localized: "macOS ekran kaydı (sistem sesi açık)"))
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

    private func validateRecordingReadiness(requireSystemAudioReadiness: Bool = true) throws {
        if cameraPermissionStatus != .authorized {
            throw CaptureRecorderError.cameraPermissionDenied
        }
        if microphonePermissionStatus != .authorized {
            throw CaptureRecorderError.microphonePermissionDenied
        }
        // Kadraj koçu önizlemesi yalnızca kamera karesi analiz eder; sistem sesi
        // yakalamıyor. Bu yüzden bu kontrolü yalnızca gerçek kayıt başlatılırken
        // zorunlu tutuyoruz — aksi halde ekran kaydı izni verilmemiş bir
        // kullanıcı, sistem sesi ayarı açıkken kadraj koçunu denediğinde
        // "Ekran kaydı başlatılamadı" gibi kendisiyle ilgisiz bir hata duyar.
        if requireSystemAudioReadiness, isSystemAudioEnabled, screenRecordingPermissionStatus != .authorized {
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

    private func scheduleFrameCoachPreviewPreparation() {
        guard frameCoachPreviewTask == nil else { return }
        guard isCameraPreviewAnalysisActive else { return }

        frameCoachPreviewTask = Task { [weak self] in
            await self?.prepareAnalysisPreviewIfPossible()
            await MainActor.run { [weak self] in
                self?.frameCoachPreviewTask = nil
            }
        }
    }

    private func cancelFrameCoachPreviewPreparation() {
        frameCoachPreviewTask?.cancel()
        frameCoachPreviewTask = nil
    }

    private func prepareAnalysisPreviewIfPossible() async {
        if selectedRecordingSource == .camera {
            guard isFrameCoachEnabled else { return }
            guard !isRecording, !isPreparingRecording else { return }
            guard !Task.isCancelled else { return }

            // Kamera/mikrofon izni eksikse veya bir aygıt seçili değilse burada
            // sessizce çıkmıyoruz: configureRecorder() aynı durumları zaten
            // CaptureRecorderError olarak fırlatıyor ve aşağıdaki catch bunu
            // VoiceOver'a duyuruyor. Kadraj koçu "açık" dendikten sonra hiçbir
            // yönlendirme gelmemesi, kör kullanıcı için nedeni belirsiz bir
            // sessiz başarısızlıktı — burada erken çıkmak yerine gerçek nedeni
            // söylemek daha doğru.
            do {
                // Kadraj koçu yalnızca kamera karesi analiz eder, sistem sesi
                // yakalamaz; ekran kaydı izni burada zorunlu değil (bkz.
                // validateRecordingReadiness'teki requireSystemAudioReadiness).
                try await configureRecorder(requireSystemAudioReadiness: false)
                guard !Task.isCancelled else { return }
                guard isCameraPreviewAnalysisActive, !isRecording, !isPreparingRecording else { return }
                startCameraSessionIfNeeded()
            } catch {
                report(error)
            }
            return
        }

        // Screen camera overlay preview is owned by updateScreenOverlayPreviewState().
        // Keeping it out of the frame-coach preparation path prevents duplicate
        // configure/start cycles when overlay and coaching toggles change together.
    }

    private var isScreenOverlayFrameCoachActive: Bool {
        selectedPreset.isScreenPreset && isScreenCameraOverlayEnabled && isFrameCoachEnabled
    }

    private var isCameraPreviewAnalysisActive: Bool {
        selectedRecordingSource == .camera && isFrameCoachEnabled
    }

    private var isAnyPreviewAnalysisActive: Bool {
        isCameraPreviewAnalysisActive || isScreenOverlayFrameCoachActive
    }

    private func resetFrameCoachAnalysisState() {
        consecutiveMissingFaceAnalyses = 0
        resetSubjectCountTracking()
        lastGoodFrameAt = nil
        lastGoodInstruction = nil
        if !isFrameCoachEnabled {
            currentFrameCoachInstruction = nil
        }
    }

    private func updateScreenOverlayPreviewState() {
        cancelScreenOverlayPreview(stopSession: false)

        guard showsScreenOverlayConfiguration else {
            cameraOverlayRecorder.stopSession()
            return
        }

        screenOverlayPreviewTask = Task {
            await prepareScreenOverlayPreviewIfPossible()
        }
    }

    private func cancelScreenOverlayPreview(stopSession: Bool) {
        screenOverlayPreviewTask?.cancel()
        screenOverlayPreviewTask = nil
        if stopSession {
            cameraOverlayRecorder.stopSession()
        }
    }

    private func prepareScreenOverlayPreviewIfPossible() async {
        guard !Task.isCancelled else { return }
        guard showsScreenOverlayConfiguration else { return }
        guard cameraPermissionStatus == .authorized else { return }
        guard !selectedCameraID.isEmpty else { return }

        do {
            try await cameraOverlayRecorder.configure(cameraDeviceID: selectedCameraID, mode: selectedMode)
            // Re-check after suspension: state may have changed while configure was running.
            // Do NOT call stopSession here — updateScreenOverlayPreviewState already manages
            // session lifecycle and a stale stopSession would kill a subsequently started session.
            guard !Task.isCancelled, showsScreenOverlayConfiguration else { return }
            cameraOverlayRecorder.startSessionInBackground()
        } catch {
            guard !Task.isCancelled else { return }
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

        // Normal camera mode keeps the warmed capture session alive between recordings.
        // Frame Coach is optional; disabling it must not make the next video recording
        // cold-start the camera and lose the user's opening words.
        if !isCameraPreviewAnalysisActive, !isRecording, !selectedPreset.isCameraPreset {
            cancelFrameCoachPreviewPreparation()
            stopCameraSessionIfNeeded()
        } else if !isRecording, !isPreparingRecording {
            scheduleFrameCoachPreviewPreparation()
        }

        if !isAnyPreviewAnalysisActive {
            resetFrameCoachAnalysisState()
        }
    }

    func autoReframeExportSummary(keyframeCount: Int, usedVideoComposition: Bool) -> String {
        guard usedVideoComposition else {
            return String(localized: "dışa aktarım tamamlandı")
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

    /// Uygulama arka plandan öne döndüğünde (ör. kullanıcı Sistem Ayarları'ndan
    /// Ekran Kaydı iznini açıp uygulamaya geri döndüğünde) çağrılır.
    /// `CGPreflightScreenCaptureAccess` bu süreç için sonucu önbelleğe alır ve
    /// izin Ayarlar'dan sonradan açılsa bile süreç yeniden başlamadan
    /// güncellenmeyebilir. Bu yüzden burada gerçek kaynağı (SCShareableContent)
    /// zorla sorgulayarak önbellekteki yanlış "izin yok" durumunu düzeltiyoruz.
    func recheckScreenRecordingAccessAfterForeground() {
        Task {
            await recheckScreenRecordingAccessAfterForegroundAsync()
        }
    }

    /// `refreshDeviceState()` tarafından tetiklenen kısa süreli (varsayılan,
    /// zorlamasız) kaynak taramasından sonra çalışacak şekilde ayrıca `await`
    /// edilebilir; böylece o taramanın önbelleği yanlışlıkla geri
    /// sıfırlamasından sonra en güncel/doğru sonuç kazanır.
    func recheckScreenRecordingAccessAfterForegroundAsync() async {
        await refreshScreenRecordingSources(forceSourceFetch: true)
    }

    private func refreshScreenRecordingSources(forceSourceFetch: Bool = false) async {
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

        // SCShareableContent.excludingDesktopWindows, izin daha hiç sorulmamışken
        // sistemde permission prompt tetikleyebilir veya asılı kalabilir; bu yüzden
        // normalde yalnızca CGPreflightScreenCaptureAccess "izinli" derse çağrılır.
        // Ancak o kontrol süreç ömrü boyunca önbelleğe alınır: kullanıcı izni
        // Ayarlar'dan sonradan açarsa uygulama bunu göremeyebilir. Ekran kaydı
        // için "henüz sorulmadı" durumu olmadığından (bkz. ScreenRecordingAuthorizationStatus),
        // forceSourceFetch true olduğunda gerçek kaynağı sorgulayıp önbelleği
        // kendiliğinden düzeltiyoruz; bu tekrar bir sistem isteği tetiklemez.
        guard forceSourceFetch || screenRecordingPermissionStatus == .authorized else {
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
        applySelectedInputs()
    }

    private func restoreLastRecordingConfiguration(_ configuration: LastRecordingConfiguration) {
        isRestoringLastRecordingConfiguration = true
        defer { isRestoringLastRecordingConfiguration = false }

        selectedPreset = configuration.selectedPreset
        selectedScreenCaptureSource = configuration.selectedScreenCaptureSource
        isScreenCameraOverlayEnabled = configuration.isScreenCameraOverlayEnabled
        isSystemAudioEnabled = configuration.isSystemAudioEnabled
        isCursorHighlightEnabled = configuration.isCursorHighlightEnabled
        isKeyboardShortcutOverlayEnabled = false
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
            isKeyboardShortcutOverlayEnabled: false,
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

    private func synchronizeRecordingSourceWithPreset() {
        if selectedPreset.isAudioPreset {
            selectedRecordingSource = .audio
        } else if selectedPreset.isCameraPreset {
            selectedRecordingSource = .camera
        } else {
            selectedRecordingSource = selectedScreenCaptureSource.recordingSource
        }
    }

}

#if DEBUG
extension RecorderViewModel {
    var recordingPauseTimelineForTesting: RecordingPauseTimeline { recordingPauseTimeline }
    var recordingSessionClockForTesting: RecordingSessionClock? { recordingSessionClock }
}
#endif

private extension String {
    var sentenceCased: String {
        guard let first else { return self }
        return String(first).uppercased(with: Locale(identifier: "tr_TR")) + dropFirst()
    }
}
