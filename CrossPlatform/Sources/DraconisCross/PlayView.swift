import DraconisCore
import DraconisPlatform
import Foundation
import SwiftCrossUI

struct PlayView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            hero
            if let game = model.selectedGame {
                launchCard(game)
                northstarCard(game)
                if let warning = model.steamWarning {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("STEAM AND NORTHSTAR").stencil()
                        Text(warning)
                    }
                    .glassCard(tinted: true)
                }
                if model.needsRunner && model.selectedRunner == nil {
                    Text("This copy runs through Wine or Proton. Pick or download one in Settings.")
                        .glassCard(tinted: true)
                }
            } else {
                setupCard
            }
        }
    }

    var hero: some View {
        HStack(spacing: 18) {
            if let icon = NativeStyle.resources?.appendingPathComponent("icon.png") {
                Image(icon).resizable().frame(width: 84, height: 84)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("DRACONIS").hero(36)
                Text("Titanfall 2 + Northstar").foregroundColor(Theme.secondary)
            }
            Spacer()
            if model.gameRunning {
                Text("● RUNNING").stencil()
            }
        }
        .glassCard()
    }

    func launchCard(_ game: GameInstall) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LAUNCH").stencil()
            ButtonRow {
                Button(model.launching ? "Starting…" : "Launch Northstar") {
                    Task { await model.launch(.northstar) }
                }
                .prominent()
                .fixedSize()
                .disabled(model.launching || model.gameRunning || !game.hasNorthstar)
                Button("Launch Vanilla") { Task { await model.launch(.vanilla) } }
                    .fixedSize()
                    .disabled(model.launching || model.gameRunning)
            }
            Text(game.hasNorthstar
                 ? "Vanilla uses Northstar's vanilla-compatible mode, which can join official servers."
                 : "Northstar isn't installed yet: vanilla starts the unmodified game.")
                .foregroundColor(Theme.faint)
        }
        .glassCard()
    }

    func northstarCard(_ game: GameInstall) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NORTHSTAR").stencil()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.northstarVersion.map { "Installed: \($0)" } ?? "Not installed")
                        .font(.system(size: 16, weight: .semibold))
                    if let latest = model.latestRelease {
                        Text("Latest: \(latest.tagName)").foregroundColor(Theme.faint)
                    }
                }
                Spacer()
                if model.northstarBusy {
                    ProgressView(value: model.northstarProgress.map { $0.fraction >= 0 ? $0.fraction : 0 } ?? 0)
                        .frame(width: 160)
                } else {
                    Button(game.hasNorthstar ? (model.northstarUpToDate ? "Reinstall" : "Update") : "Install") {
                        Task { await model.installNorthstar() }
                    }
                    if game.hasNorthstar {
                        Button("Remove") { Task { await model.uninstallNorthstar() } }.fixedSize()
                    }
                }
            }
            if let detail = model.northstarProgress?.detail {
                Text(detail).foregroundColor(Theme.faint)
            }
            Toggle("Keep Northstar up to date", isOn: $model.settings.autoUpdateNorthstar)
                .toggleStyle(.switch)
        }
        .glassCard()
    }

    var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SET UP TITANFALL 2").stencil()
            Text("Draconis didn't find Titanfall 2. Install it with Steam, or open Settings to pick its folder or create a Wine prefix with the EA app.")
            ButtonRow {
                Button("Open Settings") { model.section = .settings }
                    .prominent()
                    .fixedSize()
                Button("Rescan") { Task { await model.rescan() } }.fixedSize()
            }
        }
        .glassCard(tinted: true)
    }
}

