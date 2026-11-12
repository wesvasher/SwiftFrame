import SwiftUI
import UniformTypeIdentifiers

/// Every frame in order, then the live camera. Click to review a frame,
/// Shift- or Command-click to select more, drag to reorder, drop pictures
/// from Finder to add them.
struct FilmstripView: View {
    @ObservedObject var model: WindowModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: FilmstripLayout.spacing) {
                    ForEach(Array(model.frames.enumerated()), id: \.element.id) { index, frame in
                        FrameCell(model: model, frame: frame, number: index + 1)
                            .id(frame.id)
                    }
                    LiveCell(model: model).id(Self.liveID)
                }
                .padding(.horizontal, FilmstripLayout.inset)
                .padding(.top, FilmstripLayout.scrubHeight)
                .padding(.bottom, 8)
                .overlay(alignment: .top) {
                    if !model.frames.isEmpty { ScrubStrip(model: model) }
                }
                .overlay(alignment: .topLeading) {
                    if !model.frames.isEmpty { Playhead(model: model) }
                }
                .coordinateSpace(.named(FilmstripLayout.space))
            }
            .scrollIndicators(.visible)
            .onChange(of: model.frames.count) { old, new in
                if new > old, model.mode == .live { withAnimation { proxy.scrollTo(Self.liveID, anchor: .trailing) } }
            }
            .onChange(of: model.mode == .playback ? model.playingFrame : model.current) { _, id in
                if let id { proxy.scrollTo(id) }
            }
            .onChange(of: model.thumbnailWidth) {
                // Keep the frame being looked at in view after zooming.
                if let id = model.current { proxy.scrollTo(id, anchor: .center) }
                else { proxy.scrollTo(Self.liveID, anchor: .trailing) }
            }
        }
        .frame(height: FrameCell.height + FilmstripLayout.scrubHeight + 8)
        .background(.bar)
    }

    static let liveID = "live"
}

/// Where things sit along the filmstrip. Every frame cell is the same width,
/// so positions are simple arithmetic.
enum FilmstripLayout {
    static let inset: CGFloat = 10
    static let spacing: CGFloat = 4
    /// The cell's padding on each side of its thumbnail.
    static let cellPadding: CGFloat = 4
    /// The strip above the frames that moves the playhead.
    static let scrubHeight: CGFloat = 18
    static let space = "filmstrip"

    static func stride(_ thumbnailWidth: CGFloat) -> CGFloat { thumbnailWidth + cellPadding * 2 + spacing }

    /// The left edge of the cell at `index` (`frames.count` is the Live tile).
    static func cellX(_ index: Int, thumbnailWidth: CGFloat) -> CGFloat {
        inset + CGFloat(index) * stride(thumbnailWidth)
    }

    /// The cell under `x`; `frames.count` or more is the Live tile.
    static func index(at x: CGFloat, thumbnailWidth: CGFloat) -> Int {
        max(0, Int(((x - inset + spacing / 2) / stride(thumbnailWidth)).rounded(.down)))
    }
}

/// The strip above the frames: click or drag in it to move the playhead.
/// (Clicking a frame only selects it.)
private struct ScrubStrip: View {
    @ObservedObject var model: WindowModel

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: FilmstripLayout.scrubHeight)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(FilmstripLayout.space))
                    .onChanged { value in
                        model.scrub(toIndex: FilmstripLayout.index(at: value.location.x,
                                                                   thumbnailWidth: model.thumbnailWidth))
                    }
            )
            .help("Click or drag here to move the playhead")
            .accessibilityElement()
            .accessibilityLabel("Playhead")
            .accessibilityAdjustableAction { direction in model.step(direction == .increment ? 1 : -1) }
    }
}

/// A tall line across the filmstrip at the frame showing, like SwiftCut's
/// timeline playhead. It glides through each frame while playing and sits on
/// the middle of the frame otherwise. Drag it to scrub; the grab area is a few
/// points either side of the line, so clicks farther away still select the
/// frame underneath.
private struct Playhead: View {
    @ObservedObject var model: WindowModel
    @Environment(\.colorScheme) private var colorScheme
    /// Where the playhead was when a drag began, so grabbing it slightly off
    /// the line doesn't make it jump.
    @State private var dragStart: CGFloat?
    @State private var isHovered = false

    private let grabWidth: CGFloat = 12
    /// The line thickens while the pointer is over it, and stays thick while it's dragged.
    private var isActive: Bool { isHovered || dragStart != nil }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: model.mode != .playback)) { context in
                ZStack {
                    Color.clear
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(colorScheme == .dark ? Color.white : Color.black)
                        .shadow(radius: 2)
                        .frame(width: isActive ? 4 : 2)
                        // Faint while thin, so it doesn't hide the pictures; full strength when grabbed.
                        .opacity(isActive ? 1 : 0.35)
                }
                .animation(.easeOut(duration: 0.12), value: isActive)
                .frame(width: grabWidth, height: proxy.size.height - 4)
                .contentShape(.rect)
                .offset(x: x(at: context.date) - grabWidth / 2, y: 2)
                .gesture(drag)
                .onHover { isHovered = $0 }
                .help("Drag to move the playhead")
            }
        }
    }

    private func x(at date: Date) -> CGFloat {
        let width = model.thumbnailWidth
        let inside = FilmstripLayout.cellPadding
        if model.mode == .playback, let position = model.playbackPosition(at: date) {
            return FilmstripLayout.cellX(position.index, thumbnailWidth: width) + inside + width * position.fraction
        }
        if model.mode == .review, let id = model.current, let index = model.frames.firstIndex(of: id) {
            return FilmstripLayout.cellX(index, thumbnailWidth: width) + inside + width / 2
        }
        // Live: the middle of the Live tile.
        return FilmstripLayout.cellX(model.frames.count, thumbnailWidth: width) + inside + FrameCell.standardWidth / 2
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(FilmstripLayout.space))
            .onChanged { value in
                let start = dragStart ?? x(at: Date())
                dragStart = start
                model.scrub(toIndex: FilmstripLayout.index(at: start + value.translation.width,
                                                           thumbnailWidth: model.thumbnailWidth))
            }
            .onEnded { _ in dragStart = nil }
    }
}

private struct FrameCell: View {
    @ObservedObject var model: WindowModel
    let frame: Frame
    let number: Int
    @State private var isTargeted = false

    /// Thumbnails are always this tall; zooming the timeline changes only
    /// their width.
    static let thumbnailHeight: CGFloat = 63
    /// The width at which a 16:9 picture fits whole.
    static let standardWidth: CGFloat = 112
    /// The cell's height: the thumbnail plus its grab handle.
    static let height: CGFloat = thumbnailHeight + 29

    private var isSelected: Bool { model.selection.contains(frame.id) }
    private var isPlaying: Bool { model.mode == .playback && model.playingFrame == frame.id }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Color.black
                // Fitted to the height and centered: narrow frames show the
                // middle of the picture, wide ones leave black at the sides.
                FramePicture(image: model.images.thumbnail(frame.image, data: model.document.images[frame.image]))
                    .frame(height: FrameCell.thumbnailHeight)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: model.thumbnailWidth, height: FrameCell.thumbnailHeight)
            .clipShape(.rect(cornerRadius: 4))
            .overlay(alignment: .bottomTrailing) {
                if frame.hold > 1 {
                    Text("×\(frame.hold)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.black.opacity(0.7), in: .capsule)
                        .foregroundStyle(.white)
                        .padding(3)
                }
            }
            GripHandle(isSelected: isSelected)
                .frame(width: model.thumbnailWidth)
        }
        .padding(4)
        .background(isSelected ? Color.accentColor : .clear, in: .rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isPlaying ? Color.accentColor : .clear, lineWidth: 2)
        }
        .overlay(alignment: .leading) {
            // Where dropped frames will go.
            if isTargeted { Capsule().fill(Color.accentColor).frame(width: 3).offset(x: -3.5) }
        }
        .contentShape(.rect)
        .onTapGesture { model.click(frame.id, modifiers: NSEvent.modifierFlags) }
        .draggable(FrameDrag(id: frame.id)) {
            FramePicture(image: model.images.thumbnail(frame.image, data: model.document.images[frame.image]))
                .frame(width: FrameCell.standardWidth, height: FrameCell.thumbnailHeight)
        }
        .dropDestination(for: FrameDrop.self) { items, _ in
            handleDrop(items, before: frame.id)
        } isTargeted: { isTargeted = $0 }
        .contextMenu {
            FrameMenuItems(model: model, clicked: frame.id)
        }
        .help("Frame \(number)" + (frame.hold > 1 ? ", held for \(frame.hold) frames" : "")
              + ". Drag to move it; right-click for more.")
    }

    private func handleDrop(_ items: [FrameDrop], before target: UUID?) -> Bool {
        model.handleDrop(items, before: target)
    }
}

/// The grip under a thumbnail, showing the frame can be dragged.
private struct GripHandle: View {
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule().frame(width: 2.5, height: 9)
            }
        }
        .rotationEffect(.degrees(90))
        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.tertiary))
        .frame(maxWidth: .infinity, minHeight: 16)
        .contentShape(.rect)
        .pointerStyle(.grabIdle)
        .accessibilityLabel("Drag handle")
    }
}

private struct LiveCell: View {
    @ObservedObject var model: WindowModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                Image(systemName: "camera.fill").font(.title2).foregroundStyle(.secondary)
            }
            .frame(width: FrameCell.standardWidth, height: FrameCell.thumbnailHeight)
            Text("Live").font(.caption).foregroundStyle(model.mode == .live ? .white : .secondary)
        }
        .padding(4)
        .background(model.mode == .live ? Color.red.opacity(0.85) : .clear, in: .rect(cornerRadius: 7))
        .overlay(alignment: .leading) {
            if isTargeted { Capsule().fill(Color.accentColor).frame(width: 3).offset(x: -3.5) }
        }
        .contentShape(.rect)
        .onTapGesture { model.goLive() }
        .dropDestination(for: FrameDrop.self) { items, _ in
            model.handleDrop(items, before: nil)
        } isTargeted: { isTargeted = $0 }
        .help("Back to the live camera")
    }
}

/// The frame context menu. It acts on the selection, or on the clicked
/// frame when that isn't selected.
private struct FrameMenuItems: View {
    @ObservedObject var model: WindowModel
    let clicked: UUID

    var body: some View {
        Button("Copy Picture", systemImage: "doc.on.doc") { act { model.copyPicture(of: clicked) } }
        Button("Save Picture As…", systemImage: "square.and.arrow.down") { act { model.savePicture(of: clicked) } }
        Divider()
        Button("Duplicate", systemImage: "plus.square.on.square") { act { model.duplicateSelection() } }
        Button("Hold Longer", systemImage: "plus") { act { model.changeHold(by: 1) } }
        Button("Hold Shorter", systemImage: "minus") { act { model.changeHold(by: -1) } }
        if model.selection.count > 1, model.selection.contains(clicked) {
            Button("Reverse Order", systemImage: "arrow.left.arrow.right") { model.reverseSelection() }
        }
        Divider()
        Button("Move to Start", systemImage: "arrow.left.to.line") { act { model.moveSelection(toStart: true) } }
        Button("Move to End", systemImage: "arrow.right.to.line") { act { model.moveSelection(toStart: false) } }
        Button("Insert Pictures Before…", systemImage: "photo.badge.plus") { model.importImages(before: clicked) }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { act { model.deleteSelection() } }
    }

    private func act(_ action: () -> Void) {
        if !model.selection.contains(clicked) { model.select(clicked) }
        action()
    }
}

// MARK: - Drag and drop

extension UTType {
    static let swiftFrameFrame = UTType(exportedAs: "com.wesvasher.swiftframe.frame")
}

/// A frame dragged within one window's filmstrip.
struct FrameDrag: Codable, Transferable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .swiftFrameFrame)
    }
}

/// What the filmstrip accepts: its own frames, or picture files from Finder.
enum FrameDrop: Transferable {
    case frame(UUID)
    case file(URL)

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { (drag: FrameDrag) in FrameDrop.frame(drag.id) }
        ProxyRepresentation { (url: URL) in FrameDrop.file(url) }
    }
}

extension WindowModel {
    func handleDrop(_ items: [FrameDrop], before target: UUID?) -> Bool {
        var files: [URL] = []
        for item in items {
            switch item {
            case .frame(let id):
                guard frames.contains(where: { $0.id == id }) else { continue }
                move(dragged: id, before: target)
            case .file(let url):
                files.append(url)
            }
        }
        if !files.isEmpty { addImages(files, before: target) }
        return true
    }
}
