import DraconisCore
import DraconisPlatform
import Foundation

/// Titanfall 2 VR: CircuitLord's OpenXR mod in its own TF2VR profile.
/// Windows runs it directly; on Linux Steam runs it through Draconis's launch
/// wrapper, so SteamVR / Steam Link and other OpenXR runtimes work.
extension AppModel {
    var vrSupported: Bool {
        #if os(Windows)
        return selectedGame != nil
        #else
        guard let game = selectedGame, case .steam = game.source else { return false }
        return true
        #endif
    }

    var vrUpdateAvailable: Bool {
        guard let latest = vrLatest, let record = vrRecord else { return false }
        return latest.mod.version != record.version || latest.northstar.version != record.northstarVersion
    }

    var gameSteam: SteamInstall? {
        if let game = selectedGame, case .steam(let root, let kind, _) = game.source {
            return SteamInstall(root: root, kind: SteamInstall.Kind(rawValue: kind) ?? .native)
        }
        return SteamLocator.installs().first
    }

    func refreshVR(fetchLatest: Bool = false) async {
        vrRecord = selectedGame.flatMap { TitanfallVR.isInstalled(in: $0.root) ? TitanfallVR.record(in: $0.root) : nil }
        let steam = gameSteam
        vrRuntime = await Task.detached { VRRuntimeStatus.detect(steam: steam) }.value
        if fetchLatest, vrLatest == nil { vrLatest = try? await TitanfallVR.latest() }
    }

    static let hasher: TitanfallVR.Hasher = { try RunnerDownloads.sha256(of: $0) }

    func installVR() async {
        guard let game = selectedGame, !vrBusy, vrSupported else { return }
        vrBusy = true
        error = nil
        vrError = nil
        defer { vrBusy = false; vrPhase = nil; vrProgress = nil }
        do {
            vrPhase = "Checking the latest release…"
            let release = try await TitanfallVR.latest()
            vrLatest = release
            vrPhase = "Downloading Titanfall 2 VR \(release.mod.version) and Northstar \(release.northstar.version)…"
            let root = game.root
            let stage = try await Task.detached {
                try await TitanfallVR.stage(release, gameRoot: root, hasher: Self.hasher) { p in
                    Task { @MainActor in self.vrProgress = p.fraction >= 0 ? p.fraction : nil }
                }
            }.value
            vrProgress = nil
            #if os(Windows)
            vrPhase = "Building the mod's game assets (a few minutes)…"
            try await WindowsVR.buildAssets(gameRoot: root, stage: stage) { f in
                Task { @MainActor in self.vrProgress = f }
            }
            #else
            guard case .steam(let steamRoot, let kind, _) = game.source else { return }
            let dll = stage.appendingPathComponent("mod/Titanfall2VR.dll")
            let patched = try LoopbackPatch.apply(to: dll)
            guard patched == .patched else {
                if case .unknown(let detail) = patched { throw TitanfallVR.VRError.audioFix(detail) }
                return
            }
            try prepareWrapper()
            try await addNorthstarLaunchOption(root: steamRoot, kind: kind, wrapper: LinuxSteamVR.wrapper.path)
            vrPhase = "Building the mod's game assets through Steam (a few minutes; Steam shows Titanfall 2 as running)…"
            LinuxSteamVR.clearAssetBuild()
            guard let steam = LaunchPlanner.steamCommand(kind: kind) else { throw LaunchPlanner.PlanError.noSteam }
            try Spawner.launch(steam[0], Array(steam.dropFirst()) + ["-applaunch", SteamLocator.titanfallAppID, LinuxSteamVR.setupFlag],
                               log: gameLog)
            var result: Int32?
            for _ in 0..<(45 * 60) {
                try await Task.sleep(for: .seconds(1))
                vrProgress = LinuxSteamVR.assetBuildProgress()
                if let done = LinuxSteamVR.assetBuildResult() { result = done; break }
            }
            guard let result else { throw TitanfallVR.VRError.assets("Steam didn't run the asset build within 45 minutes. See \(LinuxSteamVR.state.path)/launch.log.") }
            guard result == 0 else { throw TitanfallVR.VRError.assets("asset_patcher.exe exited with \(result): \(LinuxSteamVR.assetBuildLogTail())") }
            if let prefix = SteamInstall(root: steamRoot, kind: SteamInstall.Kind(rawValue: kind) ?? .native)
                .compatData(appID: SteamLocator.titanfallAppID)?.appendingPathComponent("pfx") {
                vrPhase = "Updating the VC++ runtime in the game's prefix…"
                try await VCRuntime.ensure(prefix: prefix)
            }
            #endif
            vrPhase = "Checking and installing the files…"
            vrProgress = nil
            try await Task.detached {
                try TitanfallVR.verifyAssets(stage: stage, hasher: Self.hasher)
                try TitanfallVR.place(stage: stage, release: release, gameRoot: root)
            }.value
            status = "Titanfall 2 VR \(release.mod.version) is installed."
            Log.ok("vr", "Titanfall 2 VR \(release.mod.version) with Northstar \(release.northstar.version) installed in \(root.path)/TF2VR")
        } catch {
            vrError = error.localizedDescription
            fail(error)
        }
        await refreshVR()
    }

    func uninstallVR() async {
        guard let game = selectedGame, !vrBusy else { return }
        TitanfallVR.uninstall(from: game.root)
        status = "Titanfall 2 VR was removed. Your normal game and Northstar are unchanged."
        await refreshVR()
    }

    func launchVR() async {
        guard let game = selectedGame, !launching, !gameRunning, TitanfallVR.isInstalled(in: game.root) else { return }
        launching = true
        error = nil
        vrError = nil
        defer { launching = false; status = nil }
        do {
            let replacements = TitanfallVR.directXReplacements(in: game.root)
            guard replacements.isEmpty else {
                throw LaunchFailure("Another mod replaced DirectX files, which breaks VR rendering. Remove these and launch again: \(replacements.map(\.path).joined(separator: ", "))")
            }
            await refreshVR()
            #if os(Windows)
            try WindowsVR.launch(gameRoot: game.root)
            status = "Starting Titanfall 2 VR…"
            #else
            guard case .steam(let steamRoot, let kind, _) = game.source else { return }
            try prepareWrapper()
            try await addNorthstarLaunchOption(root: steamRoot, kind: kind, wrapper: LinuxSteamVR.wrapper.path)
            if let prefix = gameSteam?.compatData(appID: SteamLocator.titanfallAppID)?.appendingPathComponent("pfx") {
                status = "Checking the VC++ runtime…"
                try await VCRuntime.ensure(prefix: prefix)
            }
            try LinuxSteamVR.writeLaunchArguments(gameRoot: game.root)
            guard let steam = LaunchPlanner.steamCommand(kind: kind) else { throw LaunchPlanner.PlanError.noSteam }
            try Spawner.launch(steam[0], Array(steam.dropFirst()) + ["-applaunch", SteamLocator.titanfallAppID, LinuxSteamVR.launchFlag],
                               log: gameLog)
            status = "Steam is starting Titanfall 2 VR (the EA app signs in first)…"
            #endif
            if vrRuntime?.anyRunning == false {
                status = (status ?? "") + " No VR runtime is running yet: start SteamVR or Steam Link on the headset."
            }
            try await awaitGameStart("Titanfall 2 VR")
        } catch {
            vrError = error.localizedDescription
            fail(error)
        }
    }

    func startSteamVR() {
        guard let steam = gameSteam else { return }
        #if os(Windows)
        let exe = steam.root.appendingPathComponent("steam.exe").path
        try? Spawner.launch(exe, ["steam://run/\(VRRuntimeStatus.steamVRAppID)"])
        #else
        guard let command = LaunchPlanner.steamCommand(kind: steam.kind.rawValue) else { return }
        try? Spawner.launch(command[0], Array(command.dropFirst()) + ["steam://run/\(VRRuntimeStatus.steamVRAppID)"])
        #endif
        status = "Starting SteamVR…"
        Task {
            try? await Task.sleep(for: .seconds(8))
            await refreshVR()
            if status == "Starting SteamVR…" { status = nil }
        }
    }

    func prepareWrapper() throws {
        guard let bundled = NativeStyle.resources?.appendingPathComponent("draconis-steam-launch") else {
            throw LaunchFailure("Draconis's Steam launch wrapper is missing from the app.")
        }
        try LinuxSteamVR.installWrapper(from: bundled)
    }
}
