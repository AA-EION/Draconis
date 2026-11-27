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
                if model.launching || model.gameRunning { launchCard }
                vrCard
                if model.northstarBusy || model.toolBusy != nil { progressCard }
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
        if model.launching { return "Launching…" }
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

    var vrCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                IconView(name: "glasses", size: 16)
                Stencil("Virtual reality")
                Spacer()
                if let record = model.vrRecord {
                    Text("v\(record.version)").foregroundColor(Theme.faint)
                }
            }
            if !model.vrSupported {
                Text("On Linux, VR works with the Steam copy of Titanfall 2 for now.").foregroundColor(Theme.secondary)
            } else if model.vrBusy {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(model.vrPhase ?? "Working…").foregroundColor(Theme.secondary)
                }
                if let progress = model.vrProgress { ProgressView(value: progress) }
            } else if model.vrRecord == nil {
                Text("CircuitLord's Titanfall 2 VR mod plays the campaign in VR through OpenXR. It installs into its own TF2VR profile, so the normal game and your Northstar stay as they are. About 180 MB to download, plus 3 GB of game files built on your PC.")
                    .foregroundColor(Theme.secondary)
                GlassButton(title: "Install VR mod", icon: "download", kind: .prominent, disabled: model.selectedGame == nil) {
                    Task { await model.installVR() }
                }
            } else {
                vrRuntimeRow
                HStack(spacing: 10) {
                    GlassButton(title: model.launching ? "Launching…" : model.gameRunning ? "Running" : "Launch in VR",
                                icon: "play", kind: .prominent, disabled: model.launching || model.gameRunning) {
                        Task { await model.launchVR() }
                    }
                    if model.vrUpdateAvailable, let latest = model.vrLatest {
                        GlassButton(title: "Update to \(latest.mod.version)", icon: "refresh-cw") { Task { await model.installVR() } }
                    }
                    Spacer()
                    GlassButton(title: "Remove VR", icon: "trash", size: 13) { Task { await model.uninstallVR() } }
                }
            }
            if let message = model.vrError {
                Text(message).foregroundColor(Color(red: 1, green: 0.55, blue: 0.55))
            }
            if model.vrSupported, model.launching, model.vrRecord != nil, let status = model.status {
                HStack(spacing: 10) { ProgressView(); Text(status).foregroundColor(Theme.secondary) }
            }
            Text(vrHelp).foregroundColor(Theme.faint)
        }
        .glassCard(radius: 24, padding: 22)
    }

    var vrRuntimeRow: some View {
        HStack(spacing: 10) {
            IconView(name: model.vrRuntime?.anyRunning == true ? "circle-check" : "circle-alert", size: 16)
            Text(vrRuntimeText).foregroundColor(Theme.secondary)
            Spacer()
            if model.vrRuntime?.steamVRInstalled == true, model.vrRuntime?.steamVRRunning == false {
                GlassButton(title: "Start SteamVR", icon: "play", size: 13) { model.startSteamVR() }
            }
            GlassButton(title: "Check again", icon: "refresh-cw", size: 13) { Task { await model.refreshVR() } }
        }
    }

    var vrRuntimeText: String {
        guard let runtime = model.vrRuntime else { return "Checking for a VR runtime…" }
        if runtime.steamVRRunning { return "SteamVR is running." }
        if let other = runtime.otherRunning { return "\(other) is running." }
        if let active = runtime.activeOpenXR { return "No VR runtime is running. The active OpenXR runtime is \(active)." }
        return "No VR runtime is running."
    }

    var vrHelp: String {
        #if os(Windows)
        return "Meta Quest 3: open Steam Link on the headset and connect to this PC; it starts SteamVR. Quest Link, Air Link, Virtual Desktop and other OpenXR runtimes work too: start yours first."
        #else
        return "Meta Quest 3: open Steam Link on the headset and connect to this PC; it starts SteamVR. Without SteamVR: WiVRn streams to Quest and Pico, Monado runs wired headsets. Start your runtime first."
        #endif
    }

    var launchCard: some View {
        HStack(spacing: 14) {
            if model.launching {
                ProgressView()
            } else {
                IconView(name: "circle-check", size: 20)
            }
            VStack(alignment: .leading, spacing: 4) {
                Stencil(model.launching ? "Launching" : "Running", size: 11)
                Text(model.launching ? (model.status ?? "Starting…") : "Titanfall 2 is running. Launch is available again once it closes.")
                    .foregroundColor(Theme.secondary)
            }
        }
        .glassCard(tinted: true, radius: 18, padding: 16)
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
