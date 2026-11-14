import SwiftUI

@main
struct SwiftFrameApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        DocumentGroup(newDocument: { StopMotionDocument() }) { file in
            CaptureWindow(document: file.document, fileURL: file.fileURL)
        }
        .defaultSize(width: 1440, height: 860)
        .commands { FrameCommands() }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Start with a new capture window rather than an Open panel.
        UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppAppearance.saved.apply()
        ShutterRemote.shared.startIfEnabled()
        // Opening a project from Finder arrives first; otherwise start a new one.
        DispatchQueue.main.async {
            if NSDocumentController.shared.documents.isEmpty {
                NSDocumentController.shared.newDocument(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { NSDocumentController.shared.newDocument(nil) }
        return false
    }
}

/// The Frame menu. It acts on the front capture window.
struct FrameCommands: Commands {
    @FocusedObject private var model: WindowModel?

    var body: some Commands {
        CommandMenu("Frame") {
            // Tapping ⌘ on its own also captures (CommandTapMonitor); menus
            // can't show a lone modifier as a shortcut.
            Button("Capture Frame") { model?.capture() }
                .disabled(model?.canCapture != true)
            Button(model?.mode == .playback ? "Pause" : "Play") { model?.togglePlayback() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(model?.frames.isEmpty ?? true)
            // ⌘F again (or Escape) leaves full screen.
            Button("Play Full Screen") { model?.toggleFullScreenPlayback() }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(model.map { !$0.isPlayingFullScreen && $0.frames.isEmpty } ?? true)
            Button("Exit Full Screen Playback") { model?.endFullScreen() }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(model?.isPlayingFullScreen != true)
            Button("Go Live") { model?.goLive() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(model == nil || model?.mode == .live)
            Divider()
            Button("Previous Frame") { model?.step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(model?.frames.isEmpty ?? true)
            Button("Next Frame") { model?.step(1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(model?.frames.isEmpty ?? true)
            Button("Select All Frames") { model?.selectAll() }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled(model?.frames.isEmpty ?? true)
            Divider()
            Button("Duplicate") { model?.duplicateSelection() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(model?.hasSelection != true)
            Button("Hold Longer") { model?.changeHold(by: 1) }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(model?.hasSelection != true)
            Button("Hold Shorter") { model?.changeHold(by: -1) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(model?.hasSelection != true)
            Button("Reverse Order") { model?.reverseSelection() }
                .disabled((model?.selection.count ?? 0) < 2)
            Button("Delete") { model?.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model?.hasSelection != true)
            Divider()
            Button("Add Pictures…") { model?.importImages() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(model == nil)
        }
        CommandGroup(before: .toolbar) {
            Button("Zoom In Picture") { model?.zoomInViewer() }
                .keyboardShortcut("=", modifiers: [.command, .option])
                .disabled(model?.canZoomInViewer != true)
            Button("Zoom Out Picture") { model?.zoomOutViewer() }
                .keyboardShortcut("-", modifiers: [.command, .option])
                .disabled(model?.canZoomOutViewer != true)
            Button("Fit Picture") { model?.zoomViewerToFit() }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(model?.canZoomOutViewer != true)
            Toggle("Show Onion Skin", isOn: Binding(
                get: { model?.showsOnionSkin ?? true },
                set: { model?.setShowsOnionSkin($0) }))
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(model == nil)
            Toggle("Focus Peaking", isOn: Binding(
                get: { model?.focusPeaking.isOn ?? false },
                set: { model?.focusPeaking.isOn = $0 }))
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(model == nil)
            Divider()
            Button("Zoom In Timeline") { model?.zoomInTimeline() }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(model?.canZoomInTimeline != true)
            Button("Zoom Out Timeline") { model?.zoomOutTimeline() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(model?.canZoomOutTimeline != true)
            Button("Zoom Timeline to Fit") { model?.zoomTimelineToFit() }
                .keyboardShortcut("z", modifiers: .shift)
                .disabled(model?.canZoomTimelineToFit != true)
            Divider()
        }
        CommandGroup(after: .importExport) {
            Button("Export…") { model?.exportMovie() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(model?.frames.isEmpty ?? true)
        }
    }
}
