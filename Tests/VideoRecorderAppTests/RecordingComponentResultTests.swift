import XCTest
@testable import FrameMate

final class RecordingComponentResultTests: XCTestCase {
    func testMicrophoneEmptyRecordingBecomesSilentSuccess() {
        let result = RecordingComponentResult.microphone(from: .failure(MicrophoneAudioRecorderError.emptyRecording))

        XCTAssertEqual(try? result.value.get(), nil)
        XCTAssertNil(result.warning)
    }

    func testMicrophoneFailureBecomesWarningAndSilentSuccess() {
        let result = RecordingComponentResult.microphone(from: .failure(CaptureRecorderError.microphoneNotFound))

        XCTAssertEqual(try? result.value.get(), nil)
        XCTAssertEqual(result.warning, "mikrofon sesi eklenemedi")
    }

    func testSystemAudioEmptyRecordingBecomesSilentSuccess() {
        let result = RecordingComponentResult.systemAudio(from: .failure(ScreenRecordingError.emptyRecording))

        XCTAssertEqual(try? result.value.get(), nil)
        XCTAssertNil(result.warning)
    }

    func testSystemAudioFailureBecomesWarningAndSilentSuccess() {
        let result = RecordingComponentResult.systemAudio(from: .failure(ScreenRecordingError.cannotStartStream))

        XCTAssertEqual(try? result.value.get(), nil)
        XCTAssertEqual(result.warning, "sistem sesi eklenemedi")
    }
}
