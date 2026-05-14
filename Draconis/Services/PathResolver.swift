import Foundation
import AppKit

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

    /// `/Applications/CrossOver.app` — the conventional location, used as a
    /// last-resort fallback when LaunchServices doesn't know about CrossOver.
    public static let defaultCrossOverApp = URL(fileURLWithPath: "/Applications/CrossOver.app")

    /// Where CrossOver.app lives **on this machine**. Asks LaunchServices
    /// first (so `~/Applications`, external volumes, or renamed bundles all
    /// work), then falls back to the default location. Re-resolved on every
    /// read — cheap, and means an install during a Draconis session is picked
    /// up without restarting.
    public static var crossOverApp: URL {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.codeweavers.CrossOver"
        ) {
            return url
        }
        return defaultCrossOverApp
    }

    /// Default bottles location when CrossOver hasn't been told otherwise.
    public static let defaultCrossOverBottlesRoot: URL = applicationSupport
        .appendingPathComponent("CrossOver/Bottles", isDirectory: true)

    /// Path to CrossOver's preferences plist in the *running user's* home
    /// (`FileManager.homeDirectoryForCurrentUser` — works for any user, not
    /// just whoever built Draconis).
    public static var crossOverPrefsPlist: URL {
        home.appendingPathComponent("Library/Preferences/com.codeweavers.CrossOver.plist")
    }

    /// Where CrossOver currently stores bottles. Re-resolved on every read so
    /// that if the user changes the location inside CrossOver Preferences,
    /// Draconis picks it up without restarting.
    ///
    /// Source of truth: `BottleDir` (String) in
    /// `~/Library/Preferences/com.codeweavers.CrossOver.plist`, read straight
    /// from disk (bypassing `cfprefsd`'s cache so changes are picked up live).
    /// Defaults to `~/Library/Application Support/CrossOver/Bottles` when the
    /// key is absent, malformed, or points at something Draconis can't read.
    public static var crossOverBottlesRoot: URL {
        crossOverBottlesRoot(plistAt: crossOverPrefsPlist)
            ?? defaultCrossOverBottlesRoot
    }

    /// Pure parser — takes a plist file URL so tests can drive it with fixtures.
    /// Returns nil when the configured path is unusable.
    static func crossOverBottlesRoot(plistAt plistURL: URL) -> URL? {
        // 1. Read the plist directly. Going through PropertyListSerialization
        //    rather than UserDefaults(suiteName:) sidesteps cfprefsd caching,
        //    so a BottleDir change from CrossOver's UI is visible immediately
        //    on the next bottle refresh.
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: Any]
        else { return nil }

        guard let raw = plist["BottleDir"] else { return nil }

        // 2. Coerce to a path string. Defend against future format changes:
        //    String today, but could be URL/Data-bookmark/Array in the future.
        let candidate: String?
        switch raw {
        case let s as String:  candidate = s
        case let url as URL:   candidate = url.isFileURL ? url.path : nil
        case let arr as [Any]: candidate = arr.first as? String
        default:               candidate = nil
        }
        guard var path = candidate else { return nil }

        // 3. Sanitise. `standardizingPath` expands ~, collapses //, resolves
        //    `..`, and strips trailing slashes in one go.
        path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        path = (path as NSString).standardizingPath

        // 4. Require an absolute path that exists as a directory. A relative
        //    path or stale value (drive unmounted, folder deleted) falls back
        //    to the default rather than handing CrossOverDetector a bogus URL
        //    it'll silently enumerate as empty.
        guard path.hasPrefix("/") else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
              isDir.boolValue else { return nil }

        return URL(fileURLWithPath: path, isDirectory: true)
    }

    // MARK: - Helpers

    /// drive_c URL inside a prefix.
    public static func driveC(in prefix: URL) -> URL {
        prefix.appendingPathComponent("drive_c", isDirectory: true)
    }
}
