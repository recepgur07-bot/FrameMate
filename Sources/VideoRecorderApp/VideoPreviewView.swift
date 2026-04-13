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
