import DraconisCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Crypto)
import Crypto
#endif

/// Tools Draconis fetches for Linux: umu-launcher and GE-Proton.
public enum RunnerDownloads {
    public enum DownloadError: Error, LocalizedError {
        case checksum(String)
        case noAsset(String)
        case command(String, Int32)

        public var errorDescription: String? {
            switch self {
            case .checksum(let f): return "\(f) didn't match its published checksum; it was discarded."
            case .noAsset(let s):  return "Couldn't find a download for \(s)."
            case .command(let c, let code): return "\(c) failed (exit \(code))."
            }
        }
    }

    // umu-launcher, pinned.
    public static let umuVersion = "1.4.4"
    static let umuURL = URL(string: "https://github.com/Open-Wine-Components/umu-launcher/releases/download/1.4.4/umu-launcher-1.4.4-zipapp.tar")!
    static let umuSHA256 = "eb590691841f7fad3fc3ad8fd5db4ccb87849fe7948e62b28ece7a4ee48cc851"

    public static var umuDirectory: URL { CorePaths.directory("Tools").appendingPathComponent("umu", isDirectory: true) }

    /// umu-run: the system's, else the copy Draconis installed.
    public static func umuRun() -> URL? {
        if let system = Executables.find("umu-run") { return system }
        let local = umuDirectory.appendingPathComponent("umu-run")
        return FileManager.default.isExecutableFile(atPath: local.path) ? local : nil
    }

    public static func installUmu(progress: DownloadCoordinator.ProgressHandler? = nil) async throws -> URL {
        let archive = try await DownloadCoordinator.download(from: umuURL, progress: progress)
        defer { try? FileManager.default.removeItem(at: archive) }
        guard try sha256(of: archive) == umuSHA256 else { throw DownloadError.checksum("umu-launcher") }
        let tools = CorePaths.directory("Tools")
        try? FileManager.default.removeItem(at: umuDirectory)
        try await Spawner.run("/usr/bin/env", ["tar", "-xf", archive.path, "-C", tools.path])
        Log.ok("runners", "Installed umu-launcher \(umuVersion)")
        return umuDirectory.appendingPathComponent("umu-run")
    }

    // MARK: GE-Proton

    public struct Release: Sendable {
        public var tag: String
        public var tarball: URL
        public var checksum: URL
    }

    public static func latestGEProton() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Draconis-Launcher", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        struct Raw: Decodable {
            let tag_name: String
            let assets: [Asset]
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        #if arch(arm64)
        let arch = "aarch64"
        #else
        let arch = "x86_64"
        #endif
        // From 11.x assets carry the arch; earlier ones are just <tag>.
        for base in ["\(raw.tag_name)-\(arch)", raw.tag_name] {
            if let tar = raw.assets.first(where: { $0.name == "\(base).tar.gz" }),
               let sum = raw.assets.first(where: { $0.name == "\(base).sha512sum" }) {
                return Release(tag: raw.tag_name, tarball: tar.browser_download_url, checksum: sum.browser_download_url)
            }
        }
        throw DownloadError.noAsset(raw.tag_name)
    }

    /// Where downloaded Protons go, so Steam and umu see them too.
    public static var compatibilityTools: URL {
        let env = ProcessInfo.processInfo.environment
        let data = env["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? CorePaths.home.appendingPathComponent(".local/share")
        return data.appendingPathComponent("Steam/compatibilitytools.d", isDirectory: true)
    }

    public static func installGEProton(_ release: Release, progress: DownloadCoordinator.ProgressHandler? = nil) async throws -> URL {
        let (sumData, _) = try await URLSession.shared.data(from: release.checksum)
        let name = release.tarball.lastPathComponent
        let expected = String(decoding: sumData, as: UTF8.self)
            .split(separator: "\n")
            .first { $0.hasSuffix(name) }?
            .split(separator: " ").first.map(String.init)
        guard let expected else { throw DownloadError.noAsset("\(name) checksum") }

        let archive = try await DownloadCoordinator.download(from: release.tarball, progress: progress)
        defer { try? FileManager.default.removeItem(at: archive) }
        guard try sha512(of: archive) == expected.lowercased() else { throw DownloadError.checksum(name) }

        let dest = compatibilityTools
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try await Spawner.run("/usr/bin/env", ["tar", "-xzf", archive.path, "-C", dest.path])
        Log.ok("runners", "Installed \(release.tag)")
        let folder = String(name.dropLast(".tar.gz".count))
        return dest.appendingPathComponent(folder, isDirectory: true)
    }

    // MARK: Checksums

    public static func sha256(of url: URL) throws -> String {
        try digest(url, sha512: false)
    }

    public static func sha512(of url: URL) throws -> String {
        try digest(url, sha512: true)
    }

    static func digest(_ url: URL, sha512: Bool) throws -> String {
        #if canImport(Crypto)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var h512 = SHA512()
        var h256 = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            if sha512 { h512.update(data: chunk) } else { h256.update(data: chunk) }
        }
        let bytes: [UInt8] = sha512 ? Array(h512.finalize()) : Array(h256.finalize())
        return bytes.map { String(format: "%02x", $0) }.joined()
        #else
        throw DownloadError.checksum(url.lastPathComponent)
        #endif
    }
}
