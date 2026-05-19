import Foundation

/// Launches Titanfall 2 inside a bottle. The launch path is different for
/// each mode because each game binary handles DRM differently:
///
/// **Vanilla** — run `NorthstarLauncher.exe -vanilla` (when Northstar is installed),
///   or `Titanfall2.exe` as a fallback. NorthstarLauncher.exe -vanilla launches
///   vanilla TF2 cleanly without loading Northstar mods, and avoids auth issues
///   that arise when Maxima or the EA launcher isn't running.
///
/// **Northstar** — run `steam.exe -applaunch 1237970 -northstar -noOriginStartup -multiple`.
///   NorthstarLauncher.exe hard-codes starting Origin via a Win32 path (not
///   `origin2://`), so it hangs forever on "Waiting for Origin..." when
///   Origin isn't installed (which is always, on macOS / Wine). The
///   supported Northstar entry point is Steam launch options: Steam runs
///   Titanfall2.exe with `-northstar`, Northstar's hooks load.
///   `-noOriginStartup -multiple` are required when using Maxima — without
///   them Northstar tries to start Origin, which hangs in Wine.
///   See: https://github.com/AA-EION/Maxima-Draconis#northstar-online-play
public actor NorthstarLauncher {
    public static let shared = NorthstarLauncher()

    // Steam App ID for Titanfall 2.
    private let tf2SteamAppID = "1237970"

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
        case steamNotFoundForNorthstar

        public var errorDescription: String? {
            switch self {
            case .titanfallNotFound:
                return "Titanfall 2 wasn't found in this bottle."
            case .northstarNotFound:
                return "NorthstarLauncher.exe wasn't found in this bottle. " +
                       "Install Northstar before launching in Northstar mode."
            case .steamNotFoundForNorthstar:
                return "Northstar mode launches through Steam launch options " +
                       "(-northstar -noOriginStartup -multiple). " +
                       "Install Steam in this bottle first, or use Vanilla mode."
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
            "Asked to launch \(mode.label) in '\(bottle.name)' [\(bottle.backend.rawValue)]"
        )

        guard let tf2Root = bottle.titanfall2InstallPath
            ?? CrossOverDetector.locateTitanfall2(
                in: PathResolver.driveC(in: bottle.prefixURL)
            )?.path
        else {
            Log.error("northstar.launch", "Titanfall 2 root not found in prefix")
            throw LaunchError.titanfallNotFound
        }

        // Prefer maxima-cli when Maxima is installed in the bottle —
        // it handles EA auth itself and bypasses the Steam-applaunch /
        // Origin-DRM-hang dance Wine struggles with. Falls back to the
        // direct exe paths below when Maxima isn't there (EA-only and
        // pure-Steam setups still work via the existing flow).
        if bottle.hasMaxima {
            Log.info("northstar.launch", "Maxima present in bottle, routing through maxima-cli")
            return try await MaximaService.shared.launchGame(
                in: bottle,
                northstar: mode == .northstar
            )
        }

        switch mode {
        case .vanilla:
            return try await launchVanilla(
                bottle: bottle, tf2Root: tf2Root, extraArgs: extraArgs
            )
        case .northstar:
            return try await launchNorthstar(
                bottle: bottle, tf2Root: tf2Root, extraArgs: extraArgs
            )
        }
    }

    private func launchVanilla(
        bottle: WineBottle, tf2Root: String, extraArgs: [String]
    ) async throws -> Process {
        // Prefer NorthstarLauncher.exe -vanilla: avoids auth issues when
        // Maxima/EA launcher isn't running, and cleanly loads without mods.
        let nsExe = (tf2Root as NSString).appendingPathComponent("NorthstarLauncher.exe")
        if FileManager.default.fileExists(atPath: nsExe) {
            let args = ["-vanilla", "-novid"] + extraArgs
            Log.info("northstar.launch", "NorthstarLauncher.exe -vanilla \(args.joined(separator: " "))")
            return try await WineBackendManager.shared.launch(
                executable: nsExe,
                arguments: args,
                in: bottle,
                workingDirectory: tf2Root,
                wait: false
            )
        }

        // Fallback: run Titanfall2.exe directly when Northstar isn't installed.
        let exe = (tf2Root as NSString).appendingPathComponent("Titanfall2.exe")
        guard FileManager.default.fileExists(atPath: exe) else {
            Log.error("northstar.launch", "Titanfall2.exe missing at \(exe)")
            throw LaunchError.titanfallNotFound
        }
        let args = ["-novid"] + extraArgs
        Log.info("northstar.launch", "Titanfall2.exe \(args.joined(separator: " "))")
        return try await WineBackendManager.shared.launch(
            executable: exe,
            arguments: args,
            in: bottle,
            workingDirectory: tf2Root,
            wait: false
        )
    }

    private func launchNorthstar(
        bottle: WineBottle, tf2Root: String, extraArgs: [String]
    ) async throws -> Process {
        let nsExe = (tf2Root as NSString).appendingPathComponent("NorthstarLauncher.exe")
        guard FileManager.default.fileExists(atPath: nsExe) else {
            Log.error("northstar.launch", "NorthstarLauncher.exe missing at \(nsExe)")
            throw LaunchError.northstarNotFound
        }
        guard let steamExe = SteamInstaller.steamExePath(in: bottle.prefixURL) else {
            Log.error("northstar.launch", "steam.exe required for Northstar mode")
            throw LaunchError.steamNotFoundForNorthstar
        }
        // Required launch flags when using Maxima (per Maxima-Draconis README):
        //   -noOriginStartup  prevents Northstar from trying to start Origin
        //                     (which doesn't exist in Wine and would hang forever)
        //   -multiple         allows multiple game instances / avoids single-
        //                     instance lock that can conflict with Maxima
        //   -northstar        tells the game to load NorthstarLauncher hooks
        let args = ["-applaunch", tf2SteamAppID, "-noOriginStartup", "-multiple", "-northstar", "-novid"] + extraArgs
        Log.info("northstar.launch", "steam.exe \(args.joined(separator: " "))")
        return try await WineBackendManager.shared.launch(
            executable: steamExe,
            arguments: args,
            in: bottle,
            workingDirectory: nil,
            wait: false
        )
    }
}
