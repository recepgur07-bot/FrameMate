import AVFoundation
import CoreGraphics
import Foundation
import Vision

protocol FaceDetecting {
    func detectFaces(in pixelBuffer: CVPixelBuffer) throws -> [NormalizedFaceBox]
}

struct VisionFaceDetector: FaceDetecting {
    func detectFaces(in pixelBuffer: CVPixelBuffer) throws -> [NormalizedFaceBox] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        return observations.map { observation in
            let boundingBox = observation.boundingBox
            let converted = CGRect(
                x: boundingBox.origin.x,
                y: 1 - boundingBox.origin.y - boundingBox.size.height,
                width: boundingBox.size.width,
                height: boundingBox.size.height
            )
            return NormalizedFaceBox(rect: converted)
        }
    }
}

final class FrameAnalysisService {
    private let detector: any FaceDetecting

    init(detector: any FaceDetecting = VisionFaceDetector()) {
        self.detector = detector
    }

    func analyze(pixelBuffer: CVPixelBuffer) -> FrameAnalysis? {
        guard let faceBoxes = try? detector.detectFaces(in: pixelBuffer),
              !faceBoxes.isEmpty else {
            return nil
        }

        let sortedByArea = faceBoxes.sorted { lhs, rhs in
            lhs.rect.width * lhs.rect.height > rhs.rect.width * rhs.rect.height
        }
        let supportedFaces = Array(sortedByArea.prefix(3))
        guard let subjectCount = FrameSubjectCount(rawValue: supportedFaces.count) else {
            return nil
        }

        let minTop = supportedFaces.map { Double($0.rect.minY) }.min() ?? 0
        let maxBottom = supportedFaces.map { Double($0.rect.maxY) }.max() ?? 1
        let minX = supportedFaces.map(\.minX).min() ?? 0
        let maxX = supportedFaces.map(\.maxX).max() ?? 1
        let sortedCenters = supportedFaces.map(\.centerX).sorted()

        let spacingMetric: Double
        if sortedCenters.count >= 2 {
            let gaps = zip(sortedCenters.dropFirst(), sortedCenters).map(-)
            spacingMetric = gaps.max() ?? 0
        } else {
            spacingMetric = 0
        }

        return FrameAnalysis(
            faceBoxes: supportedFaces,
            subjectCount: subjectCount,
            headroomRatio: minTop,
            bottomCoverageRatio: max(0, 1 - maxBottom),
            horizontalGroupCenter: (minX + maxX) / 2,
            spacingMetric: spacingMetric,
            confidence: 0.9
        )
    }
}
