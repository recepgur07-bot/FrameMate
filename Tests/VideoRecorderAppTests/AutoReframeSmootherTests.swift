import XCTest
@testable import FrameMate

final class AutoReframeSmootherTests: XCTestCase {
    func testStepMovesTowardTargetWithoutJumpingDirectly() {
        var smoother = AutoReframeSmoother(smoothingFactor: 0.25)
        let target = AutoReframeCrop(originX: 0.10, originY: 0.10, width: 0.85, height: 0.85)

        let stepped = smoother.step(towards: target)

        XCTAssertNotEqual(stepped, .fullFrame)
        XCTAssertNotEqual(stepped, target)
        XCTAssertLessThan(stepped.width, 1.0)
        XCTAssertGreaterThan(stepped.width, target.width)
    }

    func testResetReturnsToFullFrame() {
        var smoother = AutoReframeSmoother(smoothingFactor: 0.25)
        _ = smoother.step(towards: AutoReframeCrop(originX: 0.10, originY: 0.10, width: 0.85, height: 0.85))

        smoother.reset()

        XCTAssertEqual(smoother.currentCrop, .fullFrame)
    }
}
