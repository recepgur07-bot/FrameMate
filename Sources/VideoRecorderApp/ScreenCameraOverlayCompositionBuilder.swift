@preconcurrency import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import QuartzCore

struct ScreenCameraOverlayComposition {
    let composition: AVMutableComposition
    let videoComposition: AVMutableVideoComposition
    let audioMix: AVAudioMix?
}

final class ScreenCameraOverlayCompositionBuilder {
    private let audioMixBuilder = RecordingAudioMixBuilder()

    func makeComposition(
        screenAsset: AVAsset,
        mode: RecordingMode,
        overlayAsset: AVAsset? = nil,
        position: ScreenCameraOverlayPosition = .bottomRight,
        overlaySize: ScreenCameraOverlaySize = .medium,
        cursorTimeline: CursorHighlightTimeline = .empty,
        keyboardShortcutTimeline: KeyboardShortcutTimeline = .empty,
        microphoneAsset: AVAsset? = nil,
        systemAudioAsset: AVAsset? = nil,
        microphoneVolume: Float = 1.0,
        systemAudioVolume: Float = 1.0,
        pauseTimeline: RecordingPauseTimeline = .empty,
        overlayOffsetSeconds: TimeInterval = 0,
        microphoneOffsetSeconds: TimeInterval = 0,
        systemAudioOffsetSeconds: TimeInterval = 0
    ) async throws -> ScreenCameraOverlayComposition {
        guard let screenVideoTrack = try await screenAsset.loadTracks(withMediaType: .video).first else {
            throw CaptureRecorderError.cannotExportMP4
        }

        let overlayVideoTrack: AVAssetTrack?
        if let overlayAsset {
            overlayVideoTrack = try await overlayAsset.loadTracks(withMediaType: .video).first
        } else {
            overlayVideoTrack = nil
        }

        let composition = AVMutableComposition()
        guard let screenCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CaptureRecorderError.cannotExportMP4
        }

        let overlayCompositionTrack = overlayVideoTrack == nil
            ? nil
            : composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)

        let screenDuration = try await screenAsset.load(.duration)
        let screenSegments = pauseTimeline.segments(for: screenDuration)
        guard !screenSegments.isEmpty else {
            throw CaptureRecorderError.cannotExportMP4
        }
        let visibleScreenDuration = pauseTimeline.outputDuration(for: screenDuration)
        try insertSegments(screenSegments, of: screenVideoTrack, into: screenCompositionTrack)

        // The screen capture is the primary component: the exported movie must end exactly
        // when the (pause-trimmed) screen content ends. Every secondary track — camera
        // overlay, microphone, system audio — is clamped to that end when inserted. The
        // camera overlay in particular reliably outlives the screen file (it starts later
        // because of its warm-up gate, positive offset, and stops later because of its
        // writer drain), and an overlay video track extending past the last video
        // composition instruction makes the whole composition invalid: AVAssetExportSession
        // then fails with AVErrorInvalidVideoComposition (-11841, "video could not be
        // composed") and the user loses the camera layer.
        if let overlayAsset, let overlayVideoTrack, let overlayCompositionTrack {
            let overlayDuration = try await overlayAsset.load(.duration)
            try insertSegments(
                pauseTimeline.segments(for: overlayDuration, offsetSeconds: overlayOffsetSeconds),
                of: overlayVideoTrack,
                into: overlayCompositionTrack,
                clampedTo: visibleScreenDuration
            )
        }

        var systemTrackIDs: [CMPersistentTrackID] = []
        let systemAudioSource = systemAudioAsset ?? screenAsset
        let systemAudioDuration = try await systemAudioSource.load(.duration)
        let systemInsertDuration = CMTimeMinimum(screenDuration, systemAudioDuration)
        if systemInsertDuration > .zero {
            for audioTrack in try await systemAudioSource.loadTracks(withMediaType: .audio) {
                if let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    try insertSegments(
                        pauseTimeline.segments(for: systemInsertDuration, offsetSeconds: systemAudioOffsetSeconds),
                        of: audioTrack,
                        into: audioCompositionTrack,
                        clampedTo: visibleScreenDuration
                    )
                    systemTrackIDs.append(audioCompositionTrack.trackID)
                }
            }
        }

        var microphoneTrackIDs: [CMPersistentTrackID] = []
        if let microphoneAsset {
            let microphoneDuration = try await microphoneAsset.load(.duration)
            let insertDuration = CMTimeMinimum(screenDuration, microphoneDuration)

            if insertDuration > .zero {
                for audioTrack in try await microphoneAsset.loadTracks(withMediaType: .audio) {
                    if let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                        try insertSegments(
                            pauseTimeline.segments(for: insertDuration, offsetSeconds: microphoneOffsetSeconds),
                            of: audioTrack,
                            into: audioCompositionTrack,
                            clampedTo: visibleScreenDuration
                        )
                        microphoneTrackIDs.append(audioCompositionTrack.trackID)
                    }
                }
            }
        }

        let renderSize = targetRenderSize(for: mode)
        let screenSourceSize = try await orientedSize(for: screenVideoTrack)
        // Vertical screen: fill the portrait canvas by cropping the landscape source (no black bands).
        // Horizontal screen: fit the content (no cropping — full screen visible).
        let screenFrame: CGRect
        if mode == .vertical1080p {
            screenFrame = filledVideoFrame(contentSize: screenSourceSize, in: renderSize)
        } else {
            screenFrame = fittedVideoFrame(contentSize: screenSourceSize, in: renderSize)
        }
        let normalizedScreenTransform = try await normalizedTransform(for: screenVideoTrack)

        let screenInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: screenCompositionTrack)
        let screenScale = min(
            screenFrame.width / max(screenSourceSize.width, 1),
            screenFrame.height / max(screenSourceSize.height, 1)
        )
        var screenTransform = normalizedScreenTransform
        screenTransform = screenTransform.concatenating(CGAffineTransform(scaleX: screenScale, y: screenScale))
        screenTransform = screenTransform.concatenating(
            CGAffineTransform(translationX: screenFrame.minX, y: screenFrame.minY)
        )
        screenInstruction.setTransform(screenTransform, at: .zero)

        // A secondary component whose entire content was clamped away (it only started
        // after the screen content already ended) leaves a segmentless track behind;
        // drop it — and any audio-mix reference to it — rather than exporting an empty
        // track.
        for track in composition.tracks where track.segments.isEmpty {
            composition.removeTrack(track)
        }
        let remainingTrackIDs = Set(composition.tracks.map(\.trackID))
        systemTrackIDs = systemTrackIDs.filter(remainingTrackIDs.contains)
        microphoneTrackIDs = microphoneTrackIDs.filter(remainingTrackIDs.contains)

        // Instruction coverage is derived from the composition tracks' *actual* inserted
        // ranges, not from the pre-computed second-based durations: `insertTimeRange` may
        // land on media sample boundaries, and AVFoundation requires the instruction list
        // to be gapless from zero through the very end of the composition (every track
        // included). Any uncovered tail — even a few milliseconds of overlay video or
        // audio past the last instruction — invalidates the whole video composition
        // (AVErrorInvalidVideoComposition, -11841).
        var compositionEnd = screenCompositionTrack.timeRange.end
        for track in composition.tracks where track.timeRange.end.isNumeric {
            compositionEnd = CMTimeMaximum(compositionEnd, track.timeRange.end)
        }

        // The overlay only participates where its track actually has media. Referencing
        // it before its first frame (it starts later than the screen because of its
        // warm-up gate) or after its last frame would be exactly the mismatch described
        // above, so the timeline is split into screen-only head / overlay+screen middle /
        // screen-only tail instructions as needed.
        var overlayRenderRange: CMTimeRange?
        if let overlayCompositionTrack {
            // Actual media coverage, excluding the explicit empty head range that holds
            // the overlay's start offset open — the overlay layer must only be
            // referenced where real camera frames exist.
            let mediaSegments = overlayCompositionTrack.segments.filter { !$0.isEmpty }
            if let firstSegment = mediaSegments.first, let lastSegment = mediaSegments.last {
                let start = CMTimeMaximum(.zero, firstSegment.timeMapping.target.start)
                let end = CMTimeMinimum(lastSegment.timeMapping.target.end, compositionEnd)
                if end > start {
                    overlayRenderRange = CMTimeRange(start: start, end: end)
                }
            }
        }

        var instructions: [AVMutableVideoCompositionInstruction] = []

        if let overlayVideoTrack,
           let overlayCompositionTrack,
           let overlayRenderRange {
            let overlayFrame = overlayFrame(
                in: renderSize,
                position: position,
                size: overlaySize
            )
            let normalizedOverlayTransform = try await normalizedTransform(for: overlayVideoTrack)
            let overlaySourceSize = try await orientedSize(for: overlayVideoTrack)
            let overlayScale = min(
                overlayFrame.width / max(overlaySourceSize.width, 1),
                overlayFrame.height / max(overlaySourceSize.height, 1)
            )

            let overlayInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: overlayCompositionTrack)
            var overlayTransform = normalizedOverlayTransform
            overlayTransform = overlayTransform.concatenating(CGAffineTransform(scaleX: overlayScale, y: overlayScale))
            overlayTransform = overlayTransform.concatenating(
                CGAffineTransform(translationX: overlayFrame.minX, y: overlayFrame.minY)
            )
            overlayInstruction.setTransform(overlayTransform, at: .zero)

            if overlayRenderRange.start > .zero {
                let screenOnlyHead = AVMutableVideoCompositionInstruction()
                screenOnlyHead.timeRange = CMTimeRange(start: .zero, end: overlayRenderRange.start)
                screenOnlyHead.layerInstructions = [screenInstruction]
                instructions.append(screenOnlyHead)
            }

            let withOverlay = AVMutableVideoCompositionInstruction()
            withOverlay.timeRange = overlayRenderRange
            withOverlay.layerInstructions = [overlayInstruction, screenInstruction]
            instructions.append(withOverlay)

            if overlayRenderRange.end < compositionEnd {
                let screenOnlyTail = AVMutableVideoCompositionInstruction()
                screenOnlyTail.timeRange = CMTimeRange(start: overlayRenderRange.end, end: compositionEnd)
                screenOnlyTail.layerInstructions = [screenInstruction]
                instructions.append(screenOnlyTail)
            }
        } else {
            let screenOnly = AVMutableVideoCompositionInstruction()
            screenOnly.timeRange = CMTimeRange(start: .zero, end: compositionEnd)
            screenOnly.layerInstructions = [screenInstruction]
            instructions.append(screenOnly)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = instructions
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        if overlayRenderRange != nil || !cursorTimeline.isEmpty || !keyboardShortcutTimeline.isEmpty {
            let overlayFrame = overlayRenderRange == nil
                ? .zero
                : overlayFrame(
                    in: renderSize,
                    position: position,
                    size: overlaySize
                )
            videoComposition.animationTool = makeOverlayDecorationTool(
                renderSize: renderSize,
                overlayFrame: overlayFrame,
                screenFrame: screenFrame,
                cursorTimeline: cursorTimeline,
                keyboardShortcutTimeline: keyboardShortcutTimeline
            )
        }

        let audioMix = audioMixBuilder.makeAudioMix(
            composition: composition,
            microphoneTrackIDs: microphoneTrackIDs,
            systemAudioTrackIDs: systemTrackIDs,
            microphoneVolume: microphoneVolume,
            systemAudioVolume: systemAudioVolume
        )

        return ScreenCameraOverlayComposition(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix
        )
    }

    private func insertSegments(
        _ segments: [RecordingSegment],
        of sourceTrack: AVAssetTrack,
        into compositionTrack: AVMutableCompositionTrack,
        clampedTo outputLimit: CMTime? = nil
    ) throws {
        var cursor = CMTime.zero
        for segment in segments {
            var sourceRange = segment.sourceRange
            if let outputLimit {
                guard segment.destinationStart < outputLimit else { continue }
                let available = outputLimit - segment.destinationStart
                if sourceRange.duration > available {
                    sourceRange = CMTimeRange(start: sourceRange.start, duration: available)
                }
            }
            // `insertTimeRange(_:of:at:)` does NOT leave a gap when `at` is past the
            // track's current end — it silently appends at the end instead, collapsing
            // the head gap of a secondary component that started after session zero
            // (e.g. the camera overlay's warm-up delay). The gap must be an explicit
            // empty range for the destination position to be honored.
            if segment.destinationStart > cursor {
                compositionTrack.insertEmptyTimeRange(CMTimeRange(start: cursor, end: segment.destinationStart))
            }
            try compositionTrack.insertTimeRange(sourceRange, of: sourceTrack, at: segment.destinationStart)
            cursor = segment.destinationStart + sourceRange.duration
        }
    }

    func targetRenderSize(for mode: RecordingMode) -> CGSize {
        mode.renderSize
    }

    func fittedVideoFrame(contentSize: CGSize, in renderSize: CGSize) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0 else {
            return CGRect(origin: .zero, size: renderSize)
        }

        let scale = min(renderSize.width / contentSize.width, renderSize.height / contentSize.height)
        let fittedWidth = contentSize.width * scale
        let fittedHeight = contentSize.height * scale
        return CGRect(
            x: (renderSize.width - fittedWidth) / 2,
            y: (renderSize.height - fittedHeight) / 2,
            width: fittedWidth,
            height: fittedHeight
        )
    }

    /// Returns a frame that fills the render canvas using the maximum scale factor,
    /// cropping content that extends beyond the canvas edges (center-aligned).
    /// Use this for vertical screen recording where fit would create black bands.
    func filledVideoFrame(contentSize: CGSize, in renderSize: CGSize) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0 else {
            return CGRect(origin: .zero, size: renderSize)
        }
        let scale = max(renderSize.width / contentSize.width, renderSize.height / contentSize.height)
        let filledWidth = contentSize.width * scale
        let filledHeight = contentSize.height * scale
        return CGRect(
            x: (renderSize.width - filledWidth) / 2,
            y: (renderSize.height - filledHeight) / 2,
            width: filledWidth,
            height: filledHeight
        )
    }

    func overlayFrame(
        in renderSize: CGSize,
        position: ScreenCameraOverlayPosition,
        size: ScreenCameraOverlaySize
    ) -> CGRect {
        let overlayWidth = renderSize.width * size.widthRatio(for: renderSize)
        let overlayHeight = overlayWidth * 9 / 16
        let horizontalPadding = max(renderSize.width * 0.035, 28)
        let verticalPadding = max(renderSize.height * 0.045, 28)

        let x: CGFloat
        switch position.horizontalAnchor {
        case 0:
            x = horizontalPadding
        case 0.5:
            x = (renderSize.width - overlayWidth) / 2
        default:
            x = renderSize.width - overlayWidth - horizontalPadding
        }

        let y: CGFloat
        switch position.verticalAnchor {
        case 0:
            y = verticalPadding
        case 0.5:
            y = (renderSize.height - overlayHeight) / 2
        default:
            y = renderSize.height - overlayHeight - verticalPadding
        }

        return CGRect(x: x, y: y, width: overlayWidth, height: overlayHeight)
    }

    func cursorRenderPoint(for sample: CursorSample, in screenFrame: CGRect) -> CGPoint {
        CGPoint(
            x: screenFrame.minX + (screenFrame.width * sample.normalizedX),
            y: screenFrame.minY + (screenFrame.height * sample.normalizedY)
        )
    }

    func cursorDecorationLayerCount(
        in renderSize: CGSize,
        screenFrame: CGRect,
        timeline: CursorHighlightTimeline
    ) -> Int {
        makeCursorDecorationLayers(
            renderSize: renderSize,
            screenFrame: screenFrame,
            timeline: timeline
        ).count
    }

    func keyboardShortcutDecorationLayerCount(
        in renderSize: CGSize,
        timeline: KeyboardShortcutTimeline
    ) -> Int {
        makeKeyboardShortcutDecorationLayers(
            renderSize: renderSize,
            timeline: timeline
        ).count
    }

    private func orientedSize(for track: AVAssetTrack) async throws -> CGSize {
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        return CGSize(width: abs(bounds.width), height: abs(bounds.height))
    }

    private func normalizedTransform(for track: AVAssetTrack) async throws -> CGAffineTransform {
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        return preferredTransform.translatedBy(x: -bounds.origin.x, y: -bounds.origin.y)
    }

    private func makeOverlayDecorationTool(
        renderSize: CGSize,
        overlayFrame: CGRect,
        screenFrame: CGRect,
        cursorTimeline: CursorHighlightTimeline,
        keyboardShortcutTimeline: KeyboardShortcutTimeline
    ) -> AVVideoCompositionCoreAnimationTool {
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)

        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)

        if overlayFrame.width > 0, overlayFrame.height > 0 {
            let borderLayer = CALayer()
            borderLayer.frame = overlayFrame.insetBy(dx: -3, dy: -3)
            borderLayer.cornerRadius = 18
            borderLayer.borderWidth = 2
            borderLayer.borderColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.92)
            borderLayer.backgroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.03)
            borderLayer.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            borderLayer.shadowOpacity = 0.35
            borderLayer.shadowRadius = 14
            borderLayer.shadowOffset = CGSize(width: 0, height: -2)
            parentLayer.addSublayer(borderLayer)
        }

        for layer in makeCursorDecorationLayers(
            renderSize: renderSize,
            screenFrame: screenFrame,
            timeline: cursorTimeline
        ) {
            parentLayer.addSublayer(layer)
        }

        for layer in makeKeyboardShortcutDecorationLayers(
            renderSize: renderSize,
            timeline: keyboardShortcutTimeline
        ) {
            parentLayer.addSublayer(layer)
        }

        return AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    private func makeCursorDecorationLayers(
        renderSize: CGSize,
        screenFrame: CGRect,
        timeline: CursorHighlightTimeline
    ) -> [CALayer] {
        guard !timeline.samples.isEmpty else { return [] }

        let spotlightLayer = CALayer()
        spotlightLayer.bounds = CGRect(x: 0, y: 0, width: 110, height: 110)
        spotlightLayer.cornerRadius = 55
        spotlightLayer.backgroundColor = CGColor(red: 1, green: 0.96, blue: 0.55, alpha: 0.18)
        spotlightLayer.shadowColor = CGColor(red: 1, green: 0.92, blue: 0.35, alpha: 1)
        spotlightLayer.shadowOpacity = 0.35
        spotlightLayer.shadowRadius = 18
        spotlightLayer.shadowOffset = .zero
        spotlightLayer.position = cursorRenderPoint(for: timeline.samples[0], in: screenFrame)

        let positionAnimation = CAKeyframeAnimation(keyPath: "position")
        positionAnimation.values = timeline.samples.map { NSValue(point: cursorRenderPoint(for: $0, in: screenFrame)) }
        let duration = max(timeline.samples.last?.timestamp ?? 0, timeline.clickEvents.last?.timestamp ?? 0, 0.01)
        positionAnimation.keyTimes = timeline.samples.map { NSNumber(value: $0.timestamp / duration) }
        positionAnimation.duration = duration
        positionAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
        positionAnimation.isRemovedOnCompletion = false
        positionAnimation.fillMode = .forwards
        positionAnimation.calculationMode = .linear
        spotlightLayer.add(positionAnimation, forKey: "cursor-position")

        var layers: [CALayer] = [spotlightLayer]
        for click in timeline.clickEvents {
            let pulseLayer = CAShapeLayer()
            let pulseSize: CGFloat = 64
            let center = cursorRenderPoint(
                for: CursorSample(timestamp: click.timestamp, normalizedX: click.normalizedX, normalizedY: click.normalizedY),
                in: screenFrame
            )
            pulseLayer.frame = CGRect(
                x: center.x - pulseSize / 2,
                y: center.y - pulseSize / 2,
                width: pulseSize,
                height: pulseSize
            )
            pulseLayer.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: pulseSize, height: pulseSize), transform: nil)
            pulseLayer.fillColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.08)
            pulseLayer.strokeColor = CGColor(red: 1, green: 0.96, blue: 0.55, alpha: 0.95)
            pulseLayer.lineWidth = 3
            pulseLayer.opacity = 0

            let group = CAAnimationGroup()
            group.animations = [
                {
                    let animation = CABasicAnimation(keyPath: "transform.scale")
                    animation.fromValue = 0.35
                    animation.toValue = 1.45
                    return animation
                }(),
                {
                    let animation = CABasicAnimation(keyPath: "opacity")
                    animation.fromValue = 0.95
                    animation.toValue = 0
                    return animation
                }()
            ]
            group.duration = 0.45
            group.beginTime = AVCoreAnimationBeginTimeAtZero + click.timestamp
            group.isRemovedOnCompletion = false
            group.fillMode = .forwards
            pulseLayer.add(group, forKey: "click-pulse")
            layers.append(pulseLayer)
        }

        return layers
    }

    private func makeKeyboardShortcutDecorationLayers(
        renderSize: CGSize,
        timeline: KeyboardShortcutTimeline
    ) -> [CALayer] {
        guard !timeline.events.isEmpty else { return [] }

        let cardWidth = min(max(renderSize.width * 0.22, 220), 420)
        let cardHeight = max(renderSize.height * 0.07, 68)
        let frame = CGRect(
            x: (renderSize.width - cardWidth) / 2,
            y: max(renderSize.height * 0.06, 28),
            width: cardWidth,
            height: cardHeight
        )

        return timeline.events.map { event in
            let container = CALayer()
            container.frame = frame
            container.opacity = 0
            container.backgroundColor = CGColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 0.82)
            container.cornerRadius = 18
            container.borderWidth = 1
            container.borderColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.12)
            container.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            container.shadowOpacity = 0.28
            container.shadowRadius = 12
            container.shadowOffset = .zero

            let textLayer = CATextLayer()
            textLayer.frame = container.bounds.insetBy(dx: 18, dy: 14)
            textLayer.string = event.label
            textLayer.font = CGFont("SFProDisplay-Semibold" as CFString)
            textLayer.fontSize = min(max(renderSize.height * 0.028, 26), 36)
            textLayer.alignmentMode = .center
            textLayer.foregroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.96)
            textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            textLayer.truncationMode = .end
            container.addSublayer(textLayer)

            let group = CAAnimationGroup()
            group.animations = [
                {
                    let animation = CAKeyframeAnimation(keyPath: "opacity")
                    animation.values = [0, 1, 1, 0]
                    animation.keyTimes = [0, 0.15, 0.75, 1]
                    return animation
                }(),
                {
                    let animation = CABasicAnimation(keyPath: "transform.scale")
                    animation.fromValue = 0.96
                    animation.toValue = 1
                    animation.duration = 0.18
                    return animation
                }()
            ]
            group.duration = 1.15
            group.beginTime = AVCoreAnimationBeginTimeAtZero + event.timestamp
            group.isRemovedOnCompletion = false
            group.fillMode = .forwards
            container.add(group, forKey: "shortcut-card")

            return container
        }
    }
}
