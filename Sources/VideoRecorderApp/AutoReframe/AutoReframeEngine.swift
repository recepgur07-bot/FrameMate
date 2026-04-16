import Foundation

struct AutoReframeEngine {
    func crop(for analysis: FrameAnalysis?, mode: RecordingMode) -> AutoReframeCrop {
        guard let analysis,
              analysis.confidence >= 0.55 else {
            return .fullFrame
        }

        switch analysis.subjectCount {
        case .one:
            return singlePersonCrop(for: analysis, mode: mode)
        case .two:
            return twoPersonCrop(for: analysis, mode: mode)
        case .three:
            return .fullFrame
        }
    }

    func strategyDescription(for analysis: FrameAnalysis?) -> String {
        guard let analysis, analysis.confidence >= 0.55 else {
            return "full-frame"
        }

        switch analysis.subjectCount {
        case .one:
            return "tek-kisi"
        case .two:
            return "iki-kisi-grup"
        case .three:
            return "full-frame"
        }
    }

    private func singlePersonCrop(for analysis: FrameAnalysis, mode: RecordingMode) -> AutoReframeCrop {
        guard let subject = analysis.subjects.first else { return .fullFrame }
        let desiredFaceWidth: Double = mode == .vertical1080p ? 0.18 : 0.16
        let minimumCrop: Double = mode == .vertical1080p ? 0.84 : 0.88
        let targetCropSize = (subject.faceBox.width / desiredFaceWidth).clamped(to: minimumCrop...1.0)

        let desiredFaceCenterY: Double = mode == .vertical1080p ? 0.36 : 0.38
        let cropCenterX = subject.faceBox.centerX
        let cropCenterY = subject.faceBox.centerY + ((0.5 - desiredFaceCenterY) * targetCropSize)

        return AutoReframeCrop(
            originX: cropCenterX - (targetCropSize / 2),
            originY: cropCenterY - (targetCropSize / 2),
            width: targetCropSize,
            height: targetCropSize
        )
        .clamped()
    }

    private func twoPersonCrop(for analysis: FrameAnalysis, mode: RecordingMode) -> AutoReframeCrop {
        guard analysis.subjects.count >= 2 else {
            return .fullFrame
        }

        let sortedSubjects = analysis.subjects.sorted { $0.faceBox.centerX < $1.faceBox.centerX }
        let left = sortedSubjects[0].faceBox
        let right = sortedSubjects[1].faceBox
        let targetFaceWidth = max(left.width, right.width)
        let targetFaceHeight = max(left.height, right.height)
        let equalizedLeft = equalizedRect(for: left, width: targetFaceWidth, height: targetFaceHeight)
        let equalizedRight = equalizedRect(for: right, width: targetFaceWidth, height: targetFaceHeight)
        let minX = min(equalizedLeft.minX, equalizedRight.minX)
        let maxX = max(equalizedLeft.maxX, equalizedRight.maxX)
        let minY = min(equalizedLeft.minY, equalizedRight.minY)
        let maxY = max(equalizedLeft.maxY, equalizedRight.maxY)
        let horizontalPadding: Double = mode == .vertical1080p ? 0.16 : 0.12
        let verticalPadding: Double = mode == .vertical1080p ? 0.28 : 0.24

        let width = min(max((maxX - minX) + horizontalPadding, mode == .vertical1080p ? 0.86 : 0.80), 1.0)
        let height = min(max((maxY - minY) + verticalPadding, mode == .vertical1080p ? 0.86 : 0.80), 1.0)
        let centerX = (left.centerX + right.centerX) / 2
        let centerY = ((left.centerY + right.centerY) / 2) + (mode == .vertical1080p ? 0.10 : 0.08)

        return AutoReframeCrop(
            originX: centerX - (width / 2),
            originY: centerY - (height / 2),
            width: width,
            height: height
        )
        .clamped()
    }

    /// Returns a portrait-mode crop for a landscape source (1920×1080 → 1080×1920).
    /// Shifts the horizontal crop window to keep the face centered.
    /// Falls back to center crop when analysis is nil or low-confidence.
    func portraitCrop(for analysis: FrameAnalysis?) -> AutoReframeCrop {
        guard let analysis, analysis.confidence >= 0.55,
              analysis.subjectCount == .one,
              let subject = analysis.subjects.first else {
            return .portraitFullHeight(centerX: 0.5)
        }
        return .portraitFullHeight(centerX: subject.faceBox.centerX)
    }

    private func equalizedRect(for face: NormalizedFaceBox, width: Double, height: Double) -> CGRect {
        CGRect(
            x: face.centerX - (width / 2),
            y: face.centerY - (height / 2),
            width: width,
            height: height
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
