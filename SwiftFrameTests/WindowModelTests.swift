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
