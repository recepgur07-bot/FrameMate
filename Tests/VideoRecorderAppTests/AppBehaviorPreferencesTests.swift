import AppKit
import XCTest
@testable import FrameMate

final class AppBehaviorPreferencesTests: XCTestCase {
    func testDefaultsMatchUtilityRecorderExpectations() {
        let preferences = AppBehaviorPreferences()

        XCTAssertFalse(preferences.hideWindowOnRecordingStart)
        XCTAssertTrue(preferences.showWindowWhenRecordingStops)
        XCTAssertEqual(preferences.activationPolicy, .regular)
        XCTAssertFalse(preferences.launchAtLogin)
    }

    func testActivationPolicyUsesAccessoryModeWhenDockIconIsHidden() {
        var preferences = AppBehaviorPreferences()
        preferences.activationPolicy = .accessory

        XCTAssertEqual(preferences.resolvedActivationPolicy, .accessory)
    }
}
