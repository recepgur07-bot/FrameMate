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

    func testVerticalModeDoesNotApplyRotationAtCaptureLayer() {
        // CaptureRecorder'ın vertical1080p modunda videoRotationAngle=0 kullandığını doğrular.
        // applyOrientation private olduğundan davranışı RecordingMode üzerinden test ederiz.
        let mode = RecordingPreset.verticalCamera.recordingMode
        XCTAssertEqual(mode, RecordingMode.vertical1080p)
        // Bu test Step 2'de captureRotationAngle eklenmeden önce compile olmaz — bu doğru TDD davranışıdır.
        // Step 1: test eklenir (compile error = failing), Step 2: property eklenir (test geçer).
        XCTAssertEqual(RecordingMode.vertical1080p.captureRotationAngle, 0)
    }
}
