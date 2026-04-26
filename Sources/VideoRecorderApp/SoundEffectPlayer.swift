import AppKit

protocol SoundEffectPlaying {
    @discardableResult func playCommandReceived() -> TimeInterval
    @discardableResult func playStart() -> TimeInterval
    @discardableResult func playStop() -> TimeInterval
    @discardableResult func playPauseResume() -> TimeInterval
}

extension SoundEffectPlaying {
    @discardableResult func playCommandReceived() -> TimeInterval { 0 }
    @discardableResult func playPauseResume() -> TimeInterval { 0 }
}

struct SoundEffectPlayer: SoundEffectPlaying {
    @discardableResult func playCommandReceived() -> TimeInterval {
        play(named: "yeni-ses")
    }

    @discardableResult func playStart() -> TimeInterval {
        play(named: "baslama")
    }

    @discardableResult func playStop() -> TimeInterval {
        play(named: "bitis")
    }

    @discardableResult func playPauseResume() -> TimeInterval {
        play(named: "ara")
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
