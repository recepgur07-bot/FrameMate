import SwiftUI

extension Notification.Name {
    static let openMainWindowRequested = Notification.Name("openMainWindowRequested")
}

final class VideoRecorderAppDelegate: NSObject, NSApplicationDelegate {
    static var shouldTerminateAfterLastWindowClosed: () -> Bool = { true }

    /// Uygulama kapanmadan önce çağrılır: aktif kaydı durdur, hotkey handler'larını temizle.
    var onWillTerminate: (() -> Void)?

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
        Self.shouldTerminateAfterLastWindowClosed()
    }

    func applicationWillTerminate(_ notification: Notification) {
        onWillTerminate?()
    }

    private static func showMainWindowIfAvailable() {
        guard let window = NSApp.windows.first(where: \.canBecomeKey) ?? NSApp.windows.first else {
            NotificationCenter.default.post(name: .openMainWindowRequested, object: "main")
            return
        }
        window.makeKeyAndOrderFront(nil)
    }
}

private struct MainWindowRootView: View {
    @Environment(\.openWindow) private var openWindow

    let viewModel: RecorderViewModel
    let mainWindowController: MainWindowController
    @Binding var hasInstalledMainWindowOpenAction: Bool

    var body: some View {
        ContentView(viewModel: viewModel)
            .onAppear {
                guard !hasInstalledMainWindowOpenAction else { return }
                hasInstalledMainWindowOpenAction = true
                NotificationCenter.default.addObserver(
                    forName: .openMainWindowRequested,
                    object: nil,
                    queue: .main
                ) { notification in
                    guard let id = notification.object as? String else { return }
                    openWindow(id: id)
                }
            }
    }
}

@main
struct VideoRecorderApp: App {
    @NSApplicationDelegateAdaptor(VideoRecorderAppDelegate.self) private var appDelegate
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    @AppStorage(AppBehaviorPreferenceKey.hideWindowOnRecordingStart) private var hideWindowOnRecordingStart = true
    @AppStorage(AppBehaviorPreferenceKey.showWindowWhenRecordingStops) private var showWindowWhenRecordingStops = true
    @AppStorage(AppBehaviorPreferenceKey.activationPolicy) private var activationPolicyPreference = AppActivationPolicyPreference.regular.rawValue
    @AppStorage(AppBehaviorPreferenceKey.launchAtLogin) private var launchAtLogin = false
    @State private var viewModel: RecorderViewModel
    @State private var menuBarRefreshTimer: Timer?
    @State private var hasInstalledMainWindowOpenAction = false
    private let hotkeyMonitor: GlobalHotkeyMonitor
    @MainActor private let menuBarController = MenuBarController()
    @MainActor private let mainWindowController: MainWindowController
    private let launchAtLoginController: any LaunchAtLoginControlling

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        let vm = RecorderViewModel()
        _viewModel = State(initialValue: vm)
        let mainWindowID = "main"
        mainWindowController = MainWindowController(
            openMainWindow: {
                NotificationCenter.default.post(
                    name: .openMainWindowRequested,
                    object: mainWindowID
                )
            }
        )
        launchAtLoginController = SMAppLaunchAtLoginController()
        hotkeyMonitor = GlobalHotkeyMonitor(
            onToggle: { vm.toggleRecording() },
            onAudioToggle: { vm.toggleAudioRecording() },
            onPauseResumeToggle: { vm.togglePauseResume() }
        )
        VideoRecorderAppDelegate.shouldTerminateAfterLastWindowClosed = {
            AppTerminationPolicy().shouldTerminateAfterLastWindowClosed(isRecording: vm.isRecording)
        }
        hotkeyMonitor.start()
    }

    var body: some Scene {
        Window("FrameMate", id: "main") {
            MainWindowRootView(
                viewModel: viewModel,
                mainWindowController: mainWindowController,
                hasInstalledMainWindowOpenAction: $hasInstalledMainWindowOpenAction
            )
                .onAppear {
                    applyActivationPolicy()
                    syncLaunchAtLogin()
                    installMenuBarIfNeeded()
                    updateMenuBarState()
                    appDelegate.onWillTerminate = {
                        if viewModel.isRecording {
                            viewModel.stopRecording()
                        }
                        hotkeyMonitor.stop()
                    }
                }
                .onChange(of: viewModel.isRecording) { wasRecording, isRecording in
                    updateMenuBarRefreshTimer(isRecording: isRecording)
                    updateMenuBarState()
                    let isScreenMode = viewModel.selectedRecordingSource == .screen
                        || viewModel.selectedRecordingSource == .window
                    guard let action = MainWindowPresentationPolicy(
                        showWindowWhenRecordingStops: showWindowWhenRecordingStops,
                        hideWindowOnRecordingStart: hideWindowOnRecordingStart && isScreenMode
                    ).actionForRecordingStateChange(
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
                .onChange(of: viewModel.completedRecording) { _, newRecording in
                    guard newRecording != nil, showWindowWhenRecordingStops else { return }
                    mainWindowController.showMainWindow()
                }
                .onChange(of: viewModel.lastSavedURL) { _, _ in
                    updateMenuBarState()
                }
                .onChange(of: viewModel.isPaused) { _, _ in
                    updateMenuBarState()
                }
                .onChange(of: activationPolicyPreference) { _, _ in
                    applyActivationPolicy()
                }
                .onChange(of: launchAtLogin) { _, _ in
                    syncLaunchAtLogin()
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
                .onDisappear {
                    menuBarRefreshTimer?.invalidate()
                    menuBarRefreshTimer = nil
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
                    .disabled(!onboardingCompleted)
                }
            }

            CommandMenu("Kayıt") {
                Button("\(recordingCommandTitle) (\(GlobalHotkeyMonitor.recordingToggleDisplay))") {
                    viewModel.toggleRecording()
                }
                .disabled(!onboardingCompleted || (!viewModel.canStartRecording && !viewModel.isRecording && !viewModel.isCountingDown))

                Button("\(audioRecordingCommandTitle) (\(GlobalHotkeyMonitor.audioRecordingToggleDisplay))") {
                    viewModel.toggleAudioRecording()
                }
                .disabled(!onboardingCompleted || viewModel.isPreparingRecording || (viewModel.isRecording && viewModel.selectedRecordingSource != .audio))
                .keyboardShortcut("5", modifiers: [.command, .control])

                Button("\(pauseResumeCommandTitle) (\(GlobalHotkeyMonitor.pauseResumeToggleDisplay))") {
                    viewModel.togglePauseResume()
                }
                .disabled(!onboardingCompleted || !viewModel.canPauseRecording)
                .keyboardShortcut("p", modifiers: [.command, .control])

                Button(frameCoachCommandTitle) {
                    viewModel.toggleFrameCoach()
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(!onboardingCompleted)

                Button(String(localized: "Mevcut Ayarları Duyur")) {
                    viewModel.announceCurrentSettings()
                }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(!onboardingCompleted)
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
            onSelectPreset: { preset in viewModel.selectPreset(preset) },
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
            lastRecordingName: viewModel.lastSavedURL?.lastPathComponent,
            recordingDuration: viewModel.currentRecordingDuration
        )
    }

    @MainActor
    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(currentActivationPolicy.resolvedPolicy)
    }

    @MainActor
    private func syncLaunchAtLogin() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        do {
            try launchAtLoginController.setEnabled(launchAtLogin)
        } catch {
            NSLog("Failed to update launch-at-login setting: \(error.localizedDescription)")
        }
    }

    private var currentActivationPolicy: AppActivationPolicyPreference {
        AppActivationPolicyPreference(rawValue: activationPolicyPreference) ?? .regular
    }

    @MainActor
    private func updateMenuBarRefreshTimer(isRecording: Bool) {
        menuBarRefreshTimer?.invalidate()
        menuBarRefreshTimer = nil

        guard isRecording else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                updateMenuBarState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        menuBarRefreshTimer = timer
    }
}
