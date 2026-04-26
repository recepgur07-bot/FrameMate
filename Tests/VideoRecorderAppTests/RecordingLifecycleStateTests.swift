import XCTest
@testable import FrameMate

final class RecordingLifecycleStateTests: XCTestCase {
    func testStartStopFinishFlowProducesStableFlags() {
        var lifecycle = RecordingLifecycleState()

        XCTAssertTrue(lifecycle.canBeginPreparing)
        XCTAssertFalse(lifecycle.isPreparing)
        XCTAssertFalse(lifecycle.isRecording)
        XCTAssertFalse(lifecycle.isStopping)

        XCTAssertTrue(lifecycle.beginPreparing())
        XCTAssertFalse(lifecycle.canBeginPreparing)
        XCTAssertTrue(lifecycle.isPreparing)

        XCTAssertTrue(lifecycle.markStarted())
        XCTAssertFalse(lifecycle.isPreparing)
        XCTAssertTrue(lifecycle.isRecording)

        XCTAssertTrue(lifecycle.beginStopping())
        XCTAssertFalse(lifecycle.isRecording)
        XCTAssertTrue(lifecycle.isStopping)

        lifecycle.finish()
        XCTAssertTrue(lifecycle.canBeginPreparing)
        XCTAssertFalse(lifecycle.isPreparing)
        XCTAssertFalse(lifecycle.isRecording)
        XCTAssertFalse(lifecycle.isStopping)
    }

    func testCannotStartTwiceOrStopWhenIdle() {
        var lifecycle = RecordingLifecycleState()

        XCTAssertFalse(lifecycle.beginStopping())
        XCTAssertTrue(lifecycle.beginPreparing())
        XCTAssertFalse(lifecycle.beginPreparing())
        XCTAssertTrue(lifecycle.markStarted())
        XCTAssertFalse(lifecycle.markStarted())
    }
}
