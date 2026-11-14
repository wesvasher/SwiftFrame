import Foundation
import Testing
@testable import SwiftFrame

@Suite struct FrameListTests {
    /// Five frames, a…e, each with its own picture.
    let frames = (0..<5).map { _ in Frame(image: UUID()) }
    var ids: [UUID] { frames.map(\.id) }

    @Test func playbackCountsHolds() {
        var list = frames
        list[1].hold = 3
        #expect(list.playbackLength == 7)
        #expect(list.index(atPlaybackFrame: 0) == 0)
        #expect(list.index(atPlaybackFrame: 1) == 1)
        #expect(list.index(atPlaybackFrame: 3) == 1)
        #expect(list.index(atPlaybackFrame: 4) == 2)
        #expect(list.index(atPlaybackFrame: 7) == nil)
        #expect(list.playbackStart(ofIndex: 2) == 4)
    }

    @Test func removeSelectsTheNextFrame() {
        var list = frames
        let next = list.remove(ids: [ids[1], ids[2]])
        #expect(list.map(\.id) == [ids[0], ids[3], ids[4]])
        #expect(next == ids[3])

        var end = frames
        #expect(end.remove(ids: [ids[4]]) == ids[3])
        var all = frames
        #expect(all.remove(ids: Set(ids)) == nil)
        #expect(all.isEmpty)
    }

    @Test func duplicateGoesAfterTheLastSelected() {
        var list = frames
        let copies = list.duplicate(ids: [ids[0], ids[2]])
        #expect(copies.count == 2)
        #expect(list.count == 7)
        #expect(list[3].id == copies[0] && list[3].image == frames[0].image)
        #expect(list[4].id == copies[1] && list[4].image == frames[2].image)
        #expect(list[5].id == ids[3])
    }

    @Test func moveKeepsOrder() {
        var list = frames
        list.move(ids: [ids[3], ids[1]], before: ids[0])
        #expect(list.map(\.id) == [ids[1], ids[3], ids[0], ids[2], ids[4]])

        var toEnd = frames
        toEnd.move(ids: [ids[0]], before: nil)
        #expect(toEnd.map(\.id) == [ids[1], ids[2], ids[3], ids[4], ids[0]])

        // Dropping on a frame that's moving puts them before the next one that isn't.
        var onSelf = frames
        onSelf.move(ids: [ids[1], ids[2]], before: ids[1])
        #expect(onSelf.map(\.id) == ids)
    }

    @Test func reverseOnlyTouchesSelectedPlaces() {
        var list = frames
        list.reverse(ids: [ids[0], ids[2], ids[4]])
        #expect(list.map(\.id) == [ids[4], ids[1], ids[2], ids[3], ids[0]])
    }

    @Test func holdStaysInRange() {
        var list = frames
        list.changeHold(ids: [ids[0]], by: -5)
        #expect(list[0].hold == 1)
        list.changeHold(ids: [ids[0]], by: 200)
        #expect(list[0].hold == 99)
    }

    @Test func rangeSelectionEitherWay() {
        #expect(frames.ids(from: ids[3], to: ids[1]) == [ids[1], ids[2], ids[3]])
        #expect(frames.ids(from: ids[1], to: ids[1]) == [ids[1]])
    }
}

@Suite struct DocumentTests {
    @Test func packageRoundTrip() throws {
        let a = UUID(), b = UUID(), unused = UUID()
        var project = Project()
        project.frames = [Frame(image: a, hold: 2), Frame(image: b), Frame(image: a)]
        project.framesPerSecond = 24
        let images = [a: Data([1, 2, 3]), b: Data([4, 5]), unused: Data([9])]

        let wrapper = try StopMotionDocument.fileWrapper(
            for: .init(project: project, images: images), existing: nil)
        let frameFiles = wrapper.fileWrappers?[StopMotionDocument.framesFolder]?.fileWrappers ?? [:]
        #expect(frameFiles.count == 2, "only pictures that frames use are saved")

        let (read, readImages) = try StopMotionDocument.read(wrapper)
        #expect(read == project)
        #expect(readImages == [a: Data([1, 2, 3]), b: Data([4, 5])])
    }
}

@Suite struct RepeatedSaveTests {
    /// Each save reuses the last save's picture files, as autosaving does;
    /// renaming a reused file that's already in a folder crashed.
    @Test func savesOverAndOverReusingPictures() throws {
        let image = UUID()
        var project = Project()
        project.frames = [Frame(image: image), Frame(image: image)]
        let snapshot = StopMotionDocument.Snapshot(project: project, images: [image: Data([0xFF, 0xD8, 0xFF, 0xD9])])

        // Saved once, then read back from disk like an open document.
        let url = FileManager.default.temporaryDirectory.appending(path: "SwiftFrameTest-\(UUID()).swiftframe")
        defer { try? FileManager.default.removeItem(at: url) }
        try StopMotionDocument.fileWrapper(for: snapshot, existing: nil).write(to: url, originalContentsURL: nil)
        var existing: FileWrapper? = try FileWrapper(url: url)
        var kept: [FileWrapper] = []
        for _ in 0..<5 {
            let wrapper = try StopMotionDocument.fileWrapper(for: snapshot, existing: existing)
            kept.append(wrapper)
            try wrapper.write(to: url, options: .atomic, originalContentsURL: url)
            existing = wrapper
        }
        let (read, images) = try StopMotionDocument.read(try #require(existing))
        #expect(read.frames.count == 2 && images[image] != nil)
    }
}
