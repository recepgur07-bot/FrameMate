@preconcurrency import AVFoundation
import AppKit
import CoreMedia
import Foundation
import ScreenCaptureKit

final class ScreenRecorder: NSObject, ScreenRecordingProviding, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let systemProvider = SystemScreenRecordingProvider()
    private let writerQueue = DispatchQueue(label: "com.local.VideoRecorder.screen-writer")
    private let streamQueue = DispatchQueue(label: "com.local.VideoRecorder.screen-stream")

    private var stream: SCStream?
    private var recordingOutput: NSObject?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var hasStartedWriting = false
    private var hasReceivedVideoFrame = false
    private var outputURL: URL?
    private var isStopping = false

    func authorizationStatus() -> ScreenRecordingAuthorizationStatus {
        systemProvider.authorizationStatus()
    }

    func requestAccess() async -> ScreenRecordingPermissionRequestResult {
        await systemProvider.requestAccess()
    }

    func availableDisplays() async throws -> [ScreenDisplayOption] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.displays.map { display in
            let frame = NSScreen.screens.first { screen in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                    return false
                }
                return String(number.uint32Value) == String(display.displayID)
            }?.frame ?? .zero
            return ScreenDisplayOption(
                id: String(display.displayID),
                name: "Ekran \(display.displayID)",
                frame: frame
            )
        }
    }

    func availableWindows() async throws -> [ScreenWindowOption] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        return content.windows
            .filter { window in
                guard let title = window.title, !title.isEmpty else { return false }
                return true
            }
            .map { window in
                let appName = window.owningApplication?.applicationName ?? "Uygulama"
                let title = window.title ?? "Adsiz pencere"
                return ScreenWindowOption(
                    id: String(window.windowID),
                    name: "\(appName) - \(title)",
                    frame: window.frame
                )
            }
    }

    func startRecording(
        target: ScreenRecordingTarget,
        microphoneDeviceID: String,
        includeSystemAudio: Bool,
        to url: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let filter = try contentFilter(for: target, content: content)
        let size = captureSize(for: target, content: content)
        let configuration = Self.makeStreamConfiguration(
            size: size,
            microphoneDeviceID: microphoneDeviceID,
            includeSystemAudio: includeSystemAudio
        )
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)

        self.stream = stream
        self.completion = completion
        self.outputURL = url
        hasStartedWriting = false
        hasReceivedVideoFrame = false
        isStopping = false

        if #available(macOS 15.0, *) {
            let recordingOutput = Self.makeRecordingOutput(
                url: url,
                delegate: self
            )
            do {
                try stream.addRecordingOutput(recordingOutput)
                self.recordingOutput = recordingOutput
            } catch {
                resetState()
                throw error
            }
        } else {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let videoInput = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: size.width,
                    AVVideoHeightKey: size.height
                ]
            )
            videoInput.expectsMediaDataInRealTime = true

            guard writer.canAdd(videoInput) else {
                resetState()
                throw ScreenRecordingError.cannotCreateWriter
            }

            writer.add(videoInput)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: streamQueue)
            self.writer = writer
            self.videoInput = videoInput
        }

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

        if #available(macOS 15.0, *), recordingOutput != nil {
            let currentStream = stream
            let currentOutputURL = outputURL
            Task {
                do {
                    try await currentStream?.stopCapture()
                    runtimeDebugLog("ScreenRecorder stopCapture completed for \(currentOutputURL?.path ?? "<nil>")")
                    await self.finishMacOS15RecordingIfNeeded(outputURL: currentOutputURL)
                } catch {
                    runtimeDebugLog("ScreenRecorder stopCapture failed: \(error.localizedDescription)")
                    self.complete(.failure(error))
                }
            }
            return
        }

        let currentStream = stream
        let currentWriter = writer
        let currentVideoInput = videoInput
        let outputURL = outputURL
        let hasVideo = hasReceivedVideoFrame

        Task {
            do {
                try await currentStream?.stopCapture()
            } catch {}

            writerQueue.async {
                currentVideoInput?.markAsFinished()

                guard let currentWriter, let outputURL else {
                    self.complete(.failure(ScreenRecordingError.cannotCreateWriter))
                    return
                }

                guard hasVideo else {
                    currentWriter.cancelWriting()
                    try? FileManager.default.removeItem(at: outputURL)
                    self.complete(.failure(ScreenRecordingError.emptyRecording))
                    return
                }

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
        guard outputType == .screen else { return }
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        guard let writer, let videoInput else { return }

        writerQueue.async {
            if !self.hasStartedWriting {
                writer.startWriting()
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                self.hasStartedWriting = true
            }

            guard videoInput.isReadyForMoreMediaData else { return }
            self.hasReceivedVideoFrame = true
            videoInput.append(sampleBuffer)
        }
    }

    private func contentFilter(for target: ScreenRecordingTarget, content: SCShareableContent) throws -> SCContentFilter {
        switch target {
        case .display(let id):
            guard let display = content.displays.first(where: { String($0.displayID) == id }) else {
                throw ScreenRecordingError.displayNotFound
            }
            return SCContentFilter(display: display, excludingWindows: [])
        case .window(let id):
            guard let window = content.windows.first(where: { String($0.windowID) == id }) else {
                throw ScreenRecordingError.windowNotFound
            }
            return SCContentFilter(desktopIndependentWindow: window)
        }
    }

    private func captureSize(for target: ScreenRecordingTarget, content: SCShareableContent) -> (width: Int, height: Int) {
        switch target {
        case .display(let id):
            if let display = content.displays.first(where: { String($0.displayID) == id }) {
                return (max(2, Int(display.width)), max(2, Int(display.height)))
            }
        case .window(let id):
            if let window = content.windows.first(where: { String($0.windowID) == id }) {
                return (max(2, Int(window.frame.width)), max(2, Int(window.frame.height)))
            }
        }

        return (1920, 1080)
    }

    static func makeStreamConfiguration(
        size: (width: Int, height: Int),
        microphoneDeviceID: String,
        includeSystemAudio: Bool
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 6
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.capturesAudio = includeSystemAudio

        if #available(macOS 15.0, *) {
            configuration.captureMicrophone = false
            configuration.microphoneCaptureDeviceID = nil
        }

        return configuration
    }

    @available(macOS 15.0, *)
    private static func makeRecordingOutput(
        url: URL,
        delegate: SCRecordingOutputDelegate
    ) -> SCRecordingOutput {
        let configuration = SCRecordingOutputConfiguration()
        configuration.outputURL = url
        configuration.videoCodecType = .h264
        configuration.outputFileType = .mov
        return SCRecordingOutput(configuration: configuration, delegate: delegate)
    }

    private func complete(_ result: Result<URL, Error>) {
        guard let completion else { return }
        self.completion = nil
        switch result {
        case .success(let url):
            runtimeDebugLog("ScreenRecorder completed successfully: \(url.path)")
        case .failure(let error):
            runtimeDebugLog("ScreenRecorder completed with error: \(error.localizedDescription)")
        }
        completion(result)
        resetState()
    }

    private func finishMacOS15RecordingIfNeeded(outputURL: URL?) async {
        var previousSize: Int64?

        for _ in 0..<10 {
            guard completion != nil else { return }
            try? await Task.sleep(for: .milliseconds(200))

            guard completion != nil else { return }
            let currentSize = Self.recordingFileSize(at: outputURL)
            if let currentSize, currentSize > 0, previousSize == currentSize,
               let outputURL {
                runtimeDebugLog("ScreenRecorder using stop fallback with stable file size \(currentSize)")
                complete(.success(outputURL))
                return
            }
            previousSize = currentSize
        }

        guard completion != nil, let fallback = Self.fallbackStopResult(for: outputURL) else { return }
        runtimeDebugLog("ScreenRecorder using final stop fallback for \(outputURL?.path ?? "<nil>")")
        complete(fallback)
    }

    static func fallbackStopResult(for outputURL: URL?, fileManager: FileManager = .default) -> Result<URL, Error>? {
        guard let outputURL else { return nil }
        guard let size = recordingFileSize(at: outputURL, fileManager: fileManager) else { return nil }
        if size > 0 {
            return .success(outputURL)
        }
        return .failure(ScreenRecordingError.emptyRecording)
    }

    private static func recordingFileSize(at outputURL: URL?, fileManager: FileManager = .default) -> Int64? {
        guard let outputURL,
              let attributes = try? fileManager.attributesOfItem(atPath: outputURL.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.int64Value
    }

    private func resetState() {
        stream = nil
        recordingOutput = nil
        writer = nil
        videoInput = nil
        completion = nil
        outputURL = nil
        hasStartedWriting = false
        hasReceivedVideoFrame = false
        isStopping = false
    }
}

@available(macOS 15.0, *)
extension ScreenRecorder: SCRecordingOutputDelegate {
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        guard let outputURL else {
            complete(.failure(ScreenRecordingError.cannotCreateWriter))
            return
        }
        complete(.success(outputURL))
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        complete(.failure(error))
    }
}
