import AppKit
import XCTest
@testable import FrameMate

final class KeyboardShortcutRecorderTests: XCTestCase {
    func testRecordsLocalShortcutEventsFromAppWindow() {
        let recorder = KeyboardShortcutRecorder(eventMonitor: KeyboardShortcutEventMonitorSpy())

        recorder.startTracking()
        recorder.simulateLocalKeyDown(
            keyCode: 8,
            charactersIgnoringModifiers: "c",
            modifiers: [.command]
        )

        let timeline = recorder.stopTracking()

        XCTAssertEqual(timeline.events.map(\.label), ["⌘ C"])
    }

    func testRecordsGlobalShortcutEventsFromOtherApps() {
        let recorder = KeyboardShortcutRecorder(eventMonitor: KeyboardShortcutEventMonitorSpy())

        recorder.startTracking()
        recorder.simulateGlobalKeyDown(
            keyCode: 9,
            charactersIgnoringModifiers: "v",
            modifiers: [.command]
        )

        let timeline = recorder.stopTracking()

        XCTAssertEqual(timeline.events.map(\.label), ["⌘ V"])
    }
}

private final class KeyboardShortcutEventMonitorSpy: KeyboardShortcutEventMonitoring {
    var localHandler: ((NSEvent) -> NSEvent?)?
    var globalHandler: ((NSEvent) -> Void)?

    func addLocalKeyDownMonitor(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any {
        localHandler = handler
        return MonitorToken()
    }

    func addGlobalKeyDownMonitor(_ handler: @escaping (NSEvent) -> Void) -> Any? {
        globalHandler = handler
        return MonitorToken()
    }

    func removeMonitor(_ monitor: Any) {}
}

private final class MonitorToken {}

private extension KeyboardShortcutRecorder {
    func simulateLocalKeyDown(
        keyCode: UInt16,
        charactersIgnoringModifiers: String,
        modifiers: NSEvent.ModifierFlags
    ) {
        let spy = eventMonitor as? KeyboardShortcutEventMonitorSpy
        _ = spy?.localHandler?(Self.makeEvent(
            keyCode: keyCode,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            modifiers: modifiers
        ))
    }

    func simulateGlobalKeyDown(
        keyCode: UInt16,
        charactersIgnoringModifiers: String,
        modifiers: NSEvent.ModifierFlags
    ) {
        let spy = eventMonitor as? KeyboardShortcutEventMonitorSpy
        spy?.globalHandler?(Self.makeEvent(
            keyCode: keyCode,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            modifiers: modifiers
        ))
    }

    static func makeEvent(
        keyCode: UInt16,
        charactersIgnoringModifiers: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: charactersIgnoringModifiers,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
