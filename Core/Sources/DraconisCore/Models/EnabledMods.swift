import Foundation

/// `R2Northstar/enabledmods.json`. Northstar's current format (`"Version": 1`)
/// is `{"Version":1,"Mod.Name":{"1.2.3":true}}`; the legacy flat format
/// `{"Mod.Name":true}` is migrated by Northstar at startup.
public struct EnabledMods: Equatable, Sendable {
    public var versioned: [String: [String: Bool]] = [:]
    public var legacy: [String: Bool] = [:]

    public init() {}

    public static func read(from url: URL) -> EnabledMods {
        guard let data = try? Data(contentsOf: url) else { return EnabledMods() }
        return parse(data)
    }

    public static func parse(_ data: Data) -> EnabledMods {
        var result = EnabledMods()
        guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return result }
        let isV1 = (raw["Version"] as? NSNumber)?.intValue == 1
        for (key, value) in raw where key != "Version" {
            if isV1, let versions = value as? [String: Any] {
                result.versioned[key] = versions.compactMapValues { ($0 as? NSNumber)?.boolValue }
            } else if let flag = value as? NSNumber {
                result.legacy[key] = flag.boolValue
            }
        }
        return result
    }

    public func isEnabled(_ name: String, version: String) -> Bool? {
        if let versions = versioned[name] {
            return versions[version] ?? versions.values.first
        }
        return legacy[name]
    }

    public mutating func set(_ name: String, version: String, enabled: Bool) {
        versioned[name, default: [:]][version] = enabled
        legacy[name] = nil
    }

    /// Carry flat entries over to the versioned format using installed versions.
    public mutating func migrateLegacy(using mods: [InstalledMod]) {
        for (name, flag) in legacy {
            for mod in mods where mod.name == name {
                versioned[name, default: [:]][mod.version] = flag
            }
        }
        legacy.removeAll()
    }

    public func write(to url: URL) throws {
        var object: [String: Any] = ["Version": 1]
        for (name, versions) in versioned { object[name] = versions }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
