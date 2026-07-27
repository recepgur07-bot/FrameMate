import AVFoundation
import CoreMedia
import Foundation

/// The single time base a recording session is expressed in.
///
/// Every component (screen, camera, microphone, system audio) writes its own file and
/// each file's t=0 is that component's own first sample. Session time is defined by the
/// *primary* component's first sample host-clock time, and every pause range and track
/// offset is derived from it, so that one recording is never described by two different
/// clocks (wall-clock uptime at "start pressed" vs. a file's own first-sample PTS).
struct RecordingSessionClock: Equatable {
    /// Host-clock presentation time of the primary component's first sample.
    let sessionZero: CMTime

    /// Converts a host-clock time (as returned by `now()`) into seconds since session
    /// zero. Negative results are clamped to 0: a host time observed before the primary's
    /// first sample arrived (e.g. a pause requested in the brief window after "start" but
    /// before the first frame lands) has no meaningful negative session time.
    func sessionSeconds(at hostTime: CMTime) -> TimeInterval {
        guard hostTime.isValid, sessionZero.isValid else { return 0 }
        return max(0, (hostTime - sessionZero).seconds)
    }

    /// Same as `sessionSeconds(at:)` but without clamping to 0 — used to compute a
    /// *secondary* component's start offset relative to the primary, which can be
    /// negative (the secondary's file began before the primary's first sample, e.g.
    /// system audio started ahead of the camera in camera mode).
    func signedSessionSeconds(at hostTime: CMTime) -> TimeInterval {
        guard hostTime.isValid, sessionZero.isValid else { return 0 }
        return (hostTime - sessionZero).seconds
    }

    static func now() -> CMTime {
        CMClockGetTime(CMClockGetHostTimeClock())
    }
}

struct RecordingPauseRange: Equatable {
    let start: TimeInterval
    let end: TimeInterval

    var duration: TimeInterval {
        max(0, end - start)
    }
}

struct RecordingSegment: Equatable {
    let sourceRange: CMTimeRange
    let destinationStart: CMTime
}

struct RecordingPauseTimeline: Equatable {
    var ranges: [RecordingPauseRange] = []

    var isEmpty: Bool {
        ranges.isEmpty
    }

    var totalPausedDuration: TimeInterval {
        normalizedRanges(clippedTo: ranges.map(\.end).max() ?? 0).reduce(0) { $0 + $1.duration }
    }

    static let empty = RecordingPauseTimeline()

    func segments(for sourceDuration: CMTime) -> [RecordingSegment] {
        guard sourceDuration.isValid,
              sourceDuration.seconds.isFinite,
              sourceDuration > .zero else {
            return []
        }

        let duration = max(0, sourceDuration.seconds)
        let normalizedRanges = normalizedRanges(clippedTo: duration)
        guard !normalizedRanges.isEmpty else {
            return [
                RecordingSegment(
                    sourceRange: CMTimeRange(start: .zero, duration: sourceDuration),
                    destinationStart: .zero
                )
            ]
        }

        var segments: [RecordingSegment] = []
        var sourceCursor: TimeInterval = 0
        var destinationCursor = CMTime.zero

        for range in normalizedRanges {
            if range.start > sourceCursor {
                let segmentDuration = range.start - sourceCursor
                let sourceStart = CMTime(seconds: sourceCursor, preferredTimescale: sourceDuration.timescale)
                let timeRange = CMTimeRange(
                    start: sourceStart,
                    duration: CMTime(seconds: segmentDuration, preferredTimescale: sourceDuration.timescale)
                )
                segments.append(RecordingSegment(sourceRange: timeRange, destinationStart: destinationCursor))
                destinationCursor = destinationCursor + timeRange.duration
            }
            sourceCursor = max(sourceCursor, range.end)
        }

        if sourceCursor < duration {
            let segmentDuration = duration - sourceCursor
            let sourceStart = CMTime(seconds: sourceCursor, preferredTimescale: sourceDuration.timescale)
            let timeRange = CMTimeRange(
                start: sourceStart,
                duration: CMTime(seconds: segmentDuration, preferredTimescale: sourceDuration.timescale)
            )
            segments.append(RecordingSegment(sourceRange: timeRange, destinationStart: destinationCursor))
        }

        return segments
    }

    /// Cuts `sourceDuration` worth of a *secondary* component's own asset using this
    /// (session-time) pause timeline, given that the component's own local time 0 is
    /// `offsetSeconds` after session zero — and places the resulting segments on the same
    /// shared output timeline the primary component (offset 0) uses via `segments(for:)`.
    /// This is the one alignment recipe every export path (screen overlay/microphone/
    /// system-audio, camera's system audio, audio-only's secondary track) uses, so a
    /// secondary component that actually started later or earlier than the primary is cut
    /// and placed correctly instead of assumed to start at the same moment (Phase 3 of the
    /// recording-timing fix).
    func segments(for sourceDuration: CMTime, offsetSeconds: TimeInterval) -> [RecordingSegment] {
        guard sourceDuration.isValid, sourceDuration.seconds.isFinite, sourceDuration > .zero else { return [] }
        guard offsetSeconds != 0 else { return segments(for: sourceDuration) }

        let offsetTime = CMTime(seconds: offsetSeconds, preferredTimescale: sourceDuration.timescale)
        let localSegments = shiftedEarlier(by: offsetSeconds).segments(for: sourceDuration)

        return localSegments.compactMap { segment in
            let destinationStart = segment.destinationStart + offsetTime
            guard destinationStart >= .zero else {
                // This portion of the secondary's content occurred before session zero
                // (the primary's own first sample) and has nowhere valid to land in the
                // shared output timeline; trim it away instead of writing it at an
                // undefined negative position.
                let deficit = CMTime.zero - destinationStart
                guard segment.sourceRange.duration > deficit else { return nil }
                let trimmedSource = CMTimeRange(
                    start: segment.sourceRange.start + deficit,
                    duration: segment.sourceRange.duration - deficit
                )
                return RecordingSegment(sourceRange: trimmedSource, destinationStart: .zero)
            }
            return RecordingSegment(sourceRange: segment.sourceRange, destinationStart: destinationStart)
        }
    }

    /// Re-expresses this timeline in a coordinate system that starts `offsetSeconds`
    /// earlier — i.e. what were session-time pause boundaries become boundaries in a
    /// secondary component's own local (asset) time, given that component's file began
    /// `offsetSeconds` after session zero.
    private func shiftedEarlier(by offsetSeconds: TimeInterval) -> RecordingPauseTimeline {
        RecordingPauseTimeline(ranges: ranges.map {
            RecordingPauseRange(start: $0.start - offsetSeconds, end: $0.end - offsetSeconds)
        })
    }

    func outputDuration(for sourceDuration: CMTime) -> CMTime {
        let segments = segments(for: sourceDuration)
        guard let last = segments.last else { return .zero }
        return last.destinationStart + last.sourceRange.duration
    }

    func shiftedTimestamp(_ timestamp: TimeInterval) -> TimeInterval? {
        guard timestamp >= 0 else { return nil }

        var removedDuration: TimeInterval = 0
        for range in normalizedRanges(clippedTo: max(timestamp, ranges.map(\.end).max() ?? timestamp)) {
            if timestamp >= range.start && timestamp < range.end {
                return nil
            }
            if timestamp >= range.end {
                removedDuration += range.duration
            }
        }

        return max(0, timestamp - removedDuration)
    }

    private func normalizedRanges(clippedTo duration: TimeInterval) -> [RecordingPauseRange] {
        let clipped = ranges
            .map { RecordingPauseRange(start: max(0, $0.start), end: min(duration, max(0, $0.end))) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }

        guard var current = clipped.first else { return [] }

        var merged: [RecordingPauseRange] = []
        for range in clipped.dropFirst() {
            if range.start <= current.end {
                current = RecordingPauseRange(start: current.start, end: max(current.end, range.end))
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)
        return merged
    }
}

extension CursorHighlightTimeline {
    func shifted(by pauseTimeline: RecordingPauseTimeline) -> CursorHighlightTimeline {
        guard !pauseTimeline.isEmpty else { return self }

        return CursorHighlightTimeline(
            samples: samples.compactMap { sample in
                guard let timestamp = pauseTimeline.shiftedTimestamp(sample.timestamp) else { return nil }
                return CursorSample(
                    timestamp: timestamp,
                    normalizedX: sample.normalizedX,
                    normalizedY: sample.normalizedY
                )
            },
            clickEvents: clickEvents.compactMap { click in
                guard let timestamp = pauseTimeline.shiftedTimestamp(click.timestamp) else { return nil }
                return CursorClickEvent(
                    timestamp: timestamp,
                    normalizedX: click.normalizedX,
                    normalizedY: click.normalizedY
                )
            }
        )
    }
}

extension KeyboardShortcutTimeline {
    func shifted(by pauseTimeline: RecordingPauseTimeline) -> KeyboardShortcutTimeline {
        guard !pauseTimeline.isEmpty else { return self }

        return KeyboardShortcutTimeline(
            events: events.compactMap { event in
                guard let timestamp = pauseTimeline.shiftedTimestamp(event.timestamp) else { return nil }
                return KeyboardShortcutEvent(timestamp: timestamp, label: event.label)
            }
        )
    }
}

extension AutoReframeTimeline {
    func shifted(by pauseTimeline: RecordingPauseTimeline) -> AutoReframeTimeline {
        guard !pauseTimeline.isEmpty else { return self }

        var timeline = AutoReframeTimeline()
        for keyframe in keyframes {
            guard let timestamp = pauseTimeline.shiftedTimestamp(keyframe.time.seconds) else { continue }
            timeline.append(
                crop: keyframe.crop,
                at: CMTime(seconds: timestamp, preferredTimescale: keyframe.time.timescale)
            )
        }
        return timeline
    }
}
