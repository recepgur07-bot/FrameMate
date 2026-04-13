import AppKit
import XCTest
@testable import VideoRecorderApp

final class KeyboardShortcutFormatterTests: XCTestCase {
    func testFormatsCommandShortcutIntoDisplayLabel() {
        let label = KeyboardShortcutFormatter.label(
            charactersIgnoringModifiers: "k",
            keyCode: 40,
            modifiers: [.command]
        )

        XCTAssertEqual(label, "⌘ K")
    }

    func testIgnoresPlainTypingWithoutShortcutModifiers() {
        let label = KeyboardShortcutFormatter.label(
            charactersIgnoringModifiers: "a",
            keyCode: 0,
            modifiers: []
        )

        XCTAssertNil(label)
    }
}
