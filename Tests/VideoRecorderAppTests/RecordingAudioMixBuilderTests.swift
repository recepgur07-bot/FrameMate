import AVFoundation
import XCTest
@testable import FrameMate

final class RecordingAudioMixBuilderTests: XCTestCase {
    func testBuilderAppliesSeparateVolumesToMicrophoneAndSystemAudioTracks() throws {
        let builder = RecordingAudioMixBuilder()
        let composition = AVMutableComposition()
        let microphoneTrack = try XCTUnwrap(
            composition.addMutableTrack(withMediaType: .audio, preferredTrackID: 11)
        )
        let systemTrack = try XCTUnwrap(
            composition.addMutableTrack(withMediaType: .audio, preferredTrackID: 22)
        )

        let audioMix = builder.makeAudioMix(
            composition: composition,
            microphoneTrackIDs: [11],
            systemAudioTrackIDs: [22],
            microphoneVolume: 0.8,
            systemAudioVolume: 0.35
        )

        let parameters = try XCTUnwrap(audioMix?.inputParameters)
        XCTAssertEqual(parameters.count, 2)

        let microphoneParameters = try XCTUnwrap(parameters.first(where: { $0.trackID == microphoneTrack.trackID }))
        let systemParameters = try XCTUnwrap(parameters.first(where: { $0.trackID == systemTrack.trackID }))

        var microphoneStart: Float = -1
        var microphoneEnd: Float = -1
        var microphoneRange = CMTimeRange(start: .zero, duration: .zero)
        XCTAssertTrue(microphoneParameters.getVolumeRamp(for: .zero, startVolume: &microphoneStart, endVolume: &microphoneEnd, timeRange: &microphoneRange))
        XCTAssertEqual(microphoneStart, 0.8, accuracy: 0.001)
        XCTAssertEqual(microphoneEnd, 0.8, accuracy: 0.001)

        var systemStart: Float = -1
        var systemEnd: Float = -1
        var systemRange = CMTimeRange(start: .zero, duration: .zero)
        XCTAssertTrue(systemParameters.getVolumeRamp(for: .zero, startVolume: &systemStart, endVolume: &systemEnd, timeRange: &systemRange))
        XCTAssertEqual(systemStart, 0.35, accuracy: 0.001)
        XCTAssertEqual(systemEnd, 0.35, accuracy: 0.001)
    }

    func testBuilderReturnsNilWhenThereAreNoTracks() {
        let builder = RecordingAudioMixBuilder()
        let composition = AVMutableComposition()

        let audioMix = builder.makeAudioMix(
            composition: composition,
            microphoneTrackIDs: [],
            systemAudioTrackIDs: [],
            microphoneVolume: 1.0,
            systemAudioVolume: 1.0
        )

        XCTAssertNil(audioMix)
    }
}
