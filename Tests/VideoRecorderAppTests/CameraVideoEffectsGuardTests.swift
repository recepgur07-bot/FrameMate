import XCTest
@testable import VideoRecorderApp

final class CameraVideoEffectsGuardTests: XCTestCase {
    func testActiveEffectNamesReturnsHumanReadableTurkishLabels() {
        let state = CameraVideoEffectsState(
            portraitEffectActive: true,
            studioLightActive: true,
            backgroundReplacementActive: false,
            centerStageActive: true
        )

        XCTAssertEqual(
            CameraVideoEffectsGuard.activeEffectNames(for: state),
            ["Portre", "Stüdyo Işığı", "Center Stage"]
        )
    }

    func testActiveEffectNamesReturnsEmptyWhenNoEffectsAreActive() {
        XCTAssertEqual(
            CameraVideoEffectsGuard.activeEffectNames(for: CameraVideoEffectsState()),
            []
        )
    }
}
