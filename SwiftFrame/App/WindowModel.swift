import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// The state of one capture window: its document, camera, what's selected
/// and what the viewer shows.
@MainActor
final class WindowModel: ObservableObject {
    enum Mode: Equatable {
        /// The live camera, with the onion skin.
        case live
        /// The selected frame, for checking and editing.
        case review
        /// The frames playing at the project's frame rate.
        case playback
    }

    let document: StopMotionDocument
    let camera = CameraController()
    let images = FrameImages()
    weak var undoManager: UndoManager?

    @Published var mode: Mode = .live
    @Published private(set) var selection: Set<UUID> = []
    /// The frame the viewer shows in review, and where Shift-click starts.
    @Published private(set) var current: UUID?
    /// The frame showing during playback, highlighted in the filmstrip.
    @Published var playingFrame: UUID?
    @Published private(set) var playbackStart = Date()
    @Published var flash = false
    @Published var exportProgress: Double?
    @Published var errorMessage: String?
    /// The width of the filmstrip's thumbnails, from `thumbnailWidths`. New
    /// windows start at the size last chosen.
    @Published private(set) var thumbnailWidth: CGFloat =
        WindowModel.thumbnailWidths.contains(CGFloat(UserDefaults.standard.double(forKey: "FilmstripThumbnailWidth")))
        ? CGFloat(UserDefaults.standard.double(forKey: "FilmstripThumbnailWidth")) : 112

    private var cancellables: Set<AnyCancellable> = []

    init(document: StopMotionDocument) {
        self.document = document
        // Menu commands and the filmstrip watch this model; pass on the
        // document's and camera's changes.
        document.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        camera.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    var frames: [Frame] { document.project.frames }
    var project: Project { document.project }
    var hasSelection: Bool { !selection.isEmpty }

    func edit(_ name: String, _ change: (inout Project) -> Void) {
        document.edit(name, undoManager: undoManager, change)
        pruneSelection()
    }

    // MARK: - Camera

    func startCamera() async {
        await camera.start(preferring: project.cameraID)
    }

    func selectCamera(_ id: String) {
        camera.select(id)
        edit("Choose Camera") { $0.cameraID = id }
        mode = .live
    }

    var canCapture: Bool { camera.status == .running }

    /// Adds the camera's current picture as a new frame at the end.
    func capture() {
        guard canCapture, let image = camera.captureStill(mirrored: project.mirrorCamera),
              let data = ImageCoding.jpeg(image)
        else {
            NSSound.beep()
            return
        }
        let imageID = document.addImage(data)
        images.store(image, for: imageID)
        let frame = Frame(image: imageID)
        edit("Capture Frame") { $0.frames.append(frame) }
        selection = []
        current = nil
        mode = .live
        flash = true
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            flash = false
        }
    }

    // MARK: - Viewer

    func goLive() {
        mode = .live
        selection = []
        current = nil
    }

    func togglePlayback() {
        if mode == .playback {
            stopPlayback()
        } else if !frames.isEmpty {
            playbackStart = Date()
            mode = .playback
        }
    }

    func stopPlayback() {
        guard mode == .playback else { return }
        if let id = playingFrame {
            selection = [id]
            current = id
            mode = .review
        } else {
            mode = current == nil ? .live : .review
        }
        playingFrame = nil
    }

    // MARK: - Filmstrip zoom

    static let thumbnailWidths: [CGFloat] = [48, 72, 112, 160, 240]

    var canZoomInTimeline: Bool { thumbnailWidth < Self.thumbnailWidths.last! }
    var canZoomOutTimeline: Bool { thumbnailWidth > Self.thumbnailWidths.first! }

    func zoomInTimeline() {
        if let next = Self.thumbnailWidths.first(where: { $0 > thumbnailWidth }) { setThumbnailWidth(next) }
    }

    func zoomOutTimeline() {
        if let next = Self.thumbnailWidths.last(where: { $0 < thumbnailWidth }) { setThumbnailWidth(next) }
    }

    private func setThumbnailWidth(_ width: CGFloat) {
        thumbnailWidth = width
        UserDefaults.standard.set(Double(width), forKey: "FilmstripThumbnailWidth")
    }

    // MARK: - Selection

    /// A click on a frame: Shift adds the range from the last clicked frame,
    /// Command adds or removes one.
    func click(_ id: UUID, modifiers: NSEvent.ModifierFlags) {
        if mode == .playback { mode = .review; playingFrame = nil }
        if modifiers.contains(.shift), let anchor = current {
            selection.formUnion(frames.ids(from: anchor, to: id))
        } else if modifiers.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
        current = id
        mode = selection.isEmpty ? .live : .review
    }

    func select(_ id: UUID) {
        selection = [id]
        current = id
        mode = .review
    }

    func selectAll() {
        selection = Set(frames.map(\.id))
        current = current ?? frames.first?.id
        if current != nil { mode = .review }
    }

    /// Moves the selection one frame left or right. Right of the last frame is
    /// the live camera.
    func step(_ offset: Int) {
        if mode == .playback { stopPlayback() }
        guard !frames.isEmpty else { return }
        let index = current.flatMap { frames.firstIndex(of: $0) } ?? frames.count
        let next = index + offset
        if next >= frames.count {
            goLive()
        } else {
            select(frames[max(next, 0)].id)
        }
    }

    private func pruneSelection() {
        let ids = Set(frames.map(\.id))
        selection.formIntersection(ids)
        if let c = current, !ids.contains(c) { current = nil }
        if mode == .review, current == nil { mode = .live }
        if mode == .playback, frames.isEmpty { mode = .live }
    }

    // MARK: - Editing

    func deleteSelection() {
        guard hasSelection else { return }
        let ids = selection
        var next: UUID?
        edit(ids.count == 1 ? "Delete Frame" : "Delete Frames") { next = $0.frames.remove(ids: ids) }
        if let next { select(next) } else { goLive() }
    }

    func duplicateSelection() {
        guard hasSelection else { return }
        let ids = selection
        var copies: [UUID] = []
        edit(ids.count == 1 ? "Duplicate Frame" : "Duplicate Frames") { copies = $0.frames.duplicate(ids: ids) }
        selection = Set(copies)
        current = copies.last
    }

    func changeHold(by delta: Int) {
        guard hasSelection else { return }
        let ids = selection
        edit("Change Hold") { $0.frames.changeHold(ids: ids, by: delta) }
    }

    func reverseSelection() {
        guard selection.count > 1 else { return }
        let ids = selection
        edit("Reverse Frames") { $0.frames.reverse(ids: ids) }
    }

    /// Drag and drop in the filmstrip: moves the dragged frame (or the whole
    /// selection, if it's part of it) before `target`, or to the end.
    func move(dragged: UUID, before target: UUID?) {
        let ids = selection.contains(dragged) ? selection : [dragged]
        edit(ids.count == 1 ? "Move Frame" : "Move Frames") { $0.frames.move(ids: ids, before: target) }
    }

    func setFrameRate(_ fps: Int) { edit("Change Frame Rate") { $0.framesPerSecond = fps } }
    func setOnionSkinFrames(_ n: Int) { edit("Change Onion Skin") { $0.onionSkinFrames = n } }
    func setOnionSkinOpacity(_ o: Double) { edit("Change Onion Skin") { $0.onionSkinOpacity = o } }
    func setMirror(_ on: Bool) { edit("Mirror Camera") { $0.mirrorCamera = on } }
    func setLoop(_ on: Bool) { edit("Loop Playback") { $0.loopPlayback = on } }

    // MARK: - Import

    func importImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose pictures to add as frames, in file name order."
        panel.prompt = "Add Frames"
        guard panel.runModal() == .OK else { return }
        addImages(panel.urls, before: nil)
    }

    /// Adds image files as frames, sorted by name, before `target` or at the end.
    func addImages(_ urls: [URL], before target: UUID?) {
        let sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let new = sorted.compactMap(ImageCoding.importFile).map { Frame(image: document.addImage($0)) }
        guard !new.isEmpty else {
            if !urls.isEmpty { errorMessage = "Those files couldn't be read as pictures." }
            return
        }
        edit(new.count == 1 ? "Add Frame" : "Add Frames") { project in
            let at = target.flatMap { project.frames.firstIndex(of: $0) } ?? project.frames.count
            project.frames.insert(contentsOf: new, at: at)
        }
        selection = Set(new.map(\.id))
        current = new.last?.id
        mode = .review
    }

    // MARK: - Export

    var codec: MovieExporter.Codec = .h264
    /// The suggested movie name, from the project's file name.
    var movieName = "Animation.mov"

    func exportMovie() {
        guard !frames.isEmpty, exportProgress == nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.quickTimeMovie]
        panel.nameFieldStringValue = movieName
        panel.message = "Export the animation as a QuickTime movie."
        let accessory = NSHostingView(rootView: CodecPicker(model: self))
        accessory.frame.size = accessory.fittingSize
        panel.accessoryView = accessory
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let items = frames.compactMap { frame in
            document.images[frame.image].map { MovieExporter.Item(data: $0, hold: frame.hold) }
        }
        let fps = project.framesPerSecond, codec = codec
        exportProgress = 0
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try await MovieExporter.export(items, framesPerSecond: fps, codec: codec, to: url) { value in
                        Task { @MainActor in self.exportProgress = value }
                    }
                }.value
                exportProgress = nil
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                exportProgress = nil
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct CodecPicker: View {
    @ObservedObject var model: WindowModel
    @State private var codec: MovieExporter.Codec = .h264

    var body: some View {
        Picker("Format:", selection: $codec) {
            ForEach(MovieExporter.Codec.allCases) { Text($0.rawValue).tag($0) }
        }
        .fixedSize()
        .padding(12)
        .onAppear { codec = model.codec }
        .onChange(of: codec) { model.codec = codec }
    }
}
