import DraconisCore
import DraconisPlatform
import Foundation
import SwiftCrossUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.chooseFile) var chooseFile

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            gameCard
            #if !os(Windows)
            runnerCard
            prefixCard
            #endif
            aboutCard
        }
    }

    var gameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Stencil("Titanfall 2")
            Text("Draconis finds Steam copies (native, Flatpak, Snap), EA app and Epic copies\(os == "Windows" ? "" : " in Draconis or Heroic prefixes"), and folders you add.")
                .foregroundColor(Theme.secondary)
            ForEach(model.games) { game in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.name).font(.system(size: 14, weight: .semibold))
                        Text(game.root.path).foregroundColor(Theme.faint)
                    }
                    Spacer()
                    if game.id == model.selectedGame?.id {
                        Stencil("Selected")
                    } else {
                        GlassButton(title: "Use", icon: "circle-check", size: 13) { model.settings.selectedGame = game.id; model.refreshInstalledMods() }
                    }
                }
            }
            ButtonRow {
                GlassButton(title: "Add a game folder…", icon: "folder-plus", size: 13) {
                    Task {
                        if let url = await chooseFile(title: "Titanfall 2 folder", defaultButtonLabel: "Add",
                                                      allowSelectingFiles: false, allowSelectingDirectories: true) {
                            await model.addGameFolder(url)
                        }
                    }
                }
                GlassButton(title: "Rescan", icon: "refresh-cw", size: 13) { Task { await model.rescan() } }
            }
        }
        .glassCard()
    }

    #if !os(Windows)
    var runnerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Stencil("Runner")
            Text("Steam copies run with the Proton you pick in Steam. Copies in a Wine prefix run with the build below; Proton goes through umu-launcher.")
                .foregroundColor(Theme.secondary)
            if model.runners.isEmpty {
                Text("No Proton or Wine found.").foregroundColor(Theme.faint)
            } else {
                Picker(of: model.runners, selection: Binding(
                    get: { model.selectedRunner },
                    set: { model.settings.runnerID = $0?.id }))
            }
            Text(model.umuRun.map { "umu-launcher: \($0.path)" } ?? "umu-launcher: not installed")
                .foregroundColor(Theme.faint)
            ButtonRow {
                GlassButton(title: "Download GE-Proton", icon: "download", size: 13) { Task { await model.installGEProton() } }
                    .disabled(model.toolBusy != nil)
                if model.umuRun == nil {
                    GlassButton(title: "Install umu-launcher", icon: "download", size: 13) { Task { await model.installUmu() } }
                        .fixedSize()
                        .disabled(model.toolBusy != nil)
                }
            }
            toolProgress
        }
        .glassCard()
    }

    var prefixCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Stencil("EA App / Epic Copy")
            Text("No Steam? Draconis can make its own Wine prefix (in its data folder, never ~/.wine) and install the EA app there. Sign in, install Titanfall 2 from the EA app, then Rescan. Epic owners: link your Epic account in the EA app.")
                .foregroundColor(Theme.secondary)
            GlassButton(title: "Create prefix with the EA app", icon: "folder-plus", size: 13) { Task { await model.createPrefixWithEAApp() } }
                .disabled(model.toolBusy != nil || model.selectedRunner == nil)
        }
        .glassCard()
    }
    #endif

    @ViewBuilder
    var toolProgress: some View {
        if let busy = model.toolBusy {
            VStack(alignment: .leading, spacing: 4) {
                Text(busy)
                ProgressView(value: model.toolProgress.map { max($0.fraction, 0) } ?? 0)
                if let detail = model.toolProgress?.detail { Text(detail).foregroundColor(Theme.faint) }
            }
        }
    }

    var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Stencil("About")
            Text("Draconis \(AppInfo.version) for \(os)").font(.system(size: 15, weight: .semibold))
            Text("Data folder: \(CorePaths.dataDirectory.path)").foregroundColor(Theme.faint)
            ButtonRow {
                OpenLinkButton(title: "Releases", url: AppInfo.releasesPage)
                OpenLinkButton(title: "Report a bug", url: AppInfo.issuesPage, icon: "circle-alert")
                GlassButton(title: "Check for updates", icon: "refresh-cw", size: 13) { Task { await model.checkForDraconisUpdate() } }
            }
            Text("Draconis is free software under the GPL-3.0-or-later. It uses SwiftCrossUI (MIT), ZIPFoundation (MIT), swift-crypto (Apache-2.0) and the Orbitron font (SIL OFL 1.1); see THIRD-PARTY-NOTICES.md. umu-launcher (GPL-3.0) and GE-Proton are downloaded only when you ask.")
                .foregroundColor(Theme.faint)
        }
        .glassCard()
    }

    var os: String {
        #if os(Windows)
        return "Windows"
        #elseif os(Linux)
        return "Linux"
        #else
        return "macOS"
        #endif
    }
}

extension Runner: @retroactive CustomStringConvertible {
    public var description: String { "\(name) (\(kind == .proton ? "Proton" : "Wine"), \(source))" }
}
