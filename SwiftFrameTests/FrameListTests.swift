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

@Suite struct ShiftFramesTests {
    let frames = (0..<6).map { _ in Frame(image: UUID()) }

    @Test func movesOneFrameAlong() {
        var list = frames
        #expect(list.shift(ids: [frames[1].id], by: 1) == 1)
        #expect(list.map(\.id) == [0, 2, 1, 3, 4, 5].map { frames[$0].id })
    }

    @Test func keepsGapsAndStopsAtTheEnds() {
        var list = frames
        // 1 and 3 moving 10 right stop when 3 reaches the end.
        #expect(list.shift(ids: [frames[1].id, frames[3].id], by: 10) == 2)
        #expect(list.map(\.id) == [0, 2, 4, 1, 5, 3].map { frames[$0].id })
        #expect(list.shift(ids: [frames[0].id], by: -1) == 0)
    }
}

@Suite struct RecycleBinTests {
    func project(_ n: Int) -> Project {
        var project = Project()
        project.frames = (0..<n).map { _ in Frame(image: UUID()) }
        return project
    }

    @Test func deletedFramesGoToTheBinAndComeBackInPlace() {
        var project = project(5)
        let ids = project.frames.map(\.id)
        let next = project.moveToBin(ids: [ids[1], ids[3]])
        #expect(next == ids[4])
        #expect(project.frames.map(\.id) == [ids[0], ids[2], ids[4]])
        #expect(project.recycleBin.map(\.index) == [1, 3])
        project.restoreFromBin(ids: [ids[1], ids[3]])
        #expect(project.frames.map(\.id) == ids && project.recycleBin.isEmpty)
    }

    @Test func binPicturesAreSaved() throws {
        var project = project(2)
        let gone = project.frames[0]
        project.moveToBin(ids: [gone.id])
        let images = Dictionary(uniqueKeysWithValues: [gone.image, project.frames[0].image].map { ($0, Data([1])) })
        let wrapper = try StopMotionDocument.fileWrapper(for: .init(project: project, images: images), existing: nil)
        let (read, readImages) = try StopMotionDocument.read(wrapper)
        #expect(read.recycleBin.map(\.id) == [gone.id])
        #expect(readImages[gone.image] != nil)
    }

    @Test func oldProjectsWithoutABinStillOpen() throws {
        let json = #"{"version":1,"frames":[],"framesPerSecond":12,"onionSkinFrames":1,"onionSkinOpacity":0.4,"mirrorCamera":false,"loopPlayback":true}"#
        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        #expect(project.recycleBin.isEmpty)
    }
}

@Suite struct CopyFramesTests {
    @Test func copiesGoBeforeTheTarget() {
        let frames = (0..<4).map { _ in Frame(image: UUID()) }
        var list = frames
        let copies = list.copy(ids: [frames[0].id, frames[2].id], before: frames[1].id)
        #expect(list.count == 6)
        #expect(list.map(\.image) == [0, 0, 2, 1, 2, 3].map { frames[$0].image })
        #expect(copies == [list[1].id, list[2].id])
        list.copy(ids: [frames[3].id], before: nil)
        #expect(list.last?.image == frames[3].image)
    }
}
