import XCTest
@testable import FrameMate

final class SpeechCuePlayerTests: XCTestCase {
    func testSpeaksFirstInstruction() {
        let speaker = SpeechInstructionSpeakerStub()
        let now = Date(timeIntervalSince1970: 1_000)
        let player = SpeechCuePlayer(
            speaker: speaker,
            announcer: nil,
            now: { now },
            cooldown: 2,
            isVoiceOverEnabled: { false }
        )

        player.speakIfNeeded("Biraz sola", isEnabled: true)

        XCTAssertEqual(speaker.spokenTexts, ["Biraz sola"])
    }

    func testSuppressesRepeatedInstructionDuringCooldown() {
        let speaker = SpeechInstructionSpeakerStub()
        var now = Date(timeIntervalSince1970: 1_000)
        let player = SpeechCuePlayer(
            speaker: speaker,
            announcer: nil,
            now: { now },
            cooldown: 5,
            isVoiceOverEnabled: { false }
        )

        player.speakIfNeeded("Biraz sola", isEnabled: true)
        now = now.addingTimeInterval(2)
        player.speakIfNeeded("Biraz sola", isEnabled: true)

        XCTAssertEqual(speaker.spokenTexts, ["Biraz sola"])
    }

    func testSpeaksChangedInstructionImmediately() {
        let speaker = SpeechInstructionSpeakerStub()
        let player = SpeechCuePlayer(
            speaker: speaker,
            announcer: nil,
            now: { Date(timeIntervalSince1970: 1_000) },
            cooldown: 5,
            isVoiceOverEnabled: { false }
        )

        player.speakIfNeeded("Biraz sola", isEnabled: true)
        player.speakIfNeeded("Kamerayı biraz aşağı indir", isEnabled: true)

        XCTAssertEqual(
            speaker.spokenTexts,
            ["Biraz sola", "Kamerayı biraz aşağı indir"]
        )
    }

    func testDisabledCoachPreventsSpeech() {
        let speaker = SpeechInstructionSpeakerStub()
        let player = SpeechCuePlayer(speaker: speaker, announcer: nil, isVoiceOverEnabled: { false })

        player.speakIfNeeded("Biraz sola", isEnabled: false)

        XCTAssertTrue(speaker.spokenTexts.isEmpty)
    }

    func testSuppressesInstructionWhileSpeakerIsStillSpeaking() {
        let speaker = SpeechInstructionSpeakerStub()
        speaker.isSpeaking = true
        let player = SpeechCuePlayer(speaker: speaker, announcer: nil, isVoiceOverEnabled: { false })

        player.speakIfNeeded("Biraz sola", isEnabled: true)

        XCTAssertTrue(speaker.spokenTexts.isEmpty)
    }

    func testSuppressesRepeatWhenSameGuidanceUsesSameKey() {
        let speaker = SpeechInstructionSpeakerStub()
        var now = Date(timeIntervalSince1970: 1_000)
        let player = SpeechCuePlayer(
            speaker: speaker,
            announcer: nil,
            now: { now },
            cooldown: 5,
            isVoiceOverEnabled: { false }
        )

        player.speakIfNeeded(
            "Bir kişi görünüyor. Kadraj çok yakın, biraz uzaklaş ve omuzlarınla göğüs hizan da görünsün",
            isEnabled: true,
            key: "Kadraj çok yakın, biraz uzaklaş ve omuzlarınla göğüs hizan da görünsün"
        )
        now = now.addingTimeInterval(1)
        player.speakIfNeeded(
            "Kadraj çok yakın, biraz uzaklaş ve omuzlarınla göğüs hizan da görünsün",
            isEnabled: true,
            key: "Kadraj çok yakın, biraz uzaklaş ve omuzlarınla göğüs hizan da görünsün"
        )

        XCTAssertEqual(
            speaker.spokenTexts,
            ["Bir kişi görünüyor. Kadraj çok yakın, biraz uzaklaş ve omuzlarınla göğüs hizan da görünsün"]
        )
    }

    func testUsesAccessibilityAnnouncementWhenVoiceOverIsRunning() {
        let speaker = SpeechInstructionSpeakerStub()
        let announcer = AccessibilityAnnouncerSpy()
        let player = SpeechCuePlayer(
            speaker: speaker,
            announcer: announcer,
            isVoiceOverEnabled: { true }
        )

        player.speakIfNeeded("Biraz sola", isEnabled: true)

        XCTAssertTrue(speaker.spokenTexts.isEmpty)
        XCTAssertEqual(announcer.announcements, ["Biraz sola"])
    }

    func testUsesAppVoiceWhenSpeechModeRequiresItEvenIfVoiceOverIsRunning() {
        let speaker = SpeechInstructionSpeakerStub()
        let announcer = AccessibilityAnnouncerSpy()
        let player = SpeechCuePlayer(
            speaker: speaker,
            announcer: announcer,
            isVoiceOverEnabled: { true }
        )

        player.speakIfNeeded(
            "Biraz sola",
            isEnabled: true,
            settings: FrameCoachPreferences(speechMode: .appVoice, feedbackFrequency: .balanced, repeatInterval: .medium, showsOnScreenText: true, spatialAudioMode: .off, playsCenterConfirmation: true)
        )

        XCTAssertEqual(speaker.spokenTexts, ["Biraz sola"])
        XCTAssertTrue(announcer.announcements.isEmpty)
    }

    func testSilentSpeechModeSuppressesAllAnnouncements() {
        let speaker = SpeechInstructionSpeakerStub()
        let announcer = AccessibilityAnnouncerSpy()
        let player = SpeechCuePlayer(
            speaker: speaker,
            announcer: announcer,
            isVoiceOverEnabled: { true }
        )

        player.speakIfNeeded(
            "Biraz sola",
            isEnabled: true,
            settings: FrameCoachPreferences(speechMode: .silent, feedbackFrequency: .balanced, repeatInterval: .medium, showsOnScreenText: true, spatialAudioMode: .off, playsCenterConfirmation: true)
        )

        XCTAssertTrue(speaker.spokenTexts.isEmpty)
        XCTAssertTrue(announcer.announcements.isEmpty)
    }

    func testSuppressesRepeatedAnnouncementDuringCooldownWhenVoiceOverIsRunning() {
        let speaker = SpeechInstructionSpeakerStub()
        let announcer = AccessibilityAnnouncerSpy()
        var now = Date(timeIntervalSince1970: 1_000)
        let player = SpeechCuePlayer(
            speaker: speaker,
            announcer: announcer,
            now: { now },
            cooldown: 5,
            isVoiceOverEnabled: { true }
        )

        player.speakIfNeeded("Biraz sola", isEnabled: true)
        now = now.addingTimeInterval(1)
        player.speakIfNeeded("Biraz sola", isEnabled: true)

        XCTAssertTrue(speaker.spokenTexts.isEmpty)
        XCTAssertEqual(announcer.announcements, ["Biraz sola"])
    }

    func testFeedbackFrequencySuppressesDifferentAnnouncementsUntilMinimumIntervalPasses() {
        let speaker = SpeechInstructionSpeakerStub()
        let announcer = AccessibilityAnnouncerSpy()
        var now = Date(timeIntervalSince1970: 1_000)
        let player = SpeechCuePlayer(
            speaker: speaker,
            announcer: announcer,
            now: { now },
            isVoiceOverEnabled: { false }
        )

        let settings = FrameCoachPreferences(
            speechMode: .appVoice,
            feedbackFrequency: .minimal,
            repeatInterval: .short,
            showsOnScreenText: true,
            spatialAudioMode: .off,
            playsCenterConfirmation: true
        )

        player.speakIfNeeded("Biraz sola", isEnabled: true, settings: settings)
        now = now.addingTimeInterval(1)
        player.speakIfNeeded("Biraz sağa", isEnabled: true, settings: settings)
        now = now.addingTimeInterval(2.5)
        player.speakIfNeeded("Biraz sağa", isEnabled: true, settings: settings)

        XCTAssertTrue(announcer.announcements.isEmpty)
        XCTAssertEqual(speaker.spokenTexts, ["Biraz sola", "Biraz sağa"])
    }
}

private final class SpeechInstructionSpeakerStub: InstructionSpeaking {
    private(set) var spokenTexts: [String] = []
    var isSpeaking = false

    func speak(_ text: String) {
        spokenTexts.append(text)
    }
}

private final class AccessibilityAnnouncerSpy: InstructionAnnouncing {
    private(set) var announcements: [String] = []

    func announce(_ text: String) {
        announcements.append(text)
    }
}
