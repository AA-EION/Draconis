import Foundation

/// Talks to https://northstar.thunderstore.io/api/v1/package/ to list mods.
/// Also handles install/uninstall against a given bottle's R2Northstar tree.
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
            case .modsDirectoryMissing:     return "Titanfall 2 isn't installed in this bottle, so there's nowhere to put mods."
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

    /// `R2Northstar/mods/` inside a bottle, or nil if Titanfall 2 isn't installed.
    private nonisolated static func modsRoot(in bottle: WineBottle) -> URL? {
        guard let tf2 = bottle.titanfall2InstallPath else { return nil }
        return URL(fileURLWithPath: tf2)
            .appendingPathComponent("R2Northstar", isDirectory: true)
            .appendingPathComponent("mods", isDirectory: true)
    }

    /// `R2Northstar/packages/` inside a bottle, or nil if Titanfall 2 isn't installed.
    private nonisolated static func packagesRoot(in bottle: WineBottle) -> URL? {
        guard let tf2 = bottle.titanfall2InstallPath else { return nil }
        return URL(fileURLWithPath: tf2)
            .appendingPathComponent("R2Northstar", isDirectory: true)
            .appendingPathComponent("packages", isDirectory: true)
    }

    /// `R2Northstar/enabledmods.json` — Northstar's source of truth for which
    /// mods are loaded. A simple `{ "Mod.Name": true|false }` map.
    private nonisolated static func enabledModsFile(in bottle: WineBottle) -> URL? {
        guard let tf2 = bottle.titanfall2InstallPath else { return nil }
        return URL(fileURLWithPath: tf2)
            .appendingPathComponent("R2Northstar", isDirectory: true)
            .appendingPathComponent("enabledmods.json")
    }

    // MARK: - Installed mods (nonisolated — pure FileManager reads)

    /// Read every mod Northstar would load in this bottle: the legacy
    /// `R2Northstar/mods/<ModName>/` layout *and* the modern
    /// `R2Northstar/packages/<full_name>/mods/<ModName>/` layout.
    public nonisolated func installedMods(in bottle: WineBottle) -> [InstalledMod] {
        let enabled = readEnabledMods(in: bottle)
        var results: [InstalledMod] = []

        // Legacy: R2Northstar/mods/<ModName>/
        if let modsRoot = Self.modsRoot(in: bottle) {
            for url in subdirectories(of: modsRoot) {
                guard let mod = Self.readMod(at: url, enabledMap: enabled, packageID: nil) else { continue }
                results.append(mod)
            }
        }

        // Modern: R2Northstar/packages/<full_name>/mods/<ModName>/
        if let packagesRoot = Self.packagesRoot(in: bottle) {
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
        enabledMap: [String: Bool],
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

        // Enabled status:
        //   1. enabledmods.json wins if it has an entry for this Name
        //   2. otherwise, dot-prefix folder is treated as disabled (legacy)
        //   3. default: enabled
        let isEnabled: Bool
        if let explicit = enabledMap[modName] {
            isEnabled = explicit
        } else {
            isEnabled = !name.hasPrefix(".")
        }

        return InstalledMod(
            id: packageID.map { "\($0)/\(name)" } ?? name,
            name: modName,
            version: manifest?.Version ?? "—",
            enabled: isEnabled,
            folderURL: folder,
            thunderstoreID: packageID
        )
    }

    /// Read `R2Northstar/enabledmods.json` — silent fallback to empty if missing/corrupt.
    private nonisolated func readEnabledMods(in bottle: WineBottle) -> [String: Bool] {
        guard let file = Self.enabledModsFile(in: bottle),
              let data = try? Data(contentsOf: file),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }

        var out: [String: Bool] = [:]
        for (k, v) in raw {
            if let b = v as? Bool { out[k] = b }
            else if let n = v as? NSNumber { out[k] = n.boolValue }
        }
        return out
    }

    // MARK: - Install / extract

    /// Install a Thunderstore version into the bottle.
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
        into bottle: WineBottle,
        resolveDependencies: Bool = true,
        installedPackages: Set<String> = [],
        packageCache: [ThunderstorePackage]? = nil
    ) async throws {
        guard let packagesRoot = Self.packagesRoot(in: bottle) else {
            throw ThunderstoreError.modsDirectoryMissing
        }
        try FileManager.default.createDirectory(
            at: packagesRoot, withIntermediateDirectories: true
        )

        let destination = packagesRoot.appendingPathComponent(version.fullName, isDirectory: true)
        let tmpZip = PathResolver.downloadsCache.appendingPathComponent(
            "\(version.fullName).zip"
        )

        Log.info("thunderstore.install", "Downloading \(version.fullName)")
        do {
            let (downloadedURL, _) = try await session.download(from: version.downloadURL)
            try? FileManager.default.removeItem(at: tmpZip)
            try FileManager.default.moveItem(at: downloadedURL, to: tmpZip)
        } catch {
            throw ThunderstoreError.downloadFailed(error.localizedDescription)
        }

        // Wipe any prior copy of this package (any version) before extracting,
        // so updates don't leave stale files behind.
        Self.removeExistingVersions(of: version, in: packagesRoot)
        try? FileManager.default.removeItem(at: destination)

        Log.run("thunderstore.install", "ditto -x -k \(tmpZip.path) \(destination.path)")
        let result = try await ProcessRunner.shared.capture(
            URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", tmpZip.path, destination.path]
        )
        if !result.ok {
            throw ThunderstoreError.extractFailed(result.stderr)
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
                into: bottle,
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
        into bottle: WineBottle,
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
                into: bottle,
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
    public func installLocalZip(at zipURL: URL, into bottle: WineBottle) async throws {
        guard let packagesRoot = Self.packagesRoot(in: bottle) else {
            throw ThunderstoreError.modsDirectoryMissing
        }
        try FileManager.default.createDirectory(
            at: packagesRoot, withIntermediateDirectories: true
        )

        let fallbackName = zipURL.deletingPathExtension().lastPathComponent
        let folderName = (try? await peekManifestFolderName(in: zipURL)) ?? fallbackName
        let destination = packagesRoot.appendingPathComponent(folderName, isDirectory: true)

        try? FileManager.default.removeItem(at: destination)
        let result = try await ProcessRunner.shared.capture(
            URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", zipURL.path, destination.path]
        )
        if !result.ok {
            throw ThunderstoreError.extractFailed(result.stderr)
        }
        Log.ok("thunderstore.install", "Installed local zip → packages/\(folderName)")
    }

    /// Stream `manifest.json` out of a zip via `unzip -p` and derive a
    /// `<Name>-<VersionNumber>` folder label. Returns nil when the zip has no
    /// manifest or the fields are missing — the caller falls back to the zip
    /// basename.
    private func peekManifestFolderName(in zipURL: URL) async throws -> String? {
        let result = try await ProcessRunner.shared.capture(
            URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-p", zipURL.path, "manifest.json"]
        )
        guard result.ok, let data = result.stdout.data(using: .utf8) else { return nil }

        struct Manifest: Decodable {
            let name: String?
            let version_number: String?
        }
        guard let m = try? JSONDecoder().decode(Manifest.self, from: data),
              let name = m.name, !name.isEmpty
        else { return nil }

        if let v = m.version_number, !v.isEmpty {
            return "\(name)-\(v)"
        }
        return name
    }

    // MARK: - Enable / disable / uninstall

    /// Toggle a mod's enabled state by writing to `R2Northstar/enabledmods.json`
    /// (Northstar's standard file). We never rename folders any more — that was
    /// a holdover that fought with the in-game mods menu.
    public nonisolated func setEnabled(_ enabled: Bool, mod: InstalledMod, in bottle: WineBottle) throws {
        guard let file = Self.enabledModsFile(in: bottle) else { return }

        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var map: [String: Any] = [:]
        if let data = try? Data(contentsOf: file),
           let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            map = raw
        }
        map[mod.name] = enabled

        let data = try JSONSerialization.data(
            withJSONObject: map, options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: file, options: .atomic)

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
