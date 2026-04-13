@preconcurrency import AVFoundation
import Foundation

typealias PreviewFrameHandler = (CVPixelBuffer, CMTime) -> Void

protocol CaptureRecording: AnyObject {
    var session: AVCaptureSession { get }

    func cameraDevices() -> [InputDevice]
    func microphoneDevices() -> [InputDevice]
    func configure(videoDeviceID: String, audioDeviceID: String, mode: RecordingMode) async throws
    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) async throws
    func stopRecording()
    func startSessionInBackground()
    func setPreviewFrameHandler(_ handler: PreviewFrameHandler?)
    func setPreviewFramesEnabled(_ isEnabled: Bool)
}

protocol MediaPermissionProviding {
    func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus
    func requestAccess(for mediaType: AVMediaType) async -> Bool
}

struct SystemMediaPermissionProvider: MediaPermissionProviding {
    func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: mediaType)
    }

    func requestAccess(for mediaType: AVMediaType) async -> Bool {
        await AVCaptureDevice.requestAccess(for: mediaType)
    }
}

struct InputDevice: Identifiable, Hashable {
    let id: String
    let name: String
}

enum CaptureRecorderError: LocalizedError {
    case cameraPermissionDenied
    case microphonePermissionDenied
    case cameraNotFound
    case microphoneNotFound
    case cannotAddCamera
    case cannotAddMicrophone
    case cannotAddMovieOutput
    case cannotExportMP4
    case alreadyRecording
    case notConfigured
    case cameraVideoEffectsActive([String])

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return String(localized: "Kamera izni verilmedi.")
        case .microphonePermissionDenied:
            return String(localized: "Mikrofon izni verilmedi.")
        case .cameraNotFound:
            return String(localized: "Kamera bulunamadı.")
        case .microphoneNotFound:
            return String(localized: "Mikrofon bulunamadı.")
        case .cannotAddCamera:
            return String(localized: "Seçilen kamera oturuma eklenemedi.")
        case .cannotAddMicrophone:
            return String(localized: "Seçilen mikrofon oturuma eklenemedi.")
        case .cannotAddMovieOutput:
            return String(localized: "Video kayıt çıkışı hazırlanamadı.")
        case .cannotExportMP4:
            return String(localized: "MP4 dosyası oluşturulamadı.")
        case .alreadyRecording:
            return String(localized: "Kayıt zaten devam ediyor.")
        case .notConfigured:
            return String(localized: "Kayıt oturumu henüz hazır değil.")
        case .cameraVideoEffectsActive(let effectNames):
            let joinedNames = effectNames.joined(separator: ", ")
            return String(localized: "Kamera denetim merkezindeki video efektleri açık: \(joinedNames). Bu efektleri kapatıp tekrar deneyin.")
        }
    }

}

final class CaptureRecorder: NSObject, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, CaptureRecording, @unchecked Sendable {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.local.VideoRecorder.capture-session")
    private let previewOutputQueue = DispatchQueue(label: "com.local.VideoRecorder.preview-output")
    private let movieOutput = AVCaptureMovieFileOutput()
    private let previewOutput = AVCaptureVideoDataOutput()
    private var completion: ((Result<URL, Error>) -> Void)?
    private var previewFrameHandler: PreviewFrameHandler?
    private var previewFramesEnabled = false

    var isRecording: Bool {
        movieOutput.isRecording
    }

    func requestPermissions() async throws {
        let hasCameraAccess = await requestAccess(for: .video)
        guard hasCameraAccess else {
            throw CaptureRecorderError.cameraPermissionDenied
        }

        let hasMicrophoneAccess = await requestAccess(for: .audio)
        guard hasMicrophoneAccess else {
            throw CaptureRecorderError.microphonePermissionDenied
        }
    }

    func cameraDevices() -> [InputDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )

        return discovery.devices.map { InputDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    func microphoneDevices() -> [InputDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )

        return discovery.devices.map { InputDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    func configure(videoDeviceID: String, audioDeviceID: String, mode: RecordingMode) async throws {
        guard let videoDevice = AVCaptureDevice(uniqueID: videoDeviceID) else {
            throw CaptureRecorderError.cameraNotFound
        }
        guard let audioDevice = AVCaptureDevice(uniqueID: audioDeviceID) else {
            throw CaptureRecorderError.microphoneNotFound
        }

        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        let audioInput = try AVCaptureDeviceInput(device: audioDevice)

        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                do {
                    session.beginConfiguration()
                    defer { session.commitConfiguration() }

                    for input in session.inputs {
                        session.removeInput(input)
                    }

                    if session.canSetSessionPreset(.hd1920x1080) {
                        session.sessionPreset = .hd1920x1080
                    } else if session.canSetSessionPreset(.high) {
                        session.sessionPreset = .high
                    }

                    guard session.canAddInput(videoInput) else {
                        throw CaptureRecorderError.cannotAddCamera
                    }
                    session.addInput(videoInput)

                    guard session.canAddInput(audioInput) else {
                        throw CaptureRecorderError.cannotAddMicrophone
                    }
                    session.addInput(audioInput)

                    if !session.outputs.contains(movieOutput) {
                        guard session.canAddOutput(movieOutput) else {
                            throw CaptureRecorderError.cannotAddMovieOutput
                        }
                        session.addOutput(movieOutput)
                    }

                    if !session.outputs.contains(previewOutput) {
                        previewOutput.alwaysDiscardsLateVideoFrames = true
                        previewOutput.videoSettings = [
                            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                        ]
                        previewOutput.setSampleBufferDelegate(self, queue: previewOutputQueue)
                        guard session.canAddOutput(previewOutput) else {
                            throw CaptureRecorderError.cannotAddMovieOutput
                        }
                        session.addOutput(previewOutput)
                    }

                    applyOrientation(for: mode)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func startSession() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [session] in
                defer { continuation.resume() }

                guard !session.isRunning else { return }
                session.startRunning()
            }
        }
    }

    func startSessionInBackground() {
        sessionQueue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stopSession() {
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                do {
                    guard session.outputs.contains(movieOutput) else {
                        throw CaptureRecorderError.notConfigured
                    }
                    guard !movieOutput.isRecording else {
                        throw CaptureRecorderError.alreadyRecording
                    }
                    if let videoDevice = currentVideoDevice(),
                       !CameraVideoEffectsGuard.activeEffectNames(for: videoDevice).isEmpty {
                        throw CaptureRecorderError.cameraVideoEffectsActive(
                            CameraVideoEffectsGuard.activeEffectNames(for: videoDevice)
                        )
                    }

                    if !session.isRunning {
                        session.startRunning()
                    }

                    self.completion = completion
                    movieOutput.startRecording(to: url, recordingDelegate: self)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopRecording() {
        sessionQueue.async { [movieOutput] in
            guard movieOutput.isRecording else { return }
            movieOutput.stopRecording()
        }
    }

    func setPreviewFrameHandler(_ handler: PreviewFrameHandler?) {
        sessionQueue.async { [weak self] in
            self?.previewFrameHandler = handler
        }
    }

    func setPreviewFramesEnabled(_ isEnabled: Bool) {
        sessionQueue.async { [weak self] in
            self?.previewFramesEnabled = isEnabled
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        if let error {
            completion?(.failure(error))
        } else {
            completion?(.success(outputFileURL))
        }
        completion = nil
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard previewFramesEnabled,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        previewFrameHandler?(imageBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    private func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    AVCaptureDevice.requestAccess(for: mediaType) { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func applyOrientation(for mode: RecordingMode) {
        let angle: CGFloat = mode == .vertical1080p ? 90 : 0

        if let movieConnection = movieOutput.connection(with: .video),
           movieConnection.isVideoRotationAngleSupported(angle) {
            movieConnection.videoRotationAngle = angle
        }

        if let previewConnection = previewOutput.connection(with: .video),
           previewConnection.isVideoRotationAngleSupported(angle) {
            previewConnection.videoRotationAngle = angle
        }
    }

    private func currentVideoDevice() -> AVCaptureDevice? {
        session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first(where: { $0.device.hasMediaType(.video) })?
            .device
    }
}
