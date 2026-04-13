@preconcurrency import AVFoundation
import Foundation
import ScreenCaptureKit

protocol SystemAudioRecordingProviding: AnyObject {
    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) async throws
    func stopRecording()
}

final class SystemAudioRecorder: NSObject, SystemAudioRecordingProviding, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let streamQueue = DispatchQueue(label: "com.local.VideoRecorder.system-audio-stream")
    private let writerQueue = DispatchQueue(label: "com.local.VideoRecorder.system-audio-writer")

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var outputURL: URL?
    private var hasStartedWriting = false
    private var hasReceivedAudioSample = false
    private var isStopping = false

    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw ScreenRecordingError.displayNotFound
        }

        let configuration = Self.makeStreamConfiguration()
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: 128_000,
                AVNumberOfChannelsKey: 2
            ]
        )
        audioInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(audioInput) else {
            throw ScreenRecordingError.cannotCreateWriter
        }

        writer.add(audioInput)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: streamQueue)

        self.stream = stream
        self.writer = writer
        self.audioInput = audioInput
        self.completion = completion
        self.outputURL = url
        hasStartedWriting = false
        hasReceivedAudioSample = false
        isStopping = false

        do {
            try await stream.startCapture()
        } catch {
            resetState()
            throw error
        }
    }

    func stopRecording() {
        guard !isStopping else { return }
        isStopping = true

        let currentStream = stream
        let currentWriter = writer
        let currentAudioInput = audioInput
        let outputURL = outputURL
        let hasAudio = hasReceivedAudioSample

        Task {
            do {
                try await currentStream?.stopCapture()
            } catch {}

            writerQueue.async {
                guard let currentWriter, let outputURL else {
                    self.complete(.failure(ScreenRecordingError.cannotCreateWriter))
                    return
                }

                guard hasAudio, self.hasStartedWriting, currentWriter.status == .writing else {
                    currentWriter.cancelWriting()
                    try? FileManager.default.removeItem(at: outputURL)
                    self.complete(.failure(ScreenRecordingError.emptyRecording))
                    return
                }

                currentAudioInput?.markAsFinished()

                currentWriter.finishWriting {
                    if let error = currentWriter.error {
                        self.complete(.failure(error))
                    } else {
                        self.complete(.success(outputURL))
                    }
                }
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        complete(.failure(error))
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio else { return }
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        guard let writer, let audioInput else { return }

        writerQueue.async {
            if !self.hasStartedWriting {
                writer.startWriting()
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                self.hasStartedWriting = true
            }

            guard audioInput.isReadyForMoreMediaData else { return }
            self.hasReceivedAudioSample = true
            audioInput.append(sampleBuffer)
        }
    }

    static func makeStreamConfiguration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 6
        configuration.capturesAudio = true
        configuration.showsCursor = false
        return configuration
    }

    private func complete(_ result: Result<URL, Error>) {
        let completion = completion
        resetState()
        completion?(result)
    }

    private func resetState() {
        stream = nil
        writer = nil
        audioInput = nil
        completion = nil
        outputURL = nil
        hasStartedWriting = false
        hasReceivedAudioSample = false
        isStopping = false
    }
}
