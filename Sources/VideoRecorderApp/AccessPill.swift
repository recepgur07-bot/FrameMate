// Sources/VideoRecorderApp/AccessPill.swift
import SwiftUI

/// Small capsule badge shown in the header zone, mirroring `StatusPill`'s look.
/// Surfaces the account-free access state (local trial / monthly free quota)
/// so the user never has to open Settings to find out how much time is left.
struct AccessPill: View {
    let accessState: AppAccessState
    let onTap: () -> Void

    var body: some View {
        if let content {
            Button(action: onTap) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(content.color)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)

                    Text(content.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(content.color)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(content.color.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(content.accessibilityLabel)
            .accessibilityHint(String(localized: "Planları görmek için etkinleştir."))
        }
    }

    private struct Content {
        let label: String
        let accessibilityLabel: String
        let color: Color
    }

    private var content: Content? {
        switch accessState.accessKind {
        case .localTrial:
            let days = accessState.localTrialDaysRemaining
            return Content(
                label: String(localized: "Sınırsız deneme · \(days) gün kaldı"),
                accessibilityLabel: String(localized: "Sınırsız deneme, \(days) gün kaldı"),
                color: .fmAccent
            )
        case .freeTier:
            let minutes = accessState.freeTierSecondsRemaining / 60
            let seconds = accessState.freeTierSecondsRemaining % 60
            return Content(
                label: String(localized: "Bu ay: \(minutes) dk \(seconds) sn kaldı"),
                accessibilityLabel: String(localized: "Bu ay \(minutes) dakika \(seconds) saniye kaldı"),
                color: .secondary
            )
        case .freeTierExhausted:
            return Content(
                label: String(localized: "Ücretsiz süre bitti"),
                accessibilityLabel: String(localized: "Bu ayki ücretsiz süre bitti"),
                color: .orange
            )
        case .yearly, .lifetime:
            return nil
        }
    }
}
