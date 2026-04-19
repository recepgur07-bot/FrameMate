import XCTest
@testable import FrameMate

final class RecordingFileNamerTests: XCTestCase {
    func testCreatesReadableMP4FilenameWithModePrefix() {
        let baseURL = URL(fileURLWithPath: "/tmp/Movies", isDirectory: true)
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(
            timeZone: TimeZone.current,
            year: 2026,
            month: 4,
            day: 7,
            hour: 15,
            minute: 30,
            second: 12
        ))!
        let namer = RecordingFileNamer(moviesDirectory: baseURL)

        let cameraURL = namer.recordingURL(source: .camera, for: date)
        let screenURL = namer.recordingURL(source: .screen, for: date)
        let windowURL = namer.recordingURL(source: .window, for: date)

        XCTAssertTrue(cameraURL.lastPathComponent.hasPrefix("Kamera Kaydı "))
        XCTAssertTrue(screenURL.lastPathComponent.hasPrefix("Ekran Kaydı "))
        XCTAssertTrue(windowURL.lastPathComponent.hasPrefix("Pencere Kaydı "))
        XCTAssertTrue(cameraURL.lastPathComponent.hasSuffix(".mp4"))
        XCTAssertEqual(cameraURL.deletingLastPathComponent().path, "/tmp/Movies/Video Recorder")
    }

    func testCreatesReadableAudioFilenameWithPrefix() {
        let baseURL = URL(fileURLWithPath: "/tmp/Movies", isDirectory: true)
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(
            timeZone: TimeZone.current,
            year: 2026,
            month: 4,
            day: 7,
            hour: 15,
            minute: 30,
            second: 12
        ))!
        let namer = RecordingFileNamer(moviesDirectory: baseURL)

        let url = namer.audioRecordingURL(for: date)

        XCTAssertTrue(url.lastPathComponent.hasPrefix("Ses Kaydı "))
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".m4a"))
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

        XCTAssertTrue(url.lastPathComponent.hasPrefix("tmp-"))
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".mov"))
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
