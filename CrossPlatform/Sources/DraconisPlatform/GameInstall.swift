import DraconisCore
import Foundation

/// A Titanfall 2 copy Draconis can launch, and how it's run.
public struct GameInstall: Identifiable, Hashable, Codable, Sendable {
    public enum Source: Hashable, Codable, Sendable {
        /// Steam copy, started through the Steam client.
        case steam(root: URL, kind: String, compatTool: String?)
        /// Linux: a Wine prefix (Draconis, Heroic, Lutris, Bottles or picked by hand).
        case prefix(URL, origin: String)
        /// Windows: an EA app, Epic or hand-picked install, run directly.
        case native(origin: String)
    }

    public var id: String { root.path }
    public var root: URL
    public var source: Source

    public init(root: URL, source: Source) {
        self.root = root
        self.source = source
    }

    public var name: String {
        switch source {
        case .steam: return "Steam"
        case .prefix(_, let origin): return origin
        case .native(let origin): return origin
        }
    }

    public var hasNorthstar: Bool { GameFiles.hasNorthstar(in: root) }
    public var northstarVersion: String? { GameFiles.northstarVersion(in: root) }

    public var prefix: URL? {
        if case .prefix(let url, _) = source { return url }
        return nil
    }

    /// The Wine prefix a game folder sits in (the folder that holds drive_c).
    public static func prefix(containing folder: URL) -> URL? {
        var url = folder.standardizedFileURL
        while url.pathComponents.count > 1 {
            if url.lastPathComponent == "drive_c" { return url.deletingLastPathComponent() }
            url = url.deletingLastPathComponent()
        }
        return nil
    }
}
