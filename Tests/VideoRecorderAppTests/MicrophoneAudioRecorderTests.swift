import AVFoundation
import XCTest
@testable import FrameMate

final class MicrophoneAudioRecorderTests: XCTestCase {
    func testAutomaticWriterSettingsPreserveCaptureOutputRecommendation() {
        let recommended: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 96_000,
            AVNumberOfChannelsKey: 2
        ]

        let settings = MicrophoneAudioRecorder.writerAudioSettings(
            recommendedSettings: recommended,
            channelMode: .automatic
        )

        XCTAssertEqual(settings[AVSampleRateKey] as? Int, 44_100)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 2)
    }

    func testWriterSettingsApplyExplicitChannelModeWithoutDiscardingRecommendation() {
        let recommended: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 96_000,
            AVNumberOfChannelsKey: 2
        ]

        let settings = MicrophoneAudioRecorder.writerAudioSettings(
            recommendedSettings: recommended,
            channelMode: .mono
        )

        XCTAssertEqual(settings[AVSampleRateKey] as? Int, 44_100)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)
    }

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
