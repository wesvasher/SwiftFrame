import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Testing
@testable import SwiftFrame

@MainActor @Suite(.serialized) struct TimelineZoomTests {
    @Test func stepsThroughThumbnailSizes() {
        let saved = UserDefaults.standard.object(forKey: "FilmstripThumbnailWidth")
        defer { UserDefaults.standard.set(saved, forKey: "FilmstripThumbnailWidth") }
        UserDefaults.standard.removeObject(forKey: "FilmstripThumbnailWidth")

        let model = WindowModel(document: StopMotionDocument())
        // New projects start at 4:3 for the 63-point-high thumbnails.
        #expect(model.thumbnailWidth == 84)
        model.zoomInTimeline()
        #expect(model.thumbnailWidth == 112)
        for _ in 0..<10 { model.zoomInTimeline() }
        #expect(model.thumbnailWidth == 240 && !model.canZoomInTimeline)
        for _ in 0..<10 { model.zoomOutTimeline() }
        #expect(model.thumbnailWidth == 24 && !model.canZoomOutTimeline)

        // Opened projects start at the last size chosen; new ones at 4:3.
        #expect(WindowModel(document: StopMotionDocument(), isNew: false).thumbnailWidth == 24)
        #expect(WindowModel(document: StopMotionDocument()).thumbnailWidth == 84)
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
        FilmstripLayout.cellX(count, thumbnailWidth: width) + FilmstripLayout.endSpaceWidth
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

@MainActor @Suite struct ViewerZoomTests {
    @Test func stepsAndKeepsThePictureInView() {
        let model = WindowModel(document: StopMotionDocument())
        model.viewerSize = CGSize(width: 800, height: 600)
        #expect(model.viewerZoom == 1 && !model.canZoomOutViewer)
        model.zoomInViewer()
        #expect(model.viewerZoom == 1.5)
        model.zoomInViewer()
        #expect(model.viewerZoom == 2)

        // At 2×, the picture can move half the view each way, no further.
        model.panViewer(to: CGSize(width: 1000, height: -1000))
        #expect(model.viewerPan == CGSize(width: 400, height: -300))
        // Zooming out pulls it back in; fitting centers it.
        model.zoomOutViewer()
        #expect(model.viewerZoom == 1.5 && model.viewerPan == CGSize(width: 200, height: -150))
        model.zoomViewerToFit()
        #expect(model.viewerZoom == 1 && model.viewerPan == .zero)

        model.setViewerZoom(20)
        #expect(model.viewerZoom == 8 && !model.canZoomInViewer)
    }
}

@Suite struct FocusPeakingTests {
    @Test func outlinesSharpEdgesOnly() throws {
        // A sharp-edged square on the left, a blurred one on the right.
        let size = CGSize(width: 400, height: 200)
        let square = CIImage(color: .white).cropped(to: CGRect(x: 40, y: 50, width: 100, height: 100))
        let soft = CIImage(color: .white).cropped(to: CGRect(x: 260, y: 50, width: 100, height: 100))
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 8])
        let picture = square.composited(over: soft)
            .composited(over: CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1)))
            .cropped(to: CGRect(origin: .zero, size: size))
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let context = CIContext()
        let pixels = try #require(buffer)
        context.render(picture, to: pixels)

        let peaking = FocusPeaking(isOn: true, tint: .red, sensitivity: FocusPeaking.Preset.medium.rawValue)
        let overlay = try #require(peaking.overlay(for: pixels, context: context))
        let data = try #require(overlay.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        var left = 0, right = 0
        for y in 0..<overlay.height {
            for x in 0..<overlay.width where bytes[y * overlay.bytesPerRow + x * 4 + 3] > 128 {
                if x < overlay.width / 2 { left += 1 } else { right += 1 }
            }
        }
        #expect(left > 200)
        #expect(right < left / 10)
    }
}

@Suite struct PeakingSensitivityTests {
    @Test func staysInRangeAndMatchesPresets() {
        var peaking = FocusPeaking()
        #expect(peaking.preset == .medium)
        peaking.sensitivity += 1
        #expect(peaking.sensitivity == 6 && peaking.preset == nil)
        #expect(peaking.threshold < FocusPeaking(sensitivity: 5).threshold)
        peaking.sensitivity = 40
        #expect(peaking.sensitivity == 10)
        peaking.sensitivity = -3
        #expect(peaking.sensitivity == 1)
    }
}

@MainActor @Suite struct OnionSkinToggleTests {
    @Test func switchesToThePlainCameraAndGoesLive() {
        let model = WindowModel(document: StopMotionDocument())
        #expect(model.showsOnionSkin)
        model.mode = .review
        model.setShowsOnionSkin(false)
        #expect(!model.showsOnionSkin && model.mode == .live)
        // The project's onion skin settings are left alone.
        #expect(model.project.onionSkinFrames == Project().onionSkinFrames)
    }
}

@MainActor @Suite struct FullScreenPlaybackTests {
    @Test func playsFromTheStartAndPausesOnTheWayOut() {
        let document = StopMotionDocument()
        document.project.frames = [Frame(image: UUID()), Frame(image: UUID()), Frame(image: UUID())]
        let model = WindowModel(document: document)
        model.click(document.project.frames[1].id, modifiers: [])

        model.playFullScreen()
        #expect(model.isPlayingFullScreen && model.mode == .playback)
        #expect(model.playbackPosition(at: Date())?.index == 0)

        model.toggleFullScreenPlayback()
        #expect(!model.isPlayingFullScreen && model.mode != .playback)
    }

    @Test func needsFrames() {
        let model = WindowModel(document: StopMotionDocument())
        model.playFullScreen()
        #expect(!model.isPlayingFullScreen)
    }
}
