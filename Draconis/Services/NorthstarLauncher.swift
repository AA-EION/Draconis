import Foundation

/// Launches Titanfall 2 inside a bottle. The launch path is different for
/// each mode because each game binary handles DRM differently:
///
/// **Vanilla** — run `Titanfall2.exe` directly.
///   The base binary contains the Steam DRM stub: if Steam isn't running it
///   self-relaunches via `steam://run/1237970`. If the copy is EA-owned,
///   the same binary triggers `link2ea://` for EA auth, which the bottle's
///   maxima-bootstrap handler intercepts. Either way DRM bootstraps itself —
///   we don't need to know which store the user has.
///
/// **Northstar** — run `steam.exe -applaunch 1237970 -northstar`.
///   NorthstarLauncher.exe hard-codes starting Origin via a Win32 path (not
///   `origin2://`), so it hangs forever on "Waiting for Origin..." when
///   Origin isn't installed (which is always, on macOS / Wine). The
///   supported Northstar entry point is Steam launch options: Steam runs
///   Titanfall2.exe with `-northstar`, Northstar's hooks load.
///   Northstar + EA-only setup is currently unsupported here.
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
        case noDriverForBackend(WineBackend)

        public var errorDescription: String? {
            switch self {
            case .titanfallNotFound:
                return "Titanfall 2 wasn't found in this bottle."
            case .northstarNotFound:
                return "NorthstarLauncher.exe wasn't found in this bottle. " +
                       "Install Northstar before launching in Northstar mode."
            case .steamNotFoundForNorthstar:
                return "Northstar mode launches through Steam launch options " +
                       "(-northstar). Install Steam in this bottle first, or " +
                       "use Vanilla mode."
            case .noDriverForBackend(let b):
                return "No driver registered for \(b.displayName)."
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

        guard let driver = await WineBackendManager.shared.driver(for: bottle.backend) else {
            throw LaunchError.noDriverForBackend(bottle.backend)
        }

        switch mode {
        case .vanilla:
            return try await launchVanilla(
                driver: driver, bottle: bottle, tf2Root: tf2Root, extraArgs: extraArgs
            )
        case .northstar:
            return try await launchNorthstar(
                driver: driver, bottle: bottle, tf2Root: tf2Root, extraArgs: extraArgs
            )
        }
    }

    private func launchVanilla(
        driver: WineBackendDriver,
        bottle: WineBottle,
        tf2Root: String,
        extraArgs: [String]
    ) async throws -> Process {
        let exe = (tf2Root as NSString).appendingPathComponent("Titanfall2.exe")
        guard FileManager.default.fileExists(atPath: exe) else {
            Log.error("northstar.launch", "Titanfall2.exe missing at \(exe)")
            throw LaunchError.titanfallNotFound
        }
        let args = ["-novid"] + extraArgs
        Log.info("northstar.launch", "Titanfall2.exe \(args.joined(separator: " "))")
        return try await driver.launch(
            executable: exe,
            arguments: args,
            in: bottle,
            workingDirectory: tf2Root,
            wait: false
        )
    }

    private func launchNorthstar(
        driver: WineBackendDriver,
        bottle: WineBottle,
        tf2Root: String,
        extraArgs: [String]
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
        // Steam launches Titanfall2.exe with -northstar, Northstar's wsock32
        // proxy hooks load, mod loader runs. Setup is identical to the Steam
        // launch option `-northstar` that Northstar's wiki documents.
        let args = ["-applaunch", tf2SteamAppID, "-novid", "-northstar"] + extraArgs
        Log.info("northstar.launch", "steam.exe \(args.joined(separator: " "))")
        return try await driver.launch(
            executable: steamExe,
            arguments: args,
            in: bottle,
            workingDirectory: nil,
            wait: false
        )
    }
}
