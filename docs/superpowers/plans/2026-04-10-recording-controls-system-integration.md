# Recording Controls & System Integration Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add global Cmd+Shift+R hotkey, recording countdown, max-duration auto-stop, menu bar indicator, and sleep prevention to VideoRecorder.

**Architecture:** Three new standalone types (`SleepPreventer`, `GlobalHotkeyMonitor`, `MenuBarController`) plus state additions to `RecorderViewModel`. `VideoRecorderApp` owns the new objects and wires them together via `.onChange`. All new state uses `@ObservationIgnored` to avoid spurious SwiftUI re-renders.

**Tech Stack:** Swift, SwiftUI, IOKit (sleep prevention), NSEvent (global hotkey), NSStatusItem (menu bar), AVSpeechSynthesizer (countdown speech via existing SpeechCuePlayer), XCTest.

**Spec:** `docs/superpowers/specs/2026-04-10-recording-controls-system-integration-design.md`

---

## Chunk 1: SleepPreventer

**Files:**
- Create: `Sources/VideoRecorderApp/SleepPreventer.swift`
- Create: `Tests/VideoRecorderAppTests/SleepPreventerTests.swift`
- Modify: `project.yml` — add IOKit.framework dependency

---

### Task 1: Add IOKit to project.yml and regenerate

- [ ] **Open** `project.yml`. Under `VideoRecorderApp` target, add after the `sources:` block (before `resources:`):

```yaml
    dependencies:
      - framework: IOKit.framework
        embed: false
```

- [ ] **Run xcodegen:**
```bash
cd "/Users/recepgur/Desktop/video recorder" && xcodegen generate
```
Expected: `Created project at .../VideoRecorder.xcodeproj`

---

### Task 2: Write SleepPreventer

- [ ] **Write failing test** `Tests/VideoRecorderAppTests/SleepPreventerTests.swift`:

```swift
import XCTest
@testable import VideoRecorderApp

final class SleepPreventerTests: XCTestCase {
    func testPreventAndAllowDoNotCrash() {
        var preventer = SleepPreventer()
        // Should not crash or throw
        preventer.prevent(reason: "Test recording")
        preventer.allow()
    }

    func testAllowWithoutPreventDoesNotCrash() {
        var preventer = SleepPreventer()
        preventer.allow() // no-op when no assertion held
    }

    func testDoublePreventReleasesFirst() {
        var preventer = SleepPreventer()
        preventer.prevent(reason: "First")
        preventer.prevent(reason: "Second") // should release first, then create new
        preventer.allow()
    }
}
```

- [ ] **Build to verify test file compiles (SleepPreventer doesn't exist yet — expect linker/type error):**
```bash
cd "/Users/recepgur/Desktop/video recorder" && xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' -only-testing:VideoRecorderAppTests/SleepPreventerTests 2>&1 | tail -20
```

- [ ] **Create** `Sources/VideoRecorderApp/SleepPreventer.swift`:

```swift
import IOKit.pwr_mgt

struct SleepPreventer {
    private var assertionID: IOPMAssertionID = 0
    private var isActive = false

    mutating func prevent(reason: String) {
        if isActive { allow() }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        isActive = (result == kIOReturnSuccess)
    }

    mutating func allow() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }
}
```

- [ ] **Run tests:**
```bash
cd "/Users/recepgur/Desktop/video recorder" && xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' -only-testing:VideoRecorderAppTests/SleepPreventerTests 2>&1 | tail -10
```
Expected: `TEST SUCCEEDED`

- [ ] **Commit:**
```bash
cd "/Users/recepgur/Desktop/video recorder" && git add Sources/VideoRecorderApp/SleepPreventer.swift Tests/VideoRecorderAppTests/SleepPreventerTests.swift project.yml VideoRecorder.xcodeproj && git commit -m "feat: add SleepPreventer with IOKit power assertion"
```

---

## Chunk 2: GlobalHotkeyMonitor

**Files:**
- Create: `Sources/VideoRecorderApp/GlobalHotkeyMonitor.swift`
- Create: `Tests/VideoRecorderAppTests/GlobalHotkeyMonitorTests.swift`

---

### Task 3: Write GlobalHotkeyMonitor

- [ ] **Write failing test** `Tests/VideoRecorderAppTests/GlobalHotkeyMonitorTests.swift`:

```swift
import XCTest
@testable import VideoRecorderApp

final class GlobalHotkeyMonitorTests: XCTestCase {
    func testStartAndStopDoNotCrash() {
        var callCount = 0
        let monitor = GlobalHotkeyMonitor(onToggle: { callCount += 1 })
        monitor.start()
        monitor.stop()
        // No crash = pass. callCount stays 0 (no synthetic event fired)
        XCTAssertEqual(callCount, 0)
    }

    func testDoubleStartDoesNotLeak() {
        let monitor = GlobalHotkeyMonitor(onToggle: {})
        monitor.start()
        monitor.start() // second call should be a no-op
        monitor.stop()
    }

    func testStopWithoutStartDoesNotCrash() {
        let monitor = GlobalHotkeyMonitor(onToggle: {})
        monitor.stop()
    }
}
```

- [ ] **Create** `Sources/VideoRecorderApp/GlobalHotkeyMonitor.swift`:

```swift
import AppKit

/// Listens for Cmd+Shift+R globally (even when app is in background) and locally.
/// Requires Accessibility permission in System Settings → Privacy → Accessibility.
/// If permission is not granted, the global monitor silently returns nil — local monitor still works.
final class GlobalHotkeyMonitor {
    private let onToggle: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
    }

    func start() {
        guard globalMonitor == nil else { return }

        let handler: (NSEvent) -> Void = { [weak self] event in
            guard event.keyCode == 15,
                  event.modifierFlags.contains([.command, .shift]),
                  !event.modifierFlags.contains(.option),
                  !event.modifierFlags.contains(.control) else { return }
            DispatchQueue.main.async { self?.onToggle() }
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
        if globalMonitor == nil {
            // Accessibility permission not granted — global hotkey inactive, local still works
            print("[GlobalHotkeyMonitor] Warning: global monitor unavailable (no Accessibility permission)")
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event)
            return event
        }
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    deinit { stop() }
}
```

- [ ] **Run tests:**
```bash
cd "/Users/recepgur/Desktop/video recorder" && xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' -only-testing:VideoRecorderAppTests/GlobalHotkeyMonitorTests 2>&1 | tail -10
```
Expected: `TEST SUCCEEDED`

- [ ] **Commit:**
```bash
cd "/Users/recepgur/Desktop/video recorder" && git add Sources/VideoRecorderApp/GlobalHotkeyMonitor.swift Tests/VideoRecorderAppTests/GlobalHotkeyMonitorTests.swift && git commit -m "feat: add GlobalHotkeyMonitor for Cmd+Shift+R"
```

---

## Chunk 3: RecorderViewModel — Countdown + Max Duration + SleepPreventer

**Files:**
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`
- Create: `Tests/VideoRecorderAppTests/RecorderViewModelCountdownTests.swift`

---

### Task 4: Add RecordingCountdown and MaxRecordingDuration enums

These go at the top of `RecorderViewModel.swift`, after the existing `FrameCoachRepeatInterval` enum (around line 84).

- [ ] **Add** after the closing `}` of `FrameCoachPreferences` struct (around line 84):

```swift
enum RecordingCountdown: Int, CaseIterable, Identifiable {
    case none = 0
    case three = 3
    case five = 5
    case ten = 10

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none: return "Yok"
        case .three: return "3 saniye"
        case .five: return "5 saniye"
        case .ten: return "10 saniye"
        }
    }
}

enum MaxRecordingDuration: Int, CaseIterable, Identifiable {
    case unlimited = 0
    case five = 5
    case ten = 10
    case fifteen = 15
    case thirty = 30
    case sixty = 60

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .unlimited: return "Sınırsız"
        case .five: return "5 dakika"
        case .ten: return "10 dakika"
        case .fifteen: return "15 dakika"
        case .thirty: return "30 dakika"
        case .sixty: return "60 dakika"
        }
    }

    var seconds: TimeInterval? {
        rawValue == 0 ? nil : TimeInterval(rawValue * 60)
    }
}
```

---

### Task 5: Add countdown + max duration state to RecorderViewModel

- [ ] **Add** these `@Observable` published properties near the other `var` declarations (around line 174, after `isPreparingRecording`):

```swift
    var countdownRemaining: Int = 0
    var recordingCountdown: RecordingCountdown = .none {
        didSet { UserDefaults.standard.set(recordingCountdown.rawValue, forKey: "recording.countdown") }
    }
    var maxRecordingDuration: MaxRecordingDuration = .unlimited {
        didSet { UserDefaults.standard.set(maxRecordingDuration.rawValue, forKey: "recording.maxDuration") }
    }
```

- [ ] **Add** these ignored properties near the `lastGoodFrameAt` declaration (around line 330):

```swift
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var recordingDurationTask: Task<Void, Never>?
    @ObservationIgnored private var sleepPreventer = SleepPreventer()
```

- [ ] **Add** computed property after `canStartRecording` (around line 316):

```swift
    var isCountingDown: Bool { countdownRemaining > 0 }
```

- [ ] **Update** `canStartRecording` to also guard on `!isCountingDown`. In every `return` branch, add `&& !isCountingDown`. Example for `.camera` branch:

```swift
        case .camera:
            return hasRequiredPermissions
                && (!isSystemAudioEnabled || screenRecordingPermissionStatus == .authorized)
                && !selectedCameraID.isEmpty
                && !selectedMicrophoneID.isEmpty
                && !isPreparingRecording
                && !isCountingDown
```
Apply the same `&& !isCountingDown` to `.screen` and `.window` branches.

- [ ] **Load saved settings** in the `setup()` function, alongside where other settings are loaded (search for `frameCoachSpeechMode =` and add near it):

```swift
        recordingCountdown = RecordingCountdown(rawValue: UserDefaults.standard.integer(forKey: "recording.countdown")) ?? .none
        maxRecordingDuration = MaxRecordingDuration(rawValue: UserDefaults.standard.integer(forKey: "recording.maxDuration")) ?? .unlimited
```

---

### Task 6: Update toggleRecording for countdown

- [ ] **Replace** the existing `toggleRecording()` (around line 559) with:

```swift
    func toggleRecording() {
        guard !isPreparingRecording else { return }

        if isRecording {
            stopRecording()
            return
        }

        if isCountingDown {
            cancelCountdown()
            return
        }

        if recordingCountdown == .none {
            startRecording()
        } else {
            beginCountdown()
        }
    }

    private func beginCountdown() {
        countdownRemaining = recordingCountdown.rawValue
        statusText = "Kayıt \(countdownRemaining) saniye sonra başlıyor…"
        countdownTask = Task { [weak self] in
            guard let self else { return }
            do {
                while await MainActor.run(body: { self.countdownRemaining }) > 0 {
                    let remaining = await MainActor.run(body: { self.countdownRemaining })
                    speechCuePlayer.speakIfNeeded(
                        "\(remaining)",
                        isEnabled: true,
                        key: "countdown-\(remaining)"
                    )
                    try await Task.sleep(for: .seconds(1))
                    await MainActor.run { self.countdownRemaining -= 1 }
                    await MainActor.run {
                        if self.countdownRemaining > 0 {
                            self.statusText = "Kayıt \(self.countdownRemaining) saniye sonra başlıyor…"
                        }
                    }
                }
                await MainActor.run { self.startRecording() }
            } catch {
                // CancellationError: cancelled via cancelCountdown()
                await MainActor.run {
                    self.countdownRemaining = 0
                    self.statusText = "İptal edildi"
                    self.speechCuePlayer.speakIfNeeded("iptal edildi", isEnabled: true, key: "countdown-cancel")
                }
            }
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        // statusText and countdownRemaining are reset inside the task's catch block
        // to avoid a race where cancelCountdown() sets "Hazır" after the catch block
        // already set "İptal edildi". The catch block is the single owner of cancel state.
    }
```

---

### Task 7: Add sleep prevention and max-duration to start/stopRecording

- [ ] **In** `startRecordingAsync()`, after `soundEffectPlayer.playStart()` (around line 753), add:

```swift
            sleepPreventer.prevent(reason: "Video kaydı devam ediyor")
            startMaxDurationTimer()
```

- [ ] **In** `stopRecording()`, after `soundEffectPlayer.playStop()` (around line 781), add:

```swift
        sleepPreventer.allow()
        recordingDurationTask?.cancel()
        recordingDurationTask = nil
```

- [ ] **Add** `startMaxDurationTimer()` as a private method:

```swift
    private func startMaxDurationTimer() {
        guard let limit = maxRecordingDuration.seconds else { return }
        recordingDurationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(limit))
                await MainActor.run { [weak self] in
                    guard let self, self.isRecording else { return }
                    self.speechCuePlayer.speakIfNeeded(
                        "Maksimum kayıt süresine ulaşıldı, kayıt durduruluyor",
                        isEnabled: true,
                        key: "max-duration-stop"
                    )
                    self.stopRecording()
                }
            } catch {
                // Cancelled when stopRecording() is called manually — normal
            }
        }
    }
```

---

### Task 8: Write countdown tests

- [ ] **Create** `Tests/VideoRecorderAppTests/RecorderViewModelCountdownTests.swift`:

```swift
import XCTest
@testable import VideoRecorderApp

@MainActor
final class RecorderViewModelCountdownTests: XCTestCase {
    func testIsCountingDownFalseWhenZero() {
        let vm = makeViewModel()
        XCTAssertFalse(vm.isCountingDown)
    }

    func testIsCountingDownTrueWhenPositive() {
        let vm = makeViewModel()
        vm.countdownRemaining = 3
        XCTAssertTrue(vm.isCountingDown)
    }

    func testCanStartRecordingFalseWhenCountingDown() {
        let vm = makeViewModel()
        vm.countdownRemaining = 3
        XCTAssertFalse(vm.canStartRecording)
    }

    // Smoke test: sets countdownRemaining directly (no Task started) to verify
    // that toggleRecording() calls cancelCountdown() and resets state synchronously.
    // The async Task cancellation path (CancellationError + speech cue) is exercised
    // at runtime; unit-testing it would require async expectations.
    func testToggleRecordingCancelsCountdownWhenCounting() {
        let vm = makeViewModel()
        vm.countdownRemaining = 3
        vm.toggleRecording()
        XCTAssertEqual(vm.countdownRemaining, 0)
        XCTAssertFalse(vm.isCountingDown)
    }

    func testRecordingCountdownDefaultIsNone() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.recordingCountdown, .none)
    }

    func testMaxRecordingDurationDefaultIsUnlimited() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.maxRecordingDuration, .unlimited)
    }

    func testMaxDurationUnlimitedHasNilSeconds() {
        XCTAssertNil(MaxRecordingDuration.unlimited.seconds)
    }

    func testMaxDurationFiveHasCorrectSeconds() {
        XCTAssertEqual(MaxRecordingDuration.five.seconds, 300)
    }

    private func makeViewModel() -> RecorderViewModel {
        RecorderViewModel(
            recorder: MockCaptureRecorder(),
            screenRecordingProvider: MockScreenRecordingProvider(),
            fileNamer: RecordingFileNamer(homeDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)),
            soundEffectPlayer: SoundEffectPlayer(),
            permissionProvider: MockMediaPermissionProvider(statuses: [:])
        )
    }
}
```

- [ ] **Run tests:**
```bash
cd "/Users/recepgur/Desktop/video recorder" && xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' -only-testing:VideoRecorderAppTests/RecorderViewModelCountdownTests 2>&1 | tail -10
```
Expected: `TEST SUCCEEDED`

- [ ] **Run full test suite to check for regressions:**
```bash
cd "/Users/recepgur/Desktop/video recorder" && xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: `TEST SUCCEEDED`

- [ ] **Commit:**
```bash
cd "/Users/recepgur/Desktop/video recorder" && git add Sources/VideoRecorderApp/RecorderViewModel.swift Tests/VideoRecorderAppTests/RecorderViewModelCountdownTests.swift && git commit -m "feat: add countdown, max duration, and sleep prevention to RecorderViewModel"
```

---

## Chunk 4: MenuBarController

**Files:**
- Create: `Sources/VideoRecorderApp/MenuBarController.swift`
- Create: `Tests/VideoRecorderAppTests/MenuBarControllerTests.swift`

---

### Task 9: Write MenuBarController

- [ ] **Write failing test** `Tests/VideoRecorderAppTests/MenuBarControllerTests.swift`:

```swift
import XCTest
@testable import VideoRecorderApp

@MainActor
final class MenuBarControllerTests: XCTestCase {
    func testActivateAndDeactivateDoNotCrash() {
        let controller = MenuBarController()
        var stopCalled = false
        controller.activate(onStop: { stopCalled = true })
        controller.deactivate()
        XCTAssertFalse(stopCalled)
    }

    func testDoubleActivateDoesNotLeak() {
        let controller = MenuBarController()
        controller.activate(onStop: {})
        controller.activate(onStop: {}) // should be a no-op
        controller.deactivate()
    }

    func testDeactivateWithoutActivateDoesNotCrash() {
        let controller = MenuBarController()
        controller.deactivate()
    }
}
```

- [ ] **Create** `Sources/VideoRecorderApp/MenuBarController.swift`:

```swift
import AppKit

/// Shows a pulsing red menu bar icon while recording is active.
/// Owned by VideoRecorderApp. Call activate() when recording starts, deactivate() when it stops.
@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private var pulseTimer: Timer?
    private var pulsePhase = false
    private var onStop: (() -> Void)?

    func activate(onStop: @escaping () -> Void) {
        guard statusItem == nil else { return }
        self.onStop = onStop

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = recordingIcon(alpha: 1.0)
        item.button?.toolTip = "Kayıt devam ediyor — Tıkla"
        item.menu = buildMenu()
        statusItem = item

        // Use Timer(timeInterval:) + RunLoop.main.add(.common) — NOT scheduledTimer —
        // to avoid double-scheduling. scheduledTimer adds to the current run loop in
        // .default mode; we then add again to .common, causing the timer to fire twice.
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.pulse()
        }
        RunLoop.main.add(timer, forMode: .common)
        pulseTimer = timer
    }

    func deactivate() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        onStop = nil
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func pulse() {
        pulsePhase.toggle()
        statusItem?.button?.image = recordingIcon(alpha: pulsePhase ? 1.0 : 0.5)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let stopItem = NSMenuItem(
            title: "Kaydı Durdur (⌘⇧R)",
            action: #selector(stopTapped),
            keyEquivalent: ""
        )
        stopItem.target = self
        menu.addItem(stopItem)
        menu.addItem(.separator())
        let showItem = NSMenuItem(
            title: "Uygulamayı Göster",
            action: #selector(showTapped),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)
        return menu
    }

    @objc private func stopTapped() {
        onStop?()
    }

    @objc private func showTapped() {
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func recordingIcon(alpha: CGFloat) -> NSImage {
        let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Kayıt")
            ?? NSImage(size: NSSize(width: 18, height: 18))
        let tinted = image.copy() as! NSImage
        tinted.lockFocus()
        NSColor.systemRed.withAlphaComponent(alpha).set()
        NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }
}
```

- [ ] **Run tests:**
```bash
cd "/Users/recepgur/Desktop/video recorder" && xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' -only-testing:VideoRecorderAppTests/MenuBarControllerTests 2>&1 | tail -10
```
Expected: `TEST SUCCEEDED`

- [ ] **Commit:**
```bash
cd "/Users/recepgur/Desktop/video recorder" && git add Sources/VideoRecorderApp/MenuBarController.swift Tests/VideoRecorderAppTests/MenuBarControllerTests.swift && git commit -m "feat: add MenuBarController with pulsing red icon during recording"
```

---

## Chunk 5: Wire Everything — VideoRecorderApp + Shortcuts + Settings

**Files:**
- Modify: `Sources/VideoRecorderApp/VideoRecorderApp.swift`
- Modify: `Sources/VideoRecorderApp/ContentView.swift` (shortcut + accessibilityHint + countdown text + settings)

---

### Task 10: Update VideoRecorderApp — wire global hotkey, menu bar, shortcut

- [ ] **Replace** the contents of `Sources/VideoRecorderApp/VideoRecorderApp.swift` with:

```swift
import SwiftUI

@main
struct VideoRecorderApp: App {
    @State private var viewModel = RecorderViewModel()
    private let hotkeyMonitor: GlobalHotkeyMonitor
    private let menuBarController = MenuBarController()

    init() {
        let vm = RecorderViewModel()
        _viewModel = State(initialValue: vm)
        hotkeyMonitor = GlobalHotkeyMonitor(onToggle: { vm.toggleRecording() })
        hotkeyMonitor.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onChange(of: viewModel.isRecording) { _, isRecording in
                    if isRecording {
                        menuBarController.activate(onStop: { [weak viewModel] in
                            viewModel?.stopRecording()
                        })
                        NSApp.windows.first?.orderOut(nil)
                    } else {
                        menuBarController.deactivate()
                    }
                }
        }
        .commands {
            CommandMenu("Mod") {
                ForEach(RecordingPreset.allCases) { preset in
                    Button(preset.menuLabel) {
                        viewModel.selectPreset(preset)
                    }
                    .keyboardShortcut(KeyEquivalent(preset.commandKey), modifiers: .command)
                }
            }

            CommandMenu("Kayıt") {
                Button(recordingCommandTitle) {
                    viewModel.toggleRecording()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!viewModel.canStartRecording && !viewModel.isRecording && !viewModel.isCountingDown)

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

    private var frameCoachCommandTitle: String {
        viewModel.isFrameCoachEnabled ? "Kadraj Koçunu Kapat" : "Kadraj Koçunu Aç"
    }
}
```

---

### Task 11: Update ContentView — shortcut + hint + countdown text

- [ ] **Find** line 253 in `ContentView.swift`:
```swift
            .keyboardShortcut("r", modifiers: .command)
```
Replace with:
```swift
            .keyboardShortcut("r", modifiers: [.command, .shift])
```

- [ ] **Find** line 256:
```swift
            .accessibilityHint("Komut R kısayolu ile de çalışır.")
```
Replace with:
```swift
            .accessibilityHint("Komut Shift R kısayolu ile uygulamanın dışından da çalışır.")
```

- [ ] **Find** `recordingButtonTitle` computed var (around line 332):
```swift
    private var recordingButtonTitle: String {
        if viewModel.isPreparingRecording {
```
Replace the whole var with:
```swift
    private var recordingButtonTitle: String {
        if viewModel.isPreparingRecording { return "Hazırlanıyor…" }
        if viewModel.isCountingDown { return "İptal Et (\(viewModel.countdownRemaining))" }
        return viewModel.isRecording ? "Kaydı Durdur" : "Kaydı Başlat"
    }
```

- [ ] **Find** the countdown status text display — add it just above the recording button (search for `Button(recordingButtonTitle)` around line 250). Add before the button:

```swift
            if viewModel.isCountingDown {
                Text("Kayıt \(viewModel.countdownRemaining) saniye sonra başlıyor…")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Geri sayım: \(viewModel.countdownRemaining) saniye")
            }
```

---

### Task 12: Add "Kayıt Ayarları" section to SettingsView

- [ ] **Find** the closing `}` of `Section("Erişilebilirlik ve Yönlendirme")` block (around line 407) in `ContentView.swift`. Add a new section immediately after it, before the outer `}` of `Form`:

```swift
            Section("Kayıt Ayarları") {
                Picker("Geri sayım süresi", selection: $viewModel.recordingCountdown) {
                    ForEach(RecordingCountdown.allCases) { countdown in
                        Text(countdown.label).tag(countdown)
                    }
                }
                .accessibilityHint("Kayıt başlatıldıktan sonra kaç saniye bekleyeceğini belirler.")

                Picker("Maksimum kayıt süresi", selection: $viewModel.maxRecordingDuration) {
                    ForEach(MaxRecordingDuration.allCases) { duration in
                        Text(duration.label).tag(duration)
                    }
                }
                .accessibilityHint("Bu süre dolunca kayıt otomatik olarak durur.")
            }
```

- [ ] **Update** the Settings window minimum height to accommodate the new section. Find `.frame(minWidth: 460, minHeight: 260)` and change to `.frame(minWidth: 460, minHeight: 380)`.

---

### Task 13: Build and run full test suite

- [ ] **Build:**
```bash
cd "/Users/recepgur/Desktop/video recorder" && xcodebuild build -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: `BUILD SUCCEEDED`

- [ ] **Run all tests:**
```bash
cd "/Users/recepgur/Desktop/video recorder" && xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: `TEST SUCCEEDED`

- [ ] **Commit:**
```bash
cd "/Users/recepgur/Desktop/video recorder" && git add Sources/VideoRecorderApp/VideoRecorderApp.swift Sources/VideoRecorderApp/ContentView.swift && git commit -m "feat: wire global hotkey, menu bar, countdown UI, and settings panel"
```

---

## Final Smoke Test Checklist

After all tasks:

- [ ] Build succeeds with no errors
- [ ] All tests pass
- [ ] App launches — window appears normally
- [ ] `Cmd+Shift+R` starts recording when app is frontmost
- [ ] `Cmd+Shift+R` starts recording when another app is frontmost (requires Accessibility permission)
- [ ] During recording: app window hides, red pulsing icon appears in menu bar
- [ ] Clicking menu bar icon → "Kaydı Durdur" stops recording, window reappears
- [ ] Setting countdown to 3s: pressing record button shows countdown text "3… 2… 1…", speech cues heard, recording starts
- [ ] Pressing `Cmd+Shift+R` during countdown cancels it
- [ ] Setting max duration to 5 min and recording: stops automatically after 5 minutes
- [ ] Sleep not triggered during recording (System Settings → Battery → no sleep during test)
- [ ] Settings window shows "Kayıt Ayarları" section with two pickers
