import AppKit
import Foundation

protocol CursorHighlightRecordingProviding: AnyObject {
    func startTracking(targetFrame: CGRect)
    func stopTracking() -> CursorHighlightTimeline
}

final class CursorHighlightRecorder: CursorHighlightRecordingProviding {
    private var targetFrame: CGRect = .zero
    private var samples: [CursorSample] = []
    private var clicks: [CursorClickEvent] = []
    private var timer: Timer?
    private var startTime: TimeInterval = 0
    private var clickMonitors: [Any] = []

    func startTracking(targetFrame: CGRect) {
        _ = stopTracking()

        guard targetFrame.width > 0, targetFrame.height > 0 else { return }

        self.targetFrame = targetFrame
        startTime = ProcessInfo.processInfo.systemUptime
        samples = []
        clicks = []

        captureSample()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.captureSample()
        }

        let eventTypes: [NSEvent.EventTypeMask] = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        clickMonitors = eventTypes.compactMap { type in
            NSEvent.addGlobalMonitorForEvents(matching: type) { [weak self] _ in
                self?.captureClick()
            }
        }
    }

    func stopTracking() -> CursorHighlightTimeline {
        timer?.invalidate()
        timer = nil

        for monitor in clickMonitors {
            NSEvent.removeMonitor(monitor)
        }
        clickMonitors.removeAll()

        defer {
            targetFrame = .zero
            startTime = 0
            samples = []
            clicks = []
        }

        return CursorHighlightTimeline(samples: samples, clickEvents: clicks)
    }

    private func captureSample() {
        guard let normalized = normalizedPoint(for: NSEvent.mouseLocation) else { return }
        let timestamp = ProcessInfo.processInfo.systemUptime - startTime
        let sample = CursorSample(timestamp: timestamp, normalizedX: normalized.x, normalizedY: normalized.y)

        if let last = samples.last,
           abs(last.normalizedX - sample.normalizedX) < 0.0005,
           abs(last.normalizedY - sample.normalizedY) < 0.0005 {
            return
        }

        samples.append(sample)
    }

    private func captureClick() {
        guard let normalized = normalizedPoint(for: NSEvent.mouseLocation) else { return }
        let timestamp = ProcessInfo.processInfo.systemUptime - startTime
        clicks.append(
            CursorClickEvent(
                timestamp: timestamp,
                normalizedX: normalized.x,
                normalizedY: normalized.y
            )
        )
    }

    private func normalizedPoint(for location: CGPoint) -> CGPoint? {
        guard targetFrame.width > 0, targetFrame.height > 0 else { return nil }
        guard targetFrame.contains(location) else { return nil }

        return CGPoint(
            x: (location.x - targetFrame.minX) / targetFrame.width,
            y: (location.y - targetFrame.minY) / targetFrame.height
        )
    }
}
