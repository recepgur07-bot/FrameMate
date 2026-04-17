import Foundation

enum RecordingPreset: String, CaseIterable, Identifiable, Codable {
    case horizontalCamera
    case verticalCamera
    case horizontalScreen
    case verticalScreen
    case audioOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .horizontalCamera:
            return String(localized: "Yatay video kaydı")
        case .verticalCamera:
            return String(localized: "Dikey video kaydı")
        case .horizontalScreen:
            return String(localized: "Yatay ekran kaydı")
        case .verticalScreen:
            return String(localized: "Dikey ekran kaydı")
        case .audioOnly:
            return String(localized: "Ses kaydı")
        }
    }

    var menuLabel: String {
        switch self {
        case .horizontalCamera:
            return String(localized: "Yatay video kaydı modu")
        case .verticalCamera:
            return String(localized: "Dikey video kaydı modu")
        case .horizontalScreen:
            return String(localized: "Yatay ekran kaydı modu")
        case .verticalScreen:
            return String(localized: "Dikey ekran kaydı modu")
        case .audioOnly:
            return String(localized: "Ses kaydı modu")
        }
    }


    var commandMenuLabel: String {
        label
    }

    var shortDescription: String {
        switch self {
        case .horizontalCamera:
            return String(localized: "Kamera ile yatay video çek")
        case .verticalCamera:
            return String(localized: "Kamera ile dikey video çek")
        case .horizontalScreen:
            return String(localized: "Yatay ekran veya pencere kaydet")
        case .verticalScreen:
            return String(localized: "Dikey ekran veya pencere kaydet")
        case .audioOnly:
            return String(localized: "Sadece ses kaydı al")
        }
    }

    var symbolName: String {
        switch self {
        case .horizontalCamera:
            return "video.fill"
        case .verticalCamera:
            return "video.badge.ellipsis"
        case .horizontalScreen:
            return "display"
        case .verticalScreen:
            return "rectangle.portrait.on.rectangle.portrait"
        case .audioOnly:
            return "waveform.circle.fill"
        }
    }

    var recordingMode: RecordingMode {
        switch self {
        case .horizontalCamera, .horizontalScreen, .audioOnly:
            return .horizontal1080p
        case .verticalCamera, .verticalScreen:
            return .vertical1080p
        }
    }

    var isCameraPreset: Bool {
        switch self {
        case .horizontalCamera, .verticalCamera:
            return true
        case .horizontalScreen, .verticalScreen, .audioOnly:
            return false
        }
    }

    var isScreenPreset: Bool {
        switch self {
        case .horizontalScreen, .verticalScreen:
            return true
        case .horizontalCamera, .verticalCamera, .audioOnly:
            return false
        }
    }

    var isAudioPreset: Bool {
        self == .audioOnly
    }

    var commandKey: Character {
        switch self {
        case .horizontalCamera:
            return "1"
        case .verticalCamera:
            return "2"
        case .horizontalScreen:
            return "3"
        case .verticalScreen:
            return "4"
        case .audioOnly:
            return "5"
        }
    }

    var readinessLabel: String {
        label
    }
}
