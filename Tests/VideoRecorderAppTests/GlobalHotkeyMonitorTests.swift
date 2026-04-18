import XCTest
@testable import FrameMate

final class GlobalHotkeyMonitorTests: XCTestCase {
    func testStartAndStopDoNotCrash() {
        var callCount = 0
        let monitor = GlobalHotkeyMonitor(onToggle: { callCount += 1 })
        monitor.start()
        monitor.stop()
        // No crash = pass. callCount stays 0 (no synthetic event fired)
        XCTAssertEqual(callCount, 0)
    }

    func testDoubleStartDoesNotLeak() {
        let monitor = GlobalHotkeyMonitor(onToggle: {})
        monitor.start()
        monitor.start() // second call should be a no-op even if the host app already registered the hotkey
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
    }

    func testStopWithoutStartDoesNotCrash() {
        let monitor = GlobalHotkeyMonitor(onToggle: {})
        monitor.stop()
    }

    func testInstallsLocalKeyMonitor() {
        let monitor = GlobalHotkeyMonitor(onToggle: {})

        XCTAssertFalse(monitor.installsLocalKeyMonitor)
    }

    func testMatchesRecordingToggleShortcut() throws {
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .control],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "r",
                charactersIgnoringModifiers: "r",
                isARepeat: false,
                keyCode: 15
            )
        )

        XCTAssertTrue(GlobalHotkeyMonitor.matchesRecordingToggle(for: event))
    }

    func testRejectsShortcutWithExtraModifiers() throws {
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .control, .shift],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "r",
                charactersIgnoringModifiers: "r",
                isARepeat: false,
                keyCode: 15
            )
        )

        XCTAssertFalse(GlobalHotkeyMonitor.matchesRecordingToggle(for: event))
    }

    func testMatchesAudioRecordingToggleShortcut() throws {
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .control],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "5",
                charactersIgnoringModifiers: "5",
                isARepeat: false,
                keyCode: 23
            )
        )

        XCTAssertEqual(GlobalHotkeyMonitor.audioRecordingToggleDisplay, "Cmd+Ctrl+5")
        XCTAssertTrue(GlobalHotkeyMonitor.matchesAudioRecordingToggle(for: event))
    }

    func testMatchesPauseResumeToggleShortcut() throws {
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .control],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "p",
                charactersIgnoringModifiers: "p",
                isARepeat: false,
                keyCode: 35
            )
        )

        XCTAssertEqual(GlobalHotkeyMonitor.pauseResumeToggleDisplay, "Cmd+Ctrl+P")
        XCTAssertTrue(GlobalHotkeyMonitor.matchesPauseResumeToggle(for: event))
    }

    func testPauseResumeToggleRejectsExtraModifiers() throws {
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .control, .shift],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "p",
                charactersIgnoringModifiers: "p",
                isARepeat: false,
                keyCode: 35
            )
        )

        XCTAssertFalse(GlobalHotkeyMonitor.matchesPauseResumeToggle(for: event))
    }
}
