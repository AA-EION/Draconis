import Foundation

/// Discovers CrossOver and its bottles, and provides cross-backend helpers for
/// locating Titanfall 2 inside any wine prefix (the layout of `drive_c` is
/// identical regardless of which wine flavour put it there).
public actor CrossOverDetector {
    public static let shared = CrossOverDetector()

    /// True if CrossOver.app exists at the location LaunchServices resolves
    /// (with a fallback check at the default /Applications path).
    public func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: PathResolver.crossOverApp.path)
    }

    /// CrossOver's `cxstart` CLI — the supported way to run an arbitrary
    /// executable inside a bottle. Accepts POSIX paths, sets up the bottle
    /// environment, and (with `--wait`) blocks until the wine process exits
    /// so `terminationStatus` reflects the real app exit code.
    public func cxstartBinary() -> URL? {
        let url = PathResolver.crossOverApp
            .appendingPathComponent("Contents/SharedSupport/CrossOver/bin/cxstart")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// `wineserver` from CrossOver's bundled wine. Used to kill all wine
    /// processes attached to a given prefix (`wineserver -k` with
    /// `WINEPREFIX=...`).
    public func wineserverBinary() -> URL? {
        let url = PathResolver.crossOverApp
            .appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wineserver")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Enumerate bottles in ~/Library/Application Support/CrossOver/Bottles.
    public func bottles() -> [WineBottle] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: PathResolver.crossOverBottlesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { url -> WineBottle? in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue,
                  fm.fileExists(atPath: PathResolver.driveC(in: url).path)
            else { return nil }
            return Self.scanBottle(
                id: "crossover:" + url.lastPathComponent,
                name: url.lastPathComponent,
                backend: .crossover,
                prefixURL: url
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// What's installed in a prefix, whichever backend owns it.
    public nonisolated static func scanBottle(
        id: String, name: String, backend: WineBackend, prefixURL url: URL
    ) -> WineBottle {
        let driveC = PathResolver.driveC(in: url)
        let titanfall = locateTitanfall2(in: driveC)
        let northstar = locateNorthstar(in: driveC)
        return WineBottle(
            id: id,
            name: name,
            backend: backend,
            prefixURL: url,
            hasNorthstar: northstar != nil,
            hasTitanfall2: titanfall != nil,
            hasSteam: SteamInstaller.steamExePath(in: url) != nil,
            hasEAApp: locateEAApp(in: driveC) != nil,
            hasEpicGames: locateEpicGames(in: driveC) != nil,
            hasMaxima: locateMaximaCli(in: driveC) != nil,
            northstarVersion: titanfall.flatMap { GameFiles.northstarVersion(in: $0) },
            titanfall2InstallPath: titanfall?.path
        )
    }

    // MARK: - Cross-backend heuristics (nonisolated, pure FileManager reads)

    public nonisolated static func locateTitanfall2(in driveC: URL) -> URL? {
        GameFiles.locateTitanfall2(under: driveC)
    }

    public nonisolated static func locateNorthstar(in driveC: URL) -> URL? {
        guard let tf2 = locateTitanfall2(in: driveC), GameFiles.hasNorthstar(in: tf2) else { return nil }
        return tf2.appendingPathComponent("NorthstarLauncher.exe")
    }

    /// EA App / EA Desktop inside the bottle. Checks both 32-bit and 64-bit Program Files.
    public nonisolated static func locateEAApp(in driveC: URL) -> URL? {
        let candidates = [
            "Program Files/Electronic Arts/EA Desktop/EA Desktop.exe",
            "Program Files (x86)/Electronic Arts/EA Desktop/EA Desktop.exe",
            "Program Files/EA/EA Desktop/EA Desktop.exe",
            "Program Files (x86)/EA/EA Desktop/EA Desktop.exe",
        ]
        let fm = FileManager.default
        for path in candidates {
            let url = driveC.appendingPathComponent(path)
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// Epic Games Launcher inside the bottle.
    public nonisolated static func locateEpicGames(in driveC: URL) -> URL? {
        let candidates = [
            "Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win32/EpicGamesLauncher.exe",
            "Program Files/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe",
        ]
        let fm = FileManager.default
        for path in candidates {
            let url = driveC.appendingPathComponent(path)
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// `maxima-cli.exe` inside the bottle. The installer drops it under
    /// `C:\Program Files\Maxima\` on Wine — note `Program Files`, not
    /// `Program Files (x86)`, because the installer is built as the
    /// shared (non-x86) variant for win10_64 prefixes.
    public nonisolated static func locateMaximaCli(in driveC: URL) -> URL? {
        let candidates = [
            "Program Files/Maxima/maxima-cli.exe",
            "Program Files (x86)/Maxima/maxima-cli.exe",
        ]
        let fm = FileManager.default
        for path in candidates {
            let url = driveC.appendingPathComponent(path)
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}
