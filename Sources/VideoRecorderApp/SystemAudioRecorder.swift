@preconcurrency import AVFoundation
import Foundation
import ScreenCaptureKit

protocol SystemAudioRecordingProviding: AnyObject {
    /// Kicks off the slow ScreenCaptureKit shareable-content enumeration ahead of time so
    /// `startRecording` doesn't have to pay for it after the user has already heard the
    /// "recording started" cue. Best-effort; safe to skip or call more than once.
    func prefetchShareableContent()
    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) async throws
    func stopRecording()
}

extension SystemAudioRecordingProviding {
    func prefetchShareableContent() {}
}

private struct UnsafeSendableBox<Value>: @unchecked Sendable {
    let value: Value
}

final class SystemAudioRecorder: NSObject, SystemAudioRecordingProviding, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private static let finalizeDelay: DispatchTimeInterval = .milliseconds(250)
    private let streamQueue = DispatchQueue(label: "com.local.VideoRecorder.system-audio-stream")
    private let writerQueue = DispatchQueue(label: "com.local.VideoRecorder.system-audio-writer")

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var outputURL: URL?
    private var hasStartedWriting = false
    private let sampleTracker = RecordingSampleTracker()
    private var isStopping = false
    private var prefetchedContentTask: Task<SCShareableContent, Error>?

    func prefetchShareableContent() {
        guard prefetchedContentTask == nil else { return }
        prefetchedContentTask = Task {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
    }

    private func resolvedShareableContent() async throws -> SCShareableContent {
        if let task = prefetchedContentTask {
            prefetchedContentTask = nil
            return try await task.value
        }
        return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    func startRecording(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) async throws {
        let content = try await resolvedShareableContent()
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
        sampleTracker.reset()
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
        let currentWriterBox = currentWriter.map(UnsafeSendableBox.init)
        let currentAudioInputBox = currentAudioInput.map(UnsafeSendableBox.init)

        Task {
            do {
                try await currentStream?.stopCapture()
            } catch {}

            writerQueue.asyncAfter(deadline: .now() + Self.finalizeDelay) {
                guard let currentWriter = currentWriterBox?.value, let outputURL else {
                    self.complete(.failure(ScreenRecordingError.cannotCreateWriter))
                    return
                }

                guard self.sampleTracker.hasAppendedSample, self.hasStartedWriting, currentWriter.status == .writing else {
                    currentWriter.cancelWriting()
                    try? FileManager.default.removeItem(at: outputURL)
                    self.complete(.failure(ScreenRecordingError.emptyRecording))
                    return
                }

                currentAudioInputBox?.value.markAsFinished()

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

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        complete(.failure(error))
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio else { return }
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        guard let writer, let audioInput else { return }
        let writerBox = UnsafeSendableBox(value: writer)
        let audioInputBox = UnsafeSendableBox(value: audioInput)
        let sampleBufferBox = UnsafeSendableBox(value: sampleBuffer)

        writerQueue.async {
            if !self.hasStartedWriting {
                writerBox.value.startWriting()
                writerBox.value.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBufferBox.value))
                self.hasStartedWriting = true
            }

            guard audioInputBox.value.isReadyForMoreMediaData else { return }
            if audioInputBox.value.append(sampleBufferBox.value) {
                self.sampleTracker.markAppendedSample()
            }
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
        sampleTracker.reset()
        isStopping = false
    }
}
