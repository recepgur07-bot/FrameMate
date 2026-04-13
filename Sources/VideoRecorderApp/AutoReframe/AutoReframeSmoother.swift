import Foundation

struct AutoReframeSmoother {
    private let smoothingFactor: Double
    private(set) var currentCrop: AutoReframeCrop

    init(
        smoothingFactor: Double = 0.22,
        currentCrop: AutoReframeCrop = .fullFrame
    ) {
        self.smoothingFactor = smoothingFactor
        self.currentCrop = currentCrop
    }

    mutating func step(towards targetCrop: AutoReframeCrop) -> AutoReframeCrop {
        currentCrop = currentCrop.interpolated(towards: targetCrop, factor: smoothingFactor)
        return currentCrop
    }

    mutating func reset() {
        currentCrop = .fullFrame
    }
}
