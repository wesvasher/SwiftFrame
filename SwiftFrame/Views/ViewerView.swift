import SwiftUI

/// The big picture: the live camera with the onion skin, a selected frame, or
/// playback.
struct ViewerView: View {
    @ObservedObject var model: WindowModel
    /// Full screen playback: just the picture, no badge or zoom buttons.
    var isFullScreen = false
    @State private var pinchStart: CGFloat?
    @State private var dragStart: CGSize?

    var body: some View {
        ZStack {
            Color.black
            switch model.mode {
            // The camera preview zooms itself; its overlays use `zoomed`.
            case .live: LiveView(model: model)
            case .review: ReviewView(model: model).zoomed(model)
            case .playback: PlaybackView(model: model).zoomed(model)
            }
        }
        .contentShape(Rectangle())
        .gesture(pinch)
        .simultaneousGesture(pan)
        .onTapGesture(count: 2) {
            withAnimation(.snappy(duration: 0.2)) {
                if model.viewerZoom > 1 { model.zoomViewerToFit() } else { model.setViewerZoom(2) }
            }
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            model.viewerSize = size
            model.panViewer(to: model.viewerPan)
        }
        .overlay(alignment: .topLeading) { if !isFullScreen { ModeBadge(model: model).padding(12) } }
        .overlay(alignment: .bottomTrailing) { if !isFullScreen { ViewerZoomControls(model: model).padding(12) } }
        .overlay { if model.flash { Color.white.opacity(0.35).allowsHitTesting(false) } }
        .animation(.easeOut(duration: 0.12), value: model.flash)
        .clipped()
    }

    /// Pinching zooms the picture.
    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? model.viewerZoom
                pinchStart = start
                model.setViewerZoom(start * value.magnification)
            }
            .onEnded { _ in pinchStart = nil }
    }

    /// Dragging moves a zoomed-in picture around.
    private var pan: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard model.viewerZoom > 1 else { return }
                let start = dragStart ?? model.viewerPan
                dragStart = start
                model.panViewer(to: CGSize(width: start.width + value.translation.width,
                                           height: start.height + value.translation.height))
            }
            .onEnded { _ in dragStart = nil }
    }
}

extension View {
    /// Scales and moves a picture with the viewer's zoom, the same way the
    /// camera preview does, so they line up.
    func zoomed(_ model: WindowModel) -> some View {
        scaleEffect(model.viewerZoom).offset(model.viewerPan)
    }
}

/// Zoom out, the zoom (click to fit) and zoom in, over the viewer's corner.
private struct ViewerZoomControls: View {
    @ObservedObject var model: WindowModel

    var body: some View {
        HStack(spacing: 2) {
            button("minus.magnifyingglass", help: "Zoom out (⌥⌘−)", enabled: model.canZoomOutViewer) {
                model.zoomOutViewer()
            }
            Button {
                withAnimation(.snappy(duration: 0.2)) { model.zoomViewerToFit() }
            } label: {
                Text(model.viewerZoom <= 1.001 ? "Fit" : "\(Int((model.viewerZoom * 100).rounded()))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .frame(minWidth: 40, minHeight: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Fit the whole picture (⌥⌘0)")
            button("plus.magnifyingglass", help: "Zoom in (⌥⌘=)", enabled: model.canZoomInViewer) {
                model.zoomInViewer()
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .background(.black.opacity(0.55), in: Capsule())
    }

    private func button(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2), action)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(help)
    }
}

/// A frame's picture, fitted to the view.
struct FramePicture: View {
    let image: CGImage?

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        }
    }
}

private struct LiveView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var camera: CameraController

    init(model: WindowModel) {
        self.model = model
        self.camera = model.camera
    }

    /// The part of the camera's picture captures keep, if it's cropped.
    private var cropRect: CGRect? {
        guard let crop = model.project.crop, let size = camera.videoSize else { return nil }
        return crop.unitRect(sourceWidth: Int(size.width), sourceHeight: Int(size.height))
    }

    private var peakingRequest: FocusPeaking {
        var peaking = model.focusPeaking
        peaking.crop = model.project.crop
        return peaking
    }

    var body: some View {
        ZStack {
            switch camera.status {
            case .running, .starting:
                CameraPreview(session: camera.session, mirrored: model.project.mirrorCamera,
                              zoom: model.viewerZoom, pan: model.viewerPan,
                              videoSize: camera.videoSize, crop: cropRect)
                Group {
                    OnionSkin(model: model)
                    if model.focusPeaking.isOn {
                        PeakingOverlay(feed: camera.peakingFeed, mirrored: model.project.mirrorCamera)
                    }
                }
                .zoomed(model)
                if camera.status == .starting { ProgressView().controlSize(.large) }
            case .denied:
                CameraMessage(
                    symbol: "video.slash",
                    title: "SwiftFrame can't use the camera",
                    message: "Allow SwiftFrame under Privacy & Security → Camera in System Settings.",
                    button: ("Open System Settings", {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                    }))
            case .noCamera:
                CameraMessage(
                    symbol: "web.camera",
                    title: "No camera connected",
                    message: "Connect a camera, or add pictures with Frame → Add Pictures.",
                    button: ("Add Pictures…", { model.importImages() }))
            case .failed(let message):
                CameraMessage(symbol: "exclamationmark.triangle", title: "The camera didn't start",
                              message: message, button: ("Try Again", {
                                  model.camera.select(model.camera.deviceID)
                              }))
            }
        }
        // Only work out focus peaking while it's showing.
        .onChange(of: peakingRequest, initial: true) { camera.setFocusPeaking(peakingRequest) }
        .onDisappear { camera.setFocusPeaking(nil) }
    }
}

/// Focus peaking's sharp edges over the live camera.
private struct PeakingOverlay: View {
    @ObservedObject var feed: PeakingFeed
    let mirrored: Bool

    var body: some View {
        FramePicture(image: feed.image)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .allowsHitTesting(false)
    }
}

/// Earlier frames over the live camera, newest strongest.
private struct OnionSkin: View {
    @ObservedObject var model: WindowModel

    var body: some View {
        let count = model.showsOnionSkin ? min(model.project.onionSkinFrames, model.frames.count) : 0
        let recent = Array(model.frames.suffix(count))
        ZStack {
            ForEach(Array(recent.enumerated()), id: \.element.id) { offset, frame in
                // offset 0 is the oldest shown; the newest gets the full setting.
                let strength = Double(offset + 1) / Double(count)
                FramePicture(image: model.images.image(frame.image, data: model.document.images[frame.image]))
                    .opacity(model.project.onionSkinOpacity * strength)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ReviewView: View {
    @ObservedObject var model: WindowModel

    var body: some View {
        if let id = model.current, let frame = model.frames.first(where: { $0.id == id }) {
            FramePicture(image: model.images.image(frame.image, data: model.document.images[frame.image]))
        }
    }
}

private struct PlaybackView: View {
    @ObservedObject var model: WindowModel

    var body: some View {
        TimelineView(.animation) { context in
            let position = model.playbackPosition(at: context.date)
            let finished = position?.finished ?? true
            let frame = position.map { model.frames[$0.index] }
            FramePicture(image: frame.flatMap { model.images.image($0.image, data: model.document.images[$0.image]) })
                .onChange(of: frame?.id, initial: true) { model.playingFrame = frame?.id }
                .onChange(of: finished) { if finished { model.stopPlayback() } }
        }
    }
}

private struct ModeBadge: View {
    @ObservedObject var model: WindowModel

    var body: some View {
        HStack(spacing: 6) {
            switch model.mode {
            case .live:
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("LIVE")
            case .review:
                Image(systemName: "photo")
                Text(position)
            case .playback:
                Image(systemName: "play.fill")
                Text(position)
            }
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.55), in: Capsule())
    }

    private var position: String {
        let id = model.mode == .playback ? model.playingFrame : model.current
        guard let id, let index = model.frames.firstIndex(of: id) else { return "" }
        return "Frame \(index + 1) of \(model.frames.count)"
    }
}

private struct CameraMessage: View {
    let symbol: String
    let title: String
    let message: String
    let button: (String, () -> Void)

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(.secondary)
            Text(title).font(.title2.weight(.semibold))
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(button.0, action: button.1).controlSize(.large)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 420)
        .padding()
    }
}
