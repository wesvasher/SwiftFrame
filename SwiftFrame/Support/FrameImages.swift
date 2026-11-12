import AppKit
import ImageIO
import UniformTypeIdentifiers

/// JPEG encoding and decoding for frame pictures.
enum ImageCoding {
    static func jpeg(_ image: CGImage, quality: Double = 0.92) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Decodes a picture, scaled down to `maxPixelSize` on its long side if given.
    static func decode(_ data: Data, maxPixelSize: Int? = nil) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        if let maxPixelSize {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    /// Reads any image file as JPEG data for a new frame.
    static func importFile(_ url: URL) -> Data? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .jpeg) == true,
           decode(data, maxPixelSize: 16) != nil {
            return data
        }
        return decode(data).flatMap { jpeg($0) }
    }
}

/// Decoded pictures for one window, so playback and the filmstrip don't
/// decode the same JPEG over and over.
@MainActor
final class FrameImages {
    private let full = NSCache<NSUUID, CGImage>()
    private let thumbnails = NSCache<NSUUID, CGImage>()

    init() {
        full.totalCostLimit = 1_500_000_000
        thumbnails.countLimit = 2000
    }

    func image(_ id: UUID, data: Data?) -> CGImage? {
        if let cached = full.object(forKey: id as NSUUID) { return cached }
        guard let data, let image = ImageCoding.decode(data, maxPixelSize: 2560) else { return nil }
        store(image, for: id)
        return image
    }

    func thumbnail(_ id: UUID, data: Data?) -> CGImage? {
        if let cached = thumbnails.object(forKey: id as NSUUID) { return cached }
        guard let data, let image = ImageCoding.decode(data, maxPixelSize: 480) else { return nil }
        thumbnails.setObject(image, forKey: id as NSUUID)
        return image
    }

    func store(_ image: CGImage, for id: UUID) {
        full.setObject(image, forKey: id as NSUUID, cost: image.bytesPerRow * image.height)
    }
}
