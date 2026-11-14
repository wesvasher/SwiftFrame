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
    /// The width of the filmstrip's frames, from `thumbnailWidths`; their
    /// height never changes. New projects start at 4:3; opened ones at the
    /// width last chosen.
    @Published private(set) var thumbnailWidth: CGFloat
    /// How far the viewer is zoomed in on the picture: 1 fits the whole picture.
    @Published private(set) var viewerZoom: CGFloat = 1
    /// How far the zoomed picture is moved from the middle, in points.
    @Published private(set) var viewerPan: CGSize = .zero
    /// Focus peaking over the live camera; new windows start as the last one was set.
    @Published var focusPeaking = FocusPeaking.saved {
        didSet { focusPeaking.save() }
    }
    /// Whether the live camera shows the onion skin (the timeline's Capture
    /// view) or just the plain camera. The project keeps its onion skin settings.
    @Published private(set) var showsOnionSkin = true
    /// Playing full screen: the window fills the screen with just the animation.
    @Published private(set) var isPlayingFullScreen = false

    private var cancellables: Set<AnyCancellable> = []

    init(document: StopMotionDocument, isNew: Bool = true) {
        self.document = document
        let saved = CGFloat(UserDefaults.standard.double(forKey: "FilmstripThumbnailWidth"))
        thumbnailWidth = !isNew && Self.thumbnailWidths.contains(saved) ? saved : Self.standardThumbnailWidth
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
        guard canCapture, let image = camera.captureStill(mirrored: project.mirrorCamera, crop: project.crop),
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
        // The picture's already taken from the camera's video, before the
        // shutter blanks it, so the camera's own photo follows.
        if ShutterRemote.shared.isEnabled { ShutterRemote.shared.fire() }
        guard GeneralSettings.flashOnCapture else { return }
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

    /// Switches the live camera between plain and with the onion skin, going
    /// live to show it.
    func setShowsOnionSkin(_ on: Bool) {
        showsOnionSkin = on
        if mode != .live { goLive() }
    }

    func togglePlayback() {
        if mode == .playback {
            stopPlayback()
        } else if let range = playRange {
            // Resume from the frame being looked at (where playback was
            // paused) if it's between the marks, or start over from the in
            // mark (from live, the last frame, or outside the marks).
            var startIndex = range.lowerBound
            if mode == .review, let id = current, let index = frames.firstIndex(of: id),
               range.contains(index), index < range.upperBound {
                startIndex = index
            }
            startPlayback(fromIndex: startIndex)
        }
    }

    /// Fills the screen with the animation and plays it from the start (the
    /// in mark, if there is one).
    func playFullScreen() {
        guard let range = playRange else { return }
        isPlayingFullScreen = true
        startPlayback(fromIndex: range.lowerBound)
    }

    // MARK: - In and out marks

    /// The first and last frames to play, by id; nil is the first or last
    /// frame of the animation, so new captures at the end are included.
    /// Not saved with the project.
    @Published private(set) var markIn: UUID?
    @Published private(set) var markOut: UUID?

    /// The frames playback covers, by index.
    var playRange: ClosedRange<Int>? { frames.playRange(in: markIn, out: markOut) }

    /// Whether the marks narrow playback to part of the animation.
    var hasMarks: Bool {
        guard let range = playRange else { return false }
        return range != 0...(frames.count - 1)
    }

    /// The frame the in and out commands mark: the one showing.
    private var markableIndex: Int? {
        let id = mode == .playback ? playingFrame : (mode == .review ? current : nil)
        return id.flatMap { frames.firstIndex(of: $0) }
    }

    var canMark: Bool { markableIndex != nil }

    /// Starts playback at the frame showing (I). An out mark before it goes.
    func markInAtCurrent() {
        guard let index = markableIndex, let range = playRange else { return }
        setPlayRange(index...max(index, range.upperBound))
    }

    /// Stops playback after the frame showing (O). An in mark after it goes.
    func markOutAtCurrent() {
        guard let index = markableIndex, let range = playRange else { return }
        setPlayRange(min(index, range.lowerBound)...index)
    }

    /// Plays the whole animation again.
    func clearMarks() {
        markIn = nil
        markOut = nil
    }

    /// Plays only these frames, by index. An end at the first or last frame
    /// is left unmarked, so it follows frames added there.
    func setPlayRange(_ range: ClosedRange<Int>) {
        guard !frames.isEmpty else { return }
        let lower = min(max(range.lowerBound, 0), frames.count - 1)
        let upper = min(max(range.upperBound, lower), frames.count - 1)
        markIn = lower == 0 ? nil : frames[lower].id
        markOut = upper == frames.count - 1 ? nil : frames[upper].id
    }

    /// Back to the window, paused where it was.
    func endFullScreen() {
        guard isPlayingFullScreen else { return }
        isPlayingFullScreen = false
        if mode == .playback { stopPlayback() }
    }

    func toggleFullScreenPlayback() {
        if isPlayingFullScreen { endFullScreen() } else { playFullScreen() }
    }

    /// `playbackStart` is when the in mark's frame showed (or would have).
    private func startPlayback(fromIndex index: Int) {
        let fps = Double(max(project.framesPerSecond, 1))
        let first = playRange?.lowerBound ?? 0
        let offset = Double(frames.playbackStart(ofIndex: index) - frames.playbackStart(ofIndex: first)) / fps
        playbackStart = Date().addingTimeInterval(-offset)
        mode = .playback
    }

    /// Where playback is at `date`, between the in and out marks: the frame
    /// showing, how far through its hold (0 to 1), and whether a non-looping
    /// playback has reached the out mark.
    func playbackPosition(at date: Date) -> (index: Int, fraction: Double, finished: Bool)? {
        guard let range = playRange else { return nil }
        let fps = Double(max(project.framesPerSecond, 1))
        return frames.playbackPosition(at: date.timeIntervalSince(playbackStart) * fps,
                                       in: range, loops: project.loopPlayback)
    }

    /// Moves the playhead to a frame: pauses playback and shows that frame.
    /// Past the last frame is the live camera.
    func scrub(toIndex index: Int) {
        guard !frames.isEmpty else { return }
        if index >= frames.count {
            if mode != .live { goLive() }
            return
        }
        let id = frames[min(max(index, 0), frames.count - 1)].id
        playingFrame = nil
        guard current != id || mode != .review else { return }
        select(id)
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

    /// 4:3, the shape of most camera pictures, at the filmstrip's height.
    static let standardThumbnailWidth: CGFloat = 84   // 63 × 4 / 3; FrameCell.thumbnailHeight is 63
    static let thumbnailWidths: [CGFloat] = [24, 40, 64, standardThumbnailWidth, 112, 168, 240]

    var canZoomInTimeline: Bool { thumbnailWidth < Self.thumbnailWidths.last! }
    var canZoomOutTimeline: Bool { thumbnailWidth > Self.thumbnailWidths.first! }
    /// The filmstrip's visible width, for zooming to fit.
    var filmstripVisibleWidth: CGFloat = 0

    var canZoomTimelineToFit: Bool {
        !frames.isEmpty && abs(fitWidth - thumbnailWidth) > 0.5
    }

    private var fitWidth: CGFloat {
        FilmstripLayout.fitWidth(count: frames.count, visibleWidth: filmstripVisibleWidth,
                                 maxWidth: Self.thumbnailWidths.last!)
    }

    /// Zooms the timeline out (or in) so every frame fits beside the Capture tile.
    func zoomTimelineToFit() {
        guard !frames.isEmpty, filmstripVisibleWidth > 0 else { return }
        setThumbnailWidth(fitWidth)
    }

    func zoomInTimeline() {
        if let next = Self.thumbnailWidths.first(where: { $0 > thumbnailWidth }) { setThumbnailWidth(next) }
    }

    func zoomOutTimeline() {
        if let next = Self.thumbnailWidths.last(where: { $0 < thumbnailWidth }) { setThumbnailWidth(next) }
    }

    private func setThumbnailWidth(_ width: CGFloat) {
        thumbnailWidth = width
        // Fit widths depend on the project, so new windows only start at a step.
        if Self.thumbnailWidths.contains(width) {
            UserDefaults.standard.set(Double(width), forKey: "FilmstripThumbnailWidth")
        }
    }

    // MARK: - Viewer zoom

    static let viewerZooms: [CGFloat] = [1, 1.5, 2, 3, 4, 6, 8]
    static let viewerZoomRange: ClosedRange<CGFloat> = 1...8
    /// The viewer's size, for keeping a zoomed picture inside it.
    var viewerSize: CGSize = .zero

    var canZoomInViewer: Bool { viewerZoom < Self.viewerZoomRange.upperBound - 0.001 }
    var canZoomOutViewer: Bool { viewerZoom > 1.001 }

    func zoomInViewer() {
        setViewerZoom(Self.viewerZooms.first { $0 > viewerZoom + 0.001 } ?? Self.viewerZoomRange.upperBound)
    }

    func zoomOutViewer() {
        setViewerZoom(Self.viewerZooms.last { $0 < viewerZoom - 0.001 } ?? 1)
    }

    func zoomViewerToFit() { setViewerZoom(1) }

    /// Zooms about the middle of the view, keeping what's there in the middle.
    func setViewerZoom(_ zoom: CGFloat) {
        let zoom = min(max(zoom, Self.viewerZoomRange.lowerBound), Self.viewerZoomRange.upperBound)
        let ratio = zoom / viewerZoom
        viewerZoom = zoom
        panViewer(to: CGSize(width: viewerPan.width * ratio, height: viewerPan.height * ratio))
    }

    /// Moves the zoomed picture, as far as its edges reach the view's.
    func panViewer(to pan: CGSize) {
        let maxX = viewerSize.width * (viewerZoom - 1) / 2
        let maxY = viewerSize.height * (viewerZoom - 1) / 2
        viewerPan = CGSize(width: min(max(pan.width, -maxX), maxX),
                           height: min(max(pan.height, -maxY), maxY))
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

    /// The copies the last Duplicate made, so the filmstrip can slide them
    /// out from under their originals.
    @Published private(set) var newCopies: Set<UUID> = []

    /// Copies the selected frames to just after the last of them, animated:
    /// the copies slide out from under the originals and the frames after
    /// them make room.
    func duplicateSelection() {
        guard hasSelection else { return }
        let ids = selection
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            var copies: [UUID] = []
            edit(ids.count == 1 ? "Duplicate Frame" : "Duplicate Frames") { copies = $0.frames.duplicate(ids: ids) }
            newCopies = Set(copies)
            selection = Set(copies)
            current = copies.last
        }
    }

    /// Whether the selection can move that way at all.
    func canShiftSelection(by delta: Int) -> Bool {
        let picked = frames.indices.filter { selection.contains(frames[$0].id) }
        guard let first = picked.first, let last = picked.last else { return false }
        return delta < 0 ? first > 0 : last < frames.count - 1
    }

    /// Moves the selected frames `delta` places along the timeline, animated.
    func shiftSelection(by delta: Int) {
        guard hasSelection, canShiftSelection(by: delta) else { return }
        let ids = selection
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            edit(ids.count == 1 ? "Move Frame" : "Move Frames") { $0.frames.shift(ids: ids, by: delta) }
        }
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

    /// Moves the selected frames, in order, to the start or the end.
    func moveSelection(toStart: Bool) {
        guard hasSelection else { return }
        let ids = selection
        let target = toStart ? frames.first(where: { !ids.contains($0.id) })?.id : nil
        edit(ids.count == 1 ? "Move Frame" : "Move Frames") { $0.frames.move(ids: ids, before: target) }
    }

    /// Puts the frame's picture on the clipboard.
    func copyPicture(of id: UUID) {
        guard let frame = frames.first(where: { $0.id == id }), let data = document.images[frame.image],
              let image = NSImage(data: data)
        else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    /// Saves the frame's picture as a JPEG file.
    func savePicture(of id: UUID) {
        guard let index = frames.firstIndex(of: id), let data = document.images[frames[index].image] else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg]
        panel.nameFieldStringValue = "\(movieName.replacingOccurrences(of: ".mov", with: "")) frame \(index + 1).jpg"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setFrameRate(_ fps: Int) { edit("Change Frame Rate") { $0.framesPerSecond = fps } }
    func setOnionSkinFrames(_ n: Int) { edit("Change Onion Skin") { $0.onionSkinFrames = n } }
    func setOnionSkinOpacity(_ o: Double) { edit("Change Onion Skin") { $0.onionSkinOpacity = o } }
    func setMirror(_ on: Bool) { edit("Mirror Camera") { $0.mirrorCamera = on } }
    func setCrop(_ crop: FrameCrop?) { edit("Change Crop") { $0.crop = crop } }
    func setLoop(_ on: Bool) { edit("Loop Playback") { $0.loopPlayback = on } }

    // MARK: - Import

    func importImages(before target: UUID? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose pictures to add as frames, in file name order."
        panel.prompt = "Add Frames"
        guard panel.runModal() == .OK else { return }
        addImages(panel.urls, before: target)
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

    /// How the last export was set up; the Export sheet starts from it.
    @Published var exportSettings = ExportSettings.saved {
        didSet { exportSettings.save() }
    }
    @Published var showsExportSheet = false
    /// The suggested movie name, from the project's file name.
    var movieName = "Animation.mov"

    /// Opens the Export sheet.
    func exportMovie() {
        guard !frames.isEmpty, exportProgress == nil else { return }
        showsExportSheet = true
    }

    /// Asks where to save, then exports as `exportSettings` says.
    func export() {
        showsExportSheet = false
        guard !frames.isEmpty, exportProgress == nil else { return }
        let settings = exportSettings
        // After the sheet has gone.
        DispatchQueue.main.async { self.runExport(settings) }
    }

    private func runExport(_ settings: ExportSettings) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [settings.contentType]
        panel.nameFieldStringValue = settings.fileName(for: (movieName as NSString).deletingPathExtension)
        panel.message = switch settings.kind {
        case .movie: "Export the animation as a \(settings.codec.rawValue) movie."
        case .gif: "Export the animation as an animated GIF."
        case .images: "Export the animation as a new folder of \(settings.imageFormat.name) pictures."
        }
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let items = frames.compactMap { frame in
            document.images[frame.image].map { MovieExporter.Item(data: $0, hold: frame.hold) }
        }
        let fps = project.framesPerSecond
        exportProgress = 0
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try await MovieExporter.export(items, framesPerSecond: fps, settings: settings, to: url) { value in
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
