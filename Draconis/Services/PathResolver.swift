import Foundation

/// Common filesystem locations Draconis needs to know about.
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

    // MARK: - Third-party install roots

    /// CrossOver default location.
    public static let crossOverApp = URL(fileURLWithPath: "/Applications/CrossOver.app")

    /// CrossOver bottles live in ~/Library/Application Support/CrossOver/Bottles.
    public static let crossOverBottlesRoot: URL = applicationSupport
        .appendingPathComponent("CrossOver/Bottles", isDirectory: true)

    /// Apple's Game Porting Toolkit installs into /usr/local/opt or via the
    /// `gameportingtoolkit` binary in PATH. We also check common Homebrew
    /// locations and the `~/Library/Application Support/com.apple.gameporting`
    /// folder created by Apple's installer.
    public static let gptkCandidatePaths: [URL] = [
        URL(fileURLWithPath: "/usr/local/bin/gameportingtoolkit"),
        URL(fileURLWithPath: "/opt/homebrew/bin/gameportingtoolkit"),
        URL(fileURLWithPath: "/usr/local/opt/game-porting-toolkit/bin/wine64"),
        URL(fileURLWithPath: "/opt/homebrew/opt/game-porting-toolkit/bin/wine64"),
    ]

    /// Whisky bottles live in ~/Library/Containers/com.isaacmarovitz.Whisky/Bottles
    public static let whiskyBottlesRoot: URL = home
        .appendingPathComponent(
            "Library/Containers/com.isaacmarovitz.Whisky/Bottles",
            isDirectory: true
        )

    /// Kegworks installs bottles as self-contained .app bundles, usually in
    /// ~/Applications/Wineskin or ~/Applications. We scan both.
    public static let kegworksWrapperRoots: [URL] = [
        home.appendingPathComponent("Applications/Wineskin", isDirectory: true),
        home.appendingPathComponent("Applications", isDirectory: true),
    ]

    /// Mapping helper: given a Wine prefix, return its `drive_c` URL.
    public static func driveC(in prefix: URL) -> URL {
        prefix.appendingPathComponent("drive_c", isDirectory: true)
    }
}
