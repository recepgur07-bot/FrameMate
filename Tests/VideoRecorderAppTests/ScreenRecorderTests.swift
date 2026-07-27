import XCTest
@testable import FrameMate

private final class ScreenAccessStateBox: @unchecked Sendable {
    var isGranted: Bool

    init(isGranted: Bool) {
        self.isGranted = isGranted
    }
}

final class ScreenRecorderTests: XCTestCase {
    func testScreenPermissionRequestReturnsDeniedWhenAccessRemainsUnavailable() async {
        let provider = SystemScreenRecordingProvider(
            preflightAccess: { false },
            requestAccessHandler: { false }
        )

        let result = await provider.requestAccess()

        XCTAssertEqual(result, .denied)
    }

    func testScreenPermissionRequestReturnsRestartWhenRequestReportsFalseButAccessBecomesAvailable() async {
        let state = ScreenAccessStateBox(isGranted: false)
        let provider = SystemScreenRecordingProvider(
            preflightAccess: { state.isGranted },
            requestAccessHandler: {
                state.isGranted = true
                return false
            }
        )

        let result = await provider.requestAccess()

        XCTAssertEqual(result, .grantedButRequiresRestart)
    }

    func testFallbackStopResultReturnsSuccessForNonEmptyRecordingFile() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("capture.mov")
        try Data([0x01, 0x02, 0x03]).write(to: url)

        let result = try XCTUnwrap(ScreenRecorder.fallbackStopResult(for: url))

        switch result {
        case .success(let returnedURL):
            XCTAssertEqual(returnedURL, url)
        case .failure(let error):
            XCTFail("Expected success, got failure: \(error.localizedDescription)")
        }
    }

    func testFallbackStopResultReturnsEmptyRecordingFailureForEmptyFile() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("capture.mov")
        try Data().write(to: url)

        let result = try XCTUnwrap(ScreenRecorder.fallbackStopResult(for: url))

        switch result {
        case .success:
            XCTFail("Expected failure for empty file")
        case .failure(let error):
            XCTAssertEqual(error as? ScreenRecordingError, .emptyRecording)
        }
    }

    func testFallbackStopResultReturnsNilForMissingFile() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.mov")

        XCTAssertNil(ScreenRecorder.fallbackStopResult(for: url))
    }

    @MainActor
    func testCompleteClearsStoppingLatchEvenOnRedundantCalls() {
        let recorder = ScreenRecorder()
        recorder.simulateStuckStopForTesting()
        XCTAssertTrue(recorder.isStoppingForTesting)

        // First completion consumes the handler and must clear the latch.
        recorder.triggerCompleteForTesting(.failure(ScreenRecordingError.emptyRecording))
        XCTAssertFalse(
            recorder.isStoppingForTesting,
            "complete() must clear isStopping so the next stopRecording() call can proceed"
        )

        // A second, redundant completion (e.g. a delegate firing after the handler was
        // already consumed by the fallback poll, or vice versa) must not re-latch it.
        recorder.triggerCompleteForTesting(.failure(ScreenRecordingError.emptyRecording))
        XCTAssertFalse(recorder.isStoppingForTesting)

        // Proof the recorder is genuinely usable again: stopRecording() must actually
        // engage (flip isStopping back to true while it does its async work) rather than
        // silently no-op because the latch was still stuck from the previous recording.
        recorder.stopRecording()
        XCTAssertTrue(
            recorder.isStoppingForTesting,
            "a fresh stopRecording() call must actually engage, not silently no-op"
        )
    }
}
