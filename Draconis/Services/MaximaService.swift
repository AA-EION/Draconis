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
        try FileManager.default.copyItem(at: tempExe, to: bottleTemp)

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

        progress(.init(phase: .registeringHelper, fraction: -1,
                       detail: "Removing MaximaHelper handler…"))
        try await unregisterHelper()

        progress(.init(phase: .done, fraction: 1, detail: "Maxima uninstalled"))
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
