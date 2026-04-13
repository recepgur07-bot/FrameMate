import SwiftUI

extension Color {
    /// #5B4CF5 — indigo brand accent
    static let fmAccent  = Color(red: 0.357, green: 0.298, blue: 0.961)
    /// #FF3B30 — system red, used for record button ready state
    static let fmRecord  = Color(red: 1.0,   green: 0.231, blue: 0.188)
    /// Orange — pause button and paused status
    static let fmPause   = Color.orange
    /// Green — ready status
    static let fmReady   = Color.green
    /// Card background — adapts to Dark Mode
    static let fmCardBg  = Color(nsColor: .controlBackgroundColor)
    /// Window surface — adapts to Dark Mode
    static let fmSurface = Color(nsColor: .windowBackgroundColor)
}
