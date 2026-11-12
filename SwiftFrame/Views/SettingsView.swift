import SwiftUI

/// Pages in the Settings window's sidebar.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case appearance

    static let storageKey = "settingsPage"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "circle.lefthalf.filled"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .appearance: .indigo
        }
    }
}

/// Settings: a sidebar of pages, with the chosen page on the right (like
/// System Settings and SwiftCut).
struct SettingsView: View {
    @AppStorage(SettingsPage.storageKey) private var page: SettingsPage = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: Binding(get: { page }, set: { if let new = $0 { page = new } })) { page in
                Label {
                    Text(page.title)
                } icon: {
                    Image(systemName: page.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(page.tint.gradient, in: RoundedRectangle(cornerRadius: 5))
                }
                .tag(page)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch page {
                case .general: GeneralSettingsView()
                case .appearance: AppearanceSettingsView()
                }
            }
            .navigationTitle(page.title)
        }
        .frame(width: 720, height: 460)
    }
}

/// SwiftFrame's light/dark setting.
enum AppAppearance: String, CaseIterable, Identifiable {
    case auto, light, dark

    var id: String { rawValue }
    static let storageKey = "appAppearance"

    /// Applies the setting to every window in the app.
    func apply() {
        switch self {
        case .auto: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    static var saved: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .auto
    }
}

/// Settings › Appearance: light, dark, or matching the Mac.
struct AppearanceSettingsView: View {
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.auto

    var body: some View {
        Form {
            Section("Appearance") {
                ChoiceCards(selection: $appearance, options: [
                    .init(value: .auto, title: "Auto", systemImage: "circle.lefthalf.filled", help: "Match your Mac's setting"),
                    .init(value: .light, title: "Light", systemImage: "sun.max.fill", help: "Always use light windows"),
                    .init(value: .dark, title: "Dark", systemImage: "moon.fill", help: "Always use dark windows"),
                ])
                Text("Auto follows your Mac's setting in System Settings › Appearance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: appearance) { _, new in new.apply() }
    }
}

/// Settings › General.
struct GeneralSettingsView: View {
    @AppStorage(GeneralSettings.flashOnCaptureKey) private var flashOnCapture = true
    @AppStorage(GeneralSettings.playheadFireKey) private var playheadFire = true

    var body: some View {
        Form {
            Section("Capturing") {
                Toggle("Flash the viewer when a frame is captured", isOn: $flashOnCapture)
            }
            Section("Playback") {
                Toggle("Fire trail behind the playhead", isOn: $playheadFire)
                Text("Sparks stream off the playhead while the animation plays. Off when Reduce Motion is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

enum GeneralSettings {
    static let flashOnCaptureKey = "flashOnCapture"
    static let playheadFireKey = "playheadFire"

    static var flashOnCapture: Bool {
        UserDefaults.standard.object(forKey: flashOnCaptureKey) as? Bool ?? true
    }
}
