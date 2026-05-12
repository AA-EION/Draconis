import Foundation

/// Talks to GitHub's REST API to find / download new NorthstarLauncher releases
/// and unzips them into a bottle.
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
        return URLSession(configuration: config)
    }()

    public enum UpdateError: Error, LocalizedError {
        case noReleases
        case badResponse(Int)
        case downloadFailed
        case unzipFailed(String)
        case bottleMissingTitanfall

        public var errorDescription: String? {
            switch self {
            case .noReleases:                return "No Northstar releases were found."
            case .badResponse(let code):     return "GitHub returned HTTP \(code)."
            case .downloadFailed:            return "Failed to download Northstar."
            case .unzipFailed(let s):        return "Couldn't extract the archive: \(s)"
            case .bottleMissingTitanfall:    return "Titanfall 2 isn't installed in that bottle."
            }
        }
    }

    public func availableReleases(includePrerelease: Bool = false) async throws -> [NorthstarRelease] {
        let (data, response) = try await session.data(from: releasesEndpoint)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
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

        return raw.compactMap { r in
            guard includePrerelease || !r.prerelease else { return nil }
            // Northstar's release zip is named `Northstar.release.<ver>.zip`.
            guard let zip = r.assets.first(where: {
                $0.name.lowercased().contains("northstar")
                && $0.name.hasSuffix(".zip")
            }) else { return nil }
            return NorthstarRelease(
                tagName: r.tag_name,
                name: r.name,
                body: r.body,
                publishedAt: r.published_at,
                prerelease: r.prerelease,
                zipURL: zip.browser_download_url
            )
        }
    }

    public func latestRelease(includePrerelease: Bool = false) async throws -> NorthstarRelease {
        let all = try await availableReleases(includePrerelease: includePrerelease)
        guard let first = all.first else { throw UpdateError.noReleases }
        return first
    }

    /// Download the release zip into the Draconis download cache and return
    /// the local file URL.
    public func downloadRelease(
        _ release: NorthstarRelease,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let dest = PathResolver.downloadsCache.appendingPathComponent(
            "Northstar-\(release.tagName).zip"
        )
        if FileManager.default.fileExists(atPath: dest.path) { return dest }

        let (tmpURL, response) = try await session.download(from: release.zipURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmpURL, to: dest)
        progress?(1.0)
        return dest
    }

    /// Extract a Northstar release zip on top of the Titanfall 2 install
    /// directory inside a bottle. Uses `/usr/bin/unzip` for reliability — it
    /// handles symlinks and permissions correctly, and is always present on
    /// macOS.
    public func install(
        zipURL: URL, into bottle: WineBottle
    ) async throws {
        guard let target = bottle.titanfall2InstallPath else {
            throw UpdateError.bottleMissingTitanfall
        }
        let result = try await ProcessRunner.shared.capture(
            URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-o", zipURL.path, "-d", target]
        )
        if !result.ok {
            throw UpdateError.unzipFailed(result.stderr)
        }
    }
}
