import Foundation

struct RecordingComponentResult {
    let value: Result<URL?, Error>
    let warning: String?

    static func microphone(from result: Result<URL, Error>) -> RecordingComponentResult {
        switch result {
        case .success(let url):
            return RecordingComponentResult(value: .success(url), warning: nil)
        case .failure(let error):
            if let microphoneError = error as? MicrophoneAudioRecorderError,
               microphoneError == .emptyRecording {
                return RecordingComponentResult(value: .success(nil), warning: nil)
            }
            return RecordingComponentResult(
                value: .success(nil),
                warning: String(localized: "mikrofon sesi eklenemedi")
            )
        }
    }

    static func systemAudio(from result: Result<URL, Error>) -> RecordingComponentResult {
        switch result {
        case .success(let url):
            return RecordingComponentResult(value: .success(url), warning: nil)
        case .failure(let error):
            if let screenError = error as? ScreenRecordingError,
               screenError == .emptyRecording {
                return RecordingComponentResult(value: .success(nil), warning: nil)
            }
            return RecordingComponentResult(
                value: .success(nil),
                warning: String(localized: "sistem sesi eklenemedi")
            )
        }
    }
}
