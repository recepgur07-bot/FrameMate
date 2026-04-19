import AVFoundation
import Foundation

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
