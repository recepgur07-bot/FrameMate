import CoreGraphics
import Foundation

struct AutoReframeCrop: Equatable {
    let originX: Double
    let originY: Double
    let width: Double
    let height: Double

    static let fullFrame = AutoReframeCrop(originX: 0, originY: 0, width: 1, height: 1)

    var centerX: Double {
        originX + (width / 2)
    }

    var centerY: Double {
        originY + (height / 2)
    }

    var rect: CGRect {
        CGRect(x: originX, y: originY, width: width, height: height)
    }

    func interpolated(towards target: AutoReframeCrop, factor: Double) -> AutoReframeCrop {
        AutoReframeCrop(
            originX: interpolate(originX, target.originX, factor: factor),
            originY: interpolate(originY, target.originY, factor: factor),
            width: interpolate(width, target.width, factor: factor),
            height: interpolate(height, target.height, factor: factor)
        )
        .clamped()
    }

    func clamped() -> AutoReframeCrop {
        let clampedWidth = width.clamped(to: 0.1...1.0)
        let clampedHeight = height.clamped(to: 0.1...1.0)
        let clampedOriginX = originX.clamped(to: 0...(1 - clampedWidth))
        let clampedOriginY = originY.clamped(to: 0...(1 - clampedHeight))

        return AutoReframeCrop(
            originX: clampedOriginX,
            originY: clampedOriginY,
            width: clampedWidth,
            height: clampedHeight
        )
    }

    private func interpolate(_ current: Double, _ target: Double, factor: Double) -> Double {
        current + ((target - current) * factor)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
