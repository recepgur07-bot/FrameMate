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

    func recordingURL(source: RecordingSource, for date: Date = Date()) -> URL {
        let prefix = Self.filePrefix(for: source)
        return outputDirectory.appendingPathComponent("\(prefix) \(Self.timestampFormatter.string(from: date)).mp4")
    }

    func audioRecordingURL(for date: Date = Date()) -> URL {
        outputDirectory.appendingPathComponent("Ses Kaydı \(Self.timestampFormatter.string(from: date)).m4a")
    }

    func temporaryMovieURL(for date: Date = Date()) -> URL {
        outputDirectory.appendingPathComponent("tmp-\(Self.internalTimestampFormatter.string(from: date)).mov")
    }

    func temporaryMovieURL(stem: String, for date: Date = Date()) -> URL {
        outputDirectory.appendingPathComponent("\(stem)-\(Self.internalTimestampFormatter.string(from: date)).mov")
    }

    func temporaryAudioURL(stem: String, for date: Date = Date()) -> URL {
        outputDirectory.appendingPathComponent("\(stem)-\(Self.internalTimestampFormatter.string(from: date)).m4a")
    }

    func ensureOutputDirectoryExists() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    private static func filePrefix(for source: RecordingSource) -> String {
        switch source {
        case .camera: return "Kamera Kaydı"
        case .screen: return "Ekran Kaydı"
        case .window: return "Pencere Kaydı"
        case .audio:  return "Ses Kaydı"
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "dd.MM.yyyy HH.mm"
        return formatter
    }()

    private static let internalTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
