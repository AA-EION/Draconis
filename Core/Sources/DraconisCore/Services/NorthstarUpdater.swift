import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Pulls releases from `R2Northstar/Northstar` on GitHub and extracts them on
/// top of a Titanfall 2 install folder, with streamed progress for the UI.
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
        case titanfallMissing

        public var errorDescription: String? {
            switch self {
            case .noReleases:               return "No Northstar releases were found."
            case .badResponse(let code):    return "GitHub returned HTTP \(code)."
            case .downloadFailed(let s):    return "Download failed: \(s)"
            case .extractFailed(let s):     return "Extraction failed: \(s)"
            case .titanfallMissing:         return "Titanfall 2 isn't installed there. Install Titanfall 2 first, then come back."
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
        let dest = CorePaths.downloads.appendingPathComponent(
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

    // MARK: - Install

    /// Extract the release zip on top of the Titanfall 2 folder.
    public func install(
        zipURL: URL, into gameRoot: URL,
        progress: ProgressHandler? = nil
    ) async throws {
        guard GameFiles.isTitanfallRoot(gameRoot) else {
            Log.error("northstar.update", "No Titanfall2.exe in \(gameRoot.path)")
            throw UpdateError.titanfallMissing
        }
        progress?(Progress(phase: .extracting, fraction: -1, detail: "Unpacking…"))
        Log.run("northstar.update", "unzip \(zipURL.lastPathComponent) → \(gameRoot.path)")
        do {
            try ZipExtractor.extract(zipURL, to: gameRoot)
        } catch {
            Log.error("northstar.update", error.localizedDescription)
            throw UpdateError.extractFailed(error.localizedDescription)
        }
        Log.ok("northstar.update", "Northstar files extracted into \(gameRoot.path)")
        progress?(Progress(phase: .done, fraction: 1.0, detail: "Installed"))
    }

    // MARK: - Uninstall

    /// Remove only the files Northstar's release adds; the game stays intact.
    public func uninstall(from gameRoot: URL) async throws {
        guard GameFiles.isTitanfallRoot(gameRoot) else { throw UpdateError.titanfallMissing }
        let fm = FileManager.default
        var errors: [String] = []
        for rel in GameFiles.northstarPaths {
            let url = gameRoot.appendingPathComponent(rel)
            guard fm.fileExists(atPath: url.path) else { continue }
            do {
                try fm.removeItem(at: url)
                Log.ok("northstar.uninstall", "Removed \(rel)")
            } catch {
                Log.error("northstar.uninstall", "Could not remove \(rel): \(error.localizedDescription)")
                errors.append(rel)
            }
        }
        if !errors.isEmpty {
            throw UpdateError.extractFailed("Could not remove: \(errors.joined(separator: ", "))")
        }
        Log.ok("northstar.uninstall", "Northstar removed from \(gameRoot.path)")
    }

    // MARK: -

    static func formatBytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
