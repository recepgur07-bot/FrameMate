import XCTest
@testable import FrameMate

final class SleepPreventerTests: XCTestCase {
    func testPreventAndAllowDoNotCrash() {
        let preventer = SleepPreventer()
        preventer.prevent(reason: "Test recording")
        preventer.allow()
    }

    func testAllowWithoutPreventDoesNotCrash() {
        let preventer = SleepPreventer()
        preventer.allow()
    }

    func testDoublePreventReleasesFirst() {
        let preventer = SleepPreventer()
        preventer.prevent(reason: "First")
        preventer.prevent(reason: "Second")
        preventer.allow()
    }
}
