// Sources/VideoRecorderApp/RecordingElapsedTimeAnnouncer.swift
import Foundation

/// Periodically notifies the caller of elapsed recording time so blind users
/// always know how long a recording has been running without navigating to the UI.
/// The announcer itself is agnostic to *how* the tick is surfaced (spoken via
/// VoiceOver, a short sound effect, or disabled outright) — that choice belongs
/// to the caller, since it depends on a user-configurable setting.
final class RecordingElapsedTimeAnnouncer {

    private var task: Task<Void, Never>?

    /// Start ticking every `intervalSeconds`. `elapsedProvider` is called on each
    /// tick to get the current elapsed recording duration (pauses excluded);
    /// `onTick` receives that duration and decides how to surface it.
    func start(
        intervalSeconds: Int,
        elapsedProvider: @escaping () -> TimeInterval?,
        onTick: @escaping (TimeInterval) -> Void
    ) {
        stop()
        guard intervalSeconds > 0 else { return }
        task = Task {
            do {
                while true {
                    try await Task.sleep(for: .seconds(intervalSeconds))
                    guard let elapsed = elapsedProvider(), elapsed > 0 else { continue }
                    await MainActor.run {
                        onTick(elapsed)
                    }
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
