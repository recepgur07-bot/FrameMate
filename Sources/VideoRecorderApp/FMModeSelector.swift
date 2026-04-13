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
