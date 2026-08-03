import AppKit
import AVFoundation

protocol SoundEffectPlaying {
    @discardableResult func playCommandReceived() -> TimeInterval
    func playCountdownTick(remaining: Int, total: Int)
    @discardableResult func playStart() -> TimeInterval
    @discardableResult func playStop() -> TimeInterval
    @discardableResult func playPauseResume() -> TimeInterval
    func playElapsedTimeReminder()
}

extension SoundEffectPlaying {
    @discardableResult func playCommandReceived() -> TimeInterval { 0 }
    func playCountdownTick(remaining: Int, total: Int) {}
    @discardableResult func playPauseResume() -> TimeInterval { 0 }
    func playElapsedTimeReminder() {}
}

struct SoundEffectPlayer: SoundEffectPlaying {
    @discardableResult func playCommandReceived() -> TimeInterval {
        play(named: "baslama")
    }

    func playCountdownTick(remaining: Int, total: Int) {
        CountdownTonePlayer.shared.play(remaining: remaining, total: total)
    }

    @discardableResult func playStart() -> TimeInterval {
        play(named: "yeni-ses")
    }

    @discardableResult func playStop() -> TimeInterval {
        play(named: "bitis")
    }

    @discardableResult func playPauseResume() -> TimeInterval {
        play(named: "ara")
    }

    /// A short, non-verbal tick used as an alternative to the spoken elapsed-time
    /// announcement — it does not interrupt VoiceOver output the way speech would.
    func playElapsedTimeReminder() {
        play(named: "sure-hatirlatma")
    }

    private func play(named name: String) -> TimeInterval {
        guard let url = Self.resourceURL(for: name),
              let sound = NSSound(contentsOf: url, byReference: false) else {
            runtimeDebugLog("SoundEffectPlayer missing sound resource: \(name).wav")
            return 0
        }
        SoundPlaybackRetainer.retain(sound)
        sound.play()
        return sound.duration
    }

    static func resourceURL(for name: String, bundle: Bundle = .main) -> URL? {
        if let bundledURL = bundle.url(forResource: name, withExtension: "wav") {
            return bundledURL
        }

        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let developmentURL = sourceRoot
            .appendingPathComponent("Resources/Sounds", isDirectory: true)
            .appendingPathComponent("\(name).wav")

        guard FileManager.default.fileExists(atPath: developmentURL.path) else {
            return nil
        }
        return developmentURL
    }
}

/// A short, nonverbal countdown cue. Its pitch rises toward zero so it remains
/// understandable even when VoiceOver is not speaking the visible countdown.
private final class CountdownTonePlayer {
    static let shared = CountdownTonePlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    // A missing audio format must degrade to a silent countdown, never crash the
    // whole app over a nonessential cue.
    private let format: AVAudioFormat? = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)

    private init() {
        guard let format else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(remaining: Int, total: Int) {
        guard total > 0, let format else { return }
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                runtimeDebugLog("Countdown tone engine could not start: \(error.localizedDescription)")
                return
            }
        }

        let frameCount = AVAudioFrameCount(format.sampleRate * 0.075)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?.pointee else { return }
        buffer.frameLength = frameCount

        let completedSteps = max(0, total - remaining)
        let frequency = 520.0 + Double(completedSteps) * 150.0
        for frame in 0..<Int(frameCount) {
            let progress = Double(frame) / Double(frameCount)
            let envelope = sin(.pi * progress)
            samples[frame] = Float(sin(2 * .pi * frequency * progress * Double(frameCount) / format.sampleRate) * envelope * 0.18)
        }

        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }
}

private enum SoundPlaybackRetainer {
    private static var activeSounds: [NSSound] = []

    static func retain(_ sound: NSSound) {
        DispatchQueue.main.async {
            activeSounds.append(sound)
            let releaseDelay = max(0.5, sound.duration + 0.25)
            DispatchQueue.main.asyncAfter(deadline: .now() + releaseDelay) {
                activeSounds.removeAll { $0 === sound }
            }
        }
    }
}
