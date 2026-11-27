import Foundation

/// When a bottle has no Steam install, Draconis can pull the official Steam
/// setup .exe down from Valve's CDN and run it under the backend's own runtime.
///
/// We delegate to the backend driver's `launch()` rather than calling wine
/// directly, so this works the same way for CrossOver / Whisky / Sikarugir /
/// GPTK.
public actor SteamInstaller {
    public static let shared = SteamInstaller()

    private let setupURL = URL(
        string: "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"
    )!

    public enum InstallError: Error, LocalizedError {
        case downloadFailed
        case launchFailed(String)

        public var errorDescription: String? {
            switch self {
            case .downloadFailed:    return "Couldn't download SteamSetup.exe."
            case .launchFailed(let s): return "Steam installer failed: \(s)"
            }
        }
    }

    public func isSteamInstalled(in bottle: WineBottle) -> Bool {
        steamExePath(in: bottle) != nil
    }

    /// POSIX path to steam.exe inside the bottle, or nil if not installed.
    public func steamExePath(in bottle: WineBottle) -> String? {
        Self.steamExePath(in: bottle.prefixURL)
    }

    /// Free-function variant so bottle scanners can detect Steam without
    /// having to `await` an actor.
    public static func steamExePath(in prefixURL: URL) -> String? {
        let driveC = PathResolver.driveC(in: prefixURL)
        let candidates = [
            "Program Files (x86)/Steam/steam.exe",
            "Program Files/Steam/steam.exe",
        ]
        for rel in candidates {
            let url = driveC.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: url.path) {
                return url.path
            }
        }
        return nil
    }

    public func ensureInstallerDownloaded() async throws -> URL {
        let dest = PathResolver.downloadsCache.appendingPathComponent("SteamSetup.exe")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        Log.info("steam.install", "Downloading SteamSetup.exe…")
        do {
            let (tmp, response) = try await URLSession.shared.download(from: setupURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw InstallError.downloadFailed
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            Log.ok("steam.install", "SteamSetup.exe ready at \(dest.path)")
            return dest
        } catch {
            Log.error("steam.install", "\(error)")
            throw InstallError.downloadFailed
        }
    }

    /// Run SteamSetup.exe inside the bottle.
    public func install(into bottle: WineBottle, silent: Bool = true) async throws {
        let installer = try await ensureInstallerDownloaded()
        do {
            let status = try await WineBackendManager.shared.launchAndWait(
                executable: installer.path,
                arguments: silent ? ["/S"] : [],
                in: bottle
            )
            if status != 0 {
                throw InstallError.launchFailed("exit code \(status)")
            }
            // Without GPU-accelerated web views Steam's window renders black under Wine.
            try? await WineBackendManager.shared.setRegistry(
                key: "HKCU\\Software\\Valve\\Steam", value: "GPUAccelWebViewsV3",
                type: "REG_DWORD", data: "1", in: bottle)
            Log.ok("steam.install", "Steam installed in “\(bottle.name)”")
        } catch let error as InstallError {
            Log.error("steam.install", "\(error)")
            throw error
        } catch {
            Log.error("steam.install", "\(error)")
            throw InstallError.launchFailed(error.localizedDescription)
        }
    }

    public static let titanfallAppID = "1237970"

    /// Open Steam on Titanfall 2's install dialog (Steam asks the user to log in first).
    public func openTitanfallInstall(in bottle: WineBottle) async throws {
        try await runSteam(["steam://install/\(Self.titanfallAppID)"], in: bottle)
    }

    /// Launch Titanfall 2 through Steam. On the first launch Steam runs the
    /// game's EA app installer (`__Installer`), which is what puts the EA app
    /// into a Steam bottle.
    public func launchTitanfallThroughSteam(in bottle: WineBottle) async throws {
        try await runSteam(["-silent", "-applaunch", Self.titanfallAppID], in: bottle)
    }

    private func runSteam(_ arguments: [String], in bottle: WineBottle) async throws {
        guard let steam = steamExePath(in: bottle) else {
            throw InstallError.launchFailed("Steam isn't installed in “\(bottle.name)”")
        }
        guard bottle.backend == .draconis else {
            try await WineBackendManager.shared.spawn(executable: steam, arguments: arguments, in: bottle)
            return
        }
        let steamRoot = URL(fileURLWithPath: steam).deletingLastPathComponent()
        Self.installWebHelperWrapper(steamRoot: steamRoot)
        Self.purgeBrowserLocks(in: bottle)
        try await WineBackendManager.shared.spawn(
            executable: steam, arguments: Self.wineArguments + arguments, in: bottle,
                wineEnvironment: WineEngine.steamEnvironment)
        watchWebHelper(steam: steam, steamRoot: steamRoot, arguments: arguments, in: bottle)
    }

    // MARK: - Steam on Draconis Wine
    //
    // Outside CrossOver, Steam's Chromium UI (steamwebhelper) draws nothing:
    // its GPU path fails under Wine on macOS. The fix from notpop/steam-on-m1-wine
    // (MIT): run it single-process without the GPU through a small wrapper
    // (Tools/steamwebhelper-wrapper), and stop Steam restoring its own binary.

    static let wineArguments = ["-no-cef-sandbox", "-cef-single-process", "-noverifyfiles"]

    private var webHelperWatch: Task<Void, Never>?

    static var bundledWrapper: URL? {
        Bundle.main.url(forResource: "steamwebhelper", withExtension: "exe")
    }

    /// Put the wrapper in front of every `steamwebhelper.exe`; Valve's binary
    /// moves to `steamwebhelper_real.exe`. Returns true when anything changed.
    @discardableResult
    static func installWebHelperWrapper(steamRoot: URL) -> Bool {
        guard let wrapper = bundledWrapper, let wrapperData = try? Data(contentsOf: wrapper) else { return false }
        let fm = FileManager.default
        let cefRoot = steamRoot.appendingPathComponent("bin/cef", isDirectory: true)
        guard let dirs = try? fm.contentsOfDirectory(at: cefRoot, includingPropertiesForKeys: nil) else { return false }
        var changed = false
        for dir in dirs where dir.lastPathComponent.hasPrefix("cef.win") {
            let target = dir.appendingPathComponent("steamwebhelper.exe")
            let real = dir.appendingPathComponent("steamwebhelper_real.exe")
            let size = (try? fm.attributesOfItem(atPath: target.path))?[.size] as? Int
            if size == wrapperData.count, (try? Data(contentsOf: target)) == wrapperData { continue }
            do {
                // Valve's helper is tens of MB; anything small is an older wrapper.
                if let size, size > 1_000_000 {
                    try? fm.removeItem(at: real)
                    try fm.moveItem(at: target, to: real)
                }
                guard fm.fileExists(atPath: real.path) else { continue }
                try? fm.removeItem(at: target)
                try fm.copyItem(at: wrapper, to: target)
                changed = true
                Log.ok("steam", "Installed the steamwebhelper wrapper in \(dir.lastPathComponent)")
            } catch {
                Log.error("steam", "Couldn't install the steamwebhelper wrapper: \(error.localizedDescription)")
            }
        }
        return changed
    }

    /// Chromium locks left by a crashed Steam make the next start windowless.
    static func purgeBrowserLocks(in bottle: WineBottle) {
        let fm = FileManager.default
        let users = PathResolver.driveC(in: bottle.prefixURL).appendingPathComponent("users")
        for user in (try? fm.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? [] {
            let cache = user.appendingPathComponent("AppData/Local/Steam/htmlcache")
            guard let files = fm.enumerator(at: cache, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in files where file.lastPathComponent.hasPrefix("Singleton") {
                try? fm.removeItem(at: file)
            }
        }
    }

    /// Steam downloads its browser on first start, after the wrapper step ran.
    /// Install the wrapper once it lands and restart Steam so it takes effect.
    private func watchWebHelper(steam: String, steamRoot: URL, arguments: [String], in bottle: WineBottle) {
        guard Self.bundledWrapper != nil else { return }
        webHelperWatch?.cancel()
        webHelperWatch = Task {
            for _ in 0..<80 {
                try? await Task.sleep(for: .seconds(15))
                if Task.isCancelled { return }
                guard Self.installWebHelperWrapper(steamRoot: steamRoot) else { continue }
                Log.info("steam", "Restarting Steam so its window can draw")
                _ = try? await WineBackendManager.shared.launchAndWait(
                    executable: steam, arguments: ["-shutdown"], in: bottle,
                    wineEnvironment: WineEngine.steamEnvironment)
                try? await Task.sleep(for: .seconds(10))
                _ = try? await WineBackendManager.shared.spawn(
                    executable: steam, arguments: Self.wineArguments + arguments, in: bottle,
                wineEnvironment: WineEngine.steamEnvironment)
                return
            }
        }
    }
}
