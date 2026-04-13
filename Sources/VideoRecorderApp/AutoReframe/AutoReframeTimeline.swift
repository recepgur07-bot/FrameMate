import AVFoundation
import Foundation

struct AutoReframeKeyframe: Equatable {
    let time: CMTime
    let crop: AutoReframeCrop
}

struct AutoReframeTimeline: Equatable {
    private(set) var keyframes: [AutoReframeKeyframe] = []

    var isEmpty: Bool {
        keyframes.isEmpty
    }

    mutating func append(crop: AutoReframeCrop, at time: CMTime) {
        guard time.isNumeric else { return }

        if let last = keyframes.last,
           abs(time.seconds - last.time.seconds) < 0.001 {
            keyframes[keyframes.count - 1] = AutoReframeKeyframe(time: time, crop: crop)
            return
        }

        keyframes.append(AutoReframeKeyframe(time: time, crop: crop))
    }

    mutating func reset() {
        keyframes.removeAll()
    }
}

private extension CMTime {
    var isNumeric: Bool {
        flags.contains(.valid) && !seconds.isNaN && !seconds.isInfinite
    }
}
