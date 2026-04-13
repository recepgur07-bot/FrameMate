import Foundation

enum ScreenCameraOverlayPosition: String, CaseIterable, Identifiable {
    case topLeft
    case topCenter
    case topRight
    case centerLeft
    case center
    case centerRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .topLeft:
            return String(localized: "Üst Sol")
        case .topCenter:
            return String(localized: "Üst Orta")
        case .topRight:
            return String(localized: "Üst Sağ")
        case .centerLeft:
            return String(localized: "Orta Sol")
        case .center:
            return String(localized: "Merkez")
        case .centerRight:
            return String(localized: "Orta Sağ")
        case .bottomLeft:
            return String(localized: "Alt Sol")
        case .bottomCenter:
            return String(localized: "Alt Orta")
        case .bottomRight:
            return String(localized: "Alt Sağ")
        }
    }

    var horizontalAnchor: CGFloat {
        switch self {
        case .topLeft, .centerLeft, .bottomLeft:
            return 0
        case .topCenter, .center, .bottomCenter:
            return 0.5
        case .topRight, .centerRight, .bottomRight:
            return 1
        }
    }

    var verticalAnchor: CGFloat {
        switch self {
        case .topLeft, .topCenter, .topRight:
            return 0
        case .centerLeft, .center, .centerRight:
            return 0.5
        case .bottomLeft, .bottomCenter, .bottomRight:
            return 1
        }
    }
}
