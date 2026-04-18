import AVFoundation
import XCTest
@testable import FrameMate

final class AutoReframeTimelineTests: XCTestCase {
    func testTimelineAppendsDistinctTimes() {
        var timeline = AutoReframeTimeline()

        timeline.append(crop: .fullFrame, at: CMTime(seconds: 0, preferredTimescale: 600))
        timeline.append(
            crop: AutoReframeCrop(originX: 0.1, originY: 0.1, width: 0.9, height: 0.9),
            at: CMTime(seconds: 0.5, preferredTimescale: 600)
        )

        XCTAssertEqual(timeline.keyframes.count, 2)
    }

    func testTimelineReplacesSameTimestampFrame() {
        var timeline = AutoReframeTimeline()

        timeline.append(crop: .fullFrame, at: CMTime(seconds: 1, preferredTimescale: 600))
        timeline.append(
            crop: AutoReframeCrop(originX: 0.1, originY: 0.1, width: 0.9, height: 0.9),
            at: CMTime(seconds: 1, preferredTimescale: 600)
        )

        XCTAssertEqual(timeline.keyframes.count, 1)
        XCTAssertEqual(
            timeline.keyframes.first?.crop,
            AutoReframeCrop(originX: 0.1, originY: 0.1, width: 0.9, height: 0.9)
        )
    }

    func testCompositionBuilderReturnsNilForEmptyTimeline() async {
        let asset = AVURLAsset(url: URL(fileURLWithPath: "/tmp/does-not-exist.mov"))
        let composition = await AutoReframeCompositionBuilder().makeVideoComposition(
            for: asset,
            timeline: AutoReframeTimeline()
        )

        XCTAssertNil(composition)
    }

    func testPauseTimelineRemovesPausedRangeFromSegments() {
        let timeline = RecordingPauseTimeline(ranges: [
            RecordingPauseRange(start: 2, end: 5)
        ])

        let segments = timeline.segments(for: CMTime(seconds: 10, preferredTimescale: 600))

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].sourceRange.start.seconds, 0, accuracy: 0.001)
        XCTAssertEqual(segments[0].sourceRange.duration.seconds, 2, accuracy: 0.001)
        XCTAssertEqual(segments[0].destinationStart.seconds, 0, accuracy: 0.001)
        XCTAssertEqual(segments[1].sourceRange.start.seconds, 5, accuracy: 0.001)
        XCTAssertEqual(segments[1].sourceRange.duration.seconds, 5, accuracy: 0.001)
        XCTAssertEqual(segments[1].destinationStart.seconds, 2, accuracy: 0.001)
        XCTAssertEqual(timeline.outputDuration(for: CMTime(seconds: 10, preferredTimescale: 600)).seconds, 7, accuracy: 0.001)
    }

    func testPauseTimelineDropsOverlayEventsInsidePausedRange() {
        let pauseTimeline = RecordingPauseTimeline(ranges: [
            RecordingPauseRange(start: 2, end: 5)
        ])
        let shortcutTimeline = KeyboardShortcutTimeline(events: [
            KeyboardShortcutEvent(timestamp: 1, label: "⌘ A"),
            KeyboardShortcutEvent(timestamp: 3, label: "⌘ B"),
            KeyboardShortcutEvent(timestamp: 6, label: "⌘ C")
        ])

        let shifted = shortcutTimeline.shifted(by: pauseTimeline)

        XCTAssertEqual(shifted.events, [
            KeyboardShortcutEvent(timestamp: 1, label: "⌘ A"),
            KeyboardShortcutEvent(timestamp: 3, label: "⌘ C")
        ])
    }
}
