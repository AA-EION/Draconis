import Foundation

/// Where the core keeps its own files. Apps may override `dataDirectory`
/// before first use (the macOS app keeps its historical location).
public enum CorePaths {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _data: URL?

    /// macOS: ~/Library/Application Support/Draconis
    /// Linux: $XDG_DATA_HOME/draconis (~/.local/share/draconis)
    /// Windows: %LOCALAPPDATA%\Draconis
    public static var dataDirectory: URL {
        get {
            lock.lock(); defer { lock.unlock() }
            if let _data { return _data }
            let url = defaultDataDirectory()
            _data = url
            return url
        }
        set { lock.lock(); _data = newValue; lock.unlock() }
    }

    public static var downloads: URL { directory("Downloads") }
    public static var logs: URL { directory("Logs") }

    public static func directory(_ name: String) -> URL {
        let url = dataDirectory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The user's home: `$HOME` when set (Linux tools and Flatpak expect it to
    /// win), else the account's home directory.
    public static var home: URL {
        if let env = ProcessInfo.processInfo.environment["HOME"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static func defaultDataDirectory() -> URL {
        let env = ProcessInfo.processInfo.environment
        #if os(macOS)
        return home.appendingPathComponent("Library/Application Support/Draconis", isDirectory: true)
        #elseif os(Windows)
        let base = env["LOCALAPPDATA"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent("AppData/Local", isDirectory: true)
        return base.appendingPathComponent("Draconis", isDirectory: true)
        #else
        let base = env["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appendingPathComponent(".local/share", isDirectory: true)
        return base.appendingPathComponent("draconis", isDirectory: true)
        #endif
    }
}
