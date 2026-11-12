import CoreGraphics
import Foundation
import Testing
@testable import SwiftFrame

@MainActor @Suite(.serialized) struct TimelineZoomTests {
    @Test func stepsThroughThumbnailSizes() {
        let saved = UserDefaults.standard.object(forKey: "FilmstripThumbnailWidth")
        defer { UserDefaults.standard.set(saved, forKey: "FilmstripThumbnailWidth") }
        UserDefaults.standard.removeObject(forKey: "FilmstripThumbnailWidth")

        let model = WindowModel(document: StopMotionDocument())
        #expect(model.thumbnailWidth == 112)
        model.zoomInTimeline()
        #expect(model.thumbnailWidth == 168)
        for _ in 0..<10 { model.zoomInTimeline() }
        #expect(model.thumbnailWidth == 240 && !model.canZoomInTimeline)
        for _ in 0..<10 { model.zoomOutTimeline() }
        #expect(model.thumbnailWidth == 24 && !model.canZoomOutTimeline)

        // New windows start at the last size chosen.
        #expect(WindowModel(document: StopMotionDocument()).thumbnailWidth == 24)
    }
}

@MainActor @Suite struct PlaybackTests {
    func model(frames: Int) -> WindowModel {
        var project = Project()
        project.framesPerSecond = 10
        project.frames = (0..<frames).map { _ in Frame(image: UUID()) }
        return WindowModel(document: StopMotionDocument(project: project, images: [:]))
    }

    @Test func playResumesFromThePausedFrame() {
        let model = model(frames: 5)
        model.select(model.frames[2].id)
        model.togglePlayback()
        #expect(model.mode == .playback)
        // Frame 3 starts 0.2 s in at 10 fps.
        #expect(abs(Date().timeIntervalSince(model.playbackStart) - 0.2) < 0.05)
    }

    @Test func playFromLiveOrTheLastFrameStartsOver() {
        let model = model(frames: 5)
        model.togglePlayback()
        #expect(abs(Date().timeIntervalSince(model.playbackStart)) < 0.05)
        model.stopPlayback()
        model.select(model.frames[4].id)
        model.togglePlayback()
        #expect(abs(Date().timeIntervalSince(model.playbackStart)) < 0.05)
    }
}

@MainActor @Suite struct PlayheadTests {
    @Test func playbackPositionCountsHolds() {
        var project = Project()
        project.framesPerSecond = 10
        project.loopPlayback = false
        project.frames = [Frame(image: UUID()), Frame(image: UUID(), hold: 4)]
        let model = WindowModel(document: StopMotionDocument(project: project, images: [:]))
        let start = model.playbackStart

        let first = model.playbackPosition(at: start.addingTimeInterval(0.05))
        #expect(first?.index == 0 && abs((first?.fraction ?? 0) - 0.5) < 0.01)
        // 0.3 s in: two playback frames into the second frame's hold of four.
        let held = model.playbackPosition(at: start.addingTimeInterval(0.3))
        #expect(held?.index == 1 && abs((held?.fraction ?? 0) - 0.5) < 0.01)
        let end = model.playbackPosition(at: start.addingTimeInterval(2))
        #expect(end?.index == 1 && end?.finished == true)
    }

    @Test func scrubSelectsFramesAndGoesLivePastTheEnd() {
        var project = Project()
        project.frames = (0..<3).map { _ in Frame(image: UUID()) }
        let model = WindowModel(document: StopMotionDocument(project: project, images: [:]))
        model.scrub(toIndex: 1)
        #expect(model.mode == .review && model.current == model.frames[1].id)
        model.scrub(toIndex: 3)
        #expect(model.mode == .live && model.current == nil)
    }

    @Test func layoutFindsTheCellUnderAPoint() {
        let width: CGFloat = 112   // stride 117, first cell at 10
        #expect(FilmstripLayout.index(at: 0, thumbnailWidth: width) == 0)
        #expect(FilmstripLayout.index(at: 120, thumbnailWidth: width) == 0)
        #expect(FilmstripLayout.index(at: 130, thumbnailWidth: width) == 1)
        #expect(FilmstripLayout.cellX(2, thumbnailWidth: width) == 244)
    }
}

@MainActor @Suite struct FrameMenuTests {
    @Test func moveSelectionToStartAndEnd() {
        var project = Project()
        project.frames = (0..<4).map { _ in Frame(image: UUID()) }
        let model = WindowModel(document: StopMotionDocument(project: project, images: [:]))
        let ids = model.frames.map(\.id)
        model.select(ids[2])
        model.moveSelection(toStart: true)
        #expect(model.frames.map(\.id) == [ids[2], ids[0], ids[1], ids[3]])
        model.moveSelection(toStart: false)
        #expect(model.frames.map(\.id) == [ids[0], ids[1], ids[3], ids[2]])
    }
}

@Suite struct FitZoomTests {
    func totalWidth(_ count: Int, _ width: CGFloat) -> CGFloat {
        FilmstripLayout.cellX(count, thumbnailWidth: width) + FilmstripLayout.liveCellWidth + FilmstripLayout.inset
    }

    @Test(arguments: [1, 5, 40, 120, 400])
    func everyFrameFits(count: Int) {
        let visible: CGFloat = 900
        let width = FilmstripLayout.fitWidth(count: count, visibleWidth: visible, maxWidth: 240)
        #expect(width <= 240 && width >= 0.5)
        #expect(totalWidth(count, width) <= visible + 0.5)
    }

    @Test func fewFramesStopAtTheWidestStep() {
        #expect(FilmstripLayout.fitWidth(count: 1, visibleWidth: 900, maxWidth: 240) == 240)
    }
}
