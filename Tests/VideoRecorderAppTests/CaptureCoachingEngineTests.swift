import CoreGraphics
import XCTest
@testable import VideoRecorderApp

final class CaptureCoachingEngineTests: XCTestCase {
    func testLowLightTakesPriorityOverGoodFraming() {
        let guidance = CaptureCoachingEngine().instruction(
            frameAnalysis: FrameAnalysis(
                faceBoxes: [NormalizedFaceBox(rect: CGRect(x: 0.42, y: 0.30, width: 0.16, height: 0.20))],
                subjectCount: .one,
                headroomRatio: 0.18,
                bottomCoverageRatio: 0.22,
                horizontalGroupCenter: 0.50,
                spacingMetric: 0,
                confidence: 0.95
            ),
            lightingAnalysis: FrameLightingAnalysis(averageLuma: 0.12),
            mode: .horizontal1080p,
            profile: .singleDeskSpeaker
        )

        XCTAssertEqual(guidance, "ışık düşük, lambayı aç veya ekran parlaklığını artır")
    }
}
