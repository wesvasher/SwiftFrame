import SwiftUI

// MARK: - Left sidebar: capture setup

/// The left sidebar: which camera, and how capturing and playback behave.
struct CaptureSidebar: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var camera: CameraController

    init(model: WindowModel) {
        self.model = model
        self.camera = model.camera
    }

    var body: some View {
        List {
            Section("Camera") {
                if camera.devices.isEmpty {
                    Label("No cameras found", systemImage: "video.slash")
                        .foregroundStyle(.secondary)
                }
                ForEach(camera.devices) { device in
                    Button {
                        model.selectCamera(device.id)
                    } label: {
                        Label {
                            Text(device.name).lineLimit(1)
                        } icon: {
                            Image(systemName: device.id == camera.deviceID ? "checkmark.circle.fill" : "web.camera")
                                .foregroundStyle(device.id == camera.deviceID ? Color.accentColor : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Toggle("Mirror", isOn: Binding(get: { model.project.mirrorCamera }, set: model.setMirror))
            }

            Section("Onion Skin") {
                Stepper(value: Binding(get: { model.project.onionSkinFrames }, set: model.setOnionSkinFrames),
                        in: 0...5) {
                    LabeledContent("Frames", value: model.project.onionSkinFrames == 0
                                   ? "Off" : "\(model.project.onionSkinFrames)")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Opacity \(Int((model.project.onionSkinOpacity * 100).rounded()))%")
                        .foregroundStyle(model.project.onionSkinFrames == 0 ? .tertiary : .secondary)
                    Slider(value: Binding(get: { model.project.onionSkinOpacity }, set: model.setOnionSkinOpacity),
                           in: 0.05...0.9)
                        .labelsHidden()
                }
                .disabled(model.project.onionSkinFrames == 0)
            }

            Section("Playback") {
                Picker("Frame Rate", selection: Binding(get: { model.project.framesPerSecond },
                                                       set: model.setFrameRate)) {
                    ForEach(Project.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
                    if !Project.frameRates.contains(model.project.framesPerSecond) {
                        // A custom rate from the capture bar's switch.
                        Text("\(model.project.framesPerSecond) fps").tag(model.project.framesPerSecond)
                    }
                }
                Toggle("Loop", isOn: Binding(get: { model.project.loopPlayback }, set: model.setLoop))
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
    }
}

// MARK: - Right sidebar: inspector

/// The right sidebar: the selected frame (or frames), or the project when
/// nothing is selected.
struct FrameInspector: View {
    @ObservedObject var model: WindowModel

    var body: some View {
        Form {
            let selected = model.frames.enumerated().filter { model.selection.contains($0.element.id) }
            if selected.count == 1, let (index, frame) = selected.first {
                single(frame, index: index)
            } else if selected.count > 1 {
                multiple(selected.map(\.element))
            } else {
                project
            }
        }
        .formStyle(.grouped)
        .inspectorColumnWidth(min: 220, ideal: 260, max: 360)
    }

    @ViewBuilder
    private func single(_ frame: Frame, index: Int) -> some View {
        Section {
            ZStack {
                Color.black
                FramePicture(image: model.images.thumbnail(frame.image, data: model.document.images[frame.image]))
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 6))
            .listRowInsets(EdgeInsets())
        }
        Section("Frame") {
            LabeledContent("Frame", value: "\(index + 1) of \(model.frames.count)")
            LabeledContent("Starts at", value: time(model.frames.playbackStart(ofIndex: index)))
            holdStepper(frame.hold)
        }
        actions
    }

    @ViewBuilder
    private func multiple(_ frames: [Frame]) -> some View {
        Section("Selection") {
            LabeledContent("Frames", value: "\(frames.count) selected")
            LabeledContent("Length", value: time(frames.playbackLength))
            let holds = Set(frames.map(\.hold))
            holdStepper(holds.count == 1 ? holds.first : nil)
        }
        actions
    }

    private var project: some View {
        Section("Project") {
            LabeledContent("Frames", value: "\(model.frames.count)")
            LabeledContent("Length", value: time(model.frames.playbackLength))
            LabeledContent("Frame Rate", value: "\(model.project.framesPerSecond) fps")
            Text("Click a frame in the timeline to inspect it.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// Hold for the selection; `hold` is nil when the frames differ.
    private func holdStepper(_ hold: Int?) -> some View {
        Stepper {
            LabeledContent("Hold", value: hold.map { $0 == 1 ? "1 frame" : "\($0) frames" } ?? "Mixed")
        } onIncrement: {
            model.changeHold(by: 1)
        } onDecrement: {
            model.changeHold(by: -1)
        }
    }

    private var actions: some View {
        Section {
            Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicateSelection() }
            if model.selection.count > 1 {
                Button("Reverse Order", systemImage: "arrow.left.arrow.right") { model.reverseSelection() }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { model.deleteSelection() }
        }
    }

    /// Playback frames as seconds at the project's frame rate.
    private func time(_ playbackFrames: Int) -> String {
        let seconds = Double(playbackFrames) / Double(max(model.project.framesPerSecond, 1))
        return seconds.formatted(.number.precision(.fractionLength(2))) + " s"
    }
}
