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
