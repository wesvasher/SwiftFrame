import CoreImage
import CoreVideo
import SwiftUI

/// Focus peaking: the sharpest edges in the live picture, drawn over it in a
/// bright color, so it's clear what's in focus.
struct FocusPeaking: Equatable, Sendable {
    enum Tint: String, CaseIterable, Identifiable, Sendable {
        case red, yellow, green, blue, white
        var id: Self { self }
        var name: String { rawValue.capitalized }

        var rgb: (red: Double, green: Double, blue: Double) {
            switch self {
            case .red: (1, 0.15, 0.1)
            case .yellow: (1, 0.9, 0)
            case .green: (0.2, 1, 0.2)
            case .blue: (0.1, 0.6, 1)
            case .white: (1, 1, 1)
            }
        }

        var color: Color { Color(red: rgb.red, green: rgb.green, blue: rgb.blue) }
    }

    /// How much counts as in focus, from 1 (only the sharpest edges) to 10
    /// (softer ones too).
    static let sensitivityRange = 1...10

    /// Named sensitivities for the presets menu.
    enum Preset: Int, CaseIterable, Identifiable, Sendable {
        case veryLow = 1, low = 3, medium = 5, high = 7, veryHigh = 9
        var id: Self { self }

        var name: String {
            switch self {
            case .veryLow: "Very Low"
            case .low: "Low"
            case .medium: "Medium"
            case .high: "High"
            case .veryHigh: "Very High"
            }
        }
    }

    var isOn = false
    var tint: Tint = .red
    var sensitivity = Preset.medium.rawValue {
        didSet { sensitivity = min(max(sensitivity, Self.sensitivityRange.lowerBound), Self.sensitivityRange.upperBound) }
    }

    /// The preset this sensitivity matches, if any.
    var preset: Preset? { Preset(rawValue: sensitivity) }

    /// How strong an edge has to be to show: each step up shows a fifth more.
    var threshold: Double { 0.45 * pow(0.8, Double(sensitivity - 1)) }

    private static let onKey = "focusPeaking"
    private static let tintKey = "focusPeakingColor"
    private static let sensitivityKey = "focusPeakingLevel"

    static var saved: FocusPeaking {
        let defaults = UserDefaults.standard
        return FocusPeaking(
            isOn: defaults.bool(forKey: onKey),
            tint: defaults.string(forKey: tintKey).flatMap(Tint.init) ?? .red,
            sensitivity: (defaults.object(forKey: sensitivityKey) as? Int).map {
                min(max($0, sensitivityRange.lowerBound), sensitivityRange.upperBound)
            } ?? Preset.medium.rawValue)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(isOn, forKey: Self.onKey)
        defaults.set(tint.rawValue, forKey: Self.tintKey)
        defaults.set(sensitivity, forKey: Self.sensitivityKey)
    }

    /// The edges of a camera picture as a transparent image the same shape,
    /// tinted where they're sharp. It's worked out at most `maxWidth` wide.
    func overlay(for buffer: CVPixelBuffer, context: CIContext, maxWidth: CGFloat = 960) -> CGImage? {
        let source = CIImage(cvPixelBuffer: buffer)
        guard source.extent.width > 0 else { return nil }
        let scale = min(1, maxWidth / source.extent.width)
        let small = source.applyingFilter("CILanczosScaleTransform", parameters: ["inputScale": scale, "inputAspectRatio": 1])
        let extent = small.extent.integral
        let edges = small
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            // Takes out camera noise, which would otherwise light up flat areas.
            .applyingFilter("CIMedianFilter")
            .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 3])
            .applyingFilter("CIColorThreshold", parameters: ["inputThreshold": threshold])
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 1])
            .cropped(to: extent)
        let mask = edges.applyingFilter("CIMaskToAlpha")
        let rgb = tint.rgb
        let color = CIImage(color: CIColor(red: rgb.red, green: rgb.green, blue: rgb.blue)).cropped(to: extent)
        let tinted = color.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: mask,
        ])
        return context.createCGImage(tinted, from: extent)
    }
}

/// The newest focus peaking picture. The live view watches this on its own,
/// so new pictures redraw only the overlay, not the whole window.
@MainActor
final class PeakingFeed: ObservableObject {
    @Published var image: CGImage?
}
