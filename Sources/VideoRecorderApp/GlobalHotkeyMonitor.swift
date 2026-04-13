import AppKit
import Carbon.HIToolbox

/// Listens for recording hotkeys globally (even when app is in background).
/// Carbon hotkeys are more reliable than NSEvent monitors and do not depend on Accessibility permission.
final class GlobalHotkeyMonitor {
    static let recordingToggleDisplay = "Cmd+Ctrl+R"
    static let recordingToggleKeyCode: UInt32 = 15
    static let recordingToggleModifiers: NSEvent.ModifierFlags = [.command, .control]
    static let audioRecordingToggleDisplay = "Cmd+Ctrl+5"
    static let audioRecordingToggleKeyCode: UInt32 = 23
    static let pauseResumeToggleDisplay = "Cmd+Ctrl+P"
    static let pauseResumeToggleKeyCode: UInt32 = 35

    fileprivate static let hotKeySignature: OSType = 0x56445248 // 'VDRH'
    fileprivate static let hotKeyID: UInt32 = 1
    fileprivate static let audioHotKeyID: UInt32 = 2
    fileprivate static let pauseResumeHotKeyID: UInt32 = 3
    private static let toggleCarbonModifiers: UInt32 = UInt32(cmdKey | controlKey)

    private let onToggle: () -> Void
    private let onAudioToggle: () -> Void
    private let onPauseResumeToggle: () -> Void
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var isStarted = false

    var isRunning: Bool { isStarted }
    var installsLocalKeyMonitor: Bool { false }

    init(
        onToggle: @escaping () -> Void,
        onAudioToggle: @escaping () -> Void,
        onPauseResumeToggle: @escaping () -> Void = {}
    ) {
        self.onToggle = onToggle
        self.onAudioToggle = onAudioToggle
        self.onPauseResumeToggle = onPauseResumeToggle
    }

    convenience init(onToggle: @escaping () -> Void, onAudioToggle: @escaping () -> Void = {}) {
        self.init(
            onToggle: onToggle,
            onAudioToggle: onAudioToggle,
            onPauseResumeToggle: {}
        )
    }

    func start() {
        guard !isStarted else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        var installedHandler: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyEventHandler,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &installedHandler
        )
        guard handlerStatus == noErr else {
            print("[GlobalHotkeyMonitor] Failed to install event handler: \(handlerStatus)")
            return
        }
        eventHandlerRef = installedHandler

        for definition in [
            (keyCode: Self.recordingToggleKeyCode, id: Self.hotKeyID),
            (keyCode: Self.audioRecordingToggleKeyCode, id: Self.audioHotKeyID),
            (keyCode: Self.pauseResumeToggleKeyCode, id: Self.pauseResumeHotKeyID)
        ] {
            let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: definition.id)
            var registeredHotKey: EventHotKeyRef?
            let hotKeyStatus = RegisterEventHotKey(
                definition.keyCode,
                Self.toggleCarbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &registeredHotKey
            )
            guard hotKeyStatus == noErr, let registeredHotKey else {
                stop()
                print("[GlobalHotkeyMonitor] Failed to register global hotkey: \(hotKeyStatus)")
                return
            }
            hotKeyRefs.append(registeredHotKey)
        }

        isStarted = true
    }

    func stop() {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        isStarted = false
    }

    fileprivate func handleHotKeyActivated() {
        onToggle()
    }

    fileprivate func handleAudioHotKeyActivated() {
        onAudioToggle()
    }

    fileprivate func handlePauseResumeHotKeyActivated() {
        onPauseResumeToggle()
    }

    static func matchesRecordingToggle(for event: NSEvent) -> Bool {
        event.type == .keyDown
            && event.keyCode == recordingToggleKeyCode
            && event.modifierFlags.contains(recordingToggleModifiers)
            && !event.modifierFlags.contains(.option)
            && !event.modifierFlags.contains(.shift)
    }

    static func matchesAudioRecordingToggle(for event: NSEvent) -> Bool {
        event.type == .keyDown
            && event.keyCode == audioRecordingToggleKeyCode
            && event.modifierFlags.contains(recordingToggleModifiers)
            && !event.modifierFlags.contains(.option)
            && !event.modifierFlags.contains(.shift)
    }

    static func matchesPauseResumeToggle(for event: NSEvent) -> Bool {
        event.type == .keyDown
            && event.keyCode == pauseResumeToggleKeyCode
            && event.modifierFlags.contains(recordingToggleModifiers)
            && !event.modifierFlags.contains(.option)
            && !event.modifierFlags.contains(.shift)
    }

    deinit { stop() }
}

private let globalHotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return noErr }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr,
          hotKeyID.signature == GlobalHotkeyMonitor.hotKeySignature else {
        return noErr
    }

    let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        switch hotKeyID.id {
        case GlobalHotkeyMonitor.hotKeyID:
            monitor.handleHotKeyActivated()
        case GlobalHotkeyMonitor.audioHotKeyID:
            monitor.handleAudioHotKeyActivated()
        case GlobalHotkeyMonitor.pauseResumeHotKeyID:
            monitor.handlePauseResumeHotKeyActivated()
        default:
            break
        }
    }
    return noErr
}
