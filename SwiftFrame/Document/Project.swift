import Foundation

/// One frame of the animation. Frames point at an image by id, so a
/// duplicated frame shares its picture with the original.
struct Frame: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var image: UUID
    /// How many playback frames this frame stays on screen ("on twos" = 2).
    var hold: Int

    init(id: UUID = UUID(), image: UUID, hold: Int = 1) {
        self.id = id
        self.image = image
        self.hold = hold
    }

    static let holdRange = 1...99
}

/// Everything in a project except the pictures: saved as Project.json.
struct Project: Codable, Equatable, Sendable {
    var version = 1
    var frames: [Frame] = []
    var framesPerSecond = 12
    /// How many earlier frames show over the live camera.
    var onionSkinFrames = 1
    var onionSkinOpacity = 0.4
    var mirrorCamera = false
    var loopPlayback = true
    /// The camera last used, by `AVCaptureDevice.uniqueID`.
    var cameraID: String?
    /// What new captures are cropped to; nil keeps the camera's whole picture.
    var crop: FrameCrop?

    static let frameRates = [6, 8, 10, 12, 15, 24, 25, 30]

    var duration: Double {
        Double(frames.playbackLength) / Double(max(framesPerSecond, 1))
    }
}

// MARK: - Frame list editing (pure logic, covered by FrameListTests)

extension Array where Element == Frame {
    /// The number of playback frames, counting holds.
    var playbackLength: Int { reduce(0) { $0 + $1.hold } }

    /// The index of the frame showing at playback frame `n` (0-based).
    func index(atPlaybackFrame n: Int) -> Int? {
        guard n >= 0 else { return nil }
        var end = 0
        for (i, frame) in enumerated() {
            end += frame.hold
            if n < end { return i }
        }
        return nil
    }

    /// The playback frame where the frame at `index` first shows.
    func playbackStart(ofIndex index: Int) -> Int {
        self[..<Swift.min(index, count)].reduce(0) { $0 + $1.hold }
    }

    func firstIndex(of id: UUID) -> Int? { firstIndex { $0.id == id } }

    /// The frames playback covers between the in and out marks, by index:
    /// a missing mark (or one whose frame is gone) is the first or last
    /// frame. Nil when there are no frames.
    func playRange(in inID: UUID?, out outID: UUID?) -> ClosedRange<Int>? {
        guard !isEmpty else { return nil }
        let a = inID.flatMap { firstIndex(of: $0) } ?? 0
        let b = outID.flatMap { firstIndex(of: $0) } ?? count - 1
        return Swift.min(a, b)...Swift.max(a, b)
    }

    /// Where playback is `t` playback frames after starting at the beginning
    /// of `range`: the frame showing, how far through its hold (0 to 1), and
    /// whether a playback that doesn't loop has reached the end of the range.
    func playbackPosition(at t: Double, in range: ClosedRange<Int>, loops: Bool)
        -> (index: Int, fraction: Double, finished: Bool)? {
        guard range.lowerBound >= 0, range.upperBound < count else { return nil }
        let start = playbackStart(ofIndex: range.lowerBound)
        let length = playbackStart(ofIndex: range.upperBound + 1) - start
        guard length > 0 else { return nil }
        let t = Swift.max(0, t)
        let finished = !loops && t >= Double(length)
        let position = Double(start) + (finished ? Double(length) - 0.001 : t.truncatingRemainder(dividingBy: Double(length)))
        guard let index = index(atPlaybackFrame: Int(position)) else { return nil }
        let fraction = (position - Double(playbackStart(ofIndex: index))) / Double(self[index].hold)
        return (index, Swift.min(Swift.max(fraction, 0), 1), finished)
    }

    /// Removes the frames, returning the frame to select afterwards: the one
    /// after the last removed frame, else the one before.
    @discardableResult
    mutating func remove(ids: Set<UUID>) -> UUID? {
        guard let last = lastIndex(where: { ids.contains($0.id) }) else { return nil }
        let after = self[(last + 1)...].first { !ids.contains($0.id) }
        let before = self[..<last].last { !ids.contains($0.id) }
        removeAll { ids.contains($0.id) }
        return (after ?? before)?.id
    }

    /// Copies the frames, in order, right after the last of them. Returns the
    /// copies' ids.
    @discardableResult
    mutating func duplicate(ids: Set<UUID>) -> [UUID] {
        guard let last = lastIndex(where: { ids.contains($0.id) }) else { return [] }
        let copies = filter { ids.contains($0.id) }.map { Frame(image: $0.image, hold: $0.hold) }
        insert(contentsOf: copies, at: last + 1)
        return copies.map(\.id)
    }

    /// Moves the frames, keeping their order, to just before `target` (or to
    /// the end when `target` is nil). Dropping on a moved frame puts them
    /// before the next frame that isn't moving.
    mutating func move(ids: Set<UUID>, before target: UUID?) {
        let moving = filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return }
        var anchor = target
        if let t = target, ids.contains(t), let i = firstIndex(of: t) {
            anchor = self[i...].first { !ids.contains($0.id) }?.id
        }
        removeAll { ids.contains($0.id) }
        let at = anchor.flatMap { firstIndex(of: $0) } ?? count
        insert(contentsOf: moving, at: at)
    }

    /// Reverses the order of the frames among their own places.
    mutating func reverse(ids: Set<UUID>) {
        let places = indices.filter { ids.contains(self[$0].id) }
        let reversed = places.map { self[$0] }.reversed()
        for (place, frame) in zip(places, reversed) { self[place] = frame }
    }

    /// Changes each frame's hold by `delta`, within `Frame.holdRange`.
    mutating func changeHold(ids: Set<UUID>, by delta: Int) {
        for i in indices where ids.contains(self[i].id) {
            self[i].hold = (self[i].hold + delta).clamped(to: Frame.holdRange)
        }
    }

    /// Ids from `a` to `b` inclusive, in either order.
    func ids(from a: UUID, to b: UUID) -> [UUID] {
        guard let i = firstIndex(of: a), let j = firstIndex(of: b) else { return [b] }
        return self[Swift.min(i, j)...Swift.max(i, j)].map(\.id)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
