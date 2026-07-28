@preconcurrency import AVFoundation
import Foundation

typealias PreviewFrameHandler = (CVPixelBuffer, CMTime) -> Void

private struct CaptureUnsafeSendableBox<Value>: @unchecked Sendable {
    let value: Value
}

protocol CaptureRecording: AnyObject {
    var session: AVCaptureSession { get }

    func cameraDevices() -> [InputDevice]
    func microphoneDevices() -> [InputDevice]
    func configure(videoDeviceID: String, audioDeviceID: String, mode: RecordingMode, audioChannelMode: AudioChannelMode) async throws
    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) async throws
    func stopRecording()
    func startSessionInBackground()
    func stopSession()
    func setPreviewFrameHandler(_ handler: PreviewFrameHandler?)
    func setPreviewFramesEnabled(_ isEnabled: Bool)
    /// Host-clock presentation time of the first video sample captured since the most
    /// recent `startRecording(to:completion:)`, if one has arrived yet. Used as this
    /// component's contribution to `RecordingSessionClock` when it is the session's
    /// primary component (the camera mode).
    var firstSamplePresentationTime: CMTime? { get }
}

extension CaptureRecording {
    var firstSamplePresentationTime: CMTime? { nil }
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

    var localizedName: String {
        DeviceDisplayNameLocalizer.localizedCaptureDeviceName(name)
    }
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
    case recordingStartTimedOut
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
        case .recordingStartTimedOut:
            return String(localized: "Kamera kaydı zamanında başlatılamadı.")
        case .cameraVideoEffectsActive(let effectNames):
            let joinedNames = effectNames.joined(separator: ", ")
            return String(localized: "Kamera denetim merkezindeki video efektleri açık: \(joinedNames). Bu efektleri kapatıp tekrar deneyin.")
        }
    }

}

final class CaptureRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, CaptureRecording, @unchecked Sendable {
    private static let recordingStartTimeout: DispatchTimeInterval = .seconds(8)
    private static let writerDrainDelay: DispatchTimeInterval = .milliseconds(250)
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.local.VideoRecorder.capture-session")
    private let previewOutputQueue = DispatchQueue(label: "com.local.VideoRecorder.preview-output")
    private let audioOutputQueue = DispatchQueue(label: "com.local.VideoRecorder.camera-audio-output")
    private let writerQueue = DispatchQueue(label: "com.local.VideoRecorder.camera-writer")
    private let previewOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var completion: ((Result<URL, Error>) -> Void)?
    private var recordingStartContinuation: CheckedContinuation<Void, Error>?
    private var recordingStartAttempt = 0
    private var writer: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var isRecording = false
    private var isStopping = false
    private var hasStartedWriting = false
    private var hasAppendedAudioSample = false
    private var audioChannelMode: AudioChannelMode = .automatic
    private var previewFrameHandler: PreviewFrameHandler?
    private var previewFramesEnabled = false
    private var capturedFirstSampleTime: CMTime?
    private var isAwaitingFirstSample = false

    var firstSamplePresentationTime: CMTime? { capturedFirstSampleTime }

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

    func configure(videoDeviceID: String, audioDeviceID: String, mode: RecordingMode, audioChannelMode: AudioChannelMode) async throws {
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

                    if !session.outputs.contains(previewOutput) {
                        // These frames are both previewed and encoded. Dropping a late
                        // frame here can make the movie clock start after the microphone.
                        previewOutput.alwaysDiscardsLateVideoFrames = false
                        previewOutput.videoSettings = [
                            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                        ]
                        previewOutput.setSampleBufferDelegate(self, queue: previewOutputQueue)
                        guard session.canAddOutput(previewOutput) else {
                            throw CaptureRecorderError.cannotAddMovieOutput
                        }
                        session.addOutput(previewOutput)
                    }

                    if !session.outputs.contains(audioOutput) {
                        audioOutput.setSampleBufferDelegate(self, queue: audioOutputQueue)
                        guard session.canAddOutput(audioOutput) else {
                            throw CaptureRecorderError.cannotAddMovieOutput
                        }
                        session.addOutput(audioOutput)
                    }

                    applyOrientation(for: mode)
                    self.audioChannelMode = audioChannelMode
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                do {
                    guard session.outputs.contains(previewOutput), session.outputs.contains(audioOutput) else {
                        throw CaptureRecorderError.notConfigured
                    }
                    guard !isRecording else {
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

                    let writer = try makeWriter(to: url, audioChannelMode: self.audioChannelMode)
                    self.writer = writer.writer
                    self.videoWriterInput = writer.videoInput
                    self.audioWriterInput = writer.audioInput
                    self.outputURL = url
                    self.completion = completion
                    self.recordingStartContinuation = continuation
                    self.recordingStartAttempt += 1
                    let startAttempt = self.recordingStartAttempt
                    self.capturedFirstSampleTime = nil
                    self.isAwaitingFirstSample = true
                    self.hasStartedWriting = false
                    self.hasAppendedAudioSample = false
                    self.isStopping = false
                    self.isRecording = true

                    // `startRecording` is only complete once AVFoundation confirms it
                    // has begun writing. Do not leave the UI in “preparing” forever if
                    // a camera never produces a valid stream.
                    self.sessionQueue.asyncAfter(deadline: .now() + Self.recordingStartTimeout) { [self] in
                        guard self.recordingStartAttempt == startAttempt,
                              let pendingContinuation = self.recordingStartContinuation else {
                            return
                        }
                        self.recordingStartContinuation = nil
                        self.cancelRecordingLocked()
                        pendingContinuation.resume(throwing: CaptureRecorderError.recordingStartTimedOut)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopRecording() {
        sessionQueue.async { [self] in
            guard isRecording, !isStopping else { return }
            isStopping = true
            if session.isRunning {
                session.stopRunning()
            }

            writerQueue.asyncAfter(deadline: .now() + Self.writerDrainDelay) { [self] in
                finishRecordingOnWriterQueue()
            }
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

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output === audioOutput {
            appendAudioSample(sampleBuffer)
            return
        }
        guard output === previewOutput else { return }
        if isAwaitingFirstSample {
            isAwaitingFirstSample = false
            capturedFirstSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        }

        appendVideoSample(sampleBuffer)

        guard previewFramesEnabled,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        previewFrameHandler?(imageBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    private func appendVideoSample(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        let sampleBufferBox = CaptureUnsafeSendableBox(value: sampleBuffer)
        writerQueue.async { [self] in
            // Audio is the timeline anchor. This deliberately preserves the first
            // spoken sound even if the camera delivers its first encoded frame later.
            guard hasStartedWriting,
                  !isStopping,
                  let videoWriterInput,
                  videoWriterInput.isReadyForMoreMediaData else { return }
            _ = videoWriterInput.append(sampleBufferBox.value)
        }
    }

    private func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        let sampleBufferBox = CaptureUnsafeSendableBox(value: sampleBuffer)
        writerQueue.async { [self] in
            guard isRecording, !isStopping,
                  let writer,
                  let audioWriterInput else { return }

            if !hasStartedWriting {
                guard writer.startWriting() else {
                    completeRecording(.failure(writer.error ?? CaptureRecorderError.cannotExportMP4))
                    return
                }
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBufferBox.value)
                writer.startSession(atSourceTime: presentationTime)
                hasStartedWriting = true
                runtimeDebugLog("Camera recording started writing audio: \(outputURL?.path ?? "unknown")")
            }

            guard audioWriterInput.isReadyForMoreMediaData,
                  audioWriterInput.append(sampleBufferBox.value) else { return }
            hasAppendedAudioSample = true
            resumeRecordingStartIfNeeded()
        }
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
        let angle: CGFloat = mode.captureRotationAngle  // always 0
        let connections = [previewOutput.connection(with: .video)].compactMap { $0 }
        for connection in connections {
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

    private func currentVideoDevice() -> AVCaptureDevice? {
        session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first(where: { $0.device.hasMediaType(.video) })?
            .device
    }

    private func makeWriter(to url: URL, audioChannelMode: AudioChannelMode) throws -> (writer: AVAssetWriter, videoInput: AVAssetWriterInput, audioInput: AVAssetWriterInput) {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let fallbackVideoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: 1920,
            AVVideoHeightKey: 1080,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000]
        ]
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: previewOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov) ?? fallbackVideoSettings
        )
        videoInput.expectsMediaDataInRealTime = true

        var audioSettings = audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) ?? [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVEncoderBitRateKey: 128_000,
            AVNumberOfChannelsKey: 1
        ]
        if audioChannelMode == .mono {
            audioSettings[AVNumberOfChannelsKey] = 1
        }
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            throw CaptureRecorderError.cannotExportMP4
        }
        writer.add(videoInput)
        writer.add(audioInput)
        return (writer, videoInput, audioInput)
    }

    private func resumeRecordingStartIfNeeded() {
        sessionQueue.async { [self] in
            guard let continuation = recordingStartContinuation else { return }
            recordingStartContinuation = nil
            continuation.resume()
        }
    }

    private func finishRecordingOnWriterQueue() {
        guard let writer, let outputURL, hasStartedWriting, hasAppendedAudioSample else {
            completeRecording(.failure(CaptureRecorderError.cannotExportMP4))
            return
        }
        videoWriterInput?.markAsFinished()
        audioWriterInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            if let error = writer.error {
                self?.completeRecording(.failure(error))
            } else {
                self?.completeRecording(.success(outputURL))
            }
        }
    }

    private func completeRecording(_ result: Result<URL, Error>) {
        sessionQueue.async { [self] in
            let pendingContinuation = recordingStartContinuation
            recordingStartContinuation = nil
            let completion = completion
            resetRecordingStateLocked()
            if let pendingContinuation {
                pendingContinuation.resume(throwing: CaptureRecorderError.recordingStartTimedOut)
            }
            completion?(result)
        }
    }

    private func cancelRecordingLocked() {
        writer?.cancelWriting()
        resetRecordingStateLocked()
    }

    private func resetRecordingStateLocked() {
        writer = nil
        videoWriterInput = nil
        audioWriterInput = nil
        outputURL = nil
        completion = nil
        isRecording = false
        isStopping = false
        hasStartedWriting = false
        hasAppendedAudioSample = false
        isAwaitingFirstSample = false
    }
}

enum MovieOutputVideoEncoding {
    static func applyHEVCSettings(to movieOutput: AVCaptureMovieFileOutput) {
        guard let connection = movieOutput.connection(with: .video) else {
            return
        }

        movieOutput.setOutputSettings([
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoMaxKeyFrameIntervalKey: 60
            ]
        ], for: connection)
    }
}

enum MovieOutputAudioEncoding {
    static func applyChannelMode(_ mode: AudioChannelMode, to movieOutput: AVCaptureMovieFileOutput) {
        guard let connection = movieOutput.connection(with: .audio) else {
            return
        }

        let nativeChannelCount = connection.audioChannels.count
        guard nativeChannelCount > 0 else { return }

        let targetChannelCount: Int
        switch mode {
        case .automatic:
            targetChannelCount = min(nativeChannelCount, 2)
        case .mono:
            targetChannelCount = 1
        case .stereo:
            targetChannelCount = min(nativeChannelCount, 2)
        }

        var settings = movieOutput.outputSettings(for: connection) ?? [:]
        settings[AVNumberOfChannelsKey] = targetChannelCount
        movieOutput.setOutputSettings(settings, for: connection)
    }
}
