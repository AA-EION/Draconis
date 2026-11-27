import Foundation

/// What a Titanfall 2 folder contains, whatever platform or runner holds it.
public enum GameFiles {
    public static func isTitanfallRoot(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("Titanfall2.exe").path)
    }

    public static func hasNorthstar(in root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent("NorthstarLauncher.exe").path)
    }

    /// Northstar's core mods, stamped with the release version.
    public static let coreMods = ["Northstar.Client", "Northstar.Custom", "Northstar.CustomServers"]

    /// Installed Northstar version: `Version` in Northstar.Client's mod.json
    /// (releases don't ship `ns_version.txt`; older Draconis builds wrote it).
    public static func northstarVersion(in root: URL) -> String? {
        let manifest = root.appendingPathComponent("R2Northstar/mods/Northstar.Client/mod.json")
        struct Manifest: Decodable { let Version: String? }
        if let data = try? Data(contentsOf: manifest),
           let version = (try? JSONDecoder().decode(Manifest.self, from: data))?.Version,
           !version.isEmpty {
            return version
        }
        guard let raw = try? String(contentsOf: root.appendingPathComponent("ns_version.txt"), encoding: .utf8)
        else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Northstar writes `1.30.0`; GitHub tags are `v1.30.0`.
    public static func versionsMatch(installed: String?, releaseTag: String) -> Bool {
        guard let installed else { return false }
        return stripV(installed) == stripV(releaseTag)
    }

    static func stripV(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.lowercased().hasPrefix("v") ? String(t.dropFirst()) : t
    }

    /// Files and folders the Northstar release zip adds to the game root.
    public static let northstarPaths = [
        "NorthstarLauncher.exe",
        "Northstar.dll",
        "r2_nsmod_loader.dll",
        "ns_version.txt",
        "ns_startup_args.txt",
        "ns_startup_args_dedi.txt",
        "R2Northstar",
        "bin/x64_retail/wsock32.dll",
        "bin/x64_dedi/wsock32.dll",
    ]

    /// Find Titanfall2.exe under `root`: known install folders first, then a
    /// depth-limited search.
    public static func locateTitanfall2(under root: URL, knownSubpaths: [String] = defaultSubpaths) -> URL? {
        for sub in knownSubpaths {
            let candidate = root.appendingPathComponent(sub)
            if isTitanfallRoot(candidate) { return candidate }
        }
        return search(for: "Titanfall2.exe", under: root, maxDepth: 5)?.deletingLastPathComponent()
    }

    public static let defaultSubpaths = [
        "Program Files (x86)/Origin Games/Titanfall2",
        "Program Files (x86)/Steam/steamapps/common/Titanfall2",
        "Program Files (x86)/EA Games/Titanfall2",
        "Program Files/Origin Games/Titanfall2",
        "Program Files/EA Games/Titanfall2",
        "Program Files/Titanfall2",
        "Games/Titanfall2",
        "Titanfall2",
    ]

    static func search(for filename: String, under root: URL, maxDepth: Int, nodeCap: Int = 50_000) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }
        var visited = 0
        let rootDepth = root.pathComponents.count
        while let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited > nodeCap { return nil }
            if url.pathComponents.count - rootDepth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if url.lastPathComponent == filename { return url }
        }
        return nil
    }
}
