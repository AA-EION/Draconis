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
            VStack(alignment: .leading, spacing: 12) {
                Text("DRACONIS").hero(22).padding(.bottom, 6)
                List(AppSection.allCases, id: \.self, selection: $model.section) { section in
                    Text(section.description).font(.system(size: 15, weight: .semibold))
                }
                Spacer()
                gamePicker
            }
            .padding(16)
            .frame(minWidth: 220, maxWidth: 260)
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
                Button("Dismiss") { model.error = nil }.fixedSize()
            }
            .errorCard()
        }
        if let status = model.status {
            Text(status).foregroundColor(Theme.secondary)
        }
    }

    var gamePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GAME").stencil()
            if model.games.isEmpty {
                Text("No Titanfall 2 found").foregroundColor(Theme.faint)
            } else {
                Picker(of: model.games, selection: Binding(
                    get: { model.selectedGame },
                    set: { model.settings.selectedGame = $0?.id; model.refreshInstalledMods() }
                ))
            }
            Button(model.scanning ? "Scanning…" : "Rescan") { Task { await model.rescan() } }.fixedSize()
        }
    }
}

struct OpenLinkButton: View {
    @Environment(\.openURL) var openURL
    var title: String
    var url: URL

    var body: some View {
        Button(title) { openURL(url) }.fixedSize()
    }
}

extension GameInstall: @retroactive CustomStringConvertible {
    public var description: String { "\(name) · \(root.lastPathComponent)" }
}
