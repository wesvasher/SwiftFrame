import SwiftUI

/// One capture window: the viewer, the capture bar and the filmstrip, for
/// one project. Open as many as you like with File → New.
struct CaptureWindow: View {
    @StateObject private var model: WindowModel
    @Environment(\.undoManager) private var undoManager
    @SceneStorage("showsInspector") private var showsInspector = true
    let fileURL: URL?

    init(document: StopMotionDocument, fileURL: URL?) {
        _model = StateObject(wrappedValue: WindowModel(document: document))
        self.fileURL = fileURL
    }

    var body: some View {
        NavigationSplitView {
            CaptureSidebar(model: model)
        } detail: {
            VStack(spacing: 0) {
                ViewerView(model: model)
                    .frame(minWidth: 480, minHeight: 270)
                Divider()
                CaptureBar(model: model)
                Divider()
                FilmstripView(model: model)
            }
            .inspector(isPresented: $showsInspector) {
                FrameInspector(model: model)
                    .toolbar {
                        Button {
                            showsInspector.toggle()
                        } label: {
                            Label("Inspector", systemImage: "sidebar.right")
                        }
                        .help("Show or hide the inspector")
                    }
            }
        }
        .toolbar { WindowToolbar(model: model) }
        .focusedSceneObject(model)
        .background(WindowKeyMonitor(onSpace: { model.togglePlayback() }, onCommandTap: { model.capture() }))
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
            .help("Capture a frame (tap ⌘)")

            HStack(spacing: 8) {
                if let progress = model.exportProgress {
                    ProgressView(value: progress).frame(width: 90)
                    Text("Exporting…").font(.callout).foregroundStyle(.secondary)
                }
                FrameRateSwitch(model: model)
                Picker("Viewer", selection: modeBinding) {
                    Label("Live", systemImage: "camera").tag(WindowModel.Mode.live)
                    Label("Frame", systemImage: "photo").tag(WindowModel.Mode.review)
                    Label("Play", systemImage: "play").tag(WindowModel.Mode.playback)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                ControlGroup {
                    Button("Zoom Out", systemImage: "minus.magnifyingglass", action: model.zoomOutTimeline)
                        .disabled(!model.canZoomOutTimeline)
                        .help("Narrower frames in the timeline (⌘−)")
                    Button("Zoom In", systemImage: "plus.magnifyingglass", action: model.zoomInTimeline)
                        .disabled(!model.canZoomInTimeline)
                        .help("Wider frames in the timeline (⌘=)")
                }
                .labelStyle(.iconOnly)
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
            Toggle(isOn: Binding(get: { model.project.loopPlayback }, set: model.setLoop)) {
                Label("Loop", systemImage: "repeat")
            }
            .help("Loop playback")

            Button {
                model.togglePlayback()
            } label: {
                Label(model.mode == .playback ? "Pause" : "Play",
                      systemImage: model.mode == .playback ? "pause.fill" : "play.fill")
            }
            .disabled(model.frames.isEmpty)
            .help("Play or pause the animation (Space)")

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

/// Window-wide keys that must work wherever keyboard focus is (the sidebar
/// list or a focused button would otherwise take them):
/// - Space calls `onSpace` (play/pause), unless a text field is being typed in.
/// - Tapping either Command key on its own calls `onCommandTap` (capture):
///   pressed and released with no other key, modifier or click in between,
///   so ⌘-shortcuts and ⌘-click don't count.
private struct WindowKeyMonitor: NSViewRepresentable {
    let onSpace: () -> Void
    let onCommandTap: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onSpace = onSpace
        view.onCommandTap = onCommandTap
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onSpace = onSpace
        view.onCommandTap = onCommandTap
    }

    final class MonitorView: NSView {
        var onSpace: () -> Void = {}
        var onCommandTap: () -> Void = {}
        private var monitor: Any?
        private var armed = false

        static let spaceKeyCode: UInt16 = 49

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown,
                                               .otherMouseDown, .scrollWheel]
            monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                guard let self else { return event }
                return self.handle(event) ? nil : event
            }
        }

        /// Returns true when the event was used up.
        private func handle(_ event: NSEvent) -> Bool {
            guard event.window === window, window?.isKeyWindow == true else {
                armed = false
                return false
            }
            switch event.type {
            case .keyDown:
                armed = false
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    .subtracting([.capsLock, .numericPad, .function])
                guard event.keyCode == Self.spaceKeyCode, flags.isEmpty,
                      !(window?.firstResponder is NSText) else { return false }
                if !event.isARepeat { onSpace() }
                return true
            case .flagsChanged:
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    .subtracting([.capsLock, .numericPad, .function])
                if flags == .command {
                    armed = true
                } else if flags.isEmpty, armed {
                    armed = false
                    onCommandTap()
                } else {
                    armed = false
                }
                return false
            default:
                armed = false
                return false
            }
        }

        override func removeFromSuperview() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            super.removeFromSuperview()
        }
    }
}

/// A small flat switch for the frame rate: 12, 24, or a custom rate set in
/// a popover. Rounded rectangles, no glass.
private struct FrameRateSwitch: View {
    @ObservedObject var model: WindowModel
    @AppStorage("customFrameRate") private var lastCustom = 15
    @State private var showsCustom = false
    @Namespace private var selection

    private enum Choice: Hashable { case twelve, twentyFour, custom }

    static let customRange = 1...60

    private var choice: Choice {
        switch model.project.framesPerSecond {
        case 12: .twelve
        case 24: .twentyFour
        default: .custom
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            segment(.twelve, "12")
            segment(.twentyFour, "24")
            segment(.custom, choice == .custom ? "\(model.project.framesPerSecond)" : "…")
                .popover(isPresented: $showsCustom, arrowEdge: .top) { customEditor }
        }
        .padding(3)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: choice)
        .help("Frames per second: 12, 24, or … for a custom rate")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Frame rate")
    }

    private func segment(_ value: Choice, _ title: String) -> some View {
        let isSelected = choice == value
        return Button {
            choose(value)
        } label: {
            Text(title)
                .font(.callout.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 12)
                .frame(minWidth: 40, minHeight: 26)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: "selected", in: selection)
                    }
                }
                .contentShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func choose(_ value: Choice) {
        switch value {
        case .twelve: model.setFrameRate(12)
        case .twentyFour: model.setFrameRate(24)
        case .custom:
            if choice != .custom { model.setFrameRate(lastCustom) }
            showsCustom = true
        }
    }

    private var customEditor: some View {
        let rate = Binding {
            model.project.framesPerSecond
        } set: { value in
            let clamped = value.clamped(to: Self.customRange)
            model.setFrameRate(clamped)
            if clamped != 12, clamped != 24 { lastCustom = clamped }
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Custom Frame Rate").font(.headline)
            // No text field: Space and Delete are window shortcuts here.
            HStack {
                Text("\(model.project.framesPerSecond) fps")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .frame(width: 70, alignment: .leading)
                Stepper("", value: rate, in: Self.customRange).labelsHidden()
            }
            Slider(value: Binding(get: { Double(rate.wrappedValue) }, set: { rate.wrappedValue = Int($0.rounded()) }),
                   in: Double(Self.customRange.lowerBound)...Double(Self.customRange.upperBound), step: 1)
                .frame(width: 220)
            Text("Any rate from 1 to 60 frames per second.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
    }
}
