import AppKit
import XCTest
@testable import FrameMate

@MainActor
final class MainWindowControllerTests: XCTestCase {
    func testShowMainWindowBringsExistingWindowForward() {
        let window = NSWindow()
        var didActivate = false
        var didRequestOpen = false
        let controller = MainWindowController(
            mainWindowProvider: { window },
            activateApp: { didActivate = true },
            openMainWindow: { didRequestOpen = true }
        )

        controller.showMainWindow()

        XCTAssertTrue(didActivate)
        XCTAssertFalse(didRequestOpen)
        XCTAssertTrue(window.isVisible)
    }

    func testShowMainWindowRequestsOpenWhenNoWindowExists() {
        var didActivate = false
        var didRequestOpen = false
        let controller = MainWindowController(
            mainWindowProvider: { nil },
            activateApp: { didActivate = true },
            openMainWindow: { didRequestOpen = true }
        )

        controller.showMainWindow()

        XCTAssertTrue(didActivate)
        XCTAssertTrue(didRequestOpen)
    }
}
