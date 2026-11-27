import Foundation

extension VDF {
    /// Valve's text format, tab-indented like Steam writes it.
    public func serialized(indent: Int = 0) -> String {
        guard case .object(let pairs) = self else { return "" }
        let tabs = String(repeating: "\t", count: indent)
        var out = ""
        for (key, value) in pairs {
            switch value {
            case .string(let s): out += "\(tabs)\"\(Self.escape(key))\"\t\t\"\(Self.escape(s))\"\n"
            case .object: out += "\(tabs)\"\(Self.escape(key))\"\n\(tabs){\n\(value.serialized(indent: indent + 1))\(tabs)}\n"
            }
        }
        return out
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
    }

    /// Set a string at a key path, creating objects on the way; keys match
    /// case-insensitively like Steam's.
    public mutating func set(_ path: [String], _ value: String) {
        guard let first = path.first, case .object(var pairs) = self else { return }
        let index = pairs.firstIndex { $0.key.caseInsensitiveCompare(first) == .orderedSame }
        if path.count == 1 {
            if let index { pairs[index].value = .string(value) } else { pairs.append((first, .string(value))) }
        } else {
            var child: VDF = index.map { pairs[$0].value } ?? .object([])
            if case .string = child { child = .object([]) }
            child.set(Array(path.dropFirst()), value)
            if let index { pairs[index].value = child } else { pairs.append((first, child)) }
        }
        self = .object(pairs)
    }
}

/// Titanfall 2's Steam launch options. Northstar's `wsock32.dll` proxy only
/// loads when Wine prefers the native DLL; Proton's builtin one ignores
/// `-northstar` and the game starts vanilla (Northstar issue #291).
public enum SteamLaunchOptions {
    public static let override = #"WINEDLLOVERRIDES="wsock32=n,b""#

    /// The options with the override added, or nil when they already have it.
    public static func withNorthstarOverride(_ options: String) -> String? {
        let trimmed = options.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("wsock32=n") { return nil }
        if trimmed.isEmpty { return "\(override) %command%" }
        // Plain arguments: Steam appends them to the game's command line.
        guard trimmed.contains("%command%") else { return "\(override) %command% \(trimmed)" }
        return "\(override) \(trimmed)"
    }

    static func path(appID: String) -> [String] {
        ["UserLocalConfigStore", "Software", "Valve", "Steam", "apps", appID, "LaunchOptions"]
    }
}

extension SteamInstall {
    /// Every Steam account's local config (`userdata/<id>/config/localconfig.vdf`).
    public func localConfigs() -> [URL] {
        let userdata = root.appendingPathComponent("userdata", isDirectory: true)
        let accounts = (try? FileManager.default.contentsOfDirectory(atPath: userdata.path)) ?? []
        return accounts.filter { $0.allSatisfy(\.isNumber) && $0 != "0" }
            .map { userdata.appendingPathComponent("\($0)/config/localconfig.vdf") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Accounts whose launch options for the app still lack the override.
    public func configsNeedingNorthstarOverride(appID: String) -> [URL] {
        localConfigs().filter { url in
            guard let vdf = VDF.load(url) else { return false }
            let current = vdf[SteamLaunchOptions.path(appID: appID)]?.string ?? ""
            return SteamLaunchOptions.withNorthstarOverride(current) != nil
        }
    }

    /// Add the override to every account's launch options. Steam must be
    /// closed: it rewrites localconfig.vdf on exit. Keeps a backup.
    @discardableResult
    public func addNorthstarOverride(appID: String) throws -> Int {
        var changed = 0
        for url in localConfigs() {
            guard var vdf = VDF.load(url) else { continue }
            let path = SteamLaunchOptions.path(appID: appID)
            let current = vdf[path]?.string ?? ""
            guard let updated = SteamLaunchOptions.withNorthstarOverride(current) else { continue }
            let backup = url.appendingPathExtension("draconis-backup")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.copyItem(at: url, to: backup)
            vdf.set(path, updated)
            try vdf.serialized().write(to: url, atomically: true, encoding: .utf8)
            Log.ok("steam", "Launch options for \(appID) in \(url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent): \(updated)")
            changed += 1
        }
        return changed
    }
}
