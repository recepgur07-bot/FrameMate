import SwiftUI
import AppKit

extension Notification.Name {
    static let openQuickHelpRequested = Notification.Name("openQuickHelpRequested")
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openSettings) private var openSettings
    @Bindable var viewModel: RecorderViewModel

    @State private var toastQueue = ToastQueue()
    @State private var isQuickHelpPresented = false

    var body: some View { makeBody() }

    @ViewBuilder
    private func makeBody() -> some View {
        VStack(spacing: 0) {
            // ── HEADER ZONE ──────────────────────────────────────────────
            headerZone
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)

            // ── TOAST ZONE ───────────────────────────────────────────────
            // Header'ın hemen altında, mod seçicinin üstünde — hiçbir şeyi kapatmaz.
            if !toastQueue.messages.isEmpty {
                FMToastOverlay(queue: toastQueue)
                    .padding(.bottom, 4)
            }

            Divider()

            // ── MODE ZONE ────────────────────────────────────────────────
            FMModeSelector(
                selectedPreset: viewModel.selectedPreset,
                isOverlayEnabled: viewModel.isScreenCameraOverlayEnabled,
                onPresetSelected: { viewModel.selectPreset($0) },
                onEnableOverlay: {
                    if !viewModel.isScreenCameraOverlayEnabled {
                        viewModel.setScreenCameraOverlayEnabled(true)
                    }
                }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // ── CONTENT ZONE ───────────────────────────────────────────────
            ScrollView {
                VStack(spacing: 12) {
                    previewCard
                    setupFlowCard
                    if shouldShowPermissionHub {
                        permissionHubCard
                    }
                }
                .padding(16)
            }

            Divider()

            // ── ACTION ZONE ───────────────────────────────────────────────
            actionZone
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .background(Color.fmSurface)
        .frame(minWidth: 620, minHeight: 640)
        .task {
            await viewModel.setup()
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isPaywallPresented },
                set: { isPresented in
                    if !isPresented { viewModel.dismissPaywall() }
                }
            )
        ) {
            AppPaywallSheet(viewModel: viewModel)
        }
        .sheet(
            item: Binding(
                get: { viewModel.completedRecording },
                set: { if $0 == nil { viewModel.dismissCompletedRecordingSummary() } }
            )
        ) { completedRecording in
            CompletedRecordingSheet(
                completedRecording: completedRecording,
                onOpen: viewModel.openCompletedRecording,
                onReveal: viewModel.revealCompletedRecording,
                onRename: viewModel.renameCompletedRecording(to:),
                onSaveAs: viewModel.saveCompletedRecordingAs(to:),
                onClose: viewModel.dismissCompletedRecordingSummary
            )
        }
        .sheet(isPresented: $isQuickHelpPresented) {
            QuickHelpSheet()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            viewModel.refreshDeviceState()
            Task { await viewModel.refreshAppAccess() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openQuickHelpRequested)) { _ in
            isQuickHelpPresented = true
        }
        // VoiceOver announcements — proactively read state changes aloud so the user
        // doesn't have to navigate to the status elements to hear what happened.
        .onChange(of: currentStatus) { oldStatus, newStatus in
            let message: String
            switch (oldStatus, newStatus) {
            case (.paused, .recording): message = String(localized: "Kayıt devam ediyor")
            case (_, .recording):       message = String(localized: "Kayıt başladı")
            case (_, .paused):          message = String(localized: "Kayıt duraklatıldı")
            case (_, .preparing):       message = String(localized: "Kayıt hazırlanıyor")
            case (_, .ready):           message = String(localized: "Kayıt durduruldu")
            }
            NSAccessibility.post(
                element: NSApp.mainWindow as Any,
                notification: .announcementRequested,
                userInfo: [
                    NSAccessibility.NotificationUserInfoKey.announcement: message,
                    NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
                ]
            )
            // Toast: show for meaningful state transitions
            switch (oldStatus, newStatus) {
            case (.paused, .recording):
                toastQueue.post(message: String(localized: "Kayıt devam ediyor"), style: .success)
            case (_, .recording):
                toastQueue.post(message: String(localized: "Kayıt başladı"), style: .success)
            case (.recording, .ready):
                toastQueue.post(message: String(localized: "Kayıt durduruldu"), style: .info)
            case (_, .paused):
                toastQueue.post(message: String(localized: "Kayıt duraklatıldı"), style: .info)
            default:
                break
            }
        }
        .onChange(of: viewModel.completedRecording) { _, newRecording in
            guard let recording = newRecording else { return }
            let durationText: String
            if let secs = viewModel.lastCompletedRecordingDuration, secs > 0 {
                let m = Int(secs) / 60
                let s = Int(secs) % 60
                durationText = m > 0
                    ? String(localized: ", \(m) dakika \(s) saniye")
                    : String(localized: ", \(s) saniye")
            } else {
                durationText = ""
            }
            let announcement = String(localized: "Kayıt tamamlandı: \(recording.url.lastPathComponent)\(durationText)")
            NSAccessibility.post(
                element: NSApp.mainWindow as Any,
                notification: .announcementRequested,
                userInfo: [
                    NSAccessibility.NotificationUserInfoKey.announcement: announcement,
                    NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
                ]
            )
            toastQueue.post(
                message: String(localized: "Kayıt tamamlandı: \(recording.url.lastPathComponent)"),
                style: .success
            )
        }
        .onChange(of: viewModel.errorText) { _, newError in
            guard let error = newError else { return }
            NSAccessibility.post(
                element: NSApp.mainWindow as Any,
                notification: .announcementRequested,
                userInfo: [
                    NSAccessibility.NotificationUserInfoKey.announcement:
                        String(localized: "Hata: \(error)"),
                    NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
                ]
            )
            toastQueue.post(message: String(localized: "Hata: \(error)"), style: .error)
        }
        // VoiceOver: Announce mode changes so the user knows which cards are now active.
        .onChange(of: viewModel.selectedPreset) { _, newPreset in
            NSAccessibility.post(
                element: NSApp.mainWindow as Any,
                notification: .announcementRequested,
                userInfo: [
                    NSAccessibility.NotificationUserInfoKey.announcement:
                        String(localized: "Mod seçildi: \(newPreset.label)"),
                    NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.medium.rawValue
                ]
            )
        }
        // Toast: microphone permission changes
        .onChange(of: viewModel.microphonePermissionStatus) { _, newStatus in
            switch newStatus {
            case .authorized:
                toastQueue.post(message: String(localized: "Mikrofon izni verildi"), style: .success)
            case .denied, .restricted:
                toastQueue.post(message: String(localized: "Mikrofon izni reddedildi — Sistem Ayarları'ndan etkinleştirebilirsin"), style: .error)
            default:
                break
            }
        }
        // Toast: camera permission changes
        .onChange(of: viewModel.cameraPermissionStatus) { _, newStatus in
            switch newStatus {
            case .authorized:
                toastQueue.post(message: String(localized: "Kamera izni verildi"), style: .success)
            case .denied, .restricted:
                toastQueue.post(message: String(localized: "Kamera izni reddedildi — Sistem Ayarları'ndan etkinleştirebilirsin"), style: .error)
            default:
                break
            }
        }
        // VoiceOver: step-by-step guide when screen recording permission is denied
        .onChange(of: viewModel.screenRecordingPermissionStatus) { _, _ in
            if let guide = viewModel.screenRecordingPermissionGuide {
                NSAccessibility.post(
                    element: NSApp.mainWindow as Any,
                    notification: .announcementRequested,
                    userInfo: [
                        NSAccessibility.NotificationUserInfoKey.announcement: guide,
                        NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
                    ]
                )
            }
        }
        // Toast: screen recording permission — always needs restart after grant
        .onChange(of: viewModel.screenPermissionNeedsRestart) { _, needsRestart in
            guard needsRestart else { return }
            toastQueue.post(
                message: String(localized: "Ekran kaydı izni verildi — değişikliğin geçerli olması için uygulamayı yeniden başlat"),
                style: .warning
            )
        }
    }

    // MARK: - Header Zone

    private var headerZone: some View {
        HStack(alignment: .center) {
            Image(systemName: "record.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.fmAccent)
                .accessibilityHidden(true)

            Text("FrameMate")
                .font(.title2.bold())
                .foregroundStyle(Color.fmAccent)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            if viewModel.isRecording {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let duration = viewModel.currentRecordingDuration ?? 0
                    let mins = Int(duration) / 60
                    let secs = Int(duration) % 60
                    Text(String(format: "%02d:%02d", mins, secs))
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(viewModel.isPaused ? Color.secondary : Color.fmAccent)
                        .accessibilityLabel(String(localized: "Geçen süre \(mins) dakika \(secs) saniye"))
                }
                .padding(.trailing, 8)
            }

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(String(localized: "Ayarlar"))
            .accessibilityLabel(String(localized: "Ayarlar"))
            .accessibilityHint(String(localized: "Uygulama ayarlarını açar."))

            StatusPill(status: currentStatus)
        }
    }

    private var currentStatus: RecordingStatus {
        if viewModel.isPreparingRecording || viewModel.isCountingDown { return .preparing }
        if viewModel.isRecording && viewModel.isPaused { return .paused }
        if viewModel.isRecording { return .recording }
        return .ready
    }

    // MARK: - Preview Card

    @ViewBuilder
    private var previewCard: some View {
        if viewModel.showsCameraControls {
            VStack(spacing: 0) {
                VideoPreviewView(
                    session: viewModel.previewSession,
                    crop: viewModel.currentAutoReframeCrop
                )
                .aspectRatio(cameraPreviewAspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )

                HStack {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Önizleme — kayıt \(viewModel.selectedMode.width)×\(viewModel.selectedMode.height) çözünürlükte yapılır"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .accessibilityHidden(true)
        } else if viewModel.showsScreenControls {
            VStack(spacing: 0) {
                ScreenRecordingCompositionPreview(
                    session: viewModel.screenOverlayPreviewSession,
                    mode: viewModel.selectedMode,
                    isOverlayEnabled: viewModel.showsScreenOverlayConfiguration,
                    position: viewModel.selectedScreenCameraOverlayPosition,
                    overlaySize: viewModel.selectedScreenCameraOverlaySize
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )

            }
            .accessibilityHidden(true)
        }
    }

    private var cameraPreviewAspectRatio: CGFloat {
        CGFloat(viewModel.selectedMode.renderSize.width) / CGFloat(viewModel.selectedMode.renderSize.height)
    }

    private var shouldShowPermissionHub: Bool {
        viewModel.hasBlockingPermissionIssue || viewModel.permissionHubItems.contains(where: { $0.primaryAction != .none })
    }

    // MARK: - Camera Card (camera-only mode)

    private var setupFlowCard: some View {
        FMCard(icon: "slider.horizontal.3", title: String(localized: "Kayıt akışı")) {
            VStack(alignment: .leading, spacing: 18) {
                setupSummaryPanel

                if viewModel.showsCameraControls {
                    flowSection(title: String(localized: "Kamera")) {
                        flowPickerRow(
                            title: String(localized: "Kamera seçimi"),
                            hint: viewModel.cameraPermissionStatus == .authorized
                                ? String(localized: "Hangi kamerayla kayıt yapılacağını seçer. Mac kamerası için bilgisayarın önüne geç; iPhone kamerası için Süreklilik Kamerası'nı kullan.")
                                : String(localized: "Önce üstteki izinler bölümünden kamera iznini tamamla.")
                        ) {
                            Picker(String(localized: "Kamera seçimi"), selection: $viewModel.selectedCameraID) {
                                if viewModel.cameras.isEmpty {
                                    Text(String(localized: "Kamera bulunamadı")).tag("")
                                } else {
                                    ForEach(viewModel.cameras) { camera in
                                        Text(camera.name).tag(camera.id)
                                    }
                                }
                            }
                            .labelsHidden()
                            .disabled(!viewModel.canChooseCamera || viewModel.cameras.isEmpty)
                            .onChange(of: viewModel.selectedCameraID) {
                                viewModel.refreshDeviceState()
                            }
                        }
                    }
                }

                if viewModel.showsScreenControls || viewModel.showsScreenOverlayControls {
                    flowSection(title: String(localized: "Ekran")) {
                        if viewModel.showsScreenSourcePicker {
                            flowPickerRow(
                                title: String(localized: "Kayıt türü"),
                                hint: String(localized: "Tam ekran mı pencere mi kaydedileceğini seçer.")
                            ) {
                                Picker(
                                    String(localized: "Kayıt türü"),
                                    selection: Binding(
                                        get: { viewModel.selectedScreenCaptureSource },
                                        set: { viewModel.selectScreenCaptureSource($0) }
                                    )
                                ) {
                                    ForEach(ScreenCaptureSource.allCases) { source in
                                        Text(source.label).tag(source)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                        }

                        if viewModel.showsScreenPicker {
                            flowPickerRow(
                                title: String(localized: "Ekran seçimi"),
                                hint: String(localized: "Kayda alınacak ekranı seçer.")
                            ) {
                                Picker(String(localized: "Ekran seçimi"), selection: $viewModel.selectedDisplayID) {
                                    if viewModel.availableDisplays.isEmpty {
                                        Text(String(localized: "Ekran bulunamadı")).tag("")
                                    } else {
                                        ForEach(viewModel.availableDisplays) { display in
                                            Text(display.localizedName).tag(display.id)
                                        }
                                    }
                                }
                                .labelsHidden()
                                .onChange(of: viewModel.selectedDisplayID) {
                                    Task { await viewModel.refreshScreenRecordingOptions() }
                                }
                            }
                        }

                        if viewModel.showsWindowPicker {
                            flowPickerRow(
                                title: String(localized: "Pencere seçimi"),
                                hint: String(localized: "Kayda alınacak pencereyi seçer.")
                            ) {
                                Picker(String(localized: "Pencere seçimi"), selection: $viewModel.selectedWindowID) {
                                    if viewModel.availableWindows.isEmpty {
                                        Text(String(localized: "Pencere bulunamadı")).tag("")
                                    } else {
                                        ForEach(viewModel.availableWindows) { window in
                                            Text(window.name).tag(window.id)
                                        }
                                    }
                                }
                                .labelsHidden()
                                .onChange(of: viewModel.selectedWindowID) {
                                    Task { await viewModel.refreshScreenRecordingOptions() }
                                }
                            }
                        }
                    }
                }

                flowSection(title: String(localized: "Ses")) {
                    if viewModel.showsMicrophonePicker {
                        flowPickerRow(
                            title: microphonePickerTitle,
                            hint: String(localized: "Mikrofon girişini seçer.")
                        ) {
                            Picker(microphonePickerTitle, selection: $viewModel.selectedMicrophoneID) {
                                if viewModel.microphonePermissionStatus != .authorized {
                                    Text(String(localized: "Mikrofon izni gerekli")).tag("")
                                } else if viewModel.microphones.isEmpty {
                                    Text(String(localized: "Mikrofon bulunamadı")).tag("")
                                } else {
                                    if viewModel.showsScreenControls {
                                        Text(String(localized: "Mikrofon kapalı")).tag("")
                                    }
                                    ForEach(viewModel.microphones) { microphone in
                                        Text(microphone.localizedName).tag(microphone.id)
                                    }
                                }
                            }
                            .labelsHidden()
                            .disabled(viewModel.microphonePermissionStatus != .authorized || viewModel.microphones.isEmpty)
                            .onChange(of: viewModel.selectedMicrophoneID) {
                                viewModel.applySelectedInputs()
                            }
                        }
                    }

                    flowToggleRow(
                        title: String(localized: "Sistem sesini kaydet"),
                        detail: String(localized: "Mac'te çalan müzik, video veya uygulama seslerini videoya ekler. Sadece senin sesin yeterliyse kapalı bırak."),
                        isOn: $viewModel.isSystemAudioEnabled
                    )

                    if viewModel.showsMicrophoneVolumeControl {
                        flowSliderRow(
                            title: String(localized: "Mikrofon seviyesi"),
                            valueText: String(localized: "\(Int(viewModel.microphoneVolume * 100))%"),
                            value: Binding(
                                get: { Double(viewModel.microphoneVolume) },
                                set: { viewModel.microphoneVolume = Float($0) }
                            )
                        )
                    }

                    if viewModel.showsSystemAudioVolumeControl {
                        flowSliderRow(
                            title: String(localized: "Sistem sesi seviyesi"),
                            valueText: String(localized: "\(Int(viewModel.systemAudioVolume * 100))%"),
                            value: Binding(
                                get: { Double(viewModel.systemAudioVolume) },
                                set: { viewModel.systemAudioVolume = Float($0) }
                            )
                        )
                    }
                }

                if viewModel.showsFrameCoachControls {
                    flowSection(title: String(localized: "Kadraj")) {
                        flowToggleRow(
                            title: String(localized: "Otomatik yeniden kadrajlama"),
                            detail: String(localized: "Kayıt sırasında yüzünü çerçevede tutar; yana döndüğünde kamera seni takip eder. Tek kişilik kamera çekimlerinde çalışır."),
                            isOn: Binding(
                                get: { viewModel.isAutoReframeEnabled },
                                set: { _ in viewModel.toggleAutoReframe() }
                            )
                        )

                        if viewModel.showsFrameCoachTextOnScreen {
                            HStack(spacing: 8) {
                                Image(systemName: "figure.stand")
                                    .foregroundStyle(Color.fmAccent)
                                    .accessibilityHidden(true)
                                Text(frameCoachStatusText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if viewModel.showsScreenControls {
                    flowSection(title: String(localized: "Görüntü")) {
                        flowToggleRow(
                            title: String(localized: "İmleci vurgula"),
                            detail: String(localized: "Kayıtta imlecin etrafında vurgu ve tıklama halkası gösterir."),
                            isOn: $viewModel.isCursorHighlightEnabled
                        )

                    }
                }

                if viewModel.showsScreenOverlayControls {
                    flowSection(title: String(localized: "Kamera kutusu — ekranda kendinizi gösterin")) {
                        flowToggleRow(
                            title: String(localized: "Kamera kutusunu göster"),
                            detail: String(localized: "Ekran kaydının üstüne kendi görüntünü ekler. Aşağıdan kamerayı, konumu ve boyutu seçebilirsin."),
                            isOn: Binding(
                                get: { viewModel.isScreenCameraOverlayEnabled },
                                set: { viewModel.setScreenCameraOverlayEnabled($0) }
                            )
                        )

                        if viewModel.showsScreenOverlayConfiguration {
                            flowPickerRow(
                                title: String(localized: "Kamera"),
                                hint: String(localized: "Kamera kutusunda görünecek kamerayı seçer. Mac kamerası için bilgisayarın önüne geç; iPhone kamerası için Süreklilik Kamerası'nı kullan.")
                            ) {
                                Picker(String(localized: "Kamera"), selection: $viewModel.selectedCameraID) {
                                    if viewModel.cameraPermissionStatus != .authorized {
                                        Text(String(localized: "Kamera izni gerekli")).tag("")
                                    } else if viewModel.cameras.isEmpty {
                                        Text(String(localized: "Kamera bulunamadı")).tag("")
                                    } else {
                                        ForEach(viewModel.cameras) { camera in
                                            Text(camera.name).tag(camera.id)
                                        }
                                    }
                                }
                                .labelsHidden()
                                .disabled(!viewModel.canChooseCamera)
                                .onChange(of: viewModel.selectedCameraID) {
                                    viewModel.refreshDeviceState()
                                }
                            }

                            flowPickerRow(
                                title: String(localized: "Kamera konumu"),
                                hint: String(localized: "Kamera kutusunun ekrandaki yerini seçer.")
                            ) {
                                Picker(String(localized: "Kamera konumu"), selection: $viewModel.selectedScreenCameraOverlayPosition) {
                                    ForEach(ScreenCameraOverlayPosition.allCases) { position in
                                        Text(position.label).tag(position)
                                    }
                                }
                                .labelsHidden()
                            }

                            flowPickerRow(
                                title: String(localized: "Kamera boyutu"),
                                hint: String(localized: "Kamera kutusunun boyutunu seçer.")
                            ) {
                                Picker(String(localized: "Kamera boyutu"), selection: $viewModel.selectedScreenCameraOverlaySize) {
                                    ForEach(ScreenCameraOverlaySize.allCases) { size in
                                        Text(size.label).tag(size)
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }
            }
        }
    }

    private var setupSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Seçili ayarlar"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.fmAccent)
                .accessibilityHidden(true)

            Text(viewModel.accessibilitySetupSummary)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let permissionSummary = viewModel.accessibilityPermissionSummary, shouldShowPermissionHub {
                Text(permissionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.fmAccent.opacity(0.14),
                            Color.fmAccent.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.fmAccent.opacity(0.14), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Kayıt ayarları özeti"))
        .accessibilityValue(viewModel.accessibilitySetupSummary)
        .accessibilityHint(
            shouldShowPermissionHub && viewModel.accessibilityPermissionSummary != nil
                ? String(localized: "Eksik izinler aşağıda ayrı olarak yönetilebilir.")
                : String(localized: "Aşağıdaki alanlarla bu ayarları değiştirebilirsin.")
        )
    }

    private func flowSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func flowPickerRow<Content: View>(title: String, hint: String, @ViewBuilder control: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .accessibilityHidden(true)
            control()
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fmSurface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func flowToggleRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: isOn) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityHint(detail)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fmSurface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func flowSliderRow(title: String, valueText: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
                Spacer()
                Text(valueText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.fmAccent)
                    .accessibilityHidden(true)
            }

            Slider(value: value, in: 0...1.5)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
                .accessibilityHint(String(localized: "Aralık: %0 ile %150. Sol/sağ ok tuşlarıyla ayarla."))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fmSurface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Shown only in pure Camera mode so the user can pick which camera to use.
    /// In Screen+Camera mode the camera picker lives inside cameraBoxCard.
    private var cameraCard: some View {
        FMCard(icon: "camera.fill", title: String(localized: "Kamera")) {
            if viewModel.cameraPermissionStatus == .authorized {
                // Permission granted — show camera picker
                Picker(String(localized: "Kamera"), selection: $viewModel.selectedCameraID) {
                    if viewModel.cameras.isEmpty {
                        Text(String(localized: "Kamera bulunamadı")).tag("")
                    } else {
                        ForEach(viewModel.cameras) { camera in
                            Text(camera.name).tag(camera.id)
                        }
                    }
                }
                .disabled(!viewModel.canChooseCamera || viewModel.cameras.isEmpty)
                .accessibilityLabel(String(localized: "Kamera seçimi"))
                .onChange(of: viewModel.selectedCameraID) {
                    viewModel.refreshDeviceState()
                }
            } else {
                Text(String(localized: "Kamera seçimi Permission Hub içinden tamamlanır."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Audio Card

    private var audioCard: some View {
        FMCard(icon: "mic.fill", title: String(localized: "Ses"), isCollapsible: true) {
            // Camera permission banner (top of Ses card):
            // In camera-only mode cameraCard already shows this — only show here
            // for Screen+Camera overlay configuration.
            // Frame coach row
            if viewModel.showsFrameCoachControls && viewModel.showsFrameCoachTextOnScreen {
                HStack(spacing: 8) {
                    Image(systemName: "figure.stand")
                        .foregroundStyle(Color.fmAccent)
                        .accessibilityHidden(true)
                    Text(frameCoachStatusText)
                        .textSelection(.enabled)
                        .accessibilityLabel(frameCoachStatusText)
                }
            }

            // Microphone picker
            if viewModel.showsMicrophonePicker {
                Picker(microphonePickerTitle, selection: $viewModel.selectedMicrophoneID) {
                    if viewModel.microphonePermissionStatus != .authorized {
                        Text(String(localized: "Mikrofon izni gerekli")).tag("")
                    } else if viewModel.microphones.isEmpty {
                        Text(String(localized: "Mikrofon bulunamadı")).tag("")
                    } else {
                        if viewModel.showsScreenControls {
                            Text(String(localized: "Mikrofon kapalı")).tag("")
                        }
                        ForEach(viewModel.microphones) { microphone in
                            Text(microphone.localizedName).tag(microphone.id)
                        }
                    }
                }
                .disabled(viewModel.microphonePermissionStatus != .authorized || viewModel.microphones.isEmpty)
                .accessibilityLabel(microphonePickerTitle)
                .onChange(of: viewModel.selectedMicrophoneID) {
                    viewModel.applySelectedInputs()
                }
            }

            // System audio toggle
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Toggle(String(localized: "Sistem sesini dahil et"), isOn: $viewModel.isSystemAudioEnabled)
                    .accessibilityHint(String(localized: "Mac'te çalan uygulama ve sistem seslerini kayda ekler."))
            }

            // Screen recording permission banner (system audio capture requires screen recording).
            // Only shown here in audio-only mode — screen modes already surface this via sourceCard.
            // Microphone volume
            if viewModel.showsMicrophoneVolumeControl {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Mikrofon seviyesi: \(Int(viewModel.microphoneVolume * 100))%"))
                    Slider(value: $viewModel.microphoneVolume, in: 0...1.5)
                        .accessibilityLabel(String(localized: "Mikrofon seviyesi"))
                        .accessibilityValue(String(localized: "\(Int(viewModel.microphoneVolume * 100)) yüzde"))
                }
            }

            // System audio volume
            if viewModel.showsSystemAudioVolumeControl {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Sistem sesi seviyesi: \(Int(viewModel.systemAudioVolume * 100))%"))
                    Slider(value: $viewModel.systemAudioVolume, in: 0...1.5)
                        .accessibilityLabel(String(localized: "Sistem sesi seviyesi"))
                        .accessibilityValue(String(localized: "\(Int(viewModel.systemAudioVolume * 100)) yüzde"))
                }
            }

            // Auto-reframe toggle
            if viewModel.showsFrameCoachControls {
                HStack(spacing: 8) {
                    Image(systemName: "viewfinder")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Toggle(
                        String(localized: "Otomatik yeniden kadrajlama"),
                        isOn: Binding(
                            get: { viewModel.isAutoReframeEnabled },
                            set: { _ in viewModel.toggleAutoReframe() }
                        )
                    )
                    .accessibilityHint(String(localized: "Tek kişilik çekimde görüntüyü yazılımsal olarak daha dengeli kadrajlar."))
                }
            }
        }
    }

    // MARK: - Source Card

    private var sourceCard: some View {
        // showsScreenSourcePicker — inner guard for the segmented source picker widget
        // showsScreenControls / showsScreenOverlayControls — outer visibility (card shown)
        FMCard(icon: "desktopcomputer", title: String(localized: "Kaynak"), isCollapsible: true) {
            if viewModel.showsScreenSourcePicker {
                Picker(String(localized: "Ekran kaynağı"), selection: Binding(
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
                Picker(String(localized: "Ekran"), selection: $viewModel.selectedDisplayID) {
                    if viewModel.availableDisplays.isEmpty {
                        Text(String(localized: "Ekran bulunamadı")).tag("")
                    } else {
                        ForEach(viewModel.availableDisplays) { display in
                            Text(display.localizedName).tag(display.id)
                        }
                    }
                }
                .accessibilityLabel(String(localized: "Ekran seçimi"))
                .onChange(of: viewModel.selectedDisplayID) {
                    Task { await viewModel.refreshScreenRecordingOptions() }
                }
            }

            if viewModel.showsWindowPicker {
                Picker(String(localized: "Pencere"), selection: $viewModel.selectedWindowID) {
                    if viewModel.availableWindows.isEmpty {
                        Text(String(localized: "Pencere bulunamadı")).tag("")
                    } else {
                        ForEach(viewModel.availableWindows) { window in
                            Text(window.name).tag(window.id)
                        }
                    }
                }
                .accessibilityLabel(String(localized: "Pencere seçimi"))
                .onChange(of: viewModel.selectedWindowID) {
                    Task { await viewModel.refreshScreenRecordingOptions() }
                }
            }
        }
    }

    // MARK: - Visual Card

    private var visualCard: some View {
        FMCard(icon: "eye.fill", title: String(localized: "Görüntü"), isCollapsible: true) {
            HStack(spacing: 8) {
                Image(systemName: "cursorarrow.rays")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Toggle(String(localized: "İmleci vurgula"), isOn: $viewModel.isCursorHighlightEnabled)
                    .accessibilityHint(String(localized: "Kayıt dışa aktarılırken imlecin etrafında yumuşak bir vurgu ve tıklama halkası gösterir."))
            }

            }
        }

    // MARK: - Camera Box Card

    private var cameraBoxCard: some View {
        FMCard(icon: "rectangle.inset.filled.on.rectangle", title: String(localized: "Kamera Kutusu"), isCollapsible: true) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.inset.filled.on.rectangle")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Toggle(
                    String(localized: "Kamera kutusunu göster"),
                    isOn: Binding(
                        get: { viewModel.isScreenCameraOverlayEnabled },
                        set: { viewModel.setScreenCameraOverlayEnabled($0) }
                    )
                )
                .accessibilityHint(String(localized: "Ekran kaydının üstüne kamera görüntünü ekler."))
            }

            if viewModel.showsScreenOverlayConfiguration {
                // Camera picker for overlay
                Picker(String(localized: "Kamera"), selection: $viewModel.selectedCameraID) {
                    if viewModel.cameraPermissionStatus != .authorized {
                        Text(String(localized: "Kamera izni gerekli")).tag("")
                    } else if viewModel.cameras.isEmpty {
                        Text(String(localized: "Kamera bulunamadı")).tag("")
                    } else {
                        ForEach(viewModel.cameras) { camera in
                            Text(camera.name).tag(camera.id)
                        }
                    }
                }
                .disabled(!viewModel.canChooseCamera)
                .accessibilityLabel(String(localized: "Kamera seçimi"))
                .onChange(of: viewModel.selectedCameraID) {
                    viewModel.refreshDeviceState()
                }

                Picker(String(localized: "Kamera kutusu konumu"), selection: $viewModel.selectedScreenCameraOverlayPosition) {
                    ForEach(ScreenCameraOverlayPosition.allCases) { position in
                        Text(position.label).tag(position)
                    }
                }
                .accessibilityLabel(String(localized: "Kamera kutusu konumu"))

                Picker(String(localized: "Kamera kutusu boyutu"), selection: $viewModel.selectedScreenCameraOverlaySize) {
                    ForEach(ScreenCameraOverlaySize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .accessibilityLabel(String(localized: "Kamera kutusu boyutu"))
            }
        }
    }

    // MARK: - Permission Banners

    private var permissionHubCard: some View {
        FMCard(icon: "hand.raised.fill", title: String(localized: "İzinler")) {
            if viewModel.hasBlockingPermissionIssue || viewModel.permissionHubItems.contains(where: { $0.primaryAction != .none }) {
                VStack(spacing: 10) {
                    ForEach(viewModel.permissionHubItems) { item in
                        permissionRow(item)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text(String(localized: "Gerekli izinler hazır."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private func permissionRow(_ item: PermissionHubItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.symbolName)
                .foregroundStyle(Color.fmAccent)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                    if !item.isRequired {
                        Text(String(localized: "Opsiyonel"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.statusLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(item.isSatisfied ? .green : .orange)
            }

            Spacer()

            HStack(spacing: 6) {
                if let secondaryTitle = item.secondaryAction?.buttonTitle {
                    Button(secondaryTitle) {
                        viewModel.performSecondaryPermissionAction(for: item.id)
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }

                if let primaryTitle = item.primaryAction.buttonTitle {
                    Button(primaryTitle) {
                        viewModel.performPrimaryPermissionAction(for: item.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.fmAccent)
                    .font(.caption)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(item.isSatisfied ? Color.green.opacity(0.06) : Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func permissionBanner(
        message: String,
        buttonTitle: String,
        buttonHint: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Button(buttonTitle, action: action)
                .font(.caption)
                .accessibilityHint(buttonHint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Action Zone

    private var actionZone: some View {
        VStack(spacing: 10) {
            // Error banner
            if let errorText = viewModel.errorText {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Record + Pause buttons
            HStack(spacing: 16) {
                Spacer()

                // Pause button — only when recording
                if viewModel.isRecording {
                    Button {
                        viewModel.togglePauseResume()
                    } label: {
                        Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 18))
                            .frame(width: 44, height: 44)
                            .background(Color.fmCardBg)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canPauseRecording)
                    .accessibilityLabel(viewModel.pauseResumeButtonTitle)
                    .accessibilityHint(String(localized: "\(GlobalHotkeyMonitor.pauseResumeToggleDisplay) aktif kaydı duraklatır veya devam ettirir."))
                }

                RecordButton(
                    state: recordButtonState,
                    countdownRemaining: viewModel.countdownRemaining,
                    accessibilityLabel: recordingButtonTitle,
                    action: { viewModel.toggleRecording() }
                )
                .disabled(!viewModel.canStartRecording && !viewModel.isRecording && !viewModel.isCountingDown)

                Spacer()
            }

            // Status row — hata detayı toast'ta gösterildiği için burada kısa tutulur
            HStack {
                Text(String(format: String(localized: "Durum: %@"), viewModel.errorText != nil ? String(localized: "Hata oluştu") : viewModel.statusText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
                    .accessibilityLabel(String(format: String(localized: "Durum %@"), viewModel.statusText))

                Spacer()

                if let lastSavedURL = viewModel.lastSavedURL {
                    Text(lastSavedURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .accessibilityLabel(String(localized: "Son kayıt dosyası \(lastSavedURL.path)"))
                }
            }
        }
    }

    // MARK: - Helpers

    private var recordButtonState: RecordButtonState {
        if viewModel.isPreparingRecording { return .preparing }
        if viewModel.isCountingDown       { return .countdown }
        if viewModel.isRecording && viewModel.isPaused { return .paused }
        if viewModel.isRecording          { return .recording }
        return .ready
    }

    /// Mirrors the original ContentView logic exactly — passed into RecordButton
    /// so the accessibility label stays in sync with the visual state.
    private var recordingButtonTitle: String {
        if viewModel.isPreparingRecording { return String(localized: "Kayıt hazırlanıyor…") }
        if viewModel.isCountingDown { return String(localized: "İptal Et (\(viewModel.countdownRemaining))") }
        return viewModel.isRecording ? String(localized: "Kaydı Durdur") : String(localized: "Kaydı Başlat")
    }

    private var frameCoachStatusText: String {
        if let instruction = viewModel.currentFrameCoachInstruction {
            return String(localized: "Kadraj koçu: \(instruction)")
        }
        return viewModel.isFrameCoachEnabled
            ? String(localized: "Kadraj koçu: açık")
            : String(localized: "Kadraj koçu: kapalı")
    }

    private var microphonePickerTitle: String {
        viewModel.showsScreenControls
            ? String(localized: "Mikrofon (isteğe bağlı)")
            : String(localized: "Mikrofon")
    }
}

struct SettingsView: View {
    @Bindable var viewModel: RecorderViewModel
    @AppStorage(AppBehaviorPreferenceKey.hideWindowOnRecordingStart) private var hideWindowOnRecordingStart = false
    @AppStorage(AppBehaviorPreferenceKey.showWindowWhenRecordingStops) private var showWindowWhenRecordingStops = true
    @AppStorage(AppBehaviorPreferenceKey.activationPolicy) private var activationPolicyPreference = AppActivationPolicyPreference.regular.rawValue
    @AppStorage(AppBehaviorPreferenceKey.launchAtLogin) private var launchAtLogin = false

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
                .accessibilityHint(String(localized: "Kadraj koçunun yönlendirmeyi nasıl ileteceğini seçer. Otomatik modda VoiceOver açıksa erişilebilirlik anonsu, kapalıysa uygulama sesi kullanılır. Sessiz modda ses çıkmaz."))

                Picker("Yön sesi", selection: $viewModel.frameCoachSpatialAudioMode) {
                    ForEach(FrameCoachSpatialAudioMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .accessibilityHint(String(localized: "Yönlendirme sesinin hangi kulaklıktan geleceğini belirler. Uzamsal modda ses, yüzünün bulunduğu tarafa göre sağ veya sol kulaktan gelir. Mono modda ses her zaman ortadan gelir."))

                Toggle("Merkez onayı çal", isOn: $viewModel.playsFrameCoachCenterConfirmation)
                    .disabled(viewModel.frameCoachSpatialAudioMode == .off)
                    .accessibilityHint(String(localized: "Yüzün tam ortaya geldiğinde kısa bir onay sesi çalar. Hangi pozisyonun doğru olduğunu anlamak için kullanışlıdır."))

                Picker("Geri bildirim sıklığı", selection: $viewModel.frameCoachFeedbackFrequency) {
                    ForEach(FrameCoachFeedbackFrequency.allCases) { frequency in
                        Text(frequency.label).tag(frequency)
                    }
                }
                .accessibilityHint(String(localized: "Kadraj koçunun ne sıklıkta yönlendirme vereceğini ayarlar. Sık seçilirse her birkaç saniyede bir uyarı gelir; seyrek seçilirse yalnızca büyük sapmalar bildirilir."))

                Picker("Aynı uyarıyı tekrarla", selection: $viewModel.frameCoachRepeatInterval) {
                    ForEach(FrameCoachRepeatInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .accessibilityHint(String(localized: "Aynı yönlendirme mesajı kaç saniyede bir tekrarlanacağını belirler. Kısa aralıkta daha sık hatırlatma alırsın; uzun aralıkta tek bir uyarıdan sonra bir süre sessizlik olur."))

                Toggle("Ekranda yönlendirme metnini göster", isOn: $viewModel.showsFrameCoachTextOnScreen)
                    .accessibilityHint(String(localized: "Kayıt sırasında yön metinlerini ekranda görünür yapar. Kapalıysa yalnızca ses çıkar, ekranda yazı görünmez."))

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

                Toggle("Komut alındı sesini çal", isOn: $viewModel.isRecordingCommandSoundEnabled)
                    .accessibilityHint(String(localized: "Kayıt başlatma komutu alındığında kısa bir onay sesi çalar."))

                Toggle("Kayıt başladı sesini çal", isOn: $viewModel.isRecordingStartSoundEnabled)
                    .accessibilityHint(String(localized: "Hazırlık veya geri sayım bittikten sonra, kayıt gerçekten başlamadan hemen önce başlangıç sesi çalar."))

                Toggle("Kayıt bitti sesini çal", isOn: $viewModel.isRecordingStopSoundEnabled)
                    .accessibilityHint(String(localized: "Kayıt durduktan sonra bitiş sesi çalar."))

                Toggle("Duraklat ve devam sesini çal", isOn: $viewModel.isRecordingPauseResumeSoundEnabled)
                    .accessibilityHint(String(localized: "Kayıt duraklatıldığında veya devam ettirildiğinde geçiş sesi çalar."))

                Toggle("Kayıt başlarken pencereyi gizle", isOn: $hideWindowOnRecordingStart)
                    .accessibilityHint(String(localized: "Kayıt başladığında uygulama penceresi ekrandan kaybolur, böylece ekran kaydında uygulamanın arayüzü görünmez."))

                Toggle("Kayıt bitince pencereyi geri aç", isOn: $showWindowWhenRecordingStops)
                    .accessibilityHint(String(localized: "Kayıt durduğunda uygulama penceresi otomatik olarak geri gelir. Kapalıysa pencereyi kendin açman gerekir."))

                Picker("Uygulama görünümü", selection: $activationPolicyPreference) {
                    ForEach(AppActivationPolicyPreference.allCases) { policy in
                        Text(policy.label).tag(policy.rawValue)
                    }
                }
                .accessibilityHint(String(localized: "Uygulamanın Dock ve menü çubuğundaki görünümünü belirler. Dock'ta görün seçeneği standart uygulama gibi davranır; yalnızca menü çubuğu seçeneği arka planda çalışır."))

                Toggle("Girişte otomatik başlat", isOn: $launchAtLogin)
                    .accessibilityHint(String(localized: "Mac açıldığında uygulama otomatik olarak başlar. Sık kullanıyorsan zaman kazandırır."))

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

            Section("Yardım ve Gizlilik") {
                Button("Hızlı Yardımı Aç") {
                    NotificationCenter.default.post(name: .openQuickHelpRequested, object: nil)
                }
                .accessibilityHint(String(localized: "Uygulama içindeki hızlı yardım penceresini açar."))

                Link(
                    "Yardım ve Destek",
                    destination: URL(string: "https://recepgur07-bot.github.io/oneday-support/framemate-support")!
                )
                .accessibilityHint(String(localized: "FrameMate destek sayfasını tarayıcıda açar."))

                Link(
                    "Gizlilik Politikası",
                    destination: URL(string: "https://recepgur07-bot.github.io/oneday-support/framemate-privacy")!
                )
                .accessibilityHint(String(localized: "FrameMate gizlilik politikasını tarayıcıda açar."))

                Link(
                    String(localized: "Kullanım Koşulları"),
                    destination: URL(string: "https://www.apple.com/legal/macapps/stdeula/")!
                )
                .accessibilityHint(String(localized: "Apple'ın standart son kullanıcı lisans sözleşmesini açar."))

                Link(
                    "Geliştiriciye E-posta Gönder",
                    destination: URL(string: "mailto:seslerinizindeapps@outlook.com")!
                )
                .accessibilityHint(String(localized: "Destek için e-posta uygulamasını açar."))

                Text("Kamera, mikrofon ve ekran kaydı izinleri yalnızca seçtiğin kayıt özellikleri için kullanılır. Kayıt dosyaları varsayılan olarak Mac'inde saklanır.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

struct QuickHelpSection: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [String]
}

enum QuickHelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted
    case recording
    case shortcuts
    case accessibility
    case troubleshooting

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .gettingStarted:
            return "play.circle.fill"
        case .recording:
            return "record.circle.fill"
        case .shortcuts:
            return "command.square.fill"
        case .accessibility:
            return "figure.roll"
        case .troubleshooting:
            return "wrench.and.screwdriver.fill"
        }
    }
}

struct QuickHelpContent: Equatable {
    let title: String
    let subtitle: String
    let searchPlaceholder: String
    let closeButtonTitle: String
    let openOnlineHelpTitle: String
    let emptyStateActionTitle: String
    let topics: [QuickHelpTopic: QuickHelpSection]

    static let english = QuickHelpContent(
        title: "Quick Help",
        subtitle: "A compact in-app guide for the main FrameMate workflows.",
        searchPlaceholder: "Search help",
        closeButtonTitle: "Close",
        openOnlineHelpTitle: "Open online help",
        emptyStateActionTitle: "Open Help & Support",
        topics: [
            .gettingStarted: QuickHelpSection(
                id: "english-start",
                title: "Getting Started",
                items: [
                    "Complete the onboarding permission steps for camera, microphone, screen recording, and accessibility features you plan to use.",
                    "Choose a recording mode: horizontal camera, horizontal screen, or audio-only.",
                    "Pick the needed inputs such as camera, microphone, display, or window before starting."
                ]
            ),
            .recording: QuickHelpSection(
                id: "english-recording",
                title: "Recording",
                items: [
                    "Screen recording can capture a full display or a single window.",
                    "Screen recordings can include microphone audio, system audio, cursor highlight, and a camera box.",
                    "Camera recordings support Frame Coach and auto reframe for single-person shots.",
                    "Audio mode can record microphone audio, system audio, or both."
                ]
            ),
            .shortcuts: QuickHelpSection(
                id: "english-shortcuts",
                title: "Keyboard Shortcuts",
                items: [
                    "Cmd+1 selects camera recording, Cmd+2 selects screen recording, and Cmd+3 selects audio recording.",
                    "Cmd+D turns Frame Coach on or off, and Cmd+I announces the current settings.",
                    "Cmd+Ctrl+R starts or stops the main recording, Cmd+Ctrl+5 toggles audio-only recording, and Cmd+Ctrl+P pauses or resumes."
                ]
            ),
            .accessibility: QuickHelpSection(
                id: "english-accessibility",
                title: "Accessibility",
                items: [
                    "FrameMate is designed to work well with VoiceOver, keyboard navigation, live status announcements, and spoken guidance.",
                    "Frame Coach is especially helpful for blind and low-vision creators who need spoken framing feedback.",
                    "Enable FrameMate in System Settings > Privacy & Security > Accessibility when you want reliable Cmd+I setting announcements."
                ]
            ),
            .troubleshooting: QuickHelpSection(
                id: "english-troubleshooting",
                title: "Troubleshooting",
                items: [
                    "If camera, microphone, or screen recording does not work, review permissions in System Settings > Privacy & Security.",
                    "If FrameMate is not listed under Screen Recording, use the plus button, choose FrameMate from Applications, enable it, then reopen the app.",
                    "If system audio is missing, verify Screen Recording permission and reopen the app.",
                    "If accessibility announcements do not work reliably, allow FrameMate under Accessibility."
                ]
            )
        ]
    )

    static let turkish = QuickHelpContent(
        title: "Hızlı Yardım",
        subtitle: "FrameMate'in temel akışlarını uygulama içinden hızlıca anlatan kısa rehber.",
        searchPlaceholder: "Yardımda ara",
        closeButtonTitle: "Kapat",
        openOnlineHelpTitle: "Çevrimiçi yardımı aç",
        emptyStateActionTitle: "Yardım ve Desteği Aç",
        topics: [
            .gettingStarted: QuickHelpSection(
                id: "turkish-start",
                title: "Başlangıç",
                items: [
                    "Kullanacağın özelliklere göre onboarding içindeki kamera, mikrofon, ekran kaydı ve erişilebilirlik izinlerini tamamla.",
                    "Kayıt modunu seç: yatay video, yatay ekran veya ses kaydı.",
                    "Kaydı başlatmadan önce gerekli girişleri seç: kamera, mikrofon, ekran veya pencere."
                ]
            ),
            .recording: QuickHelpSection(
                id: "turkish-recording",
                title: "Kayıt",
                items: [
                    "Ekran kaydı tam ekranı veya tek pencereyi yakalayabilir.",
                    "Ekran kayıtlarına mikrofon, sistem sesi, imleç vurgusu ve kamera kutusu eklenebilir.",
                    "Kamera kayıtlarında Kadraj Koçu ve tek kişilik çekimler için otomatik yeniden kadrajlama kullanılabilir.",
                    "Ses modu mikrofonu, sistem sesini veya ikisini birlikte kaydedebilir."
                ]
            ),
            .shortcuts: QuickHelpSection(
                id: "turkish-shortcuts",
                title: "Klavye Kısayolları",
                items: [
                    "Cmd+1 kamera kaydını, Cmd+2 ekran kaydını, Cmd+3 ses kaydını seçer.",
                    "Cmd+D Kadraj Koçu'nu açıp kapatır, Cmd+I mevcut ayarları duyurur.",
                    "Cmd+Ctrl+R ana kaydı başlatır veya durdurur, Cmd+Ctrl+5 ses kaydını açıp kapatır, Cmd+Ctrl+P duraklatır veya devam ettirir."
                ]
            ),
            .accessibility: QuickHelpSection(
                id: "turkish-accessibility",
                title: "Erişilebilirlik",
                items: [
                    "FrameMate; VoiceOver, klavye ile kullanım, canlı durum anonsları ve sesli yönlendirme ile güçlü çalışacak şekilde tasarlanmıştır.",
                    "Kadraj Koçu, özellikle kör ve az gören kullanıcılar için konuşmalı kadraj geri bildirimi sunar.",
                    "Güvenilir Cmd+I ayar duyurusu için Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik bölümünde FrameMate'e izin ver."
                ]
            ),
            .troubleshooting: QuickHelpSection(
                id: "turkish-troubleshooting",
                title: "Sorun Giderme",
                items: [
                    "Kamera, mikrofon veya ekran kaydı çalışmıyorsa Sistem Ayarları > Gizlilik ve Güvenlik içindeki izinleri kontrol et.",
                    "FrameMate Ekran Kaydı listesinde görünmüyorsa artı düğmesine bas, Uygulamalar'dan FrameMate'i seç, anahtarı aç ve uygulamayı yeniden başlat.",
                    "Sistem sesi gelmiyorsa Ekran Kaydı iznini doğrula ve uygulamayı yeniden aç.",
                    "Erişilebilirlik duyuruları güvenilir çalışmıyorsa FrameMate'e Erişilebilirlik izni verildiğinden emin ol."
                ]
            )
        ]
    )

    static func content(forPreferredLanguage preferredLanguage: String?) -> QuickHelpContent {
        let normalized = preferredLanguage?.lowercased() ?? "en"
        return normalized.hasPrefix("tr") ? .turkish : .english
    }

    static var current: QuickHelpContent {
        content(forPreferredLanguage: Locale.preferredLanguages.first)
    }
}

private struct QuickHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTopic: QuickHelpTopic = .gettingStarted
    @State private var searchText = ""
    @AccessibilityFocusState private var isTopicTitleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField(content.searchPlaceholder, text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .accessibilityHint(searchFieldHint)

            HStack(spacing: 0) {
                List(QuickHelpTopic.allCases, selection: $selectedTopic) { topic in
                    Label(title(for: topic), systemImage: topic.symbolName)
                        .tag(topic)
                }
                .listStyle(.sidebar)
                .frame(minWidth: 230, idealWidth: 250, maxWidth: 280)
                .accessibilityLabel(sectionListTitle)
                .accessibilityValue(title(for: selectedTopic))
                .accessibilityHint(sectionListHint)

                Divider()

                ScrollView {
                    QuickHelpTopicView(
                        title: title(for: selectedTopic),
                        items: filteredItems(for: selectedTopic),
                        emptyStateTitle: emptyStateTitle,
                        emptyStateMessage: emptyStateMessage,
                        emptyStateActionTitle: content.emptyStateActionTitle,
                        onOpenOnlineHelp: openOnlineHelp,
                        isTitleFocused: $isTopicTitleFocused
                    )
                    .padding(24)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 560)
        .onChange(of: selectedTopic) { _, newTopic in
            guard isVoiceOverRunning else { return }
            let announcement = content == .turkish
                ? "\(title(for: newTopic)) bölümü açıldı."
                : "\(title(for: newTopic)) section opened."
            announceForVoiceOver(announcement)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTopicTitleFocused = true
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(content.openOnlineHelpTitle) {
                    openOnlineHelp()
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button(content.closeButtonTitle) {
                    dismiss()
                }
            }
        }
    }

    private var content: QuickHelpContent {
        .current
    }

    private func title(for topic: QuickHelpTopic) -> String {
        content.topics[topic]?.title ?? ""
    }

    private func filteredItems(for topic: QuickHelpTopic) -> [String] {
        let items = content.topics[topic]?.items ?? []
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var emptyStateTitle: String {
        content == .turkish ? "Sonuç bulunamadı" : "No results found"
    }

    private var emptyStateMessage: String {
        content == .turkish
            ? "Farklı bir kelimeyle tekrar deneyebilirsin."
            : "Try a different word or a shorter phrase."
    }

    private var sectionListTitle: String {
        content == .turkish ? "Yardım bölümleri" : "Help sections"
    }

    private var sectionListHint: String {
        content == .turkish
            ? "Listeden bir bölüm seç. Seçili bölümün içeriği sağ tarafta açılır."
            : "Select a section from the list. The selected section opens in the content area on the right."
    }

    private var searchFieldHint: String {
        content == .turkish
            ? "Yalnızca seçili yardım bölümünün içeriğinde arama yapar."
            : "Searches only within the currently selected help section."
    }

    private var isVoiceOverRunning: Bool {
        NSWorkspace.shared.isVoiceOverEnabled
    }

    private func announceForVoiceOver(_ text: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(
            element: app,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: text,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    private func openOnlineHelp() {
        NSWorkspace.shared.open(URL(string: "https://recepgur07-bot.github.io/oneday-support/framemate-support")!)
    }
}

private struct QuickHelpTopicView: View {
    let title: String
    let items: [String]
    let emptyStateTitle: String
    let emptyStateMessage: String
    let emptyStateActionTitle: String
    let onOpenOnlineHelp: () -> Void
    @AccessibilityFocusState.Binding var isTitleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isTitleFocused)

            if items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(emptyStateTitle)
                        .font(.headline)
                    Text(emptyStateMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button(emptyStateActionTitle) {
                        onOpenOnlineHelp()
                    }
                    .padding(.top, 6)
                }
            } else {
                ForEach(items, id: \.self) { item in
                    Label {
                        Text(item)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.fmAccent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .accessibilityLabel(String(localized: "Dosya adı"))
                .accessibilityHint(String(localized: "Dosyanın adını düzenle. Uzantı otomatik eklenir."))
                Button("Yeniden Adlandır") {
                    onRename(editableName)
                }
                .accessibilityHint(String(localized: "Yukarıdaki alandaki adı kaydeder"))
            }

            HStack {
                Button("Aç") {
                    onOpen()
                }
                .accessibilityHint(String(localized: "Kaydı varsayılan uygulamayla açar"))
                Button("Klasörde Göster") {
                    onReveal()
                }
                .accessibilityHint(String(localized: "Finder'da dosyanın bulunduğu klasörü gösterir"))
                Button("Farklı Kaydet") {
                    onSaveAs(editableName)
                }
                .accessibilityHint(String(localized: "Kaydı farklı bir konuma kopyalar"))
                Spacer()
                Button("Kapat") {
                    onClose()
                }
                .accessibilityHint(String(localized: "Bu pencereyi kapatır"))
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
            Text(String(localized: "Pro erişim seç"))
                .font(.title2.weight(.semibold))

            Text(String(localized: "Yıllık plan 14 gün ücretsiz deneme ile başlar. Bu deneme, App Store hesabın daha önce kullanmadıysa görünür. Ömür boyu planı istersen doğrudan tek seferde satın alabilirsin."))
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

            HStack(spacing: 16) {
                Link(
                    String(localized: "Gizlilik Politikası"),
                    destination: URL(string: "https://recepgur07-bot.github.io/oneday-support/framemate-privacy")!
                )
                .accessibilityHint(String(localized: "FrameMate gizlilik politikasını tarayıcıda açar."))

                Link(
                    String(localized: "Kullanım Koşulları"),
                    destination: URL(string: "https://www.apple.com/legal/macapps/stdeula/")!
                )
                .accessibilityHint(String(localized: "Apple'ın standart son kullanıcı lisans sözleşmesini açar."))
            }
            .font(.footnote)

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

            Button(isBusy ? String(localized: "İşleniyor…") : buttonTitle(for: plan)) {
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

    private func buttonTitle(for plan: AppAccessPlan) -> String {
        switch plan {
        case .yearly:
            return String(localized: "Yıllık Planı Seç")
        case .lifetime:
            return String(localized: "Ömür Boyu Satın Al")
        }
    }
}
