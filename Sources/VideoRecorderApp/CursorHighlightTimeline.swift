import CoreGraphics
import Foundation

struct CursorSample: Equatable {
    let timestamp: TimeInterval
    let normalizedX: CGFloat
    let normalizedY: CGFloat
}

struct CursorClickEvent: Equatable {
    let timestamp: TimeInterval
    let normalizedX: CGFloat
    let normalizedY: CGFloat
}

struct CursorHighlightTimeline: Equatable {
    var samples: [CursorSample] = []
    var clickEvents: [CursorClickEvent] = []

    var isEmpty: Bool {
        samples.isEmpty && clickEvents.isEmpty
    }

    static let empty = CursorHighlightTimeline()
}
