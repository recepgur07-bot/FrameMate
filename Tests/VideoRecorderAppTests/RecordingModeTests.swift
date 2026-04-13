import XCTest
@testable import VideoRecorderApp

final class RecordingModeTests: XCTestCase {
    func testHorizontalModeUses1080pLandscapeDimensions() {
        XCTAssertEqual(RecordingMode.horizontal1080p.width, 1920)
        XCTAssertEqual(RecordingMode.horizontal1080p.height, 1080)
        XCTAssertEqual(RecordingMode.horizontal1080p.label, "1080p Yatay")
    }

    func testVerticalModeUses1080pPortraitDimensions() {
        XCTAssertEqual(RecordingMode.vertical1080p.width, 1080)
        XCTAssertEqual(RecordingMode.vertical1080p.height, 1920)
        XCTAssertEqual(RecordingMode.vertical1080p.label, "1080p Dikey")
    }
}
