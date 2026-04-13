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
