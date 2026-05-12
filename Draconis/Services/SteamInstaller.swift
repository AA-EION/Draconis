import Foundation

/// When a bottle has no Steam install, Draconis can pull the official Steam
/// setup .exe down from Valve's CDN and run it under wine inside the prefix.
///
/// We deliberately do NOT bundle a copy of SteamSetup.exe; we fetch it at
/// runtime from steamcdn-a.akamaihd.net so users always get the latest.
public actor SteamInstaller {
    public static let shared = SteamInstaller()

    private let setupURL = URL(
        string: "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"
    )!

    public enum InstallError: Error, LocalizedError {
        case bottleHasNoWine
        case downloadFailed
        case wineFailed(String)

        public var errorDescription: String? {
            switch self {
            case .bottleHasNoWine:    return "That bottle doesn't have a wine binary configured."
            case .downloadFailed:     return "Couldn't download SteamSetup.exe."
            case .wineFailed(let s):  return "Wine failed during Steam install: \(s)"
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

    /// Download Valve's installer to the cache (idempotent).
    public func ensureInstallerDownloaded() async throws -> URL {
        let dest = PathResolver.downloadsCache.appendingPathComponent("SteamSetup.exe")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        let (tmp, response) = try await URLSession.shared.download(from: setupURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw InstallError.downloadFailed
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    /// Run SteamSetup.exe inside the bottle's wine prefix. The Steam installer
    /// supports `/S` for silent install on Windows; under wine we still pass
    /// it but on some prefixes the user will see the wizard.
    public func install(into bottle: WineBottle, silent: Bool = true) async throws {
        guard let wine = await NorthstarLauncher.shared.resolveWine(for: bottle) else {
            throw InstallError.bottleHasNoWine
        }
        let installer = try await ensureInstallerDownloaded()

        var args = [installer.path]
        if silent { args.append("/S") }

        let result = try await ProcessRunner.shared.capture(
            wine, arguments: args,
            environment: [
                "WINEPREFIX": bottle.prefixURL.path,
                "WINEDEBUG": "-all",
            ]
        )
        if !result.ok {
            throw InstallError.wineFailed(result.stderr)
        }
    }
}
