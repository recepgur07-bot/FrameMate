import XCTest
@testable import FrameMate

final class FrameCoachSpatialCueResolverTests: XCTestCase {
    func testReturnsRightCueForMoveRightGuidance() {
        let cue = FrameCoachSpatialCueResolver().cue(for: nil, guidance: "biraz sağa geç")

        XCTAssertEqual(
            cue,
            FrameCoachSpatialCue(direction: .right, severity: .mild, confirmsCentered: false)
        )
    }

    func testReturnsLeftCueForMoveLeftGuidance() {
        let cue = FrameCoachSpatialCueResolver().cue(for: nil, guidance: "biraz sola geç")

        XCTAssertEqual(
            cue,
            FrameCoachSpatialCue(direction: .left, severity: .mild, confirmsCentered: false)
        )
    }

    func testReturnsCenterCueForGoodFrameGuidance() {
        let cue = FrameCoachSpatialCueResolver().cue(for: nil, guidance: "kadraj uygun")

        XCTAssertEqual(
            cue,
            FrameCoachSpatialCue(direction: .center, severity: .mild, confirmsCentered: true)
        )
    }

    func testSuppressesCueForNoFaceGuidance() {
        XCTAssertNil(FrameCoachSpatialCueResolver().cue(for: nil, guidance: "Yüz algılanamıyor"))
    }
}
