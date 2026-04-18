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
}
