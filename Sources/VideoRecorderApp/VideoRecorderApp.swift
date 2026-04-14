import SwiftUI

final class VideoRecorderAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            Self.showMainWindowIfAvailable()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Self.showMainWindowIfAvailable()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        sender.activate(ignoringOtherApps: true)
        Self.showMainWindowIfAvailable()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private static func showMainWindowIfAvailable() {
        guard let window = NSApp.windows.first(where: \.canBecomeKey) ?? NSApp.windows.first else { return }
        window.makeKeyAndOrderFront(nil)
    }
}

@main
struct VideoRecorderApp: App {
    @NSApplicationDelegateAdaptor(VideoRecorderAppDelegate.self) private var appDelegate
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    @State private var viewModel: RecorderViewModel
    private let hotkeyMonitor: GlobalHotkeyMonitor
    @MainActor private let menuBarController = MenuBarController()
    @MainActor private let mainWindowController = MainWindowController()
    private let mainWindowPresentationPolicy = MainWindowPresentationPolicy()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        let vm = RecorderViewModel()
        _viewModel = State(initialValue: vm)
        hotkeyMonitor = GlobalHotkeyMonitor(
            onToggle: { vm.toggleRecording() },
            onAudioToggle: { vm.toggleAudioRecording() },
            onPauseResumeToggle: { vm.togglePauseResume() }
        )
        hotkeyMonitor.start()
    }

    var body: some Scene {
        Window("Video Kaydedici", id: "main") {
            ContentView(viewModel: viewModel)
                .onAppear {
                    installMenuBarIfNeeded()
                    updateMenuBarState()
                }
                .onChange(of: viewModel.isRecording) { wasRecording, isRecording in
                    updateMenuBarState()
                    guard let action = mainWindowPresentationPolicy.actionForRecordingStateChange(
                        from: wasRecording,
                        to: isRecording
                    ) else { return }

                    switch action {
                    case .hide:
                        mainWindowController.hideMainWindow()
                    case .show:
                        mainWindowController.showMainWindow()
                    }
                }
                .onChange(of: viewModel.lastSavedURL) { _, _ in
                    updateMenuBarState()
                }
                .onChange(of: viewModel.isPaused) { _, _ in
                    updateMenuBarState()
                }
                .sheet(
                    isPresented: Binding(
                        get: { !onboardingCompleted },
                        set: { _ in }  // Kapatma yalnızca onDismiss callback'i üzerinden olur
                    )
                ) {
                    OnboardingView(
                        onDismiss: { onboardingCompleted = true },
                        viewModel: viewModel
                    )
                    .interactiveDismissDisabled(!onboardingCompleted)
                }
        }
        .defaultSize(width: 720, height: 680)
        .commands {
            CommandMenu("Kayıt Modu") {
                ForEach(RecordingPreset.allCases) { preset in
                    Button(preset.commandMenuLabel) {
                        viewModel.selectPreset(preset)
                    }
                    .keyboardShortcut(KeyEquivalent(preset.commandKey), modifiers: .command)
                }
            }

            CommandMenu("Kayıt") {
                Button("\(recordingCommandTitle) (\(GlobalHotkeyMonitor.recordingToggleDisplay))") {
                    viewModel.toggleRecording()
                }
                .disabled(!viewModel.canStartRecording && !viewModel.isRecording && !viewModel.isCountingDown)

                Button("\(audioRecordingCommandTitle) (\(GlobalHotkeyMonitor.audioRecordingToggleDisplay))") {
                    viewModel.toggleAudioRecording()
                }
                .disabled(viewModel.isPreparingRecording || (viewModel.isRecording && viewModel.selectedRecordingSource != .audio))
                .keyboardShortcut("5", modifiers: [.command, .control])

                Button("\(pauseResumeCommandTitle) (\(GlobalHotkeyMonitor.pauseResumeToggleDisplay))") {
                    viewModel.togglePauseResume()
                }
                .disabled(!viewModel.canPauseRecording)
                .keyboardShortcut("p", modifiers: [.command, .control])

                Button(frameCoachCommandTitle) {
                    viewModel.toggleFrameCoach()
                }
                .keyboardShortcut("d", modifiers: .command)
            }
        }

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }

    private var recordingCommandTitle: String {
        if viewModel.isPreparingRecording { return "Kayıt hazırlanıyor" }
        if viewModel.isCountingDown { return "Geri sayımı İptal Et (\(viewModel.countdownRemaining))" }
        return viewModel.isRecording ? "Kaydı Durdur" : "Kaydı Başlat"
    }

    private var audioRecordingCommandTitle: String {
        if viewModel.isRecording && viewModel.selectedRecordingSource == .audio {
            return "Ses Kaydını Durdur"
        }
        return "Ses Kaydını Başlat"
    }

    private var pauseResumeCommandTitle: String {
        viewModel.isPaused ? "Devam Et" : "Duraklat"
    }

    private var frameCoachCommandTitle: String {
        viewModel.isFrameCoachEnabled ? "Kadraj Koçunu Kapat" : "Kadraj Koçunu Aç"
    }

    @MainActor
    private func installMenuBarIfNeeded() {
        menuBarController.install(
            onToggle: { viewModel.toggleRecording() },
            onAudioToggle: { viewModel.toggleAudioRecording() },
            onPauseResumeToggle: { viewModel.togglePauseResume() },
            onShow: { mainWindowController.showMainWindow() },
            onOpenLastRecording: { viewModel.openLastSavedRecording() },
            onRevealLastRecording: { viewModel.revealLastSavedRecording() },
            onOpenSettings: {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
    }

    @MainActor
    private func updateMenuBarState() {
        menuBarController.update(
            isRecording: viewModel.isRecording,
            isPaused: viewModel.isPaused,
            hasLastRecording: viewModel.lastSavedURL != nil,
            lastRecordingName: viewModel.lastSavedURL?.lastPathComponent
        )
    }
}
