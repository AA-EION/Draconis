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
            Text("TITANFALL 2").stencil()
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
                        Text("SELECTED").stencil()
                    } else {
                        Button("Use") { model.settings.selectedGame = game.id; model.refreshInstalledMods() }.fixedSize()
                    }
                }
            }
            ButtonRow {
                Button("Add a game folder…") {
                    Task {
                        if let url = await chooseFile(title: "Titanfall 2 folder", defaultButtonLabel: "Add",
                                                      allowSelectingFiles: false, allowSelectingDirectories: true) {
                            await model.addGameFolder(url)
                        }
                    }
                }
                Button("Rescan") { Task { await model.rescan() } }.fixedSize()
            }
        }
        .glassCard()
    }

    #if !os(Windows)
    var runnerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RUNNER").stencil()
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
                Button("Download GE-Proton") { Task { await model.installGEProton() } }.fixedSize()
                    .disabled(model.toolBusy != nil)
                if model.umuRun == nil {
                    Button("Install umu-launcher") { Task { await model.installUmu() } }.fixedSize()
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
            Text("EA APP / EPIC COPY").stencil()
            Text("No Steam? Draconis can make its own Wine prefix (in its data folder, never ~/.wine) and install the EA app there. Sign in, install Titanfall 2 from the EA app, then Rescan. Epic owners: link your Epic account in the EA app.")
                .foregroundColor(Theme.secondary)
            Button("Create prefix with the EA app") { Task { await model.createPrefixWithEAApp() } }.fixedSize()
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
            Text("ABOUT").stencil()
            Text("Draconis \(AppInfo.version) for \(os)").font(.system(size: 15, weight: .semibold))
            Text("Data folder: \(CorePaths.dataDirectory.path)").foregroundColor(Theme.faint)
            ButtonRow {
                OpenLinkButton(title: "Releases", url: AppInfo.releasesPage)
                OpenLinkButton(title: "Report a bug", url: AppInfo.issuesPage)
                Button("Check for updates") { Task { await model.checkForDraconisUpdate() } }.fixedSize()
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
