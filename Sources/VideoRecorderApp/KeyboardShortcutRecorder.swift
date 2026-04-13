import AppKit
import Foundation

protocol KeyboardShortcutRecordingProviding: AnyObject {
    func startTracking()
    func stopTracking() -> KeyboardShortcutTimeline
}

final class KeyboardShortcutRecorder: KeyboardShortcutRecordingProviding {
    private var events: [KeyboardShortcutEvent] = []
    private var startTime: TimeInterval = 0
    private var monitor: Any?

    func startTracking() {
        _ = stopTracking()
        events = []
        startTime = ProcessInfo.processInfo.systemUptime

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            if let label = KeyboardShortcutFormatter.label(
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                keyCode: event.keyCode,
                modifiers: event.modifierFlags
            ) {
                let timestamp = ProcessInfo.processInfo.systemUptime - self.startTime
                self.events.append(KeyboardShortcutEvent(timestamp: timestamp, label: label))
            }
        }
    }

    func stopTracking() -> KeyboardShortcutTimeline {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        let timeline = KeyboardShortcutTimeline(events: events)
        events = []
        startTime = 0
        return timeline
    }
}
