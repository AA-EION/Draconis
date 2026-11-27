import Foundation

/// Reuses the prefix the Heroic Games Launcher (macOS) set up for its Epic copy
/// of Titanfall 2. Heroic installs the EA app there and the EA app installs the
/// game, so the prefix is a complete Titanfall 2 bottle.
public enum HeroicImporter {
    public enum Source: Equatable, Sendable {
        /// Heroic runs the game in a CrossOver bottle, which Draconis already lists.
        case crossOverBottle(String)
        /// Heroic runs it in a plain Wine prefix.
        case prefix(URL)
    }

    public enum ImportError: Error, LocalizedError {
        case notFound
        case prefixMissing(String)
        case nameTaken(String)

        public var errorDescription: String? {
            switch self {
            case .notFound:
                return "Heroic doesn't have Titanfall 2 (Epic) set up on this Mac."
            case .prefixMissing(let path):
                return "Heroic's Wine prefix for Titanfall 2 isn't at \(path) anymore."
            case .nameTaken(let name):
                return "A Draconis prefix named \"\(name)\" already exists."
            }
        }
    }

    static var heroicRoot: URL {
        PathResolver.applicationSupport.appendingPathComponent("heroic", isDirectory: true)
    }

    /// Where Heroic keeps Titanfall 2, if it does.
    public static func detect() -> Source? {
        let config = heroicRoot.appendingPathComponent("GamesConfig/\(EpicService.titanfallAppName).json")
        guard let data = try? Data(contentsOf: config),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let game = root[EpicService.titanfallAppName] as? [String: Any]
        else { return nil }

        let wine = game["wineVersion"] as? [String: Any]
        if (wine?["type"] as? String) == "crossover",
           let bottle = game["wineCrossoverBottle"] as? String, !bottle.isEmpty {
            return .crossOverBottle(bottle)
        }
        guard var path = game["winePrefix"] as? String, !path.isEmpty else { return nil }
        if path.hasPrefix("~") { path = PathResolver.home.path + path.dropFirst() }
        return .prefix(URL(fileURLWithPath: path, isDirectory: true))
    }

    /// Make Heroic's prefix a Draconis prefix by linking it into the Prefixes
    /// folder; Heroic's copy stays where it is and keeps working in Heroic.
    /// Returns the bottle name to select.
    public static func importTitanfall(as name: String = "Titanfall 2 (Heroic)") throws -> String {
        guard let source = detect() else { throw ImportError.notFound }
        switch source {
        case .crossOverBottle(let bottle):
            return bottle
        case .prefix(let prefix):
            guard FileManager.default.fileExists(atPath: PathResolver.driveC(in: prefix).path) else {
                throw ImportError.prefixMissing(prefix.path)
            }
            let link = WineEngine.prefixURL(named: name)
            guard !FileManager.default.fileExists(atPath: link.path) else { throw ImportError.nameTaken(name) }
            try FileManager.default.createDirectory(at: WineEngine.prefixesRoot, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: prefix)
            return name
        }
    }
}
