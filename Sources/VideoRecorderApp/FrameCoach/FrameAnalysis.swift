import Foundation
import CoreGraphics

struct NormalizedFaceBox: Equatable {
    let rect: CGRect

    var centerX: Double {
        Double(rect.midX)
    }

    var centerY: Double {
        Double(rect.midY)
    }

    var maxX: Double {
        Double(rect.maxX)
    }

    var minX: Double {
        Double(rect.minX)
    }

    var minY: Double {
        Double(rect.minY)
    }

    var maxY: Double {
        Double(rect.maxY)
    }

    var width: Double {
        Double(rect.width)
    }

    var height: Double {
        Double(rect.height)
    }
}

enum FrameSubjectCount: Int, CaseIterable, Equatable {
    case one = 1
    case two = 2
    case three = 3
}

enum FrameSubjectRole: Equatable {
    case solo
    case left
    case center
    case right

    var label: String {
        switch self {
        case .solo:
            return "kişi"
        case .left:
            return "soldaki kişi"
        case .center:
            return "ortadaki kişi"
        case .right:
            return "sağdaki kişi"
        }
    }
}

struct FrameSubjectObservation: Equatable {
    let role: FrameSubjectRole
    let faceBox: NormalizedFaceBox
}

struct FrameAnalysis: Equatable {
    let faceBoxes: [NormalizedFaceBox]
    let subjectCount: FrameSubjectCount
    let headroomRatio: Double
    let bottomCoverageRatio: Double
    let horizontalGroupCenter: Double
    let spacingMetric: Double
    let confidence: Double

    var faceCount: Int {
        faceBoxes.count
    }

    var averageFaceCenterY: Double? {
        guard !faceBoxes.isEmpty else { return nil }
        return faceBoxes.map(\.centerY).reduce(0, +) / Double(faceBoxes.count)
    }

    var averageFaceWidth: Double? {
        guard !faceBoxes.isEmpty else { return nil }
        return faceBoxes.map { Double($0.rect.width) }.reduce(0, +) / Double(faceBoxes.count)
    }

    var averageFaceHeight: Double? {
        guard !faceBoxes.isEmpty else { return nil }
        return faceBoxes.map(\.height).reduce(0, +) / Double(faceBoxes.count)
    }

    var groupCenterX: Double {
        horizontalGroupCenter
    }

    var faceWidthRatio: Double? {
        let widths = faceBoxes.map(\.width)
        guard let minWidth = widths.min(),
              let maxWidth = widths.max(),
              minWidth > 0 else {
            return nil
        }

        return maxWidth / minWidth
    }

    var overlapRatio: Double {
        guard faceBoxes.count >= 2 else { return 0 }

        let sorted = faceBoxes.sorted { $0.centerX < $1.centerX }
        var strongestOverlap = 0.0

        for index in 0..<(sorted.count - 1) {
            let current = sorted[index].rect
            let next = sorted[index + 1].rect
            let intersection = current.intersection(next)

            guard !intersection.isNull else { continue }

            let intersectionArea = Double(intersection.width * intersection.height)
            let smallerArea = min(
                Double(current.width * current.height),
                Double(next.width * next.height)
            )

            guard smallerArea > 0 else { continue }
            strongestOverlap = max(strongestOverlap, intersectionArea / smallerArea)
        }

        return strongestOverlap
    }

    var subjects: [FrameSubjectObservation] {
        let sorted = faceBoxes.sorted { $0.centerX < $1.centerX }
        return sorted.enumerated().map { index, faceBox in
            FrameSubjectObservation(role: role(for: index, total: sorted.count), faceBox: faceBox)
        }
    }

    private func role(for index: Int, total: Int) -> FrameSubjectRole {
        switch total {
        case 1:
            return .solo
        case 2:
            return index == 0 ? .left : .right
        case 3:
            switch index {
            case 0:
                return .left
            case 1:
                return .center
            default:
                return .right
            }
        default:
            return .solo
        }
    }
}
