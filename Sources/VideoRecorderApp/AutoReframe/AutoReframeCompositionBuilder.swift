import AVFoundation
import CoreGraphics
import Foundation

struct AutoReframeCompositionBuilder {
    func makeVideoComposition(
        for asset: AVAsset,
        timeline: AutoReframeTimeline
    ) async -> AVMutableVideoComposition? {
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
}
