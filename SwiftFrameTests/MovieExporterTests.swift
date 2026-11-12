import AVFoundation
import CoreGraphics
import Foundation
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
}
