import DraconisCore
import Foundation

/// Finds every Titanfall 2 copy on this machine.
public enum GameLocator {
    public static func all(extraFolders: [URL] = []) -> [GameInstall] {
        var found: [GameInstall] = []
        func add(_ game: GameInstall) {
            if !found.contains(where: { $0.root.standardizedFileURL.path == game.root.standardizedFileURL.path }) {
                found.append(game)
            }
        }
        for install in SteamLocator.installs() {
            if let folder = install.installFolder(appID: SteamLocator.titanfallAppID), GameFiles.isTitanfallRoot(folder) {
                add(GameInstall(root: folder, source: .steam(
                    root: install.root, kind: install.kind.rawValue,
                    compatTool: install.compatTool(appID: SteamLocator.titanfallAppID))))
            }
        }
        #if os(Windows)
        for (path, origin) in windowsInstalls() {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if GameFiles.isTitanfallRoot(url) { add(GameInstall(root: url, source: .native(origin: origin))) }
        }
        #else
        for (prefix, origin) in knownPrefixes() {
            if let root = GameFiles.locateTitanfall2(under: prefix.appendingPathComponent("drive_c")) {
                add(GameInstall(root: root, source: .prefix(prefix, origin: origin)))
            }
        }
        #endif
        for folder in extraFolders where GameFiles.isTitanfallRoot(folder) {
            add(custom(folder))
        }
        return found
    }

    /// A folder the user picked.
    public static func custom(_ folder: URL) -> GameInstall {
        #if os(Windows)
        return GameInstall(root: folder, source: .native(origin: "Custom"))
        #else
        if let prefix = GameInstall.prefix(containing: folder) {
            return GameInstall(root: folder, source: .prefix(prefix, origin: "Custom"))
        }
        return GameInstall(root: folder, source: .native(origin: "Custom"))
        #endif
    }

    #if !os(Windows)
    /// Draconis's own prefixes plus Heroic's Epic setup.
    static func knownPrefixes(home: URL = CorePaths.home) -> [(URL, String)] {
        var result: [(URL, String)] = []
        let fm = FileManager.default
        if let entries = try? fm.contentsOfDirectory(at: PrefixStore.root, includingPropertiesForKeys: nil) {
            result += entries.map { ($0, "Draconis: \($0.lastPathComponent)") }
        }
        for config in [home.appendingPathComponent(".config/heroic"),
                       home.appendingPathComponent(".var/app/com.heroicgameslauncher.hgl/config/heroic")] {
            let file = config.appendingPathComponent("GamesConfig/creamhorn.json")
            guard let data = try? Data(contentsOf: file),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let game = json["creamhorn"] as? [String: Any],
                  var path = game["winePrefix"] as? String, !path.isEmpty else { continue }
            if path.hasPrefix("~") { path = home.path + path.dropFirst() }
            result.append((URL(fileURLWithPath: path, isDirectory: true), "Heroic (Epic)"))
        }
        return result
    }
    #endif

    #if os(Windows)
    static func windowsInstalls() -> [(String, String)] {
        var result: [(String, String)] = []
        for key in [#"SOFTWARE\Respawn\Titanfall2"#, #"SOFTWARE\WOW6432Node\Respawn\Titanfall2"#] {
            if let dir = WindowsRegistry.string(.localMachine, key, "Install Dir") { result.append((dir, "EA app")) }
        }
        let manifests = URL(fileURLWithPath: #"C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests"#)
        for file in (try? FileManager.default.contentsOfDirectory(at: manifests, includingPropertiesForKeys: nil)) ?? []
        where file.pathExtension == "item" {
            guard let data = try? Data(contentsOf: file),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  json["AppName"] as? String == "creamhorn",
                  let location = json["InstallLocation"] as? String else { continue }
            result.append((location, "Epic Games"))
        }
        return result
    }
    #endif
}
