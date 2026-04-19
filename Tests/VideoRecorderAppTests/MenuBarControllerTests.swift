import XCTest
@testable import FrameMate

@MainActor
final class MenuBarControllerTests: XCTestCase {
    func testActivateAndDeactivateDoNotCrash() {
        let controller = MenuBarController()
        var toggleCalled = false
        controller.install(
            onToggle: { toggleCalled = true },
            onShow: {},
            onOpenLastRecording: {},
            onRevealLastRecording: {},
            onOpenSettings: {},
            onQuit: {}
        )
        controller.deactivate()
        XCTAssertFalse(toggleCalled)
    }

    func testDoubleActivateDoesNotLeak() {
        let controller = MenuBarController()
        controller.install(
            onToggle: {},
            onShow: {},
            onOpenLastRecording: {},
            onRevealLastRecording: {},
            onOpenSettings: {},
            onQuit: {}
        )
        XCTAssertTrue(controller.isActive)
        controller.install(
            onToggle: {},
            onShow: {},
            onOpenLastRecording: {},
            onRevealLastRecording: {},
            onOpenSettings: {},
            onQuit: {}
        )
        XCTAssertTrue(controller.isActive)
        controller.deactivate()
        XCTAssertFalse(controller.isActive)
    }

    func testDeactivateWithoutActivateDoesNotCrash() {
        let controller = MenuBarController()
        controller.deactivate()
    }

    func testUpdateKeepsStatusItemInstalled() {
        let controller = MenuBarController()
        controller.install(
            onToggle: {},
            onShow: {},
            onOpenLastRecording: {},
            onRevealLastRecording: {},
            onOpenSettings: {},
            onQuit: {}
        )

        controller.update(isRecording: true, hasLastRecording: true)
        XCTAssertTrue(controller.isActive)

        controller.update(isRecording: false, hasLastRecording: false)
        XCTAssertTrue(controller.isActive)
    }

    func testReadyStateUpdatesTooltipAndStatusRow() {
        let controller = MenuBarController()
        controller.install(
            onToggle: {},
            onShow: {},
            onOpenLastRecording: {},
            onRevealLastRecording: {},
            onOpenSettings: {},
            onQuit: {}
        )

        controller.update(isRecording: false, hasLastRecording: true, lastRecordingName: "demo.mp4")

        XCTAssertEqual(controller.debugToolTip, "Son kayıt hazır: demo.mp4")
        XCTAssertEqual(controller.debugMenuTitles.first, "Durum: Son kayıt hazır (demo.mp4)")
    }

    func testMenuIncludesAudioRecordingShortcut() {
        let controller = MenuBarController()
        controller.install(
            onToggle: {},
            onAudioToggle: {},
            onShow: {},
            onOpenLastRecording: {},
            onRevealLastRecording: {},
            onOpenSettings: {},
            onQuit: {}
        )

        XCTAssertTrue(controller.debugMenuTitles.contains("Ses Kaydını Başlat (\(GlobalHotkeyMonitor.audioRecordingToggleDisplay))"))
    }

    func testMenuIncludesPauseResumeShortcutWhileRecording() {
        let controller = MenuBarController()
        controller.install(
            onToggle: {},
            onAudioToggle: {},
            onPauseResumeToggle: {},
            onShow: {},
            onOpenLastRecording: {},
            onRevealLastRecording: {},
            onOpenSettings: {},
            onQuit: {}
        )

        controller.update(isRecording: true, isPaused: false, hasLastRecording: false)

        XCTAssertTrue(controller.debugMenuTitles.contains("Duraklat (\(GlobalHotkeyMonitor.pauseResumeToggleDisplay))"))
    }

    func testMenuIncludesResumeShortcutWhilePaused() {
        let controller = MenuBarController()
        controller.install(
            onToggle: {},
            onAudioToggle: {},
            onPauseResumeToggle: {},
            onShow: {},
            onOpenLastRecording: {},
            onRevealLastRecording: {},
            onOpenSettings: {},
            onQuit: {}
        )

        controller.update(isRecording: true, isPaused: true, hasLastRecording: false)

        XCTAssertTrue(controller.debugMenuTitles.contains("Devam Et (\(GlobalHotkeyMonitor.pauseResumeToggleDisplay))"))
        XCTAssertEqual(controller.debugMenuTitles.first, "Durum: Kayıt duraklatıldı")
    }

    func testRecordingMenuShowsElapsedDuration() {
        let controller = MenuBarController()
        controller.install(
            onToggle: {},
            onAudioToggle: {},
            onPauseResumeToggle: {},
            onShow: {},
            onOpenLastRecording: {},
            onRevealLastRecording: {},
            onOpenSettings: {},
            onQuit: {}
        )

        controller.update(
            isRecording: true,
            isPaused: false,
            hasLastRecording: false,
            recordingDuration: 65
        )

        XCTAssertTrue(controller.debugMenuTitles.contains("Kayıt süresi: 01:05"))
    }

    func testMenuIncludesQuickPresetSection() {
        let controller = MenuBarController()
        controller.install(
            onToggle: {},
            onAudioToggle: {},
            onPauseResumeToggle: {},
            onSelectPreset: { _ in },
            onShow: {},
            onOpenLastRecording: {},
            onRevealLastRecording: {},
            onOpenSettings: {},
            onQuit: {}
        )

        XCTAssertTrue(controller.debugAllMenuTitles.contains("Hazır Çalışma Modları"))
        XCTAssertTrue(controller.debugAllMenuTitles.contains("Yatay video kaydı modu"))
        XCTAssertTrue(controller.debugAllMenuTitles.contains("Yatay ekran kaydı modu"))
        XCTAssertTrue(controller.debugAllMenuTitles.contains("Ses kaydı modu"))
    }
}
