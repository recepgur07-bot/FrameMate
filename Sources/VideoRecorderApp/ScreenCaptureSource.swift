import Foundation

enum ScreenCaptureSource: String, CaseIterable, Identifiable, Codable {
    case screen
    case window

    var id: String { rawValue }

    var label: String {
        switch self {
        case .screen:
            return "Tam Ekran"
        case .window:
            return "Pencere"
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
