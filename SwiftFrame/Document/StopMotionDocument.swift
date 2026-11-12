import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let swiftFrameProject = UTType(exportedAs: "com.wesvasher.swiftframe.project")
}

/// A `.swiftframe` package:
///
///     My Film.swiftframe/
///       Project.json        frames, holds, frame rate, onion skin settings
///       Frames/<uuid>.jpg   one picture per image id
///
/// Each open document is its own capture window.
final class StopMotionDocument: ReferenceFileDocument, @unchecked Sendable {
    static let readableContentTypes: [UTType] = [.swiftFrameProject]

    static let projectFile = "Project.json"
    static let framesFolder = "Frames"

    @Published var project: Project
    /// JPEG data by image id. Images no frame uses any more stay here (undo
    /// may bring their frames back) but aren't saved.
    @Published private(set) var images: [UUID: Data]

    struct Snapshot: Sendable {
        var project: Project
        var images: [UUID: Data]
    }

    init() {
        project = Project()
        images = [:]
    }

    init(project: Project, images: [UUID: Data]) {
        self.project = project
        self.images = images
    }

    required init(configuration: ReadConfiguration) throws {
        let (project, images) = try Self.read(configuration.file)
        self.project = project
        self.images = images
    }

    static func read(_ file: FileWrapper) throws -> (Project, [UUID: Data]) {
        guard let children = file.fileWrappers,
              let json = children[projectFile]?.regularFileContents
        else { throw CocoaError(.fileReadCorruptFile) }
        let project = try JSONDecoder().decode(Project.self, from: json)
        var images: [UUID: Data] = [:]
        for (name, wrapper) in children[framesFolder]?.fileWrappers ?? [:] {
            let base = (name as NSString).deletingPathExtension
            if let id = UUID(uuidString: base), let data = wrapper.regularFileContents {
                images[id] = data
            }
        }
        return (project, images)
    }

    func snapshot(contentType: UTType) throws -> Snapshot {
        Snapshot(project: project, images: images)
    }

    func fileWrapper(snapshot: Snapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        try Self.fileWrapper(for: snapshot, existing: configuration.existingFile)
    }

    /// Builds the package, reusing the existing file's frame files so saving
    /// doesn't rewrite every picture.
    static func fileWrapper(for snapshot: Snapshot, existing: FileWrapper?) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(snapshot.project)

        let old = existing?.fileWrappers?[framesFolder]?.fileWrappers ?? [:]
        var frames: [String: FileWrapper] = [:]
        for id in Set(snapshot.project.frames.map(\.image)) {
            let name = "\(id.uuidString).jpg"
            if let reused = old[name], reused.isRegularFile {
                frames[name] = reused
            } else if let data = snapshot.images[id] {
                frames[name] = FileWrapper(regularFileWithContents: data)
            }
        }
        for (name, wrapper) in frames { wrapper.preferredFilename = name }

        let framesWrapper = FileWrapper(directoryWithFileWrappers: frames)
        let projectWrapper = FileWrapper(regularFileWithContents: json)
        return FileWrapper(directoryWithFileWrappers: [
            projectFile: projectWrapper,
            framesFolder: framesWrapper,
        ])
    }

    // MARK: - Editing

    /// Adds a picture and returns its id. Pictures aren't part of undo; a
    /// frame that uses one is.
    @MainActor
    func addImage(_ data: Data) -> UUID {
        let id = UUID()
        images[id] = data
        return id
    }

    /// Changes the project as one undoable step.
    @MainActor
    func edit(_ actionName: String, undoManager: UndoManager?, _ change: (inout Project) -> Void) {
        let old = project
        change(&project)
        guard project != old else { return }
        registerUndo(restoring: old, actionName: actionName, undoManager: undoManager)
    }

    @MainActor
    private func registerUndo(restoring old: Project, actionName: String, undoManager: UndoManager?) {
        guard let undoManager else { return }
        let manager = undoManager
        manager.registerUndo(withTarget: self) { document in
            let current = document.project
            document.project = old
            document.registerUndo(restoring: current, actionName: actionName, undoManager: manager)
        }
        manager.setActionName(actionName)
    }
}
