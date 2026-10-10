import Foundation

/// Downloads and runs EA Desktop's installer inside a bottle. Modelled on
/// `SteamInstaller` so the wizard can treat the EA path uniformly: pick
/// the frontend, install it into the bottle, hand off to the user to
/// install the game through the launcher.
///
/// When TF2 is purchased on EA (as opposed to bought-on-Steam-and-linked),
/// EA Desktop is the simplest auth backbone — it handles `link2ea://`
/// natively, no Maxima needed.
public actor EAInstaller {
    public static let shared = EAInstaller()

    /// EA Desktop installer (the "EA app"). The download URL is publicly
    /// hosted by EA; the binary itself bootstraps the rest of the app
    /// from EA's CDN on first run.
    private let setupURL = URL(
        string: "https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer-releases/EAappInstaller.exe"
    )!

    public enum InstallError: Error, LocalizedError {
        case downloadFailed
        case launchFailed(String)

        public var errorDescription: String? {
            switch self {
            case .downloadFailed:
                return "Couldn't download EAappInstaller.exe."
            case .launchFailed(let s):
                return "EA Desktop installer failed: \(s)"
            }
        }
    }

    /// True if EA Desktop / EA app is installed in this bottle.
    public func isEAInstalled(in bottle: WineBottle) -> Bool {
        eaExePath(in: bottle) != nil
    }

    /// POSIX path to EA Desktop's main binary inside the bottle, or nil
    /// if not installed. Checks both the modern "EA Desktop" install
    /// layout and the legacy "EA app" / Origin paths so a user who
    /// already installed via Origin gets detected too.
    public func eaExePath(in bottle: WineBottle) -> String? {
        Self.eaExePath(in: bottle.prefixURL)
    }

    /// Free-function variant so bottle scanners can detect EA Desktop
    /// without awaiting the actor.
    public static func eaExePath(in prefixURL: URL) -> String? {
        let driveC = PathResolver.driveC(in: prefixURL)
        let candidates = [
            // EA Desktop (current)
            "Program Files/Electronic Arts/EA Desktop/EA Desktop/EADesktop.exe",
            "Program Files (x86)/Electronic Arts/EA Desktop/EA Desktop/EADesktop.exe",
            // Legacy EA app / Origin fallbacks
            "Program Files (x86)/Origin/Origin.exe",
            "Program Files/Origin/Origin.exe",
        ]
        for rel in candidates {
            let url = driveC.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: url.path) {
                return url.path
            }
        }
        return nil
    }

    public func ensureInstallerDownloaded() async throws -> URL {
        let dest = PathResolver.downloadsCache.appendingPathComponent("EAappInstaller.exe")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        Log.info("ea.install", "Downloading EAappInstaller.exe…")
        do {
            let (tmp, response) = try await URLSession.shared.download(from: setupURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw InstallError.downloadFailed
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            Log.ok("ea.install", "EAappInstaller.exe ready at \(dest.path)")
            return dest
        } catch {
            Log.error("ea.install", "\(error)")
            throw InstallError.downloadFailed
        }
    }

    /// Run EAappInstaller.exe inside the bottle. EA's installer doesn't
    /// have a universally-supported silent flag — different bundle
    /// versions accept `/S`, `--silent`, or nothing — so by default we
    /// run it interactively and let the user click through. Pass
    /// `silent: true` to attempt `/S` if you know the bundle accepts it.
    public func install(into bottle: WineBottle, silent: Bool = false) async throws {
        let installer = try await ensureInstallerDownloaded()

        // The arguments Steam's and Heroic's EA app installs pass.
        let args = silent ? ["EAX_LAUNCH_CLIENT=0", "IGNORE_INSTALLED=1"] : []
        do {
            let status = try await WineBackendManager.shared.launchAndWait(
                executable: installer.path,
                arguments: args,
                in: bottle,
                workingDirectory: nil
            )
            if status != 0 {
                throw InstallError.launchFailed("exit code \(status)")
            }
            Log.ok("ea.install", "EA Desktop installed in “\(bottle.name)”")
        } catch {
            Log.error("ea.install", "\(error)")
            throw InstallError.launchFailed(error.localizedDescription)
        }
    }

    /// EA's local service (LSX) that Titanfall 2 and Northstar talk to.
    public static let lsxPort: UInt16 = 3216

    public nonisolated static func isLSXListening() -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = lsxPort.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    /// Start the EA app in the bottle unless its LSX service is already up, and
    /// wait for it. `-noOriginStartup` means Northstar won't start it itself,
    /// yet still needs a signed-in EA app to authenticate.
    public func startIfNeeded(in bottle: WineBottle, timeout: Duration = .seconds(120)) async throws {
        if Self.isLSXListening() { return }
        guard let exe = CrossOverDetector.locateEAApp(in: PathResolver.driveC(in: bottle.prefixURL)) else {
            throw InstallError.launchFailed("The EA app isn't installed in “\(bottle.name)”")
        }
        Log.info("ea.app", "Starting the EA app…")
        try await WineBackendManager.shared.spawn(
            executable: exe.path, in: bottle, wineEnvironment: WineEngine.eaAppEnvironment)
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if Self.isLSXListening() {
                Log.ok("ea.app", "EA app is running")
                return
            }
            try await Task.sleep(for: .seconds(2))
        }
        throw InstallError.launchFailed("The EA app didn't come up. Open it, sign in, then launch again.")
    }
}
