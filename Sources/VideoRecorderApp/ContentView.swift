import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var viewModel: RecorderViewModel

    @State private var toastQueue = ToastQueue()

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
                        viewModel.toggleScreenCameraOverlay()
                    }
                }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // ── CONTENT ZONE (scrollable) ─────────────────────────────────
            ScrollView {
                VStack(spacing: 12) {
                    permissionHubCard
                    previewCard
                    // Camera-only mode: show camera device picker
                    if viewModel.showsCameraControls {
                        cameraCard
                    }
                    audioCard
                    if viewModel.showsScreenControls || viewModel.showsScreenOverlayControls {
                        sourceCard
                    }
                    if viewModel.showsScreenControls {
                        visualCard
                    }
                    if viewModel.showsScreenOverlayControls {
                        cameraBoxCard
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
            isPresented: Binding(
                get: { viewModel.completedRecording != nil },
                set: { isPresented in
                    if !isPresented { viewModel.dismissCompletedRecordingSummary() }
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
            Task { await viewModel.refreshAppAccess() }
        }
        // VoiceOver announcements — proactively read state changes aloud so the user
        // doesn't have to navigate to the status elements to hear what happened.
        .onChange(of: currentStatus) { oldStatus, newStatus in
            let message: String
            switch newStatus {
            case .recording:  message = String(localized: "Kayıt başladı")
            case .paused:     message = String(localized: "Kayıt duraklatıldı")
            case .preparing:  message = String(localized: "Kayıt hazırlanıyor")
            case .ready:      message = String(localized: "Kayıt durduruldu")
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
            VideoPreviewView(
                session: viewModel.previewSession,
                crop: viewModel.currentAutoReframeCrop
            )
            .frame(minHeight: 240)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
            .accessibilityHidden(true)
        } else if viewModel.showsScreenControls {
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
            .accessibilityHidden(true)
        }
    }

    // MARK: - Camera Card (camera-only mode)

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

            // System audio toggle
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Toggle(String(localized: "Sistem sesini dahil et"), isOn: $viewModel.isSystemAudioEnabled)
                    .accessibilityHint(String(localized: "Mac'te calan uygulama ve sistem seslerini kayda ekler."))
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
                            Text(display.name).tag(display.id)
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

            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Toggle(String(localized: "Klavye kısayollarını göster"), isOn: $viewModel.isKeyboardShortcutOverlayEnabled)
                    .accessibilityHint(String(localized: "Komut, kontrol ve option gibi anlamlı kısayolları videoda kısa süre gösterir."))
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
                        set: { _ in viewModel.toggleScreenCameraOverlay() }
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
                Text(String(localized: "Durum: \(viewModel.errorText != nil ? "Hata oluştu" : viewModel.statusText)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
                    .accessibilityLabel(String(localized: "Durum \(viewModel.statusText)"))

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
