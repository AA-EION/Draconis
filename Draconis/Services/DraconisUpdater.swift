import Foundation
import AppKit

/// Self-updater for Draconis itself. Queries the GitHub Releases API for the
/// `AA-EION/Draconis` repo, compares the published tag against the running
/// app's `CFBundleShortVersionString`, and — on user approval — downloads the
/// DMG, mounts it, hands the swap off to a detached shell helper, and quits.
///
/// Why a detached helper rather than swapping in-process:
///   macOS doesn't lock a running `.app`, so `FileManager.replaceItem` works,
///   but the old process can still read mismatched resources from the new
///   bundle between the swap and `NSApp.terminate`. A detached `/bin/sh`
///   that waits for our PID to exit, performs the move, and re-`open`s the
///   new bundle eliminates that window entirely. Same pattern as Sparkle.
public actor DraconisUpdater {
    public static let shared = DraconisUpdater()

    private let releasesEndpoint = URL(
        string: "https://api.github.com/repos/AA-EION/Draconis/releases/latest"
    )!

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept": "application/vnd.github+json",
            "User-Agent": "Draconis-Launcher"
        ]
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    // MARK: - Errors

    public enum UpdateError: Error, LocalizedError {
        case badResponse(Int)
        case noDMGAsset
        case downloadFailed(String)
        case mountFailed(String)
        case appNotFoundOnDMG
        case appNotInApplications(currentPath: String)
        case trashUnavailable(String)

        public var errorDescription: String? {
            switch self {
            case .badResponse(let c):           return "GitHub returned HTTP \(c)."
            case .noDMGAsset:                   return "No DMG asset attached to the latest release."
            case .downloadFailed(let s):        return "Download failed: \(s)"
            case .mountFailed(let s):           return "Could not mount DMG: \(s)"
            case .appNotFoundOnDMG:             return "Draconis.app not found inside the downloaded DMG."
            case .appNotInApplications(let p):
                return "Draconis must live in an Applications folder to self-update (running from \(p))."
            case .trashUnavailable(let s):      return "Cannot resolve a Trash folder for the running app: \(s)"
            }
        }
    }

    // MARK: - Progress

    public struct Progress: Sendable {
        public enum Phase: Sendable {
            case checking, downloading, preparing, swapping, done
        }
        public var phase: Phase
        public var fraction: Double
        public var detail: String
    }

    public typealias ProgressHandler = @Sendable (Progress) -> Void

    // MARK: - Release model

    public struct Release: Sendable, Equatable, Identifiable {
        public let tagName: String
        public let name: String
        public let body: String
        public let dmgURL: URL
        public var id: String { tagName }
    }

    // MARK: - Current version

    /// `CFBundleShortVersionString` from Info.plist (the same value
    /// `MARKETING_VERSION` from `project.yml` flows into at build time).
    public nonisolated var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    // MARK: - Skip-this-version persistence

    private let skipKey = "draconisSkippedUpdateVersion"

    /// The tag the user explicitly chose to skip (e.g. `"v0.8.2"`), or nil.
    /// Persisted in UserDefaults so it survives relaunches; cleared whenever
    /// a newer-than-skipped release shows up.
    public nonisolated var skippedVersion: String? {
        UserDefaults.standard.string(forKey: skipKey)
    }

    public nonisolated func setSkipped(_ tag: String?) {
        if let tag {
            UserDefaults.standard.set(tag, forKey: skipKey)
        } else {
            UserDefaults.standard.removeObject(forKey: skipKey)
        }
    }

    // MARK: - Release lookup

    public func latestRelease() async throws -> Release {
        Log.info("draconis.update", "Checking GitHub for newer Draconis release…")
        let (data, response) = try await session.data(from: releasesEndpoint)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UpdateError.badResponse(code)
        }
        struct RawRelease: Decodable {
            let tag_name: String
            let name: String?
            let body: String?
            let assets: [Asset]
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
        }
        let raw = try JSONDecoder().decode(RawRelease.self, from: data)
        guard let dmg = raw.assets.first(where: {
            $0.name.lowercased().hasSuffix(".dmg")
        }) else {
            throw UpdateError.noDMGAsset
        }
        return Release(
            tagName: raw.tag_name,
            name: raw.name ?? raw.tag_name,
            body: raw.body ?? "",
            dmgURL: dmg.browser_download_url
        )
    }

    /// Returns the latest release iff it represents a newer version than
    /// what's currently running AND the user hasn't explicitly skipped it.
    /// Returns nil otherwise (up to date, network failure, or skipped).
    public func availableUpdate() async -> Release? {
        guard let release = try? await latestRelease() else { return nil }

        let remote = Self.normalize(release.tagName)
        let local = Self.normalize(currentVersion)
        guard Self.compare(local, remote) == .orderedAscending else {
            Log.ok("draconis.update", "Up to date (running \(currentVersion), latest \(release.tagName))")
            // The user is no longer behind, drop any stale skip.
            if skippedVersion != nil { setSkipped(nil) }
            return nil
        }

        if let skipped = skippedVersion {
            let skippedNorm = Self.normalize(skipped)
            if Self.compare(skippedNorm, remote) == .orderedAscending {
                Log.info("draconis.update",
                    "Skipped tag \(skipped) is older than latest \(release.tagName); re-prompting")
                setSkipped(nil)
            } else if skippedNorm == remote {
                Log.info("draconis.update", "User skipped \(release.tagName); not prompting")
                return nil
            }
        }

        Log.info("draconis.update",
            "Update available: \(currentVersion) → \(release.tagName)")
        return release
    }

    // MARK: - Version comparison

    /// Strips a leading `v`/`V` so `v0.8.2` and `0.8.2` compare equal.
    private static func normalize(_ tag: String) -> String {
        var s = tag
        if let first = s.first, first == "v" || first == "V" {
            s.removeFirst()
        }
        return s
    }

    /// Semver-aware comparison. Splits each tag at the first `-` into a numeric
    /// base (`1.0.0`) and an optional pre-release suffix (`rc1`). Bases are
    /// compared numerically per dot-separated component; when bases are equal,
    /// a tag *with* a pre-release ranks lower than one without (so `1.0.0` >
    /// `1.0.0-rc1`, per semver §11). Two pre-releases compare lexicographically.
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let (lBase, lPre) = splitPrerelease(lhs)
        let (rBase, rPre) = splitPrerelease(rhs)

        let a = lBase.components(separatedBy: ".")
        let b = rBase.components(separatedBy: ".")
        for i in 0..<max(a.count, b.count) {
            let lc = i < a.count ? a[i] : "0"
            let rc = i < b.count ? b[i] : "0"
            if let li = Int(lc), let ri = Int(rc) {
                if li != ri { return li < ri ? .orderedAscending : .orderedDescending }
            } else if lc != rc {
                return lc < rc ? .orderedAscending : .orderedDescending
            }
        }

        switch (lPre, rPre) {
        case (nil, nil):            return .orderedSame
        case (nil, _?):             return .orderedDescending
        case (_?, nil):             return .orderedAscending
        case (let l?, let r?):
            if l == r { return .orderedSame }
            return l < r ? .orderedAscending : .orderedDescending
        }
    }

    private static func splitPrerelease(_ tag: String) -> (base: String, prerelease: String?) {
        guard let dash = tag.firstIndex(of: "-") else { return (tag, nil) }
        return (String(tag[..<dash]), String(tag[tag.index(after: dash)...]))
    }

    // MARK: - Install

    /// Downloads the DMG, mounts it, copies the new app to a staging dir,
    /// writes a detached `/bin/sh` helper that waits for our PID to exit
    /// before swapping the running bundle, then asks AppKit to terminate.
    /// Helper survives `terminate` because it's reparented to launchd.
    public func install(
        _ release: Release,
        progress: @escaping ProgressHandler
    ) async throws {
        let currentBundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        // Accept any `/Applications/` segment — covers both `/Applications/`
        // and `~/Applications/` (the per-user apps folder), plus apps living
        // in subfolders of either.
        guard currentBundleURL.path.contains("/Applications/") else {
            throw UpdateError.appNotInApplications(currentPath: currentBundleURL.path)
        }

        // Resolve the right Trash for the volume the running app lives on.
        // On the boot volume that's `~/.Trash`; on external volumes it's
        // `/Volumes/<name>/.Trashes/<uid>/`. FileManager picks the correct one.
        let trashDir: URL
        do {
            trashDir = try FileManager.default.url(
                for: .trashDirectory,
                in: .userDomainMask,
                appropriateFor: currentBundleURL,
                create: true
            )
        } catch {
            throw UpdateError.trashUnavailable(error.localizedDescription)
        }

        progress(.init(phase: .downloading, fraction: 0,
                       detail: "Downloading Draconis \(release.tagName)…"))

        let cachedDMG = PathResolver.downloadsCache.appendingPathComponent(
            "Draconis-\(release.tagName).dmg"
        )
        try? FileManager.default.removeItem(at: cachedDMG)

        let tmpDMG = try await DownloadCoordinator.download(from: release.dmgURL) { p in
            progress(.init(phase: .downloading, fraction: p.fraction, detail: p.detail))
        }
        try FileManager.default.moveItem(at: tmpDMG, to: cachedDMG)
        Log.ok("draconis.update", "Downloaded \(cachedDMG.lastPathComponent)")

        progress(.init(phase: .preparing, fraction: -1, detail: "Mounting DMG…"))
        let mountPoint = try await mountDMG(at: cachedDMG)
        Log.ok("draconis.update", "Mounted at \(mountPoint.path)")

        // No defer for detach: the helper script handles it after we quit
        // (it's idempotent — `hdiutil detach -quiet || true`). For the
        // error paths below we do an explicit best-effort detach.
        do {
            let newAppURL = mountPoint.appendingPathComponent("Draconis.app")
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: newAppURL.path, isDirectory: &isDir),
                  isDir.boolValue else {
                throw UpdateError.appNotFoundOnDMG
            }

            progress(.init(phase: .preparing, fraction: -1,
                           detail: "Staging new version…"))
            let staging = PathResolver.downloadsCache.appendingPathComponent(
                "Draconis-\(release.tagName).staged.app"
            )
            try? FileManager.default.removeItem(at: staging)
            try await ditto(from: newAppURL, to: staging)
            Log.ok("draconis.update", "Staged at \(staging.path)")

            progress(.init(phase: .swapping, fraction: -1, detail: "Preparing relaunch…"))
            try launchSwapHelper(
                stagedApp: staging,
                installedApp: currentBundleURL,
                mountPoint: mountPoint,
                trashDir: trashDir
            )
        } catch {
            _ = try? await detachDMG(at: mountPoint)
            throw error
        }

        progress(.init(phase: .done, fraction: 1.0, detail: "Quitting to apply update…"))
        Log.ok("draconis.update", "Swap helper launched; quitting Draconis")

        // Give the user a beat to see the final message before we vanish.
        try? await Task.sleep(nanoseconds: 600_000_000)
        await MainActor.run {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - DMG mount

    private func mountDMG(at dmg: URL) async throws -> URL {
        let result = try await ProcessRunner.shared.capture(
            URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: ["attach", dmg.path, "-nobrowse", "-readonly", "-plist"]
        )
        guard result.ok else {
            throw UpdateError.mountFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        guard let plistData = result.stdout.data(using: .utf8),
              let plist = try PropertyListSerialization.propertyList(
                  from: plistData, options: [], format: nil
              ) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]]
        else {
            throw UpdateError.mountFailed("hdiutil plist parse failed")
        }
        for entity in entities {
            if let mp = entity["mount-point"] as? String, !mp.isEmpty {
                return URL(fileURLWithPath: mp, isDirectory: true)
            }
        }
        throw UpdateError.mountFailed("no mount-point in hdiutil output")
    }

    private func detachDMG(at mountPoint: URL) async throws {
        _ = try await ProcessRunner.shared.capture(
            URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: ["detach", mountPoint.path, "-quiet"]
        )
    }

    private func ditto(from src: URL, to dst: URL) async throws {
        let result = try await ProcessRunner.shared.capture(
            URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: [src.path, dst.path]
        )
        guard result.ok else {
            throw UpdateError.downloadFailed(
                result.stderr.isEmpty ? "ditto exited \(result.terminationStatus)" : result.stderr
            )
        }
    }

    // MARK: - Helper script

    /// Writes a small shell script to the downloads cache that:
    ///   1. waits for our PID to exit,
    ///   2. moves the running bundle to the user's Trash with a timestamped name,
    ///   3. moves the staged bundle into place,
    ///   4. re-opens it via `/usr/bin/open`.
    ///
    /// Launched with `setsid` so it survives `NSApplication.terminate(nil)`.
    private func launchSwapHelper(
        stagedApp: URL,
        installedApp: URL,
        mountPoint: URL,
        trashDir: URL
    ) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let scriptURL = PathResolver.downloadsCache
            .appendingPathComponent("draconis-update.sh")
        let logURL = PathResolver.draconisSupport
            .appendingPathComponent("update.log")

        let trashName = "Draconis-\(Int(Date().timeIntervalSince1970)).app"

        let script = """
        #!/bin/sh
        # Draconis self-update helper. Auto-generated; safe to delete.
        set -u
        LOG=\(shellQuote(logURL.path))
        exec >>"$LOG" 2>&1
        echo "[$(date -u +%FT%TZ)] update helper started (parent pid \(pid))"

        # Wait for the running Draconis process to actually exit.
        i=0
        while kill -0 \(pid) 2>/dev/null; do
            i=$((i + 1))
            if [ "$i" -gt 300 ]; then
                echo "timed out waiting for parent pid \(pid)"
                exit 1
            fi
            sleep 0.2
        done

        # Detach the DMG if it's still mounted (best-effort).
        /usr/bin/hdiutil detach \(shellQuote(mountPoint.path)) -quiet >/dev/null 2>&1 || true

        # Move the running bundle to Trash (timestamped to avoid collisions),
        # then move the staged new bundle into place.
        if [ -d \(shellQuote(installedApp.path)) ]; then
            mkdir -p \(shellQuote(trashDir.path))
            mv \(shellQuote(installedApp.path)) \(shellQuote(trashDir.appendingPathComponent(trashName).path)) || {
                echo "failed to move old bundle to Trash"
                exit 1
            }
        fi

        mv \(shellQuote(stagedApp.path)) \(shellQuote(installedApp.path)) || {
            echo "failed to move staged bundle into place"
            exit 1
        }

        # Strip quarantine defensively — URLSession downloads shouldn't carry
        # com.apple.quarantine, but covering the corner case costs nothing.
        /usr/bin/xattr -dr com.apple.quarantine \(shellQuote(installedApp.path)) >/dev/null 2>&1 || true

        echo "[$(date -u +%FT%TZ)] swap complete; relaunching"
        /usr/bin/open \(shellQuote(installedApp.path))
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        var attrs = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
        attrs[.posixPermissions] = 0o755
        try FileManager.default.setAttributes(attrs, ofItemAtPath: scriptURL.path)

        // setsid detaches the helper from our process group so it survives the
        // NSApplication.terminate that's coming next.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        proc.arguments = ["/bin/sh", scriptURL.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = FileHandle.nullDevice
        try proc.run()
        Log.run("draconis.update", "nohup /bin/sh \(scriptURL.path)")
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
