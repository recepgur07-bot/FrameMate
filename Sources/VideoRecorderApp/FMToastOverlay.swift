import Observation
import SwiftUI

enum ToastStyle {
    case success, info, error, warning
}

@Observable
@MainActor
final class ToastQueue {
    struct Message: Identifiable {
        let id = UUID()
        let text: String
        let style: ToastStyle
    }

    var messages: [Message] = []

    func post(message: String, style: ToastStyle) {
        let msg = Message(text: message, style: style)
        messages.append(msg)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            messages.removeAll { $0.id == msg.id }
        }
    }
}

struct FMToastOverlay: View {
    var queue: ToastQueue

    var body: some View {
        VStack(spacing: 4) {
            ForEach(queue.messages) { message in
                ToastBanner(message: message)
            }
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.2), value: queue.messages.count)
    }
}

private struct ToastBanner: View {
    let message: ToastQueue.Message

    private var backgroundColor: Color {
        switch message.style {
        case .success: return Color.green.opacity(0.85)
        case .info:    return Color.blue.opacity(0.85)
        case .error:   return Color.red.opacity(0.85)
        case .warning: return Color.orange.opacity(0.85)
        }
    }

    var body: some View {
        Text(message.text)
            .font(.callout)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8))
    }
}
