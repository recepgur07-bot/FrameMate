import XCTest
@testable import FrameMate

final class QuickHelpContentTests: XCTestCase {
    func testCurrentQuickHelpUsesTurkishForTurkishPreferredLanguage() {
        XCTAssertEqual(
            QuickHelpContent.content(forPreferredLanguage: "tr-TR"),
            .turkish
        )
    }

    func testCurrentQuickHelpUsesEnglishForNonTurkishPreferredLanguage() {
        XCTAssertEqual(
            QuickHelpContent.content(forPreferredLanguage: "en-US"),
            .english
        )
    }

    func testEnglishQuickHelpIncludesGlobalRecordingShortcut() {
        XCTAssertTrue(
            QuickHelpContent.english.topics.values
                .flatMap(\.items)
                .contains(where: { $0.contains("Cmd+Ctrl+R") })
        )
    }

    func testTurkishQuickHelpEmphasizesBlindAndLowVisionSupport() {
        XCTAssertTrue(
            QuickHelpContent.turkish.topics.values
                .flatMap(\.items)
                .contains(where: { $0.localizedCaseInsensitiveContains("kör ve az gören") })
        )
    }

    func testEnglishQuickHelpIncludesTroubleshootingTopic() {
        XCTAssertEqual(
            QuickHelpContent.english.topics[.troubleshooting]?.title,
            "Troubleshooting"
        )
    }

    func testTurkishQuickHelpUsesLocalizedSearchPlaceholder() {
        XCTAssertEqual(
            QuickHelpContent.turkish.searchPlaceholder,
            "Yardımda ara"
        )
    }

    func testTopicsExposeStableSymbolsForTabBar() {
        XCTAssertEqual(QuickHelpTopic.gettingStarted.symbolName, "play.circle.fill")
        XCTAssertEqual(QuickHelpTopic.recording.symbolName, "record.circle.fill")
        XCTAssertEqual(QuickHelpTopic.shortcuts.symbolName, "command.square.fill")
        XCTAssertEqual(QuickHelpTopic.accessibility.symbolName, "figure.roll")
        XCTAssertEqual(QuickHelpTopic.troubleshooting.symbolName, "wrench.and.screwdriver.fill")
    }

    func testEnglishQuickHelpIncludesOnlineHelpActionTitle() {
        XCTAssertEqual(
            QuickHelpContent.english.emptyStateActionTitle,
            "Open Help & Support"
        )
    }
}
