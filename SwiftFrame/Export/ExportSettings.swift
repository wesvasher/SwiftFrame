import Foundation
import UniformTypeIdentifiers

/// What to export the animation as: a movie (H.264, HEVC or a ProRes
/// flavor, in QuickTime or MPEG-4), an animated GIF, or a folder of numbered
/// pictures. The last choice is remembered for the next export.
struct ExportSettings: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case movie, gif, images
        var id: Self { self }
        var name: String {
            switch self {
            case .movie: "Movie"
            case .gif: "Animated GIF"
            case .images: "Image Sequence"
            }
        }
    }

    enum Container: String, Codable, CaseIterable, Identifiable, Sendable {
        case mov, mp4
        var id: Self { self }
        var name: String { self == .mov ? "QuickTime (.mov)" : "MPEG-4 (.mp4)" }
        var type: UTType { self == .mov ? .quickTimeMovie : .mpeg4Movie }
    }

    enum ImageFormat: String, Codable, CaseIterable, Identifiable, Sendable {
        case png, jpeg, tiff
        var id: Self { self }
        var name: String { rawValue.uppercased() }
        var type: UTType {
            switch self {
            case .png: .png
            case .jpeg: .jpeg
            case .tiff: .tiff
            }
        }
        var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    }

    /// The tallest the export may be; smaller pictures are never scaled up.
    enum Size: Int, Codable, CaseIterable, Identifiable, Sendable {
        case original = 0
        case p2160 = 2160, p1080 = 1080, p720 = 720, p480 = 480, p360 = 360
        var id: Self { self }
        var name: String {
            switch self {
            case .original: "Full Size"
            case .p2160: "2160p (4K)"
            default: "\(rawValue)p"
            }
        }
        var maxHeight: Int? { self == .original ? nil : rawValue }
    }

    var kind: Kind = .movie
    var codec: MovieExporter.Codec = .h264
    var container: Container = .mov
    var imageFormat: ImageFormat = .png
    var size: Size = .original
    /// GIFs only: play over and over, or once.
    var loopGIF = true

    /// ProRes only goes in QuickTime movies.
    var effectiveContainer: Container { codec.isProRes ? .mov : container }

    /// What the save panel asks for: a movie, a GIF, or a new folder.
    var contentType: UTType {
        switch kind {
        case .movie: effectiveContainer.type
        case .gif: .gif
        case .images: .folder
        }
    }

    func fileName(for name: String) -> String {
        switch kind {
        case .movie: "\(name).\(effectiveContainer.rawValue)"
        case .gif: "\(name).gif"
        case .images: "\(name) Frames"
        }
    }

    /// The size of the export for pictures `width` × `height`: shrunk to fit
    /// `size`, and even, as video encoders want.
    func outputSize(width: Int, height: Int) -> (width: Int, height: Int) {
        var w = Double(width), h = Double(height)
        if let maxHeight = size.maxHeight, h > Double(maxHeight) {
            w *= Double(maxHeight) / h
            h = Double(maxHeight)
        }
        let even = kind == .movie
        func round(_ v: Double) -> Int {
            // Even sizes round to the nearest even number: 853.3 → 854.
            max(2, even ? Int((v / 2).rounded()) * 2 : Int(v.rounded()))
        }
        return (round(w), round(h))
    }

    private static let key = "exportSettings"

    static var saved: ExportSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(ExportSettings.self, from: data)
        else { return ExportSettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
