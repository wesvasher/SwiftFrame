import AVFoundation
import SwiftUI

/// The live camera picture, fitted to the view like the captured frames are,
/// so the onion skin lines up with it.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    var mirrored: Bool

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.mirrored = mirrored
    }

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()
        var mirrored = false { didSet { applyMirroring() } }

        override init(frame: NSRect) {
            super.init(frame: frame)
            previewLayer.videoGravity = .resizeAspect
            previewLayer.backgroundColor = .black
            layer = previewLayer
            wantsLayer = true
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func layout() {
            super.layout()
            applyMirroring()
        }

        private func applyMirroring() {
            guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }
}
