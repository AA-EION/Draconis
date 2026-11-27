import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Talks to https://thunderstore.io/c/northstar/api/v1/package/ to list mods.
/// Also installs, toggles and removes mods in a game folder's R2Northstar tree.
///
/// **Install layout — uses `R2Northstar/packages/<full_name>/`** (the modern
/// Northstar layout, documented at docs.northstar.tf/Wiki/using-northstar/packages).
/// Each Thunderstore zip is extracted as-is into its own package folder, so
/// `manifest.json`, `mods/`, and `plugins/` keep their original positions.
/// Northstar recursively scans packages/ for `mods/*/mod.json` and `plugins/*.dll`.
///
/// Older mods that pre-date `packages/` may still be loose in
/// `R2Northstar/mods/<ModName>/`. The listing logic reads *both* roots so the
/// user sees everything Northstar actually loads.
///
/// Thunderstore returns ISO 8601 dates *with fractional seconds*
/// (e.g. `2020-08-08T15:25:35.555000Z`). Swift's stock `.iso8601` decoder does
/// NOT accept fractional seconds, which is the most common reason for the mod
/// list silently coming back empty. We use a multi-format date decoder so both
/// shapes parse.
public actor ThunderstoreClient {
    public static let shared = ThunderstoreClient()

    private let packagesURL = URL(
        string: "https://thunderstore.io/c/northstar/api/v1/package/"
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
            case .modsDirectoryMissing:     return "Titanfall 2 isn't installed there, so there's nowhere to put mods."
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

    // MARK: - Path helpers

    private nonisolated static func northstarDir(_ gameRoot: URL) -> URL {
        gameRoot.appendingPathComponent("R2Northstar", isDirectory: true)
    }
    private nonisolated static func modsRoot(in gameRoot: URL) -> URL {
        northstarDir(gameRoot).appendingPathComponent("mods", isDirectory: true)
    }
    private nonisolated static func packagesRoot(in gameRoot: URL) -> URL {
        northstarDir(gameRoot).appendingPathComponent("packages", isDirectory: true)
    }
    /// Northstar's own `{ "Mod.Name": true|false }` map of loaded mods.
    private nonisolated static func enabledModsFile(in gameRoot: URL) -> URL {
        northstarDir(gameRoot).appendingPathComponent("enabledmods.json")
    }

    // MARK: - Installed mods (nonisolated — pure FileManager reads)

    /// Read every mod Northstar would load: the legacy
    /// `R2Northstar/mods/<ModName>/` layout *and* the modern
    /// `R2Northstar/packages/<full_name>/mods/<ModName>/` layout.
    public nonisolated func installedMods(in gameRoot: URL) -> [InstalledMod] {
        let enabled = readEnabledMods(in: gameRoot)
        var results: [InstalledMod] = []

        // Legacy: R2Northstar/mods/<ModName>/
        do {
            let modsRoot = Self.modsRoot(in: gameRoot)
            for url in subdirectories(of: modsRoot) {
                guard let mod = Self.readMod(at: url, enabledMap: enabled, packageID: nil) else { continue }
                results.append(mod)
            }
        }

        // Modern: R2Northstar/packages/<full_name>/mods/<ModName>/
        do {
            let packagesRoot = Self.packagesRoot(in: gameRoot)
            for pkg in subdirectories(of: packagesRoot) {
                let modsDir = pkg.appendingPathComponent("mods", isDirectory: true)
                let packageID = pkg.lastPathComponent
                guard FileManager.default.fileExists(atPath: modsDir.path) else { continue }
                for url in subdirectories(of: modsDir) {
                    guard let mod = Self.readMod(at: url, enabledMap: enabled, packageID: packageID) else { continue }
                    results.append(mod)
                }
            }
        }

        return results.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private nonisolated func subdirectories(of root: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private nonisolated static func readMod(
        at folder: URL,
        enabledMap: EnabledMods,
        packageID: String?
    ) -> InstalledMod? {
        let name = folder.lastPathComponent
        let manifestPath = folder.appendingPathComponent("mod.json")
        guard let data = try? Data(contentsOf: manifestPath) else { return nil }

        struct ModManifest: Decodable {
            let Name: String?
            let Version: String?
        }
        let manifest = try? JSONDecoder().decode(ModManifest.self, from: data)
        let modName = manifest?.Name ?? name

        // enabledmods.json wins; otherwise a dot-prefixed folder (legacy) is off.
        let version = manifest?.Version ?? "—"
        let isEnabled = enabledMap.isEnabled(modName, version: version) ?? !name.hasPrefix(".")

        return InstalledMod(
            id: packageID.map { "\($0)/\(name)" } ?? name,
            name: modName,
            version: version,
            enabled: isEnabled,
            folderURL: folder,
            thunderstoreID: packageID
        )
    }

    private nonisolated func readEnabledMods(in gameRoot: URL) -> EnabledMods {
        EnabledMods.read(from: Self.enabledModsFile(in: gameRoot))
    }

    // MARK: - Install / extract

    /// Install a Thunderstore version into the game's R2Northstar folder.
    ///
    /// New layout: extract the zip wholesale into
    /// `R2Northstar/packages/<full_name>/`. This preserves the Thunderstore
    /// package's internal structure (`mods/`, `plugins/`, `manifest.json`,
    /// `icon.png`, `README.md`) exactly as Northstar expects.
    ///
    /// If `resolveDependencies` is true, recursively install any dependencies
    /// the manifest declares (skipping ones already installed and Northstar
    /// itself, which is managed separately).
    public func install(
        _ version: ThunderstoreVersion,
        into gameRoot: URL,
        resolveDependencies: Bool = true,
        installedPackages: Set<String> = [],
        packageCache: [ThunderstorePackage]? = nil
    ) async throws {
        guard GameFiles.isTitanfallRoot(gameRoot) else { throw ThunderstoreError.modsDirectoryMissing }
        let packagesRoot = Self.packagesRoot(in: gameRoot)
        try FileManager.default.createDirectory(
            at: packagesRoot, withIntermediateDirectories: true
        )

        let destination = packagesRoot.appendingPathComponent(version.fullName, isDirectory: true)
        let tmpZip = CorePaths.downloads.appendingPathComponent(
            "\(version.fullName).zip"
        )

        Log.info("thunderstore.install", "Downloading \(version.fullName)")
        do {
            let downloadedURL = try await DownloadCoordinator.download(from: version.downloadURL)
            try? FileManager.default.removeItem(at: tmpZip)
            try FileManager.default.moveItem(at: downloadedURL, to: tmpZip)
        } catch {
            throw ThunderstoreError.downloadFailed(error.localizedDescription)
        }

        // Wipe any prior copy of this package (any version) before extracting,
        // so updates don't leave stale files behind.
        Self.removeExistingVersions(of: version, in: packagesRoot)
        try? FileManager.default.removeItem(at: destination)

        do {
            try ZipExtractor.extract(tmpZip, to: destination)
        } catch {
            throw ThunderstoreError.extractFailed(error.localizedDescription)
        }
        Log.ok("thunderstore.install", "Installed \(version.fullName) → packages/")

        // Recursively install declared dependencies. Fetch the Thunderstore
        // package list at most once and pass it down the recursion so a deep
        // dependency tree doesn't trigger multiple multi-MB downloads.
        if resolveDependencies, !version.dependencies.isEmpty {
            var seen = installedPackages
            seen.insert(version.fullName)
            let packages: [ThunderstorePackage]
            if let cached = packageCache {
                packages = cached
            } else {
                packages = (try? await listPackages()) ?? []
            }
            try await installDependencies(
                version.dependencies,
                into: gameRoot,
                alreadyInstalled: seen,
                packageCache: packages
            )
        }
    }

    /// Remove any older `<package_basename>-x.y.z/` folders so we don't leave
    /// duplicate copies that Northstar would double-load.
    private nonisolated static func removeExistingVersions(
        of version: ThunderstoreVersion, in packagesRoot: URL
    ) {
        // `full_name` is "<author>-<modname>-<version>". Strip the trailing
        // version to get the package's stable prefix.
        let parts = version.fullName.split(separator: "-")
        guard parts.count >= 2 else { return }
        let prefix = parts.dropLast().joined(separator: "-") + "-"

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: packagesRoot.path) else { return }
        for entry in entries where entry.hasPrefix(prefix) {
            // `Author-Mod-` also prefixes other packages (`Author-Mod-Extras-1.0.0`);
            // only a bare version number may follow.
            let remainder = entry.dropFirst(prefix.count)
            guard remainder.range(of: #"^\d+(\.\d+)*$"#, options: .regularExpression) != nil else {
                continue
            }
            let url = packagesRoot.appendingPathComponent(entry)
            try? fm.removeItem(at: url)
            Log.info("thunderstore.install", "Removed older version: \(entry)")
        }
    }

    /// Resolve `Author-ModName-x.y.z` dependency strings against the live
    /// Thunderstore listing and install each one. Northstar.Northstar itself
    /// is skipped — that's installed via the Northstar updater, not the mod
    /// installer.
    private func installDependencies(
        _ depStrings: [String],
        into gameRoot: URL,
        alreadyInstalled: Set<String>,
        packageCache: [ThunderstorePackage]
    ) async throws {
        let byOwnerName: [String: ThunderstorePackage] = Dictionary(
            uniqueKeysWithValues: packageCache.map { ("\($0.owner)-\($0.name)", $0) }
        )

        var seen = alreadyInstalled
        for dep in depStrings {
            // dep looks like "Author-ModName-1.2.3"
            let parts = dep.split(separator: "-")
            guard parts.count >= 2 else { continue }
            let key = parts.dropLast().joined(separator: "-")

            if key == "northstar-Northstar" { continue }
            if seen.contains(dep) { continue }
            seen.insert(dep)

            guard let pkg = byOwnerName[key], let latest = pkg.latest else {
                Log.warn("thunderstore.install", "Dependency not found on Thunderstore: \(dep)")
                continue
            }
            Log.info("thunderstore.install", "Installing dependency: \(latest.fullName)")
            try await install(
                latest,
                into: gameRoot,
                resolveDependencies: true,
                installedPackages: seen,
                packageCache: packageCache
            )
        }
    }

    // MARK: - Local zip install (drag & drop)

    /// Install a `.zip` from the user's disk. Used by drag-and-drop. The zip is
    /// expected to follow the Thunderstore layout: top-level `manifest.json`
    /// plus `mods/` (and optionally `plugins/`). The package folder is named
    /// after `manifest.name + manifest.version_number` when readable, falling
    /// back to the zip's basename when the manifest can't be parsed.
    public func installLocalZip(at zipURL: URL, into gameRoot: URL) async throws {
        guard GameFiles.isTitanfallRoot(gameRoot) else { throw ThunderstoreError.modsDirectoryMissing }
        let packagesRoot = Self.packagesRoot(in: gameRoot)
        try FileManager.default.createDirectory(
            at: packagesRoot, withIntermediateDirectories: true
        )

        let fallbackName = zipURL.deletingPathExtension().lastPathComponent
        let folderName = Self.manifestFolderName(in: zipURL) ?? fallbackName
        let destination = packagesRoot.appendingPathComponent(folderName, isDirectory: true)

        try? FileManager.default.removeItem(at: destination)
        do {
            try ZipExtractor.extract(zipURL, to: destination)
        } catch {
            throw ThunderstoreError.extractFailed(error.localizedDescription)
        }
        Log.ok("thunderstore.install", "Installed local zip → packages/\(folderName)")
    }

    /// `<name>-<version_number>` from the zip's `manifest.json`, or nil.
    nonisolated static func manifestFolderName(in zipURL: URL) -> String? {
        guard let data = ZipExtractor.read("manifest.json", in: zipURL) else { return nil }
        struct Manifest: Decodable {
            let name: String?
            let version_number: String?
        }
        guard let m = try? JSONDecoder().decode(Manifest.self, from: data),
              let name = m.name, !name.isEmpty
        else { return nil }
        if let v = m.version_number, !v.isEmpty { return "\(name)-\(v)" }
        return name
    }

    // MARK: - Enable / disable / uninstall

    /// Toggle a mod in `R2Northstar/enabledmods.json`, in Northstar's current
    /// versioned format; a legacy flat file is migrated on the way.
    public nonisolated func setEnabled(_ enabled: Bool, mod: InstalledMod, in gameRoot: URL) throws {
        let file = Self.enabledModsFile(in: gameRoot)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var map = EnabledMods.read(from: file)
        map.migrateLegacy(using: installedMods(in: gameRoot))
        map.set(mod.name, version: mod.version, enabled: enabled)
        try map.write(to: file)

        // Heal legacy dot-prefixed folders left over from earlier Draconis builds.
        let current = mod.folderURL.lastPathComponent
        if current.hasPrefix(".") {
            let parent = mod.folderURL.deletingLastPathComponent()
            let healed = parent.appendingPathComponent(String(current.dropFirst()))
            try? FileManager.default.moveItem(at: mod.folderURL, to: healed)
        }
    }

    /// Remove a mod. If it came from a package folder, remove the whole
    /// package (since `R2Northstar/packages/<full_name>/` is atomic — its
    /// `mods/`, `plugins/`, and manifest are co-installed). Otherwise just
    /// remove the loose folder under `R2Northstar/mods/`.
    public nonisolated func uninstall(_ mod: InstalledMod) throws {
        if let packageID = mod.thunderstoreID {
            // mod.folderURL is .../packages/<full_name>/mods/<ModName>/.
            // Walk back up to the package root.
            var url = mod.folderURL
            while url.lastPathComponent != packageID && url.pathComponents.count > 1 {
                url = url.deletingLastPathComponent()
            }
            try FileManager.default.removeItem(at: url)
        } else {
            try FileManager.default.removeItem(at: mod.folderURL)
        }
    }
}
