import AVFoundation
import Foundation
@testable import VideoRecorderApp

final class MockInstructionSpeaker: InstructionSpeaking {
    private(set) var spokenTexts: [String] = []
    var isSpeaking = false

    func speak(_ text: String) {
        spokenTexts.append(text)
    }
}

final class MockCaptureRecorder: CaptureRecording {
    let session = AVCaptureSession()
    var cameras: [InputDevice]
    var microphones: [InputDevice]
    private(set) var previewFramesEnabled = false
    private(set) var previewFrameHandler: PreviewFrameHandler?

    init(cameras: [InputDevice] = [], microphones: [InputDevice] = []) {
        self.cameras = cameras
        self.microphones = microphones
    }

    func cameraDevices() -> [InputDevice] { cameras }
    func microphoneDevices() -> [InputDevice] { microphones }

    func configure(videoDeviceID: String, audioDeviceID: String, mode: RecordingMode) async throws {}
    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) async throws {}
    func stopRecording() {}
    func startSessionInBackground() {}
    func setPreviewFrameHandler(_ handler: PreviewFrameHandler?) { previewFrameHandler = handler }
    func setPreviewFramesEnabled(_ isEnabled: Bool) { previewFramesEnabled = isEnabled }
}

struct MockMediaPermissionProvider: MediaPermissionProviding {
    var statuses: [AVMediaType: AVAuthorizationStatus]

    func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        statuses[mediaType] ?? .notDetermined
    }

    func requestAccess(for mediaType: AVMediaType) async -> Bool {
        statuses[mediaType] == .authorized
    }
}

final class MockScreenRecordingProvider: ScreenRecordingProviding {
    var status: ScreenRecordingAuthorizationStatus = .authorized
    var requestResult: ScreenRecordingPermissionRequestResult = .granted
    var displays: [ScreenDisplayOption] = []
    var windows: [ScreenWindowOption] = []
    var displaysError: Error?
    var windowsError: Error?
    private(set) var startedTarget: ScreenRecordingTarget?
    private(set) var startedMicrophoneID: String?
    private(set) var startedSystemAudioEnabled = false
    private(set) var startedURL: URL?
    private(set) var stopCalled = false
    private(set) var isStartPending = false
    var startError: Error?
    var shouldCompleteOnStop = false
    private var completion: ((Result<URL, Error>) -> Void)?

    init(
        status: ScreenRecordingAuthorizationStatus = .authorized,
        displays: [ScreenDisplayOption] = [],
        windows: [ScreenWindowOption] = []
    ) {
        self.status = status
        self.displays = displays
        self.windows = windows
    }

    func authorizationStatus() -> ScreenRecordingAuthorizationStatus {
        status
    }

    func requestAccess() async -> ScreenRecordingPermissionRequestResult {
        requestResult
    }

    func availableDisplays() async throws -> [ScreenDisplayOption] {
        if let displaysError {
            throw displaysError
        }
        return displays
    }

    func availableWindows() async throws -> [ScreenWindowOption] {
        if let windowsError {
            throw windowsError
        }
        return windows
    }

    func startRecording(
        target: ScreenRecordingTarget,
        microphoneDeviceID: String,
        includeSystemAudio: Bool,
        to url: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) async throws {
        if let startError {
            throw startError
        }

        startedTarget = target
        startedMicrophoneID = microphoneDeviceID
        startedSystemAudioEnabled = includeSystemAudio
        startedURL = url
        self.completion = completion
        isStartPending = true
    }

    func stopRecording() {
        stopCalled = true
        if shouldCompleteOnStop, let startedURL {
            isStartPending = false
            completion?(.success(startedURL))
        }
    }
}

final class MockCameraOverlayRecorder: CameraOverlayRecording {
    let session = AVCaptureSession()
    private(set) var configuredCameraID: String?
    private(set) var configuredMode: RecordingMode?
    private(set) var startedURL: URL?
    private(set) var stopCalled = false
    private(set) var startSessionCalled = false
    private(set) var stopSessionCalled = false
    private(set) var previewFramesEnabled = false
    private(set) var previewFrameHandler: PreviewFrameHandler?
    var startError: Error?
    var shouldCompleteOnStop = true
    private var completion: ((Result<URL, Error>) -> Void)?

    func configure(cameraDeviceID: String, mode: RecordingMode) async throws {
        configuredCameraID = cameraDeviceID
        configuredMode = mode
    }

    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) async throws {
        if let startError {
            throw startError
        }

        startedURL = url
        self.completion = completion
    }

    func stopRecording() {
        stopCalled = true
        if shouldCompleteOnStop, let startedURL {
            completion?(.success(startedURL))
        }
    }

    func startSessionInBackground() {
        startSessionCalled = true
    }

    func stopSession() {
        stopSessionCalled = true
    }

    func setPreviewFrameHandler(_ handler: PreviewFrameHandler?) {
        previewFrameHandler = handler
    }

    func setPreviewFramesEnabled(_ isEnabled: Bool) {
        previewFramesEnabled = isEnabled
    }
}

final class MockSystemAudioRecorder: SystemAudioRecordingProviding {
    private(set) var startCalled = false
    private(set) var stopCalled = false
    private(set) var startedURL: URL?
    var startError: Error?
    var shouldCompleteOnStop = true
    var onStart: () -> Void = {}
    private var completion: ((Result<URL, Error>) -> Void)?

    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) async throws {
        if let startError {
            throw startError
        }

        startCalled = true
        startedURL = url
        self.completion = completion
        onStart()
    }

    func stopRecording() {
        stopCalled = true
        if shouldCompleteOnStop, let startedURL {
            completion?(.success(startedURL))
        }
    }
}

final class MockMicrophoneAudioRecorder: MicrophoneAudioRecordingProviding {
    private(set) var startCalled = false
    private(set) var stopCalled = false
    private(set) var startedURL: URL?
    private(set) var startedDeviceID: String?
    var startError: Error?
    var shouldCompleteOnStop = true
    private var completion: ((Result<URL, Error>) -> Void)?

    func startRecording(deviceID: String, to url: URL, completion: @escaping (Result<URL, Error>) -> Void) async throws {
        if let startError {
            throw startError
        }

        startCalled = true
        startedURL = url
        startedDeviceID = deviceID
        self.completion = completion
    }

    func stopRecording() {
        stopCalled = true
        if shouldCompleteOnStop, let startedURL {
            completion?(.success(startedURL))
        }
    }
}

final class MockCursorHighlightRecorder: CursorHighlightRecordingProviding {
    private(set) var startCalled = false
    private(set) var stopCalled = false
    private(set) var startedFrame: CGRect?
    var timelineToReturn = CursorHighlightTimeline.empty

    func startTracking(targetFrame: CGRect) {
        startCalled = true
        startedFrame = targetFrame
    }

    func stopTracking() -> CursorHighlightTimeline {
        stopCalled = true
        return timelineToReturn
    }
}

final class MockKeyboardShortcutRecorder: KeyboardShortcutRecordingProviding {
    private(set) var startCalled = false
    private(set) var stopCalled = false
    var timelineToReturn = KeyboardShortcutTimeline.empty

    func startTracking() {
        startCalled = true
    }

    func stopTracking() -> KeyboardShortcutTimeline {
        stopCalled = true
        return timelineToReturn
    }
}

final class MockTrialStartDateStore: TrialStartDateStoring {
    var startDate: Date?

    init(startDate: Date? = nil) {
        self.startDate = startDate
    }
}

struct FixedDateProvider: DateProviding {
    var now: Date
}

final class MockAppStorePurchasing: AppStorePurchasing {
    var productsToReturn: [AppStoreProductInfo]
    var entitlementProductIDs: Set<String>
    var purchaseResults: [String: AppStorePurchaseResult] = [:]
    private(set) var purchasedProductIDs: [String] = []
    private(set) var syncCallCount = 0

    init(
        productsToReturn: [AppStoreProductInfo] = [],
        entitlementProductIDs: Set<String> = []
    ) {
        self.productsToReturn = productsToReturn
        self.entitlementProductIDs = entitlementProductIDs
    }

    func products(for productIDs: [String]) async throws -> [AppStoreProductInfo] {
        productsToReturn.filter { productIDs.contains($0.id) }
    }

    func currentEntitlementProductIDs() async -> Set<String> {
        entitlementProductIDs
    }

    func purchase(productID: String) async throws -> AppStorePurchaseResult {
        purchasedProductIDs.append(productID)
        return purchaseResults[productID] ?? .success
    }

    func syncPurchases() async throws {
        syncCallCount += 1
    }
}

@MainActor
final class MockAppAccessManager: AppAccessManaging {
    var state: AppAccessState
    private(set) var refreshCallCount = 0
    private(set) var purchasedPlans: [AppAccessPlan] = []
    private(set) var restoreCallCount = 0
    var purchaseResult: AppStorePurchaseResult = .success

    init(state: AppAccessState) {
        self.state = state
    }

    func refresh() async {
        refreshCallCount += 1
    }

    func purchase(plan: AppAccessPlan) async -> AppStorePurchaseResult {
        purchasedPlans.append(plan)
        return purchaseResult
    }

    func restorePurchases() async {
        restoreCallCount += 1
    }
}
