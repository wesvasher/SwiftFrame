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
        .overlay {
            // Full screen playback covers the whole window with the animation.
            if model.isPlayingFullScreen {
                ViewerView(model: model, isFullScreen: true)
                    .ignoresSafeArea()
            }
        }
        .toolbar(model.isPlayingFullScreen ? .hidden : .visible, for: .windowToolbar)
        .background(FullScreenWindow(isOn: model.isPlayingFullScreen, onExit: { model.endFullScreen() }))
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
/// frame rate and timeline zoom on the other.
/// Picks the camera, beside the capture button.
private struct CameraSelector: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var camera: CameraController

    var body: some View {
        Menu {
            if camera.devices.isEmpty {
                Text("No cameras found")
            }
            Picker("Camera", selection: Binding(get: { camera.deviceID ?? "" }, set: { model.selectCamera($0) })) {
                ForEach(camera.devices) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label(name, systemImage: camera.devices.isEmpty ? "video.slash" : "web.camera")
                .lineLimit(1)
        }
        .menuStyle(.button)
        .frame(maxWidth: 220, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .help("Choose a camera")
    }

    private var name: String {
        camera.devices.first { $0.id == camera.deviceID }?.name ?? "No Camera"
    }
}

private struct CaptureBar: View {
    @ObservedObject var model: WindowModel

    var body: some View {
        HStack {
            HStack(spacing: 10) {
                CameraSelector(model: model, camera: model.camera)
                Text(summary)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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
                ControlGroup {
                    Button("Zoom Out", systemImage: "minus.magnifyingglass", action: model.zoomOutTimeline)
                        .disabled(!model.canZoomOutTimeline)
                        .help("Narrower frames in the timeline (⌘−)")
                    Button("Zoom In", systemImage: "plus.magnifyingglass", action: model.zoomInTimeline)
                        .disabled(!model.canZoomInTimeline)
                        .help("Wider frames in the timeline (⌘=)")
                    Button("Zoom to Fit", systemImage: "arrow.right.and.line.vertical.and.arrow.left",
                           action: model.zoomTimelineToFit)
                        .disabled(!model.canZoomTimelineToFit)
                        .help("Fit every frame in the timeline (⇧Z)")
                }
                .labelStyle(.iconOnly)
                .fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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

            Toggle(isOn: $model.focusPeaking.isOn) {
                Label("Focus Peaking", systemImage: "viewfinder")
            }
            .help("Show what's in focus on the live camera (⇧⌘P)")
        }

        ToolbarItemGroup {
            Toggle(isOn: Binding(get: { model.showsOnionSkin }, set: model.setShowsOnionSkin)) {
                Label("Onion Skin", systemImage: "square.3.layers.3d")
            }
            .help(model.showsOnionSkin
                  ? "Showing the onion skin over the camera. Click for the plain camera (⇧⌘O)"
                  : "Showing the plain camera. Click to show the onion skin (⇧⌘O)")

            Toggle(isOn: Binding(get: { model.project.loopPlayback }, set: model.setLoop)) {
                Label("Loop", systemImage: "repeat")
            }
            .help("Loop playback")

            Button {
                model.playFullScreen()
            } label: {
                Label("Play Full Screen", systemImage: "play.display")
            }
            .disabled(model.frames.isEmpty)
            .help("Play the animation full screen (⌘F)")

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
        HStack(spacing: 2) {
            segment(.twelve, Text("12"))
            segment(.twentyFour, Text("24"))
            // The symbol's dots sit centered (a typed "…" sits on the baseline), drawn heavier.
            segment(.custom, choice == .custom
                    ? Text("\(model.project.framesPerSecond)")
                    : Text(Image(systemName: "ellipsis")).fontWeight(.black))
                .popover(isPresented: $showsCustom, arrowEdge: .top) { customEditor }
        }
        .padding(2)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.separator, lineWidth: 0.5))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: choice)
        .help("Frames per second: 12, 24, or … for a custom rate")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Frame rate")
    }

    private func segment(_ value: Choice, _ title: Text) -> some View {
        let isSelected = choice == value
        return Button {
            choose(value)
        } label: {
            title
                .font(.caption.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 8)
                .frame(minWidth: 30, minHeight: 20)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: "selected", in: selection)
                    }
                }
                .contentShape(.rect(cornerRadius: 5))
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

/// Puts the window in full screen while `isOn`, and back out after, unless
/// it was already full screen. Leaving full screen another way (the green
/// button, Escape, ⌃⌘F) calls `onExit`.
private struct FullScreenWindow: NSViewRepresentable {
    let isOn: Bool
    let onExit: () -> Void

    func makeNSView(context: Context) -> WatcherView { WatcherView() }

    func updateNSView(_ view: WatcherView, context: Context) {
        view.onExit = onExit
        view.setFullScreen(isOn)
    }

    final class WatcherView: NSView {
        var onExit: () -> Void = {}
        private var wanted = false
        /// Whether going full screen was ours to undo.
        private var entered = false
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.entered = false
                    if self.wanted { self.onExit() }
                }
            }
            if wanted { apply() }
        }

        func setFullScreen(_ on: Bool) {
            guard on != wanted else { return }
            wanted = on
            apply()
        }

        private func apply() {
            guard let window else { return }
            let isFull = window.styleMask.contains(.fullScreen)
            if wanted, !isFull {
                entered = true
                window.toggleFullScreen(nil)
            } else if !wanted, isFull, entered {
                entered = false
                window.toggleFullScreen(nil)
            }
        }
    }
}
