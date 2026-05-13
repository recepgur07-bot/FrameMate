@preconcurrency import AVFoundation
import Foundation

private struct UnsafeSendableBox<Value>: @unchecked Sendable {
    let value: Value
}

protocol MicrophoneAudioRecordingProviding: AnyObject {
    func startRecording(deviceID: String, to url: URL, completion: @escaping (Result<URL, Error>) -> Void) async throws
    func stopRecording()
}

enum MicrophoneAudioRecorderError: LocalizedError, Equatable {
    case microphoneNotFound
    case cannotAddMicrophone
    case cannotCreateWriter
    case emptyRecording

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

    func startRecording(deviceID: String, to url: URL, completion: @escaping (Result<URL, Error>) -> Void) async throws {
        guard let device = AVCaptureDevice(uniqueID: deviceID) else {
            throw MicrophoneAudioRecorderError.microphoneNotFound
        }

        let input = try AVCaptureDeviceInput(device: device)
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: 128_000,
                AVNumberOfChannelsKey: 1
            ]
        )
        writerInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(writerInput) else {
            throw MicrophoneAudioRecorderError.cannotCreateWriter
        }
        writer.add(writerInput)
        let writerBox = UnsafeSendableBox(value: writer)
        let writerInputBox = UnsafeSendableBox(value: writerInput)

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

                        self.audioInput = input
                        self.writer = writerBox.value
                        self.writerInput = writerInputBox.value
                        self.completion = completion
                        self.outputURL = url
                        self.hasStartedWriting = false
                        self.sampleTracker.reset()
                        self.isStopping = false
                    }

                    continuation.resume()
                } catch {
                    self.resetState()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopRecording() {
        guard !isStopping else { return }
        isStopping = true

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
            if !self.hasStartedWriting {
                writerBox.value.startWriting()
                writerBox.value.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBufferBox.value))
                self.hasStartedWriting = true
            }

            guard writerInputBox.value.isReadyForMoreMediaData else { return }
            if writerInputBox.value.append(sampleBufferBox.value) {
                self.sampleTracker.markAppendedSample()
            }
        }
    }

    private func complete(_ result: Result<URL, Error>) {
        let completion = completion
        resetState()
        completion?(result)
    }

    private func resetState() {
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
    }
}
