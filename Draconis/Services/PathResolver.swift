import Foundation

/// Common filesystem locations Draconis needs to know about.
/// All paths are macOS-native — we never reach for Linux conventions.
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
    /// own settings, managed bottles, downloaded Northstar zips, etc.
    public static let draconisSupport: URL = {
        let url = applicationSupport.appendingPathComponent("Draconis", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )
        return url
    }()

    public static let managedBottles: URL = {
        let url = draconisSupport.appendingPathComponent("Bottles", isDirectory: true)
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

    // MARK: - Third-party install roots (all standard macOS locations)

    /// CrossOver.app default location.
    public static let crossOverApp = URL(fileURLWithPath: "/Applications/CrossOver.app")

    /// CrossOver bottles live in ~/Library/Application Support/CrossOver/Bottles.
    public static let crossOverBottlesRoot: URL = applicationSupport
        .appendingPathComponent("CrossOver/Bottles", isDirectory: true)

    /// Apple's Game Porting Toolkit is shipped as `gameportingtoolkit` (a wine
    /// wrapper script) plus a `wine64` binary. Both Homebrew prefixes are
    /// checked. We also detect the GPTK wrapper script that ships with newer
    /// versions of the toolkit.
    public static let gptkCandidatePaths: [URL] = [
        URL(fileURLWithPath: "/usr/local/bin/gameportingtoolkit"),
        URL(fileURLWithPath: "/opt/homebrew/bin/gameportingtoolkit"),
        URL(fileURLWithPath: "/usr/local/opt/game-porting-toolkit/bin/wine64"),
        URL(fileURLWithPath: "/opt/homebrew/opt/game-porting-toolkit/bin/wine64"),
    ]

    /// Whisky (current versions) stores bottles directly in Application
    /// Support, not inside its container.
    public static let whiskyBottlesRoot: URL = applicationSupport
        .appendingPathComponent("Whisky/Bottles", isDirectory: true)

    /// Whisky bundles its own wine here.
    public static let whiskyWineBinary: URL = applicationSupport
        .appendingPathComponent("Whisky/Libraries/Wine/bin/wine64")

    /// Kegworks wrappers live in ~/Applications/Wineskin or ~/Applications,
    /// each as a self-contained .app bundle with `Contents/SharedSupport/wine`.
    public static let kegworksWrapperRoots: [URL] = [
        home.appendingPathComponent("Applications/Wineskin", isDirectory: true),
        home.appendingPathComponent("Applications/Kegworks", isDirectory: true),
        home.appendingPathComponent("Applications", isDirectory: true),
    ]

    /// Sikarugir is the *predecessor* of Kegworks (gcenx). Wrappers live in
    /// the same kind of location and use the same self-contained .app pattern.
    public static let sikarugirAppRoot = URL(
        fileURLWithPath: "/Applications/Sikarugir"
    )
    public static let sikarugirWrapperRoots: [URL] = [
        home.appendingPathComponent("Applications/Sikarugir", isDirectory: true),
        home.appendingPathComponent("Applications", isDirectory: true),
    ]

    // MARK: - Helpers

    /// drive_c URL inside a prefix.
    public static func driveC(in prefix: URL) -> URL {
        prefix.appendingPathComponent("drive_c", isDirectory: true)
    }
}
