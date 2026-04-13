import CoreGraphics
import Foundation

enum RecordingMode: String, CaseIterable, Identifiable {
    case horizontal1080p
    case vertical1080p

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
}
