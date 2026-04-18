import SwiftUI

/// Popup-style preset selector for the currently supported recording modes.
/// VoiceOver users hear a single selectable control instead of a grid, while
/// sighted users still get a modern compact mode picker.
struct FMModeSelector: View {
    let selectedPreset: RecordingPreset
    let isOverlayEnabled: Bool
    let onPresetSelected: (RecordingPreset) -> Void
    let onEnableOverlay: () -> Void

    private let presets: [RecordingPreset] = [
        .horizontalCamera,
        .horizontalScreen,
        .audioOnly
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Kayıt modu"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            Menu {
                ForEach(presets) { preset in
                    Button {
                        if preset == .horizontalScreen && isOverlayEnabled {
                            onPresetSelected(.horizontalScreen)
                            return
                        }
                        onPresetSelected(preset)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.label)
                                Text(preset.shortDescription)
                                    .font(.caption)
                            }
                        } icon: {
                            Image(systemName: preset.symbolName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.fmAccent.opacity(0.12))
                        Image(systemName: selectedPreset.symbolName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.fmAccent)
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedPreset.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(selectedPreset.shortDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Kısayol: ⌘\(String(describing: selectedPreset.commandKey))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.fmAccent)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text(String(localized: "Değiştir"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.fmAccent)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.fmAccent)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.fmAccent.opacity(0.10))
                    .clipShape(Capsule())
                    .accessibilityHidden(true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.fmCardBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.fmAccent.opacity(0.35), lineWidth: 1.5)
                )
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(String(localized: "Kayıt modu"))
            .accessibilityValue(selectedPreset.label)
            .accessibilityHint(String(localized: "Boşluk tuşuna basıp listeden seçim yapabilirsin. Kısayollar Komut 1 ile Komut 3 arasındadır."))
        }
    }
}
