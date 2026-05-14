import Foundation

/// Launches Titanfall 2 (vanilla or via Northstar) inside a given bottle by
/// delegating to the backend's own runtime — we never invoke `wine` directly.
public actor NorthstarLauncher {
    public static let shared = NorthstarLauncher()

    public enum LaunchMode: String, Sendable, CaseIterable, Identifiable {
        case northstar
        case vanilla
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .northstar: return "Northstar"
            case .vanilla:   return "Titanfall 2 (vanilla)"
            }
        }
    }

    public enum LaunchError: Error, LocalizedError {
        case titanfallNotFound
        case northstarNotFound
        case noDriverForBackend(WineBackend)

        public var errorDescription: String? {
            switch self {
            case .titanfallNotFound:         return "Titanfall 2 wasn't found in this bottle."
            case .northstarNotFound:         return "NorthstarLauncher.exe wasn't found in this bottle."
            case .noDriverForBackend(let b): return "No driver registered for \(b.displayName)."
            }
        }
    }

    @discardableResult
    public func launch(
        bottle: WineBottle,
        mode: LaunchMode,
        extraArgs: [String] = []
    ) async throws -> Process {
        Log.info(
            "northstar.launch",
            "Asked to launch \(mode.label) in “\(bottle.name)” [\(bottle.backend.rawValue)]"
        )

        // Resolve install path (might have been picked up since we last
        // scanned — re-resolve so the user doesn't have to rescan).
        guard let tf2Root = bottle.titanfall2InstallPath
            ?? CrossOverDetector.locateTitanfall2(
                in: PathResolver.driveC(in: bottle.prefixURL)
            )?.path
        else {
            Log.error("northstar.launch", "Titanfall 2 root not found in prefix")
            throw LaunchError.titanfallNotFound
        }
        // Both modes go through NorthstarLauncher.exe — vanilla just adds
        // `-vanilla`, which boots the unmodded game while still using
        // Northstar's auth bypass. Launching Titanfall2.exe directly fails
        // silently on CrossOver bottles (it spawns wine processes but the
        // game exits because real EA/Origin auth is missing), so we never
        // invoke it. UI must gate the launch button on hasNorthstar.
        let exePath = (tf2Root as NSString).appendingPathComponent("NorthstarLauncher.exe")
        guard FileManager.default.fileExists(atPath: exePath) else {
            Log.error("northstar.launch", "NorthstarLauncher.exe missing at \(exePath)")
            throw LaunchError.northstarNotFound
        }

        guard let driver = await WineBackendManager.shared.driver(for: bottle.backend) else {
            throw LaunchError.noDriverForBackend(bottle.backend)
        }

        var args: [String] = ["-novid"]
        if mode == .vanilla { args.append("-vanilla") }
        args.append(contentsOf: extraArgs)

        Log.info("northstar.launch", "Handing off to \(bottle.backend.displayName) driver…")
        return try await driver.launch(
            executable: exePath,
            arguments: args,
            in: bottle,
            workingDirectory: tf2Root,
            wait: false
        )
    }
}
