import AVFoundation
import SwiftUI

/// The live camera picture, fitted to the view like the captured frames are,
/// so the onion skin lines up with it.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    var mirrored: Bool
    var zoom: CGFloat = 1
    var pan: CGSize = .zero

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.mirrored = mirrored
        view.zoom = zoom
        view.pan = pan
    }

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()
        var mirrored = false { didSet { applyMirroring() } }
        var zoom: CGFloat = 1 { didSet { if zoom != oldValue { needsLayout = true } } }
        var pan: CGSize = .zero { didSet { if pan != oldValue { needsLayout = true } } }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = .black
            layer?.masksToBounds = true
            previewLayer.videoGravity = .resizeAspect
            layer?.addSublayer(previewLayer)
        }

        // Top-left origin, like SwiftUI's offsets.
        override var isFlipped: Bool { true }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func layout() {
            super.layout()
            // Scaled about the center, then moved by the pan: the same as
            // SwiftUI's scaleEffect + offset on the onion skin.
            let size = CGSize(width: bounds.width * zoom, height: bounds.height * zoom)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = CGRect(x: (bounds.width - size.width) / 2 + pan.width,
                                        y: (bounds.height - size.height) / 2 + pan.height,
                                        width: size.width, height: size.height)
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
