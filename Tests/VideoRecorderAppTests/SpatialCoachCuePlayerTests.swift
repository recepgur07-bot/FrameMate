import XCTest
@testable import FrameMate

final class SpatialCoachCuePlayerTests: XCTestCase {
    func testPlayAcceptsGeneratedStereoCueBuffer() {
        let player = SpatialCoachCuePlayer()
        let preferences = FrameCoachPreferences(
            speechMode: .silent,
            feedbackFrequency: .balanced,
            repeatInterval: .medium,
            showsOnScreenText: false,
            spatialAudioMode: .tonesOnly,
            playsCenterConfirmation: true
        )

        player.play(
            FrameCoachSpatialCue(direction: .left, severity: .mild, confirmsCentered: false),
            preferences: preferences
        )

        player.reset()
    }
}
