import DraconisCore
import DraconisPlatform
import Foundation
import SwiftCrossUI

struct PlayView: View {
    @Bindable var model: AppModel
    @State var mode: LaunchMode = .northstar

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero
            if let game = model.selectedGame {
                pills(game)
                actions(game)
                if model.northstarBusy || model.toolBusy != nil { progressCard }
                if let warning = model.steamWarning {
                    notice("STEAM AND NORTHSTAR", warning)
                }
                if model.needsRunner && model.selectedRunner == nil {
                    notice("RUNNER", "This copy runs through Wine or Proton. Pick or download one in Settings.")
                }
            } else {
                setupCard
            }
        }
    }

    var hero: some View {
        VStack(spacing: 8) {
            if let icon = NativeStyle.resources?.appendingPathComponent("icon.png") {
                Image(icon).resizable().frame(width: 96, height: 96)
            }
            Text(tracked("DRACONIS", 3)).hero(46).foregroundColor(Theme.primary)
            Text("Titanfall 2 + Northstar").titleFont(17).foregroundColor(Theme.secondary)
            if let game = model.selectedGame {
                Text(game.description).foregroundColor(Theme.faint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    func pills(_ game: GameInstall) -> some View {
        HStack(spacing: 12) {
            StatusPill(label: "Titanfall 2", value: "Installed", icon: "gamepad-2", active: true)
            StatusPill(label: "Launcher", value: launcher(game), icon: "shield-check", active: launcherReady(game))
            StatusPill(label: "Northstar", value: game.northstarVersion.map { "v\($0)" } ?? "Missing",
                       icon: "zap", active: game.hasNorthstar)
        }
    }

    func launcher(_ game: GameInstall) -> String {
        switch game.source {
        case .steam: return "Steam"
        case .native(let origin): return origin
        case .prefix: return model.selectedRunner?.name ?? "No runner"
        }
    }

    func launcherReady(_ game: GameInstall) -> Bool {
        !model.needsRunner || model.selectedRunner != nil
    }

    func actions(_ game: GameInstall) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Segmented(options: [(LaunchMode.northstar, "Northstar"), (.vanilla, "Vanilla")], selection: $mode)
            GlassButton(title: launchTitle(game), icon: "play", kind: .prominent, fullWidth: true, size: 18,
                        disabled: model.launching || model.gameRunning || (mode == .northstar && !game.hasNorthstar)) {
                let mode = mode
                Task { await model.launch(mode) }
            }
            Text(caption(game)).foregroundColor(Theme.faint)
            HStack(spacing: 10) {
                if !game.hasNorthstar {
                    GlassButton(title: "Install Northstar", icon: "download", disabled: model.northstarBusy) {
                        Task { await model.installNorthstar() }
                    }
                } else {
                    if !model.northstarUpToDate, let latest = model.latestRelease {
                        GlassButton(title: "Update to \(latest.tagName)", icon: "refresh-cw", disabled: model.northstarBusy) {
                            Task { await model.installNorthstar() }
                        }
                    }
                    GlassButton(title: "Uninstall NS", icon: "trash", disabled: model.northstarBusy) {
                        Task { await model.uninstallNorthstar() }
                    }
                }
                Spacer()
                Toggle("Auto-update", isOn: $model.settings.autoUpdateNorthstar).toggleStyle(.switch)
            }
        }
        .glassCard(radius: 24, padding: 22)
    }

    func launchTitle(_ game: GameInstall) -> String {
        if model.gameRunning { return "Running" }
        if model.launching { return "Starting…" }
        return mode == .northstar ? "Launch Northstar" : "Launch"
    }

    func caption(_ game: GameInstall) -> String {
        switch mode {
        case .northstar:
            return game.hasNorthstar ? "Modded Titanfall 2 with Northstar's community servers."
                : "Install Northstar to play on community servers."
        case .vanilla:
            return game.hasNorthstar ? "Northstar's vanilla-compatible mode: joins official servers."
                : "The unmodified game on official servers."
        }
    }

    var progressCard: some View {
        let progress = model.northstarProgress ?? model.toolProgress
        return VStack(alignment: .leading, spacing: 8) {
            Stencil(model.toolBusy ?? "Northstar", size: 11)
            if let detail = progress?.detail { Text(detail).foregroundColor(Theme.secondary) }
            ProgressView(value: progress.map { $0.fraction >= 0 ? $0.fraction : 0 } ?? 0)
        }
        .glassCard(radius: 18, padding: 16)
    }

    func notice(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Stencil(title)
            Text(text).foregroundColor(Theme.secondary)
        }
        .glassCard(tinted: true, radius: 18, padding: 16)
    }

    var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stencil("Set up Titanfall 2")
            Text("Draconis didn't find Titanfall 2. Install it with Steam, or open Settings to pick its folder or create a Wine prefix with the EA app.")
                .foregroundColor(Theme.secondary)
            HStack(spacing: 10) {
                GlassButton(title: "Open Settings", icon: "settings", kind: .prominent) { model.section = .settings }
                GlassButton(title: model.scanning ? "Scanning…" : "Rescan", icon: "refresh-cw") {
                    Task { await model.rescan() }
                }
            }
        }
        .glassCard(tinted: true, radius: 24, padding: 22)
    }
}
