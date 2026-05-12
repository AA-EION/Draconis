import Foundation

/// Discovers CrossOver and its bottles.
public actor CrossOverDetector {
    public static let shared = CrossOverDetector()

    /// True if CrossOver.app is present in /Applications.
    public func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: PathResolver.crossOverApp.path)
    }

    /// CrossOver's bundled wine64 binary.
    /// Path is stable: CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine64
    public func wineBinary() -> URL? {
        let url = PathResolver.crossOverApp.appendingPathComponent(
            "Contents/SharedSupport/CrossOver/bin/wine64"
        )
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

            // A CrossOver bottle root contains a `cxbottle.conf` and a
            // `drive_c` directory.
            let driveC = url.appendingPathComponent("drive_c")
            guard fm.fileExists(atPath: driveC.path) else { return nil }

            let northstar = locateNorthstar(in: driveC)
            let titanfall = locateTitanfall2(in: driveC)

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

    /// Convenience: bottles that already have Northstar installed.
    public func northstarReadyBottles() -> [WineBottle] {
        bottles().filter(\.hasNorthstar)
    }

    // MARK: - Heuristics
    //
    // These are pure FileManager reads with no shared state; marking them
    // `nonisolated` lets other drivers call them without `await`.

    /// Walk `drive_c` looking for a Titanfall2.exe. We check Steam's default
    /// install path first, then a few common alternatives, then fall back to
    /// a shallow search.
    nonisolated func locateTitanfall2(in driveC: URL) -> URL? {
        let candidates = [
            "Program Files (x86)/Origin Games/Titanfall2",
            "Program Files (x86)/Steam/steamapps/common/Titanfall2",
            "Program Files/EA Games/Titanfall2",
            "Games/Titanfall2",
            "Titanfall2",
        ]
        let fm = FileManager.default
        for sub in candidates {
            let root = driveC.appendingPathComponent(sub)
            let exe  = root.appendingPathComponent("Titanfall2.exe")
            if fm.fileExists(atPath: exe.path) { return root }
        }
        return nil
    }

    /// Northstar is present when NorthstarLauncher.exe sits next to Titanfall2.exe.
    nonisolated func locateNorthstar(in driveC: URL) -> URL? {
        guard let tf2 = locateTitanfall2(in: driveC) else { return nil }
        let launcher = tf2.appendingPathComponent("NorthstarLauncher.exe")
        return FileManager.default.fileExists(atPath: launcher.path) ? launcher : nil
    }
}
