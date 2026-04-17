import AppKit

enum MainWindowPresentationAction: Equatable {
    case hide
    case show
}

struct MainWindowPresentationPolicy {
    func actionForRecordingStateChange(from previous: Bool, to current: Bool) -> MainWindowPresentationAction? {
        switch (previous, current) {
        case (true, false):
            return .show
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
    func hideMainWindow() {
        mainWindow()?.orderOut(nil)
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        guard let window = mainWindow() else { return }
        window.makeKeyAndOrderFront(nil)
    }

    private func mainWindow() -> NSWindow? {
        NSApp.mainWindow
            ?? NSApp.keyWindow
            ?? NSApp.windows.first(where: { $0.isVisible })
            ?? NSApp.windows.first
    }
}
