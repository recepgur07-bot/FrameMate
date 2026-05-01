import Foundation

enum ScreenCaptureSource: String, CaseIterable, Identifiable, Codable {
    case screen
    case window

    var id: String { rawValue }

    var label: String {
        switch self {
        case .screen:
            return String(localized: "Tam Ekran")
        case .window:
            return String(localized: "Pencere")
        }
    }

    var recordingSource: RecordingSource {
        switch self {
        case .screen:
            return .screen
        case .window:
            return .window
        }
    }
}
