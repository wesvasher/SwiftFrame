import SwiftUI
import UniformTypeIdentifiers

/// Every frame in order, with the Capture tile pinned at the right edge (the
/// frames scroll underneath it). Click to review a frame, Shift- or
/// Command-click to select more, drag to reorder, drop pictures from Finder
/// to add them.
struct FilmstripView: View {
    @ObservedObject var model: WindowModel
    @State private var scrollPosition = ScrollPosition(edge: .leading)
    /// The scroll view's offset, content width and visible width.
    @State private var scrollX: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var visibleWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // The navigator's space is always kept, so the window's layout
            // doesn't jump when zooming makes the strip scroll.
            ZStack {
                if isZoomedIn {
                    navigator.transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: StripNavigator<EmptyView>.height)
            .padding(.horizontal, FilmstripLayout.inset)
            .padding(.top, 6)
            strip
        }
        .animation(.easeOut(duration: 0.15), value: isZoomedIn)
        .background(.bar)
    }

    private var strip: some View {
        ScrollView(.horizontal) {
            FilmstripContent(model: model)
        }
        .scrollIndicators(.visible)
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: [CGFloat].self) {
            [$0.contentOffset.x, $0.contentSize.width, $0.containerSize.width]
        } action: { _, new in
            scrollX = new[0]
            contentWidth = new[1]
            visibleWidth = new[2]
            model.filmstripVisibleWidth = new[2]
        }
        .overlay(alignment: .trailing) {
            CaptureTile(model: model)
                .padding(.top, FilmstripLayout.headerHeight)
                .padding(.bottom, 8)
                .padding(.horizontal, FilmstripLayout.inset)
                .frame(maxHeight: .infinity)
                .background(.bar)
                .overlay(alignment: .leading) { Divider() }
                .shadow(color: .black.opacity(0.12), radius: 6, x: -3)
        }
        .onChange(of: model.frames.count) { old, new in
            if new > old, model.mode == .live { withAnimation { scrollPosition.scrollTo(edge: .trailing) } }
        }
        .onChange(of: model.mode == .playback ? model.playingFrame : model.current) { _, id in
            if let id, !isInView(id) { scrollPosition.scrollTo(id: id, anchor: .center) }
        }
        .onChange(of: model.thumbnailWidth) {
            // Keep the frame being looked at in view after zooming.
            if let id = model.current { scrollPosition.scrollTo(id: id, anchor: .center) }
            else { scrollPosition.scrollTo(edge: .trailing) }
        }
        .frame(height: FrameCell.height + FilmstripLayout.headerHeight + 8)
    }

    /// The width the frames can be seen in: the scroll view less the Capture tile.
    private var unobscuredWidth: CGFloat { max(0, visibleWidth - FilmstripLayout.endSpaceWidth - FilmstripLayout.inset) }

    /// Whether the frames run past the visible width (so the strip scrolls).
    private var isZoomedIn: Bool {
        !model.frames.isEmpty && visibleWidth > 0 && contentWidth > visibleWidth + 1
    }

    private func isInView(_ id: UUID) -> Bool {
        guard let index = model.frames.firstIndex(of: id) else { return true }
        let x = FilmstripLayout.cellX(index, thumbnailWidth: model.thumbnailWidth)
        return x >= scrollX && x + FilmstripLayout.stride(model.thumbnailWidth) <= scrollX + unobscuredWidth
    }

    /// SwiftCut's zoom navigator: the whole timeline in miniature, with the
    /// part in view outlined. Drag the box to scroll; click elsewhere to jump.
    private var navigator: some View {
        let width = model.thumbnailWidth
        return StripNavigator(
            contentWidth: contentWidth,
            visible: scrollX...(scrollX + max(1, unobscuredWidth)),
            playheadX: playheadX,
            scroll: { left in
                scrollX = left
                scrollPosition.scrollTo(x: left)
            }
        ) { mapWidth in
            let scale = mapWidth / max(1, contentWidth)
            NavigatorOverview(model: model, scale: scale, thumbnailWidth: width)
        }
    }

    /// The playhead's place along the strip, for the navigator.
    private var playheadX: CGFloat? {
        let width = model.thumbnailWidth
        let index: Int?
        if model.mode == .playback, let id = model.playingFrame {
            index = model.frames.firstIndex(of: id)
        } else if model.mode == .review, let id = model.current {
            index = model.frames.firstIndex(of: id)
        } else {
            return FilmstripLayout.playheadX(model.frames.count, thumbnailWidth: width)
        }
        return index.map { FilmstripLayout.playheadX($0, thumbnailWidth: width) }
    }
}

/// The frames in miniature for the navigator. Long animations draw a
/// picture for only some frames, so the overview stays quick.
private struct NavigatorOverview: View {
    @ObservedObject var model: WindowModel
    let scale: CGFloat
    let thumbnailWidth: CGFloat

    var body: some View {
        let frames = model.frames
        let cellWidth = max(1, thumbnailWidth * scale)
        // About one picture per 8 points of navigator.
        let step = max(1, Int((8 / max(cellWidth, 0.1)).rounded(.up)))
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.quaternary.opacity(0.5))
            ForEach(Array(Swift.stride(from: 0, to: frames.count, by: step)), id: \.self) { index in
                let frame = frames[index]
                let x = FilmstripLayout.cellX(index, thumbnailWidth: thumbnailWidth) * scale
                ZStack {
                    Color.black
                    FramePicture(image: model.images.thumbnail(frame.image, data: model.document.images[frame.image]))
                        .scaledToFill()
                }
                .frame(width: max(1, cellWidth * CGFloat(step) - (step == 1 ? 1 : 0)))
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .offset(x: x)
            }
        }
    }
}

/// The frames, then room for the pinned Capture tile, with the scrub strip
/// and playhead over them.
struct FilmstripContent: View {
    @ObservedObject var model: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LazyHStack(spacing: FilmstripLayout.spacing(model.thumbnailWidth)) {
            ForEach(Array(model.frames.enumerated()), id: \.element.id) { index, frame in
                FrameCell(model: model, frame: frame, number: index + 1)
                    .id(frame.id)
                    // Copies slide out from their originals; frames going to or
                    // coming back from the recycle bin shrink and fade.
                    .transition(model.newCopies.contains(frame.id) ? copyTransition : binTransition)
            }
            // Room for the pinned Capture tile, so the last frame can scroll
            // out from under it. Dropping here moves to the end.
            EndSpace(model: model)
        }
        .padding(.leading, FilmstripLayout.inset)
        .padding(.top, FilmstripLayout.headerHeight)
        .padding(.bottom, 8)
        .overlay(alignment: .topLeading) {
            // The in-to-out bar, on its own row above the frames.
            if !model.frames.isEmpty { RangeStrip(model: model) }
        }
        .overlay(alignment: .top) {
            if !model.frames.isEmpty {
                ScrubStrip(model: model).padding(.top, FilmstripLayout.rangeHeight)
            }
        }
        .overlay(alignment: .topLeading) {
            if !model.frames.isEmpty {
                Playhead(model: model).padding(.top, FilmstripLayout.rangeHeight)
            }
        }
        .coordinateSpace(.named(FilmstripLayout.space))
    }

    /// A new copy starts on top of its original, a little smaller, and slides
    /// out into its place as the frames after it move over. Just a fade with
    /// Reduce Motion on.
    private var binTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity)
    }

    /// Duplicates slide out from under their originals; Option-dragged
    /// copies pop up where they're dropped. Both grow from small, so the
    /// bouncy animation overshoots a little as they land.
    private var copyTransition: AnyTransition {
        if reduceMotion { return .opacity }
        switch model.copyStyle {
        case .slide:
            let count = CGFloat(max(1, model.newCopies.count))
            return .asymmetric(
                insertion: .offset(x: -FilmstripLayout.stride(model.thumbnailWidth) * count)
                    .combined(with: .scale(scale: 0.7))
                    .combined(with: .opacity),
                removal: .opacity)
        case .pop:
            return .asymmetric(
                insertion: .scale(scale: 0.3, anchor: .bottom).combined(with: .opacity),
                removal: .opacity)
        }
    }
}

/// Where things sit along the filmstrip. Every frame cell is the same width,
/// so positions are simple arithmetic.
enum FilmstripLayout {
    static let inset: CGFloat = 10
    /// Below this width frames shrink their padding and gaps too, so a fully
    /// zoomed-out timeline can fit many frames.
    static let compactWidth: CGFloat = 24
    /// The Capture tile's width, padding included; it never zooms.
    static let liveCellWidth: CGFloat = 112 + 8   // FrameCell.standardWidth + padding
    /// The space after the last frame: exactly what the pinned Capture tile
    /// covers (the tile and its inset on both sides), so the last frame and
    /// the live playhead are never hidden under it.
    static let endSpaceWidth: CGFloat = liveCellWidth + inset * 2

    /// The gap between cells and each cell's padding around its thumbnail
    /// (the selection color shows in the padding): 5 points between pictures.
    static let gap: CGFloat = 1
    static let padding: CGFloat = 2

    /// The gap between cells.
    static func spacing(_ thumbnailWidth: CGFloat) -> CGFloat {
        thumbnailWidth >= compactWidth ? gap : thumbnailWidth / 24
    }

    /// The cell's padding on each side of its thumbnail.
    static func cellPadding(_ thumbnailWidth: CGFloat) -> CGFloat {
        thumbnailWidth >= compactWidth ? padding : thumbnailWidth / 12
    }
    /// The strip above the frames that moves the playhead.
    static let scrubHeight: CGFloat = 18
    /// The in-to-out bar's row, above the scrub strip.
    static let rangeHeight: CGFloat = 16
    /// Everything above the frames.
    static let headerHeight: CGFloat = rangeHeight + scrubHeight
    static let space = "filmstrip"

    static func stride(_ thumbnailWidth: CGFloat) -> CGFloat {
        thumbnailWidth + cellPadding(thumbnailWidth) * 2 + spacing(thumbnailWidth)
    }

    /// The widest thumbnail (up to `maxWidth`) at which `count` frames and the
    /// Capture tile all fit in `visibleWidth`.
    static func fitWidth(count: Int, visibleWidth: CGFloat, maxWidth: CGFloat) -> CGFloat {
        guard count > 0 else { return maxWidth }
        let available = visibleWidth - inset - endSpaceWidth
        let perFrame = available / CGFloat(count)
        // Full padding and gaps above the compact width…
        let full = padding * 2 + gap
        if perFrame - full >= compactWidth { return min(perFrame - full, maxWidth) }
        // …and shrinking with the width below it (stride 1.25 × width), down
        // to half a point wide.
        return max(0.5, min(perFrame / 1.25, compactWidth - 0.01))
    }

    /// The left edge of the cell at `index` (`frames.count` is the space under the Capture tile).
    static func cellX(_ index: Int, thumbnailWidth: CGFloat) -> CGFloat {
        inset + CGFloat(index) * stride(thumbnailWidth)
    }

    /// The boundary between cells nearest `x`: 0 is before the first frame,
    /// `n` is after frame `n - 1`.
    static func boundary(at x: CGFloat, thumbnailWidth: CGFloat) -> Int {
        max(0, Int(((x - inset) / stride(thumbnailWidth)).rounded()))
    }

    /// Where the playhead sits for the frame at `index`: in the gap just
    /// before it (`frames.count` is the gap after the last frame).
    static func playheadX(_ index: Int, thumbnailWidth: CGFloat) -> CGFloat {
        cellX(index, thumbnailWidth: thumbnailWidth) - spacing(thumbnailWidth) / 2
    }

    /// The cell under `x`; `frames.count` or more is past the last frame.
    static func index(at x: CGFloat, thumbnailWidth: CGFloat) -> Int {
        max(0, Int(((x - inset + spacing(thumbnailWidth) / 2) / stride(thumbnailWidth)).rounded(.down)))
    }
}

/// The in-to-out bar above the frames: playback starts at its left end and
/// stops (or loops) at its right end. Drag an end to move it, drag the bar to
/// move both, double-click it to play everything again. Faint until marked.
private struct RangeStrip: View {
    @ObservedObject var model: WindowModel
    /// The marks when a drag began.
    @State private var dragStart: ClosedRange<Int>?
    @State private var isHovered = false

    private enum End { case start, end }
    private let handleWidth: CGFloat = 8

    var body: some View {
        let width = model.thumbnailWidth
        let range = model.playRange ?? 0...0
        let x0 = FilmstripLayout.cellX(range.lowerBound, thumbnailWidth: width)
        let x1 = FilmstripLayout.cellX(range.upperBound + 1, thumbnailWidth: width) - FilmstripLayout.spacing(width)
        let marked = model.hasMarks
        let tint = marked ? Color.accentColor : Color.secondary
        let height = FilmstripLayout.rangeHeight - 4

        ZStack(alignment: .topLeading) {
            Color.clear
            // The bar, with a handle at each end.
            RoundedRectangle(cornerRadius: 4)
                .fill(tint.opacity(marked ? 0.3 : (isHovered ? 0.18 : 0.1)))
                .strokeBorder(tint.opacity(marked ? 0.9 : 0.35), lineWidth: 1)
                .frame(width: max(x1 - x0, handleWidth * 2), height: height)
                .contentShape(.rect)
                .gesture(moveBoth)
                .onTapGesture(count: 2) { withAnimation(.snappy(duration: 0.2)) { model.clearMarks() } }
                .pointerStyle(dragStart != nil ? .grabActive : .grabIdle)
                .offset(x: x0, y: 2)
            handle(.start, tint: tint, marked: marked)
                .offset(x: x0, y: 2)
            handle(.end, tint: tint, marked: marked)
                .offset(x: max(x1, x0 + handleWidth * 2) - handleWidth, y: 2)
        }
        .frame(height: FilmstripLayout.rangeHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.18), value: model.playRange)
        .contextMenu {
            Button("Set In at Current Frame") { model.markInAtCurrent() }.disabled(!model.canMark)
            Button("Set Out at Current Frame") { model.markOutAtCurrent() }.disabled(!model.canMark)
            Button("Clear In and Out") { model.clearMarks() }.disabled(!model.hasMarks)
        }
        .help(marked
              ? "Playback runs between these ends. Drag an end or the bar to change it; double-click to play everything (I, O, ⌥X)"
              : "Drag an end to play only part of the animation (I, O)")
        .accessibilityElement()
        .accessibilityLabel("Playback range")
        .accessibilityValue(marked ? "Frames \(range.lowerBound + 1) to \(range.upperBound + 1)" : "All frames")
    }

    private func handle(_ end: End, tint: Color, marked: Bool) -> some View {
        UnevenRoundedRectangle(cornerRadii: end == .start
                               ? .init(topLeading: 4, bottomLeading: 4)
                               : .init(bottomTrailing: 4, topTrailing: 4))
            .fill(tint.opacity(marked ? 1 : 0.45))
            .overlay {
                Capsule().fill(.white.opacity(0.85)).frame(width: 1.5, height: 6)
            }
            .frame(width: handleWidth, height: FilmstripLayout.rangeHeight - 4)
            // A wider grab area than it looks.
            .padding(.horizontal, 3)
            .contentShape(.rect)
            .padding(.horizontal, -3)
            .gesture(moveEnd(end))
            .pointerStyle(.frameResize(position: end == .start ? .leading : .trailing))
    }

    private func moveEnd(_ end: End) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(FilmstripLayout.space))
            .onChanged { value in
                guard let range = model.playRange else { return }
                let boundary = FilmstripLayout.boundary(at: value.location.x, thumbnailWidth: model.thumbnailWidth)
                switch end {
                case .start: model.setPlayRange(min(boundary, range.upperBound)...range.upperBound)
                case .end: model.setPlayRange(range.lowerBound...max(boundary - 1, range.lowerBound))
                }
            }
    }

    private var moveBoth: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(FilmstripLayout.space))
            .onChanged { value in
                guard let start = dragStart ?? model.playRange else { return }
                dragStart = start
                let last = model.frames.count - 1
                let steps = Int((value.translation.width / FilmstripLayout.stride(model.thumbnailWidth)).rounded())
                let shift = min(max(steps, -start.lowerBound), last - start.upperBound)
                model.setPlayRange((start.lowerBound + shift)...(start.upperBound + shift))
            }
            .onEnded { _ in dragStart = nil }
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
    @State private var sparks = FireTrail.Sparks()
    @AppStorage(GeneralSettings.habaneroModeKey) private var showsFire = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let grabWidth: CGFloat = 12
    /// The line thickens while the pointer is over it, and stays thick while it's dragged.
    private var isActive: Bool { isHovered || dragStart != nil }

    var body: some View {
        GeometryReader { proxy in
            if model.mode == .playback {
                // Made fresh each time playback starts: a paused TimelineView
                // doesn't always start ticking again when unpaused.
                TimelineView(.animation) { context in
                    let x = x(at: context.date)
                    ZStack(alignment: .topLeading) {
                        if showsFire, !reduceMotion {
                            FireTrail(sparks: sparks, date: context.date, x: x, origin: x - FireTrail.reach)
                                .frame(width: FireTrail.reach + FireTrail.lead, height: proxy.size.height)
                                .offset(x: x - FireTrail.reach)
                        }
                        line(height: proxy.size.height, x: x)
                    }
                }
                .onAppear { sparks.reset() }
            } else {
                line(height: proxy.size.height, x: x(at: Date()))
            }
        }
    }

    private func line(height: CGFloat, x: CGFloat) -> some View {
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
        .frame(width: grabWidth, height: height - 4)
        .contentShape(.rect)
        .offset(x: x - grabWidth / 2, y: 2)
        .gesture(drag)
        .onHover { isHovered = $0 }
        .help("Drag to move the playhead")
    }

    /// The start of the frame at `index`: the gap just before it, so the
    /// line stays clear of the frame's picture and grab handle.
    private func start(_ index: Int) -> CGFloat {
        FilmstripLayout.playheadX(index, thumbnailWidth: model.thumbnailWidth)
    }

    private func x(at date: Date) -> CGFloat {
        let width = model.thumbnailWidth
        if model.mode == .playback, let position = model.playbackPosition(at: date) {
            // Glides evenly from this frame's start to the next one's over
            // the frame's time on screen (1/12 s at 12 fps, longer when held).
            return start(position.index) + FilmstripLayout.stride(width) * position.fraction
        }
        if model.mode == .review, let id = model.current, let index = model.frames.firstIndex(of: id) {
            return start(index)
        }
        // Live: in the gap after the last frame, where the next capture goes.
        return start(model.frames.count)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(FilmstripLayout.space))
            .onChanged { value in
                let start = dragStart ?? x(at: Date())
                dragStart = start
                // The line sits at a frame's start, so it shows the frame to
                // its right (a point in, past rounding).
                model.scrub(toIndex: FilmstripLayout.index(at: start + value.translation.width + 1,
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
    /// Too narrow for the grip and hold badge (a fully zoomed-out timeline).
    private var isTiny: Bool { model.thumbnailWidth < 16 }

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
            .clipShape(.rect(cornerRadius: min(4, model.thumbnailWidth / 4)))
            .overlay(alignment: .bottomTrailing) {
                if frame.hold > 1, !isTiny {
                    Text("×\(frame.hold)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.black.opacity(0.7), in: .capsule)
                        .foregroundStyle(.white)
                        .padding(3)
                }
            }
            GripHandle(isSelected: isSelected)
                .opacity(isTiny ? 0 : 1)
                .frame(width: model.thumbnailWidth)
        }
        .padding(FilmstripLayout.cellPadding(model.thumbnailWidth))
        .background(isSelected ? Color.accentColor : .clear, in: .rect(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isPlaying ? Color.accentColor : .clear, lineWidth: 2)
        }
        .overlay(alignment: .leading) {
            // Where dropped frames will go.
            if isTargeted { Capsule().fill(Color.accentColor).frame(width: 3).offset(x: -2) }
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

/// The empty space at the end of the frames, under the pinned Capture tile.
private struct EndSpace: View {
    @ObservedObject var model: WindowModel
    @State private var isTargeted = false

    var body: some View {
        Color.clear
            .frame(width: FilmstripLayout.endSpaceWidth, height: FrameCell.height)
            .overlay(alignment: .leading) {
                if isTargeted { Capsule().fill(Color.accentColor).frame(width: 3).offset(x: -2) }
            }
            .contentShape(.rect)
            .dropDestination(for: FrameDrop.self) { items, _ in
                model.handleDrop(items, before: nil)
            } isTargeted: { isTargeted = $0 }
    }
}

/// The tile pinned at the timeline's right edge: goes back to the live
/// camera, or captures a frame when already there. Dropping frames on it
/// moves them to the end.
private struct CaptureTile: View {
    @ObservedObject var model: WindowModel
    @State private var isTargeted = false

    private var isLive: Bool { model.mode == .live }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                Image(systemName: "camera.fill").font(.title2)
                    .foregroundStyle(isLive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            }
            .frame(width: FrameCell.standardWidth, height: FrameCell.thumbnailHeight)
            Text("Capture")
                .font(.caption.weight(isLive ? .semibold : .regular))
                .foregroundStyle(isLive ? .white : .secondary)
                .frame(minHeight: 16)
        }
        .padding(4)
        .background(isLive ? Color.red.opacity(0.85) : .clear, in: .rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isTargeted ? Color.accentColor : .clear, lineWidth: 2)
        }
        .contentShape(.rect)
        .onTapGesture {
            if isLive { model.capture() } else { model.goLive() }
        }
        .dropDestination(for: FrameDrop.self) { items, _ in
            model.handleDrop(items, before: nil)
        } isTargeted: { isTargeted = $0 }
        .help(isLive ? "Capture a frame (tap ⌘)" : "Back to the live camera to capture (⌘L)")
        .accessibilityLabel("Capture")
        .accessibilityAddTraits(.isButton)
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
        Button("Move to Recycle Bin", systemImage: "trash", role: .destructive) { act { model.deleteSelection() } }
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
        // Holding Option when letting go copies instead of moving, as in Finder.
        let copies = NSEvent.modifierFlags.contains(.option)
        for item in items {
            switch item {
            case .frame(let id):
                guard frames.contains(where: { $0.id == id }) else { continue }
                if copies { copy(dragged: id, before: target) } else { move(dragged: id, before: target) }
            case .file(let url):
                files.append(url)
            }
        }
        if !files.isEmpty { addImages(files, before: target) }
        return true
    }
}
