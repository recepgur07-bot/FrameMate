import XCTest
@testable import __MODULE_NAME__

final class AppSmokeTests: XCTestCase {
    func testStarterConfigExposesExpectedNames() {
        XCTAssertEqual(AppConfig.moduleName, "__MODULE_NAME__")
        XCTAssertEqual(AppConfig.displayName, "__DISPLAY_NAME__")
    }
}
