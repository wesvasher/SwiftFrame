import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Exports the frames as an animated GIF or as a folder of numbered pictures.
enum ImageExporter {
    /// An animated GIF, each frame shown for its hold. GIF timings are in
    /// hundredths of a second, so each frame's is rounded where it ends,
    /// keeping the whole animation on time.
    static func exportGIF(_ items: [MovieExporter.Item], framesPerSecond fps: Int, settings: ExportSettings,
                          to url: URL, progress: @Sendable @escaping (Double) -> Void) async throws {
        guard !items.isEmpty else { throw MovieExporter.ExportError.noFrames }
        try? FileManager.default.removeItem(at: url)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString,
                                                                items.count, nil)
        else { throw MovieExporter.ExportError.writer("The GIF couldn't be created.") }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: settings.loopGIF ? 0 : 1],
        ] as CFDictionary)

        let fps = Double(max(fps, 1))
        var size: (width: Int, height: Int)?
        var ticks = 0
        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            guard let picture = ImageCoding.decode(item.data) else { throw MovieExporter.ExportError.unreadableFrame }
            let frameSize = size ?? settings.outputSize(width: picture.width, height: picture.height)
            size = frameSize
            guard let image = fitted(picture, width: frameSize.width, height: frameSize.height)
            else { throw MovieExporter.ExportError.writer("Out of memory for the GIF's frames.") }
            let start = (Double(ticks) / fps * 100).rounded()
            ticks += item.hold
            let delay = ((Double(ticks) / fps * 100).rounded() - start) / 100
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay,
                ],
            ] as CFDictionary)
            progress(Double(index + 1) / Double(items.count))
        }
        guard CGImageDestinationFinalize(destination) else {
            throw MovieExporter.ExportError.writer("The GIF couldn't be finished.")
        }
    }

    /// A new folder of pictures numbered from 0001, one per frame of
    /// playback, so a frame held for 3 is written 3 times and the folder
    /// plays at the project's frame rate in any editor.
    static func exportImages(_ items: [MovieExporter.Item], settings: ExportSettings, to folder: URL,
                             progress: @Sendable @escaping (Double) -> Void) async throws {
        guard !items.isEmpty else { throw MovieExporter.ExportError.noFrames }
        let manager = FileManager.default
        try? manager.removeItem(at: folder)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)

        let total = items.reduce(0) { $0 + $1.hold }
        let digits = max(4, String(total).count)
        let format = settings.imageFormat
        var size: (width: Int, height: Int)?
        var number = 0
        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            guard let picture = ImageCoding.decode(item.data) else { throw MovieExporter.ExportError.unreadableFrame }
            let frameSize = size ?? settings.outputSize(width: picture.width, height: picture.height)
            size = frameSize
            guard let image = fitted(picture, width: frameSize.width, height: frameSize.height),
                  let data = encode(image, as: format)
            else { throw MovieExporter.ExportError.writer("A picture couldn't be written.") }
            for _ in 0..<item.hold {
                number += 1
                let name = "frame_" + String(repeating: "0", count: max(0, digits - String(number).count))
                    + String(number) + "." + format.fileExtension
                try data.write(to: folder.appending(path: name))
            }
            progress(Double(index + 1) / Double(items.count))
        }
    }

    static func encode(_ image: CGImage, as format: ExportSettings.ImageFormat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.type.identifier as CFString, 1, nil)
        else { return nil }
        let options: [CFString: Any] = format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.92] : [:]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// The picture at the export's size, fitted on black.
    static func fitted(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        if image.width == width, image.height == height { return image }
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        MovieExporter.drawFitted(image, in: context, width: width, height: height)
        return context.makeImage()
    }
}
