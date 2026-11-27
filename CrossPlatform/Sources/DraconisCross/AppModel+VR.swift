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
            #if !os(Windows)
            let prefix = gameSteam?.compatData(appID: SteamLocator.titanfallAppID)?.appendingPathComponent("pfx")
            guard VCRuntime.canInstall(prefix: prefix) else { throw LaunchFailure(VCRuntime.missingTool) }
            #endif
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
            #if os(Windows)
            try await ensureVRRuntime()
            try WindowsVR.launch(gameRoot: game.root)
            status = "Starting Titanfall 2 VR… put on your headset."
            try await awaitGameStart("Titanfall 2 VR")
            #else
            guard case .steam(let steamRoot, let kind, _) = game.source else { return }
            try prepareWrapper()
            // Changing launch options can close Steam (and SteamVR with it), so first.
            try await addNorthstarLaunchOption(root: steamRoot, kind: kind, wrapper: LinuxSteamVR.wrapper.path)
            try await ensureVRRuntime()
            if let prefix = gameSteam?.compatData(appID: SteamLocator.titanfallAppID)?.appendingPathComponent("pfx") {
                status = "Checking the VC++ runtime…"
                try await VCRuntime.ensure(prefix: prefix)
            }
            try LinuxSteamVR.writeLaunchArguments(gameRoot: game.root)
            guard let steam = LaunchPlanner.steamCommand(kind: kind) else { throw LaunchPlanner.PlanError.noSteam }
            let logStart = LinuxSteamVR.launchLogSize()
            try Spawner.launch(steam[0], Array(steam.dropFirst()) + ["-applaunch", SteamLocator.titanfallAppID, LinuxSteamVR.launchFlag],
                               log: gameLog)
            status = "Steam is starting Titanfall 2 VR…"
            try await awaitVRStart(logStart: logStart)
            #endif
        } catch {
            vrError = error.localizedDescription
            fail(error)
        }
    }

    /// Start SteamVR when no VR runtime is running, and wait for it.
    func ensureVRRuntime() async throws {
        await refreshVR()
        guard let runtime = vrRuntime else { return }
        switch runtime.plan {
        case .ready:
            return
        case .startActive(let name):
            throw LaunchFailure("\(name) is your active OpenXR runtime but it isn't running. Start it (or switch to SteamVR), then launch again.")
        case .noRuntime:
            throw LaunchFailure("No VR runtime found. Install SteamVR (Steam → Library → Tools), or start WiVRn or Monado, then launch again.")
        case .startSteamVR:
            startSteamVR()
            status = "Starting SteamVR… Meta Quest 3: open Steam Link on the headset and connect to this PC."
            for _ in 0..<60 {
                try await Task.sleep(for: .seconds(2))
                await refreshVR()
                if vrRuntime?.steamVRRunning == true { return }
            }
            throw LaunchFailure("SteamVR didn't start within 2 minutes. Start it from Steam (or connect with Steam Link), then launch again.")
        }
    }

    #if !os(Windows)
    /// Follow the wrapper's log: the EA app signs in first, then the VR launcher starts.
    func awaitVRStart(logStart: UInt64) async throws {
        for _ in 0..<180 {
            try await Task.sleep(for: .seconds(2))
            // Steam's own processes carry Titanfall2.exe's path from the start;
            // only the VR launcher's means the game is really starting.
            if HostProcesses.anyCommandLine(containing: [TitanfallVR.launcher]) {
                gameRunning = true
                Log.ok("launch", "Titanfall 2 VR is running")
                Task { await watchUntilExit() }
                return
            }
            switch LinuxSteamVR.launchStep(since: logStart) {
            case .startingEA: status = "Starting the EA app in the game's prefix. Sign in if it asks…"
            case .signedIn: status = "EA app signed in. Starting Titanfall 2 VR…"
            case .starting: status = "Starting Titanfall 2 VR… put on your headset."
            case .failed(let message): throw LaunchFailure(message)
            case nil: break
            }
        }
        throw LaunchFailure("Titanfall 2 VR didn't start within 6 minutes. See \(LinuxSteamVR.state.path)/launch.log.")
    }
    #endif

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
