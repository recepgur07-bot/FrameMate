# FrameMate UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Visually redesign the macOS video recorder app as "FrameMate" — a polished, Light Minimal interface with indigo branding, card-based layout, animated record button, and custom mode selector, while preserving 100% of existing accessibility support.

**Architecture:** Five new standalone SwiftUI component files are created first (color tokens, card, status pill, record button, mode selector), then ContentView is completely rewritten to use them. The ViewModel and all recording logic are untouched; only the presentation layer changes. TDD is applied to all testable logic (enum labels, mapping functions, state equality); pure-visual SwiftUI bodies are verified by compiler + build success.

**Tech Stack:** SwiftUI (macOS 14+), SF Symbols, `@ViewBuilder`, `@State`, `@Observable`, XcodeGen (`project.yml`)

**Spec:** `docs/superpowers/specs/2026-04-13-framemate-ui-redesign-design.md`

**Key ViewModel properties confirmed:**
- `viewModel.lastSavedURL: URL?` (confirmed in existing ContentView line 276)
- `viewModel.showsScreenSourcePicker` — inner guard for the source picker widget
- `viewModel.showsScreenControls` — outer guard for Kaynak/Görüntü cards
- `viewModel.showsScreenOverlayControls` — outer guard for Kamera Kutusu card
- `viewModel.showsScreenOverlayConfiguration` — inner guard (overlay enabled)
- `SettingsView` lives inside `Sources/VideoRecorderApp/ContentView.swift`

---

## Chunk 1: Foundation — Color Tokens, FMCard, StatusPill

### Task 1: Color Token Extension

**Files:**
- Create: `Sources/VideoRecorderApp/FrameMateColors.swift`

> Color token values are load-bearing (brand identity). They cannot be unit-tested meaningfully in pure XCTest (SwiftUI `Color` does not expose RGB accessors). Correctness is verified by code review of exact RGB literals and successful build.

- [ ] **Step 1: Create the color token file**

```swift
// Sources/VideoRecorderApp/FrameMateColors.swift
import SwiftUI

extension Color {
    /// #5B4CF5 — indigo brand accent
    static let fmAccent  = Color(red: 0.357, green: 0.298, blue: 0.961)
    /// #FF3B30 — system red, used for record button ready state
    static let fmRecord  = Color(red: 1.0,   green: 0.231, blue: 0.188)
    /// Orange — pause button and paused status
    static let fmPause   = Color.orange
    /// Green — ready status
    static let fmReady   = Color.green
    /// Card background — adapts to Dark Mode
    static let fmCardBg  = Color(nsColor: .controlBackgroundColor)
    /// Window surface — adapts to Dark Mode
    static let fmSurface = Color(nsColor: .windowBackgroundColor)
}
```

- [ ] **Step 2: Verify the file compiles**

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild -scheme VideoRecorderApp -configuration Debug build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
cd "/Users/recepgur/Desktop/video recorder"
git add Sources/VideoRecorderApp/FrameMateColors.swift
git commit -m "feat: add FrameMate color token extension"
```

---

### Task 2: StatusPill — Logic First (TDD), Then View

`RecordingStatus` enum is pure logic (labels, colors) — fully unit-testable. Write tests first.

**Files:**
- Create: `Sources/VideoRecorderApp/StatusPill.swift`
- Modify: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] **Step 1: Write the failing tests for RecordingStatus**

Add the following test class to `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift` (at the bottom of the file, before the final `}`):

```swift
// MARK: - RecordingStatus tests
final class RecordingStatusTests: XCTestCase {
    func test_ready_label() {
        XCTAssertEqual(RecordingStatus.ready.label, "Hazır")
    }

    func test_recording_label() {
        XCTAssertEqual(RecordingStatus.recording.label, "Kayıt")
    }

    func test_paused_label() {
        XCTAssertEqual(RecordingStatus.paused.label, "Duraklatıldı")
    }

    func test_preparing_label() {
        XCTAssertEqual(RecordingStatus.preparing.label, "Hazırlanıyor")
    }

    func test_dotColors_are_distinct() {
        // All three active-state colors should be distinct objects
        let readyColor  = RecordingStatus.ready.dotColor
        let recordColor = RecordingStatus.recording.dotColor
        let pauseColor  = RecordingStatus.paused.dotColor
        XCTAssertNotEqual(readyColor, recordColor)
        XCTAssertNotEqual(readyColor, pauseColor)
        XCTAssertNotEqual(recordColor, pauseColor)
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure (RecordingStatus not yet defined)**

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | grep -E "(error:|FAILED)"
```
Expected: compile error referencing `RecordingStatus`.

- [ ] **Step 3: Create StatusPill.swift with RecordingStatus enum and StatusPill view**

```swift
// Sources/VideoRecorderApp/StatusPill.swift
import SwiftUI

/// The four states rendered by StatusPill in the header.
enum RecordingStatus: Equatable {
    case ready
    case recording
    case paused
    case preparing

    var dotColor: Color {
        switch self {
        case .ready:     return .fmReady
        case .recording: return .fmRecord
        case .paused:    return .fmPause
        case .preparing: return .secondary
        }
    }

    var label: String {
        switch self {
        case .ready:     return String(localized: "Hazır")
        case .recording: return String(localized: "Kayıt")
        case .paused:    return String(localized: "Duraklatıldı")
        case .preparing: return String(localized: "Hazırlanıyor")
        }
    }
}

/// Small capsule badge shown in the header zone.
struct StatusPill: View {
    let status: RecordingStatus

    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.dotColor)
                .frame(width: 8, height: 8)
                .scaleEffect(pulsing ? 1.3 : 1.0)
                .accessibilityHidden(true)

            Text(status.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(status.dotColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.dotColor.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityLabel(String(localized: "Durum: \(status.label)"))
        .onAppear { startPulseIfNeeded() }
        .onChange(of: status) { _, _ in startPulseIfNeeded() }
    }

    private func startPulseIfNeeded() {
        // First, stop any existing animation cleanly
        withAnimation(.default) { pulsing = false }
        guard status == .recording else { return }
        // Then start the pulse for the recording state
        withAnimation(
            .easeInOut(duration: 0.9)
            .repeatForever(autoreverses: true)
        ) {
            pulsing = true
        }
    }
}
```

- [ ] **Step 4: Run tests — expect all RecordingStatusTests to pass**

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | grep -E "(PASS|FAIL|error:)"
```
Expected: `RecordingStatusTests` — all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
cd "/Users/recepgur/Desktop/video recorder"
git add Sources/VideoRecorderApp/StatusPill.swift
git add Tests/VideoRecorderAppTests/RecorderViewModelTests.swift
git commit -m "feat: add StatusPill component with RecordingStatus enum (TDD)"
```

---

### Task 3: FMCard Component

FMCard is a pure-UI component. The only testable behaviour is compile-time correctness (no unit tests needed for layout). Shadow/border spec: FMCard has **shadow only** (no border stroke) — the `Color.secondary.opacity(0.15)` border applies to the **preview card** only, not to FMCard.

**Files:**
- Create: `Sources/VideoRecorderApp/FMCard.swift`

- [ ] **Step 1: Create FMCard**

```swift
// Sources/VideoRecorderApp/FMCard.swift
import SwiftUI

/// Reusable card container used in the FrameMate content zone.
/// When `isCollapsible` is true a chevron appears and tapping the header
/// toggles the card between expanded and collapsed states.
/// Cards always start expanded; state is NOT persisted between launches.
struct FMCard<Content: View>: View {
    let icon: String
    let title: String
    var isCollapsible: Bool = false
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — always announces as a heading regardless of collapsibility
            Button(action: {
                if isCollapsible {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(Color.fmAccent)
                        .frame(width: 20)
                        .accessibilityHidden(true)

                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    if isCollapsible {
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(isExpanded ? 0 : -180))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(
                isCollapsible
                    ? (isExpanded
                        ? String(localized: "Daraltmak için dokun")
                        : String(localized: "Genişletmek için dokun"))
                    : ""
            )

            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .padding(16)
            }
        }
        .background(Color.fmCardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Shadow only — no stroke border (preview card has its own border)
        .shadow(color: Color.primary.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild -scheme VideoRecorderApp -configuration Debug build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
cd "/Users/recepgur/Desktop/video recorder"
git add Sources/VideoRecorderApp/FMCard.swift
git commit -m "feat: add FMCard reusable collapsible card component"
```

---

## Chunk 2: Interactive Components — RecordButton, FMModeSelector

### Task 4: RecordButton — TDD on Logic Types

The `RecordButtonState` enum and its equality are testable. Write tests first. The view body (fill color, animation) is visual and verified by build + manual inspection.

**Files:**
- Create: `Sources/VideoRecorderApp/RecordButton.swift`
- Modify: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

The spec signature for `RecordButton`:
```swift
struct RecordButton: View {
    let state: RecordButtonState  // enum with 5 cases
    let countdownRemaining: Int   // used when state == .countdown
    let accessibilityLabel: String // derived from recordingButtonTitle in ContentView
    let action: () -> Void
}
```

`accessibilityLabel` is passed in from ContentView's `recordingButtonTitle` computed var — this ensures the label and the button's visual state always come from the same source of truth.

- [ ] **Step 1: Write failing tests for RecordButtonState**

Add to `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`:

```swift
// MARK: - RecordButtonState tests
final class RecordButtonStateTests: XCTestCase {
    func test_states_are_distinct() {
        XCTAssertNotEqual(RecordButtonState.ready,     .recording)
        XCTAssertNotEqual(RecordButtonState.ready,     .paused)
        XCTAssertNotEqual(RecordButtonState.ready,     .preparing)
        XCTAssertNotEqual(RecordButtonState.recording, .paused)
        XCTAssertNotEqual(RecordButtonState.recording, .preparing)
        XCTAssertNotEqual(RecordButtonState.paused,    .preparing)
    }

    func test_countdown_equality() {
        XCTAssertEqual(RecordButtonState.countdown, .countdown)
        XCTAssertNotEqual(RecordButtonState.countdown, .ready)
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure (RecordButtonState not yet defined)**

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | grep -E "(error:|FAILED)"
```
Expected: compile error referencing `RecordButtonState`.

- [ ] **Step 3: Create RecordButton.swift**

```swift
// Sources/VideoRecorderApp/RecordButton.swift
import SwiftUI

/// The five visual states of the main record button.
enum RecordButtonState: Equatable {
    case ready
    case recording
    case paused
    case preparing
    case countdown
}

/// Large 64pt circular button in the Action Zone.
/// Pass `accessibilityLabel` from ContentView's `recordingButtonTitle` computed var
/// so the label stays in sync with the visual state from a single source of truth.
struct RecordButton: View {
    let state: RecordButtonState
    /// The countdown number to display when `state == .countdown`. Ignored otherwise.
    let countdownRemaining: Int
    /// Must be set to ContentView's `recordingButtonTitle` computed var.
    let accessibilityLabel: String
    let action: () -> Void

    @State private var ringScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Pulsing outer ring — visible only while recording
            if state == .recording {
                Circle()
                    .stroke(Color.fmRecord.opacity(0.35), lineWidth: 3)
                    .frame(width: 80, height: 80)
                    .scaleEffect(ringScale)
                    .accessibilityHidden(true)
            }

            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(fillColor)
                        .frame(width: 64, height: 64)

                    buttonContent
                        .foregroundStyle(symbolColor)
                }
            }
            .buttonStyle(.plain)
            .disabled(state == .preparing)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(
                String(localized: "\(GlobalHotkeyMonitor.recordingToggleDisplay) son seçili modu başlatır veya durdurur.")
            )
        }
        .onAppear { startPulseIfRecording() }
        .onChange(of: state) { _, _ in startPulseIfRecording() }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var buttonContent: some View {
        switch state {
        case .ready:
            Image(systemName: "record.circle.fill")
                .font(.system(size: 28))
        case .recording:
            Image(systemName: "stop.circle.fill")
                .font(.system(size: 28))
        case .paused:
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 28))
        case .preparing:
            Image(systemName: "hourglass")
                .font(.system(size: 24))
        case .countdown:
            Text("\(countdownRemaining)")
                .font(.title.bold())
        }
    }

    // MARK: - Derived properties

    private var fillColor: Color {
        switch state {
        case .ready:      return .fmRecord
        case .recording:  return .white
        case .paused:     return .fmPause
        case .preparing:  return .secondary
        case .countdown:  return .secondary
        }
    }

    private var symbolColor: Color {
        switch state {
        case .ready:      return .white
        case .recording:  return .fmRecord
        case .paused:     return .white
        case .preparing:  return .white
        case .countdown:  return .white
        }
    }

    // MARK: - Animation

    private func startPulseIfRecording() {
        withAnimation(.default) { ringScale = 1.0 }
        guard state == .recording else { return }
        withAnimation(
            .easeInOut(duration: 0.9)
            .repeatForever(autoreverses: true)
        ) {
            ringScale = 1.08
        }
    }
}
```

- [ ] **Step 4: Run tests — expect all RecordButtonStateTests to pass**

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | grep -E "(PASS|FAIL|error:)"
```
Expected: All `RecordButtonStateTests` pass.

- [ ] **Step 5: Commit**

```bash
cd "/Users/recepgur/Desktop/video recorder"
git add Sources/VideoRecorderApp/RecordButton.swift
git add Tests/VideoRecorderAppTests/RecorderViewModelTests.swift
git commit -m "feat: add RecordButton component with 5-state animation (TDD)"
```

---

### Task 5: FMModeSelector — TDD on Mapping Functions

The two mapping functions (`compose` and `decompose`) are pure functions — fully unit-testable. Write all 11 tests before implementing the component.

**Files:**
- Create: `Sources/VideoRecorderApp/FMModeSelector.swift`
- Modify: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] **Step 1: Write failing tests for FMModeSelector mapping**

Add to `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`:

```swift
// MARK: - FMModeSelector mapping tests
final class FMModeSelectorTests: XCTestCase {
    typealias PM  = FMModeSelector.PrimaryMode
    typealias ORI = FMModeSelector.Orientation

    // compose: PrimaryMode + Orientation → RecordingPreset

    func test_compose_cameraHorizontal() {
        XCTAssertEqual(FMModeSelector.compose(primaryMode: .camera, orientation: .horizontal), .horizontalCamera)
    }
    func test_compose_cameraVertical() {
        XCTAssertEqual(FMModeSelector.compose(primaryMode: .camera, orientation: .vertical), .verticalCamera)
    }
    func test_compose_screenHorizontal() {
        XCTAssertEqual(FMModeSelector.compose(primaryMode: .screen, orientation: .horizontal), .horizontalScreen)
    }
    func test_compose_screenVertical() {
        XCTAssertEqual(FMModeSelector.compose(primaryMode: .screen, orientation: .vertical), .verticalScreen)
    }
    func test_compose_screenCamera_alwaysHorizontalScreen() {
        XCTAssertEqual(FMModeSelector.compose(primaryMode: .screenCamera, orientation: .horizontal), .horizontalScreen)
        XCTAssertEqual(FMModeSelector.compose(primaryMode: .screenCamera, orientation: .vertical),   .horizontalScreen)
    }
    func test_compose_audio() {
        XCTAssertEqual(FMModeSelector.compose(primaryMode: .audio, orientation: .horizontal), .audioOnly)
    }

    // decompose: RecordingPreset + overlayEnabled → (PrimaryMode, Orientation)

    func test_decompose_horizontalCamera() {
        let (pm, ori) = FMModeSelector.decompose(preset: .horizontalCamera, overlayEnabled: false)
        XCTAssertEqual(pm, .camera); XCTAssertEqual(ori, .horizontal)
    }
    func test_decompose_verticalCamera() {
        let (pm, ori) = FMModeSelector.decompose(preset: .verticalCamera, overlayEnabled: false)
        XCTAssertEqual(pm, .camera); XCTAssertEqual(ori, .vertical)
    }
    func test_decompose_horizontalScreen_noOverlay() {
        let (pm, ori) = FMModeSelector.decompose(preset: .horizontalScreen, overlayEnabled: false)
        XCTAssertEqual(pm, .screen); XCTAssertEqual(ori, .horizontal)
    }
    func test_decompose_horizontalScreen_withOverlay() {
        let (pm, ori) = FMModeSelector.decompose(preset: .horizontalScreen, overlayEnabled: true)
        XCTAssertEqual(pm, .screenCamera); XCTAssertEqual(ori, .horizontal)
    }
    func test_decompose_verticalScreen() {
        let (pm, ori) = FMModeSelector.decompose(preset: .verticalScreen, overlayEnabled: false)
        XCTAssertEqual(pm, .screen); XCTAssertEqual(ori, .vertical)
    }
    func test_decompose_audioOnly() {
        let (pm, ori) = FMModeSelector.decompose(preset: .audioOnly, overlayEnabled: false)
        XCTAssertEqual(pm, .audio); XCTAssertEqual(ori, .horizontal)
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | grep -E "(error:|FAILED)"
```
Expected: compile error referencing `FMModeSelector`.

- [ ] **Step 3: Create FMModeSelector.swift**

```swift
// Sources/VideoRecorderApp/FMModeSelector.swift
import SwiftUI

/// Custom segmented mode selector that replaces the plain Picker in ContentView.
/// Maps primary-mode + orientation choices onto a `RecordingPreset` and
/// propagates changes via callbacks (no direct ViewModel dependency keeps
/// the component testable in isolation).
struct FMModeSelector: View {
    // MARK: - Input

    /// The preset currently active in the ViewModel.
    let selectedPreset: RecordingPreset
    /// Whether the screen-camera overlay is currently enabled in the ViewModel.
    let isOverlayEnabled: Bool
    /// Called when the user selects a new preset.
    let onPresetSelected: (RecordingPreset) -> Void
    /// Called when Ekran+Kamera is selected and overlay is not yet enabled.
    let onEnableOverlay: () -> Void

    // MARK: - Local state

    @State private var primaryMode: PrimaryMode
    @State private var orientation: Orientation

    // MARK: - Nested types

    enum PrimaryMode: Equatable {
        case camera, screen, screenCamera, audio
    }

    enum Orientation: Equatable {
        case horizontal, vertical
    }

    // MARK: - Init

    init(
        selectedPreset: RecordingPreset,
        isOverlayEnabled: Bool,
        onPresetSelected: @escaping (RecordingPreset) -> Void,
        onEnableOverlay: @escaping () -> Void
    ) {
        self.selectedPreset   = selectedPreset
        self.isOverlayEnabled = isOverlayEnabled
        self.onPresetSelected = onPresetSelected
        self.onEnableOverlay  = onEnableOverlay

        let (pm, ori) = Self.decompose(preset: selectedPreset, overlayEnabled: isOverlayEnabled)
        _primaryMode  = State(initialValue: pm)
        _orientation  = State(initialValue: ori)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 8) {
            // Primary mode segments
            HStack(spacing: 4) {
                modeSegment(mode: .camera,
                            icon: "camera.fill",
                            label: String(localized: "Kamera"))
                modeSegment(mode: .screen,
                            icon: "desktopcomputer",
                            label: String(localized: "Ekran"))
                modeSegment(mode: .screenCamera,
                            icon: "rectangle.inset.filled.on.rectangle",
                            label: String(localized: "Ekran+Kamera"))
                modeSegment(mode: .audio,
                            icon: "waveform.circle.fill",
                            label: String(localized: "Ses"))
            }
            .padding(4)
            .background(Color.fmCardBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel(String(localized: "Kayıt modu seçimi"))

            // Orientation toggle — hidden for Ekran+Kamera and Ses
            if primaryMode == .camera || primaryMode == .screen {
                HStack(spacing: 4) {
                    orientationButton(
                        orientation: .horizontal,
                        icon: "rectangle.fill",
                        label: String(localized: "Yatay")
                    )
                    orientationButton(
                        orientation: .vertical,
                        icon: "rectangle.portrait.fill",
                        label: String(localized: "Dikey")
                    )
                }
                .accessibilityLabel(String(localized: "Yönlendirme seçimi"))
            }
        }
        .onChange(of: selectedPreset) { _, newPreset in
            let (pm, ori) = Self.decompose(preset: newPreset, overlayEnabled: isOverlayEnabled)
            primaryMode = pm
            orientation = ori
        }
    }

    // MARK: - Segment builders

    @ViewBuilder
    private func modeSegment(mode: PrimaryMode, icon: String, label: String) -> some View {
        let isSelected = primaryMode == mode
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                primaryMode = mode
            }
            propagate()
            if mode == .screenCamera && !isOverlayEnabled {
                onEnableOverlay()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.fmAccent : Color.clear)
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(String(localized: "Bu kayıt modunu seçer"))
    }

    @ViewBuilder
    private func orientationButton(orientation: Orientation, icon: String, label: String) -> some View {
        let isSelected = self.orientation == orientation
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                self.orientation = orientation
            }
            propagate()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.fmAccent.opacity(0.15) : Color.clear)
            .foregroundStyle(isSelected ? Color.fmAccent : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(String(localized: "Bu yönlendirmeyi seçer"))
    }

    // MARK: - Preset mapping (static — unit-testable)

    private func propagate() {
        onPresetSelected(Self.compose(primaryMode: primaryMode, orientation: orientation))
    }

    /// primaryMode + orientation → RecordingPreset
    static func compose(primaryMode: PrimaryMode, orientation: Orientation) -> RecordingPreset {
        switch primaryMode {
        case .camera:
            return orientation == .horizontal ? .horizontalCamera : .verticalCamera
        case .screen:
            return orientation == .horizontal ? .horizontalScreen : .verticalScreen
        case .screenCamera:
            return .horizontalScreen   // overlay toggled separately via onEnableOverlay
        case .audio:
            return .audioOnly
        }
    }

    /// RecordingPreset + overlayEnabled → (PrimaryMode, Orientation)
    static func decompose(preset: RecordingPreset, overlayEnabled: Bool) -> (PrimaryMode, Orientation) {
        switch preset {
        case .horizontalCamera: return (.camera,                               .horizontal)
        case .verticalCamera:   return (.camera,                               .vertical)
        case .horizontalScreen: return (overlayEnabled ? .screenCamera : .screen, .horizontal)
        case .verticalScreen:   return (.screen,                               .vertical)
        case .audioOnly:        return (.audio,                                .horizontal)
        }
    }
}
```

- [ ] **Step 4: Run tests — expect all FMModeSelectorTests to pass**

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | grep -E "(PASS|FAIL|error:)"
```
Expected: All `FMModeSelectorTests` pass (11 tests).

- [ ] **Step 5: Commit**

```bash
cd "/Users/recepgur/Desktop/video recorder"
git add Sources/VideoRecorderApp/FMModeSelector.swift
git add Tests/VideoRecorderAppTests/RecorderViewModelTests.swift
git commit -m "feat: add FMModeSelector with 11 mapping tests (TDD)"
```

---

## Chunk 3: ContentView Redesign, Debug Panel Move, Project Rename

### Task 6: Move Debug Panel to SettingsView

This task deletes `debugPanel` from `ContentView` and adds it to `SettingsView` under `#if DEBUG`. Both live in the same file: `Sources/VideoRecorderApp/ContentView.swift`.

**Files:**
- Modify: `Sources/VideoRecorderApp/ContentView.swift`

- [ ] **Step 1: Verify no other references to isDebugPanelExpanded**

Before deleting, confirm the state var is only used in `debugPanel`:

```bash
grep -n "isDebugPanelExpanded" "/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/ContentView.swift"
```
Expected: exactly 2 lines (the `@State` declaration and the `DisclosureGroup` usage). If more, investigate before proceeding.

- [ ] **Step 2: Remove isDebugPanelExpanded state var from ContentView**

In `ContentView.swift`, delete this line (line ~6):
```swift
    @State private var isDebugPanelExpanded = false
```

- [ ] **Step 3: Remove debugPanel call site from ContentView.body**

In `ContentView.swift`, delete this line from the `body` property (line ~288):
```swift
            debugPanel
```

- [ ] **Step 4: Remove debugPanel computed property from ContentView**

Delete the entire `@ViewBuilder private var debugPanel: some View { ... }` property (lines ~401–422 of the original file).

- [ ] **Step 5: Add #if DEBUG section to SettingsView**

`SettingsView` lives further down in the same `ContentView.swift` file. At the end of its `Form`, just before the closing `}` of the Form block, add:

```swift
            #if DEBUG
            Section("Tanılama") {
                DisclosureGroup("Otomatik Kadraj Tanılama") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Strateji: \(viewModel.lastAutoReframeStrategy)"))
                        Text(String(localized: "Ana kare sayısı: \(viewModel.lastAutoReframeKeyframeCount)"))
                        Text(String(localized: "Kompozisyon kullanıldı: \(viewModel.lastAutoReframeUsedVideoComposition ? "evet" : "hayır")"))
                        Text(String(localized: "Yedek dışa aktarım: \(viewModel.lastAutoReframeUsedFallbackExport ? "evet" : "hayır")"))
                        Text(
                            String(
                                format: "Aktif crop: x %.2f y %.2f gen %.2f yuk %.2f",
                                viewModel.currentAutoReframeCrop.originX,
                                viewModel.currentAutoReframeCrop.originY,
                                viewModel.currentAutoReframeCrop.width,
                                viewModel.currentAutoReframeCrop.height
                            )
                        )
                        .textSelection(.enabled)
                    }
                    .padding(.top, 6)
                }
            }
            #endif
```

- [ ] **Step 6: Verify Debug build (the #if DEBUG section must compile)**

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild -scheme VideoRecorderApp -configuration Debug build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Commit**

```bash
cd "/Users/recepgur/Desktop/video recorder"
git add Sources/VideoRecorderApp/ContentView.swift
git commit -m "refactor: move debug panel from ContentView to SettingsView under #if DEBUG"
```

---

### Task 7: ContentView Full Redesign

The entire `ContentView` struct is rewritten. `SettingsView`, `CompletedRecordingSheet`, and `AppPaywallSheet` remain intact after the ContentView struct.

**Files:**
- Modify: `Sources/VideoRecorderApp/ContentView.swift`

**Key property notes for implementer:**
- `viewModel.showsScreenControls` — outer guard for Kaynak and Görüntü cards
- `viewModel.showsScreenOverlayControls` — outer guard for Kamera Kutusu card
- `viewModel.showsScreenSourcePicker` — inner guard for the source picker widget inside Kaynak card
- `viewModel.showsScreenOverlayConfiguration` — inner guard (shows pickers when overlay is enabled)
- `viewModel.lastSavedURL: URL?` — confirmed URL optional (use `.lastPathComponent` for display)
- `recordingButtonTitle` is a `private var` in ContentView; it must be preserved as-is and passed to `RecordButton(accessibilityLabel:)`.

- [ ] **Step 1: Replace ContentView struct with the redesigned version**

Replace everything from `struct ContentView: View {` through the closing `}` that ends the ContentView struct (just before `struct SettingsView: View {`) with the following:

```swift
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var viewModel: RecorderViewModel

    var body: some View {
        VStack(spacing: 0) {
            // ── HEADER ZONE ──────────────────────────────────────────────
            headerZone
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            // ── MODE ZONE ────────────────────────────────────────────────
            FMModeSelector(
                selectedPreset: viewModel.selectedPreset,
                isOverlayEnabled: viewModel.isScreenCameraOverlayEnabled,
                onPresetSelected: { viewModel.selectPreset($0) },
                onEnableOverlay: {
                    if !viewModel.isScreenCameraOverlayEnabled {
                        viewModel.toggleScreenCameraOverlay()
                    }
                }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // ── CONTENT ZONE (scrollable) ─────────────────────────────────
            ScrollView {
                VStack(spacing: 12) {
                    previewCard
                    audioCard
                    if viewModel.showsScreenControls || viewModel.showsScreenOverlayControls {
                        sourceCard
                    }
                    if viewModel.showsScreenControls {
                        visualCard
                    }
                    if viewModel.showsScreenOverlayControls {
                        cameraBoxCard
                    }
                }
                .padding(16)
            }

            Divider()

            // ── ACTION ZONE ───────────────────────────────────────────────
            actionZone
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .background(Color.fmSurface)
        .frame(minWidth: 620, minHeight: 640)
        .task {
            await viewModel.setup()
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isPaywallPresented },
                set: { isPresented in
                    if !isPresented { viewModel.dismissPaywall() }
                }
            )
        ) {
            AppPaywallSheet(viewModel: viewModel)
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.completedRecording != nil },
                set: { isPresented in
                    if !isPresented { viewModel.dismissCompletedRecordingSummary() }
                }
            )
        ) {
            if let completedRecording = viewModel.completedRecording {
                CompletedRecordingSheet(
                    completedRecording: completedRecording,
                    onOpen: viewModel.openCompletedRecording,
                    onReveal: viewModel.revealCompletedRecording,
                    onRename: viewModel.renameCompletedRecording(to:),
                    onSaveAs: viewModel.saveCompletedRecordingAs(to:),
                    onClose: viewModel.dismissCompletedRecordingSummary
                )
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            viewModel.refreshDeviceState()
            Task { await viewModel.refreshAppAccess() }
        }
    }

    // MARK: - Header Zone

    private var headerZone: some View {
        HStack(alignment: .center) {
            Image(systemName: "record.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.fmAccent)
                .accessibilityHidden(true)

            Text("FrameMate")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.fmAccent)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            StatusPill(status: currentStatus)
        }
    }

    private var currentStatus: RecordingStatus {
        if viewModel.isPreparingRecording || viewModel.isCountingDown { return .preparing }
        if viewModel.isRecording && viewModel.isPaused { return .paused }
        if viewModel.isRecording { return .recording }
        return .ready
    }

    // MARK: - Preview Card

    @ViewBuilder
    private var previewCard: some View {
        if viewModel.showsCameraControls {
            VideoPreviewView(
                session: viewModel.previewSession,
                crop: viewModel.currentAutoReframeCrop
            )
            .frame(minHeight: 240)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
            .accessibilityHidden(true)
        } else if viewModel.showsScreenControls {
            ScreenRecordingCompositionPreview(
                session: viewModel.screenOverlayPreviewSession,
                mode: viewModel.selectedMode,
                isOverlayEnabled: viewModel.showsScreenOverlayConfiguration,
                position: viewModel.selectedScreenCameraOverlayPosition,
                overlaySize: viewModel.selectedScreenCameraOverlaySize
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
            .accessibilityHidden(true)
        }
    }

    // MARK: - Audio Card

    private var audioCard: some View {
        FMCard(icon: "mic.fill", title: String(localized: "Ses"), isCollapsible: true) {
            // Camera permission banner (top of Ses card)
            if viewModel.showsCameraControls || viewModel.showsScreenOverlayConfiguration {
                cameraPermissionBanner
            }

            // Frame coach row
            if viewModel.showsFrameCoachControls && viewModel.showsFrameCoachTextOnScreen {
                HStack(spacing: 8) {
                    Image(systemName: "figure.stand")
                        .foregroundStyle(Color.fmAccent)
                        .accessibilityHidden(true)
                    Text(frameCoachStatusText)
                        .textSelection(.enabled)
                        .accessibilityLabel(frameCoachStatusText)
                }
            }

            // Microphone picker
            if viewModel.showsMicrophonePicker {
                Picker(microphonePickerTitle, selection: $viewModel.selectedMicrophoneID) {
                    if viewModel.microphonePermissionStatus != .authorized {
                        Text(String(localized: "Mikrofon izni gerekli")).tag("")
                    } else if viewModel.microphones.isEmpty {
                        Text(String(localized: "Mikrofon bulunamadı")).tag("")
                    } else {
                        if viewModel.showsScreenControls {
                            Text(String(localized: "Mikrofon kapalı")).tag("")
                        }
                        ForEach(viewModel.microphones) { microphone in
                            Text(microphone.name).tag(microphone.id)
                        }
                    }
                }
                .disabled(viewModel.microphonePermissionStatus != .authorized || viewModel.microphones.isEmpty)
                .accessibilityLabel(microphonePickerTitle)
                .onChange(of: viewModel.selectedMicrophoneID) {
                    viewModel.applySelectedInputs()
                }
            }

            // System audio toggle
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Toggle(String(localized: "Sistem sesini dahil et"), isOn: $viewModel.isSystemAudioEnabled)
                    .accessibilityHint(String(localized: "Mac'te calan uygulama ve sistem seslerini kayda ekler."))
            }

            // Microphone volume
            if viewModel.showsMicrophoneVolumeControl {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Mikrofon seviyesi: \(Int(viewModel.microphoneVolume * 100))%"))
                    Slider(value: $viewModel.microphoneVolume, in: 0...1.5)
                        .accessibilityLabel(String(localized: "Mikrofon seviyesi"))
                        .accessibilityValue(String(localized: "\(Int(viewModel.microphoneVolume * 100)) yüzde"))
                }
            }

            // System audio volume
            if viewModel.showsSystemAudioVolumeControl {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Sistem sesi seviyesi: \(Int(viewModel.systemAudioVolume * 100))%"))
                    Slider(value: $viewModel.systemAudioVolume, in: 0...1.5)
                        .accessibilityLabel(String(localized: "Sistem sesi seviyesi"))
                        .accessibilityValue(String(localized: "\(Int(viewModel.systemAudioVolume * 100)) yüzde"))
                }
            }

            // Microphone permission banner (bottom of Ses card)
            microphonePermissionBanner

            // Auto-reframe toggle
            if viewModel.showsFrameCoachControls {
                HStack(spacing: 8) {
                    Image(systemName: "viewfinder")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Toggle(
                        String(localized: "Otomatik yeniden kadrajlama"),
                        isOn: Binding(
                            get: { viewModel.isAutoReframeEnabled },
                            set: { _ in viewModel.toggleAutoReframe() }
                        )
                    )
                    .accessibilityHint(String(localized: "Tek kişilik çekimde görüntüyü yazılımsal olarak daha dengeli kadrajlar."))
                }
            }
        }
    }

    // MARK: - Source Card

    private var sourceCard: some View {
        // showsScreenSourcePicker — inner guard for the segmented source picker widget
        // showsScreenControls / showsScreenOverlayControls — outer visibility (card shown)
        FMCard(icon: "desktopcomputer", title: String(localized: "Kaynak"), isCollapsible: true) {
            // Screen recording permission banner (top of Kaynak card)
            if (viewModel.showsScreenControls || viewModel.isSystemAudioEnabled)
                && viewModel.screenRecordingPermissionStatus == .denied {
                screenPermissionBanner
            }

            if viewModel.showsScreenSourcePicker {
                Picker(String(localized: "Ekran kaynağı"), selection: Binding(
                    get: { viewModel.selectedScreenCaptureSource },
                    set: { viewModel.selectScreenCaptureSource($0) }
                )) {
                    ForEach(ScreenCaptureSource.allCases) { source in
                        Text(source.label).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(String(localized: "Ekran kaynağı seçimi"))
            }

            if viewModel.showsScreenPicker {
                Picker(String(localized: "Ekran"), selection: $viewModel.selectedDisplayID) {
                    if viewModel.availableDisplays.isEmpty {
                        Text(String(localized: "Ekran bulunamadı")).tag("")
                    } else {
                        ForEach(viewModel.availableDisplays) { display in
                            Text(display.name).tag(display.id)
                        }
                    }
                }
                .accessibilityLabel(String(localized: "Ekran seçimi"))
                .onChange(of: viewModel.selectedDisplayID) {
                    Task { await viewModel.refreshScreenRecordingOptions() }
                }
            }

            if viewModel.showsWindowPicker {
                Picker(String(localized: "Pencere"), selection: $viewModel.selectedWindowID) {
                    if viewModel.availableWindows.isEmpty {
                        Text(String(localized: "Pencere bulunamadı")).tag("")
                    } else {
                        ForEach(viewModel.availableWindows) { window in
                            Text(window.name).tag(window.id)
                        }
                    }
                }
                .accessibilityLabel(String(localized: "Pencere seçimi"))
                .onChange(of: viewModel.selectedWindowID) {
                    Task { await viewModel.refreshScreenRecordingOptions() }
                }
            }
        }
    }

    // MARK: - Visual Card

    private var visualCard: some View {
        FMCard(icon: "eye.fill", title: String(localized: "Görüntü"), isCollapsible: true) {
            HStack(spacing: 8) {
                Image(systemName: "cursorarrow.rays")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Toggle(String(localized: "İmleci vurgula"), isOn: $viewModel.isCursorHighlightEnabled)
                    .accessibilityHint(String(localized: "Kayıt dışa aktarılırken imlecin etrafında yumuşak bir vurgu ve tıklama halkası gösterir."))
            }

            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Toggle(String(localized: "Klavye kısayollarını göster"), isOn: $viewModel.isKeyboardShortcutOverlayEnabled)
                    .accessibilityHint(String(localized: "Komut, kontrol ve option gibi anlamlı kısayolları videoda kısa süre gösterir."))
            }
        }
    }

    // MARK: - Camera Box Card

    private var cameraBoxCard: some View {
        FMCard(icon: "rectangle.inset.filled.on.rectangle", title: String(localized: "Kamera Kutusu"), isCollapsible: true) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.inset.filled.on.rectangle")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Toggle(
                    String(localized: "Kamera kutusunu göster"),
                    isOn: Binding(
                        get: { viewModel.isScreenCameraOverlayEnabled },
                        set: { _ in viewModel.toggleScreenCameraOverlay() }
                    )
                )
                .accessibilityHint(String(localized: "Ekran kaydının üstüne kamera görüntünü ekler."))
            }

            if viewModel.showsScreenOverlayConfiguration {
                // Camera picker for overlay
                Picker(String(localized: "Kamera"), selection: $viewModel.selectedCameraID) {
                    if viewModel.cameraPermissionStatus != .authorized {
                        Text(String(localized: "Kamera izni gerekli")).tag("")
                    } else if viewModel.cameras.isEmpty {
                        Text(String(localized: "Kamera bulunamadı")).tag("")
                    } else {
                        ForEach(viewModel.cameras) { camera in
                            Text(camera.name).tag(camera.id)
                        }
                    }
                }
                .disabled(!viewModel.canChooseCamera)
                .accessibilityLabel(String(localized: "Kamera seçimi"))
                .onChange(of: viewModel.selectedCameraID) {
                    viewModel.refreshDeviceState()
                }

                Picker(String(localized: "Kamera kutusu konumu"), selection: $viewModel.selectedScreenCameraOverlayPosition) {
                    ForEach(ScreenCameraOverlayPosition.allCases) { position in
                        Text(position.label).tag(position)
                    }
                }
                .accessibilityLabel(String(localized: "Kamera kutusu konumu"))

                Picker(String(localized: "Kamera kutusu boyutu"), selection: $viewModel.selectedScreenCameraOverlaySize) {
                    ForEach(ScreenCameraOverlaySize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .accessibilityLabel(String(localized: "Kamera kutusu boyutu"))
            }
        }
    }

    // MARK: - Permission Banners

    @ViewBuilder
    private var cameraPermissionBanner: some View {
        let camStatus = viewModel.cameraPermissionStatus
        if camStatus == .notDetermined {
            permissionBanner(
                message: String(localized: "Kamera izni gerekli"),
                buttonTitle: String(localized: "İzin Ver"),
                buttonHint: String(localized: "Sistem izin penceresini açar. İzin Ver veya Reddet seçin."),
                action: { viewModel.requestCameraPermission() }
            )
        } else if camStatus == .denied {
            permissionBanner(
                message: String(localized: "Kamera izni reddedildi"),
                buttonTitle: String(localized: "Ayarları Aç"),
                buttonHint: String(localized: "Kamera izni daha önce reddedildi. Sistem Ayarları Gizlilik ekranını açar."),
                action: { viewModel.openPrivacySettings(for: .video) }
            )
        }
    }

    @ViewBuilder
    private var microphonePermissionBanner: some View {
        let micStatus = viewModel.microphonePermissionStatus
        if micStatus == .notDetermined {
            permissionBanner(
                message: String(localized: "Mikrofon izni gerekli"),
                buttonTitle: String(localized: "İzin Ver"),
                buttonHint: String(localized: "Sistem izin penceresini açar. İzin Ver veya Reddet seçin."),
                action: { viewModel.requestMicrophonePermission() }
            )
        } else if micStatus == .denied {
            permissionBanner(
                message: String(localized: "Mikrofon izni reddedildi"),
                buttonTitle: String(localized: "Ayarları Aç"),
                buttonHint: String(localized: "Mikrofon izni daha önce reddedildi. Sistem Ayarları Gizlilik ekranını açar."),
                action: { viewModel.openPrivacySettings(for: .audio) }
            )
        }
    }

    @ViewBuilder
    private var screenPermissionBanner: some View {
        permissionBanner(
            message: String(localized: "Ekran kaydı izni gerekli"),
            buttonTitle: String(localized: "Ayarları Aç"),
            buttonHint: String(localized: "Sistem Ayarları içinde Ekran Kaydı gizlilik ekranını açar."),
            action: { viewModel.openScreenRecordingSettings() }
        )
    }

    private func permissionBanner(
        message: String,
        buttonTitle: String,
        buttonHint: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Button(buttonTitle, action: action)
                .font(.caption)
                .accessibilityHint(buttonHint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Action Zone

    private var actionZone: some View {
        VStack(spacing: 10) {
            // Error banner
            if let errorText = viewModel.errorText {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Record + Pause buttons
            HStack(spacing: 16) {
                Spacer()

                // Pause button — only when recording
                if viewModel.isRecording {
                    Button {
                        viewModel.togglePauseResume()
                    } label: {
                        Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 18))
                            .frame(width: 44, height: 44)
                            .background(Color.fmCardBg)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canPauseRecording)
                    .accessibilityLabel(viewModel.pauseResumeButtonTitle)
                    .accessibilityHint(String(localized: "\(GlobalHotkeyMonitor.pauseResumeToggleDisplay) aktif kaydı duraklatır veya devam ettirir."))
                }

                RecordButton(
                    state: recordButtonState,
                    countdownRemaining: viewModel.countdownRemaining,
                    accessibilityLabel: recordingButtonTitle,
                    action: { viewModel.toggleRecording() }
                )
                .disabled(!viewModel.canStartRecording && !viewModel.isRecording && !viewModel.isCountingDown)

                Spacer()
            }

            // Status row
            HStack {
                Text(String(localized: "Durum: \(viewModel.statusText)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityLabel(String(localized: "Durum \(viewModel.statusText)"))

                Spacer()

                if let lastSavedURL = viewModel.lastSavedURL {
                    Text(lastSavedURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .accessibilityLabel(String(localized: "Son kayıt dosyası \(lastSavedURL.path)"))
                }
            }
        }
    }

    // MARK: - Helpers

    private var recordButtonState: RecordButtonState {
        if viewModel.isPreparingRecording { return .preparing }
        if viewModel.isCountingDown       { return .countdown }
        if viewModel.isRecording && viewModel.isPaused { return .paused }
        if viewModel.isRecording          { return .recording }
        return .ready
    }

    /// Mirrors the original ContentView logic exactly — passed into RecordButton
    /// so the accessibility label stays in sync with the visual state.
    private var recordingButtonTitle: String {
        if viewModel.isPreparingRecording { return String(localized: "Kayıt hazırlanıyor…") }
        if viewModel.isCountingDown { return String(localized: "İptal Et (\(viewModel.countdownRemaining))") }
        return viewModel.isRecording ? String(localized: "Kaydı Durdur") : String(localized: "Kaydı Başlat")
    }

    private var frameCoachStatusText: String {
        if let instruction = viewModel.currentFrameCoachInstruction {
            return String(localized: "Kadraj koçu: \(instruction)")
        }
        return viewModel.isFrameCoachEnabled
            ? String(localized: "Kadraj koçu: açık")
            : String(localized: "Kadraj koçu: kapalı")
    }

    private var microphonePickerTitle: String {
        viewModel.showsScreenControls
            ? String(localized: "Mikrofon (isteğe bağlı)")
            : String(localized: "Mikrofon")
    }
}
```

- [ ] **Step 2: Verify build — if there are property-name compile errors, grep the ViewModel**

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild -scheme VideoRecorderApp -configuration Debug build 2>&1 | tail -20
```

If build errors appear for unknown property names, run:
```bash
grep -n "var shows" "/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/RecorderViewModel.swift"
```
Adjust guard conditions accordingly, then rebuild.

Expected: `BUILD SUCCEEDED` with no errors or warnings.

- [ ] **Step 3: Run all tests**

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | grep -E "(PASS|FAIL|error:)"
```
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
cd "/Users/recepgur/Desktop/video recorder"
git add Sources/VideoRecorderApp/ContentView.swift
git commit -m "feat: complete FrameMate ContentView redesign — 4-zone layout, cards, accessibility preserved"
```

---

### Task 8: Project Rename — FrameMate

**Files:**
- Modify: `project.yml`
- Modify: `Resources/Info.plist`

- [ ] **Step 1: Update PRODUCT_NAME in project.yml**

In `project.yml` (line 34), change:
```yaml
        PRODUCT_NAME: VideoRecorder
```
to:
```yaml
        PRODUCT_NAME: FrameMate
```

- [ ] **Step 2: Add CFBundleDisplayName to Info.plist**

In `Resources/Info.plist`, add after the `<key>CFBundleName</key>` entry:
```xml
	<key>CFBundleDisplayName</key>
	<string>FrameMate</string>
```

- [ ] **Step 3: Regenerate the Xcode project**

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodegen generate
```
Expected: `✅ Generated: VideoRecorder.xcodeproj`

- [ ] **Step 4: Verify build with new product name**

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild -scheme VideoRecorderApp -configuration Debug build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
cd "/Users/recepgur/Desktop/video recorder"
git add project.yml Resources/Info.plist VideoRecorder.xcodeproj/project.pbxproj
git commit -m "feat: rename app to FrameMate (PRODUCT_NAME + CFBundleDisplayName)"
```

---

## Implementation Checklist

All of the following must be true before this plan is considered complete:

- [ ] `FrameMateColors.swift` — 6 color tokens defined, file compiles
- [ ] `StatusPill.swift` — `RecordingStatus` enum with 4 states, pulse animation cancels cleanly on state change, `accessibilityLabel` on pill
- [ ] `FMCard.swift` — collapsible with spring animation, `.isHeader` trait always present, shadow-only (no border), `isExpanded = true` default
- [ ] `RecordButton.swift` — matches spec struct signature (`state`, `countdownRemaining`, `accessibilityLabel`, `action`), 5 states, ring pulse cancels cleanly
- [ ] `FMModeSelector.swift` — 4 segments + orientation toggle, `onEnableOverlay` called for Ekran+Kamera, all 11 mapping tests pass
- [ ] `ContentView.swift` — 4-zone layout, all original accessibility modifiers preserved, `debugPanel` removed, `recordingButtonTitle` passed to RecordButton
- [ ] `SettingsView` in `ContentView.swift` — debug section under `#if DEBUG` compiles in Debug build
- [ ] `project.yml` — `PRODUCT_NAME: FrameMate`
- [ ] `Resources/Info.plist` — `CFBundleDisplayName: FrameMate`
- [ ] All existing tests pass
- [ ] `BUILD SUCCEEDED` for Debug configuration
