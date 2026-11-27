import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// CircuitLord's Titanfall 2 VR mod (OpenXR, closed source, not redistributable),
/// installed the way his CircuitLordVRModInstaller does: downloaded from his
/// manifest with its checksums into a separate `TF2VR` Northstar profile, so
/// the normal game and the user's Northstar stay untouched.
public enum TitanfallVR {
    public static let manifestURL = URL(string: "https://raw.githubusercontent.com/CircuitLord/CircuitLordVRModInstaller/main/manifest-v3.json")!
    static let installerRaw = "https://raw.githubusercontent.com/CircuitLord/CircuitLordVRModInstaller"
    public static let profile = "TF2VR"
    public static let launcher = "Titanfall2VRLauncher.exe"
    public static let recordFile = ".draconis-vr.json"

    public struct Package: Codable, Equatable, Sendable {
        public var version: String
        public var url: URL
        public var sha256: String
    }

    public struct Release: Equatable, Sendable {
        public var mod: Package
        public var northstar: Package
    }

    public struct Record: Codable, Equatable, Sendable {
        public var version: String
        public var northstarVersion: String
        public var files: [String]
    }

    public enum VRError: Error, LocalizedError {
        case manifest(String)
        case checksum(String)
        case missing(String)
        case assets(String)
        case audioFix(String)

        public var errorDescription: String? {
            switch self {
            case .manifest(let detail): return "Couldn't read the Titanfall 2 VR release list: \(detail)"
            case .checksum(let file): return "\(file) didn't match its published checksum, so it wasn't installed."
            case .missing(let file): return "The Titanfall 2 VR download is missing \(file)."
            case .assets(let detail): return "Building the VR mod's game assets failed: \(detail)"
            case .audioFix(let detail): return "Couldn't apply the Linux audio fix to this mod version (\(detail)). Draconis needs an update for it."
            }
        }
    }

    /// Hashes a file (SHA-256 hex); supplied by each platform.
    public typealias Hasher = @Sendable (URL) throws -> String

    // MARK: - Release

    /// The current mod release and the Northstar build its installer pins
    /// (read from the installer source at the manifest's commit).
    public static func latest(channel: String = "stable") async throws -> Release {
        var request = URLRequest(url: URL(string: manifestURL.absoluteString + "?t=\(Int(Date().timeIntervalSince1970))")!)
        request.setValue("Draconis-Launcher", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tf = json["titanfall2vr"] as? [String: Any],
              let commit = (json["installer"] as? [String: Any])?["commit"] as? String
        else { throw VRError.manifest("unexpected format") }
        var entry = tf
        if channel != "stable" {
            guard let match = (tf["channels"] as? [[String: Any]])?.first(where: { $0["id"] as? String == channel })
            else { throw VRError.manifest("no \(channel) channel") }
            entry = match
        }
        guard let version = entry["version"] as? String, let urlString = entry["url"] as? String,
              let url = URL(string: urlString), let sha = entry["sha256"] as? String
        else { throw VRError.manifest("no Titanfall 2 VR entry") }
        let sourceURL = URL(string: "\(installerRaw)/\(commit)/src/Installer/Installers/Titanfall2Installer.cs")!
        let (source, _) = try await URLSession.shared.data(from: sourceURL)
        let northstar = try northstarPin(in: String(decoding: source, as: UTF8.self))
        return Release(mod: Package(version: version, url: url, sha256: sha.lowercased()), northstar: northstar)
    }

    static func northstarPin(in source: String) throws -> Package {
        func constant(_ name: String) -> String? {
            guard let range = source.range(of: #"\#(name)\s*=\s*"([^"]+)""#, options: .regularExpression) else { return nil }
            let match = source[range]
            return match.split(separator: "\"").dropFirst().first.map(String.init)
        }
        guard let version = constant("NorthstarVersion"), let urlString = constant("NorthstarUrl"),
              let url = URL(string: urlString), let sha = constant("NorthstarSha256")
        else { throw VRError.manifest("no Northstar pin in the installer source") }
        return Package(version: version, url: url, sha256: sha.lowercased())
    }

    // MARK: - Install

    /// Staging area beside the game, so built assets move in without copying.
    public static func stage(in gameRoot: URL) -> URL {
        gameRoot.appendingPathComponent(".draconis-vr-stage", isDirectory: true)
    }

    /// Download, verify and unpack both packages into the stage.
    public static func stage(_ release: Release, gameRoot: URL, hasher: Hasher,
                             progress: DownloadCoordinator.ProgressHandler? = nil) async throws -> URL {
        let stage = stage(in: gameRoot)
        try? FileManager.default.removeItem(at: stage)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        for (package, name) in [(release.mod, "mod"), (release.northstar, "ns")] {
            let zip = CorePaths.downloads.appendingPathComponent("\(name == "mod" ? "Titanfall2VR" : "Northstar")-\(package.version).zip")
            if (try? hasher(zip)) != package.sha256 {
                try? FileManager.default.removeItem(at: zip)
                let downloaded = try await DownloadCoordinator.download(from: package.url, progress: progress)
                try FileManager.default.moveItem(at: downloaded, to: zip)
                guard try hasher(zip) == package.sha256 else {
                    try? FileManager.default.removeItem(at: zip)
                    throw VRError.checksum(zip.lastPathComponent)
                }
            }
            try ZipExtractor.extract(zip, to: stage.appendingPathComponent(name, isDirectory: true))
        }
        for file in ["mod/Titanfall2VR.dll", "mod/xr_probe.exe", "mod/crash_monitor.exe", "mod/launch.json",
                     "mod/asset_patcher.exe", "mod/patches/manifest.json", "ns/NorthstarLauncher.exe", "ns/R2Northstar/Northstar.dll"]
        where !FileManager.default.fileExists(atPath: stage.appendingPathComponent(file).path) {
            throw VRError.missing(file)
        }
        return stage
    }

    /// `asset_patcher.exe apply <game> <patches> <assets>`: builds the mod's
    /// game-derived files from the installed game.
    public static func assetPatcherArguments(gameRoot: URL, stage: URL, path: (URL) -> String = { $0.path }) -> [String] {
        ["apply", path(gameRoot), path(stage.appendingPathComponent("mod/patches")), path(stage.appendingPathComponent("assets"))]
    }

    /// Every built file must match the patch manifest.
    public static func verifyAssets(stage: URL, hasher: Hasher) throws {
        let manifest = stage.appendingPathComponent("mod/patches/manifest.json")
        guard let json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any],
              let outputs = json["outputs"] as? [String: String]
        else { throw VRError.assets("unreadable patch manifest") }
        let assets = stage.appendingPathComponent("assets")
        let bad = outputs.filter { rel, sha in (try? hasher(assets.appendingPathComponent(rel))) != sha.lowercased() }
        if let first = bad.keys.sorted().first {
            throw VRError.assets("\(bad.count) of \(outputs.count) files are missing or wrong, e.g. \(first)")
        }
    }

    /// Move the staged files into the game folder, in the official layout, and
    /// drop the files an earlier version installed that this one doesn't.
    public static func place(stage: URL, release: Release, gameRoot: URL) throws {
        let fm = FileManager.default
        var written: [String] = []
        func put(_ source: URL, _ relative: String) throws {
            let destination = gameRoot.appendingPathComponent(relative)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: source, to: destination)
            written.append(relative)
        }
        func putTree(_ root: URL, _ prefix: String) throws {
            guard fm.fileExists(atPath: root.path),
                  let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
            let base = root.standardizedFileURL.path
            for case let file as URL in walker where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                let rel = String(file.standardizedFileURL.path.dropFirst(base.count + 1))
                try put(file, "\(prefix)/\(rel)")
            }
        }
        let mod = stage.appendingPathComponent("mod"), ns = stage.appendingPathComponent("ns")
        try put(ns.appendingPathComponent("NorthstarLauncher.exe"), launcher)
        try putTree(ns.appendingPathComponent("R2Northstar"), profile)
        try put(mod.appendingPathComponent("Titanfall2VR.dll"), "\(profile)/plugins/Titanfall2VR.dll")
        for tool in ["xr_probe.exe", "crash_monitor.exe", "launch.json", "steam_api64.dll"]
        where fm.fileExists(atPath: mod.appendingPathComponent(tool).path) {
            try put(mod.appendingPathComponent(tool), "\(profile)/tools/\(tool)")
        }
        try putTree(mod.appendingPathComponent("mods"), "\(profile)/mods")
        try putTree(mod.appendingPathComponent("licenses"), "\(profile)/licenses")
        for doc in ["LICENSE.txt", "THIRD_PARTY_NOTICES.md"] where fm.fileExists(atPath: mod.appendingPathComponent(doc).path) {
            try put(mod.appendingPathComponent(doc), "\(profile)/\(doc)")
        }
        try putTree(stage.appendingPathComponent("assets"), profile)

        let current = Set(written)
        for stale in record(in: gameRoot)?.files ?? [] where !current.contains(stale) && !stale.contains("..") {
            try? fm.removeItem(at: gameRoot.appendingPathComponent(stale))
        }
        let record = Record(version: release.mod.version, northstarVersion: release.northstar.version, files: written.sorted())
        try JSONEncoder().encode(record).write(to: gameRoot.appendingPathComponent("\(profile)/\(recordFile)"))
        try? fm.removeItem(at: stage)
    }

    public static func record(in gameRoot: URL) -> Record? {
        guard let data = try? Data(contentsOf: gameRoot.appendingPathComponent("\(profile)/\(recordFile)")) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    public static func isInstalled(in gameRoot: URL) -> Bool {
        guard record(in: gameRoot) != nil else { return false }
        return [launcher, "\(profile)/Northstar.dll", "\(profile)/plugins/Titanfall2VR.dll",
                "\(profile)/tools/crash_monitor.exe", "\(profile)/tools/launch.json"]
            .allSatisfy { FileManager.default.fileExists(atPath: gameRoot.appendingPathComponent($0).path) }
    }

    /// Remove every file the install recorded, and the profile's leftovers.
    public static func uninstall(from gameRoot: URL) {
        let fm = FileManager.default
        for file in record(in: gameRoot)?.files ?? [] where !file.contains("..") {
            try? fm.removeItem(at: gameRoot.appendingPathComponent(file))
        }
        try? fm.removeItem(at: gameRoot.appendingPathComponent(profile))
        try? fm.removeItem(at: gameRoot.appendingPathComponent(launcher))
        try? fm.removeItem(at: stage(in: gameRoot))
    }

    // MARK: - Launch

    /// Arguments for `Titanfall2VRLauncher.exe`, from the mod's launch.json,
    /// filled in like the official installer.
    public static func launchArguments(gameRoot: URL) throws -> [String] {
        let file = gameRoot.appendingPathComponent("\(profile)/tools/launch.json")
        guard let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any],
              let args = json["arguments"] as? [String]
        else { throw VRError.missing("TF2VR/tools/launch.json") }
        return (args + (json["vrArguments"] as? [String] ?? [])).map {
            $0.replacingOccurrences(of: "{profile}", with: profile).replacingOccurrences(of: "{width}", with: "1280")
                .replacingOccurrences(of: "{height}", with: "720").replacingOccurrences(of: "{sound}", with: "1")
        }
    }

    /// DirectX replacement DLLs from other mods take Present away from VR rendering.
    public static func directXReplacements(in gameRoot: URL) -> [URL] {
        ["", "bin/x64_retail/"].flatMap { dir in ["dxgi.dll", "d3d11.dll"].map { gameRoot.appendingPathComponent(dir + $0) } }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Environment for the VR process: the mod reads TF2VR_OPENXR, and stale
    /// OpenVR/OpenXR overrides would point it at the wrong runtime.
    public static func environment(_ base: [String: String]) -> [String: String] {
        var env = base.filter { key, _ in
            !key.uppercased().hasPrefix("TF2VR_") && !["VR_PATHREG_OVERRIDE", "VR_CONFIG_PATH", "VR_LOG_PATH", "XR_RUNTIME_JSON"].contains(key)
        }
        env["TF2VR_OPENXR"] = "1"
        return env
    }
}
