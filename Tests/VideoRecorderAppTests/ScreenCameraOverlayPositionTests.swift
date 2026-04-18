import XCTest
@testable import FrameMate

final class ScreenCameraOverlayPositionTests: XCTestCase {
    func testTopLeftAnchorsToTopAndLeft() {
        XCTAssertEqual(ScreenCameraOverlayPosition.topLeft.horizontalAnchor, 0)
        XCTAssertEqual(ScreenCameraOverlayPosition.topLeft.verticalAnchor, 0)
    }

    func testBottomCenterAnchorsToBottomAndCenter() {
        XCTAssertEqual(ScreenCameraOverlayPosition.bottomCenter.horizontalAnchor, 0.5)
        XCTAssertEqual(ScreenCameraOverlayPosition.bottomCenter.verticalAnchor, 1)
    }
}
