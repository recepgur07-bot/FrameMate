import AVFoundation
import CoreMedia
import XCTest
@testable import FrameMate

final class ScreenCameraOverlayCompositionBuilderTests: XCTestCase {
    func testTargetRenderSizeMatchesHorizontal1080Preset() {
        let builder = ScreenCameraOverlayCompositionBuilder()

        XCTAssertEqual(
            builder.targetRenderSize(for: .horizontal1080p),
            CGSize(width: 1920, height: 1080)
        )
    }

    func testFittedVideoFramePreservesAspectRatioInsideTargetCanvas() {
        let builder = ScreenCameraOverlayCompositionBuilder()

        let frame = builder.fittedVideoFrame(
            contentSize: CGSize(width: 1280, height: 832),
            in: CGSize(width: 1920, height: 1080)
        )

        XCTAssertEqual(frame.height, 1080, accuracy: 1)
        XCTAssertEqual(frame.midX, 960, accuracy: 1)
        XCTAssertLessThan(frame.width, 1920)
    }

    func testBottomRightFrameStaysInsideLandscapeRenderSize() {
        let builder = ScreenCameraOverlayCompositionBuilder()

        let frame = builder.overlayFrame(
            in: CGSize(width: 1920, height: 1080),
            position: .bottomRight,
            size: .medium
        )

        XCTAssertGreaterThan(frame.minX, 0)
        XCTAssertGreaterThan(frame.minY, 0)
        XCTAssertLessThan(frame.maxX, 1920)
        XCTAssertLessThan(frame.maxY, 1080)
    }

    func testCenterFrameIsCenteredInVerticalRenderSize() {
        let builder = ScreenCameraOverlayCompositionBuilder()

        let frame = builder.overlayFrame(
            in: CGSize(width: 1080, height: 1920),
            position: .center,
            size: .medium
        )

        XCTAssertEqual(frame.midX, 540, accuracy: 1)
        XCTAssertEqual(frame.midY, 960, accuracy: 1)
    }

    func testTopRightFrameSitsHigherThanBottomRightFrame() {
        let builder = ScreenCameraOverlayCompositionBuilder()

        let topRight = builder.overlayFrame(
            in: CGSize(width: 1920, height: 1080),
            position: .topRight,
            size: .medium
        )
        let bottomRight = builder.overlayFrame(
            in: CGSize(width: 1920, height: 1080),
            position: .bottomRight,
            size: .medium
        )

        XCTAssertLessThan(topRight.minY, bottomRight.minY)
        XCTAssertEqual(topRight.maxX, bottomRight.maxX, accuracy: 1)
    }

    func testLargeOverlayFrameIsBiggerThanSmallOverlayFrame() {
        let builder = ScreenCameraOverlayCompositionBuilder()

        let small = builder.overlayFrame(
            in: CGSize(width: 1920, height: 1080),
            position: .bottomRight,
            size: .small
        )
        let large = builder.overlayFrame(
            in: CGSize(width: 1920, height: 1080),
            position: .bottomRight,
            size: .large
        )

        XCTAssertGreaterThan(large.width, small.width)
        XCTAssertGreaterThan(large.height, small.height)
    }

    func testMediumLandscapeOverlayIsMoreConservativeThanLegacySizing() {
        let builder = ScreenCameraOverlayCompositionBuilder()

        let frame = builder.overlayFrame(
            in: CGSize(width: 1920, height: 1080),
            position: .topRight,
            size: .medium
        )

        XCTAssertLessThan(frame.width, 430)
        XCTAssertLessThan(frame.height, 250)
    }

    func testCursorSampleMapsIntoRenderedScreenFrame() {
        let builder = ScreenCameraOverlayCompositionBuilder()
        let screenFrame = CGRect(x: 129.2307692308, y: 0, width: 1661.5384615385, height: 1080)
        let sample = CursorSample(timestamp: 1.2, normalizedX: 0.5, normalizedY: 0.25)

        let point = builder.cursorRenderPoint(for: sample, in: screenFrame)

        XCTAssertEqual(point.x, screenFrame.midX, accuracy: 0.5)
        XCTAssertEqual(point.y, screenFrame.minY + screenFrame.height * 0.25, accuracy: 0.5)
    }

    func testCursorClickEventsCreateExtraDecorationLayers() {
        let builder = ScreenCameraOverlayCompositionBuilder()
        let timeline = CursorHighlightTimeline(
            samples: [CursorSample(timestamp: 0, normalizedX: 0.4, normalizedY: 0.6)],
            clickEvents: [CursorClickEvent(timestamp: 0.2, normalizedX: 0.4, normalizedY: 0.6)]
        )

        let layerCount = builder.cursorDecorationLayerCount(
            in: CGSize(width: 1920, height: 1080),
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            timeline: timeline
        )

        XCTAssertEqual(layerCount, 2)
    }

    func testKeyboardShortcutEventsCreateDecorationLayers() {
        let builder = ScreenCameraOverlayCompositionBuilder()
        let timeline = KeyboardShortcutTimeline(
            events: [KeyboardShortcutEvent(timestamp: 0.3, label: "⌘ K")]
        )

        let layerCount = builder.keyboardShortcutDecorationLayerCount(
            in: CGSize(width: 1920, height: 1080),
            timeline: timeline
        )

        XCTAssertEqual(layerCount, 1)
    }

    func testFilledVideoFrameExpandsToFillCanvasHeight() {
        // Vertical screen: 1920x1080 source into 1080x1920 canvas
        // Fill scale = 1920/1080 = 1.778 (height fills canvas height)
        // Filled width = 1920 * 1.778 = 3413 (wider than canvas)
        let builder = ScreenCameraOverlayCompositionBuilder()
        let frame = builder.filledVideoFrame(
            contentSize: CGSize(width: 1920, height: 1080),
            in: CGSize(width: 1080, height: 1920)
        )
        XCTAssertEqual(frame.height, 1920, accuracy: 1)  // fills canvas height
        XCTAssertGreaterThan(frame.width, 1080)           // wider than canvas (will be cropped)
        XCTAssertLessThan(frame.minX, 0)                  // extends beyond left edge
        XCTAssertEqual(frame.midX, 540, accuracy: 1)      // centered horizontally
    }

    func testFilledVideoFrameForSquareSourceEqualsCanvas() {
        let builder = ScreenCameraOverlayCompositionBuilder()
        let frame = builder.filledVideoFrame(
            contentSize: CGSize(width: 100, height: 100),
            in: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(frame.origin.x, 0, accuracy: 1)
        XCTAssertEqual(frame.origin.y, 0, accuracy: 1)
        XCTAssertEqual(frame.width, 100, accuracy: 1)
        XCTAssertEqual(frame.height, 100, accuracy: 1)
    }

    func testVerticalScreenModeUsesFilledFrameNotFittedFrame() {
        // Vertical screen should fill the canvas (no black bars), not fit (pillarbox)
        let builder = ScreenCameraOverlayCompositionBuilder()
        let renderSize = RecordingMode.vertical1080p.renderSize  // 1080x1920
        let screenSourceSize = CGSize(width: 1920, height: 1080)

        let filledFrame = builder.filledVideoFrame(contentSize: screenSourceSize, in: renderSize)
        let fittedFrame = builder.fittedVideoFrame(contentSize: screenSourceSize, in: renderSize)

        // Fill: height = 1920, no black bands
        XCTAssertEqual(filledFrame.height, 1920, accuracy: 1)
        // Fit: height < 1920, has black bands
        XCTAssertLessThan(fittedFrame.height, 1920)
    }

    // Phase 3 fixture: primary's first sample lands at session zero, a secondary
    // component's first sample lands 10s later (offsetSeconds = 10), and the session was
    // paused for [20, 25]. The secondary's own asset must be cut at its *local* time
    // ([10, 15], i.e. the pause shifted 10s earlier), and — because every track in the
    // merged output shares one timeline — its resumed content must land at the exact same
    // output position the primary's own (untouched) `segments(for:)` already places its own
    // post-pause content at, not at some offset-relative position of its own.
    func testSecondaryTrackAlignmentCutsInLocalTimeAndPlacesOnSharedOutputTimeline() {
        var pauseTimeline = RecordingPauseTimeline()
        pauseTimeline.ranges = [RecordingPauseRange(start: 20, end: 25)]
        let sourceDuration = CMTime(seconds: 50, preferredTimescale: 600)

        // Ground truth: this is what the *primary* (offset 0) gets from the pause
        // timeline's own unmodified segments(for:) — the resumed segment after a [20,25]
        // pause must land at output position 20 (25 - 5s removed), not 10.
        let primarySegments = pauseTimeline.segments(for: sourceDuration)
        let primaryResumedSegment = try! XCTUnwrap(primarySegments.last)
        XCTAssertEqual(primaryResumedSegment.destinationStart.seconds, 20, accuracy: 0.01)

        let secondarySegments = pauseTimeline.segments(for: sourceDuration, offsetSeconds: 10)
        XCTAssertEqual(secondarySegments.count, 2)

        let localCut = secondarySegments[0]
        XCTAssertEqual(localCut.sourceRange.start.seconds, 0, accuracy: 0.01)
        XCTAssertEqual(localCut.sourceRange.duration.seconds, 10, accuracy: 0.01, "content before the pause, in the secondary's own local time, is [0,10)")

        let resumedSegment = secondarySegments[1]
        XCTAssertEqual(resumedSegment.sourceRange.start.seconds, 15, accuracy: 0.01, "resumes at local time 15 (the pause shifted 10s earlier: [10,15])")
        XCTAssertEqual(
            resumedSegment.destinationStart.seconds, 20, accuracy: 0.01,
            "must land at the same shared output position as the primary's own post-pause content (20s), not at a position relative only to this component's own offset"
        )
    }

    // Regression: the camera overlay's own file reliably starts later (warm-up gate,
    // positive offset) and ends later (writer drain) than the screen capture. Before the
    // clamping fix, the overlay composition track extended past the last video
    // composition instruction, which invalidates the whole composition —
    // AVAssetExportSession then fails with AVErrorInvalidVideoComposition (-11841,
    // "Video oluşturulamadı") and the user gets a screen-only video with no camera box.
    func testOverlayLongerThanScreenYieldsGaplessInstructionsCoveringWholeComposition() async throws {
        let builder = ScreenCameraOverlayCompositionBuilder()
        let screenAsset = try await makeSolidColorVideoAsset(durationSeconds: 1.0)
        let overlayAsset = try await makeSolidColorVideoAsset(durationSeconds: 2.0)

        let result = try await builder.makeComposition(
            screenAsset: screenAsset,
            mode: .horizontal1080p,
            overlayAsset: overlayAsset,
            overlayOffsetSeconds: 0.4
        )

        let compositionDuration = try await result.composition.load(.duration)
        let instructions = result.videoComposition.instructions.compactMap {
            $0 as? AVVideoCompositionInstruction
        }
        XCTAssertEqual(instructions.count, result.videoComposition.instructions.count)
        XCTAssertFalse(instructions.isEmpty)

        // Instructions must be gapless and overlap-free from zero...
        var cursor = CMTime.zero
        for instruction in instructions {
            XCTAssertEqual(
                instruction.timeRange.start, cursor,
                "instructions must be contiguous — a gap or overlap invalidates the composition"
            )
            cursor = instruction.timeRange.end
        }
        // ...through the very end of the composition; any uncovered tail is -11841.
        XCTAssertGreaterThanOrEqual(cursor, compositionDuration)

        // No video track may outlive the covered range either — the overlay (2s, offset
        // 0.4s) must have been clamped to the screen's visible end (1s).
        for track in try await result.composition.loadTracks(withMediaType: .video) {
            let range = try await track.load(.timeRange)
            XCTAssertLessThanOrEqual(range.end, cursor)
        }
        XCTAssertEqual(compositionDuration.seconds, 1.0, accuracy: 0.15, "the export must end when the screen content ends")

        // The overlay must actually be composited (an instruction with both layers), and
        // the head before its first frame (~0.4s) must be screen-only rather than
        // referencing an overlay track that has no media yet.
        XCTAssertTrue(instructions.contains { $0.layerInstructions.count == 2 })
        XCTAssertEqual(instructions.first?.layerInstructions.count, 1, "overlay starts later than the screen; the head must be screen-only")
    }

    // The same guarantee when the overlay is *shorter* than the screen: overlay+screen
    // middle, then a screen-only tail out to the screen's end — still gapless.
    func testOverlayShorterThanScreenStillCoversWholeCompositionWithScreenOnlyTail() async throws {
        let builder = ScreenCameraOverlayCompositionBuilder()
        let screenAsset = try await makeSolidColorVideoAsset(durationSeconds: 2.0)
        let overlayAsset = try await makeSolidColorVideoAsset(durationSeconds: 1.0)

        let result = try await builder.makeComposition(
            screenAsset: screenAsset,
            mode: .horizontal1080p,
            overlayAsset: overlayAsset,
            overlayOffsetSeconds: 0.3
        )

        let compositionDuration = try await result.composition.load(.duration)
        let instructions = result.videoComposition.instructions.compactMap {
            $0 as? AVVideoCompositionInstruction
        }

        var cursor = CMTime.zero
        for instruction in instructions {
            XCTAssertEqual(instruction.timeRange.start, cursor)
            cursor = instruction.timeRange.end
        }
        XCTAssertGreaterThanOrEqual(cursor, compositionDuration)
        XCTAssertEqual(compositionDuration.seconds, 2.0, accuracy: 0.15)
        XCTAssertTrue(instructions.contains { $0.layerInstructions.count == 2 })
        XCTAssertEqual(
            instructions.last?.layerInstructions.count, 1,
            "after the overlay's last frame the tail must be screen-only"
        )
    }

    // Pathological but possible: the overlay's first frame arrived only after the screen
    // content already ended. Its whole track is clamped away and must be dropped, leaving
    // a plain, valid screen-only composition instead of an empty video track.
    func testOverlayStartingAfterScreenEndIsDroppedEntirely() async throws {
        let builder = ScreenCameraOverlayCompositionBuilder()
        let screenAsset = try await makeSolidColorVideoAsset(durationSeconds: 1.0)
        let overlayAsset = try await makeSolidColorVideoAsset(durationSeconds: 1.0)

        let result = try await builder.makeComposition(
            screenAsset: screenAsset,
            mode: .horizontal1080p,
            overlayAsset: overlayAsset,
            overlayOffsetSeconds: 2.0
        )

        let videoTracks = try await result.composition.loadTracks(withMediaType: .video)
        XCTAssertEqual(videoTracks.count, 1, "the fully clamped-away overlay track must be removed")

        let compositionDuration = try await result.composition.load(.duration)
        let instructions = result.videoComposition.instructions.compactMap {
            $0 as? AVVideoCompositionInstruction
        }
        var cursor = CMTime.zero
        for instruction in instructions {
            XCTAssertEqual(instruction.timeRange.start, cursor)
            XCTAssertEqual(instruction.layerInstructions.count, 1)
            cursor = instruction.timeRange.end
        }
        XCTAssertGreaterThanOrEqual(cursor, compositionDuration)
        XCTAssertEqual(compositionDuration.seconds, 1.0, accuracy: 0.15)
    }

    /// Writes a real, tiny H.264 movie file so `makeComposition` exercises the same
    /// AVAsset track/duration loading it does in production. Solid-color frames keep it
    /// fast (~a second of encoding for both fixtures combined).
    private func makeSolidColorVideoAsset(
        durationSeconds: Double,
        size: CGSize = CGSize(width: 320, height: 240),
        fps: Int32 = 30
    ) async throws -> AVURLAsset {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("composition-coverage-\(UUID().uuidString).mov")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? CaptureRecorderError.cannotExportMP4
        }
        writer.startSession(atSourceTime: .zero)

        var createdBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, nil, &createdBuffer)
        let buffer = try XCTUnwrap(createdBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            memset(baseAddress, 0x80, CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let frameCount = Int(durationSeconds * Double(fps))
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? CaptureRecorderError.cannotExportMP4
        }
        return AVURLAsset(url: url)
    }

    func testSecondaryTrackAlignmentTrimsContentThatPredatesSessionZero() {
        var pauseTimeline = RecordingPauseTimeline()
        pauseTimeline.ranges = []
        let sourceDuration = CMTime(seconds: 20, preferredTimescale: 600)

        // A component that started 5s *before* the primary (e.g. system audio prefetched
        // ahead of the camera) has 5s of its own content with nowhere valid to land in the
        // output, since the output starts at session zero.
        let segments = pauseTimeline.segments(for: sourceDuration, offsetSeconds: -5)

        XCTAssertEqual(segments.count, 1)
        let segment = try! XCTUnwrap(segments.first)
        XCTAssertEqual(segment.destinationStart.seconds, 0, accuracy: 0.01)
        XCTAssertEqual(segment.sourceRange.start.seconds, 5, accuracy: 0.01, "the first 5s (before session zero) must be trimmed away")
        XCTAssertEqual(segment.sourceRange.duration.seconds, 15, accuracy: 0.01)
    }
}
