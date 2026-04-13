import AVFoundation
import Foundation

struct RecordingAudioMixBuilder {
    func makeAudioMix(
        composition: AVComposition,
        microphoneTrackIDs: [CMPersistentTrackID],
        systemAudioTrackIDs: [CMPersistentTrackID],
        microphoneVolume: Float,
        systemAudioVolume: Float
    ) -> AVMutableAudioMix? {
        let trackIDs = Set(microphoneTrackIDs + systemAudioTrackIDs)
        guard !trackIDs.isEmpty else { return nil }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = trackIDs.compactMap { trackID in
            guard let track = composition.track(withTrackID: trackID) else {
                return nil
            }

            let parameters = AVMutableAudioMixInputParameters(track: track)
            if microphoneTrackIDs.contains(trackID) {
                parameters.setVolume(microphoneVolume, at: .zero)
            } else {
                parameters.setVolume(systemAudioVolume, at: .zero)
            }
            return parameters
        }
        return audioMix
    }
}
