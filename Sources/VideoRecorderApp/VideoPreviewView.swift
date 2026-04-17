import AVFoundation
import SwiftUI

struct VideoPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    let crop: AutoReframeCrop

    func makeNSView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.update(session: session, crop: crop)
        return view
    }

    func updateNSView(_ nsView: PreviewContainerView, context: Context) {
        nsView.update(session: session, crop: crop)
    }
}

final class PreviewContainerView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var currentCrop: AutoReframeCrop = .fullFrame

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer = previewLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        applyCrop()
    }

    func update(session: AVCaptureSession, crop: AutoReframeCrop) {
        previewLayer.session = session
        currentCrop = crop
        applyCrop()
    }

    private func applyCrop() {
        // Portrait crop: width << 1, height ≈ 1.0
        // The preview layer's .resizeAspectFill gravity already fills the portrait
        // container with the landscape feed (centering it). We only need a horizontal
        // translation to follow the face. Applying independent x/y scales would
        // distort the aspect ratio.
        let isPortraitCrop = currentCrop.height > 0.95 && currentCrop.width < 0.5

        if isPortraitCrop {
            // With resizeAspectFill in a portrait container, the preview layer fills the
            // container height. The fill scale = bounds.height / 1080.
            // Source pixel delta to shift = (0.5 - centerX) * 1920
            // Mapped to container pixels = delta * (bounds.height / 1080)
            let fillScale = bounds.height / 1080.0
            let horizontalShift = (0.5 - currentCrop.centerX) * 1920.0 * fillScale
            let transform = CGAffineTransform(translationX: horizontalShift, y: 0)
            previewLayer.setAffineTransform(transform)
        } else {
            // Original square-crop behavior for horizontal mode
            let scaleX = 1 / max(currentCrop.width, 0.0001)
            let scaleY = 1 / max(currentCrop.height, 0.0001)
            let translationX = (0.5 - currentCrop.centerX) * bounds.width * scaleX
            let translationY = (0.5 - currentCrop.centerY) * bounds.height * scaleY

            let transform = CGAffineTransform.identity
                .translatedBy(x: translationX, y: translationY)
                .scaledBy(x: scaleX, y: scaleY)

            previewLayer.setAffineTransform(transform)
        }
    }
}
