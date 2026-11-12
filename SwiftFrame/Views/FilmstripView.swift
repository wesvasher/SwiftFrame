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
                LazyHStack(spacing: 4) {
                    ForEach(Array(model.frames.enumerated()), id: \.element.id) { index, frame in
                        FrameCell(model: model, frame: frame, number: index + 1)
                            .id(frame.id)
                    }
                    LiveCell(model: model).id(Self.liveID)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.visible)
            .onChange(of: model.frames.count) { old, new in
                if new > old, model.mode == .live { withAnimation { proxy.scrollTo(Self.liveID, anchor: .trailing) } }
            }
            .onChange(of: model.mode == .playback ? model.playingFrame : model.current) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .frame(height: FrameCell.height + 16)
        .background(.bar)
    }

    static let liveID = "live"
}

private struct FrameCell: View {
    @ObservedObject var model: WindowModel
    let frame: Frame
    let number: Int
    @State private var isTargeted = false

    static let height: CGFloat = 92

    private var isSelected: Bool { model.selection.contains(frame.id) }
    private var isPlaying: Bool { model.mode == .playback && model.playingFrame == frame.id }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Color.black
                FramePicture(image: model.images.thumbnail(frame.image, data: model.document.images[frame.image]))
            }
            .frame(width: 112, height: 63)
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
            Text("\(number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(isSelected ? .white : .secondary)
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
                .frame(width: 112, height: 63)
        }
        .dropDestination(for: FrameDrop.self) { items, _ in
            handleDrop(items, before: frame.id)
        } isTargeted: { isTargeted = $0 }
        .contextMenu {
            FrameMenuItems(model: model, clicked: frame.id)
        }
        .help("Frame \(number)" + (frame.hold > 1 ? ", held for \(frame.hold) frames" : ""))
    }

    private func handleDrop(_ items: [FrameDrop], before target: UUID?) -> Bool {
        model.handleDrop(items, before: target)
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
            .frame(width: 112, height: 63)
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
        Button("Duplicate", systemImage: "plus.square.on.square") { act { model.duplicateSelection() } }
        Button("Hold Longer", systemImage: "plus") { act { model.changeHold(by: 1) } }
        Button("Hold Shorter", systemImage: "minus") { act { model.changeHold(by: -1) } }
        if model.selection.count > 1, model.selection.contains(clicked) {
            Button("Reverse Order", systemImage: "arrow.left.arrow.right") { model.reverseSelection() }
        }
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
