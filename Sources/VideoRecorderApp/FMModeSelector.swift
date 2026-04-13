// Sources/VideoRecorderApp/FMModeSelector.swift
import SwiftUI

/// Custom segmented mode selector that replaces the plain Picker in ContentView.
/// Maps primary-mode + orientation choices onto a `RecordingPreset` and
/// propagates changes via callbacks (no direct ViewModel dependency keeps
/// the component testable in isolation).
///
/// VoiceOver design: the 4 mode buttons are collapsed into ONE adjustable
/// element ("Kayıt modu, Kamera") and the 2 orientation buttons into another
/// ("Yönlendirme, Yatay"). Users change them with arrow keys — no need to
/// tab through every individual button.
struct FMModeSelector: View {
    // MARK: - Input

    let selectedPreset: RecordingPreset
    let isOverlayEnabled: Bool
    let onPresetSelected: (RecordingPreset) -> Void
    let onEnableOverlay: () -> Void

    // MARK: - Local state

    @State private var primaryMode: PrimaryMode
    @State private var orientation: Orientation

    // MARK: - Nested types

    enum PrimaryMode: Equatable {
        case camera, screen, screenCamera, audio

        var label: String {
            switch self {
            case .camera:       return String(localized: "Kamera")
            case .screen:       return String(localized: "Ekran")
            case .screenCamera: return String(localized: "Ekran+Kamera")
            case .audio:        return String(localized: "Ses")
            }
        }
    }

    enum Orientation: Equatable {
        case horizontal, vertical

        var label: String {
            switch self {
            case .horizontal: return String(localized: "Yatay")
            case .vertical:   return String(localized: "Dikey")
            }
        }
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
            // ── Primary mode row ─────────────────────────────────────────
            // Visual: 4 clickable segment buttons.
            // VoiceOver: collapsed into ONE adjustable element.
            //   Reads: "Kayıt modu, Kamera"  →  arrow up/down to cycle.
            HStack(spacing: 4) {
                modeSegment(mode: .camera,
                            icon: "camera.fill",
                            label: PrimaryMode.camera.label)
                modeSegment(mode: .screen,
                            icon: "desktopcomputer",
                            label: PrimaryMode.screen.label)
                modeSegment(mode: .screenCamera,
                            icon: "rectangle.inset.filled.on.rectangle",
                            label: PrimaryMode.screenCamera.label)
                modeSegment(mode: .audio,
                            icon: "waveform.circle.fill",
                            label: PrimaryMode.audio.label)
            }
            .padding(4)
            .background(Color.fmCardBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            // VoiceOver collapses all 4 buttons into one adjustable control
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Kayıt modu"))
            .accessibilityValue(primaryMode.label)
            .accessibilityHint(String(localized: "Değiştirmek için ok tuşlarını kullan"))
            .accessibilityAdjustableAction { direction in
                let modes: [PrimaryMode] = [.camera, .screen, .screenCamera, .audio]
                guard let idx = modes.firstIndex(of: primaryMode) else { return }
                let next: PrimaryMode?
                switch direction {
                case .increment: next = idx + 1 < modes.count ? modes[idx + 1] : nil
                case .decrement: next = idx > 0               ? modes[idx - 1] : nil
                @unknown default: next = nil
                }
                if let mode = next {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        primaryMode = mode
                    }
                    propagate()
                    if mode == .screenCamera && !isOverlayEnabled { onEnableOverlay() }
                }
            }

            // ── Orientation row ──────────────────────────────────────────
            // Only shown for Kamera and Ekran modes.
            // VoiceOver: collapsed into ONE adjustable element.
            //   Reads: "Yönlendirme, Yatay"  →  arrow up/down to toggle.
            if primaryMode == .camera || primaryMode == .screen {
                HStack(spacing: 4) {
                    orientationButton(orientation: .horizontal,
                                      icon: "rectangle.fill",
                                      label: Orientation.horizontal.label)
                    orientationButton(orientation: .vertical,
                                      icon: "rectangle.portrait.fill",
                                      label: Orientation.vertical.label)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Yönlendirme"))
                .accessibilityValue(orientation.label)
                .accessibilityHint(String(localized: "Değiştirmek için ok tuşlarını kullan"))
                .accessibilityAdjustableAction { _ in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        orientation = orientation == .horizontal ? .vertical : .horizontal
                    }
                    propagate()
                }
            }
        }
        .onChange(of: selectedPreset) { _, newPreset in
            let (pm, ori) = Self.decompose(preset: newPreset, overlayEnabled: isOverlayEnabled)
            primaryMode = pm
            orientation = ori
        }
    }

    // MARK: - Segment builders
    // These are purely visual — VoiceOver does not navigate into them
    // (the parent HStack carries .accessibilityElement(children: .ignore)).

    @ViewBuilder
    private func modeSegment(mode: PrimaryMode, icon: String, label: String) -> some View {
        let isSelected = primaryMode == mode
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                primaryMode = mode
            }
            propagate()
            if mode == .screenCamera && !isOverlayEnabled { onEnableOverlay() }
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
    }

    // MARK: - Preset mapping (static — unit-testable)

    private func propagate() {
        onPresetSelected(Self.compose(primaryMode: primaryMode, orientation: orientation))
    }

    static func compose(primaryMode: PrimaryMode, orientation: Orientation) -> RecordingPreset {
        switch primaryMode {
        case .camera:
            return orientation == .horizontal ? .horizontalCamera : .verticalCamera
        case .screen:
            return orientation == .horizontal ? .horizontalScreen : .verticalScreen
        case .screenCamera:
            return .horizontalScreen
        case .audio:
            return .audioOnly
        }
    }

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
