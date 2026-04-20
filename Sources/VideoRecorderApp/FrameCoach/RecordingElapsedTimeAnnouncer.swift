// Sources/VideoRecorderApp/RecordingElapsedTimeAnnouncer.swift
import AppKit
import Foundation

/// Periodically announces elapsed recording time via VoiceOver so blind users
/// always know how long a recording has been running without navigating to the UI.
final class RecordingElapsedTimeAnnouncer {

    private var task: Task<Void, Never>?
    private let intervalSeconds: Int

    init(intervalSeconds: Int = 30) {
        self.intervalSeconds = intervalSeconds
    }

    /// Start announcing. `elapsedProvider` is called on each tick to get the
    /// current elapsed recording duration (pauses excluded).
    func start(elapsedProvider: @escaping () -> TimeInterval?) {
        stop()
        task = Task { [intervalSeconds] in
            do {
                while true {
                    try await Task.sleep(for: .seconds(intervalSeconds))
                    guard let elapsed = elapsedProvider(), elapsed > 0 else { continue }
                    let minutes = Int(elapsed) / 60
                    let seconds = Int(elapsed) % 60
                    let text: String
                    if minutes > 0 {
                        text = String(localized: "Kayıt süresi: \(minutes) dakika \(seconds) saniye")
                    } else {
                        text = String(localized: "Kayıt süresi: \(seconds) saniye")
                    }
                    NSAccessibility.post(
                        element: NSApp as Any,
                        notification: .announcementRequested,
                        userInfo: [
                            NSAccessibility.NotificationUserInfoKey.announcement: text,
                            NSAccessibility.NotificationUserInfoKey.priority:
                                NSAccessibilityPriorityLevel.medium.rawValue
                        ]
                    )
                }
            } catch {
                // Cancelled when stop() is called — normal
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
