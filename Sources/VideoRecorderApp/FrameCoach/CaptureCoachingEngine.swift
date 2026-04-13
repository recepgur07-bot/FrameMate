import Foundation

struct FrameLightingAnalysis: Equatable {
    let averageLuma: Double

    var isLowLight: Bool {
        averageLuma < 0.18
    }
}

final class CaptureCoachingEngine {
    static let lowLightInstruction = String(localized: "ışık düşük, lambayı aç veya ekran parlaklığını artır")

    private let frameCoachingEngine: FrameCoachingEngine

    init(frameCoachingEngine: FrameCoachingEngine = FrameCoachingEngine()) {
        self.frameCoachingEngine = frameCoachingEngine
    }

    func instruction(
        frameAnalysis: FrameAnalysis?,
        lightingAnalysis: FrameLightingAnalysis?,
        mode: RecordingMode,
        profile: FrameCoachingProfile
    ) -> String {
        if lightingAnalysis?.isLowLight == true {
            return Self.lowLightInstruction
        }

        guard let frameAnalysis else {
            return String(localized: "Yüz algılanamıyor, kameraya bak")
        }

        return frameCoachingEngine.instruction(for: frameAnalysis, mode: mode, profile: profile)
    }
}
