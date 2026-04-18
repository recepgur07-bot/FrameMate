import Foundation

enum FrameCoachSpatialAudioMode: String, CaseIterable, Identifiable {
    case off
    case tonesOnly
    case tonesAndSpeech

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:
            return String(localized: "Kapalı")
        case .tonesOnly:
            return String(localized: "Sadece yön sesi")
        case .tonesAndSpeech:
            return String(localized: "Yön sesi ve konuşma")
        }
    }
}

enum FrameCoachSpatialDirection: Equatable {
    case left
    case right
    case up
    case down
    case center
}

enum FrameCoachSpatialSeverity: Equatable {
    case mild
    case strong
}

struct FrameCoachSpatialCue: Equatable {
    var direction: FrameCoachSpatialDirection
    var severity: FrameCoachSpatialSeverity
    var confirmsCentered: Bool
}
