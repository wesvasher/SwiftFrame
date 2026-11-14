import SwiftUI

/// The right sidebar: the selected frame (or frames), or the project when
/// nothing is selected, then every capture setting, in sections that fold
/// up like SwiftCut's inspector.
struct FrameInspector: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var camera: CameraController

    init(model: WindowModel) {
        self.model = model
        self.camera = model.camera
    }

    var body: some View {
        InspectorPanel {
            let selected = model.frames.enumerated().filter { model.selection.contains($0.element.id) }
            if selected.count == 1, let (index, frame) = selected.first {
                single(frame, index: index)
            } else if selected.count > 1 {
                multiple(selected.map(\.element))
            } else {
                project
            }
            cameraSection
            CameraShutterSection(remote: .shared)
            focusPeakingSection
            onionSkinSection
            playbackSection
        } footer: {
            footer
        }
        .inspectorColumnWidth(min: 240, ideal: 280, max: 380)
    }

    // MARK: Selection

    @ViewBuilder
    private func single(_ frame: Frame, index: Int) -> some View {
        InspectorSection("Frame") {
            GridRow {
                ZStack {
                    Color.black
                    FramePicture(image: model.images.thumbnail(frame.image, data: model.document.images[frame.image]))
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 6))
                .gridCellColumns(2)
            }
            InspectorRow("Frame", "\(index + 1) of \(model.frames.count)")
            InspectorRow("Starts at", time(model.frames.playbackStart(ofIndex: index)))
            holdRow(frame.hold)
        }
    }

    private func multiple(_ frames: [Frame]) -> some View {
        InspectorSection("Selection") {
            InspectorRow("Frames", "\(frames.count) selected")
            InspectorRow("Length", time(frames.playbackLength))
            let holds = Set(frames.map(\.hold))
            holdRow(holds.count == 1 ? holds.first : nil)
        }
    }

    private var project: some View {
        InspectorSection("Project") {
            InspectorRow("Frames", "\(model.frames.count)")
            InspectorRow("Length", time(model.frames.playbackLength))
            InspectorRow("Frame Rate", "\(model.project.framesPerSecond) fps")
            GridRow {
                Text("Click a frame in the timeline to inspect it.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .gridCellColumns(2)
            }
        }
    }

    /// Hold for the selection; `hold` is nil when the frames differ.
    private func holdRow(_ hold: Int?) -> some View {
        GridRow {
            InspectorLabel("Hold")
            Stepper {
                Text(hold.map { $0 == 1 ? "1 frame" : "\($0) frames" } ?? "Mixed")
            } onIncrement: {
                model.changeHold(by: 1)
            } onDecrement: {
                model.changeHold(by: -1)
            }
        }
    }

    /// Frame actions when frames are selected.
    @ViewBuilder private var footer: some View {
        if model.selection.isEmpty {
            Text(model.frames.isEmpty ? "No frames yet" : "No frames selected")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        } else {
            Button {
                model.duplicateSelection()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square").frame(maxWidth: .infinity)
            }
            if model.selection.count > 1 {
                Button {
                    model.reverseSelection()
                } label: {
                    Label("Reverse", systemImage: "arrow.left.arrow.right").frame(maxWidth: .infinity)
                }
            }
            Button(role: .destructive) {
                model.deleteSelection()
            } label: {
                Label("Delete", systemImage: "trash").frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Settings

    private var cameraSection: some View {
        InspectorSection("Camera") {
            GridRow {
                InspectorLabel("Camera")
                if camera.devices.isEmpty {
                    Text("No cameras found").foregroundStyle(.secondary)
                } else {
                    Picker("Camera", selection: Binding(get: { camera.deviceID ?? "" },
                                                        set: { model.selectCamera($0) })) {
                        ForEach(camera.devices) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                }
            }
            GridRow {
                InspectorLabel("Mirror")
                Toggle("Mirror", isOn: Binding(get: { model.project.mirrorCamera }, set: model.setMirror))
                    .labelsHidden()
            }
            CropPicker(model: model, camera: camera)
        }
    }

    private var focusPeakingSection: some View {
        InspectorSection("Focus Peaking") {
            Toggle("Focus Peaking", isOn: $model.focusPeaking.isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Show what's in focus (⇧⌘P)")
        } content: {
            GridRow {
                InspectorLabel("Color")
                Picker("Color", selection: $model.focusPeaking.tint) {
                    ForEach(FocusPeaking.Tint.allCases) { tint in
                        Label {
                            Text(tint.name)
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(tint.color)
                        }
                        .tag(tint)
                    }
                }
                .labelsHidden()
            }
            GridRow {
                InspectorLabel("Sensitivity")
                PeakingSensitivity(peaking: $model.focusPeaking)
            }
            .disabled(!model.focusPeaking.isOn)
        }
    }

    private var onionSkinSection: some View {
        InspectorSection("Onion Skin") {
            GridRow {
                InspectorLabel("Frames")
                Stepper(value: Binding(get: { model.project.onionSkinFrames }, set: model.setOnionSkinFrames),
                        in: 0...5) {
                    Text(model.project.onionSkinFrames == 0 ? "Off" : "\(model.project.onionSkinFrames)")
                        .monospacedDigit()
                }
            }
            GridRow {
                InspectorLabel("Opacity")
                HStack(spacing: 6) {
                    Slider(value: Binding(get: { model.project.onionSkinOpacity }, set: model.setOnionSkinOpacity),
                           in: 0.05...0.9)
                        .labelsHidden()
                    Text("\(Int((model.project.onionSkinOpacity * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }
            .disabled(model.project.onionSkinFrames == 0)
        }
    }

    private var playbackSection: some View {
        InspectorSection("Playback") {
            GridRow {
                InspectorLabel("Frame Rate")
                Picker("Frame Rate", selection: Binding(get: { model.project.framesPerSecond },
                                                       set: model.setFrameRate)) {
                    ForEach(Project.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
                    if !Project.frameRates.contains(model.project.framesPerSecond) {
                        // A custom rate from the capture bar's switch.
                        Text("\(model.project.framesPerSecond) fps").tag(model.project.framesPerSecond)
                    }
                }
                .labelsHidden()
            }
            GridRow {
                InspectorLabel("Loop")
                Toggle("Loop", isOn: Binding(get: { model.project.loopPlayback }, set: model.setLoop))
                    .labelsHidden()
            }
        }
    }

    /// Playback frames as seconds at the project's frame rate.
    private func time(_ playbackFrames: Int) -> String {
        let seconds = Double(playbackFrames) / Double(max(model.project.framesPerSecond, 1))
        return seconds.formatted(.number.precision(.fractionLength(2))) + " s"
    }
}

/// Focus peaking's sensitivity: − and + step the number, and the menu jumps
/// to a named preset (it says Custom between them).
private struct PeakingSensitivity: View {
    @Binding var peaking: FocusPeaking

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Button {
                    peaking.sensitivity -= 1
                } label: {
                    Label("Less Sensitive", systemImage: "minus")
                }
                .disabled(peaking.sensitivity <= FocusPeaking.sensitivityRange.lowerBound)
                .help("Show only the sharpest edges")

                Text("\(peaking.sensitivity)")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 22)
                    .accessibilityLabel("Sensitivity \(peaking.sensitivity)")

                Button {
                    peaking.sensitivity += 1
                } label: {
                    Label("More Sensitive", systemImage: "plus")
                }
                .disabled(peaking.sensitivity >= FocusPeaking.sensitivityRange.upperBound)
                .help("Show softer edges too")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .fixedSize()

            Spacer(minLength: 0)

            Menu(peaking.preset?.name ?? "Custom") {
                ForEach(FocusPeaking.Preset.allCases) { preset in
                    Toggle(isOn: Binding(get: { peaking.preset == preset },
                                         set: { _ in peaking.sensitivity = preset.rawValue })) {
                        Text("\(preset.name) (\(preset.rawValue))")
                    }
                }
            }
            .menuStyle(.button)
            .fixedSize()
            .help("Sensitivity presets")
        }
    }
}

/// Fire a Sony camera's shutter over Bluetooth with each capture, so the
/// camera saves a full-size photo while SwiftFrame captures its HDMI video.
private struct CameraShutterSection: View {
    @ObservedObject var remote: ShutterRemote

    var body: some View {
        InspectorSection("Camera Shutter") {
            Toggle("Fire Camera Shutter", isOn: $remote.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Press a Sony camera's shutter over Bluetooth with each capture")
        } content: {
            GridRow {
                VStack(alignment: .leading, spacing: 6) {
                    if remote.isEnabled {
                        status
                        if let problem = remote.problem {
                            Text(problem).font(.caption).foregroundStyle(.red)
                        }
                    } else {
                        Text("Press a Sony camera's shutter over Bluetooth with each capture, so it saves a full-size photo too.")
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .gridCellColumns(2)
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch remote.state {
        case .off:
            EmptyView()
        case .unavailable(let message):
            Label {
                Text(message).font(.caption)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
            if remote.savedCameraName != nil { forgetButton }
        case .searching:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Looking for cameras…").foregroundStyle(.secondary)
                }
                Text("On the camera: Network › Bluetooth › Bluetooth Function and Bluetooth Rmt Ctrl On, then Pairing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(remote.found) { camera in
                Button {
                    remote.connect(to: camera.id)
                } label: {
                    Label("Pair \(camera.name)", systemImage: "camera")
                }
            }
        case .connecting(let name):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Waiting for \(name)…").foregroundStyle(.secondary).lineLimit(2)
            }
            .help("Turn the camera on, with Bluetooth Rmt Ctrl on. Pairing the first time: accept it on the camera.")
            forgetButton
        case .connected(let name):
            Label {
                Text(name).lineLimit(1)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            HStack {
                Button("Test Shutter") { remote.fire() }
                forgetButton
            }
        }
    }

    private var forgetButton: some View {
        Button("Forget Camera") { remote.forget() }
            .help("Unpair this camera, to pair another")
    }
}

/// Crops new captures to a shape from the middle of the camera's picture.
private struct CropPicker: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var camera: CameraController

    var body: some View {
        GridRow {
            InspectorLabel("Crop")
            Picker("Crop", selection: Binding(get: { model.project.crop }, set: model.setCrop)) {
                Text("Full Frame").tag(FrameCrop?.none)
                Divider()
                ForEach(FrameCrop.presets) { Text($0.name).tag(Optional($0.crop)) }
                if let crop = model.project.crop, !FrameCrop.presets.contains(where: { $0.crop == crop }) {
                    Text(crop.name).tag(Optional(crop))
                }
            }
            .labelsHidden()
            .help("Crop new frames to this shape from the middle of the picture, without squeezing it")
        }
        if let detail {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// What the crop keeps of the camera's actual picture.
    private var detail: String? {
        guard let size = camera.videoSize else { return nil }
        let width = Int(size.width), height = Int(size.height)
        guard let crop = model.project.crop else { return "\(width) × \(height)" }
        let rect = crop.rect(sourceWidth: width, sourceHeight: height)
        return "\(Int(rect.width)) × \(Int(rect.height)) of \(width) × \(height)"
    }
}
