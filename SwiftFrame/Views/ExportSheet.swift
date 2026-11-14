import SwiftUI

/// Choose how to export: a movie (H.264, HEVC or ProRes, .mov or .mp4), an
/// animated GIF, or an image sequence, and how big. Export then asks where.
struct ExportSheet: View {
    @ObservedObject var model: WindowModel

    var body: some View {
        let settings = $model.exportSettings
        VStack(alignment: .leading, spacing: 0) {
            Text("Export Animation")
                .font(.title3.weight(.semibold))
                .padding([.horizontal, .top], 20)

            Form {
                Picker("Format", selection: settings.kind) {
                    ForEach(ExportSettings.Kind.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)

                switch model.exportSettings.kind {
                case .movie:
                    Picker("Codec", selection: settings.codec) {
                        ForEach(MovieExporter.Codec.allCases.filter { !$0.isProRes }) { Text($0.rawValue).tag($0) }
                        Divider()
                        ForEach(MovieExporter.Codec.allCases.filter(\.isProRes)) { Text($0.rawValue).tag($0) }
                    }
                    Picker("File", selection: settings.container) {
                        ForEach(ExportSettings.Container.allCases) { Text($0.name).tag($0) }
                    }
                    .disabled(model.exportSettings.codec.isProRes)
                case .gif:
                    Toggle("Loop forever", isOn: settings.loopGIF)
                case .images:
                    Picker("Pictures", selection: settings.imageFormat) {
                        ForEach(ExportSettings.ImageFormat.allCases) { Text($0.name).tag($0) }
                    }
                }

                Picker("Size", selection: settings.size) {
                    ForEach(ExportSettings.Size.allCases) { Text($0.name).tag($0) }
                }

                LabeledContent("Output") {
                    Text(summary).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.showsExportSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") { model.export() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
    }

    /// What will be written, in a line or two.
    private var summary: String {
        let settings = model.exportSettings
        let size = pictureSize.map { settings.outputSize(width: $0.width, height: $0.height) }
        let dimensions = size.map { "\($0.width) × \($0.height)" } ?? ""
        let fps = "\(model.project.framesPerSecond) fps"
        let detail: String = switch settings.kind {
        case .movie: "\(settings.codec.note)"
        case .gif: "GIFs have 256 colors and big files; best for short, small loops."
        case .images: "\(model.frames.playbackLength) pictures, one per frame of playback, in a new folder."
        }
        return [dimensions, fps].filter { !$0.isEmpty }.joined(separator: ", ") + "\n" + detail
    }

    private var pictureSize: (width: Int, height: Int)? {
        guard let frame = model.frames.first,
              let image = model.images.image(frame.image, data: model.document.images[frame.image])
        else { return nil }
        return (image.width, image.height)
    }
}
