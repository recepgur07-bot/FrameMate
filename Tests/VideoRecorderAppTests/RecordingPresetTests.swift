import XCTest
@testable import FrameMate

final class RecordingPresetTests: XCTestCase {
    func testHorizontalCameraPresetMapsToHorizontalCameraConfiguration() {
        XCTAssertTrue(RecordingPreset.horizontalCamera.isCameraPreset)
        XCTAssertEqual(RecordingPreset.horizontalCamera.recordingMode, .horizontal1080p)
        XCTAssertEqual(RecordingPreset.horizontalCamera.commandKey, "1")
    }

    func testHorizontalScreenPresetMapsToSecondShortcutSlot() {
        XCTAssertTrue(RecordingPreset.horizontalScreen.isScreenPreset)
        XCTAssertEqual(RecordingPreset.horizontalScreen.recordingMode, .horizontal1080p)
        XCTAssertEqual(RecordingPreset.horizontalScreen.commandKey, "2")
    }

    func testAudioOnlyPresetUsesThirdShortcutSlot() {
        XCTAssertTrue(RecordingPreset.audioOnly.isAudioPreset)
        XCTAssertEqual(RecordingPreset.audioOnly.recordingMode, .horizontal1080p)
        XCTAssertEqual(RecordingPreset.audioOnly.commandKey, "3")
    }

    func testCommandMenuLabelsStayShortAndReadable() {
        XCTAssertEqual(RecordingPreset.horizontalCamera.commandMenuLabel, "Yatay video kaydı")
        XCTAssertEqual(RecordingPreset.horizontalScreen.commandMenuLabel, "Yatay ekran kaydı")
        XCTAssertEqual(RecordingPreset.audioOnly.commandMenuLabel, "Ses kaydı")
    }

    func testAllCasesExposeOnlySupportedReleaseModes() {
        XCTAssertEqual(RecordingPreset.allCases, [.horizontalCamera, .horizontalScreen, .audioOnly])
    }

    func testUnsupportedVerticalPresetsFallbackToSupportedReleasePresets() {
        XCTAssertEqual(RecordingPreset.verticalCamera.supportedReleasePreset, .horizontalCamera)
        XCTAssertEqual(RecordingPreset.verticalScreen.supportedReleasePreset, .horizontalScreen)
    }
}
