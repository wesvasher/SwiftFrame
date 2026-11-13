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

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.mirrored = mirrored
        if view.zoom != zoom || view.pan != pan {
            view.zoom = zoom
            view.pan = pan
            view.needsLayout = true
        }
    }

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()
        var mirrored = false { didSet { applyMirroring() } }
        var zoom: CGFloat = 1
        var pan: CGSize = .zero

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = .black
            layer?.masksToBounds = true
            previewLayer.videoGravity = .resizeAspect
            previewLayer.backgroundColor = .black
            layer?.addSublayer(previewLayer)
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
            let size = CGSize(width: bounds.width * zoom, height: bounds.height * zoom)
            previewLayer.frame = CGRect(x: bounds.midX + pan.width - size.width / 2,
                                        y: bounds.midY + pan.height - size.height / 2,
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
