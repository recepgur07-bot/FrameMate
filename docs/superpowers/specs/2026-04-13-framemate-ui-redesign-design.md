# FrameMate UI Redesign — Design Spec
Date: 2026-04-13

## Overview

Complete visual redesign of the macOS video recorder app, rebranded as **FrameMate**. The goal is to transform the current plain VStack layout into a polished, professional-grade macOS application that competes visually with Loom and CleanShot X, while preserving 100% of existing accessibility support.

Design direction: **Light Minimal** — clean white/adaptive surfaces, strong indigo brand color, large prominent record button, SF Symbols throughout, card-based layout.

---

## 1. Branding

### App Name
- **FrameMate** (replaces "Video Kaydedici" everywhere in the UI)
- All user-visible strings updated accordingly
- Bundle display name updated in Info.plist

### Color Tokens (defined as SwiftUI extension)
```swift
extension Color {
    static let fmAccent     = Color(red: 0.357, green: 0.298, blue: 0.961) // #5B4CF5 indigo
    static let fmRecord     = Color(red: 1.0,   green: 0.231, blue: 0.188) // #FF3B30 system red
    static let fmPause      = Color.orange
    static let fmReady      = Color.green
    static let fmCardBg     = Color(nsColor: .controlBackgroundColor)
    static let fmSurface    = Color(nsColor: .windowBackgroundColor)
}
```

### Typography
- App title "FrameMate": `.largeTitle` weight `.bold`, color `.fmAccent`
- Section headers: `.subheadline` weight `.semibold`, `.secondary`
- Body labels: `.body` regular
- Status text: `.caption` weight `.medium`

---

## 2. Layout Architecture

The window is reorganised into four vertical zones:

```
┌──────────────────────────────────────┐
│  HEADER ZONE                         │  Fixed, always visible
│  Logo + "FrameMate" + status pill    │
├──────────────────────────────────────┤
│  MODE ZONE                           │  Fixed, always visible
│  Segmented mode picker with icons    │
├──────────────────────────────────────┤
│  CONTENT ZONE  (ScrollView)          │  Scrollable
│  Preview card                        │
│  Collapsible control cards           │
├──────────────────────────────────────┤
│  ACTION ZONE                         │  Fixed, always visible
│  Record button + pause + status      │
└──────────────────────────────────────┘
```

Window minimum size: `620 × 640 pt`

---

## 3. Header Zone

### Layout
`HStack` — icon + title on left, status pill on right.

### App Icon Mark
SF Symbol `record.circle.fill` in `.fmAccent`, size 28pt. Placed left of title.

### Title
`Text("FrameMate")` — `.largeTitle`, `.bold`, color `.fmAccent`.

### Status Pill
A small capsule badge showing current state:
- ⬤ Hazır — green dot + "Hazır" text
- ⬤ Kayıt — red dot + "Kayıt" text, subtle pulse animation
- ⬤ Duraklatıldı — orange dot + "Duraklatıldı" text
- ⬤ Hazırlanıyor — gray dot + "Hazırlanıyor" text

```swift
struct StatusPill: View {
    // capsule shape, .caption font, colored dot, 8pt h-padding, 4pt v-padding
    // background: status color at 0.12 opacity
    // foreground: status color
}
```

Accessibility: `.accessibilityLabel("Durum: \(statusText)")` on the pill.

---

## 4. Mode Zone

Replaces the plain `Picker` with a custom segmented control using SF Symbols + labels.

The `RecordingPreset` enum has five cases: `horizontalCamera`, `verticalCamera`, `horizontalScreen`, `verticalScreen`, `audioOnly`. These map to the segmented control as follows:

### Primary Mode Segments (4 segments)
| Segment | SF Symbol | Label | Covers presets |
|---------|-----------|-------|----------------|
| Kamera | `camera.fill` | Kamera | `horizontalCamera`, `verticalCamera` |
| Ekran | `desktopcomputer` | Ekran | `horizontalScreen`, `verticalScreen` |
| Ekran+Kamera | `rectangle.inset.filled.on.rectangle` | Ekran+Kamera | `horizontalScreen` + overlay enabled |
| Ses | `waveform.circle.fill` | Ses | `audioOnly` |

### Orientation Toggle
When the selected primary mode is **Kamera** or **Ekran**, a small horizontal/vertical toggle appears below the mode selector:
- Two buttons: `rectangle.portrait.fill` (Dikey) and `rectangle.fill` (Yatay)
- Selecting Yatay → maps to `horizontalCamera` / `horizontalScreen`
- Selecting Dikey → maps to `verticalCamera` / `verticalScreen`
- Hidden for Ekran+Kamera and Ses modes (always horizontal)
- Default: Yatay selected

This means `FMModeSelector` holds two pieces of state: selected primary mode + orientation. It computes the final `RecordingPreset` from the combination and calls `viewModel.selectPreset(_:)`.

**Ekran+Kamera special case:** There is no dedicated `RecordingPreset` case for screen+camera — it is `horizontalScreen` with the camera overlay enabled. When the user selects the Ekran+Kamera segment, `FMModeSelector` must:
1. Call `viewModel.selectPreset(.horizontalScreen)`
2. If `viewModel.isScreenCameraOverlayEnabled == false`, call `viewModel.toggleScreenCameraOverlay()`

Deselecting this segment (switching to another mode) does not automatically disable the overlay.

### Visual Treatment
- Selected segment: `.fmAccent` background (rounded), white icon + label
- Unselected: transparent background, `.secondary` color
- Capsule shape, 8pt corner radius
- Smooth spring animation on selection change

### VoiceOver Labels (explicit)
- Group container: `.accessibilityLabel("Kayıt modu seçimi")`
- Each segment button: `.accessibilityLabel("<Label>")` e.g. "Kamera", "Ekran", "Ekran ve Kamera", "Ses"
- Each segment button: `.accessibilityHint("Bu kayıt modunu seçer")`
- Orientation toggle buttons: `.accessibilityLabel("Yatay")` / `.accessibilityLabel("Dikey")`
- Orientation group: `.accessibilityLabel("Yönlendirme seçimi")`

---

## 5. Content Zone (ScrollView)

All sections are wrapped in `FMCard` — a reusable card component:

```swift
struct FMCard<Content: View>: View {
    let icon: String       // SF Symbol name
    let title: String
    let content: Content
    // RoundedRectangle(cornerRadius: 12)
    // background: .fmCardBg
    // shadow: color Color.primary.opacity(0.06), radius 4, y 2  ← adapts to Dark Mode
    // padding: 16pt internal
    // icon tinted .fmAccent, .accessibilityHidden(true) (decorative)
}
```

### Preview Card
- Corner radius 12pt, overflow `.hidden`
- Subtle border: `Color.secondary.opacity(0.15)`, lineWidth 1
- Aspect ratio preserved

### FMCard Full Signature
```swift
struct FMCard<Content: View>: View {
    let icon: String        // SF Symbol name, tinted .fmAccent, .accessibilityHidden(true)
    let title: String       // section header, .subheadline .semibold
    let isCollapsible: Bool // if true, shows chevron and toggles expanded state
    @State private var isExpanded: Bool = true
    @ViewBuilder let content: () -> Content

    // Collapsed state: shows only icon + title row + chevron
    // Expanded state: shows icon + title + content below
    // Chevron: "chevron.down" rotates 180° when collapsed, spring animation
    // Cards start expanded (isExpanded = true) and do not persist state between launches
}
```

### Control Cards (collapsible)
Each section becomes a collapsible `FMCard`. Sections:

1. **Ses** — icon `mic.fill`
   - Microphone picker
   - System audio toggle
   - Volume sliders (when visible)

2. **Kaynak** — icon `desktopcomputer` (screen modes only)
   - Screen source picker
   - Display / window picker

3. **Görüntü** — icon `eye.fill` (screen modes only)
   - Cursor highlight toggle
   - Keyboard shortcut overlay toggle

4. **Kamera Kutusu** — icon `rectangle.inset.filled.on.rectangle` (screen+camera mode)
   - Overlay enable toggle
   - Position picker
   - Size picker

### Toggle Styling
All `Toggle` items get an SF Symbol icon to the left:
- Sistem sesi: `speaker.wave.2.fill`
- İmleci vurgula: `cursorarrow.rays`
- Klavye kısayolları: `keyboard`
- Kamera kutusu: `rectangle.inset.filled.on.rectangle`
- Otomatik kadrajlama: `viewfinder`

### Permission Banners — Placement Mapping
Each permission type renders as an inline warning banner inside its relevant card:

| Permission | Card | Condition |
|------------|------|-----------|
| Camera notDetermined | **Ses** card (top) | `showsCameraControls || showsScreenOverlayConfiguration` |
| Camera denied | **Ses** card (top) | same |
| Microphone notDetermined | **Ses** card (bottom) | always |
| Microphone denied | **Ses** card (bottom) | always |
| Screen recording denied | **Kaynak** card (top) | `showsScreenControls || isSystemAudioEnabled` |

Banner anatomy: `HStack` — `exclamationmark.triangle.fill` (orange, `.accessibilityHidden(true)`) + warning text (`.caption`) + `Button("Ayarları Aç")`. Background: `.orange.opacity(0.08)`, corner radius 8pt. Button preserves existing `.accessibilityHint` from the original implementation.

### Frame Coach Status
Displayed as a subtle info row inside the camera card when active — SF Symbol `figure.stand` + coaching text.

---

## 6. Action Zone

Fixed bottom bar, separated by a `Divider`. Always visible regardless of scroll position.

### Record Button
Large circular button, 64pt diameter. Five visual states:

| State | Condition | Fill | Symbol | Animation |
|-------|-----------|------|--------|-----------|
| Ready | `!isRecording && !isPaused && !isPreparing && !isCountingDown` | `.fmRecord` | `record.circle.fill` white 28pt | none |
| Recording | `isRecording && !isPaused` | white | `stop.circle.fill` red 28pt | outer ring pulses scale 1.0→1.08, easeInOut 0.9s repeat |
| Paused | `isRecording && isPaused` | `.fmPause` (orange) | `pause.circle.fill` white 28pt | none |
| Preparing | `isPreparingRecording` | `Color.secondary` | `hourglass` white 24pt | none, disabled |
| Countdown | `isCountingDown` | `Color.secondary` | countdown number as `Text`, `.title .bold` | none |

Accessibility:
- `.accessibilityLabel(recordingButtonTitle)` — uses same computed var as existing code
- `.accessibilityHint(String(localized: "\(GlobalHotkeyMonitor.recordingToggleDisplay) son seçili modu başlatır veya durdurur."))`

```swift
struct RecordButton: View {
    let state: RecordButtonState  // enum with 5 cases above
    let countdownRemaining: Int
    let action: () -> Void
    // 64pt circle, states as defined above
}
```

### Pause Button
Smaller secondary button (44pt), only visible when recording:
- `pause.fill` or `play.fill` SF Symbol
- `.secondary` style (not as prominent as record)

### Status Row (below buttons)
`HStack`:
- Left: `Text(String(localized: "Durum: \(statusText)"))` — `.caption`, `.secondary`, `.textSelection(.enabled)`
- Right (when last saved): `Text(lastFileName)` — `.caption`, `.secondary`, truncated, `.textSelection(.enabled)`
- `.accessibilityLabel(String(localized: "Durum \(statusText)"))`

### Error Display
`viewModel.errorText` renders as a warning banner in the Action Zone, above the record button:
- Red background `.opacity(0.08)`, SF Symbol `xmark.circle.fill` red, `.caption` text in red
- `.textSelection(.enabled)` preserved
- Only visible when `errorText != nil`

### Frame Coach Status Row
When `showsFrameCoachControls && showsFrameCoachTextOnScreen`, the coaching text renders as an info row at the top of the **Ses** card:
- SF Symbol `figure.stand` in `.fmAccent`, `.accessibilityHidden(true)`
- `Text(frameCoachStatusText).textSelection(.enabled)`
- `.accessibilityLabel(frameCoachStatusText)`

---

## 7. Debug Panel

The `DisclosureGroup("Otomatik Kadraj Tanılama", ...)` is removed from `ContentView`. It is moved to `SettingsView` under a new `#if DEBUG` guarded `Section("Tanılama")` at the bottom of the `Form`. The `#if DEBUG` flag is used (matches Xcode's default Debug/Release configuration). In Release builds this section does not compile. The layout inside Settings mirrors the existing `debugPanel` computed property.

**Note:** The existing `debugPanel` property in `ContentView.swift` is currently unguarded and ships in Release builds. The implementer must: (1) delete `debugPanel` and its call site from `ContentView.swift` entirely, and (2) add the `#if DEBUG`-guarded `Section` in `SettingsView` as part of the same change. This is both a move and a guard addition.

---

## 8. Settings Window

Unchanged functionally. Visual improvements only:
- Section headers get SF Symbol icons
- `Form` styling already `.grouped` — no changes needed

---

## 9. Paywall Sheet

Visual upgrade:
- Header: SF Symbol `star.fill` in gold, "FrameMate Pro" title
- Plan cards: more prominent, accent color border on hover/focus
- "En Popüler" badge on yearly plan (capsule, `.fmAccent` background)

---

## 10. Completed Recording Sheet

Visual upgrade:
- SF Symbol `checkmark.circle.fill` in green, large, at top
- File name field styled as a text field with border
- Action buttons as a proper `ControlGroup`

---

## 11. Accessibility Compliance

All existing accessibility modifiers are preserved without exception. Explicit checklist:

- `.accessibilityLabel` on every interactive element ✓
- `.accessibilityHint` on every button (including permission banner "Ayarları Aç" buttons) ✓
- `.accessibilityAddTraits(.isHeader)` on section headers ✓
- `.accessibilityHidden(true)` on preview views ✓
- `.accessibilityHidden(true)` on all decorative SF Symbol icons (card icons, toggle icons, banner icons) ✓
- VoiceOver announcements via existing `SpeechCuePlayer` unchanged ✓
- `String(localized:)` wrapping on all user-visible strings including status pill and "En Popüler" badge ✓
- `.textSelection(.enabled)` on status text, last saved URL, error text, frame coach text ✓
- Volume `Slider` controls preserve both `.accessibilityLabel` and `.accessibilityValue` from existing code ✓
- Toggle icon SF Symbols are `.accessibilityHidden(true)` — the Toggle itself carries the label ✓
- `FMModeSelector` segment buttons carry individual `.accessibilityLabel` and `.accessibilityHint` as specified in Section 4 ✓
- `StatusPill` uses `String(localized: "Durum: \(statusText)")` ✓

---

## 12. Files Changed

| File | Change |
|------|--------|
| `ContentView.swift` | Full visual redesign — layout, cards, record button, header |
| `Info.plist` | `CFBundleDisplayName = "FrameMate"` |
| `project.yml` | `PRODUCT_NAME = FrameMate` |
| New: `FrameMateColors.swift` | Color token extension |
| New: `FMCard.swift` | Reusable card component |
| New: `StatusPill.swift` | Status pill component |
| New: `RecordButton.swift` | Animated record button |
| New: `FMModeSelector.swift` | Custom mode segmented control |

---

## 13. Out of Scope

- No changes to recording logic, ViewModel, or any non-UI code
- No changes to test files
- No new features
- Localization strings updated only for renamed labels ("Video Kaydedici" → "FrameMate")
