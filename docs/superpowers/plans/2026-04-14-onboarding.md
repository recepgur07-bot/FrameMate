# Onboarding Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** İlk açılışta kullanıcıya FrameMate'i 3 adımda tanıtan, izin verilmeden geçilemeyen onboarding sheet'i ekle.

**Architecture:** Yeni `OnboardingView.swift` dosyası tüm 3 sayfayı barındırır. `VideoRecorderApp.swift`'e `@AppStorage("onboarding.completed")` ve `.sheet` eklenir. `RecorderViewModel` değiştirilmez.

**Tech Stack:** SwiftUI, `@Observable`, `@AppStorage`, `AVAuthorizationStatus`, `ScreenRecordingAuthorizationStatus`, `NSWorkspace`

---

## Chunk 1: OnboardingView — Temel Yapı ve Adım Göstergesi

### Task 1: `OnboardingView.swift` dosyasını oluştur — iskelet ve adım göstergesi

**Files:**
- Create: `Sources/VideoRecorderApp/OnboardingView.swift`

- [ ] **Adım 1: Dosyayı oluştur**

```swift
import SwiftUI
import AppKit

struct OnboardingView: View {
    @Binding var onboardingCompleted: Bool
    var viewModel: RecorderViewModel

    @State private var currentStep = 0

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 24)
                .padding(.bottom, 20)

            // Sayfa geçişleri buraya gelecek — ZStack ile (Task 2'de doldurulacak)
            Spacer()

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
                    onboardingCompleted = true
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
```

- [ ] **Adım 2: Projeyi derle — derleme hatası olmamalı**

```bash
cd "/Users/recepgur/Desktop/video recorder"
xcodebuild build -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | tail -20
```

Beklenen: `BUILD SUCCEEDED` veya sadece henüz eksik sayfa view'lerinden kaynaklanan hata.

- [ ] **Adım 3: Commit**

```bash
cd "/Users/recepgur/Desktop/video recorder"
git add Sources/VideoRecorderApp/OnboardingView.swift
git commit -m "feat: OnboardingView iskelet — adım göstergesi ve navigasyon"
```

---

### Task 2: Adım 1 — Hoş Geldin sayfası

**Files:**
- Modify: `Sources/VideoRecorderApp/OnboardingView.swift`

- [ ] **Adım 1: `OnboardingWelcomePage` view'ini ekle**

`OnboardingView`'in sonuna (struct'ın dışına) ekle:

```swift
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
```

- [ ] **Adım 2: `OnboardingView.body` içinde sayfayı bağla**

`body`'deki `// Sayfa geçişleri buraya gelecek — ZStack ile (Task 2'de doldurulacak)` ve `Spacer()` satırlarını şununla değiştir:

```swift
ZStack {
    switch currentStep {
    case 0:
        OnboardingWelcomePage()
            .transition(.asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            ))
    case 1:
        // Task 3'te gelecek
        Color.clear
    case 2:
        // Task 4'te gelecek
        Color.clear
    default:
        Color.clear
    }
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
```

Not: `ZStack` (Group değil) zorunlu — macOS SwiftUI'de `.transition` animasyonlarının tetiklenmesi için view identity container olarak `ZStack` gereklidir.

- [ ] **Adım 3: Derle**

```bash
xcodebuild build -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | tail -10
```

Beklenen: `BUILD SUCCEEDED`

- [ ] **Adım 4: Commit**

```bash
git add Sources/VideoRecorderApp/OnboardingView.swift
git commit -m "feat: onboarding adım 1 — hoş geldin sayfası"
```

---

### Task 3: Adım 2 — Kayıt Modları sayfası

**Files:**
- Modify: `Sources/VideoRecorderApp/OnboardingView.swift`

- [ ] **Adım 1: `OnboardingModesPage` view'ini ekle**

`OnboardingWelcomePage`'den sonra ekle:

```swift
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
        VStack(alignment: .leading, spacing: 20) {
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
```

- [ ] **Adım 2: ZStack'te `case 1`'i güncelle**

`case 1:` altındaki `Color.clear`'ı şununla değiştir:

```swift
OnboardingModesPage()
    .transition(.asymmetric(
        insertion: .move(edge: .trailing),
        removal: .move(edge: .leading)
    ))
```

- [ ] **Adım 3: Derle**

```bash
xcodebuild build -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | tail -10
```

Beklenen: `BUILD SUCCEEDED`

- [ ] **Adım 4: Commit**

```bash
git add Sources/VideoRecorderApp/OnboardingView.swift
git commit -m "feat: onboarding adım 2 — kayıt modları sayfası"
```

---

## Chunk 2: İzinler Sayfası ve VideoRecorderApp Entegrasyonu

### Task 4: Adım 3 — İzinler sayfası

**Files:**
- Modify: `Sources/VideoRecorderApp/OnboardingView.swift`

- [ ] **Adım 1: `OnboardingPermissionsPage` view'ini ekle**

`OnboardingModesPage`'den sonra ekle:

```swift
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

    // MARK: - Ekran Kaydı

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

    // MARK: - Mikrofon

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

    // MARK: - Kamera

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
```

- [ ] **Adım 2: ZStack'te `case 2`'yi güncelle**

`case 2:` altındaki `Color.clear`'ı şununla değiştir:

```swift
OnboardingPermissionsPage(viewModel: viewModel)
    .transition(.asymmetric(
        insertion: .move(edge: .trailing),
        removal: .move(edge: .leading)
    ))
```

- [ ] **Adım 3: Derle**

```bash
xcodebuild build -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | tail -10
```

Beklenen: `BUILD SUCCEEDED`

- [ ] **Adım 4: Commit**

```bash
git add Sources/VideoRecorderApp/OnboardingView.swift
git commit -m "feat: onboarding adım 3 — izinler sayfası ve PermissionRow"
```

---

### Task 5: `VideoRecorderApp.swift` entegrasyonu

**Files:**
- Modify: `Sources/VideoRecorderApp/VideoRecorderApp.swift:32-60`

- [ ] **Adım 1: `@AppStorage` property'sini ekle**

`VideoRecorderApp` struct'ına mevcut `@State` ve diğer property'lerin yanına şunu ekle:

```swift
@AppStorage("onboarding.completed") private var onboardingCompleted = false
```

- [ ] **Adım 2: `.sheet` ve `.interactiveDismissDisabled` ekle**

`VideoRecorderApp.body` içinde `ContentView(viewModel: viewModel)` zincirinin sonuna (`.onAppear`'dan önce veya sonra, sıra önemli değil) şunu ekle:

```swift
.sheet(
    isPresented: Binding(
        get: { !onboardingCompleted },
        set: { if !$0 { onboardingCompleted = true } }
    )
) {
    OnboardingView(
        onboardingCompleted: $onboardingCompleted,
        viewModel: viewModel
    )
    .interactiveDismissDisabled(!onboardingCompleted)
}
```

Not: `.interactiveDismissDisabled(!onboardingCompleted)` sheet'in **içinde**, `OnboardingView` üzerine uygulanır. macOS SwiftUI'de bu modifier yalnızca sunulan view'e uygulandığında sheet dismiss'i engeller; ContentView zincirine uygulanırsa etkisiz kalır.

- [ ] **Adım 3: Derle**

```bash
xcodebuild build -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | tail -10
```

Beklenen: `BUILD SUCCEEDED`

- [ ] **Adım 4: Test suite'i çalıştır**

```bash
xcodebuild test -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | tail -20
```

Beklenen: Tüm mevcut testler geçmeli. Yeni test dosyası eklenmedi — `OnboardingView` saf UI kodu, bağımsız test edilecek iş mantığı içermiyor; izin durum mantığı `RecorderViewModel`'de zaten test kapsamında.

- [ ] **Adım 5: `XcodeProjectConfigurationTests` güncelleme kontrolü**

```bash
grep -n "OnboardingView\|onboarding" "/Users/recepgur/Desktop/video recorder/Tests/VideoRecorderAppTests/XcodeProjectConfigurationTests.swift"
```

Eğer test dosya sayısı veya kaynak listesi kontrol ediyorsa, yeni dosyayı listeye ekle. Eğer çıktı boş ise adımı atla.

- [ ] **Adım 6: Commit**

```bash
git add Sources/VideoRecorderApp/VideoRecorderApp.swift
git commit -m "feat: VideoRecorderApp onboarding sheet entegrasyonu"
```

---

### Task 6: Xcode proje dosyasına kaynak ekle

**Files:**
- Modify: `VideoRecorder.xcodeproj/project.pbxproj`
- Modify: `project.yml` (XcodeGen kullanılıyorsa)

- [ ] **Adım 1: `project.yml` içinde yeni dosyayı kontrol et**

```bash
grep -n "sources\|Sources" "/Users/recepgur/Desktop/video recorder/project.yml" | head -10
```

- [ ] **Adım 2: XcodeGen ile proje yenile (eğer `project.yml` mevcutsa)**

```bash
cd "/Users/recepgur/Desktop/video recorder" && xcodegen generate 2>&1 | tail -10
```

Eğer `xcodegen` bulunamazsa:

```bash
which xcodegen || echo "xcodegen bulunamadı"
```

Bulunamazsa Xcode'da `File > Add Files to VideoRecorder` ile `OnboardingView.swift`'i manuel ekle.

- [ ] **Adım 3: Son derleme**

```bash
xcodebuild build -scheme VideoRecorderApp -destination 'platform=macOS' 2>&1 | tail -10
```

Beklenen: `BUILD SUCCEEDED`

- [ ] **Adım 4: Commit**

```bash
git add VideoRecorder.xcodeproj/project.pbxproj project.yml
git commit -m "chore: OnboardingView.swift xcode projesine eklendi"
```
