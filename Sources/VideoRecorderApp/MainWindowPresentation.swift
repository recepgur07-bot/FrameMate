import AppKit

enum MainWindowPresentationAction: Equatable {
    case hide
    case show
}

struct MainWindowPresentationPolicy {
    let showWindowWhenRecordingStops: Bool
    let hideWindowOnRecordingStart: Bool

    init(showWindowWhenRecordingStops: Bool = true, hideWindowOnRecordingStart: Bool = true) {
        self.showWindowWhenRecordingStops = showWindowWhenRecordingStops
        self.hideWindowOnRecordingStart = hideWindowOnRecordingStart
    }

    func actionForRecordingStateChange(from previous: Bool, to current: Bool) -> MainWindowPresentationAction? {
        switch (previous, current) {
        case (false, true):
            return hideWindowOnRecordingStart ? .hide : nil
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
    private let hideApp: () -> Void
    private let unhideApp: () -> Void
    private let openMainWindow: () -> Void

    init(
        mainWindowProvider: @escaping () -> NSWindow? = {
            NSApp.mainWindow
                ?? NSApp.keyWindow
                ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey })
                ?? NSApp.windows.first(where: { $0.canBecomeKey })
        },
        activateApp: @escaping () -> Void = {
            NSApp.activate(ignoringOtherApps: true)
        },
        hideApp: @escaping () -> Void = {
            NSApp.hide(nil)
        },
        unhideApp: @escaping () -> Void = {
            NSApp.unhide(nil)
        },
        openMainWindow: @escaping () -> Void = {}
    ) {
        self.mainWindowProvider = mainWindowProvider
        self.activateApp = activateApp
        self.hideApp = hideApp
        self.unhideApp = unhideApp
        self.openMainWindow = openMainWindow
    }

    func hideMainWindow() {
        mainWindow()?.orderOut(nil)
        hideApp()
    }

    func showMainWindow() {
        unhideApp()
        activateApp()
        guard let window = mainWindow() else {
            openMainWindow()
            return
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func mainWindow() -> NSWindow? {
        mainWindowProvider()
    }
}
