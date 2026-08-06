@preconcurrency import AVFoundation
import Foundation

private struct UnsafeSendableBox<Value>: @unchecked Sendable {
    let value: Value
}

protocol MicrophoneAudioRecordingProviding: AnyObject {
    func startRecording(deviceID: String, to url: URL, audioChannelMode: AudioChannelMode, completion: @escaping (Result<URL, Error>) -> Void) async throws
    func stopRecording()
    /// Host-clock presentation time of the first accepted audio sample of the current (or
    /// most recently finished) recording, if one has arrived yet. Used as this component's
    /// contribution to `RecordingSessionClock` when it is the session's primary component
    /// (audio-only mode with a microphone selected).
    var firstSamplePresentationTime: CMTime? { get }
}

extension MicrophoneAudioRecordingProviding {
    var firstSamplePresentationTime: CMTime? { nil }
}

enum MicrophoneAudioRecorderError: LocalizedError, Equatable {
    case microphoneNotFound
    case cannotAddMicrophone
    case cannotCreateWriter
    case emptyRecording
    case noSignalAtStart

    var errorDescription: String? {
        switch self {
        case .microphoneNotFound:
            return String(localized: "Seçilen mikrofon bulunamadı.")
        case .cannotAddMicrophone:
            return String(localized: "Mikrofon ses kaydı hazırlanamadı.")
        case .cannotCreateWriter:
            return String(localized: "Mikrofon ses dosyası oluşturulamadı.")
        case .emptyRecording:
            return String(localized: "Mikrofon kaydında ses alınamadı.")
        case .noSignalAtStart:
            return String(localized: "Seçilen mikrofondan ses sinyali gelmiyor. Cihazın bağlı ve seçili giriş cihazı olduğundan emin olup tekrar deneyin.")
        }
    }
}

final class RecordingSampleTracker {
    private(set) var hasAppendedSample = false

    func markAppendedSample() {
        hasAppendedSample = true
    }

    func reset() {
        hasAppendedSample = false
    }
}

typealias MicrophoneAudioRecorderSampleTracker = RecordingSampleTracker

final class MicrophoneAudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, MicrophoneAudioRecordingProviding, @unchecked Sendable {
    private static let finalizeDelay: DispatchTimeInterval = .milliseconds(250)
    private let sessionQueue = DispatchQueue(label: "com.local.VideoRecorder.microphone-audio-session")
    private let writerQueue = DispatchQueue(label: "com.local.VideoRecorder.microphone-audio-writer")
    private let outputQueue = DispatchQueue(label: "com.local.VideoRecorder.microphone-audio-output")

    private let session = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var audioInput: AVCaptureDeviceInput?
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var outputURL: URL?
    private var hasStartedWriting = false
    private let sampleTracker = RecordingSampleTracker()
    private var isStopping = false
    private var capturedFirstSampleTime: CMTime?

    // Sample-flow instrumentation. An external/USB microphone that stops delivering
    // mid-take (capture-session runtime error, device format renegotiation, the box
    // going to sleep) used to be invisible: the writer simply stopped receiving
    // samples, the file ended early, and the user only heard "sound at the start,
    // then nothing". These counters, the periodic flow log and the stall watchdog
    // make that failure observable and recoverable instead of silent.
    private var receivedSampleCount = 0
    private var appendedSampleCount = 0
    private var droppedNotReadyCount = 0
    private var failedAppendCount = 0
    private var lastSampleHostTime: CFAbsoluteTime?
    private var lastFlowLogHostTime: CFAbsoluteTime?
    private var didLogSourceFormat = false
    private var sessionObserverTokens: [NSObjectProtocol] = []
    private var stallWatchdog: DispatchSourceTimer?
    private var recordingDeviceID: String?
    private var hasReportedStall = false
    private var sessionRestartCount = 0

    /// How long the microphone may deliver nothing before the recorder treats the
    /// capture session as stalled and tries to restart it. Audio arrives in ~10ms
    /// buffers, so a second of total silence from the device is already pathological.
    private static let stallThreshold: CFTimeInterval = 1.5
    private static let stallCheckInterval: DispatchTimeInterval = .milliseconds(500)
    private static let flowLogInterval: CFTimeInterval = 5
    /// Restarting is a recovery attempt, not a retry loop: a device that keeps dying
    /// should surface as a stalled recording rather than spin forever.
    private static let maximumSessionRestarts = 5

    var firstSamplePresentationTime: CMTime? { capturedFirstSampleTime }

    func startRecording(deviceID: String, to url: URL, audioChannelMode: AudioChannelMode, completion: @escaping (Result<URL, Error>) -> Void) async throws {
        guard let device = AVCaptureDevice(uniqueID: deviceID) else {
            throw MicrophoneAudioRecorderError.microphoneNotFound
        }

        let input = try AVCaptureDeviceInput(device: device)

        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try SessionConfigurationRunner.configureAndStartIfNeeded(session: self.session) {
                        for existingInput in self.session.inputs {
                            self.session.removeInput(existingInput)
                        }

                        if self.session.outputs.contains(self.audioOutput) == false {
                            self.audioOutput.setSampleBufferDelegate(self, queue: self.outputQueue)
                            guard self.session.canAddOutput(self.audioOutput) else {
                                throw MicrophoneAudioRecorderError.cannotAddMicrophone
                            }
                            self.session.addOutput(self.audioOutput)
                        }

                        guard self.session.canAddInput(input) else {
                            throw MicrophoneAudioRecorderError.cannotAddMicrophone
                        }
                        self.session.addInput(input)
                    }

                    // Use the active output's format recommendation, just as the
                    // camera recorder does. External/USB microphones often expose a
                    // different sample rate or channel layout than the built-in
                    // microphone; hard-coding AAC settings before the output has
                    // started can make the standalone audio-only writer reject or
                    // silently fail to encode those samples.
                    let audioSettings = Self.writerAudioSettings(
                        recommendedSettings: self.audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .m4a),
                        channelMode: audioChannelMode
                    )
                    let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
                    let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                    writerInput.expectsMediaDataInRealTime = true

                    guard writer.canAdd(writerInput) else {
                        throw MicrophoneAudioRecorderError.cannotCreateWriter
                    }
                    writer.add(writerInput)

                    self.audioInput = input
                    self.writer = writer
                    self.writerInput = writerInput
                    self.completion = completion
                    self.outputURL = url
                    self.hasStartedWriting = false
                    self.sampleTracker.reset()
                    self.isStopping = false
                    self.capturedFirstSampleTime = nil
                    self.recordingDeviceID = deviceID
                    self.resetFlowInstrumentation()
                    self.installSessionObservers()
                    self.startStallWatchdog()
                    runtimeDebugLog("Microphone capture started: device=\(device.localizedName) settings=\(audioSettings)")

                    continuation.resume()
                } catch {
                    if self.session.isRunning {
                        self.session.stopRunning()
                    }
                    self.resetState()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopRecording() {
        guard !isStopping else { return }
        isStopping = true
        stopStallWatchdog()
        removeSessionObservers()
        runtimeDebugLog(
            "Microphone capture finished: received=\(receivedSampleCount) appended=\(appendedSampleCount) "
            + "droppedNotReady=\(droppedNotReadyCount) failedAppend=\(failedAppendCount) restarts=\(sessionRestartCount)"
        )

        let currentWriter = writer
        let currentWriterInput = writerInput
        let outputURL = outputURL
        let currentWriterBox = currentWriter.map(UnsafeSendableBox.init)
        let currentWriterInputBox = currentWriterInput.map(UnsafeSendableBox.init)

        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }

            self.writerQueue.asyncAfter(deadline: .now() + Self.finalizeDelay) {
                guard let currentWriter = currentWriterBox?.value, let outputURL else {
                    self.complete(.failure(MicrophoneAudioRecorderError.cannotCreateWriter))
                    return
                }

                guard self.sampleTracker.hasAppendedSample, currentWriter.status == .writing else {
                    currentWriter.cancelWriting()
                    try? FileManager.default.removeItem(at: outputURL)
                    self.complete(.failure(MicrophoneAudioRecorderError.emptyRecording))
                    return
                }

                currentWriterInputBox?.value.markAsFinished()

                let finishedWriterBox = UnsafeSendableBox(value: currentWriter)
                finishedWriterBox.value.finishWriting { [finishedWriterBox] in
                    if let error = finishedWriterBox.value.error {
                        self.complete(.failure(error))
                    } else {
                        self.complete(.success(outputURL))
                    }
                }
            }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        guard let writer, let writerInput else { return }
        let writerBox = UnsafeSendableBox(value: writer)
        let writerInputBox = UnsafeSendableBox(value: writerInput)
        let sampleBufferBox = UnsafeSendableBox(value: sampleBuffer)

        writerQueue.async {
            self.noteSampleArrived(sampleBufferBox.value)

            if !self.hasStartedWriting {
                guard writerBox.value.startWriting() else {
                    self.complete(.failure(writerBox.value.error ?? MicrophoneAudioRecorderError.cannotCreateWriter))
                    return
                }
                writerBox.value.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBufferBox.value))
                self.hasStartedWriting = true
            }
            if self.capturedFirstSampleTime == nil {
                self.capturedFirstSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBufferBox.value)
            }

            guard writerInputBox.value.isReadyForMoreMediaData else {
                // Silently discarding audio here is what makes a stalled encoder look
                // like a dead microphone; count it so the runtime log can tell the two
                // apart.
                self.droppedNotReadyCount += 1
                return
            }
            if writerInputBox.value.append(sampleBufferBox.value) {
                self.sampleTracker.markAppendedSample()
                self.appendedSampleCount += 1
            } else {
                self.failedAppendCount += 1
                if self.failedAppendCount == 1 {
                    runtimeDebugLog(
                        "Microphone capture: first writer append failure at sample \(self.receivedSampleCount), "
                        + "writer status=\(writerBox.value.status.rawValue) error=\(writerBox.value.error?.localizedDescription ?? "none")"
                    )
                }
            }
        }
    }

    // MARK: - Sample-flow instrumentation

    private func resetFlowInstrumentation() {
        receivedSampleCount = 0
        appendedSampleCount = 0
        droppedNotReadyCount = 0
        failedAppendCount = 0
        lastSampleHostTime = nil
        lastFlowLogHostTime = nil
        didLogSourceFormat = false
        hasReportedStall = false
        sessionRestartCount = 0
    }

    /// Called on the writer queue for every buffer the device delivers. Records arrival
    /// time (for the stall watchdog) and periodically logs throughput plus the actual
    /// signal level, so a device that keeps delivering *silence* is distinguishable from
    /// one that stops delivering at all.
    private func noteSampleArrived(_ sampleBuffer: CMSampleBuffer) {
        let now = CFAbsoluteTimeGetCurrent()
        receivedSampleCount += 1
        lastSampleHostTime = now
        hasReportedStall = false

        if !didLogSourceFormat {
            didLogSourceFormat = true
            if let format = CMSampleBufferGetFormatDescription(sampleBuffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                runtimeDebugLog(
                    "Microphone capture source format: \(asbd.mChannelsPerFrame) ch, \(asbd.mSampleRate) Hz, "
                    + "formatID=\(asbd.mFormatID), flags=\(asbd.mFormatFlags)"
                )
            }
        }

        guard let lastFlowLogHostTime else {
            self.lastFlowLogHostTime = now
            return
        }
        guard now - lastFlowLogHostTime >= Self.flowLogInterval else { return }
        self.lastFlowLogHostTime = now
        runtimeDebugLog(
            "Microphone capture flow: received=\(receivedSampleCount) appended=\(appendedSampleCount) "
            + "droppedNotReady=\(droppedNotReadyCount) failedAppend=\(failedAppendCount) "
            + "level=\(String(format: "%.4f", Self.peakLevel(of: sampleBuffer)))"
        )
    }

    /// Peak absolute sample value of a buffer, normalized to 0...1. Only used for the
    /// diagnostic log line, so a cheap best-effort read of the first channel is enough.
    static func peakLevel(of sampleBuffer: CMSampleBuffer) -> Float {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return -1
        }

        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
              let pointer, length > 0 else {
            return -1
        }

        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        var peak: Float = 0
        if isFloat, asbd.mBitsPerChannel == 32 {
            pointer.withMemoryRebound(to: Float.self, capacity: length / MemoryLayout<Float>.size) { samples in
                for index in 0..<(length / MemoryLayout<Float>.size) {
                    peak = max(peak, abs(samples[index]))
                }
            }
        } else if asbd.mBitsPerChannel == 16 {
            pointer.withMemoryRebound(to: Int16.self, capacity: length / MemoryLayout<Int16>.size) { samples in
                for index in 0..<(length / MemoryLayout<Int16>.size) {
                    peak = max(peak, abs(Float(samples[index])) / 32_768)
                }
            }
        } else {
            return -1
        }
        return peak
    }

    // MARK: - Capture-session health

    /// AVCaptureSession reports a mid-session failure (a USB microphone renegotiating
    /// its format, the audio HAL resetting, the device briefly dropping off the bus)
    /// through `runtimeErrorNotification`, and a session that hits one stays stopped
    /// until it is explicitly restarted. Nothing observed these notifications before,
    /// which is precisely how a take could keep "recording" while the microphone had
    /// already stopped feeding it.
    private func installSessionObservers() {
        removeSessionObservers()
        let center = NotificationCenter.default

        let runtimeErrorToken = center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
            runtimeDebugLog("Microphone capture session runtime error: \(error?.localizedDescription ?? "unknown") (code \(error?.code ?? 0))")
            self?.restartSessionAfterFailure(reason: "runtime error")
        }

        let interruptedToken = center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: nil
        ) { _ in
            runtimeDebugLog("Microphone capture session was interrupted")
        }

        let interruptionEndedToken = center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            runtimeDebugLog("Microphone capture session interruption ended")
            self?.restartSessionAfterFailure(reason: "interruption ended")
        }

        let stoppedToken = center.addObserver(
            forName: AVCaptureSession.didStopRunningNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            guard let self, !self.isStopping else { return }
            runtimeDebugLog("Microphone capture session stopped running mid-recording")
            self.restartSessionAfterFailure(reason: "session stopped")
        }

        sessionObserverTokens = [runtimeErrorToken, interruptedToken, interruptionEndedToken, stoppedToken]
    }

    private func removeSessionObservers() {
        for token in sessionObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
        sessionObserverTokens = []
    }

    /// Watches for the microphone going quiet at the *delivery* level (no buffers at
    /// all, as opposed to buffers full of silence) and restarts the capture session
    /// when that happens, so the rest of the take is still recorded instead of the
    /// file simply ending where the device died.
    private func startStallWatchdog() {
        stallWatchdog?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: sessionQueue)
        timer.schedule(deadline: .now() + Self.stallCheckInterval, repeating: Self.stallCheckInterval)
        timer.setEventHandler { [weak self] in
            self?.checkForStall()
        }
        stallWatchdog = timer
        timer.resume()
    }

    private func stopStallWatchdog() {
        stallWatchdog?.cancel()
        stallWatchdog = nil
    }

    private func checkForStall() {
        guard !isStopping else { return }
        // Nothing has arrived yet: startup latency, not a stall. The view model's own
        // first-sample wait already covers a microphone that never starts at all.
        guard let lastSampleHostTime else { return }
        let silentFor = CFAbsoluteTimeGetCurrent() - lastSampleHostTime
        guard silentFor >= Self.stallThreshold, !hasReportedStall else { return }

        hasReportedStall = true
        runtimeDebugLog(
            "Microphone capture stalled: no samples for \(String(format: "%.1f", silentFor))s "
            + "after \(receivedSampleCount) samples; attempting session restart"
        )
        restartSessionAfterFailure(reason: "sample delivery stalled")
    }

    /// Rebuilds and restarts the capture session in place. The asset writer is left
    /// untouched: it keeps its already-written samples and simply resumes receiving new
    /// ones, so a recovered take is continuous rather than split into two files.
    private func restartSessionAfterFailure(reason: String) {
        sessionQueue.async { [weak self] in
            guard let self, !self.isStopping else { return }
            guard self.sessionRestartCount < Self.maximumSessionRestarts else {
                runtimeDebugLog("Microphone capture: restart limit reached, not restarting again (\(reason))")
                return
            }
            self.sessionRestartCount += 1

            // Re-adding the device input matters: after a runtime error the existing
            // input can be bound to a connection the HAL has already torn down, and
            // simply calling startRunning() then yields a running session that never
            // delivers a sample.
            if let deviceID = self.recordingDeviceID,
               let device = AVCaptureDevice(uniqueID: deviceID) {
                self.session.beginConfiguration()
                for existingInput in self.session.inputs {
                    self.session.removeInput(existingInput)
                }
                if let refreshedInput = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(refreshedInput) {
                    self.session.addInput(refreshedInput)
                    self.audioInput = refreshedInput
                }
                self.session.commitConfiguration()
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }
            runtimeDebugLog(
                "Microphone capture session restarted (\(reason), attempt \(self.sessionRestartCount)); "
                + "running=\(self.session.isRunning)"
            )
        }
    }

    /// Keeps the audio-only recorder on the same encoder-negotiation path as camera
    /// recording while retaining the user's explicit mono/stereo preference.
    static func writerAudioSettings(
        recommendedSettings: [String: Any]?,
        channelMode: AudioChannelMode
    ) -> [String: Any] {
        var settings = recommendedSettings ?? [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVEncoderBitRateKey: 128_000,
            AVNumberOfChannelsKey: 1
        ]

        switch channelMode {
        case .automatic:
            break
        case .mono:
            settings[AVNumberOfChannelsKey] = 1
        case .stereo:
            settings[AVNumberOfChannelsKey] = 2
        }

        return settings
    }

    private func complete(_ result: Result<URL, Error>) {
        let completion = completion
        resetState()
        completion?(result)
    }

    private func resetState() {
        stopStallWatchdog()
        removeSessionObservers()
        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }
        session.commitConfiguration()

        audioInput = nil
        writer = nil
        writerInput = nil
        completion = nil
        outputURL = nil
        hasStartedWriting = false
        sampleTracker.reset()
        isStopping = false
        recordingDeviceID = nil
        // `capturedFirstSampleTime` deliberately survives teardown: the export path
        // reads it *after* this recording has completed, to align this component
        // against the session clock. It is cleared at the start of the next take.
    }
}
