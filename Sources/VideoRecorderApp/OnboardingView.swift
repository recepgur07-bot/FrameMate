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
        if missingTitles.count == 1 { return "\(missingTitles[0]) izni gerekli" }
        if missingTitles.count == 2 { return "\(missingTitles[0]) ve \(missingTitles[1]) izni gerekli" }
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
                .accessibilityLabel("Adım 3 / 3: Birkaç İzne İhtiyacımız Var")
                .accessibilityAddTraits(.isHeader)

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
        let suffix = item.isRequired ? "" : String(localized: ", opsiyonel")
        return String(localized: "\(item.title)\(suffix), \(item.statusLabel)")
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.symbolName)
                .font(.system(size: 20))
                .foregroundStyle(Color.fmAccent)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .fontWeight(.semibold)
                    if !item.isRequired {
                        Text("(opsiyonel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                stateLabel
            }

            Spacer()

            stateButton
        }
        // Tüm satırı tek VoiceOver elemanına dönüştür
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel)
        // Eylem varsa accessibilityAction ekle
        .modifier(PermissionRowActions(item: item, onPrimaryAction: onPrimaryAction, onSecondaryAction: onSecondaryAction))
    }

    @ViewBuilder
    private var stateLabel: some View {
        Text(item.statusLabel)
            .font(.caption)
            .foregroundStyle(item.isSatisfied ? .green : .orange)
    }

    @ViewBuilder
    private var stateButton: some View {
        if let buttonTitle = item.primaryAction.buttonTitle {
            VStack(alignment: .trailing, spacing: 6) {
                Button(buttonTitle) { onPrimaryAction() }
                    .buttonStyle(.bordered)
                if let secondaryAction = item.secondaryAction,
                   let secondaryTitle = secondaryAction.buttonTitle,
                   let onSecondaryAction {
                    Button(secondaryTitle) { onSecondaryAction() }
                        .buttonStyle(.plain)
                        .font(.caption)
                }
            }
        } else {
            Label("Verildi", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

// MARK: - PermissionRow Accessibility Actions

/// Adds the correct accessibilityAction(s) to a PermissionRow based on its state.
/// Separated into a ViewModifier so the conditional logic stays outside body.
private struct PermissionRowActions: ViewModifier {
    let item: PermissionHubItem
    let onPrimaryAction: () -> Void
    let onSecondaryAction: (() -> Void)?

    func body(content: Content) -> some View {
        if let primaryTitle = item.primaryAction.buttonTitle {
            content
                .accessibilityAction(named: primaryTitle) {
                    onPrimaryAction()
                }
                .accessibilityAction(named: item.secondaryAction?.buttonTitle ?? "") {
                    onSecondaryAction?()
                }
        } else {
            content
        }
    }
}
