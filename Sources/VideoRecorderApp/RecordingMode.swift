import CoreGraphics
import Foundation

enum RecordingMode: String, Identifiable, CaseIterable {
    case horizontal1080p
    case vertical1080p

    static var allCases: [RecordingMode] {
        [.horizontal1080p]
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .horizontal1080p:
            return String(localized: "1080p Yatay")
        case .vertical1080p:
            return String(localized: "1080p Dikey")
        }
    }


    var width: Int32 {
        switch self {
        case .horizontal1080p:
            return 1920
        case .vertical1080p:
            return 1080
        }
    }

    var height: Int32 {
        switch self {
        case .horizontal1080p:
            return 1080
        case .vertical1080p:
            return 1920
        }
    }

    var renderSize: CGSize {
        CGSize(width: Int(width), height: Int(height))
    }

    /// Rotation angle to apply at capture layer.
    /// Both modes use 0 — vertical mode's portrait crop is handled at export time.
    /// Switch exhaustiveness ensures new modes are handled explicitly.
    var captureRotationAngle: CGFloat {
        switch self {
        case .horizontal1080p: return 0
        case .vertical1080p:   return 0
        }
    }
}
