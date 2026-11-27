import DefaultBackend
import DraconisCore
import DraconisPlatform
import Foundation
import SwiftCrossUI

@main
struct DraconisApp: App {
    @State var model = AppModel()

    var body: some Scene {
        WindowGroup("Draconis") {
            RootView(model: model)
                .colorScheme(.dark)
                .nativeWindow()
                .task { await model.bootstrap() }
        }
        .defaultSize(width: 1080, height: 700)
    }
}

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    if let icon = NativeStyle.resources?.appendingPathComponent("icon.png") {
                        Image(icon).resizable().frame(width: 30, height: 30)
                    }
                    Text(tracked("DRACONIS", 2)).hero(18)
                }
                .padding(.bottom, 14)
                ForEach(AppSection.allCases) { section in
                    SidebarItem(section: section, selected: (model.section ?? .play) == section) {
                        model.section = section
                    }
                }
                Spacer()
                gamePicker
            }
            .padding(16)
            .frame(minWidth: 220, maxWidth: 250)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    banners
                    detail
                }
                .padding(24)
                .frame(maxWidth: 900)
            }
            .background(LinearGradient(colors: [Theme.backgroundTop, Theme.background], startPoint: .top, endPoint: .bottom))
        }
    }

    @ViewBuilder
    var detail: some View {
        switch model.section ?? .play {
        case .play: PlayView(model: model)
        case .mods: ModsView(model: model)
        case .servers: ServersView(model: model)
        case .console: ConsoleView(model: model)
        case .settings: SettingsView(model: model)
        }
    }

    @ViewBuilder
    var banners: some View {
        if let version = model.newerVersion {
            HStack {
                Text("Draconis \(version) is available.")
                Spacer()
                OpenLinkButton(title: "Download", url: AppInfo.releasesPage)
            }
            .glassCard(tinted: true)
        }
        if let error = model.error {
            HStack {
                Text(error)
                Spacer()
                GlassButton(title: "Dismiss", icon: "x", size: 13) { model.error = nil }
            }
            .errorCard()
        }
        if let status = model.status {
            Text(status).foregroundColor(Theme.secondary)
        }
    }

    var gamePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Stencil("Game", size: 10)
            if model.games.isEmpty {
                Text("No Titanfall 2 found").foregroundColor(Theme.faint)
            } else {
                Picker(of: model.games, selection: Binding(
                    get: { model.selectedGame },
                    set: { model.settings.selectedGame = $0?.id; model.refreshInstalledMods() }
                ))
            }
            GlassButton(title: model.scanning ? "Scanning…" : "Rescan", icon: "refresh-cw", size: 13) {
                Task { await model.rescan() }
            }
        }
    }
}

struct OpenLinkButton: View {
    @Environment(\.openURL) var openURL
    var title: String
    var url: URL
    var icon = "download"

    var body: some View {
        GlassButton(title: title, icon: icon, size: 13) { openURL(url) }
    }
}

extension GameInstall: @retroactive CustomStringConvertible {
    public var description: String { "\(name) · \(root.lastPathComponent)" }
}

struct SidebarItem: View {
    var section: AppSection
    var selected: Bool
    var action: @MainActor @Sendable () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            IconView(name: section.icon, size: 17)
            Text(section.description).titleFont(16)
                .foregroundColor(selected ? Theme.primary : Theme.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Color(white: 1, opacity: selected ? 0.14 : hovering ? 0.07 : 0)))
        .onHover { hovering = $0 }
        .onTapGesture { action() }
    }
}
