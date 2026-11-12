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
        #expect(model.thumbnailWidth == 160)
        for _ in 0..<10 { model.zoomInTimeline() }
        #expect(model.thumbnailWidth == 240 && !model.canZoomInTimeline)
        for _ in 0..<10 { model.zoomOutTimeline() }
        #expect(model.thumbnailWidth == 48 && !model.canZoomOutTimeline)

        // New windows start at the last size chosen.
        #expect(WindowModel(document: StopMotionDocument()).thumbnailWidth == 48)
    }
}
