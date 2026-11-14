import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SwiftFrame

@Suite struct MovieExporterTests {
    /// A solid-color JPEG.
    func picture(_ gray: Double, width: Int = 320, height: Int = 180) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        return try #require(ImageCoding.jpeg(image))
    }

    @Test func exportsHoldsAtTheFrameRate() async throws {
        let items = [
            MovieExporter.Item(data: try picture(0.1), hold: 1),
            MovieExporter.Item(data: try picture(0.5), hold: 3),
            // A different size is fitted inside the first frame's.
            MovieExporter.Item(data: try picture(0.9, width: 200, height: 200), hold: 2),
        ]
        let url = FileManager.default.temporaryDirectory.appending(path: "SwiftFrameTest-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: url) }

        try await MovieExporter.export(items, framesPerSecond: 12, codec: .h264, to: url) { _ in }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        #expect(abs(duration.seconds - 0.5) < 0.01, "6 playback frames at 12 fps")
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(size == CGSize(width: 320, height: 180))
    }

    func items() throws -> [MovieExporter.Item] {
        [
            MovieExporter.Item(data: try picture(0.1), hold: 1),
            MovieExporter.Item(data: try picture(0.5), hold: 3),
            MovieExporter.Item(data: try picture(0.9), hold: 2),
        ]
    }

    func temporary(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "SwiftFrameTest-\(UUID())-\(name)")
    }

    @Test(arguments: [MovieExporter.Codec.proRes422HQ, .proRes4444, .proRes422Proxy])
    func exportsProRes(_ codec: MovieExporter.Codec) async throws {
        let url = temporary("prores.mov")
        defer { try? FileManager.default.removeItem(at: url) }
        var settings = ExportSettings()
        settings.codec = codec
        settings.container = .mp4   // ProRes always goes in QuickTime.
        #expect(settings.effectiveContainer == .mov)
        try await MovieExporter.export(try items(), framesPerSecond: 12, settings: settings, to: url) { _ in }

        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        let fourCC = codec.type.rawValue.utf8.reduce(FourCharCode(0)) { $0 << 8 | FourCharCode($1) }
        #expect(CMFormatDescriptionGetMediaSubType(format) == fourCC)
    }

    @Test func exportsSmallerMPEG4() async throws {
        let url = temporary("small.mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        var settings = ExportSettings()
        settings.codec = .hevc
        settings.container = .mp4
        settings.size = .p360   // Taller than the pictures: left alone.
        try await MovieExporter.export(try items(), framesPerSecond: 24, settings: settings, to: url) { _ in }
        let asset = AVURLAsset(url: url)
        #expect(abs(try await asset.load(.duration).seconds - 0.25) < 0.01)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 320, height: 180))
    }

    @Test func shrinksToTheChosenSize() {
        var settings = ExportSettings()
        settings.size = .p1080
        #expect(settings.outputSize(width: 3840, height: 2160) == (1920, 1080))
        #expect(settings.outputSize(width: 1280, height: 720) == (1280, 720))
        settings.size = .p480
        #expect(settings.outputSize(width: 1920, height: 1080) == (854, 480))
        settings.kind = .gif   // Odd sizes are fine outside movies.
        #expect(settings.outputSize(width: 1921, height: 1081).width == 853)
    }

    @Test func exportsAGIFOnTime() async throws {
        let url = temporary("anim.gif")
        defer { try? FileManager.default.removeItem(at: url) }
        var settings = ExportSettings()
        settings.kind = .gif
        try await MovieExporter.export(try items(), framesPerSecond: 12, settings: settings, to: url) { _ in }

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 3)
        var total = 0.0
        for index in 0..<3 {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            total += gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0
        }
        #expect(abs(total - 0.5) < 0.001, "6 frames at 12 fps")
    }

    @Test func exportsAnImageSequenceWithHolds() async throws {
        let folder = temporary("Frames")
        defer { try? FileManager.default.removeItem(at: folder) }
        var settings = ExportSettings()
        settings.kind = .images
        settings.imageFormat = .jpeg
        try await MovieExporter.export(try items(), framesPerSecond: 12, settings: settings, to: folder) { _ in }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path()).sorted()
        #expect(names == (1...6).map { String(format: "frame_%04d.jpg", $0) })
    }
}
