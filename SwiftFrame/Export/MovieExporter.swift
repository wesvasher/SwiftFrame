import AVFoundation
import CoreGraphics

/// Writes the frames to a QuickTime movie, each shown for its hold.
enum MovieExporter {
    enum Codec: String, CaseIterable, Identifiable, Sendable {
        case h264 = "H.264"
        case hevc = "HEVC"
        case proRes = "ProRes 422"
        var id: String { rawValue }
        var type: AVVideoCodecType {
            switch self {
            case .h264: .h264
            case .hevc: .hevc
            case .proRes: .proRes422
            }
        }
    }

    struct Item: Sendable {
        let data: Data
        let hold: Int
    }

    enum ExportError: LocalizedError {
        case noFrames, unreadableFrame, writer(String)
        var errorDescription: String? {
            switch self {
            case .noFrames: "There are no frames to export."
            case .unreadableFrame: "A frame's picture couldn't be read."
            case .writer(let message): message
            }
        }
    }

    // Uses AVAssetWriterInputPixelBufferAdaptor, deprecated in macOS 27 for
    // AVAssetWriter.inputPixelBufferReceiver(for:pixelBufferAttributes:).
    static func export(_ items: [Item], framesPerSecond fps: Int, codec: Codec, to url: URL,
                       progress: @Sendable @escaping (Double) -> Void) async throws {
        guard let first = items.first else { throw ExportError.noFrames }
        guard let firstImage = ImageCoding.decode(first.data) else { throw ExportError.unreadableFrame }
        // Encoders want even sizes.
        let width = firstImage.width & ~1, height = firstImage.height & ~1

        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec.type,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw ExportError.writer("The movie couldn't be set up.") }
        writer.add(input)
        try writer.start()
        writer.startSession(atSourceTime: .zero)

        let timescale = CMTimeScale(max(fps, 1))
        var time: Int64 = 0
        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            guard let image = index == 0 ? firstImage : ImageCoding.decode(item.data) else {
                throw ExportError.unreadableFrame
            }
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard let pool = adaptor.pixelBufferPool, let buffer = makeBuffer(pool: pool, drawing: image,
                                                                               width: width, height: height)
            else { throw ExportError.writer("Out of memory for the movie's frames.") }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: time, timescale: timescale)) else {
                throw ExportError.writer(writer.error?.localizedDescription ?? "A frame couldn't be written.")
            }
            time += Int64(item.hold)
            progress(Double(index + 1) / Double(items.count))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: time, timescale: timescale))
        await writer.finishWriting()
        if writer.status != .completed {
            throw ExportError.writer(writer.error?.localizedDescription ?? "The movie couldn't be finished.")
        }
    }

    private static func makeBuffer(pool: CVPixelBufferPool, drawing image: CGImage,
                                   width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.setFillColor(.black)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Fit pictures of other sizes inside the first one's.
        let scale = min(Double(width) / Double(image.width), Double(height) / Double(image.height))
        let w = Double(image.width) * scale, h = Double(image.height) * scale
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (Double(width) - w) / 2, y: (Double(height) - h) / 2, width: w, height: h))
        return buffer
    }
}
