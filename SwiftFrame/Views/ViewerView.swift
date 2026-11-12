import SwiftUI

/// The big picture: the live camera with the onion skin, a selected frame, or
/// playback.
struct ViewerView: View {
    @ObservedObject var model: WindowModel
    @State private var panStart: CGSize?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                switch model.mode {
                case .live: LiveView(model: model)
                case .review: ReviewView(model: model)
                case .playback: PlaybackView(model: model)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(.rect)
            // Drag to look around while zoomed in.
            .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                let start = panStart ?? model.pan
                panStart = start
                model.setPan(CGSize(width: start.width + value.translation.width,
                                    height: start.height + value.translation.height))
            }.onEnded { _ in panStart = nil }, including: model.zoom > 1 ? .all : .none)
            .onChange(of: geometry.size, initial: true) { model.viewerSize = geometry.size }
        }
        .overlay(alignment: .topLeading) { ModeBadge(model: model).padding(12) }
        .overlay { if model.flash { Color.white.opacity(0.35).allowsHitTesting(false) } }
        .animation(.easeOut(duration: 0.12), value: model.flash)
        .clipped()
    }
}

/// Applies the window's zoom and pan, the same way `CameraPreview` does.
struct Zoomed: ViewModifier {
    let zoom: CGFloat
    let pan: CGSize

    func body(content: Content) -> some View {
        content.scaleEffect(zoom).offset(pan)
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

    var body: some View {
        ZStack {
            switch camera.status {
            case .running, .starting:
                CameraPreview(session: camera.session, mirrored: model.project.mirrorCamera,
                              zoom: model.zoom, pan: model.pan)
                OnionSkin(model: model)
                    .modifier(Zoomed(zoom: model.zoom, pan: model.pan))
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
    }
}

/// Earlier frames over the live camera, newest strongest.
private struct OnionSkin: View {
    @ObservedObject var model: WindowModel

    var body: some View {
        let count = min(model.project.onionSkinFrames, model.frames.count)
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
                .modifier(Zoomed(zoom: model.zoom, pan: model.pan))
        }
    }
}

private struct PlaybackView: View {
    @ObservedObject var model: WindowModel

    var body: some View {
        TimelineView(.animation) { context in
            let frames = model.frames
            let length = max(frames.playbackLength, 1)
            let fps = Double(max(model.project.framesPerSecond, 1))
            let elapsed = Int(context.date.timeIntervalSince(model.playbackStart) * fps)
            let finished = !model.project.loopPlayback && elapsed >= length
            let n = finished ? length - 1 : elapsed % length
            let frame = frames.index(atPlaybackFrame: n).map { frames[$0] }
            FramePicture(image: frame.flatMap { model.images.image($0.image, data: model.document.images[$0.image]) })
                .modifier(Zoomed(zoom: model.zoom, pan: model.pan))
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
            if model.zoom > 1 {
                Text("· \(Int((model.zoom * 100).rounded()))%")
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
