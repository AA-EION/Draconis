import Foundation

/// Filesystem locations Draconis needs to know about. All paths are
/// macOS-native — Draconis is CrossOver-only, so no Linux conventions
/// or other wine-flavour install roots live here.
public enum PathResolver {

    public static let home: URL = FileManager.default
        .homeDirectoryForCurrentUser

    public static let applicationSupport: URL = {
        let url = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? home.appendingPathComponent("Library/Application Support")
        return url
    }()

    /// ~/Library/Application Support/Draconis — where Draconis stores its
    /// own settings, downloaded Northstar zips, per-bottle launch logs.
    public static let draconisSupport: URL = {
        let url = applicationSupport.appendingPathComponent("Draconis", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )
        return url
    }()

    public static let downloadsCache: URL = {
        let url = draconisSupport.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )
        return url
    }()

    public static let launchLogs: URL = {
        let url = draconisSupport.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )
        return url
    }()

    /// Per-bottle log file where detached wine launches funnel stdout/stderr.
    /// Keeps GUI launches from inheriting Draconis's GUI-app fds.
    public static func bottleLogFile(for bottle: WineBottle) -> URL {
        let safeName = bottle.id
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return launchLogs.appendingPathComponent("\(safeName).log")
    }

    // MARK: - CrossOver locations

    /// CrossOver.app default location.
    public static let crossOverApp = URL(fileURLWithPath: "/Applications/CrossOver.app")

    /// CrossOver bottles live in ~/Library/Application Support/CrossOver/Bottles.
    public static let crossOverBottlesRoot: URL = applicationSupport
        .appendingPathComponent("CrossOver/Bottles", isDirectory: true)

    // MARK: - Helpers

    /// drive_c URL inside a prefix.
    public static func driveC(in prefix: URL) -> URL {
        prefix.appendingPathComponent("drive_c", isDirectory: true)
    }
}
