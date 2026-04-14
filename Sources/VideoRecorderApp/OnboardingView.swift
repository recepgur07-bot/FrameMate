import SwiftUI
import AppKit

// MARK: - OnboardingView

struct OnboardingView: View {
    var onDismiss: () -> Void
    var viewModel: RecorderViewModel

    @State private var currentStep = 0

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 24)
                .padding(.bottom, 20)

            ZStack {
                switch currentStep {
                case 0:
                    OnboardingWelcomePage()
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .leading)
                        ))
                case 1:
                    OnboardingModesPage()
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .leading)
                        ))
                case 2:
                    OnboardingPermissionsPage(viewModel: viewModel)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .leading)
                        ))
                default:
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            navigationRow
                .padding(.horizontal, 32)
                .padding(.bottom, 28)
        }
        .frame(width: 560)
        .frame(minHeight: 420)
        .background(
            ZStack {
                Color.clear.background(.regularMaterial)
                LinearGradient(
                    colors: [Color.fmAccent.opacity(0.08), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        )
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(index == currentStep ? Color.fmAccent : Color.secondary.opacity(0.3))
                    .frame(width: index == currentStep ? 10 : 7, height: index == currentStep ? 10 : 7)
                    .animation(.easeInOut(duration: 0.25), value: currentStep)
            }
        }
        .accessibilityHidden(true)
    }

    private var navigationRow: some View {
        HStack {
            Spacer()
            if currentStep < 2 {
                Button("İleri") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.fmAccent)
                .keyboardShortcut(.return, modifiers: [])
            } else {
                Button("Başla") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.fmAccent)
                .disabled(!canProceed)
                .accessibilityHint(canProceed ? "" : "Ekran kaydı ve mikrofon izni gerekli")
                .keyboardShortcut(.return, modifiers: [])
            }
        }
    }

    private var canProceed: Bool {
        viewModel.screenRecordingPermissionStatus == .authorized &&
        !viewModel.screenPermissionNeedsRestart &&
        viewModel.microphonePermissionStatus == .authorized
    }
}

// MARK: - Welcome Page

private struct OnboardingWelcomePage: View {
    var body: some View {
        VStack(spacing: 16) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .accessibilityHidden(true)
            }

            Text("FrameMate'e Hoş Geldin")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("Ekranını, sesini ve kameranı kolayca kaydet.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Adım 1 / 3, FrameMate'e Hoş Geldin")
    }
}

// MARK: - Modes Page

private struct OnboardingModesPage: View {
    private struct ModeRow: View {
        let symbol: String
        let title: String
        let description: String

        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 24))
                    .foregroundStyle(Color.fmAccent)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.semibold)
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nasıl Kayıt Yapabilirsin?")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            ModeRow(
                symbol: "rectangle.on.rectangle",
                title: "Ekran Kaydı",
                description: "Tüm ekranı veya bir pencereyi yakala."
            )
            ModeRow(
                symbol: "rectangle.badge.person.crop",
                title: "Ekran + Kamera",
                description: "Kendi görüntünle birlikte kaydet."
            )
            ModeRow(
                symbol: "waveform",
                title: "Sadece Ses",
                description: "Toplantı ve podcast için saf ses kaydı."
            )
        }
        .padding(.horizontal, 32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Adım 2 / 3, Kayıt Modları")
    }
}

// MARK: - Permissions Page

private struct OnboardingPermissionsPage: View {
    var viewModel: RecorderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Birkaç İzne İhtiyacımız Var")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            screenRecordingRow
            microphoneRow
            cameraRow

            Text("Kamera izni yalnızca Ekran + Kamera modunda gereklidir.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Adım 3 / 3, İzinler. Ekran kaydı izni gerekli. Mikrofon izni gerekli. Kamera izni opsiyonel.")
    }

    private var screenRecordingRow: some View {
        PermissionRow(
            symbol: "lock.rectangle",
            title: "Ekran Kaydı",
            isOptional: false,
            state: screenRecordingRowState,
            onGrant: { viewModel.requestScreenRecordingPermission() },
            onOpenSettings: nil
        )
    }

    private var screenRecordingRowState: PermissionRowState {
        if viewModel.screenRecordingPermissionStatus == .authorized && !viewModel.screenPermissionNeedsRestart {
            return .granted
        } else if viewModel.screenRecordingPermissionStatus == .authorized && viewModel.screenPermissionNeedsRestart {
            return .needsRestart
        } else {
            return .notGranted
        }
    }

    private var microphoneRow: some View {
        PermissionRow(
            symbol: "mic",
            title: "Mikrofon",
            isOptional: false,
            state: microphoneRowState,
            onGrant: { viewModel.requestMicrophonePermission() },
            onOpenSettings: {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                )
            }
        )
    }

    private var microphoneRowState: PermissionRowState {
        switch viewModel.microphonePermissionStatus {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        default: return .notGranted
        }
    }

    private var cameraRow: some View {
        PermissionRow(
            symbol: "camera",
            title: "Kamera",
            isOptional: true,
            state: cameraRowState,
            onGrant: { viewModel.requestCameraPermission() },
            onOpenSettings: {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
                )
            }
        )
    }

    private var cameraRowState: PermissionRowState {
        switch viewModel.cameraPermissionStatus {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        default: return .notGranted
        }
    }
}

// MARK: - PermissionRow

private enum PermissionRowState {
    case notGranted
    case granted
    case denied
    case needsRestart
}

private struct PermissionRow: View {
    let symbol: String
    let title: String
    let isOptional: Bool
    let state: PermissionRowState
    let onGrant: () -> Void
    let onOpenSettings: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(Color.fmAccent)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .fontWeight(.semibold)
                    if isOptional {
                        Text("(opsiyonel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                stateLabel
            }

            Spacer()

            stateButton
        }
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch state {
        case .notGranted:
            EmptyView()
        case .granted:
            EmptyView()
        case .denied:
            Text("Erişim reddedildi")
                .font(.caption)
                .foregroundStyle(.red)
        case .needsRestart:
            Text("Uygulamayı yeniden başlatın")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var stateButton: some View {
        switch state {
        case .notGranted:
            Button("İzin Ver") { onGrant() }
                .buttonStyle(.bordered)
                .accessibilityLabel("\(title) izni ver")

        case .granted:
            Label("Verildi", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Verildi")

        case .denied:
            if let onOpenSettings {
                Button("Ayarları Aç") { onOpenSettings() }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("\(title) için sistem ayarlarını aç")
            }

        case .needsRestart:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("\(title) izni uygulamayı yeniden başlatmayı gerektiriyor")
        }
    }
}
