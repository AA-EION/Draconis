import Foundation

/// Pulls releases from `R2Northstar/Northstar` on GitHub and extracts them on
/// top of the Titanfall 2 install directory inside a bottle.
///
/// We expose a streaming progress channel so the UI can show a live bar; we
/// extract with macOS's native `/usr/bin/ditto` (the Apple-recommended archive
/// tool — handles resource forks, extended attributes, and Unicode names
/// correctly) rather than reaching for `unzip` or a third-party library.
public actor NorthstarUpdater {
    public static let shared = NorthstarUpdater()

    private let releasesEndpoint = URL(
        string: "https://api.github.com/repos/R2Northstar/Northstar/releases"
    )!

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept": "application/vnd.github+json",
            "User-Agent": "Draconis-Launcher"
        ]
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    public enum UpdateError: Error, LocalizedError {
        case noReleases
        case badResponse(Int)
        case downloadFailed(String)
        case extractFailed(String)
        case bottleMissingTitanfall

        public var errorDescription: String? {
            switch self {
            case .noReleases:               return "No Northstar releases were found."
            case .badResponse(let code):    return "GitHub returned HTTP \(code)."
            case .downloadFailed(let s):    return "Download failed: \(s)"
            case .extractFailed(let s):     return "Extraction failed: \(s)"
            case .bottleMissingTitanfall:   return "Titanfall 2 isn't installed in that bottle. Install Titanfall 2 first, then come back."
            }
        }
    }

    /// Progress reported to the UI.
    public struct Progress: Sendable {
        public enum Phase: String, Sendable {
            case fetchingReleases, downloading, extracting, done
        }
        public var phase: Phase
        public var fraction: Double           // 0…1, -1 if indeterminate
        public var detail: String
    }

    public typealias ProgressHandler = @Sendable (Progress) -> Void

    // MARK: - Releases

    public func availableReleases(includePrerelease: Bool = false) async throws -> [NorthstarRelease] {
        Log.info("northstar.update", "Fetching release list from GitHub…")
        let (data, response) = try await session.data(from: releasesEndpoint)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            Log.error("northstar.update", "GitHub HTTP \(code)")
            throw UpdateError.badResponse(code)
        }
        struct RawRelease: Decodable {
            let tag_name: String
            let name: String
            let body: String
            let published_at: Date
            let prerelease: Bool
            let assets: [Asset]
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let raw = try decoder.decode([RawRelease].self, from: data)

        let releases: [NorthstarRelease] = raw.compactMap { r in
            guard includePrerelease || !r.prerelease else { return nil }
            guard let zip = r.assets.first(where: {
                $0.name.lowercased().contains("northstar")
                && $0.name.lowercased().hasSuffix(".zip")
            }) else { return nil }
            return NorthstarRelease(
                tagName: r.tag_name, name: r.name, body: r.body,
                publishedAt: r.published_at, prerelease: r.prerelease,
                zipURL: zip.browser_download_url
            )
        }
        Log.ok("northstar.update", "Found \(releases.count) releases")
        return releases
    }

    public func latestRelease(includePrerelease: Bool = false) async throws -> NorthstarRelease {
        let all = try await availableReleases(includePrerelease: includePrerelease)
        guard let first = all.first else { throw UpdateError.noReleases }
        return first
    }

    // MARK: - Download with progress

    /// Streamed download — emits fractional progress on the provided handler.
    /// Uses a URLSessionDownloadDelegate under the hood for efficient byte
    /// streaming + native progress reporting.
    public func downloadRelease(
        _ release: NorthstarRelease,
        progress: ProgressHandler? = nil
    ) async throws -> URL {
        let dest = PathResolver.downloadsCache.appendingPathComponent(
            "Northstar-\(release.tagName).zip"
        )
        if FileManager.default.fileExists(atPath: dest.path) {
            Log.info("northstar.update", "Using cached zip at \(dest.path)")
            progress?(Progress(phase: .downloading, fraction: 1.0, detail: "Cached"))
            return dest
        }

        Log.info("northstar.update", "Downloading \(release.zipURL.absoluteString)")
        progress?(Progress(phase: .downloading, fraction: 0, detail: "Connecting…"))

        let tmpURL = try await DownloadCoordinator.download(
            from: release.zipURL, progress: progress
        )
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmpURL, to: dest)

        Log.ok("northstar.update", "Downloaded \(dest.lastPathComponent)")
        return dest
    }

    // MARK: - Extract

    /// Extract the zip into the Titanfall 2 root using macOS's native `ditto`.
    public func install(
        zipURL: URL, into bottle: WineBottle,
        progress: ProgressHandler? = nil
    ) async throws {
        // Re-resolve the install path — when the user just created the bottle,
        // the WineBottle struct from a stale scan may not have it set.
        let resolvedRoot = bottle.titanfall2InstallPath
            ?? CrossOverDetector.locateTitanfall2(
                in: PathResolver.driveC(in: bottle.prefixURL)
            )?.path

        guard let target = resolvedRoot else {
            Log.error("northstar.update",
                      "No Titanfall 2 root in “\(bottle.name)” (\(bottle.prefixURL.path))")
            throw UpdateError.bottleMissingTitanfall
        }

        // Make sure the target directory exists (it should, but defensively).
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target, isDirectory: &isDir),
              isDir.boolValue else {
            Log.error("northstar.update", "Target dir doesn't exist: \(target)")
            throw UpdateError.extractFailed("Target dir doesn't exist: \(target)")
        }

        progress?(Progress(phase: .extracting, fraction: -1,
                           detail: "Unpacking with ditto…"))
        Log.run("northstar.update",
                "ditto -x -k \"\(zipURL.path)\" \"\(target)\"")

        let result = try await ProcessRunner.shared.capture(
            URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", zipURL.path, target]
        )
        guard result.ok else {
            Log.error("northstar.update", result.stderr)
            throw UpdateError.extractFailed(
                result.stderr.isEmpty ? "ditto exited \(result.terminationStatus)" : result.stderr
            )
        }

        Log.ok("northstar.update", "Northstar files extracted into \(target)")
        progress?(Progress(phase: .done, fraction: 1.0, detail: "Installed"))
    }

    // MARK: -

    static func formatBytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
