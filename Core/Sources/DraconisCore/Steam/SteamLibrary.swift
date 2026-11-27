import Foundation

/// A Steam installation and the Titanfall 2 copy in it.
public struct SteamInstall: Hashable, Sendable {
    public enum Kind: String, Sendable { case native, flatpak, snap, windows }

    public var root: URL
    public var kind: Kind

    public init(root: URL, kind: Kind) {
        self.root = root
        self.kind = kind
    }

    public var steamapps: URL { root.appendingPathComponent("steamapps", isDirectory: true) }

    /// Library folders (each with its own `steamapps/`), the root first.
    public func libraries() -> [URL] {
        var result = [root]
        guard let vdf = VDF.load(steamapps.appendingPathComponent("libraryfolders.vdf"))
                ?? VDF.load(root.appendingPathComponent("config/libraryfolders.vdf")),
              let folders = vdf["libraryfolders"] ?? vdf["LibraryFolders"]
        else { return result }
        for (_, entry) in folders.entries {
            let path = entry["path"]?.string ?? entry.string
            guard let path, entry["mounted"]?.string != "0" else { continue }
            let url = translate(URL(fileURLWithPath: path, isDirectory: true))
            if !result.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
                result.append(url)
            }
        }
        return result
    }

    /// Flatpak Steam records its own in-sandbox home path for the default library.
    func translate(_ url: URL) -> URL {
        guard kind == .flatpak else { return url }
        let home = CorePaths.home.path
        let inner = home + "/.local/share/Steam"
        if url.path == inner || url.path.hasPrefix(inner + "/") {
            return URL(fileURLWithPath: root.path + url.path.dropFirst(inner.count), isDirectory: true)
        }
        return url
    }

    /// Install folder of an app, when its manifest says it's fully installed
    /// enough to have files (StateFlags isn't checked: updates keep the files).
    public func installFolder(appID: String) -> URL? {
        for library in libraries() {
            let apps = library.appendingPathComponent("steamapps", isDirectory: true)
            guard let manifest = VDF.load(apps.appendingPathComponent("appmanifest_\(appID).acf")),
                  let dir = manifest[["AppState", "installdir"]]?.string
            else { continue }
            let folder = apps.appendingPathComponent("common/\(dir)", isDirectory: true)
            if FileManager.default.fileExists(atPath: folder.path) { return folder }
        }
        return nil
    }

    /// The compatibility tool Steam runs the app with ("GE-Proton11-14", …),
    /// falling back to the global default.
    public func compatTool(appID: String) -> String? {
        guard let config = VDF.load(root.appendingPathComponent("config/config.vdf")),
              let mapping = config[["InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping"]]
        else { return nil }
        for key in [appID, "0"] {
            if let name = mapping[[key, "name"]]?.string, !name.isEmpty { return name }
        }
        return nil
    }

    /// Steam's Proton prefix for an app (`compatdata/<appid>`), if it exists.
    public func compatData(appID: String) -> URL? {
        for library in libraries() {
            let dir = library.appendingPathComponent("steamapps/compatdata/\(appID)", isDirectory: true)
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("pfx").path) { return dir }
        }
        return nil
    }
}

public enum SteamLocator {
    public static let titanfallAppID = "1237970"

    /// Every Steam install on this machine, native before sandboxed ones.
    public static func installs(home: URL = CorePaths.home,
                                environment: [String: String] = ProcessInfo.processInfo.environment) -> [SteamInstall] {
        var candidates: [(String, SteamInstall.Kind)] = []
        #if os(Windows)
        if let path = WindowsRegistry.string(.currentUser, #"Software\Valve\Steam"#, "SteamPath") {
            candidates.append((path, .windows))
        }
        if let path = WindowsRegistry.string(.localMachine, #"SOFTWARE\WOW6432Node\Valve\Steam"#, "InstallPath") {
            candidates.append((path, .windows))
        }
        candidates.append((#"C:\Program Files (x86)\Steam"#, .windows))
        #else
        if let dir = environment["STEAM_DIR"], !dir.isEmpty { candidates.append((dir, .native)) }
        let h = home.path
        candidates += [
            ("\(h)/.steam/steam", .native),
            ("\(h)/.local/share/Steam", .native),
            ("\(h)/.steam/root", .native),
            ("\(h)/.steam/debian-installation", .native),
            ("\(h)/.var/app/com.valvesoftware.Steam/.local/share/Steam", .flatpak),
            ("\(h)/.var/app/com.valvesoftware.Steam/data/Steam", .flatpak),
            ("\(h)/snap/steam/common/.local/share/Steam", .snap),
            ("\(h)/snap/steam/common/.steam/steam", .snap),
        ]
        #endif
        var seen = Set<String>()
        var result: [SteamInstall] = []
        for (path, kind) in candidates {
            let url = URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath()
            guard FileManager.default.fileExists(atPath: url.appendingPathComponent("steamapps").path),
                  seen.insert(url.path).inserted else { continue }
            result.append(SteamInstall(root: url, kind: kind))
        }
        return result
    }

    /// Titanfall 2 in any Steam library.
    public static func titanfall(in installs: [SteamInstall] = installs()) -> (SteamInstall, URL)? {
        for install in installs {
            if let folder = install.installFolder(appID: titanfallAppID), GameFiles.isTitanfallRoot(folder) {
                return (install, folder)
            }
        }
        return nil
    }
}
