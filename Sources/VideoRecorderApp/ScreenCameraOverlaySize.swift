import CoreGraphics
import Foundation

enum ScreenCameraOverlaySize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small:
            return "Küçük"
        case .medium:
            return "Orta"
        case .large:
            return "Büyük"
        }
    }

    func widthRatio(for renderSize: CGSize) -> CGFloat {
        let isVertical = renderSize.height > renderSize.width

        switch self {
        case .small:
            return isVertical ? 0.24 : 0.15
        case .medium:
            return isVertical ? 0.30 : 0.21
        case .large:
            return isVertical ? 0.36 : 0.27
        }
    }
}
