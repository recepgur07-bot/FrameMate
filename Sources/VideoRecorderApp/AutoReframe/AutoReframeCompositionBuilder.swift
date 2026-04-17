import AVFoundation
import CoreGraphics
import Foundation

struct AutoReframeCompositionBuilder {

    // MARK: - Portrait camera export

    /// Scale factor that fills a 1080×1920 portrait canvas from a 1920×1080 landscape source.
    /// renderHeight(1920) / sourceHeight(1080) = 1.7̄7̄8̄
    static let portraitFillScale: CGFloat = 1920.0 / 1080.0

    /// Returns the AVCompositionLayerInstruction transform that maps a landscape 1920×1080
    /// source track into a 1080×1920 portrait render canvas, using `crop` for horizontal position.
    ///
    /// Math:
    ///   scale = portraitFillScale = 1.778
    ///   After scaling: source is 3413×1920, which exactly fills the 1920 canvas height.
    ///   tx = -crop.originX * 1920 * scale
    ///   ty = 0 (height fills perfectly, no vertical offset needed)
    static func portraitLayerTransform(for crop: AutoReframeCrop) -> CGAffineTransform {
        let scale = portraitFillScale
        let tx = -crop.originX * 1920.0 * scale
        return CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: tx, y: 0))
    }

    func makeVideoComposition(
        for asset: AVAsset,
        timeline: AutoReframeTimeline,
        mode: RecordingMode = .horizontal1080p
    ) async -> AVMutableVideoComposition? {
        // Portrait camera mode: always build a composition (no letterbox fallback)
        if mode == .vertical1080p {
            return await makePortraitVideoComposition(for: asset, timeline: timeline)
        }

        // Existing horizontal path — unchanged
        guard !timeline.keyframes.isEmpty,
              let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }

        let naturalSize = (try? await videoTrack.load(.naturalSize)) ?? .zero
        let preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        let duration = (try? await asset.load(.duration)) ?? .zero

        guard naturalSize != .zero, duration > .zero else {
            return nil
        }

        let renderSize = resolvedRenderSize(naturalSize: naturalSize, preferredTransform: preferredTransform)
        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        for keyframe in timeline.keyframes {
            layerInstruction.setTransform(
                transform(
                    for: keyframe.crop,
                    renderSize: renderSize,
                    preferredTransform: preferredTransform
                ),
                at: keyframe.time
            )
        }

        if timeline.keyframes.count >= 2 {
            for index in 0..<(timeline.keyframes.count - 1) {
                let current = timeline.keyframes[index]
                let next = timeline.keyframes[index + 1]
                let timeRange = CMTimeRange(start: current.time, end: next.time)
                guard timeRange.duration > .zero else { continue }
                layerInstruction.setTransformRamp(
                    fromStart: transform(
                        for: current.crop,
                        renderSize: renderSize,
                        preferredTransform: preferredTransform
                    ),
                    toEnd: transform(
                        for: next.crop,
                        renderSize: renderSize,
                        preferredTransform: preferredTransform
                    ),
                    timeRange: timeRange
                )
            }
        }

        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]
        return composition
    }

    private func resolvedRenderSize(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGSize {
        let transformed = naturalSize.applying(preferredTransform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }

    private func transform(
        for crop: AutoReframeCrop,
        renderSize: CGSize,
        preferredTransform: CGAffineTransform
    ) -> CGAffineTransform {
        let scaleX = 1 / crop.width
        let scaleY = 1 / crop.height
        let offsetX = -crop.originX * renderSize.width
        let offsetY = -crop.originY * renderSize.height

        return preferredTransform
            .translatedBy(x: offsetX, y: offsetY)
            .scaledBy(x: scaleX, y: scaleY)
    }

    private func makePortraitVideoComposition(
        for asset: AVAsset,
        timeline: AutoReframeTimeline
    ) async -> AVMutableVideoComposition? {
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }

        let duration = (try? await asset.load(.duration)) ?? .zero
        guard duration > .zero else { return nil }

        // DEPENDENCY: Chunk 1 must have removed capture-layer rotation first.
        // This function assumes the source track is 1920×1080 landscape (preferredTransform=identity).
        // Guard against accidentally being called on a pre-rotated portrait source.
        let naturalSize = (try? await videoTrack.load(.naturalSize)) ?? .zero
        guard naturalSize.width > naturalSize.height else {
            // Source is already portrait or square — landscape assumption violated.
            // Fall back to nil so the export session honours preferredTransform as-is.
            return nil
        }

        let renderSize = RecordingMode.vertical1080p.renderSize  // 1080×1920

        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)

        if timeline.keyframes.isEmpty {
            // No auto-reframe: center crop
            let centerCrop = AutoReframeCrop.portraitFullHeight(centerX: 0.5)
            layerInstruction.setTransform(
                Self.portraitLayerTransform(for: centerCrop),
                at: .zero
            )
        } else {
            // Auto-reframe: keyframe-based horizontal panning
            for keyframe in timeline.keyframes {
                layerInstruction.setTransform(
                    Self.portraitLayerTransform(for: keyframe.crop),
                    at: keyframe.time
                )
            }
            // Smooth ramps between keyframes
            if timeline.keyframes.count >= 2 {
                for index in 0..<(timeline.keyframes.count - 1) {
                    let current = timeline.keyframes[index]
                    let next = timeline.keyframes[index + 1]
                    let timeRange = CMTimeRange(start: current.time, end: next.time)
                    guard timeRange.duration > .zero else { continue }
                    layerInstruction.setTransformRamp(
                        fromStart: Self.portraitLayerTransform(for: current.crop),
                        toEnd: Self.portraitLayerTransform(for: next.crop),
                        timeRange: timeRange
                    )
                }
            }
        }

        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]
        return composition
    }
}
