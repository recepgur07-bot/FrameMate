import XCTest
@testable import FrameMate

final class MainWindowPresentationPolicyTests: XCTestCase {
    func testLaunchStateDoesNotRequestWindowChange() {
        let policy = MainWindowPresentationPolicy()

        XCTAssertNil(policy.actionForRecordingStateChange(from: false, to: false))
    }

    func testRecordingStartKeepsWindowVisible() {
        let policy = MainWindowPresentationPolicy()

        XCTAssertNil(policy.actionForRecordingStateChange(from: false, to: true))
    }

    func testRecordingStopRequestsShow() {
        let policy = MainWindowPresentationPolicy()

        XCTAssertEqual(
            policy.actionForRecordingStateChange(from: true, to: false),
            .show
        )
    }

    func testUnchangedRecordingStateDoesNotRequestWindowChange() {
        let policy = MainWindowPresentationPolicy()

        XCTAssertNil(policy.actionForRecordingStateChange(from: true, to: true))
    }

    func testAppTerminatesAfterLastWindowClosesWhenIdle() {
        let policy = AppTerminationPolicy()

        XCTAssertTrue(policy.shouldTerminateAfterLastWindowClosed(isRecording: false))
    }

    func testAppStaysOpenAfterLastWindowClosesWhileRecording() {
        let policy = AppTerminationPolicy()

        XCTAssertFalse(policy.shouldTerminateAfterLastWindowClosed(isRecording: true))
    }
}
