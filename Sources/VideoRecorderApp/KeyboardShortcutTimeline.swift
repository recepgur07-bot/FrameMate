import AppKit
import Foundation

struct KeyboardShortcutEvent: Equatable {
    let timestamp: TimeInterval
    let label: String
}

struct KeyboardShortcutTimeline: Equatable {
    var events: [KeyboardShortcutEvent] = []

    var isEmpty: Bool {
        events.isEmpty
    }

    static let empty = KeyboardShortcutTimeline()
}

enum KeyboardShortcutFormatter {
    static func label(
        charactersIgnoringModifiers: String?,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> String? {
        let filteredModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        let shortcutModifiers = filteredModifiers.intersection([.command, .control, .option, .shift])

        guard shortcutModifiers.contains(.command)
                || shortcutModifiers.contains(.control)
                || shortcutModifiers.contains(.option) else {
            return nil
        }

        let key = keyLabel(charactersIgnoringModifiers: charactersIgnoringModifiers, keyCode: keyCode)
        guard let key, !key.isEmpty else {
            return nil
        }

        var parts: [String] = []
        if shortcutModifiers.contains(.control) { parts.append("⌃") }
        if shortcutModifiers.contains(.option) { parts.append("⌥") }
        if shortcutModifiers.contains(.shift) { parts.append("⇧") }
        if shortcutModifiers.contains(.command) { parts.append("⌘") }
        parts.append(key)
        return parts.joined(separator: " ")
    }

    private static func keyLabel(charactersIgnoringModifiers: String?, keyCode: UInt16) -> String? {
        let trimmed = charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed.uppercased()
        }

        switch keyCode {
        case 36:
            return "Return"
        case 48:
            return "Tab"
        case 49:
            return "Space"
        case 53:
            return "Esc"
        default:
            return nil
        }
    }
}
