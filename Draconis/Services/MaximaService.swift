import Foundation
import AppKit

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
        case helperRegistrationFailed(code: Int32, stderr: String)
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
            case .helperRegistrationFailed(let code, let stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return "MaximaHelper registration failed (lsregister exit \(code))"
                    + (trimmed.isEmpty ? "" : ": \(trimmed)")
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
        maximaFilePath(in: bottle, named: "maxima-cli.exe")
    }

    /// POSIX path to `maxima.exe` (the graphical UI shipped in the
    /// installer) inside the bottle, or `nil` if not installed.
    public func maximaUiPath(in bottle: WineBottle) -> String? {
        maximaFilePath(in: bottle, named: "maxima.exe")
    }

    /// POSIX path to MaximaSetup's NSIS uninstaller (`Uninstall.exe`) inside
    /// the bottle, or nil if not present.
    public func uninstallerPath(in bottle: WineBottle) -> String? {
        maximaFilePath(in: bottle, named: "Uninstall.exe")
    }

    private func maximaFilePath(in bottle: WineBottle, named filename: String) -> String? {
        let driveC = PathResolver.driveC(in: bottle.prefixURL)
        for dir in possibleInstallDirs {
            let url = driveC
                .appendingPathComponent(dir)
                .appendingPathComponent(filename)
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
    /// Two-step process:
    ///   1. Strip `com.apple.quarantine` from the bundled helper (inherited
    ///      from Draconis being delivered via DMG) — LaunchServices ignores
    ///      URL handler claims from quarantined apps.
    ///   2. `lsregister -f` to make LaunchServices aware of the bundle, then
    ///      `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` to
    ///      actually bind `qrc://` to us. The setDefaultApplication call may
    ///      surface a system confirmation prompt to the user.
    ///
    /// MaximaHelper forwards `qrc://` to `http://127.0.0.1:31033` — the same
    /// loopback port that maxima-cli inside Wine listens on, since Wine shares
    /// the host's TCP stack.
    public func registerHelper() async throws {
        guard let helperURL = bundledHelperURL else {
            throw MaximaError.helperNotBundled
        }

        // Strip quarantine from both the helper and Draconis itself.
        // LaunchServices ignores URL handler claims from quarantined apps.
        // Without elevated perms these can silently fail (e.g. on /Applications
        // installs the OS may keep quarantine pinned), so don't block on errors.
        _ = try? runProcess(
            "/usr/bin/xattr",
            arguments: ["-dr", "com.apple.quarantine", helperURL.path]
        )
        _ = try? runProcess(
            "/usr/bin/xattr",
            arguments: ["-dr", "com.apple.quarantine", Bundle.main.bundleURL.path]
        )

        // Unregister any stale copies of the helper that LaunchServices knows
        // about — leftovers from mounted DMGs (each Draconis-vX.dmg download
        // becomes /Volumes/Draconis N/), local Debug builds in DerivedData,
        // installers extracted to /private/tmp, etc. If any of those win the
        // qrc:// binding, setDefaultApplication below silently no-ops.
        let canonicalOurs = helperURL.resolvingSymlinksInPath().standardizedFileURL.path
        let known = await MainActor.run {
            NSWorkspace.shared.urlsForApplications(withBundleIdentifier: helperBundleID)
        }
        for url in known {
            let canonical = url.resolvingSymlinksInPath().standardizedFileURL.path
            if canonical == canonicalOurs { continue }
            Log.info("maxima.helper", "Unregistering stale copy at \(canonical)")
            _ = try? runProcess(lsregister.path, arguments: ["-u", canonical])
        }

        let result = try runProcess(lsregister.path, arguments: ["-f", helperURL.path])
        guard result.exitCode == 0 else {
            Log.error("maxima.helper",
                      "lsregister failed (\(result.exitCode)): \(result.stderr)")
            throw MaximaError.helperRegistrationFailed(
                code: result.exitCode, stderr: result.stderr
            )
        }
        Log.info("maxima.helper", "Bundle known to LaunchServices at \(helperURL.path)")

        // setDefaultApplication is the supported way to claim a URL scheme on
        // macOS 12+. On first run macOS shows the user a confirmation prompt;
        // on subsequent calls it's silent. Throws if the user declines or if
        // LaunchServices refuses (e.g. signature issues).
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.setDefaultApplication(
                at: helperURL,
                toOpenURLsWithScheme: "qrc"
            ) { error in
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
        Log.ok("maxima.helper", "MaximaHelper is now the default qrc:// handler")
    }

    /// Removes the qrc:// scheme claim and unregisters every known copy of
    /// MaximaHelper from LaunchServices. Use this when uninstalling Maxima
    /// or when the user wants another app (e.g. EA's launcher inside
    /// CrossOver) to own qrc://.
    public func unregisterHelper() async throws {
        let known = await MainActor.run {
            NSWorkspace.shared.urlsForApplications(withBundleIdentifier: helperBundleID)
        }
        for url in known {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            Log.info("maxima.helper", "Unregistering \(path)")
            _ = try? runProcess(lsregister.path, arguments: ["-u", path])
        }
        Log.ok("maxima.helper",
               "MaximaHelper removed from LaunchServices (\(known.count) copies)")
    }

    private let helperBundleID = "com.armchairdevelopers.maxima.helper"

    private struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private func runProcess(
        _ executable: String,
        arguments: [String],
        extraEnv: [String: String] = [:]
    ) throws -> ProcessResult {
        let proc = Process()
        let out = Pipe()
        let err = Pipe()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        if !extraEnv.isEmpty {
            var env = ProcessInfo.processInfo.environment
            for (k, v) in extraEnv { env[k] = v }
            proc.environment = env
        }
        proc.standardOutput = out
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
        let outStr = String(data: out.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        let errStr = String(data: err.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        return .init(exitCode: proc.terminationStatus, stdout: outStr, stderr: errStr)
    }

    /// True if MaximaHelper (our bundled copy) is the current system handler
    /// for `qrc://`. Uses NSWorkspace.urlForApplication which queries
    /// LaunchServices directly — no parsing of lsregister dumps, no pipes.
    public func isHelperRegistered() async -> Bool {
        guard let helperURL = bundledHelperURL else { return false }
        guard let probe = URL(string: "qrc://probe") else { return false }
        guard let defaultApp = await MainActor.run(body: {
            NSWorkspace.shared.urlForApplication(toOpen: probe)
        }) else {
            return false
        }
        // Compare canonical paths (resolves symlinks, /private/tmp etc.)
        let registered = defaultApp.resolvingSymlinksInPath().standardizedFileURL.path
        let expected = helperURL.resolvingSymlinksInPath().standardizedFileURL.path
        return registered == expected
    }

    // MARK: - Version tracking

    private let versionKey = "maximaInstalledVersion"

    /// The tag string stored when Maxima was last installed (e.g. "v0.3.1").
    /// Nil if Maxima was never installed through Draconis, or if the preference
    /// was cleared. Since the MaximaSetup.exe binary doesn't embed its own
    /// version, we use the GitHub release tag that produced it.
    ///
    /// `nonisolated` because it only reads UserDefaults (thread-safe) and the
    /// immutable `versionKey` constant — no actor-isolated state is touched.
    public nonisolated var installedVersion: String? {
        UserDefaults.standard.string(forKey: versionKey)
    }

    /// Fetches the latest release tag from GitHub without downloading the asset.
    /// Returns `(tagName, downloadURL)`.
    public func fetchLatestRelease() async throws -> (tagName: String, downloadURL: URL) {
        var request = URLRequest(url: githubReleasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Draconis-Launcher", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw MaximaError.badGitHubResponse(http.statusCode)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let asset = release.assets.first(where: { $0.name == "MaximaSetup.exe" }),
              let url = URL(string: asset.browserDownloadURL) else {
            throw MaximaError.noInstallerAsset
        }
        return (release.tagName, url)
    }

    /// Returns true when the installed version tag is older than the latest
    /// GitHub release. Returns false if Maxima is not installed yet.
    public func isUpdateAvailable() async -> Bool {
        guard let local = installedVersion else { return false }
        guard let (remote, _) = try? await fetchLatestRelease() else { return false }
        return local != remote
    }

    // MARK: - Install

    /// Downloads MaximaSetup.exe from the latest Maxima-Draconis release,
    /// runs it silently inside the bottle, then registers MaximaHelper.
    ///
    /// The installer is saved to `PathResolver.downloadsCache/MaximaSetup.exe`
    /// (overwriting any previous copy) so it lives alongside Northstar zips.
    public func downloadAndInstall(
        into bottle: WineBottle,
        progress: @escaping ProgressHandler
    ) async throws {
        // 1 — Resolve download URL and tag from GitHub Releases
        progress(.init(phase: .fetchingRelease, fraction: -1,
                       detail: "Looking up latest release…"))
        let (tagName, installerURL) = try await fetchLatestRelease()

        // 2 — Download to the shared Downloads cache (overwrite previous copy).
        let cachedExe = PathResolver.downloadsCache
            .appendingPathComponent("MaximaSetup.exe")
        try? FileManager.default.removeItem(at: cachedExe)

        progress(.init(phase: .downloading, fraction: 0,
                       detail: "Downloading MaximaSetup.exe…"))
        let tempExe = try await DownloadCoordinator.download(
            from: installerURL
        ) { p in
            progress(.init(phase: .downloading, fraction: p.fraction, detail: p.detail))
        }
        try FileManager.default.moveItem(at: tempExe, to: cachedExe)

        // 3 — If Maxima is already installed we're effectively updating;
        //     run the uninstaller first so the new version isn't fighting
        //     a running maxima-cli or stale files. Best-effort.
        if isInstalled(in: bottle) {
            progress(.init(phase: .installing, fraction: -1,
                           detail: "Removing previous Maxima install…"))
            try? await uninstall(from: bottle) { _ in }
        }

        progress(.init(phase: .installing, fraction: -1, detail: "Running installer…"))
        let bottleTemp = PathResolver.driveC(in: bottle.prefixURL)
            .appendingPathComponent("windows/Temp/MaximaSetup.exe")
        try? FileManager.default.removeItem(at: bottleTemp)
        try FileManager.default.createDirectory(
            at: bottleTemp.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: cachedExe, to: bottleTemp)

        // 4 — Run the NSIS installer silently (/S) inside the bottle
        //     Files are installed before the service-creation step, so even if
        //     the Wine service manager rejects `sc create`, the binaries land.
        let proc = try await WineBackendManager.shared.launch(
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
        try await registerHelper()

        // Persist the installed version tag so we can detect updates later.
        UserDefaults.standard.set(tagName, forKey: versionKey)

        progress(.init(phase: .done, fraction: 1, detail: "Maxima is ready"))
    }

    // MARK: - Uninstall

    /// Runs Maxima's bundled NSIS uninstaller inside the bottle (silently),
    /// then unregisters the macOS helper. Before invoking the uninstaller
    /// it kills wineserver processes for this prefix so an in-flight
    /// maxima-cli or other locked file doesn't block removal.
    public func uninstall(
        from bottle: WineBottle,
        progress: @escaping ProgressHandler
    ) async throws {
        guard let uninstallerPath = uninstallerPath(in: bottle) else {
            throw MaximaError.notInstalled
        }

        progress(.init(phase: .installing, fraction: -1,
                       detail: "Stopping bottle processes…"))
        await killBottleProcesses(bottle: bottle)

        progress(.init(phase: .installing, fraction: -1,
                       detail: "Running uninstaller…"))
        let proc = try await WineBackendManager.shared.launch(
            executable: uninstallerPath,
            arguments: ["/S"],
            in: bottle,
            workingDirectory: nil
        )

        let start = Date()
        let tickTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let elapsed = Int(-start.timeIntervalSinceNow)
                progress(.init(phase: .installing, fraction: -1,
                               detail: "Running uninstaller… (\(elapsed)s)"))
            }
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            proc.terminationHandler = { _ in cont.resume() }
            if !proc.isRunning { cont.resume() }
        }
        tickTask.cancel()

        let code = proc.terminationStatus
        Log.ok("maxima.uninstall", "Uninstaller exited with code \(code)")
        if code != 0 {
            throw MaximaError.installerFailed(code)
        }

        // Give the NSIS uninstaller's wineserver writes a moment to flush to
        // disk before we remove any leftover files ourselves. Without this
        // delay isInstalled(in:) can still find maxima-cli.exe immediately
        // after the installer exits.
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        // Best-effort sweep of install directories the NSIS script may have
        // left behind (e.g. when wineserver locked a file mid-removal).
        forceRemoveInstallDirs(in: bottle)

        // Clear the persisted version tag so the UI reflects the uninstalled
        // state immediately — without this the version check in refreshMaximaState
        // would report a stale version until the next app launch.
        UserDefaults.standard.removeObject(forKey: versionKey)

        progress(.init(phase: .registeringHelper, fraction: -1,
                       detail: "Removing MaximaHelper handler…"))
        try await unregisterHelper()

        progress(.init(phase: .done, fraction: 1, detail: "Maxima uninstalled"))
    }

    /// Removes the known Maxima install directories from the bottle's drive_c.
    /// Called after the NSIS uninstaller exits to catch any files the uninstaller
    /// left behind (locked handles, wineserver latency, etc.).
    private func forceRemoveInstallDirs(in bottle: WineBottle) {
        let driveC = PathResolver.driveC(in: bottle.prefixURL)
        let fm = FileManager.default
        for dir in possibleInstallDirs {
            let url = driveC.appendingPathComponent(dir)
            if fm.fileExists(atPath: url.path) {
                do {
                    try fm.removeItem(at: url)
                    Log.ok("maxima.uninstall", "Removed leftover dir: \(dir)")
                } catch {
                    Log.error("maxima.uninstall",
                              "Could not remove \(dir): \(error.localizedDescription)")
                }
            }
        }
    }

    /// `wineserver -k` against the bottle's WINEPREFIX kills every wine
    /// process attached to that prefix. Best-effort — failure isn't fatal,
    /// the uninstaller will just report any locked files itself.
    private func killBottleProcesses(bottle: WineBottle) async {
        guard let wineserver = await CrossOverDetector.shared.wineserverBinary() else {
            return
        }
        var proc = ProcessResult(exitCode: 0, stdout: "", stderr: "")
        proc = (try? runProcess(
            wineserver.path,
            arguments: ["-k"],
            extraEnv: ["WINEPREFIX": bottle.prefixURL.path]
        )) ?? proc
        _ = proc
        // wineserver -k is async; give it a moment to actually quit.
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    // NOTE: There is intentionally no MaximaService.launch() anymore. For
    // Steam-owned Titanfall 2 (the only configuration this fork supports),
    // launching goes through `steam.exe -applaunch 1237970` — Steam invokes
    // Titanfall2.exe, which emits a link2ea:// URI, which the maxima-bootstrap
    // protocol handler (registered inside the bottle by MaximaSetup.exe)
    // catches and resolves through maxima-cli automatically. See
    // NorthstarLauncher.swift for the user-facing launch entry point.
    //
    // Invoking `maxima-cli launch <slug>` directly is for EA-store-owned
    // games; it fails with "No owned offer found" when the user owns TF2
    // on Steam.

}

// MARK: - GitHub API types

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [Asset]
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

// MARK: - CLI invocations (driven via cxstart inside the bottle)

extension MaximaService {

    /// One row in the `maxima-cli list-games --json` output. Fields named
    /// to match the JSON document Maxima emits — see Maxima-Draconis CLAUDE.md
    /// "Mode::ListGames" section for the full schema.
    public struct OwnedGame: Codable, Sendable, Identifiable {
        public let slug: String
        public let name: String
        public let offerId: String
        public let contentId: String
        public let displayName: String
        public let installed: Bool
        public let installPath: String?
        public let version: String?
        public let hasCloudSave: Bool

        public var id: String { offerId }

        private enum CodingKeys: String, CodingKey {
            case slug, name, installed, version
            case offerId = "offer_id"
            case contentId = "content_id"
            case displayName = "display_name"
            case installPath = "install_path"
            case hasCloudSave = "has_cloud_save"
        }
    }

    public enum CliError: Error, LocalizedError {
        case notInstalled
        case cxstartMissing
        case cliFailed(exitCode: Int32, stderr: String)
        case invalidOutput(String)
        case notLoggedIn

        public var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "Maxima isn't installed in this bottle."
            case .cxstartMissing:
                return "CrossOver's cxstart binary not found."
            case .cliFailed(let code, let stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let tail = trimmed.isEmpty ? "" : ": \(trimmed)"
                return "maxima-cli exited with code \(code)\(tail)"
            case .invalidOutput(let detail):
                return "maxima-cli output couldn't be parsed: \(detail)"
            case .notLoggedIn:
                return "Maxima isn't logged in to an EA account yet. Run `maxima-cli` interactively inside the bottle once to complete the OAuth flow."
            }
        }
    }

    /// Run `maxima-cli list-games --json` inside the bottle, parse the
    /// JSON array, return what Maxima reports about the user's EA library.
    /// Requires the user to have completed OAuth at least once — Draconis
    /// is intentionally non-interactive here. If maxima-cli emits no
    /// `[` (the JSON array start) it's almost certainly because login
    /// failed; surface that as `.notLoggedIn`.
    public func listGames(in bottle: WineBottle) async throws -> [OwnedGame] {
        guard let cliPath = maximaCliPath(in: bottle) else {
            throw CliError.notInstalled
        }
        guard let cxstart = await CrossOverDetector.shared.cxstartBinary() else {
            throw CliError.cxstartMissing
        }

        let process = Process()
        process.executableURL = cxstart
        process.arguments = [
            "--bottle", bottle.name,
            "--wait",
            cliPath,
            "list-games",
            "--json",
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        Log.run("maxima.cli", "cxstart --bottle \(bottle.name) --wait \(cliPath) list-games --json")

        try await Task.detached(priority: .userInitiated) {
            try process.run()
            process.waitUntilExit()
        }.value

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let stderr = String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw CliError.cliFailed(exitCode: process.terminationStatus, stderr: stderr)
        }

        // cxstart sometimes echoes a launch banner before the program's
        // own stdout. The JSON document always starts with `[`, so trim
        // anything before it.
        guard let bracket = stdoutData.firstIndex(of: UInt8(ascii: "[")) else {
            let text = String(data: stdoutData, encoding: .utf8) ?? "<binary>"
            // No bracket usually means OAuth wasn't completed and the
            // login flow printed an interactive prompt that never got
            // resolved — surface that as a distinct, actionable error.
            if text.contains("Login failed") || text.contains("paste") || text.isEmpty {
                throw CliError.notLoggedIn
            }
            throw CliError.invalidOutput(text)
        }
        let jsonData = stdoutData[bracket...]

        do {
            return try JSONDecoder().decode([OwnedGame].self, from: jsonData)
        } catch {
            throw CliError.invalidOutput("JSON decode failed: \(error.localizedDescription)")
        }
    }

    /// Apply the Steam-CEG fix to a Titanfall 2 install: replace the two
    /// CEG-signed launcher binaries (`Titanfall2.exe` and
    /// `Titanfall2_trial.exe`) with the EA originals via Maxima's
    /// `install --replace-files … --only-listed-files` flow. ~3 MB
    /// download, leaves everything else in the install untouched
    /// (Northstar files, save games, bin/, Core/).
    ///
    /// `gamePath` is the install root as Wine sees it — e.g.
    /// `C:\Program Files (x86)\Steam\steamapps\common\Titanfall2`.
    /// Caller is responsible for passing a valid TF2 directory.
    public func applyCegFix(
        in bottle: WineBottle,
        gamePath: String
    ) async throws {
        guard let cliPath = maximaCliPath(in: bottle) else {
            throw CliError.notInstalled
        }
        guard let cxstart = await CrossOverDetector.shared.cxstartBinary() else {
            throw CliError.cxstartMissing
        }

        let process = Process()
        process.executableURL = cxstart
        process.arguments = [
            "--bottle", bottle.name,
            "--wait",
            cliPath,
            "install",
            "titanfall-2",
            "--path", gamePath,
            "--replace-files", "Titanfall2.exe,Titanfall2_trial.exe",
            "--only-listed-files",
        ]

        Log.run("maxima.ceg", "Applying CEG fix to \(gamePath) in bottle \(bottle.name)")

        // Pipe output to the per-bottle log file so the user can read
        // exactly what maxima-cli reported if something goes wrong.
        let logURL = PathResolver.bottleLogFile(for: bottle)
        try? FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        try logHandle.seekToEnd()
        process.standardOutput = logHandle
        process.standardError = logHandle

        try await Task.detached(priority: .userInitiated) {
            try process.run()
            process.waitUntilExit()
        }.value

        try? logHandle.close()

        if process.terminationStatus != 0 {
            throw CliError.cliFailed(
                exitCode: process.terminationStatus,
                stderr: "see \(logURL.path) for details"
            )
        }

        Log.ok("maxima.ceg", "CEG fix applied successfully")
    }

    /// Run `maxima-cli launch <offer> [--game-path …] [--game-args
    /// -northstar]` inside the bottle. Used by the launch decision
    /// tree when Maxima is present — maxima-cli handles EA auth +
    /// bootstrap spawn internally, so we don't need Steam's `applaunch`
    /// or the `-noOriginStartup` flag dance.
    ///
    /// `gamePath` is optional. When supplied, it's forwarded verbatim
    /// as `--game-path` so maxima-cli skips its EA-library lookup
    /// (helpful for Steam-installed copies where the EA library may
    /// not register the install). maxima-cli v0.8.0+ accepts either
    /// the install directory or the executable path; we pass the
    /// directory from `WineBottle.titanfall2InstallPath`.
    ///
    /// Returns the detached `Process` so the caller can either
    /// `waitUntilExit` or fire-and-forget (typically the latter —
    /// games are GUI apps and we want App Nap to leave them alone).
    ///
    /// Why we bypass `Foundation.Process` for this path: the same
    /// `cxstart maxima-cli.exe …` invocation reaches Main Menu from
    /// Terminal but freezes TF2 mid-launch (right after LSX
    /// `GetAllGameInfo`) when spawned via Swift's `Process` from a
    /// `.app`. Verified by running the literal cxstart command both
    /// ways and watching the LSX trace. Three differences between
    /// `Process()` and shell `fork → setsid → exec` cause it; see
    /// `CleanSpawn.swift` for the full breakdown.
    ///
    /// `gamePath` is forwarded as `--game-path` so maxima-cli skips
    /// its EA-library lookup. `gameArgs` is forwarded as one
    /// `--game-args` per element (maxima-cli's CLI accepts repeated
    /// flags); the caller passes the full set of args the target exe
    /// needs (e.g. `-noOriginStartup`, `-vanilla`).
    @discardableResult
    public func launchGame(
        in bottle: WineBottle,
        gamePath: String,
        gameArgs: [String] = []
    ) async throws -> Process {
        guard let cliPath = maximaCliPath(in: bottle) else {
            throw CliError.notInstalled
        }
        guard let cxstart = await CrossOverDetector.shared.cxstartBinary() else {
            throw CliError.cxstartMissing
        }

        var cliArgs: [String] = ["launch", "Origin.OFR.50.0001456", "--game-path", gamePath]
        for arg in gameArgs {
            cliArgs.append(contentsOf: ["--game-args", arg])
        }

        let logURL = PathResolver.bottleLogFile(for: bottle)
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }

        let cxstartArgs: [String] = ["--bottle", bottle.name, cliPath] + cliArgs
        Log.info(
            "maxima.launch",
            "CleanSpawn.spawn cxstart=\(cxstart.path) args=\(cxstartArgs.joined(separator: " "))"
        )

        let pid = try CleanSpawn.spawn(
            executable: cxstart.path,
            arguments: cxstartArgs,
            stdinPath: "/dev/null",
            stdoutPath: logURL.path
        )

        Log.info("maxima.launch", "cxstart spawned pid=\(pid)")

        // The caller's API takes a `Process` (it tracks lifetime via
        // termination). We don't have a `Process` for a posix_spawn'd
        // child — the PID is the only handle. Return a placeholder
        // `Process` that's not actually used by `AppEnvironment`
        // (which polls `pgrep Titanfall2.exe` instead). The stub stays
        // unattached to any real child.
        return Process()
    }

    /// Launch Maxima's graphical UI (`maxima.exe`) interactively
    /// inside the bottle. Used by the onboarding wizard's Maxima
    /// route so the user can do OAuth login + pick + install
    /// Titanfall 2 from their EA library — steps that require a
    /// human in the loop and can't be scripted from Draconis (qrc://
    /// callback, browser handoff, library browsing).
    ///
    /// Goes through `CleanSpawn` for the same reason `launchGame`
    /// does — `Foundation.Process` from a `.app` context freezes the
    /// Wine chain. See `CleanSpawn.swift` for the full rationale.
    public func launchMaximaUI(in bottle: WineBottle) async throws {
        guard let uiPath = maximaUiPath(in: bottle) else {
            throw CliError.notInstalled
        }
        guard let cxstart = await CrossOverDetector.shared.cxstartBinary() else {
            throw CliError.cxstartMissing
        }

        let logURL = PathResolver.bottleLogFile(for: bottle)
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }

        let cxstartArgs: [String] = ["--bottle", bottle.name, uiPath]
        Log.info(
            "maxima.ui",
            "CleanSpawn.spawn cxstart=\(cxstart.path) args=\(cxstartArgs.joined(separator: " "))"
        )

        let pid = try CleanSpawn.spawn(
            executable: cxstart.path,
            arguments: cxstartArgs,
            stdinPath: "/dev/null",
            stdoutPath: logURL.path
        )
        Log.info("maxima.ui", "maxima.exe spawned pid=\(pid)")
    }

    /// Drive the user's `MaximaRole` choice for a bottle:
    ///   * `.none` — uninstall Maxima if present, persist the choice.
    ///   * `.authOnly` — install Maxima (downloads installer +
    ///     registers MaximaHelper) if it isn't already, persist.
    ///   * `.fullReplace` — same as authOnly, then run
    ///     `maxima-cli install --replace-files
    ///     "Titanfall2.exe,Titanfall2_trial.exe"
    ///     --only-listed-files` against the install path so the
    ///     CEG-signed launcher binaries get replaced with EA originals.
    ///
    /// The persisted role is read by `WineBottle.maximaRole` at launch
    /// time to pick the right command path (see `NorthstarLauncher`'s
    /// decision matrix).
    public func applyRole(
        _ role: MaximaRole,
        in bottle: WineBottle,
        progress: @escaping @Sendable (MaximaService.Progress) -> Void = { _ in }
    ) async throws {
        switch role {
        case .none:
            if isInstalled(in: bottle) {
                Log.info("maxima.role", "Role .none — uninstalling Maxima from \(bottle.name)")
                try? await uninstall(from: bottle, progress: progress)
            }
        case .authOnly:
            if !isInstalled(in: bottle) {
                Log.info("maxima.role", "Role .authOnly — installing Maxima into \(bottle.name)")
                try await downloadAndInstall(into: bottle, progress: progress)
            } else {
                Log.info("maxima.role", "Maxima already installed; skipping download")
            }
            try await registerHelper()
        case .fullReplace:
            if !isInstalled(in: bottle) {
                Log.info("maxima.role", "Role .fullReplace — installing Maxima first")
                try await downloadAndInstall(into: bottle, progress: progress)
            }
            try await registerHelper()
            // Locate the TF2 install dir so we can target it for the
            // surgical replace. Without an install we can't do the
            // CEG fix; surface as a clean error.
            guard let tf2Root = bottle.titanfall2InstallPath
                ?? CrossOverDetector.locateTitanfall2(
                    in: PathResolver.driveC(in: bottle.prefixURL)
                )?.path
            else {
                throw CliError.cliFailed(
                    exitCode: -1,
                    stderr: "Titanfall 2 install not found in bottle — apply the role after Titanfall 2 is installed."
                )
            }
            Log.info("maxima.role", "Applying CEG fix at \(tf2Root)")
            try await applyCegFix(in: bottle, gamePath: tf2Root)
        }

        MaximaRole.save(role, forBottle: bottle.id)
        Log.ok("maxima.role", "Persisted role=\(role.rawValue) for bottle \(bottle.id)")
    }
}
