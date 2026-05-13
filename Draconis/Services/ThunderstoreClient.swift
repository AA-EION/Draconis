import Foundation

/// Talks to https://northstar.thunderstore.io/api/v1/package/ to list mods.
/// Also handles install/uninstall against a given bottle's R2Northstar/mods
/// directory.
///
/// Thunderstore returns ISO 8601 dates *with fractional seconds*
/// (e.g. `2020-08-08T15:25:35.555000Z`). Swift's stock `.iso8601` decoder does
/// NOT accept fractional seconds, which is the most common reason for the mod
/// list silently coming back empty. We use a multi-format date decoder so both
/// shapes parse.
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
        case extractFailed(String)
        case downloadFailed(String)

        public var errorDescription: String? {
            switch self {
            case .badResponse(let c):       return "Thunderstore returned HTTP \(c)."
            case .decodingFailed(let s):    return "Couldn't parse Thunderstore data: \(s)"
            case .modsDirectoryMissing:     return "R2Northstar/mods folder is missing in that bottle."
            case .extractFailed(let s):     return "Couldn't extract the mod: \(s)"
            case .downloadFailed(let s):    return "Couldn't download the mod: \(s)"
            }
        }
    }

    // MARK: - Listing

    public func listPackages() async throws -> [ThunderstorePackage] {
        Log.info("thunderstore", "GET \(packagesURL.absoluteString)")
        let (data, response) = try await session.data(from: packagesURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            Log.error("thunderstore", "HTTP \(code)")
            throw ThunderstoreError.badResponse(code)
        }

        let decoder = Self.makeDecoder()
        do {
            let packages = try decoder.decode([ThunderstorePackage].self, from: data)
            Log.ok("thunderstore", "Decoded \(packages.count) packages")
            return packages
        } catch {
            // Most likely a date format mismatch — log a sliver of the payload
            // so the user can see what came back.
            let preview = String(data: data.prefix(400), encoding: .utf8) ?? "(binary)"
            Log.error("thunderstore", "Decode failed: \(error)\nFirst bytes: \(preview)")
            throw ThunderstoreError.decodingFailed(String(describing: error))
        }
    }

    /// Multi-format ISO 8601 decoder that handles fractional seconds.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]

        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let str = try container.decode(String.self)
            if let d = withFraction.date(from: str) { return d }
            if let d = standard.date(from: str) { return d }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognised ISO date: \(str)"
            )
        }
        return decoder
    }

    // MARK: - Installed mods (nonisolated — pure FileManager reads)

    public nonisolated func installedMods(in bottle: WineBottle) -> [InstalledMod] {
        guard let tf2 = bottle.titanfall2InstallPath else { return [] }
        let modsRoot = (tf2 as NSString)
            .appendingPathComponent("R2Northstar/mods")
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: modsRoot) else {
            return []
        }

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

    // MARK: - Install / extract

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
        Log.info("thunderstore.install", "Downloading \(version.fullName)")
        do {
            let (downloadedURL, _) = try await session.download(from: version.downloadURL)
            try? FileManager.default.removeItem(at: tmp)
            try FileManager.default.moveItem(at: downloadedURL, to: tmp)
        } catch {
            throw ThunderstoreError.downloadFailed(error.localizedDescription)
        }

        Log.run("thunderstore.install", "ditto -x -k \(tmp.path) \(modsRoot)")
        let result = try await ProcessRunner.shared.capture(
            URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", tmp.path, modsRoot]
        )
        if !result.ok {
            throw ThunderstoreError.extractFailed(result.stderr)
        }
        Log.ok("thunderstore.install", "Installed \(version.fullName)")
    }

    public nonisolated func setEnabled(_ enabled: Bool, mod: InstalledMod) throws {
        let parent = mod.folderURL.deletingLastPathComponent()
        let current = mod.folderURL.lastPathComponent
        let target = enabled
            ? (current.hasPrefix(".") ? String(current.dropFirst()) : current)
            : (current.hasPrefix(".") ? current : "." + current)
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
