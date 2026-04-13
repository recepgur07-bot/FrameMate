# Recording Controls & System Integration Design
**Date:** 2026-04-10  
**Scope:** Grup A (Kayıt Kontrolü) + Grup B (Sistem Entegrasyonu)

---

## Goal

Make VideoRecorder behave like a professional macOS recording app. The app must be fully operable from the background (global hotkey), provide countdown feedback before recording, prevent system sleep during recording, and show a clear recording indicator in the menu bar. All features must be fully accessible via VoiceOver and audio cues.

---

## Grup A — Recording Controls

### A1. Global Keyboard Shortcut (Cmd+Shift+R)

**Current state:** `Cmd+R` via SwiftUI `keyboardShortcut` — only works when app is frontmost.

**New behaviour:** `Cmd+Shift+R` starts/stops recording regardless of which app is active.

**Implementation:**
- `GlobalHotkeyMonitor` — new class
- Registers both a **global** monitor (`NSEvent.addGlobalMonitorForEvents(matching: .keyDown)`) and a **local** monitor (`NSEvent.addLocalMonitorForEvents`) so the shortcut works whether the app is in the foreground or background
- `addGlobalMonitorForEvents` returns `nil` silently when Accessibility permission is not granted in System Settings → Privacy → Accessibility. The init must check for `nil` and log a warning; recording remains operable via the UI button. No crash, no throw.
- Checks keyCode 15 (`r`) + `.command + .shift` modifiers
- Calls `RecorderViewModel.toggleRecording()` via `DispatchQueue.main.async`
- Held for app lifetime in `VideoRecorderApp`

**Shortcut change — both locations:**
1. `VideoRecorderApp.swift` menu command: `keyboardShortcut("r", modifiers: [.command, .shift])`
2. `ContentView.swift` record button: `keyboardShortcut("r", modifiers: [.command, .shift])` — **both must be updated**

**VoiceOver hint** on record button updated to mention `Cmd+Shift+R`.

---

### A2. Recording Countdown

**New setting:** `RecordingCountdown` enum — `.none` (0s), `.three` (3s), `.five` (5s), `.ten` (10s). Default: `.none`. Persisted as `UserDefaults` key `recording.countdown`.

**State in `RecorderViewModel`:**
- `var countdownRemaining: Int = 0` — `> 0` means countdown is active (no separate `isCountingDown` bool; use computed `var isCountingDown: Bool { countdownRemaining > 0 }`)
- `@ObservationIgnored private var countdownTask: Task<Void, Never>?`
- `canStartRecording` updated: also guards on `!isCountingDown`

**Behaviour:**
- `toggleRecording()` called while `!isRecording && !isCountingDown`: if countdown > 0, start countdown task; else call `startRecording()` directly
- `toggleRecording()` called while `isCountingDown`: cancel task, announce "iptal edildi", reset `countdownRemaining = 0`
- Countdown task: each second decrements `countdownRemaining`, speaks via `SpeechCuePlayer` using the `speakIfNeeded(_:isEnabled:key:)` overload with `enforceFrequencyLimit: false` to bypass the frequency limiter. On `CancellationError`: caught, "iptal edildi" spoken, state reset. On completion: calls `startRecording()`.
- Status text during countdown: "Kayıt 3 saniye sonra başlıyor…"

---

### A3. Maximum Recording Duration

**New setting:** `MaxRecordingDuration` enum — `.unlimited`, `.five`, `.ten`, `.fifteen`, `.thirty`, `.sixty` (minutes). Default: `.unlimited`. Persisted as `UserDefaults` key `recording.maxDuration`.

**Implementation:**
- `@ObservationIgnored private var recordingDurationTask: Task<Void, Never>?` — Task-based async sleeping (not `Timer`) so it fires correctly while the app is backgrounded or a menu is open
- Started in `startRecording()` if duration != `.unlimited`
- On expiry: `stopRecording()` called on `@MainActor`, announces "Maksimum kayıt süresine ulaşıldı, kayıt durduruluyor", plays `playStop()` sound
- Cancelled in `stopRecording()`

---

## Grup B — System Integration

### B1. Menu Bar Presence During Recording

**Ownership:** `MenuBarController` is owned by `VideoRecorderApp` (not `RecorderViewModel`). `VideoRecorderApp` uses `.onChange(of: viewModel.isRecording)` to call `activate()` / `deactivate()`.

**`MenuBarController`** — new `@MainActor` class:
- Holds `NSStatusItem?`
- `activate(onStop: @escaping () -> Void)`: creates status item, sets red icon, builds menu with "Kaydı Durdur (⌘⇧R)" (calls `onStop` closure) + "Göster" (calls `NSApp.activate`). Starts pulse timer.
- `deactivate()`: invalidates pulse timer **first**, then removes status item, shows window via `NSApp.windows.first?.makeKeyAndOrderFront(nil)` + `NSApp.activate(ignoringOtherApps: true)`
- `onStop` closure passed as `{ [weak viewModel] in viewModel?.stopRecording() }` — avoids retain cycle. Do NOT pass `viewModel.stopRecording` directly as a method reference; that creates a strong capture.

**Window hide/show:**
- Recording starts: `NSApp.windows.first?.orderOut(nil)` — hides window, keeps Dock icon
- Recording stops (via `deactivate()`): `NSApp.windows.first?.makeKeyAndOrderFront(nil)` + `NSApp.activate(ignoringOtherApps: true)`
- **Do NOT use `NSApp.hide(nil)`** — that hides all windows and removes Dock presence

**Icon:** SF Symbol `record.circle.fill` rendered as `NSImage` from `NSImage(systemSymbolName:)`, tinted red.

---

### B2. Sleep & Screen Saver Prevention

**`SleepPreventer`** — new struct wrapping IOKit:

```swift
import IOKit.pwr_mgt

struct SleepPreventer {
    private var assertionID: IOPMAssertionID = 0
    mutating func prevent() { /* IOPMAssertionCreateWithName */ }
    mutating func allow()   { /* IOPMAssertionRelease */ }
}
```

Stored in `RecorderViewModel` as:
```swift
@ObservationIgnored private var sleepPreventer = SleepPreventer()
```

`@ObservationIgnored` is required — without it, every `mutating` call triggers SwiftUI observation diffing on `RecorderViewModel`, causing unnecessary view re-renders.

**`project.yml`** must add:
```yaml
dependencies:
  - framework: IOKit.framework
    embed: false
```

`prevent()` called in `startRecording()` after recording begins. `allow()` called in `stopRecording()`. Both are thread-safe IOKit calls, safe on `@MainActor`.

---

### B3. Recording Indicator (Menu Bar Pulse)

**In `MenuBarController`:**
- `@ObservationIgnored private var pulseTimer: Timer?`
- Timer scheduled on `.common` run loop mode so it fires during menu tracking and scroll events
- Every 0.8s: toggles icon alpha between 1.0 and 0.5
- `deactivate()` invalidates timer **before** removing status item to prevent dangling timer callback

---

## Settings Panel Additions

New section "Kayıt Ayarları" in existing Settings window:

| Setting | Type | Default | UserDefaults key |
|---|---|---|---|
| Geri sayım süresi | Picker (0/3/5/10 sn) | 0 sn | `recording.countdown` |
| Maksimum kayıt süresi | Picker (Sınırsız/5/10/15/30/60 dk) | Sınırsız | `recording.maxDuration` |

---

## Architecture Overview

```
VideoRecorderApp (app lifetime)
  ├── GlobalHotkeyMonitor  ← Cmd+Shift+R global + local
  ├── MenuBarController    ← owned here, driven by .onChange(of: viewModel.isRecording)
  └── RecorderViewModel
        ├── toggleRecording()         ← countdown → startRecording()
        ├── startRecording()          ← sleepPreventer.prevent()
        ├── stopRecording()           ← sleepPreventer.allow(), recordingDurationTask?.cancel()
        ├── @ObservationIgnored SleepPreventer
        ├── @ObservationIgnored countdownTask: Task?
        └── @ObservationIgnored recordingDurationTask: Task?
```

---

## Files Changed

| File | Change |
|---|---|
| `project.yml` | Add `IOKit.framework` dependency |
| `VideoRecorderApp.swift` | Add `GlobalHotkeyMonitor`, `MenuBarController`; update shortcut to `Cmd+Shift+R`; add `.onChange` for menu bar |
| `ContentView.swift` | Update record button shortcut to `Cmd+Shift+R`; update accessibilityHint; add countdown status display |
| `RecorderViewModel.swift` | Add countdown state + task, max-duration task, `SleepPreventer`, update `toggleRecording()` and `canStartRecording` |
| **New:** `GlobalHotkeyMonitor.swift` | Global + local event monitors |
| **New:** `MenuBarController.swift` | NSStatusItem, pulse timer, window hide/show |
| **New:** `SleepPreventer.swift` | IOKit power assertion wrapper |

---

## What Is NOT Changing

- Recording pipeline, export, frame coach, auto-reframe — untouched
- Existing `Cmd+1–4` mode shortcuts — untouched
- `Cmd+D` frame coach toggle — untouched
- File naming and output path — untouched (Grup C scope)
- `Info.plist` — no new usage description keys required for `NSEvent` global monitors
