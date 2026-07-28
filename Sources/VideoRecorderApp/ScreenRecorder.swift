@preconcurrency import AVFoundation
import AppKit
import CoreMedia
import Foundation
import ScreenCaptureKit

private struct UnsafeSendableBox<Value>: @unchecked Sendable {
    let value: Value
}

final class ScreenRecorder: NSObject, ScreenRecordingProviding, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private static let finalizeDelay: DispatchTimeInterval = .milliseconds(250)
    private let systemProvider = SystemScreenRecordingProvider()
    private let writerQueue = DispatchQueue(label: "com.local.VideoRecorder.screen-writer")
    private let streamQueue = DispatchQueue(label: "com.local.VideoRecorder.screen-stream")

    private var stream: SCStream?
    private var recordingOutput: NSObject?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var hasStartedWriting = false
    private let sampleTracker = RecordingSampleTracker()
    private var outputURL: URL?
    private var isStopping = false
    private var prefetchedContentTask: Task<SCShareableContent, Error>?
    private var capturedFirstSampleTime: CMTime?
    private var observationStreamOutputAdded = false

    var firstSamplePresentationTime: CMTime? { capturedFirstSampleTime }

    func prefetchShareableContent() {
        guard prefetchedContentTask == nil else { return }
        runtimeDebugLog("ScreenCaptureKit content prefetch requested")
        prefetchedContentTask = Task {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            runtimeDebugLog("ScreenCaptureKit content prefetch completed")
            return content
        }
    }

    private func resolvedShareableContent() async throws -> SCShareableContent {
        if let task = prefetchedContentTask {
            prefetchedContentTask = nil
            runtimeDebugLog("ScreenCaptureKit recording start is using prefetched content")
            return try await task.value
        }
        runtimeDebugLog("ScreenCaptureKit recording start has no prefetched content")
        return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

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
                name: String(format: String(localized: "Ekran %@"), String(display.displayID)),
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
                let title = window.title ?? String(localized: "Adsız pencere")
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
        let content = try await resolvedShareableContent()
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
        sampleTracker.reset()
        isStopping = false
        capturedFirstSampleTime = nil
        observationStreamOutputAdded = false

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
            // SCRecordingOutput writes the file itself and gives us no per-sample
            // visibility, so we cannot otherwise learn when the primary component's
            // first sample actually landed (RecordingSessionClock's session zero) or
            // measure how that compares to the file's own first frame (Phase 4). This
            // observation-only stream output is best-effort: if it fails to attach we
            // still record, we just cannot resolve a session clock for this mode.
            do {
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: streamQueue)
                observationStreamOutputAdded = true
            } catch {
                runtimeDebugLog("ScreenRecorder could not attach observation stream output: \(error.localizedDescription)")
            }
        } else {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let videoInput = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.hevc,
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
        let currentWriterBox = currentWriter.map(UnsafeSendableBox.init)
        let currentVideoInputBox = currentVideoInput.map(UnsafeSendableBox.init)

        Task {
            do {
                try await currentStream?.stopCapture()
            } catch {}

            writerQueue.asyncAfter(deadline: .now() + Self.finalizeDelay) {
                currentVideoInputBox?.value.markAsFinished()

                guard let currentWriter = currentWriterBox?.value, let outputURL else {
                    self.complete(.failure(ScreenRecordingError.cannotCreateWriter))
                    return
                }

                guard self.sampleTracker.hasAppendedSample else {
                    currentWriter.cancelWriting()
                    try? FileManager.default.removeItem(at: outputURL)
                    self.complete(.failure(ScreenRecordingError.emptyRecording))
                    return
                }

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
        guard outputType == .screen else { return }
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        // ScreenCaptureKit delivers idle/duplicate frames alongside real ones; only a
        // `.complete` frame is an actual new sample, so this is the gate the first-sample
        // timestamp (and, on the pre-15 path, the writer) must be based on.
        guard Self.frameStatus(of: sampleBuffer) == .complete else { return }

        if capturedFirstSampleTime == nil {
            capturedFirstSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        }

        guard let writer, let videoInput else { return }
        let writerBox = UnsafeSendableBox(value: writer)
        let videoInputBox = UnsafeSendableBox(value: videoInput)
        let sampleBufferBox = UnsafeSendableBox(value: sampleBuffer)

        writerQueue.async {
            if !self.hasStartedWriting {
                writerBox.value.startWriting()
                writerBox.value.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBufferBox.value))
                self.hasStartedWriting = true
            }

            guard videoInputBox.value.isReadyForMoreMediaData else { return }
            if videoInputBox.value.append(sampleBufferBox.value) {
                self.sampleTracker.markAppendedSample()
            }
        }
    }

    /// Reads ScreenCaptureKit's own completeness signal off the sample buffer's
    /// attachments. Returns `nil` (treated as "not complete") if the attachment is
    /// missing rather than assuming the frame is usable — Phase 4.1's "measure, don't
    /// guess" applies here too.
    private static func frameStatus(of sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let statusRawValue = attachments[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRawValue) else {
            return nil
        }
        return status
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
        configuration.videoCodecType = .hevc
        configuration.outputFileType = .mov
        return SCRecordingOutput(configuration: configuration, delegate: delegate)
    }

    private func complete(_ result: Result<URL, Error>) {
        // resetState() (which clears isStopping) must run on every call to complete(),
        // even a redundant one that arrives after the completion handler was already
        // consumed — otherwise a second completion source (e.g. the stop-fallback poll
        // racing the SCRecordingOutput delegate) leaves isStopping latched forever and
        // the next stopRecording() call becomes a silent no-op.
        let completionToInvoke = completion
        completion = nil
        defer { resetState() }

        guard let completionToInvoke else { return }
        switch result {
        case .success(let url):
            runtimeDebugLog("ScreenRecorder completed successfully: \(url.path)")
            Self.logFinalizedFirstFramePTSDiscrepancy(at: url, observedFirstSampleTime: capturedFirstSampleTime)
        case .failure(let error):
            runtimeDebugLog("ScreenRecorder completed with error: \(error.localizedDescription)")
        }
        completionToInvoke(result)
    }

    /// Reads the finalized file's own first video sample time back from disk and logs how
    /// it compares to the first-sample time we observed live during capture. This is a
    /// measurement only (Phase 4 of the recording-timing fix): it does not correct
    /// anything, it exists so a residual offset between the two is visible in
    /// `runtimeDebugLog` instead of silently assumed away.
    private static func logFinalizedFirstFramePTSDiscrepancy(at url: URL, observedFirstSampleTime: CMTime?) {
        guard let observedFirstSampleTime, observedFirstSampleTime.isValid else { return }
        Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let timeRange = try? await track.load(.timeRange) else {
                return
            }
            let realFirstFramePTS = timeRange.start
            let deltaSeconds = (realFirstFramePTS - observedFirstSampleTime).seconds
            runtimeDebugLog(
                "ScreenRecorder finalized file first frame PTS \(realFirstFramePTS.seconds)s vs. observed first sample \(observedFirstSampleTime.seconds)s (delta \(deltaSeconds)s) — measurement only, not auto-corrected"
            )
        }
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

        guard completion != nil else { return }
        // fallbackStopResult can return nil (missing/unreadable file); complete() must
        // still be reached in that case, or isStopping stays latched forever — see the
        // comment in complete() for why this is the failure mode this guards against.
        let fallback = Self.fallbackStopResult(for: outputURL) ?? .failure(ScreenRecordingError.emptyRecording)
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
        sampleTracker.reset()
        isStopping = false
    }
}

#if DEBUG
extension ScreenRecorder {
    /// Test-only seam: simulates a recorder stuck mid-stop (isStopping latched, a
    /// completion handler still pending) without needing a real SCStream, so the
    /// stuck-latch regression from `complete()` can be exercised directly.
    func simulateStuckStopForTesting() {
        isStopping = true
        completion = { _ in }
    }

    func triggerCompleteForTesting(_ result: Result<URL, Error>) {
        complete(result)
    }

    var isStoppingForTesting: Bool { isStopping }
}
#endif

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
