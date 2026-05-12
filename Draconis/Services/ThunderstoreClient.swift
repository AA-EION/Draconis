import Foundation

/// Talks to https://northstar.thunderstore.io/api/v1/package/ to list mods.
/// Also handles install/uninstall against a given bottle's R2Northstar/mods
/// directory.
public actor ThunderstoreClient {
    public static let shared = ThunderstoreClient()

    private let packagesURL = URL(
        string: "https://northstar.thunderstore.io/api/v1/package/"
    )!

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = ["User-Agent": "Draconis-Launcher"]
        return URLSession(configuration: config)
    }()

    public enum ThunderstoreError: Error, LocalizedError {
        case badResponse(Int)
        case decodingFailed(String)
        case modsDirectoryMissing
        case unzipFailed(String)

        public var errorDescription: String? {
            switch self {
            case .badResponse(let c):       return "Thunderstore returned HTTP \(c)."
            case .decodingFailed(let s):    return "Couldn't parse Thunderstore data: \(s)"
            case .modsDirectoryMissing:     return "R2Northstar/mods folder is missing in that bottle."
            case .unzipFailed(let s):       return "Couldn't extract the mod: \(s)"
            }
        }
    }

    /// Returns all packages from Thunderstore. The endpoint is paginated by
    /// the server with a hard cap; we follow no pagination because the
    /// Northstar registry returns a single JSON array.
    public func listPackages() async throws -> [ThunderstorePackage] {
        let (data, response) = try await session.data(from: packagesURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ThunderstoreError.badResponse(
                (response as? HTTPURLResponse)?.statusCode ?? -1
            )
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([ThunderstorePackage].self, from: data)
        } catch {
            throw ThunderstoreError.decodingFailed(String(describing: error))
        }
    }

    /// Inspect the local mods directory of a bottle.
    /// Pure FileManager read — safe to call from anywhere.
    public nonisolated func installedMods(in bottle: WineBottle) -> [InstalledMod] {
        guard let tf2 = bottle.titanfall2InstallPath else { return [] }
        let modsRoot = (tf2 as NSString)
            .appendingPathComponent("R2Northstar/mods")
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            atPath: modsRoot
        ) else { return [] }

        return entries.compactMap { name -> InstalledMod? in
            let folder = (modsRoot as NSString).appendingPathComponent(name)
            let manifestPath = (folder as NSString)
                .appendingPathComponent("mod.json")
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath))
            else { return nil }

            struct ModManifest: Decodable {
                let Name: String?
                let Version: String?
            }
            let manifest = (try? JSONDecoder().decode(ModManifest.self, from: data))
            return InstalledMod(
                id: name,
                name: manifest?.Name ?? name,
                version: manifest?.Version ?? "—",
                enabled: !name.hasPrefix("."),
                folderURL: URL(fileURLWithPath: folder)
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Download a Thunderstore mod and extract it into the bottle.
    public func install(
        _ version: ThunderstoreVersion, into bottle: WineBottle
    ) async throws {
        guard let tf2 = bottle.titanfall2InstallPath else {
            throw ThunderstoreError.modsDirectoryMissing
        }
        let modsRoot = (tf2 as NSString)
            .appendingPathComponent("R2Northstar/mods")
        try FileManager.default.createDirectory(
            atPath: modsRoot, withIntermediateDirectories: true
        )

        let tmp = PathResolver.downloadsCache.appendingPathComponent(
            "\(version.fullName).zip"
        )
        let (downloadedURL, _) = try await session.download(from: version.downloadURL)
        try? FileManager.default.removeItem(at: tmp)
        try FileManager.default.moveItem(at: downloadedURL, to: tmp)

        let result = try await ProcessRunner.shared.capture(
            URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-o", tmp.path, "-d", modsRoot]
        )
        if !result.ok {
            throw ThunderstoreError.unzipFailed(result.stderr)
        }
    }

    /// Toggle enabled by renaming the folder with a leading `.` (mirrors how
    /// Northstar itself treats hidden mods).
    public nonisolated func setEnabled(_ enabled: Bool, mod: InstalledMod) throws {
        let parent = mod.folderURL.deletingLastPathComponent()
        let current = mod.folderURL.lastPathComponent
        let target  = enabled
            ? current.hasPrefix(".") ? String(current.dropFirst()) : current
            : current.hasPrefix(".") ? current : "." + current
        if current == target { return }
        try FileManager.default.moveItem(
            at: mod.folderURL,
            to: parent.appendingPathComponent(target)
        )
    }

    public nonisolated func uninstall(_ mod: InstalledMod) throws {
        try FileManager.default.removeItem(at: mod.folderURL)
    }
}
