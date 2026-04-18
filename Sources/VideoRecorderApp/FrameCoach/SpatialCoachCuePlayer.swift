import AVFoundation
import Foundation

protocol SpatialCuePlaying: AnyObject {
    func play(_ cue: FrameCoachSpatialCue, preferences: FrameCoachPreferences)
    func reset()
}

final class SilentSpatialCuePlayer: SpatialCuePlaying {
    func play(_ cue: FrameCoachSpatialCue, preferences: FrameCoachPreferences) {}
    func reset() {}
}

final class SpatialCoachCuePlayer: SpatialCuePlaying {
    private let engine = AVAudioEngine()
    private let stateLock = NSLock()
    private let sampleRate: Double = 44_100

    private var sourceNode: AVAudioSourceNode?
    private var activeCue: FrameCoachSpatialCue?
    private var activePreferences = FrameCoachPreferences.default
    private var phase: Double = 0
    private var pulsePhase: Double = 0

    init() {
        configureEngineIfNeeded()
    }

    convenience init(now: @escaping () -> Date) {
        self.init()
    }

    func play(_ cue: FrameCoachSpatialCue, preferences: FrameCoachPreferences) {
        guard preferences.spatialAudioMode != .off else {
            reset()
            return
        }
        guard preferences.playsCenterConfirmation || !cue.confirmsCentered else {
            reset()
            return
        }

        configureEngineIfNeeded()

        stateLock.lock()
        activeCue = cue
        activePreferences = preferences
        stateLock.unlock()

        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            runtimeDebugLog("SpatialCoachCuePlayer could not start engine: \(error.localizedDescription)")
        }
    }

    func reset() {
        stateLock.lock()
        activeCue = nil
        pulsePhase = 0
        stateLock.unlock()
    }

    private func configureEngineIfNeeded() {
        guard sourceNode == nil else { return }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }

            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let cueSnapshot: FrameCoachSpatialCue?
            self.stateLock.lock()
            cueSnapshot = self.activeCue
            self.stateLock.unlock()

            guard let cue = cueSnapshot else {
                for buffer in ablPointer {
                    guard let channelData = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    for frame in 0..<Int(frameCount) {
                        channelData[frame] = 0
                    }
                }
                return noErr
            }

            let channelCount = ablPointer.count
            let amplitude = self.amplitude(for: cue)
            let pulseSpeed = self.pulseSpeed(for: cue)
            let baseFrequency = self.baseFrequency(for: cue)
            let modulationDepth = self.modulationDepth(for: cue)

            for frame in 0..<Int(frameCount) {
                let pulseValue = self.pulseValue(for: cue, speed: pulseSpeed)
                let progress = (sin(self.pulsePhase) + 1) * 0.5
                let frequency = self.instantaneousFrequency(
                    for: cue,
                    baseFrequency: baseFrequency,
                    progress: progress,
                    modulationDepth: modulationDepth
                )

                let sample = Float(sin(self.phase) * amplitude * pulseValue)
                let (leftGain, rightGain) = self.channelGains(for: cue, progress: progress)

                if channelCount > 0, let left = ablPointer[0].mData?.assumingMemoryBound(to: Float.self) {
                    left[frame] = sample * leftGain
                }
                if channelCount > 1, let right = ablPointer[1].mData?.assumingMemoryBound(to: Float.self) {
                    right[frame] = sample * rightGain
                }
                if channelCount > 2 {
                    for channelIndex in 2..<channelCount {
                        if let channel = ablPointer[channelIndex].mData?.assumingMemoryBound(to: Float.self) {
                            channel[frame] = sample * 0.35
                        }
                    }
                }

                self.phase += 2.0 * .pi * frequency / self.sampleRate
                if self.phase >= 2.0 * .pi {
                    self.phase.formTruncatingRemainder(dividingBy: 2.0 * .pi)
                }

                self.pulsePhase += 2.0 * .pi * pulseSpeed / self.sampleRate
                if self.pulsePhase >= 2.0 * .pi {
                    self.pulsePhase.formTruncatingRemainder(dividingBy: 2.0 * .pi)
                }
            }

            return noErr
        }

        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9
    }

    private func baseFrequency(for cue: FrameCoachSpatialCue) -> Double {
        switch cue.direction {
        case .left, .right:
            return cue.severity == .strong ? 210 : 340
        case .up:
            return cue.severity == .strong ? 460 : 620
        case .down:
            return cue.severity == .strong ? 190 : 280
        case .center:
            return 740
        }
    }

    private func instantaneousFrequency(
        for cue: FrameCoachSpatialCue,
        baseFrequency: Double,
        progress: Double,
        modulationDepth: Double
    ) -> Double {
        switch cue.direction {
        case .left, .right:
            return baseFrequency + (sin(pulsePhase * 0.5) * modulationDepth)
        case .up:
            return baseFrequency + (progress * modulationDepth)
        case .down:
            return baseFrequency - (progress * modulationDepth)
        case .center:
            return baseFrequency + (sin(pulsePhase * 2.0) * 10)
        }
    }

    private func amplitude(for cue: FrameCoachSpatialCue) -> Double {
        if cue.confirmsCentered {
            return 0.08
        }
        switch cue.severity {
        case .strong:
            return 0.24
        case .mild:
            return 0.15
        }
    }

    private func pulseSpeed(for cue: FrameCoachSpatialCue) -> Double {
        if cue.confirmsCentered {
            return 1.2
        }
        switch cue.severity {
        case .strong:
            return 4.0
        case .mild:
            return 2.2
        }
    }

    private func modulationDepth(for cue: FrameCoachSpatialCue) -> Double {
        switch cue.direction {
        case .left, .right:
            return cue.severity == .strong ? 22 : 14
        case .up, .down:
            return cue.severity == .strong ? 210 : 130
        case .center:
            return 0
        }
    }

    private func pulseValue(for cue: FrameCoachSpatialCue, speed: Double) -> Double {
        let raw = (sin(pulsePhase) + 1) * 0.5
        switch cue.direction {
        case .center:
            return 0.35 + raw * 0.25
        case .left, .right:
            let shaped = pow(raw, cue.severity == .strong ? 0.55 : 0.8)
            return 0.25 + shaped * 0.95
        case .up, .down:
            let triangle = abs(((pulsePhase / (2.0 * .pi) * speed).truncatingRemainder(dividingBy: 1.0)) - 0.5) * 2.0
            return 0.25 + (1.0 - triangle) * 0.85
        }
    }

    private func channelGains(for cue: FrameCoachSpatialCue, progress: Double) -> (Float, Float) {
        switch cue.direction {
        case .left:
            return (1.0, cue.severity == .strong ? 0.0 : 0.08)
        case .right:
            return (cue.severity == .strong ? 0.0 : 0.08, 1.0)
        case .up:
            let gain = Float(0.42 + progress * 0.42)
            return (gain, gain)
        case .down:
            let gain = Float(0.86 - progress * 0.34)
            return (gain, gain)
        case .center:
            return (0.34, 0.34)
        }
    }
}
