import Foundation

/// Discovers CrossOver and its bottles, and provides cross-backend helpers for
/// locating Titanfall 2 inside any wine prefix (the layout of `drive_c` is
/// identical regardless of which wine flavour put it there).
public actor CrossOverDetector {
    public static let shared = CrossOverDetector()

    /// True if CrossOver.app is present in /Applications.
    public func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: PathResolver.crossOverApp.path)
    }

    /// CrossOver's wine wrapper script. We prefer the `wine` shell wrapper over
    /// `wine64` because the wrapper is the only binary that understands CrossOver's
    /// `--bottle` flag (it sets WINEPREFIX, loads per-bottle DXVK/MoltenVK config,
    /// then delegates to wine64 internally). Calling wine64 directly with that
    /// flag silently ignores it, leaving the bottle uninitialised.
    public func wineBinary() -> URL? {
        let candidates = [
            "Contents/SharedSupport/CrossOver/bin/wine",
            "Contents/SharedSupport/CrossOver/bin/wine64",
        ]
        for sub in candidates {
            let url = PathResolver.crossOverApp.appendingPathComponent(sub)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// CrossOver's `cxstart` CLI. This is the supported way to run an arbitrary
    /// executable inside a bottle: it accepts a POSIX path, sets up the bottle
    /// environment, and (with `--wait`) blocks until the wine process exits so
    /// `terminationStatus` reflects the real app exit code.
    public func cxstartBinary() -> URL? {
        let url = PathResolver.crossOverApp
            .appendingPathComponent("Contents/SharedSupport/CrossOver/bin/cxstart")
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

            return WineBottle(
                id: "crossover:" + url.lastPathComponent,
                name: url.lastPathComponent,
                backend: .crossover,
                prefixURL: url,
                wineBinaryURL: wineBinary(),
                hasNorthstar: northstar != nil,
                hasTitanfall2: titanfall != nil,
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
