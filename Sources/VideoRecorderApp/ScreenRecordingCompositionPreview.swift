import AVFoundation
import SwiftUI

struct ScreenRecordingCompositionPreview: View {
    let session: AVCaptureSession
    let mode: RecordingMode
    let isOverlayEnabled: Bool
    let position: ScreenCameraOverlayPosition
    let overlaySize: ScreenCameraOverlaySize

    private let compositionBuilder = ScreenCameraOverlayCompositionBuilder()

    var body: some View {
        GeometryReader { geometry in
            let previewBounds = geometry.size
            let renderSize = compositionBuilder.targetRenderSize(for: mode)
            let canvasFrame = compositionBuilder.fittedVideoFrame(
                contentSize: renderSize,
                in: previewBounds
            )
            let overlayFrame = compositionBuilder.overlayFrame(
                in: canvasFrame.size,
                position: position,
                size: overlaySize
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.92),
                                Color.black.opacity(0.84)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: canvasFrame.width, height: canvasFrame.height)
                    .position(x: canvasFrame.midX, y: canvasFrame.midY)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Çıktı önizlemesi")
                                .font(.headline)
                            Text(renderSizeLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(18)
                    }

                if isOverlayEnabled {
                    VideoPreviewView(session: session, crop: .fullFrame)
                        .frame(width: overlayFrame.width, height: overlayFrame.height)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.white.opacity(0.88), lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 6)
                        .position(
                            x: canvasFrame.minX + overlayFrame.midX,
                            y: canvasFrame.minY + overlayFrame.midY
                        )
                }
            }
        }
        .frame(minHeight: 260)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var renderSizeLabel: String {
        "\(Int(mode.renderSize.width)) x \(Int(mode.renderSize.height))"
    }

    private var accessibilityLabel: String {
        if isOverlayEnabled {
            return String(localized: "Çıktı önizlemesi. Kamera kutusu \(position.label) konumunda ve \(overlaySize.label.lowercased()) boyutta.")
        }
        return String(localized: "Çıktı önizlemesi. Kamera kutusu kapalı.")
    }

}
