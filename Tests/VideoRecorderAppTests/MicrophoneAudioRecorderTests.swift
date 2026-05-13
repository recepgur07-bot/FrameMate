import XCTest
@testable import FrameMate

final class MicrophoneAudioRecorderTests: XCTestCase {
    func testSampleTrackerOnlyCountsAppendedSamplesAsRecorded() {
        let tracker = RecordingSampleTracker()

        XCTAssertFalse(tracker.hasAppendedSample)

        tracker.markAppendedSample()

        XCTAssertTrue(tracker.hasAppendedSample)
    }

    func testSampleTrackerSeesAudioQueuedBeforeStopDecision() {
        let queue = DispatchQueue(label: "MicrophoneAudioRecorderTests.writer")
        let tracker = RecordingSampleTracker()
        let expectation = expectation(description: "stop decision evaluated")

        queue.async {
            tracker.markAppendedSample()
        }

        queue.async {
            XCTAssertTrue(tracker.hasAppendedSample)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }
}
