import XCTest
@testable import VideoRecorderApp

final class RecordingPresetTests: XCTestCase {
    func testHorizontalCameraPresetMapsToHorizontalCameraConfiguration() {
        XCTAssertTrue(RecordingPreset.horizontalCamera.isCameraPreset)
        XCTAssertEqual(RecordingPreset.horizontalCamera.recordingMode, .horizontal1080p)
        XCTAssertEqual(RecordingPreset.horizontalCamera.commandKey, "1")
    }

    func testVerticalScreenPresetMapsToVerticalScreenConfiguration() {
        XCTAssertTrue(RecordingPreset.verticalScreen.isScreenPreset)
        XCTAssertEqual(RecordingPreset.verticalScreen.recordingMode, .vertical1080p)
        XCTAssertEqual(RecordingPreset.verticalScreen.commandKey, "4")
    }

    func testCommandMenuLabelsStayShortAndReadable() {
        XCTAssertEqual(RecordingPreset.horizontalCamera.commandMenuLabel, "Yatay video kaydı")
        XCTAssertEqual(RecordingPreset.verticalScreen.commandMenuLabel, "Dikey ekran kaydı")
    }
}
