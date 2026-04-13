import AppKit

@objc(VideoRecorderApplication)
final class VideoRecorderApplication: NSApplication {
    override init() {
        super.init()
        debugLog("init principal=\(NSStringFromClass(type(of: self)))")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        debugLog("init(coder:) principal=\(NSStringFromClass(type(of: self)))")
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            let keyEquivalent = event.charactersIgnoringModifiers?.lowercased() ?? "?"
            debugLog("sendEvent cmd key=\(keyEquivalent) modifiers=\(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)")
            if keyWindow?.performKeyEquivalent(with: event) == true {
                debugLog("handled by keyWindow")
                return
            }

            if mainWindow !== keyWindow, mainWindow?.performKeyEquivalent(with: event) == true {
                debugLog("handled by mainWindow")
                return
            }

            if mainMenu?.performKeyEquivalent(with: event) == true {
                debugLog("handled by mainMenu")
                return
            }

            if performCommandKeyFallback(for: event) {
                debugLog("handled by fallback")
                return
            }

            debugLog("fell through to super")
        }

        super.sendEvent(event)
    }

    private func performCommandKeyFallback(for event: NSEvent) -> Bool {
        guard
            let keyEquivalent = event.charactersIgnoringModifiers?.lowercased(),
            let menu = mainMenu,
            let item = menu.item(
                matching: keyEquivalent,
                modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            )
        else {
            debugLog("fallback no matching item for \(event.charactersIgnoringModifiers?.lowercased() ?? "?")")
            return false
        }

        guard item.isEnabled else {
            debugLog("fallback found disabled item \(item.title)")
            return false
        }

        if let action = item.action {
            debugLog("fallback sending action for \(item.title)")
            return sendAction(action, to: item.target, from: item)
        }

        debugLog("fallback found item without action \(item.title)")
        return false
    }
}

private extension NSMenu {
    func item(matching keyEquivalent: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem? {
        let normalizedModifiers = modifiers.intersection(.deviceIndependentFlagsMask)

        for item in items {
            if item.matches(keyEquivalent: keyEquivalent, modifiers: normalizedModifiers) {
                return item
            }

            if let nested = item.submenu?.item(matching: keyEquivalent, modifiers: normalizedModifiers) {
                return nested
            }
        }

        return nil
    }
}

private extension NSMenuItem {
    func matches(keyEquivalent: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        self.keyEquivalent.lowercased() == keyEquivalent
            && keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == modifiers
    }
}

func runtimeDebugLog(_ message: String) {
#if DEBUG
    appendDebugLog(
        prefix: "[Runtime]",
        message: message,
        path: "/tmp/videorecorder-runtime.log"
    )
#endif
}

private func debugLog(_ message: String) {
#if DEBUG
    appendDebugLog(
        prefix: "[VideoRecorderApplication]",
        message: message,
        path: "/tmp/videorecorder-keyevents.log"
    )
#endif
}

private func appendDebugLog(prefix: String, message: String, path: String) {
#if DEBUG
    let line = "\(prefix) \(message)\n"
    let url = URL(fileURLWithPath: path)
    let data = Data(line.utf8)

    if FileManager.default.fileExists(atPath: url.path),
       let handle = try? FileHandle(forWritingTo: url) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    } else {
        try? data.write(to: url)
    }
#endif
}
