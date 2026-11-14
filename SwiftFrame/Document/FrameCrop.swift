import CoreGraphics

/// A crop for captured frames, by its size at 1080 lines: the camera's
/// picture is cut down to this shape from the middle, never squeezed. A
/// bigger or smaller signal is cropped to the same shape, as big as fits, so
/// 1620 × 1080 is exactly 1620 × 1080 of a 1920 × 1080 HDMI signal and
/// 3240 × 2160 of a 4K one.
struct FrameCrop: Codable, Hashable, Sendable {
    var width: Int
    var height: Int

    struct Preset: Identifiable, Sendable {
        let name: String
        let crop: FrameCrop
        var id: FrameCrop { crop }
    }

    static let presets: [Preset] = [
        Preset(name: "a6600 1620×1080 (3:2)", crop: FrameCrop(width: 1620, height: 1080)),
        Preset(name: "4:3 1440×1080", crop: FrameCrop(width: 1440, height: 1080)),
        Preset(name: "Square 1080×1080", crop: FrameCrop(width: 1080, height: 1080)),
        Preset(name: "4:5 864×1080", crop: FrameCrop(width: 864, height: 1080)),
        Preset(name: "Vertical 9:16 608×1080", crop: FrameCrop(width: 608, height: 1080)),
        Preset(name: "2:1 1920×960", crop: FrameCrop(width: 1920, height: 960)),
        Preset(name: "1.85:1 1920×1038", crop: FrameCrop(width: 1920, height: 1038)),
        Preset(name: "Scope 2.39:1 1920×804", crop: FrameCrop(width: 1920, height: 804)),
    ]

    var name: String {
        Self.presets.first { $0.crop == self }?.name ?? "\(width)×\(height)"
    }

    /// The crop of a `sourceWidth` × `sourceHeight` picture, in its pixels
    /// from the top left: the biggest rectangle of this shape that fits, in
    /// the middle, in whole pixels.
    func rect(sourceWidth: Int, sourceHeight: Int) -> CGRect {
        guard width > 0, height > 0, sourceWidth > 0, sourceHeight > 0 else {
            return CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight)
        }
        let scale = min(Double(sourceWidth) / Double(width), Double(sourceHeight) / Double(height))
        let w = min(sourceWidth, Int((Double(width) * scale).rounded()))
        let h = min(sourceHeight, Int((Double(height) * scale).rounded()))
        return CGRect(x: (sourceWidth - w) / 2, y: (sourceHeight - h) / 2, width: w, height: h)
    }

    /// The crop as fractions of the picture (0 to 1), for drawing.
    func unitRect(sourceWidth: Int, sourceHeight: Int) -> CGRect {
        let r = rect(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
        return CGRect(x: r.minX / CGFloat(sourceWidth), y: r.minY / CGFloat(sourceHeight),
                      width: r.width / CGFloat(sourceWidth), height: r.height / CGFloat(sourceHeight))
    }

    /// The crop in Core Image's coordinates, which start at the bottom left.
    func ciRect(sourceWidth: Int, sourceHeight: Int) -> CGRect {
        let r = rect(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
        return CGRect(x: r.minX, y: CGFloat(sourceHeight) - r.maxY, width: r.width, height: r.height)
    }
}
