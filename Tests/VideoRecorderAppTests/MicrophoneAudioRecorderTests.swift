import XCTest
@testable import FrameMate

final class MicrophoneAudioRecorderTests: XCTestCase {
    func testSampleTrackerSeesAudioQueuedBeforeStopDecision() {
        let queue = DispatchQueue(label: "MicrophoneAudioRecorderTests.writer")
        let tracker = MicrophoneAudioRecorderSampleTracker()
        let expectation = expectation(description: "stop decision evaluated")

        queue.async {
            tracker.markReceivedAudioSample()
        }

        queue.async {
            XCTAssertTrue(tracker.hasReceivedAudioSample)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }
}
