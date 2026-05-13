import Foundation

/// Manages the Maxima EA launcher inside a Wine bottle and the MaximaHelper
/// macOS agent that bridges the qrc:// OAuth redirect from the host to Wine.
///
/// Architecture:
///   macOS host
///   ├── Draconis.app/Contents/Resources/MaximaHelper.app  ← bundled, registered once
///   └── CrossOver bottle
///       └── Program Files/Maxima/maxima-cli.exe           ← installed via MaximaSetup.exe
///
/// Wine uses the host's TCP stack so MaximaHelper can reach maxima-cli at
/// 127.0.0.1:31033 without any special routing.
public actor MaximaService {
    public static let shared = MaximaService()

    // Titanfall 2 Steam App ID — used with `maxima-cli launch`
    private let tf2SteamAppID = "1237970"

    // Possible install locations set by MaximaSetup.exe ($PROGRAMFILES64 or $PROGRAMFILES)
    private let possibleInstallDirs = [
        "Program Files/Maxima",
        "Program Files (x86)/Maxima",
    ]

    private let githubReleasesURL = URL(
        string: "https://api.github.com/repos/AA-EION/Maxima-Draconis/releases/latest"
    )!

    private let lsregister = URL(fileURLWithPath:
        "/System/Library/Frameworks/CoreServices.framework" +
        "/Versions/A/Frameworks/LaunchServices.framework" +
        "/Versions/A/Support/lsregister"
    )

    // MARK: - Progress

    public struct Progress: Sendable {
        public enum Phase: Sendable {
            case fetchingRelease, downloading, installing, registeringHelper, done
            var label: String {
                switch self {
                case .fetchingRelease:   return "FETCHING"
                case .downloading:       return "DOWNLOADING"
                case .installing:        return "INSTALLING"
                case .registeringHelper: return "REGISTERING"
                case .done:              return "DONE"
                }
            }
        }
        public var phase: Phase
        public var fraction: Double   // 0…1, negative = indeterminate
        public var detail: String
    }

    public typealias ProgressHandler = @Sendable (Progress) -> Void

    // MARK: - Errors

    public enum MaximaError: Error, LocalizedError {
        case notInstalled
        case helperNotBundled
        case noDriver
        case noInstallerAsset
        case installerDownloadFailed(String)
        case installerFailed(Int32)
        case badGitHubResponse(Int)

        public var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "Maxima is not installed in this bottle. Use 'Set up Maxima' first."
            case .helperNotBundled:
                return "MaximaHelper.app is missing from the Draconis bundle."
            case .noDriver:
                return "No Wine driver available for this bottle's backend."
            case .noInstallerAsset:
                return "MaximaSetup.exe was not found in the latest Maxima-Draconis release."
            case .installerDownloadFailed(let s):
                return "Installer download failed: \(s)"
            case .installerFailed(let code):
                return "Installer exited with code \(code). Check the bottle for errors."
            case .badGitHubResponse(let code):
                return "GitHub returned HTTP \(code) fetching the release."
            }
        }
    }

    // MARK: - Detection

    /// True if maxima-cli.exe is present in the bottle's expected install path.
    public func isInstalled(in bottle: WineBottle) -> Bool {
        maximaCliPath(in: bottle) != nil
    }

    /// POSIX path to maxima-cli.exe inside the bottle, or nil if not installed.
    public func maximaCliPath(in bottle: WineBottle) -> String? {
        let driveC = PathResolver.driveC(in: bottle.prefixURL)
        for dir in possibleInstallDirs {
            let url = driveC
                .appendingPathComponent(dir)
                .appendingPathComponent("maxima-cli.exe")
            if FileManager.default.fileExists(atPath: url.path) {
                return url.path
            }
        }
        return nil
    }

    // MARK: - MaximaHelper

    /// The MaximaHelper.app bundled inside Draconis.app/Contents/Resources.
    public var bundledHelperURL: URL? {
        Bundle.main.url(forResource: "MaximaHelper", withExtension: "app")
    }

    /// Registers MaximaHelper with macOS LaunchServices so it handles qrc:// URLs.
    ///
    /// Must be called once on first setup and again if Draconis.app is moved.
    /// MaximaHelper forwards qrc:// to http://127.0.0.1:31033 — the same
    /// loopback port that maxima-cli inside Wine listens on, since Wine shares
    /// the host's TCP stack.
    public func registerHelper() throws {
        guard let helperURL = bundledHelperURL else {
            throw MaximaError.helperNotBundled
        }
        let proc = Process()
        proc.executableURL = lsregister
        proc.arguments = ["-f", helperURL.path]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        Log.ok("maxima.helper", "Registered MaximaHelper at \(helperURL.path)")
    }

    /// True if MaximaHelper is currently the system handler for qrc://.
    ///
    /// Checks lsregister's dump for our bundle identifier. This is the most
    /// reliable way since NSWorkspace doesn't expose URL scheme handler queries.
    public func isHelperRegistered() async -> Bool {
        guard FileManager.default.fileExists(atPath: lsregister.path) else {
            return false
        }
        let proc = Process()
        let out = Pipe()
        proc.executableURL = lsregister
        proc.arguments = ["-dump"]
        proc.standardOutput = out
        proc.standardError = Pipe()
        try? proc.run()
        // Drain and wait off the actor thread to avoid blocking concurrency.
        return await Task.detached(priority: .utility) {
            proc.waitUntilExit()
            let raw = String(
                data: out.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            return raw.contains("com.armchairdevelopers.maxima.helper")
        }.value
    }

    // MARK: - Install

    /// Downloads MaximaSetup.exe from the latest Maxima-Draconis release,
    /// runs it silently inside the bottle, then registers MaximaHelper.
    public func downloadAndInstall(
        into bottle: WineBottle,
        progress: @escaping ProgressHandler
    ) async throws {
        // 1 — Resolve download URL from GitHub Releases
        progress(.init(phase: .fetchingRelease, fraction: -1,
                       detail: "Looking up latest release…"))
        let installerURL = try await fetchInstallerURL()

        // 2 — Download
        progress(.init(phase: .downloading, fraction: 0,
                       detail: "Downloading MaximaSetup.exe…"))
        let tempExe = try await DownloadCoordinator.download(
            from: installerURL
        ) { p in
            progress(.init(phase: .downloading, fraction: p.fraction, detail: p.detail))
        }

        // 3 — Copy into bottle so the installer runs with correct Wine paths
        progress(.init(phase: .installing, fraction: -1, detail: "Running installer…"))
        let bottleTemp = PathResolver.driveC(in: bottle.prefixURL)
            .appendingPathComponent("windows/Temp/MaximaSetup.exe")
        try? FileManager.default.removeItem(at: bottleTemp)
        try FileManager.default.createDirectory(
            at: bottleTemp.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: tempExe, to: bottleTemp)

        guard let driver = await WineBackendManager.shared.driver(for: bottle.backend) else {
            throw MaximaError.noDriver
        }

        // 4 — Run the NSIS installer silently (/S) inside the bottle
        //     Files are installed before the service-creation step, so even if
        //     the Wine service manager rejects `sc create`, the binaries land.
        let proc = try await driver.launch(
            executable: bottleTemp.path,
            arguments: ["/S"],
            in: bottle,
            workingDirectory: nil
        )

        // Tick the UI every second so the user can see elapsed time.
        // waitUntilExit() would block the cooperative thread pool and prevent
        // @MainActor tasks from running, so we use terminationHandler instead.
        let installStart = Date()
        let tickTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let elapsed = Int(-installStart.timeIntervalSinceNow)
                progress(.init(phase: .installing, fraction: -1,
                               detail: "Running installer… (\(elapsed)s)"))
            }
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            proc.terminationHandler = { _ in cont.resume() }
            if !proc.isRunning { cont.resume() }
        }
        tickTask.cancel()

        let code = proc.terminationStatus
        Log.ok("maxima.install", "Installer exited with code \(code)")
        if code != 0 {
            throw MaximaError.installerFailed(code)
        }

        // 5 — Register helper
        progress(.init(phase: .registeringHelper, fraction: -1,
                       detail: "Registering MaximaHelper…"))
        try registerHelper()

        progress(.init(phase: .done, fraction: 1, detail: "Maxima is ready"))
    }

    // MARK: - Launch

    /// Launches Titanfall 2 via `maxima-cli launch <tf2SteamAppID>` inside the bottle.
    @discardableResult
    public func launch(bottle: WineBottle) async throws -> Process {
        guard let cliPath = maximaCliPath(in: bottle) else {
            throw MaximaError.notInstalled
        }
        guard let driver = await WineBackendManager.shared.driver(for: bottle.backend) else {
            throw MaximaError.noDriver
        }
        let workDir = (cliPath as NSString).deletingLastPathComponent
        Log.info("maxima.launch",
                 "maxima-cli.exe launch \(tf2SteamAppID) in '\(bottle.name)'")
        return try await driver.launch(
            executable: cliPath,
            arguments: ["launch", tf2SteamAppID],
            in: bottle,
            workingDirectory: workDir
        )
    }

    // MARK: - Private

    private func fetchInstallerURL() async throws -> URL {
        var request = URLRequest(url: githubReleasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Draconis-Launcher", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw MaximaError.badGitHubResponse(http.statusCode)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let asset = release.assets.first(where: { $0.name == "MaximaSetup.exe" }) else {
            throw MaximaError.noInstallerAsset
        }
        guard let url = URL(string: asset.browserDownloadURL) else {
            throw MaximaError.noInstallerAsset
        }
        return url
    }
}

// MARK: - GitHub API types

private struct GitHubRelease: Decodable {
    let assets: [Asset]
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
}
