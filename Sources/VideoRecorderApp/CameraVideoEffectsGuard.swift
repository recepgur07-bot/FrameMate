@preconcurrency import AVFoundation
import Foundation

struct CameraVideoEffectsState: Equatable {
    var portraitEffectActive = false
    var studioLightActive = false
    var backgroundReplacementActive = false
    var centerStageActive = false
}

enum CameraVideoEffectsGuard {
    static func activeEffectNames(for state: CameraVideoEffectsState) -> [String] {
        var names: [String] = []

        if state.portraitEffectActive {
            names.append("Portre")
        }
        if state.studioLightActive {
            names.append("Stüdyo Işığı")
        }
        if state.backgroundReplacementActive {
            names.append("Arka Plan")
        }
        if state.centerStageActive {
            names.append("Center Stage")
        }

        return names
    }

    static func activeEffectNames(for device: AVCaptureDevice) -> [String] {
        activeEffectNames(
            for: CameraVideoEffectsState(
                portraitEffectActive: device.isPortraitEffectActive,
                studioLightActive: device.isStudioLightActive,
                backgroundReplacementActive: {
                    if #available(macOS 15.0, *) {
                        return device.isBackgroundReplacementActive
                    }
                    return false
                }(),
                centerStageActive: device.isCenterStageActive
            )
        )
    }
}
