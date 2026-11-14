import AVFoundation
import SwiftUI

/// The live camera picture, fitted to the view like the captured frames are,
/// so the onion skin lines up with it. Zoomed in, it's scaled about the
/// middle and moved by `pan`, as SwiftUI's `scaleEffect` then `offset` would.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    var mirrored: Bool
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
    /// The camera picture's size, and the part of it to show (fractions,
    /// from the top left), when it's cropped.
    var videoSize: CGSize?
    var crop: CGRect?

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.mirrored = mirrored
        if view.zoom != zoom || view.pan != pan || view.videoSize != videoSize || view.crop != crop {
            view.zoom = zoom
            view.pan = pan
            view.videoSize = videoSize
            view.crop = crop
            view.needsLayout = true
        }
    }

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()
        /// Clips the picture to the crop.
        private let cropLayer = CALayer()
        var mirrored = false { didSet { applyMirroring() } }
        var zoom: CGFloat = 1
        var pan: CGSize = .zero
        var videoSize: CGSize?
        var crop: CGRect?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = .black
            layer?.masksToBounds = true
            previewLayer.videoGravity = .resizeAspect
            previewLayer.backgroundColor = .black
            cropLayer.masksToBounds = true
            cropLayer.addSublayer(previewLayer)
            layer?.addSublayer(cropLayer)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        // Top-left origin, like SwiftUI, so the pan goes the same way.
        override var isFlipped: Bool { true }

        // Clicks and drags go to the viewer's SwiftUI gestures.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let videoSize, let crop, videoSize.width > 0, videoSize.height > 0, crop.width > 0, crop.height > 0 {
                // The crop, fitted to the view like a cropped frame, then
                // zoomed; the whole picture is laid out around it, clipped.
                let shown = CGSize(width: videoSize.width * crop.width, height: videoSize.height * crop.height)
                let fit = min(bounds.width / shown.width, bounds.height / shown.height) * zoom
                let cropFrame = CGRect(x: bounds.midX + pan.width - shown.width * fit / 2,
                                       y: bounds.midY + pan.height - shown.height * fit / 2,
                                       width: shown.width * fit, height: shown.height * fit)
                cropLayer.frame = cropFrame
                previewLayer.frame = CGRect(x: -crop.minX * videoSize.width * fit,
                                            y: -crop.minY * videoSize.height * fit,
                                            width: videoSize.width * fit, height: videoSize.height * fit)
            } else {
                let size = CGSize(width: bounds.width * zoom, height: bounds.height * zoom)
                cropLayer.frame = CGRect(x: bounds.midX + pan.width - size.width / 2,
                                         y: bounds.midY + pan.height - size.height / 2,
                                         width: size.width, height: size.height)
                previewLayer.frame = cropLayer.bounds
            }
            CATransaction.commit()
            applyMirroring()
        }

        private func applyMirroring() {
            guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }
}
