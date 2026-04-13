import CoreGraphics
import XCTest
@testable import VideoRecorderApp

final class AutoReframeEngineTests: XCTestCase {
    func testSinglePersonOffCenterProducesShiftedCrop() {
        let analysis = FrameAnalysis(
            faceBoxes: [NormalizedFaceBox(rect: CGRect(x: 0.18, y: 0.28, width: 0.14, height: 0.18))],
            subjectCount: .one,
            headroomRatio: 0.2,
            bottomCoverageRatio: 0.2,
            horizontalGroupCenter: 0.25,
            spacingMetric: 0,
            confidence: 0.95
        )

        let crop = AutoReframeEngine().crop(for: analysis, mode: .horizontal1080p)

        XCTAssertLessThan(crop.width, 1.0)
        XCTAssertLessThan(crop.centerX, 0.5)
    }

    func testLowConfidenceAnalysisKeepsFullFrame() {
        let analysis = FrameAnalysis(
            faceBoxes: [NormalizedFaceBox(rect: CGRect(x: 0.42, y: 0.30, width: 0.14, height: 0.18))],
            subjectCount: .one,
            headroomRatio: 0.2,
            bottomCoverageRatio: 0.2,
            horizontalGroupCenter: 0.5,
            spacingMetric: 0,
            confidence: 0.2
        )

        XCTAssertEqual(AutoReframeEngine().crop(for: analysis, mode: .horizontal1080p), .fullFrame)
    }

    func testTwoPeopleProduceGroupedCrop() {
        let analysis = FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.22, y: 0.30, width: 0.14, height: 0.18)),
                NormalizedFaceBox(rect: CGRect(x: 0.58, y: 0.30, width: 0.14, height: 0.18))
            ],
            subjectCount: .two,
            headroomRatio: 0.2,
            bottomCoverageRatio: 0.2,
            horizontalGroupCenter: 0.5,
            spacingMetric: 0.3,
            confidence: 0.95
        )

        let crop = AutoReframeEngine().crop(for: analysis, mode: .horizontal1080p)

        XCTAssertLessThan(crop.width, 1.0)
        XCTAssertEqual(AutoReframeEngine().strategyDescription(for: analysis), "iki-kisi-grup")
    }

    func testTwoPeopleWithUnevenFaceSizesStayBalancedAroundGroupCenter() {
        let analysis = FrameAnalysis(
            faceBoxes: [
                NormalizedFaceBox(rect: CGRect(x: 0.14, y: 0.28, width: 0.22, height: 0.28)),
                NormalizedFaceBox(rect: CGRect(x: 0.66, y: 0.33, width: 0.10, height: 0.13))
            ],
            subjectCount: .two,
            headroomRatio: 0.2,
            bottomCoverageRatio: 0.2,
            horizontalGroupCenter: 0.5,
            spacingMetric: 0.35,
            confidence: 0.95
        )

        let crop = AutoReframeEngine().crop(for: analysis, mode: .horizontal1080p)

        XCTAssertEqual(crop.centerX, 0.5, accuracy: 0.03)
        XCTAssertLessThan(crop.width, 1.0)
    }
}
