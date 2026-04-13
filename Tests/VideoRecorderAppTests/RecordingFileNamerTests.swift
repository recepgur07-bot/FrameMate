import XCTest
@testable import VideoRecorderApp

final class RecordingFileNamerTests: XCTestCase {
    func testCreatesTimestampedMP4Filename() {
        let baseURL = URL(fileURLWithPath: "/tmp/Movies", isDirectory: true)
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 4,
            day: 7,
            hour: 15,
            minute: 30,
            second: 12
        ))!
        let namer = RecordingFileNamer(moviesDirectory: baseURL)

        let url = namer.recordingURL(for: date)

        XCTAssertEqual(url.lastPathComponent, "recording-20260407-153012.mp4")
        XCTAssertEqual(url.deletingLastPathComponent().path, "/tmp/Movies/Video Recorder")
    }

    func testCreatesTemporaryMovieFilenameForCapture() {
        let baseURL = URL(fileURLWithPath: "/tmp/Movies", isDirectory: true)
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 4,
            day: 7,
            hour: 15,
            minute: 30,
            second: 12
        ))!
        let namer = RecordingFileNamer(moviesDirectory: baseURL)

        let url = namer.temporaryMovieURL(for: date)

        XCTAssertEqual(url.lastPathComponent, "recording-20260407-153012.mov")
        XCTAssertEqual(url.deletingLastPathComponent().path, "/tmp/Movies/Video Recorder")
    }

    func testDefaultOutputDirectoryUsesMoviesVideoRecorder() {
        let homeDirectory = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let namer = RecordingFileNamer(homeDirectory: homeDirectory)

        XCTAssertEqual(namer.outputDirectory.path, "/Users/example/Movies/Video Recorder")
    }

    func testCanUseExplicitOutputDirectory() {
        let outputDirectory = URL(fileURLWithPath: "/tmp/Custom Recordings", isDirectory: true)
        let namer = RecordingFileNamer(outputDirectory: outputDirectory)

        XCTAssertEqual(namer.outputDirectory.path, "/tmp/Custom Recordings")
    }
}
