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
                Button(String(localized: "İleri")) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.fmAccent)
                .keyboardShortcut(.return, modifiers: [])
            } else {
                Button(String(localized: "Başla")) {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.fmAccent)
                .disabled(!canProceed)
                .accessibilityHint(canProceed ? "" : startHint)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
    }

    private var startHint: String {
        let missingTitles = viewModel.requiredPermissionItems
            .filter { !$0.isSatisfied }
            .map(\.title)
        if missingTitles.isEmpty { return "" }
        if missingTitles.count == 1 { return String(localized: "\(missingTitles[0]) izni gerekli") }
        if missingTitles.count == 2 { return String(localized: "\(missingTitles[0]) ve \(missingTitles[1]) izni gerekli") }
        return ""
    }

    private var canProceed: Bool {
        viewModel.canProceedPastOnboarding
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
        .accessibilityLabel(String(localized: "Adım 1 / 3, FrameMate'e Hoş Geldin"))
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
                title: String(localized: "Ekran Kaydı"),
                description: String(localized: "Tüm ekranı veya bir pencereyi yakala.")
            )
            ModeRow(
                symbol: "rectangle.badge.person.crop",
                title: String(localized: "Ekran + Kamera"),
                description: String(localized: "Kendi görüntünle birlikte kaydet.")
            )
            ModeRow(
                symbol: "waveform",
                title: String(localized: "Sadece Ses"),
                description: String(localized: "Toplantı ve podcast için saf ses kaydı.")
            )
        }
        .padding(.horizontal, 32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Adım 2 / 3, Kayıt Modları"))
    }
}

// MARK: - Permissions Page

private struct OnboardingPermissionsPage: View {
    var viewModel: RecorderViewModel
    @State private var feedbackMessage: String?
    @State private var feedbackColor: Color = .green

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Birkaç İzne İhtiyacımız Var")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(String(localized: "Adım 3 / 3: Birkaç İzne İhtiyacımız Var"))
                .accessibilityAddTraits(.isHeader)

            Text("Sağdaki düğmeler tıklanabilir. İzin istedikten sonra macOS penceresi açılırsa oradan onay ver.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let feedbackMessage {
                HStack(spacing: 8) {
                    Image(systemName: feedbackColor == .green ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(feedbackColor)
                        .accessibilityHidden(true)
                    Text(feedbackMessage)
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(12)
                .background(feedbackColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(feedbackMessage)
            }

            ForEach(viewModel.permissionHubItems) { item in
                PermissionRow(item: item, onPrimaryAction: {
                    viewModel.performPrimaryPermissionAction(for: item.id)
                }, onSecondaryAction: {
                    viewModel.performSecondaryPermissionAction(for: item.id)
                })
            }

            Text("Kamera izni yalnızca Ekran + Kamera modunda gereklidir.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
        .onChange(of: viewModel.cameraPermissionStatus) { _, newStatus in
            switch newStatus {
            case .authorized:
                postFeedback(String(localized: "Kamera izni verildi."), color: .green)
            case .denied, .restricted:
                postFeedback(String(localized: "Kamera izni verilmedi."), color: .orange)
            default:
                break
            }
        }
        .onChange(of: viewModel.microphonePermissionStatus) { _, newStatus in
            switch newStatus {
            case .authorized:
                postFeedback(String(localized: "Mikrofon izni verildi."), color: .green)
            case .denied, .restricted:
                postFeedback(String(localized: "Mikrofon izni verilmedi."), color: .orange)
            default:
                break
            }
        }
        .onChange(of: viewModel.screenPermissionNeedsRestart) { _, needsRestart in
            guard needsRestart else { return }
            postFeedback(String(localized: "Ekran kaydı izni verildi. Uygulamayı yeniden açman gerekecek."), color: .green)
        }
    }

    private func postFeedback(_ message: String, color: Color) {
        feedbackMessage = message
        feedbackColor = color
        viewModel.announceText(message)
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
    let item: PermissionHubItem
    let onPrimaryAction: () -> Void
    let onSecondaryAction: (() -> Void)?

    // MARK: - VoiceOver: her satır TEK bir eleman
    // macOS VoiceOver'da sağ/sol ok ile satırlar arasında tek adımda geçiş sağlar.
    // Durum ve eylem accessibilityLabel + accessibilityAction ile iletilir.

    private var rowAccessibilityLabel: String {
        let suffix: String = item.isRequired ? "" : String(localized: ", opsiyonel")
        return "\(item.title)\(suffix), \(item.statusLabel)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.fmAccent.opacity(0.12))
                Image(systemName: item.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.fmAccent)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.headline)
                    if !item.isRequired {
                        Text("Opsiyonel")  // LocalizedStringKey — "Opsiyonel" → "Optional"
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.10))
                            .clipShape(Capsule())
                    }
                    statusBadge
                }

                Text(item.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let helperText = item.helperText {
                    Text(helperText)
                        .font(.caption)
                        .foregroundStyle(item.isSatisfied ? .green : .secondary)
                }
            }

            Spacer(minLength: 16)

            stateButton
        }
        .padding(16)
        .background(rowBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(rowBorderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statusBadge: some View {
        Text(item.statusLabel)
            .font(.caption)
            .foregroundStyle(item.isSatisfied ? .green : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((item.isSatisfied ? Color.green : Color.orange).opacity(0.12))
            .clipShape(Capsule())
    }

    private var rowBackground: Color {
        if item.isRequestInFlight {
            return Color.fmAccent.opacity(0.08)
        }
        return item.isSatisfied ? Color.green.opacity(0.05) : Color.white.opacity(0.72)
    }

    private var rowBorderColor: Color {
        if item.isRequestInFlight {
            return Color.fmAccent.opacity(0.45)
        }
        return item.isSatisfied ? Color.green.opacity(0.22) : Color.secondary.opacity(0.12)
    }

    @ViewBuilder
    private var stateButton: some View {
        if let buttonTitle = item.primaryAction.buttonTitle {
            VStack(alignment: .trailing, spacing: 6) {
                Button(buttonTitle) { onPrimaryAction() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.fmAccent)
                    .controlSize(.large)
                    .frame(minWidth: 128)
                if let secondaryAction = item.secondaryAction,
                   let secondaryTitle = secondaryAction.buttonTitle,
                   let onSecondaryAction {
                    Button(secondaryTitle) { onSecondaryAction() }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .font(.caption)
                        .frame(minWidth: 128)
                }
            }
        } else {
            VStack(alignment: .trailing, spacing: 6) {
                Label(item.isRequestInFlight ? "Bekleniyor" : "Tamam", systemImage: item.isRequestInFlight ? "hourglass" : "checkmark.circle.fill")
                    .foregroundStyle(item.isRequestInFlight ? Color.fmAccent : .green)
                    .font(.subheadline.weight(.semibold))
                if item.isRequestInFlight {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }
}
