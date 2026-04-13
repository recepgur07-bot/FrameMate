import AppKit

/// Shows a pulsing red menu bar icon while recording is active.
/// Owned by VideoRecorderApp. Call activate() when recording starts, deactivate() when it stops.
@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private var pulseTimer: Timer?
    private var pulsePhase = false
    private var isRecording = false
    private var isPaused = false
    private var hasLastRecording = false
    private var lastRecordingName: String?
    private var onToggle: (() -> Void)?
    private var onAudioToggle: (() -> Void)?
    private var onPauseResumeToggle: (() -> Void)?
    private var onShow: (() -> Void)?
    private var onOpenLastRecording: (() -> Void)?
    private var onRevealLastRecording: (() -> Void)?
    private var onOpenSettings: (() -> Void)?
    private var onQuit: (() -> Void)?

    var isActive: Bool { statusItem != nil }

    func install(
        onToggle: @escaping () -> Void,
        onAudioToggle: @escaping () -> Void,
        onPauseResumeToggle: @escaping () -> Void = {},
        onShow: @escaping () -> Void,
        onOpenLastRecording: @escaping () -> Void,
        onRevealLastRecording: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onToggle = onToggle
        self.onAudioToggle = onAudioToggle
        self.onPauseResumeToggle = onPauseResumeToggle
        self.onShow = onShow
        self.onOpenLastRecording = onOpenLastRecording
        self.onRevealLastRecording = onRevealLastRecording
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit

        guard statusItem == nil else {
            rebuildMenu()
            updateAppearance()
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        rebuildMenu()
        updateAppearance()
    }

    func install(
        onToggle: @escaping () -> Void,
        onAudioToggle: @escaping () -> Void = {},
        onShow: @escaping () -> Void,
        onOpenLastRecording: @escaping () -> Void,
        onRevealLastRecording: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        install(
            onToggle: onToggle,
            onAudioToggle: onAudioToggle,
            onPauseResumeToggle: {},
            onShow: onShow,
            onOpenLastRecording: onOpenLastRecording,
            onRevealLastRecording: onRevealLastRecording,
            onOpenSettings: onOpenSettings,
            onQuit: onQuit
        )
    }

    func activate(onStop: @escaping () -> Void, onShow: @escaping () -> Void) {
        install(
            onToggle: onStop,
            onAudioToggle: {},
            onPauseResumeToggle: {},
            onShow: onShow,
            onOpenLastRecording: {},
            onRevealLastRecording: {},
            onOpenSettings: {},
            onQuit: {}
        )
        update(isRecording: true, isPaused: false, hasLastRecording: hasLastRecording)
    }

    func update(isRecording: Bool, isPaused: Bool = false, hasLastRecording: Bool, lastRecordingName: String? = nil) {
        self.isRecording = isRecording
        self.isPaused = isRecording && isPaused
        self.hasLastRecording = hasLastRecording
        self.lastRecordingName = lastRecordingName
        rebuildMenu()
        updateAppearance()
    }

    func update(isRecording: Bool, hasLastRecording: Bool, lastRecordingName: String? = nil) {
        update(
            isRecording: isRecording,
            isPaused: false,
            hasLastRecording: hasLastRecording,
            lastRecordingName: lastRecordingName
        )
    }

    func deactivate() {
        stopPulsing()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        onToggle = nil
        onAudioToggle = nil
        onPauseResumeToggle = nil
        onShow = nil
        onOpenLastRecording = nil
        onRevealLastRecording = nil
        onOpenSettings = nil
        onQuit = nil
    }

    private func pulse() {
        pulsePhase.toggle()
        statusItem?.button?.image = recordingIcon(alpha: pulsePhase ? 1.0 : 0.5)
    }

    private func updateAppearance() {
        guard let button = statusItem?.button else { return }
        button.image = currentStatusIcon()
        button.toolTip = currentToolTip

        if isRecording && !isPaused {
            startPulsing()
        } else {
            stopPulsing()
        }
    }

    private func currentStatusIcon() -> NSImage {
        if isRecording {
            return recordingIcon(alpha: 1.0)
        }
        if hasLastRecording {
            return readyIcon()
        }
        return idleIcon()
    }

    private var currentToolTip: String {
        if isRecording {
            return isPaused ? "Kayıt duraklatıldı" : "Kayıt devam ediyor"
        }
        if hasLastRecording, let lastRecordingName {
            return "Son kayıt hazır: \(lastRecordingName)"
        }
        if hasLastRecording {
            return "Son kayıt hazır"
        }
        return "Video Kaydedici"
    }

    private func startPulsing() {
        guard pulseTimer == nil else { return }
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.pulse()
        }
        RunLoop.main.add(timer, forMode: .common)
        pulseTimer = timer
    }

    private func stopPulsing() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulsePhase = false
    }

    private func rebuildMenu() {
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let statusItem = makeMenuItem(title: currentStatusLine, action: nil)
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(.separator())

        let toggleItem = NSMenuItem(
            title: isRecording
                ? "Kaydı Durdur (\(GlobalHotkeyMonitor.recordingToggleDisplay))"
                : "Kaydı Başlat (\(GlobalHotkeyMonitor.recordingToggleDisplay))",
            action: #selector(toggleTapped),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let audioToggleItem = NSMenuItem(
            title: isRecording
                ? "Ses Kaydını Durdur (\(GlobalHotkeyMonitor.audioRecordingToggleDisplay))"
                : "Ses Kaydını Başlat (\(GlobalHotkeyMonitor.audioRecordingToggleDisplay))",
            action: #selector(audioToggleTapped),
            keyEquivalent: ""
        )
        audioToggleItem.target = self
        menu.addItem(audioToggleItem)

        let pauseResumeItem = NSMenuItem(
            title: isPaused
                ? "Devam Et (\(GlobalHotkeyMonitor.pauseResumeToggleDisplay))"
                : "Duraklat (\(GlobalHotkeyMonitor.pauseResumeToggleDisplay))",
            action: #selector(pauseResumeTapped),
            keyEquivalent: ""
        )
        pauseResumeItem.target = self
        pauseResumeItem.isEnabled = isRecording
        menu.addItem(pauseResumeItem)
        menu.addItem(.separator())

        menu.addItem(makeMenuItem(title: "Ana Pencereyi Göster", action: #selector(showTapped)))

        let openLastItem = makeMenuItem(title: "Son Kaydı Aç", action: #selector(openLastRecordingTapped))
        openLastItem.isEnabled = hasLastRecording
        menu.addItem(openLastItem)

        let revealLastItem = makeMenuItem(title: "Klasörde Göster", action: #selector(revealLastRecordingTapped))
        revealLastItem.isEnabled = hasLastRecording
        menu.addItem(revealLastItem)

        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Ayarlar", action: #selector(openSettingsTapped)))
        menu.addItem(makeMenuItem(title: "Çık", action: #selector(quitTapped)))
        return menu
    }

    private var currentStatusLine: String {
        if isRecording {
            return isPaused ? "Durum: Kayıt duraklatıldı" : "Durum: Kayıt yapılıyor"
        }
        if hasLastRecording, let lastRecordingName {
            return "Durum: Son kayıt hazır (\(lastRecordingName))"
        }
        if hasLastRecording {
            return "Durum: Son kayıt hazır"
        }
        return "Durum: Hazır"
    }

    private func makeMenuItem(title: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private nonisolated func toggleTapped() {
        Task { @MainActor in self.onToggle?() }
    }

    @objc private nonisolated func audioToggleTapped() {
        Task { @MainActor in self.onAudioToggle?() }
    }

    @objc private nonisolated func pauseResumeTapped() {
        Task { @MainActor in self.onPauseResumeToggle?() }
    }

    @objc private nonisolated func showTapped() {
        Task { @MainActor in
            self.onShow?()
        }
    }

    @objc private nonisolated func openLastRecordingTapped() {
        Task { @MainActor in
            self.onOpenLastRecording?()
        }
    }

    @objc private nonisolated func revealLastRecordingTapped() {
        Task { @MainActor in
            self.onRevealLastRecording?()
        }
    }

    @objc private nonisolated func openSettingsTapped() {
        Task { @MainActor in
            self.onOpenSettings?()
        }
    }

    @objc private nonisolated func quitTapped() {
        Task { @MainActor in
            self.onQuit?()
        }
    }

    private func recordingIcon(alpha: CGFloat) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let symbol = (NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Kayıt")?
            .withSymbolConfiguration(config)) ?? NSImage(size: NSSize(width: 16, height: 16))
        let size = symbol.size.width > 0 ? symbol.size : NSSize(width: 16, height: 16)
        return NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.systemRed.withAlphaComponent(alpha).set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    private func idleIcon() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        return (NSImage(systemSymbolName: "video", accessibilityDescription: "Video Kaydedici")?
            .withSymbolConfiguration(config)) ?? NSImage(size: NSSize(width: 16, height: 16))
    }

    private func readyIcon() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        return (NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Son kayıt hazır")?
            .withSymbolConfiguration(config)) ?? NSImage(size: NSSize(width: 16, height: 16))
    }

    var debugToolTip: String? { statusItem?.button?.toolTip }
    var debugMenuTitles: [String] { statusItem?.menu?.items.map(\.title) ?? [] }
}
