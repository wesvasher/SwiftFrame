import SwiftUI

/// One capture window: the viewer, the capture bar and the filmstrip, for
/// one project. Open as many as you like with File → New.
struct CaptureWindow: View {
    @StateObject private var model: WindowModel
    @Environment(\.undoManager) private var undoManager
    let fileURL: URL?

    init(document: StopMotionDocument, fileURL: URL?) {
        _model = StateObject(wrappedValue: WindowModel(document: document))
        self.fileURL = fileURL
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewerView(model: model)
                .frame(minWidth: 480, minHeight: 270)
            Divider()
            CaptureBar(model: model)
            Divider()
            FilmstripView(model: model)
        }
        .toolbar { WindowToolbar(model: model) }
        .focusedSceneObject(model)
        .task { await model.startCamera() }
        .onAppear {
            model.undoManager = undoManager
            model.movieName = movieName
        }
        .onChange(of: fileURL) { model.movieName = movieName }
        .onChange(of: undoManager) { model.undoManager = undoManager }
        .onDisappear { model.camera.stop() }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var movieName: String {
        (fileURL?.deletingPathExtension().lastPathComponent ?? "Animation") + ".mov"
    }
}

/// The capture button, with the project's length on one side and the
/// viewer modes on the other.
private struct CaptureBar: View {
    @ObservedObject var model: WindowModel

    var body: some View {
        HStack {
            Text(summary)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: model.capture) {
                ZStack {
                    Circle().fill(.red)
                    Circle().strokeBorder(.white.opacity(0.9), lineWidth: 3).padding(3)
                }
                .frame(width: 44, height: 44)
                .opacity(model.canCapture ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!model.canCapture)
            .help("Capture a frame (Space)")

            HStack(spacing: 8) {
                if let progress = model.exportProgress {
                    ProgressView(value: progress).frame(width: 90)
                    Text("Exporting…").font(.callout).foregroundStyle(.secondary)
                }
                Picker("Viewer", selection: modeBinding) {
                    Label("Live", systemImage: "camera").tag(WindowModel.Mode.live)
                    Label("Frame", systemImage: "photo").tag(WindowModel.Mode.review)
                    Label("Play", systemImage: "play").tag(WindowModel.Mode.playback)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var modeBinding: Binding<WindowModel.Mode> {
        Binding {
            model.mode
        } set: { mode in
            switch mode {
            case .live: model.goLive()
            case .playback: if model.mode != .playback { model.togglePlayback() }
            case .review:
                model.stopPlayback()
                if model.mode != .review, let last = model.frames.last { model.select(last.id) }
            }
        }
    }

    private var summary: String {
        let count = model.frames.count
        let fps = model.project.framesPerSecond
        let seconds = model.project.duration.formatted(.number.precision(.fractionLength(1)))
        return "\(count) \(count == 1 ? "frame" : "frames") · \(seconds) s at \(fps) fps"
    }
}

private struct WindowToolbar: ToolbarContent {
    @ObservedObject var model: WindowModel
    @ObservedObject var camera: CameraController

    init(model: WindowModel) {
        self.model = model
        self.camera = model.camera
    }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Menu {
                if camera.devices.isEmpty {
                    Text("No cameras found")
                }
                Picker("Camera", selection: Binding(
                    get: { camera.deviceID ?? "" }, set: { model.selectCamera($0) })
                ) {
                    ForEach(camera.devices) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("Mirror Camera", isOn: Binding(get: { model.project.mirrorCamera }, set: model.setMirror))
            } label: {
                Label(cameraName, systemImage: "web.camera")
            }
            .help("Choose a camera")
        }

        ToolbarItemGroup {
            Picker("Frame Rate", selection: Binding(get: { model.project.framesPerSecond }, set: model.setFrameRate)) {
                ForEach(Project.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
            }
            .fixedSize()
            .help("Frames per second")

            OnionSkinButton(model: model)

            Toggle(isOn: Binding(get: { model.project.loopPlayback }, set: model.setLoop)) {
                Label("Loop", systemImage: "repeat")
            }
            .help("Loop playback")

            Button {
                model.togglePlayback()
            } label: {
                Label(model.mode == .playback ? "Stop" : "Play",
                      systemImage: model.mode == .playback ? "stop.fill" : "play.fill")
            }
            .disabled(model.frames.isEmpty)
            .help("Play the animation (Return)")

            Button {
                model.exportMovie()
            } label: {
                Label("Export Movie", systemImage: "square.and.arrow.up")
            }
            .disabled(model.frames.isEmpty || model.exportProgress != nil)
            .help("Export a QuickTime movie")
        }
    }

    private var cameraName: String {
        camera.devices.first { $0.id == camera.deviceID }?.name ?? "Camera"
    }
}

private struct OnionSkinButton: View {
    @ObservedObject var model: WindowModel
    @State private var isShown = false

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Label("Onion Skin", systemImage: "square.stack.3d.down.forward")
        }
        .help("Onion skin: earlier frames over the live camera")
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            Form {
                Stepper(value: Binding(get: { model.project.onionSkinFrames }, set: model.setOnionSkinFrames),
                        in: 0...5) {
                    LabeledContent("Frames", value: model.project.onionSkinFrames == 0
                                   ? "Off" : "\(model.project.onionSkinFrames)")
                }
                Slider(value: Binding(get: { model.project.onionSkinOpacity }, set: model.setOnionSkinOpacity),
                       in: 0.05...0.9) {
                    Text("Opacity")
                }
                .disabled(model.project.onionSkinFrames == 0)
            }
            .formStyle(.grouped)
            .frame(width: 280)
        }
    }
}
