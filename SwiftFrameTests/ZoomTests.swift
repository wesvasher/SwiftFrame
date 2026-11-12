import CoreGraphics
import Testing
@testable import SwiftFrame

@MainActor @Suite struct ZoomTests {
    @Test func stepsThroughLevels() {
        let model = WindowModel(document: StopMotionDocument())
        #expect(!model.canZoomOut)
        model.zoomIn()
        #expect(model.zoom == 1.5)
        for _ in 0..<10 { model.zoomIn() }
        #expect(model.zoom == 8 && !model.canZoomIn)
        model.zoomOut()
        #expect(model.zoom == 6)
        model.actualSize()
        #expect(model.zoom == 1)
    }

    @Test func panStaysInsideThePicture() {
        let model = WindowModel(document: StopMotionDocument())
        model.viewerSize = CGSize(width: 400, height: 200)
        model.setPan(CGSize(width: 50, height: 50))
        #expect(model.pan == .zero, "no panning at actual size")
        model.zoomIn(); model.zoomIn()   // 2×
        model.setPan(CGSize(width: 500, height: -30))
        #expect(model.pan == CGSize(width: 200, height: -30))
        model.zoomOut(); model.zoomOut()
        #expect(model.pan == .zero, "back to actual size recenters")
    }
}
