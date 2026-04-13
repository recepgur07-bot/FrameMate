import Foundation

struct RecordingFileNamer {
    let outputDirectory: URL

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    init(moviesDirectory: URL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]) {
        outputDirectory = moviesDirectory.appendingPathComponent("Video Recorder", isDirectory: true)
    }

    init(homeDirectory: URL) {
        let moviesDirectory = homeDirectory.appendingPathComponent("Movies", isDirectory: true)
        outputDirectory = moviesDirectory.appendingPathComponent("Video Recorder", isDirectory: true)
    }

    func recordingURL(for date: Date = Date()) -> URL {
        outputDirectory.appendingPathComponent("recording-\(Self.timestampFormatter.string(from: date)).mp4")
    }

    func audioRecordingURL(for date: Date = Date()) -> URL {
        outputDirectory.appendingPathComponent("audio-\(Self.timestampFormatter.string(from: date)).m4a")
    }

    func temporaryMovieURL(for date: Date = Date()) -> URL {
        outputDirectory.appendingPathComponent("recording-\(Self.timestampFormatter.string(from: date)).mov")
    }

    func temporaryMovieURL(stem: String, for date: Date = Date()) -> URL {
        outputDirectory.appendingPathComponent("\(stem)-\(Self.timestampFormatter.string(from: date)).mov")
    }

    func temporaryAudioURL(stem: String, for date: Date = Date()) -> URL {
        outputDirectory.appendingPathComponent("\(stem)-\(Self.timestampFormatter.string(from: date)).m4a")
    }

    func ensureOutputDirectoryExists() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
