import XCTest
@testable import FrameMate

final class RecordingModeTests: XCTestCase {
    func testHorizontalModeUses1080pLandscapeDimensions() {
        XCTAssertEqual(RecordingMode.horizontal1080p.width, 1920)
        XCTAssertEqual(RecordingMode.horizontal1080p.height, 1080)
        XCTAssertEqual(RecordingMode.horizontal1080p.label, "1080p Yatay")
    }

    func testAllCasesExposeOnlyHorizontalMode() {
        XCTAssertEqual(RecordingMode.allCases, [.horizontal1080p])
    }

    func testHorizontalModeDoesNotApplyRotationAtCaptureLayer() {
        let mode = RecordingPreset.horizontalCamera.recordingMode
        XCTAssertEqual(mode, RecordingMode.horizontal1080p)
        XCTAssertEqual(RecordingMode.horizontal1080p.captureRotationAngle, 0)
    }
}
