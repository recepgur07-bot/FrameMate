import Foundation

enum RecordingSource: String, CaseIterable, Identifiable {
    case camera
    case screen
    case window
    case audio

    var id: String { rawValue }

    var label: String {
        switch self {
        case .camera:
            return String(localized: "Kamera")
        case .screen:
            return String(localized: "Tam Ekran")
        case .window:
            return String(localized: "Pencere")
        case .audio:
            return String(localized: "Ses")
        }
    }

}
