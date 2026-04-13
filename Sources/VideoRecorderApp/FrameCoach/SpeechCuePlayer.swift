import AppKit
import AVFoundation
import Foundation

protocol InstructionSpeaking: AnyObject {
    var isSpeaking: Bool { get }
    func speak(_ text: String)
}

protocol InstructionAnnouncing: AnyObject {
    func announce(_ text: String)
}

final class SystemInstructionSpeaker: NSObject, InstructionSpeaking {
    private let synthesizer = AVSpeechSynthesizer()

    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        let languageCode = Locale.preferredLanguages.first ?? "en-US"
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        utterance.rate = 0.45
        synthesizer.speak(utterance)
    }

}

final class SystemAccessibilityAnnouncer: InstructionAnnouncing {
    func announce(_ text: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(
            element: app,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: text,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}

final class SpeechCuePlayer {
    private let speaker: any InstructionSpeaking
    private let announcer: (any InstructionAnnouncing)?
    private let now: () -> Date
    private let cooldown: TimeInterval
    private let isVoiceOverEnabled: () -> Bool

    private var lastSpokenKey: String?
    private var lastSpokenAt: Date?
    private var lastAnnouncementAt: Date?

    init(
        speaker: any InstructionSpeaking = SystemInstructionSpeaker(),
        announcer: (any InstructionAnnouncing)? = SystemAccessibilityAnnouncer(),
        now: @escaping () -> Date = Date.init,
        cooldown: TimeInterval = 2.5,
        isVoiceOverEnabled: @escaping () -> Bool = SystemAccessibilityAnnouncer.isVoiceOverRunning
    ) {
        self.speaker = speaker
        self.announcer = announcer
        self.now = now
        self.cooldown = cooldown
        self.isVoiceOverEnabled = isVoiceOverEnabled
    }

    convenience init(
        speaker: any InstructionSpeaking = SystemInstructionSpeaker(),
        now: @escaping () -> Date = Date.init,
        cooldown: TimeInterval = 2.5
    ) {
        self.init(
            speaker: speaker,
            announcer: SystemAccessibilityAnnouncer(),
            now: now,
            cooldown: cooldown,
            isVoiceOverEnabled: SystemAccessibilityAnnouncer.isVoiceOverRunning
        )
    }

    func speakIfNeeded(_ instruction: String, isEnabled: Bool, key: String? = nil) {
        let legacySettings = FrameCoachPreferences(
            speechMode: .automatic,
            feedbackFrequency: .balanced,
            repeatInterval: cooldown <= 2 ? .short : (cooldown >= 8 ? .long : .medium),
            showsOnScreenText: true
        )
        speakIfNeeded(instruction, isEnabled: isEnabled, key: key, settings: legacySettings, enforceFrequencyLimit: false)
    }

    func speakIfNeeded(_ instruction: String, isEnabled: Bool, key: String? = nil, settings: FrameCoachPreferences) {
        speakIfNeeded(instruction, isEnabled: isEnabled, key: key, settings: settings, enforceFrequencyLimit: true)
    }

    private func speakIfNeeded(
        _ instruction: String,
        isEnabled: Bool,
        key: String? = nil,
        settings: FrameCoachPreferences,
        enforceFrequencyLimit: Bool
    ) {
        guard isEnabled else { return }

        let currentTime = now()
        let dedupeKey = key ?? instruction
        let route = outputRoute(for: settings.speechMode)

        guard route != .silent else { return }

        if route == .appVoice {
            guard !speaker.isSpeaking else { return }
        }

        if dedupeKey == lastSpokenKey,
           let lastSpokenAt,
           currentTime.timeIntervalSince(lastSpokenAt) < settings.repeatInterval.seconds {
            return
        }

        if enforceFrequencyLimit,
           let lastAnnouncementAt,
           currentTime.timeIntervalSince(lastAnnouncementAt) < settings.feedbackFrequency.minimumInterval {
            return
        }

        if route == .appVoice {
            speaker.speak(instruction)
        } else {
            announcer?.announce(instruction)
        }
        lastSpokenKey = dedupeKey
        lastSpokenAt = currentTime
        lastAnnouncementAt = currentTime
    }

    func reset() {
        lastSpokenKey = nil
        lastSpokenAt = nil
        lastAnnouncementAt = nil
    }

    private func outputRoute(for speechMode: FrameCoachSpeechMode) -> SpeechOutputRoute {
        switch speechMode {
        case .automatic:
            if isVoiceOverEnabled(), announcer != nil {
                return .voiceOver
            }
            return .appVoice
        case .voiceOver:
            return announcer == nil ? .appVoice : .voiceOver
        case .appVoice:
            return .appVoice
        case .silent:
            return .silent
        }
    }
}

private enum SpeechOutputRoute {
    case appVoice
    case voiceOver
    case silent
}

private extension SystemAccessibilityAnnouncer {
    static func isVoiceOverRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == "com.apple.VoiceOver" && !app.isTerminated
        }
    }
}
