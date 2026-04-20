// Sources/VideoRecorderApp/FMToastOverlay.swift
import AppKit
import SwiftUI

// MARK: - Toast Model

enum ToastStyle {
    case success   // yeşil — 3 sn sonra otomatik kapanır
    case info      // mavi  — 3 sn sonra otomatik kapanır
    case warning   // turuncu — "Tamam" gerektirir
    case error     // kırmızı — "Tamam" gerektirir

    var autoDismiss: Bool {
        switch self {
        case .success, .info: return true
        case .warning, .error: return false
        }
    }

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info:    return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: return .green
        case .info:    return Color(red: 0.357, green: 0.298, blue: 0.961) // fmAccent
        case .warning: return .orange
        case .error:   return .red
        }
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let style: ToastStyle
}

// MARK: - Toast Queue

@Observable
final class ToastQueue {
    var messages: [ToastMessage] = []

    func post(message: String, style: ToastStyle) {
        let toast = ToastMessage(message: message, style: style)
        messages.append(toast)
    }

    func dismiss(id: UUID) {
        messages.removeAll { $0.id == id }
    }
}

// MARK: - Toast Overlay

/// Place this as an `.overlay(alignment: .top)` on ContentView.
/// Renders queued toasts stacked below the header, one per slot.
struct FMToastOverlay: View {
    var queue: ToastQueue

    var body: some View {
        VStack(spacing: 8) {
            ForEach(queue.messages) { toast in
                FMToastBanner(toast: toast, onDismiss: { queue.dismiss(id: toast.id) })
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal:   .move(edge: .top).combined(with: .opacity)
                        )
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: queue.messages)
    }
}

// MARK: - Single Banner

private struct FMToastBanner: View {
    let toast: ToastMessage
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.style.icon)
                .foregroundStyle(toast.style.color)
                .font(.system(size: 16, weight: .medium))
                .accessibilityHidden(true)

            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !toast.style.autoDismiss {
                Button("Tamam") { onDismiss() }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(toast.style.color)
                    .accessibilityLabel(String(localized: "Bildirimi kapat"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(toast.style.color.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: Color.primary.opacity(0.10), radius: 6, x: 0, y: 3)
        )
        // VoiceOver: announce immediately when toast appears
        .accessibilityElement(children: .combine)
        .accessibilityLabel(toast.message)
        .accessibilityAddTraits(.isStaticText)
        .task {
            guard toast.style.autoDismiss else { return }
            // Give VoiceOver users extra time to hear the announcement before it disappears.
            let delay: Double = NSWorkspace.shared.runningApplications
                .contains(where: { $0.bundleIdentifier == "com.apple.VoiceOver" }) ? 6 : 3
            try? await Task.sleep(for: .seconds(delay))
            onDismiss()
        }
    }
}
