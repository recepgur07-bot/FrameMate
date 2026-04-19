import AppKit
import XCTest
@testable import FrameMate

@MainActor
final class MainWindowControllerTests: XCTestCase {
    func testShowMainWindowBringsExistingWindowForward() {
        let window = NSWindow()
        var didActivate = false
        var didUnhide = false
        var didRequestOpen = false
        let controller = MainWindowController(
            mainWindowProvider: { window },
            activateApp: { didActivate = true },
            hideApp: {},
            unhideApp: { didUnhide = true },
            openMainWindow: { didRequestOpen = true }
        )

        controller.showMainWindow()

        XCTAssertTrue(didActivate)
        XCTAssertTrue(didUnhide)
        XCTAssertFalse(didRequestOpen)
        XCTAssertTrue(window.isVisible)
    }

    func testShowMainWindowRequestsOpenWhenNoWindowExists() {
        var didActivate = false
        var didUnhide = false
        var didRequestOpen = false
        let controller = MainWindowController(
            mainWindowProvider: { nil },
            activateApp: { didActivate = true },
            hideApp: {},
            unhideApp: { didUnhide = true },
            openMainWindow: { didRequestOpen = true }
        )

        controller.showMainWindow()

        XCTAssertTrue(didActivate)
        XCTAssertTrue(didUnhide)
        XCTAssertTrue(didRequestOpen)
    }

    func testHideMainWindowHidesApplication() {
        let window = NSWindow()
        var didHide = false
        let controller = MainWindowController(
            mainWindowProvider: { window },
            activateApp: {},
            hideApp: { didHide = true },
            unhideApp: {},
            openMainWindow: {}
        )

        controller.hideMainWindow()

        XCTAssertTrue(didHide)
    }
}
