import CoreGraphics
import XCTest
@testable import FrameMate

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

    // MARK: - Portrait crop tests

    func testPortraitCropWidthIsCorrectRatioForLandscapeSource() {
        // Portrait crop: 1080 hedef genişlik / (1920/1080 fill scale) / 1920 kaynak genişlik
        // = 1080 * 1080 / (1920 * 1920) = (1080/1920)^2 ≈ 0.3164
        let crop = AutoReframeCrop.portraitFullHeight(centerX: 0.5)
        XCTAssertEqual(crop.width, AutoReframeCrop.portraitWidthRatio, accuracy: 0.001)
        XCTAssertEqual(crop.height, 1.0, accuracy: 0.001)
        XCTAssertEqual(crop.originY, 0.0, accuracy: 0.001)
    }

    func testPortraitCropCenterXFollowsFace() {
        let crop = AutoReframeCrop.portraitFullHeight(centerX: 0.3)
        // centerX of crop must be within the clamped range
        XCTAssertGreaterThanOrEqual(crop.originX, 0)
        XCTAssertLessThanOrEqual(crop.originX + crop.width, 1.0)
        XCTAssertEqual(crop.centerX, 0.3, accuracy: 0.01)
    }

    func testPortraitCropClampsAtLeftEdge() {
        // Face at far left: crop must not go negative
        let crop = AutoReframeCrop.portraitFullHeight(centerX: 0.05)
        XCTAssertEqual(crop.originX, 0.0, accuracy: 0.001)
    }

    func testPortraitCropClampsAtRightEdge() {
        // Face at far right: crop must not exceed source width
        let crop = AutoReframeCrop.portraitFullHeight(centerX: 0.95)
        XCTAssertEqual(crop.originX + crop.width, 1.0, accuracy: 0.001)
    }

    func testPortraitEngineProducesCropForCenteredFace() {
        let analysis = FrameAnalysis(
            faceBoxes: [NormalizedFaceBox(rect: CGRect(x: 0.43, y: 0.20, width: 0.14, height: 0.18))],
            subjectCount: .one,
            headroomRatio: 0.2,
            bottomCoverageRatio: 0.2,
            horizontalGroupCenter: 0.5,
            spacingMetric: 0,
            confidence: 0.95
        )
        let crop = AutoReframeEngine().portraitCrop(for: analysis)
        XCTAssertEqual(crop.height, 1.0, accuracy: 0.001)
        XCTAssertEqual(crop.width, AutoReframeCrop.portraitWidthRatio, accuracy: 0.001)
    }

    func testPortraitEngineReturnsFullHeightCenterCropForNilAnalysis() {
        let crop = AutoReframeEngine().portraitCrop(for: nil)
        XCTAssertEqual(crop.height, 1.0, accuracy: 0.001)
        XCTAssertEqual(crop.width, AutoReframeCrop.portraitWidthRatio, accuracy: 0.001)
        XCTAssertEqual(crop.centerX, 0.5, accuracy: 0.001)
    }

    // MARK: - Portrait composition builder tests

    func testPortraitFillScaleConstantIsCorrect() {
        // Fill scale: 1920(renderH) / 1080(sourceH)
        XCTAssertEqual(AutoReframeCompositionBuilder.portraitFillScale, 1920.0 / 1080.0, accuracy: 0.001)
    }

    func testPortraitTransformForCenterCropMapsSourceCenterToRenderCenter() {
        // Center crop (centerX=0.5): source center (960,540) must map to render center (540,960)
        let crop = AutoReframeCrop.portraitFullHeight(centerX: 0.5)
        let t = AutoReframeCompositionBuilder.portraitLayerTransform(for: crop)
        let sourceCenter = CGPoint(x: 960, y: 540).applying(t)
        XCTAssertEqual(sourceCenter.x, 540, accuracy: 1)
        XCTAssertEqual(sourceCenter.y, 960, accuracy: 1)
    }

    func testPortraitTransformForLeftFaceShiftsWindowLeft() {
        // Face at left (centerX=0.2): crop window starts at left, source left of frame maps to render x~0
        let crop = AutoReframeCrop.portraitFullHeight(centerX: 0.2)
        let t = AutoReframeCompositionBuilder.portraitLayerTransform(for: crop)
        // Left edge of crop window in source: crop.originX * 1920
        let cropLeftSourceX = crop.originX * 1920.0
        let mappedLeft = CGPoint(x: cropLeftSourceX, y: 0).applying(t)
        XCTAssertEqual(mappedLeft.x, 0, accuracy: 2)
    }
}
