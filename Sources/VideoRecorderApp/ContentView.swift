import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var viewModel: RecorderViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Video Kaydedici")
                .font(.title)
                .accessibilityAddTraits(.isHeader)

            Picker("Kayıt modu", selection: Binding(
                get: { viewModel.selectedPreset },
                set: { viewModel.selectPreset($0) }
            )) {
                ForEach(RecordingPreset.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(String(localized: "Kayıt modu seçimi"))

            if viewModel.showsCameraControls {
                VideoPreviewView(
                    session: viewModel.previewSession,
                    crop: viewModel.currentAutoReframeCrop
                )
                .frame(minHeight: 240)
                .accessibilityHidden(true)

                Picker("Kamera", selection: $viewModel.selectedCameraID) {
                    if viewModel.cameraPermissionStatus != .authorized {
                        Text("Kamera izni gerekli").tag("")
                    } else if viewModel.cameras.isEmpty {
                        Text("Kamera bulunamadı").tag("")
                    } else {
                        ForEach(viewModel.cameras) { camera in
                            Text(camera.name).tag(camera.id)
                        }
                    }
                }
                .disabled(!viewModel.canChooseCamera)
                .accessibilityLabel(String(localized: "Kamera seçimi"))
                .onChange(of: viewModel.selectedCameraID) {
                    viewModel.applySelectedInputs()
                }
            }

            if viewModel.showsScreenControls {
                ScreenRecordingCompositionPreview(
                    session: viewModel.screenOverlayPreviewSession,
                    mode: viewModel.selectedMode,
                    isOverlayEnabled: viewModel.showsScreenOverlayConfiguration,
                    position: viewModel.selectedScreenCameraOverlayPosition,
                    overlaySize: viewModel.selectedScreenCameraOverlaySize
                )
                .accessibilityHidden(true)
            }

            if viewModel.showsScreenOverlayConfiguration {
                Picker("Kamera", selection: $viewModel.selectedCameraID) {
                    if viewModel.cameraPermissionStatus != .authorized {
                        Text("Kamera izni gerekli").tag("")
                    } else if viewModel.cameras.isEmpty {
                        Text("Kamera bulunamadı").tag("")
                    } else {
                        ForEach(viewModel.cameras) { camera in
                            Text(camera.name).tag(camera.id)
                        }
                    }
                }
                .disabled(!viewModel.canChooseCamera)
                .accessibilityLabel("Kamera seçimi")
                .onChange(of: viewModel.selectedCameraID) {
                    viewModel.refreshDeviceState()
                }
            }

            if viewModel.showsScreenSourceSection {
                GroupBox("Kaynak") {
                    VStack(alignment: .leading, spacing: 12) {
                        if viewModel.showsScreenSourcePicker {
                            Picker("Ekran kaynağı", selection: Binding(
                                get: { viewModel.selectedScreenCaptureSource },
                                set: { viewModel.selectScreenCaptureSource($0) }
                            )) {
                                ForEach(ScreenCaptureSource.allCases) { source in
                                    Text(source.label).tag(source)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityLabel(String(localized: "Ekran kaynağı seçimi"))
                        }

                        if viewModel.showsScreenPicker {
                            Picker("Ekran", selection: $viewModel.selectedDisplayID) {
                                if viewModel.availableDisplays.isEmpty {
                                    Text("Ekran bulunamadı").tag("")
                                } else {
                                    ForEach(viewModel.availableDisplays) { display in
                                        Text(display.name).tag(display.id)
                                    }
                                }
                            }
                            .accessibilityLabel(String(localized: "Ekran seçimi"))
                            .onChange(of: viewModel.selectedDisplayID) {
                                Task {
                                    await viewModel.refreshScreenRecordingOptions()
                                }
                            }
                        }

                        if viewModel.showsWindowPicker {
                            Picker("Pencere", selection: $viewModel.selectedWindowID) {
                                if viewModel.availableWindows.isEmpty {
                                    Text("Pencere bulunamadı").tag("")
                                } else {
                                    ForEach(viewModel.availableWindows) { window in
                                        Text(window.name).tag(window.id)
                                    }
                                }
                            }
                            .accessibilityLabel(String(localized: "Pencere seçimi"))
                            .onChange(of: viewModel.selectedWindowID) {
                                Task {
                                    await viewModel.refreshScreenRecordingOptions()
                                }
                            }
                        }
                    }
                }
            }

            if viewModel.showsScreenControls {
                GroupBox("Görüntü") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("İmleci vurgula", isOn: $viewModel.isCursorHighlightEnabled)
                            .accessibilityHint(String(localized: "Kayıt dışa aktarılırken imlecin etrafında yumuşak bir vurgu ve tıklama halkası gösterir."))

                        Toggle("Klavye kısayollarını göster", isOn: $viewModel.isKeyboardShortcutOverlayEnabled)
                            .accessibilityHint(String(localized: "Komut, kontrol ve option gibi anlamlı kısayolları videoda kısa süre gösterir."))
                    }
                }
            }

            GroupBox("Ses") {
                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.showsMicrophonePicker {
                        Picker(microphonePickerTitle, selection: $viewModel.selectedMicrophoneID) {
                            if viewModel.microphonePermissionStatus != .authorized {
                                Text("Mikrofon izni gerekli").tag("")
                            } else if viewModel.microphones.isEmpty {
                                Text("Mikrofon bulunamadı").tag("")
                            } else {
                                if viewModel.showsScreenControls {
                                    Text("Mikrofon kapalı").tag("")
                                }

                                ForEach(viewModel.microphones) { microphone in
                                    Text(microphone.name).tag(microphone.id)
                                }
                            }
                        }
                        .disabled(viewModel.microphonePermissionStatus != .authorized || viewModel.microphones.isEmpty)
                        .accessibilityLabel(microphonePickerTitle)
                        .onChange(of: viewModel.selectedMicrophoneID) {
                            viewModel.applySelectedInputs()
                        }
                    }

                    Toggle("Sistem sesini dahil et", isOn: $viewModel.isSystemAudioEnabled)
                        .accessibilityHint(String(localized: "Mac'te calan uygulama ve sistem seslerini kayda ekler."))

                    if viewModel.showsMicrophoneVolumeControl {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Mikrofon seviyesi: \(Int(viewModel.microphoneVolume * 100))%")
                            Slider(value: $viewModel.microphoneVolume, in: 0...1.5)
                                .accessibilityLabel(String(localized: "Mikrofon seviyesi"))
                                .accessibilityValue(String(localized: "\(Int(viewModel.microphoneVolume * 100)) yüzde"))
                        }
                    }

                    if viewModel.showsSystemAudioVolumeControl {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sistem sesi seviyesi: \(Int(viewModel.systemAudioVolume * 100))%")
                            Slider(value: $viewModel.systemAudioVolume, in: 0...1.5)
                                .accessibilityLabel(String(localized: "Sistem sesi seviyesi"))
                                .accessibilityValue(String(localized: "\(Int(viewModel.systemAudioVolume * 100)) yüzde"))
                        }
                    }
                }
            }

            if viewModel.showsScreenOverlayControls {
                GroupBox("Kamera Kutusu") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(
                            "Kamera kutusunu göster",
                            isOn: Binding(
                                get: { viewModel.isScreenCameraOverlayEnabled },
                                set: { _ in viewModel.toggleScreenCameraOverlay() }
                            )
                        )
                        .accessibilityHint(String(localized: "Ekran kaydının üstüne kamera görüntünü ekler."))

                        if viewModel.showsScreenOverlayConfiguration {
                            Picker("Kamera kutusu konumu", selection: $viewModel.selectedScreenCameraOverlayPosition) {
                                ForEach(ScreenCameraOverlayPosition.allCases) { position in
                                    Text(position.label).tag(position)
                                }
                            }
                            .accessibilityLabel(String(localized: "Kamera kutusu konumu"))

                            Picker("Kamera kutusu boyutu", selection: $viewModel.selectedScreenCameraOverlaySize) {
                                ForEach(ScreenCameraOverlaySize.allCases) { size in
                                    Text(size.label).tag(size)
                                }
                            }
                            .accessibilityLabel(String(localized: "Kamera kutusu boyutu"))
                        }
                    }
                }
            }

            Text(viewModel.permissionStatusText)
                .textSelection(.enabled)
                .accessibilityLabel(viewModel.permissionStatusText)

            permissionButtons

            if viewModel.showsFrameCoachControls && viewModel.showsFrameCoachTextOnScreen {
                Text(frameCoachStatusText)
                    .textSelection(.enabled)
                    .accessibilityLabel(frameCoachStatusText)
            }

            if viewModel.showsFrameCoachControls {
                Toggle(
                    "Otomatik yeniden kadrajlama",
                    isOn: Binding(
                        get: { viewModel.isAutoReframeEnabled },
                        set: { _ in viewModel.toggleAutoReframe() }
                    )
                )
                .accessibilityHint(String(localized: "Tek kişilik çekimde görüntüyü yazılımsal olarak daha dengeli kadrajlar."))
            }

            if viewModel.isCountingDown {
                Text("Kayıt \(viewModel.countdownRemaining) saniye sonra başlıyor…")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(String(localized: "Geri sayım: \(viewModel.countdownRemaining) saniye"))
            }

            HStack {
                Button(recordingButtonTitle) {
                    viewModel.toggleRecording()
                }
                .disabled(!viewModel.canStartRecording && !viewModel.isRecording && !viewModel.isCountingDown)
                .accessibilityLabel(recordingButtonTitle)
                .accessibilityHint(String(localized: "\(GlobalHotkeyMonitor.recordingToggleDisplay) son seçili modu başlatır veya durdurur. Ses kaydı için \(GlobalHotkeyMonitor.audioRecordingToggleDisplay) kısayolu uygulamanın içinden ve dışından çalışır."))

                Button(viewModel.pauseResumeButtonTitle) {
                    viewModel.togglePauseResume()
                }
                .disabled(!viewModel.canPauseRecording)
                .accessibilityLabel(viewModel.pauseResumeButtonTitle)
                .accessibilityHint(String(localized: "\(GlobalHotkeyMonitor.pauseResumeToggleDisplay) aktif kaydı duraklatır veya devam ettirir."))
            }

            Text(String(localized: "Durum: \(viewModel.statusText)"))
                .textSelection(.enabled)
                .accessibilityLabel(String(localized: "Durum \(viewModel.statusText)"))

            if let lastSavedURL = viewModel.lastSavedURL {
                Text(String(localized: "Son kayıt: \(lastSavedURL.path)"))
                    .textSelection(.enabled)
                    .accessibilityLabel(String(localized: "Son kayıt dosyası \(lastSavedURL.path)"))
            }

            if let errorText = viewModel.errorText {
                Text(String(localized: "Hata: \(errorText)"))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

        }
        .padding()
        .frame(minWidth: 560, minHeight: 560)
        .task {
            await viewModel.setup()
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isPaywallPresented },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissPaywall()
                    }
                }
            )
        ) {
            AppPaywallSheet(viewModel: viewModel)
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.completedRecording != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissCompletedRecordingSummary()
                    }
                }
            )
        ) {
            if let completedRecording = viewModel.completedRecording {
                CompletedRecordingSheet(
                    completedRecording: completedRecording,
                    onOpen: viewModel.openCompletedRecording,
                    onReveal: viewModel.revealCompletedRecording,
                    onRename: viewModel.renameCompletedRecording(to:),
                    onSaveAs: viewModel.saveCompletedRecordingAs(to:),
                    onClose: viewModel.dismissCompletedRecordingSummary
                )
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            viewModel.refreshDeviceState()
            Task {
                await viewModel.refreshAppAccess()
            }
        }
    }

    @ViewBuilder
    private var permissionButtons: some View {
        let camStatus = viewModel.cameraPermissionStatus
        let micStatus = viewModel.microphonePermissionStatus
        let screenStatus = viewModel.screenRecordingPermissionStatus

        if viewModel.showsCameraControls || viewModel.showsScreenOverlayConfiguration {
            if camStatus == .notDetermined {
                Button("Kamera iznine izin ver") {
                    viewModel.requestCameraPermission()
                }
                .accessibilityHint(String(localized: "Sistem izin penceresini açar. İzin Ver veya Reddet seçin."))
            } else if camStatus == .denied {
                Button("Kamera izni reddedildi — Sistem Ayarları'nı aç") {
                    viewModel.openPrivacySettings(for: .video)
                }
                .accessibilityHint(String(localized: "Kamera izni daha önce reddedildi. Sistem Ayarları Gizlilik ekranını açar."))
            }
        }

        if micStatus == .notDetermined {
            Button("Mikrofon iznine izin ver") {
                viewModel.requestMicrophonePermission()
            }
            .accessibilityHint(String(localized: "Sistem izin penceresini açar. İzin Ver veya Reddet seçin."))
        } else if micStatus == .denied {
            Button("Mikrofon izni reddedildi — Sistem Ayarları'nı aç") {
                viewModel.openPrivacySettings(for: .audio)
            }
            .accessibilityHint(String(localized: "Mikrofon izni daha önce reddedildi. Sistem Ayarları Gizlilik ekranını açar."))
        }

        if (viewModel.showsScreenControls || viewModel.isSystemAudioEnabled) && screenStatus == .denied {
            Button("Ekran kaydı iznini iste") {
                viewModel.requestScreenRecordingPermission()
            }
            .accessibilityHint(String(localized: "macOS ekran kaydı izin akışını başlatmayı dener. Gerekirse uygulamayı kapatıp yeniden açmak gerekir."))

            Button("Ekran Kaydı Ayarları'nı aç") {
                viewModel.openScreenRecordingSettings()
            }
            .accessibilityHint(String(localized: "Sistem Ayarları içinde Ekran Kaydı gizlilik ekranını açar."))
        }
    }

    private var recordingButtonTitle: String {
        if viewModel.isPreparingRecording { return String(localized: "Kayıt hazırlanıyor…") }
        if viewModel.isCountingDown { return String(localized: "İptal Et (\(viewModel.countdownRemaining))") }
        return viewModel.isRecording ? String(localized: "Kaydı Durdur") : String(localized: "Kaydı Başlat")
    }

    private var frameCoachStatusText: String {
        if let instruction = viewModel.currentFrameCoachInstruction {
            return String(localized: "Kadraj koçu: \(instruction)")
        }

        return viewModel.isFrameCoachEnabled ? String(localized: "Kadraj koçu: açık") : String(localized: "Kadraj koçu: kapalı")
    }

    private var microphonePickerTitle: String {
        viewModel.showsScreenControls ? String(localized: "Mikrofon (isteğe bağlı)") : String(localized: "Mikrofon")
    }

}

struct SettingsView: View {
    @Bindable var viewModel: RecorderViewModel

    var body: some View {
        Form {
            Section("Erişim ve Satın Alma") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.accessStatusTitle)
                        .font(.headline)
                    Text(viewModel.accessStatusDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Planları Gör") {
                    viewModel.presentPaywall()
                }

                Button("Satın Alımları Geri Yükle") {
                    Task {
                        await viewModel.restorePurchases()
                    }
                }
                .disabled(viewModel.isRestoringPurchases || viewModel.purchasingPlan != nil)
            }

            Section("Erişilebilirlik ve Yönlendirme") {
                Picker("Yönlendirme sesi", selection: $viewModel.frameCoachSpeechMode) {
                    ForEach(FrameCoachSpeechMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Picker("Geri bildirim sıklığı", selection: $viewModel.frameCoachFeedbackFrequency) {
                    ForEach(FrameCoachFeedbackFrequency.allCases) { frequency in
                        Text(frequency.label).tag(frequency)
                    }
                }

                Picker("Aynı uyarıyı tekrarla", selection: $viewModel.frameCoachRepeatInterval) {
                    ForEach(FrameCoachRepeatInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }

                Toggle("Ekranda yönlendirme metnini göster", isOn: $viewModel.showsFrameCoachTextOnScreen)

                Text(settingsDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Kayıt Ayarları") {
                Picker("Geri sayım süresi", selection: $viewModel.recordingCountdown) {
                    ForEach(RecordingCountdown.allCases) { countdown in
                        Text(countdown.label).tag(countdown)
                    }
                }
                .accessibilityHint(String(localized: "Kayıt başlatıldıktan sonra kaç saniye bekleyeceğini belirler."))

                Picker("Maksimum kayıt süresi", selection: $viewModel.maxRecordingDuration) {
                    ForEach(MaxRecordingDuration.allCases) { duration in
                        Text(duration.label).tag(duration)
                    }
                }
                .accessibilityHint(String(localized: "Bu süre dolunca kayıt otomatik olarak durur."))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Varsayılan kayıt klasörü")
                        .font(.headline)
                    Text(viewModel.recordingOutputDirectoryPath)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Button("Klasör Seç") {
                        viewModel.chooseRecordingOutputDirectory()
                    }
                }
            }

            #if DEBUG
            Section("Tanılama") {
                DisclosureGroup("Otomatik Kadraj Tanılama") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Strateji: \(viewModel.lastAutoReframeStrategy)"))
                        Text(String(localized: "Ana kare sayısı: \(viewModel.lastAutoReframeKeyframeCount)"))
                        Text(String(localized: "Kompozisyon kullanıldı: \(viewModel.lastAutoReframeUsedVideoComposition ? "evet" : "hayır")"))
                        Text(String(localized: "Yedek dışa aktarım: \(viewModel.lastAutoReframeUsedFallbackExport ? "evet" : "hayır")"))
                        Text(
                            String(
                                format: "Aktif crop: x %.2f y %.2f gen %.2f yuk %.2f",
                                viewModel.currentAutoReframeCrop.originX,
                                viewModel.currentAutoReframeCrop.originY,
                                viewModel.currentAutoReframeCrop.width,
                                viewModel.currentAutoReframeCrop.height
                            )
                        )
                        .textSelection(.enabled)
                    }
                    .padding(.top, 6)
                }
            }
            #endif
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 460, minHeight: 380)
    }

    private var settingsDescription: String {
        String(localized: "Otomatik modda VoiceOver açıksa yönlendirmeler erişilebilirlik anonsu olarak iletilir. Sessiz mod, sesi kapatır ama istersen ekrandaki metni bırakır.")
    }
}

private struct CompletedRecordingSheet: View {
    let completedRecording: CompletedRecordingSummary
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onRename: (String) -> Void
    let onSaveAs: (String) -> Void
    let onClose: () -> Void
    @State private var editableName: String

    init(
        completedRecording: CompletedRecordingSummary,
        onOpen: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onRename: @escaping (String) -> Void,
        onSaveAs: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.completedRecording = completedRecording
        self.onOpen = onOpen
        self.onReveal = onReveal
        self.onRename = onRename
        self.onSaveAs = onSaveAs
        self.onClose = onClose
        _editableName = State(initialValue: completedRecording.editableName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Kayıt Tamamlandı")
                .font(.title2.weight(.semibold))

            Text(completedRecording.url.path)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if !completedRecording.warnings.isEmpty {
                Text(completedRecording.warnings.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Dosya adı")
                    .font(.headline)
                TextField(
                    "Dosya adı",
                    text: $editableName
                )
                Button("Yeniden Adlandır") {
                    onRename(editableName)
                }
            }

            HStack {
                Button("Aç") {
                    onOpen()
                }
                Button("Klasörde Göster") {
                    onReveal()
                }
                Button("Farklı Kaydet") {
                    onSaveAs(editableName)
                }
                Spacer()
                Button("Kapat") {
                    onClose()
                }
            }
        }
        .padding(24)
        .frame(minWidth: 520)
    }
}

private struct AppPaywallSheet: View {
    @Bindable var viewModel: RecorderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(String(localized: "14 Günlük Deneme Bitti"))
                .font(.title2.weight(.semibold))

            Text(String(localized: "Kayıt başlatmaya devam etmek için bir plan seç."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let message = viewModel.paywallMessageText {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 12) {
                paywallButton(for: .yearly)
                paywallButton(for: .lifetime)
            }

            HStack {
                Button(String(localized: "Satın Alımları Geri Yükle")) {
                    Task {
                        await viewModel.restorePurchases()
                    }
                }
                .disabled(viewModel.isRestoringPurchases || viewModel.purchasingPlan != nil)

                Spacer()

                Button(String(localized: "Kapat")) {
                    viewModel.dismissPaywall()
                }
            }
        }
        .padding(24)
        .frame(minWidth: 460)
    }

    @ViewBuilder
    private func paywallButton(for plan: AppAccessPlan) -> some View {
        let offer = viewModel.offer(for: plan)
        let isBusy = viewModel.purchasingPlan == plan

        VStack(alignment: .leading, spacing: 6) {
            Text(offer?.title ?? plan.defaultTitle)
                .font(.headline)

            if let price = offer?.price {
                Text(price)
                    .font(.title3.weight(.medium))
            } else {
                Text(String(localized: "App Store fiyatı hazır olduğunda burada görünecek"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(offer?.description ?? plan.defaultDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(isBusy ? String(localized: "İşleniyor…") : String(localized: "Seç")) {
                Task {
                    await viewModel.purchaseAccess(plan: plan)
                }
            }
            .disabled(!(offer?.isAvailableForPurchase ?? false) || viewModel.purchasingPlan != nil || viewModel.isRestoringPurchases)
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
