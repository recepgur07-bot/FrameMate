import XCTest
@testable import FrameMate

final class ScreenRecorderTests: XCTestCase {
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
}
