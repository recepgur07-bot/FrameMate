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
    /// Host-clock presentation time of the first video sample captured since the most
    /// recent `startRecording(to:completion:)`, if one has arrived yet. The screen+camera
    /// overlay is never the session's primary component, but its own start offset
    /// relative to the primary is still needed to align its track in the export (Phase 3).
    var firstSamplePresentationTime: CMTime? { get }
}

extension CameraOverlayRecording {
    var firstSamplePresentationTime: CMTime? { nil }
}

private struct CameraOverlaySampleBox: @unchecked Sendable {
    let value: CMSampleBuffer
}

/// Records the camera overlay for screen+camera recordings by feeding frames from a
/// dedicated `AVCaptureVideoDataOutput` into an `AVAssetWriter` — the same architecture
/// `CaptureRecorder` already uses for the plain "kamera kaydı" mode, chosen over
/// `AVCaptureMovieFileOutput` because that API gives no control over (and no reliable
/// signal about) when the camera has actually delivered its first frame, and its
/// `stopRecording()` can leave the recording stuck indefinitely — with no completion and
/// no error — if the camera session stalled while negotiating exposure/focus at record
/// start. `AVAssetWriter` lets this class detect both failure modes directly: it only
/// calls `writer.startWriting()` once a real sample has arrived, and a bounded timeout
/// on `finishWriting` guarantees `stopRecording()` always eventually reports success or
/// failure instead of hanging.
final class CameraOverlayRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, CameraOverlayRecording, @unchecked Sendable {
    /// How long `startRecording` waits for the camera to actually deliver its first frame
    /// before failing closed. Without this, a camera still negotiating exposure/focus at
    /// recording start can produce a file with no real video in it, and the caller would
    /// have no way to know — see the screen+camera-overlay "camera never appears in the
    /// final video" investigation this timeout was added to close.
    private static let recordingStartTimeout: DispatchTimeInterval = .seconds(4)
    /// How long `stopRecording` waits for `AVAssetWriter.finishWriting` to actually call
    /// back before forcing a failure. `finishWriting` normally completes in well under a
    /// second for a clip this short; this is a safety net, not the expected path.
    private static let finishWritingTimeout: DispatchTimeInterval = .seconds(5)
    /// Short delay between `stopRecording` and telling the writer to finish, so any sample
    /// already queued on `writerQueue` from a frame that arrived right at the stop moment
    /// gets appended before `markAsFinished()` — mirrors `CaptureRecorder`'s identical delay.
    private static let writerDrainDelay: DispatchTimeInterval = .milliseconds(250)

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.local.VideoRecorder.camera-overlay")
    private let previewOutputQueue = DispatchQueue(label: "com.local.VideoRecorder.camera-overlay.preview-output")
    private let recordingOutputQueue = DispatchQueue(label: "com.local.VideoRecorder.camera-overlay.recording-output")
    private let writerQueue = DispatchQueue(label: "com.local.VideoRecorder.camera-overlay-writer")

    /// Feeds only the frame-coach preview handler. Kept separate from `recordingOutput` so
    /// analysis keeps seeing the camera's natural (unrotated) orientation exactly as before,
    /// regardless of what rotation the recorded file needs for vertical mode.
    private let previewOutput = AVCaptureVideoDataOutput()
    /// Feeds only the asset writer. Its connection carries whatever rotation the recorded
    /// file needs (see `applyOrientation`), independent of `previewOutput`.
    private let recordingOutput = AVCaptureVideoDataOutput()

    private var writer: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var recordingStartContinuation: CheckedContinuation<Void, Error>?
    private var recordingStartAttempt = 0
    private var isRecording = false
    private var isStopping = false
    private var hasStartedWriting = false
    private var previewFrameHandler: PreviewFrameHandler?
    private var previewFramesEnabled = false
    private var capturedFirstSampleTime: CMTime?
    private var isAwaitingFirstSample = false
    private var configuredDeviceID: String?
    private var configuredMode: RecordingMode?

    var firstSamplePresentationTime: CMTime? { capturedFirstSampleTime }

    func configure(cameraDeviceID: String, mode: RecordingMode) async throws {
        guard let videoDevice = AVCaptureDevice(uniqueID: cameraDeviceID) else {
            throw CaptureRecorderError.cameraNotFound
        }

        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                do {
                    guard !isRecording else {
                        throw CaptureRecorderError.alreadyRecording
                    }

                    // The screen+camera overlay preview configures this same session
                    // before recording starts. Re-adding an identical input to an
                    // already-running session forces the camera to re-negotiate
                    // exposure/focus — a multi-second stall right as recording begins.
                    // Skip the rebuild when the device and mode haven't actually changed.
                    if configuredDeviceID == cameraDeviceID,
                       configuredMode == mode,
                       session.inputs.contains(where: { ($0 as? AVCaptureDeviceInput)?.device.uniqueID == cameraDeviceID }) {
                        continuation.resume()
                        return
                    }

                    let videoInput = try AVCaptureDeviceInput(device: videoDevice)

                    try configureSessionLocked(videoInput: videoInput, mode: mode)

                    configuredDeviceID = cameraDeviceID
                    configuredMode = mode
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configureSessionLocked(videoInput: AVCaptureDeviceInput, mode: RecordingMode) throws {
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

        if !session.outputs.contains(recordingOutput) {
            // This output's frames go straight into the asset writer; none may be
            // dropped or the recording gains gaps.
            recordingOutput.alwaysDiscardsLateVideoFrames = false
            recordingOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            recordingOutput.setSampleBufferDelegate(self, queue: recordingOutputQueue)
            guard session.canAddOutput(recordingOutput) else {
                throw CaptureRecorderError.cannotAddMovieOutput
            }
            session.addOutput(recordingOutput)
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
    }

    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                do {
                    guard session.outputs.contains(recordingOutput) else {
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

                    let writer = try makeWriter(to: url)
                    self.writer = writer.writer
                    self.videoWriterInput = writer.videoInput
                    self.outputURL = url
                    self.completion = completion
                    self.recordingStartContinuation = continuation
                    self.recordingStartAttempt += 1
                    let startAttempt = self.recordingStartAttempt
                    self.capturedFirstSampleTime = nil
                    self.isAwaitingFirstSample = true
                    self.hasStartedWriting = false
                    self.isStopping = false
                    self.isRecording = true

                    // Don't tell the caller the overlay is recording until the camera has
                    // actually delivered a frame. Without this, a camera still negotiating
                    // exposure/focus can produce a file with no real video in it, and the
                    // caller has no way to know the overlay silently failed.
                    self.sessionQueue.asyncAfter(deadline: .now() + Self.recordingStartTimeout) { [self] in
                        guard self.recordingStartAttempt == startAttempt,
                              let pendingContinuation = self.recordingStartContinuation else {
                            return
                        }
                        self.recordingStartContinuation = nil
                        runtimeDebugLog("Camera overlay recording timed out waiting for its first frame; cancelling it")
                        self.writerQueue.async { [self] in
                            self.writer?.cancelWriting()
                        }
                        self.resetRecordingStateLocked()
                        pendingContinuation.resume(throwing: CaptureRecorderError.recordingStartTimedOut)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func resumeRecordingStartIfNeeded() {
        sessionQueue.async { [self] in
            guard let continuation = recordingStartContinuation else { return }
            recordingStartContinuation = nil
            continuation.resume()
        }
    }

    func stopRecording() {
        sessionQueue.async { [self] in
            guard isRecording, !isStopping else { return }
            isStopping = true
            let attempt = recordingStartAttempt

            writerQueue.asyncAfter(deadline: .now() + Self.writerDrainDelay) { [self] in
                finishRecordingOnWriterQueue()
            }

            // finishWriting normally completes almost immediately for a clip this short.
            // If it never calls back, don't leave the recording (and whatever awaits its
            // result) stuck forever — report a failure and let the caller move on.
            self.sessionQueue.asyncAfter(deadline: .now() + Self.finishWritingTimeout) { [self] in
                guard self.isRecording, self.recordingStartAttempt == attempt else { return }
                runtimeDebugLog("Camera overlay recording finalize timed out; forcing failure")
                self.completeRecording(.failure(CaptureRecorderError.recordingStartTimedOut))
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

    private func applyOrientation(for mode: RecordingMode) {
        let angle: CGFloat = mode == .vertical1080p ? 90 : 0

        if let connection = recordingOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    private func currentVideoDevice() -> AVCaptureDevice? {
        session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first(where: { $0.device.hasMediaType(.video) })?
            .device
    }

    private func makeWriter(to url: URL) throws -> (writer: AVAssetWriter, videoInput: AVAssetWriterInput) {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let fallbackVideoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: 1920,
            AVVideoHeightKey: 1080,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000]
        ]
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: recordingOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov) ?? fallbackVideoSettings
        )
        videoInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(videoInput) else {
            throw CaptureRecorderError.cannotExportMP4
        }
        writer.add(videoInput)
        return (writer, videoInput)
    }

    private func appendVideoSampleIfRecording(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        let box = CameraOverlaySampleBox(value: sampleBuffer)
        writerQueue.async { [self] in
            guard isRecording, !isStopping, let writer, let videoWriterInput else { return }

            if !hasStartedWriting {
                guard writer.startWriting() else {
                    completeRecording(.failure(writer.error ?? CaptureRecorderError.cannotExportMP4))
                    return
                }
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(box.value)
                writer.startSession(atSourceTime: presentationTime)
                hasStartedWriting = true
                runtimeDebugLog("Camera overlay recording started writing video: \(outputURL?.path ?? "unknown")")
            }

            guard videoWriterInput.isReadyForMoreMediaData else { return }
            _ = videoWriterInput.append(box.value)
        }
    }

    private func finishRecordingOnWriterQueue() {
        guard let writer, hasStartedWriting else {
            completeRecording(.failure(CaptureRecorderError.cannotExportMP4))
            return
        }
        videoWriterInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self else { return }
            if let error = writer.error {
                self.completeRecording(.failure(error))
            } else if let url = self.outputURL {
                self.completeRecording(.success(url))
            } else {
                self.completeRecording(.failure(CaptureRecorderError.cannotExportMP4))
            }
        }
    }

    private func completeRecording(_ result: Result<URL, Error>) {
        sessionQueue.async { [self] in
            // Idempotent: a forced timeout and the writer's own (late) completion can
            // both reach here for the same attempt. Only the first one should report.
            guard isRecording else { return }
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

    private func resetRecordingStateLocked() {
        writer = nil
        videoWriterInput = nil
        outputURL = nil
        completion = nil
        isRecording = false
        isStopping = false
        hasStartedWriting = false
        isAwaitingFirstSample = false
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output === recordingOutput {
            if isAwaitingFirstSample {
                isAwaitingFirstSample = false
                capturedFirstSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                resumeRecordingStartIfNeeded()
            }
            appendVideoSampleIfRecording(sampleBuffer)
            return
        }

        guard output === previewOutput else { return }
        guard previewFramesEnabled,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        previewFrameHandler?(pixelBuffer, presentationTime)
    }
}
