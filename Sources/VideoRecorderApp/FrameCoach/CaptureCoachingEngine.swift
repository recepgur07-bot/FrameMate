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
        instructionDetail(frameAnalysis: frameAnalysis, lightingAnalysis: lightingAnalysis, mode: mode, profile: profile).text
    }

    func instructionDetail(
        frameAnalysis: FrameAnalysis?,
        lightingAnalysis: FrameLightingAnalysis?,
        mode: RecordingMode,
        profile: FrameCoachingProfile
    ) -> FrameCoachGuidance {
        if lightingAnalysis?.isLowLight == true {
            return FrameCoachGuidance(text: Self.lowLightInstruction, kind: .lowLight)
        }

        guard let frameAnalysis else {
            return FrameCoachGuidance(text: FrameCoachingEngine.noFaceInstruction, kind: .hardCorrection)
        }

        return frameCoachingEngine.instructionDetail(for: frameAnalysis, mode: mode, profile: profile)
    }
}
