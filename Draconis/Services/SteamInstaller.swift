import Foundation

/// When a bottle has no Steam install, Draconis can pull the official Steam
/// setup .exe down from Valve's CDN and run it under the backend's own runtime.
///
/// We delegate to the backend driver's `launch()` rather than calling wine
/// directly, so this works the same way for CrossOver / Whisky / Kegworks /
/// Sikarugir / GPTK.
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
        let driveC = PathResolver.driveC(in: bottle.prefixURL)
        return FileManager.default.fileExists(
            atPath: driveC
                .appendingPathComponent("Program Files (x86)/Steam/steam.exe")
                .path
        )
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

    /// Run SteamSetup.exe inside the bottle via the backend's own runtime.
    public func install(into bottle: WineBottle, silent: Bool = true) async throws {
        let installer = try await ensureInstallerDownloaded()

        guard let driver = await WineBackendManager.shared.driver(for: bottle.backend) else {
            throw InstallError.launchFailed("No driver for \(bottle.backend.displayName)")
        }
        let args = silent ? ["/S"] : []
        do {
            let proc = try await driver.launch(
                executable: installer.path,
                arguments: args,
                in: bottle,
                workingDirectory: nil
            )
            proc.waitUntilExit()
            if proc.terminationStatus != 0 {
                throw InstallError.launchFailed("exit code \(proc.terminationStatus)")
            }
            Log.ok("steam.install", "Steam installed in “\(bottle.name)”")
        } catch {
            Log.error("steam.install", "\(error)")
            throw InstallError.launchFailed(error.localizedDescription)
        }
    }
}
