import AppKit

enum MainWindowPresentationAction: Equatable {
    case hide
    case show
}

struct MainWindowPresentationPolicy {
    let showWindowWhenRecordingStops: Bool

    init(showWindowWhenRecordingStops: Bool = true) {
        self.showWindowWhenRecordingStops = showWindowWhenRecordingStops
    }

    func actionForRecordingStateChange(from previous: Bool, to current: Bool) -> MainWindowPresentationAction? {
        switch (previous, current) {
        case (false, true):
            return .hide
        case (true, false):
            return showWindowWhenRecordingStops ? .show : nil
        default:
            return nil
        }
    }
}

struct AppTerminationPolicy {
    func shouldTerminateAfterLastWindowClosed(isRecording: Bool) -> Bool {
        !isRecording
    }
}

@MainActor
final class MainWindowController {
    private let mainWindowProvider: () -> NSWindow?
    private let activateApp: () -> Void
    private let openMainWindow: () -> Void

    init(
        mainWindowProvider: @escaping () -> NSWindow? = {
            NSApp.mainWindow
                ?? NSApp.keyWindow
                ?? NSApp.windows.first(where: { $0.isVisible })
                ?? NSApp.windows.first
        },
        activateApp: @escaping () -> Void = {
            NSApp.activate(ignoringOtherApps: true)
        },
        openMainWindow: @escaping () -> Void = {}
    ) {
        self.mainWindowProvider = mainWindowProvider
        self.activateApp = activateApp
        self.openMainWindow = openMainWindow
    }

    func hideMainWindow() {
        mainWindow()?.orderOut(nil)
    }

    func showMainWindow() {
        activateApp()
        guard let window = mainWindow() else {
            openMainWindow()
            return
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func mainWindow() -> NSWindow? {
        mainWindowProvider()
    }
}
