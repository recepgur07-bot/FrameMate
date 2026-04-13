@preconcurrency import AVFoundation
import Foundation

protocol CameraOverlayRecording: AnyObject {
    var session: AVCaptureSession { get }

    func configure(cameraDeviceID: String, mode: RecordingMode) async throws
    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) async throws
    func stopRecording()
    func startSessionInBackground()
    func stopSession()
    func setPreviewFrameHandler(_ handler: PreviewFrameHandler?)
    func setPreviewFramesEnabled(_ isEnabled: Bool)
}

final class CameraOverlayRecorder: NSObject, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, CameraOverlayRecording, @unchecked Sendable {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.local.VideoRecorder.camera-overlay")
    private let previewOutputQueue = DispatchQueue(label: "com.local.VideoRecorder.camera-overlay.preview-output")
    private let movieOutput = AVCaptureMovieFileOutput()
    private let previewOutput = AVCaptureVideoDataOutput()
    private var completion: ((Result<URL, Error>) -> Void)?
    private var previewFrameHandler: PreviewFrameHandler?
    private var previewFramesEnabled = false

    func configure(cameraDeviceID: String, mode: RecordingMode) async throws {
        guard let videoDevice = AVCaptureDevice(uniqueID: cameraDeviceID) else {
            throw CaptureRecorderError.cameraNotFound
        }

        let videoInput = try AVCaptureDeviceInput(device: videoDevice)

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

    private func applyOrientation(for mode: RecordingMode) {
        let angle: CGFloat = mode == .vertical1080p ? 90 : 0

        if let movieConnection = movieOutput.connection(with: .video),
           movieConnection.isVideoRotationAngleSupported(angle) {
            movieConnection.videoRotationAngle = angle
        }
    }

    private func currentVideoDevice() -> AVCaptureDevice? {
        session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first(where: { $0.device.hasMediaType(.video) })?
            .device
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard output === previewOutput, previewFramesEnabled else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        previewFrameHandler?(pixelBuffer, presentationTime)
    }
}
