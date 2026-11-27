import DraconisCore
import Foundation

/// Draconis-owned Wine prefixes: `<data>/Prefixes/<name>`. Nothing outside
/// this folder (and never `~/.wine`) is used as a prefix Draconis creates.
public enum PrefixStore {
    public static var root: URL { CorePaths.directory("Prefixes") }

    public static func url(named name: String) -> URL {
        root.appendingPathComponent(name, isDirectory: true)
    }

    public struct InvalidPrefix: Error, LocalizedError {
        public var path: String
        public var errorDescription: String? {
            "Refusing to create a prefix at \(path): it isn't inside Draconis's Prefixes folder."
        }
    }

    public static func validatedForCreation(_ prefix: URL) throws -> URL {
        let base = root.standardizedFileURL.path + "/"
        let path = prefix.standardizedFileURL.path
        guard path.hasPrefix(base), path.count > base.count else { throw InvalidPrefix(path: path) }
        return prefix
    }
}
