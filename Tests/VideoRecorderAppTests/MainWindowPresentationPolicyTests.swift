import XCTest
@testable import FrameMate

final class MainWindowPresentationPolicyTests: XCTestCase {
    func testLaunchStateDoesNotRequestWindowChange() {
        let policy = MainWindowPresentationPolicy()

        XCTAssertNil(policy.actionForRecordingStateChange(from: false, to: false))
    }

    func testRecordingStartKeepsWindowVisible() {
        let policy = MainWindowPresentationPolicy()

        XCTAssertEqual(
            policy.actionForRecordingStateChange(from: false, to: true),
            .hide
        )
    }

    func testRecordingStopRequestsShow() {
        let policy = MainWindowPresentationPolicy()

        XCTAssertEqual(
            policy.actionForRecordingStateChange(from: true, to: false),
            .show
        )
    }

    func testRecordingStopCanRemainHiddenWhenConfigured() {
        let policy = MainWindowPresentationPolicy(showWindowWhenRecordingStops: false)

        XCTAssertNil(policy.actionForRecordingStateChange(from: true, to: false))
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
