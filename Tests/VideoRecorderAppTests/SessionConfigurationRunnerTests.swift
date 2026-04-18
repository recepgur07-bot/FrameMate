import XCTest
@testable import FrameMate

final class SessionConfigurationRunnerTests: XCTestCase {
    func testRunnerCommitsBeforeStartingSession() throws {
        let session = SessionLifecycleSpy()

        try SessionConfigurationRunner.configureAndStartIfNeeded(session: session) {
            session.events.append("configure")
        }

        XCTAssertEqual(session.events, ["begin", "configure", "commit", "start"])
    }

    func testRunnerDoesNotStartWhenSessionIsAlreadyRunning() throws {
        let session = SessionLifecycleSpy()
        session.isRunning = true

        try SessionConfigurationRunner.configureAndStartIfNeeded(session: session) {
            session.events.append("configure")
        }

        XCTAssertEqual(session.events, ["begin", "configure", "commit"])
    }

    func testRunnerStillCommitsWhenConfigurationThrows() {
        let session = SessionLifecycleSpy()

        XCTAssertThrowsError(
            try SessionConfigurationRunner.configureAndStartIfNeeded(session: session) {
                session.events.append("configure")
                throw SessionConfigurationTestError.boom
            }
        )

        XCTAssertEqual(session.events, ["begin", "configure", "commit"])
    }
}

private enum SessionConfigurationTestError: Error {
    case boom
}

private final class SessionLifecycleSpy: SessionLifecycleControlling {
    var isRunning = false
    var events: [String] = []

    func beginConfiguration() {
        events.append("begin")
    }

    func commitConfiguration() {
        events.append("commit")
    }

    func startRunning() {
        events.append("start")
        isRunning = true
    }
}
