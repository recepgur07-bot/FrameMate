import AppKit
import Foundation

protocol KeyboardShortcutRecordingProviding: AnyObject {
    func startTracking()
    func stopTracking() -> KeyboardShortcutTimeline
}

protocol KeyboardShortcutEventMonitoring: AnyObject {
    func addLocalKeyDownMonitor(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any
    func addGlobalKeyDownMonitor(_ handler: @escaping (NSEvent) -> Void) -> Any?
    func removeMonitor(_ monitor: Any)
}

final class KeyboardShortcutRecorder: KeyboardShortcutRecordingProviding {
    private var events: [KeyboardShortcutEvent] = []
    private var startTime: TimeInterval = 0
    private var monitors: [Any] = []
    let eventMonitor: any KeyboardShortcutEventMonitoring

    init(eventMonitor: any KeyboardShortcutEventMonitoring = AppKitKeyboardShortcutEventMonitor()) {
        self.eventMonitor = eventMonitor
    }

    func startTracking() {
        _ = stopTracking()
        events = []
        startTime = ProcessInfo.processInfo.systemUptime

        let localMonitor = eventMonitor.addLocalKeyDownMonitor { [weak self] event in
            self?.record(event)
            return event
        }
        monitors.append(localMonitor)

        if let globalMonitor = eventMonitor.addGlobalKeyDownMonitor({ [weak self] event in
            self?.record(event)
        }) {
            monitors.append(globalMonitor)
        }
    }

    func stopTracking() -> KeyboardShortcutTimeline {
        for monitor in monitors {
            eventMonitor.removeMonitor(monitor)
        }
        monitors.removeAll()

        let timeline = KeyboardShortcutTimeline(events: events)
        events = []
        startTime = 0
        return timeline
    }

    private func record(_ event: NSEvent) {
        if let label = KeyboardShortcutFormatter.label(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            modifiers: event.modifierFlags
        ) {
            let timestamp = ProcessInfo.processInfo.systemUptime - startTime
            events.append(KeyboardShortcutEvent(timestamp: timestamp, label: label))
        }
    }
}

private final class AppKitKeyboardShortcutEventMonitor: KeyboardShortcutEventMonitoring {
    func addLocalKeyDownMonitor(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler) as Any
    }

    func addGlobalKeyDownMonitor(_ handler: @escaping (NSEvent) -> Void) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
    }

    func removeMonitor(_ monitor: Any) {
        NSEvent.removeMonitor(monitor)
    }
}
