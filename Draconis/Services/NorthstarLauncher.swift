import Foundation

/// Launches Titanfall 2 (vanilla or via Northstar) inside a given bottle.
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
        case bottleMissingWine
        case titanfallNotFound
        case northstarNotFound
        case launchFailed(String)

        public var errorDescription: String? {
            switch self {
            case .bottleMissingWine:  return "This bottle has no usable wine binary."
            case .titanfallNotFound:  return "Titanfall 2 wasn't found in this bottle."
            case .northstarNotFound:  return "NorthstarLauncher.exe wasn't found in this bottle."
            case .launchFailed(let s): return "Launch failed: \(s)"
            }
        }
    }

    @discardableResult
    public func launch(
        bottle: WineBottle,
        mode: LaunchMode,
        extraArgs: [String] = []
    ) async throws -> Process {
        // Resolve the wine binary
        guard let wine = await resolveWine(for: bottle) else {
            throw LaunchError.bottleMissingWine
        }

        // Resolve the executable inside the prefix
        guard let tf2Path = bottle.titanfall2InstallPath else {
            throw LaunchError.titanfallNotFound
        }
        let exeName: String
        switch mode {
        case .northstar: exeName = "NorthstarLauncher.exe"
        case .vanilla:   exeName = "Titanfall2.exe"
        }
        let exePath = (tf2Path as NSString).appendingPathComponent(exeName)
        guard FileManager.default.fileExists(atPath: exePath) else {
            throw mode == .northstar
                ? LaunchError.northstarNotFound
                : LaunchError.titanfallNotFound
        }

        var args = [exePath]
        if mode == .northstar {
            // Northstar respects standard Source engine args
            args.append("-novid")
        }
        args.append(contentsOf: extraArgs)

        do {
            return try ProcessRunner.shared.detached(
                wine, arguments: args,
                environment: launchEnvironment(for: bottle),
                currentDirectory: URL(fileURLWithPath: tf2Path)
            )
        } catch {
            throw LaunchError.launchFailed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    func resolveWine(for bottle: WineBottle) async -> URL? {
        if let explicit = bottle.wineBinaryURL,
           FileManager.default.fileExists(atPath: explicit.path) {
            return explicit
        }
        // Fall back to the backend's default wine.
        return await WineBackendManager.shared
            .driver(for: bottle.backend)?
            .wineBinary()
    }

    func launchEnvironment(for bottle: WineBottle) -> [String: String] {
        var env: [String: String] = [
            "WINEPREFIX": bottle.prefixURL.path,
            "WINEDEBUG":  "-all",
        ]
        // GPTK requires MTL_HUD_ENABLED + DXMT/DXVK toggles; Apple's wrapper
        // also sets MTL_CAPTURE_ENABLED. We leave most knobs to the backend
        // and only inject what's universally safe.
        if bottle.backend == .gptk {
            env["MTL_HUD_ENABLED"] = "0"
            // Apple's wine64 sometimes needs ROSETTA_ADVERTISE_AVX=1
            env["ROSETTA_ADVERTISE_AVX"] = "1"
        }
        return env
    }
}
