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
                  isDir.boolValue else { return nil }

            // A CrossOver bottle root contains `cxbottle.conf` and `drive_c`.
            let driveC = url.appendingPathComponent("drive_c")
            guard fm.fileExists(atPath: driveC.path) else { return nil }

            let titanfall = Self.locateTitanfall2(in: driveC)
            let northstar = Self.locateNorthstar(in: driveC)
            let nsVersion = titanfall.flatMap { Self.readNorthstarVersion(in: $0) }

            return WineBottle(
                id: "crossover:" + url.lastPathComponent,
                name: url.lastPathComponent,
                prefixURL: url,
                hasNorthstar: northstar != nil,
                hasTitanfall2: titanfall != nil,
                hasSteam: SteamInstaller.steamExePath(in: url) != nil,
                hasEAApp: Self.locateEAApp(in: driveC) != nil,
                hasEpicGames: Self.locateEpicGames(in: driveC) != nil,
                hasMaxima: Self.locateMaximaCli(in: driveC) != nil,
                northstarVersion: nsVersion,
                titanfall2InstallPath: titanfall?.path
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Cross-backend heuristics (nonisolated, pure FileManager reads)

    /// Walks `drive_c` looking for Titanfall2.exe. Tries the well-known install
    /// roots first; if nothing matches it does a depth-limited recursive sweep
    /// so unusual installs (custom folder names, EA App's new layout) still get
    /// detected.
    public nonisolated static func locateTitanfall2(in driveC: URL) -> URL? {
        let knownRoots = [
            "Program Files (x86)/Origin Games/Titanfall2",
            "Program Files (x86)/Steam/steamapps/common/Titanfall2",
            "Program Files (x86)/EA Games/Titanfall2",
            "Program Files/Origin Games/Titanfall2",
            "Program Files/EA Games/Titanfall2",
            "Program Files/Titanfall2",
            "Games/Titanfall2",
            "Titanfall2",
        ]
        let fm = FileManager.default
        for sub in knownRoots {
            let root = driveC.appendingPathComponent(sub)
            let exe  = root.appendingPathComponent("Titanfall2.exe")
            if fm.fileExists(atPath: exe.path) { return root }
        }

        return recursiveSearch(
            for: "Titanfall2.exe",
            startingAt: driveC,
            maxDepth: 5
        )?.deletingLastPathComponent()
    }

    /// Northstar is present when NorthstarLauncher.exe sits next to Titanfall2.exe.
    public nonisolated static func locateNorthstar(in driveC: URL) -> URL? {
        guard let tf2 = locateTitanfall2(in: driveC) else { return nil }
        let launcher = tf2.appendingPathComponent("NorthstarLauncher.exe")
        return FileManager.default.fileExists(atPath: launcher.path) ? launcher : nil
    }

    /// Reads the installed Northstar version from ns_version.txt written by the installer.
    /// Returns a tag string like "v1.28.0", or nil if the file is absent or unreadable.
    public nonisolated static func readNorthstarVersion(in tf2Root: URL) -> String? {
        let versionFile = tf2Root.appendingPathComponent("ns_version.txt")
        guard let raw = try? String(contentsOf: versionFile, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    /// Depth-limited recursive search using FileManager.enumerator with a cap
    /// so even a pathological prefix returns within a couple of seconds.
    private nonisolated static func recursiveSearch(
        for filename: String,
        startingAt root: URL,
        maxDepth: Int,
        nodeCap: Int = 50_000
    ) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var visited = 0
        let rootDepth = root.pathComponents.count

        for case let url as URL in enumerator {
            visited += 1
            if visited > nodeCap { return nil }

            let depth = url.pathComponents.count - rootDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if url.lastPathComponent == filename {
                return url
            }
        }
        return nil
    }
}
