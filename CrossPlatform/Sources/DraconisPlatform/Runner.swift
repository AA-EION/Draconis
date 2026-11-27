import DraconisCore
import Foundation

/// A Windows compatibility layer for prefix installs on Linux.
public struct Runner: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// A Proton build, run through umu-run (Steam Runtime container).
        case proton
        /// A plain Wine build (`bin/wine`).
        case wine
    }

    public var kind: Kind
    public var name: String
    public var path: URL
    public var source: String

    public var id: String { "\(kind.rawValue):\(path.path)" }

    public init(kind: Kind, name: String, path: URL, source: String) {
        self.kind = kind
        self.name = name
        self.path = path
        self.source = source
    }

    public var isGEProton: Bool {
        let n = name.lowercased()
        return n.contains("ge-proton") || n.contains("northstar")
    }
}

#if !os(Windows)
public enum RunnerLocator {
    /// Proton and Wine builds already on this machine, newest-looking first.
    public static func all(home: URL = CorePaths.home,
                           environment: [String: String] = ProcessInfo.processInfo.environment) -> [Runner] {
        var protonDirs: [(URL, String)] = []
        for install in SteamLocator.installs(home: home, environment: environment) {
            for library in install.libraries() {
                protonDirs.append((library.appendingPathComponent("steamapps/common"), "Steam"))
            }
            protonDirs.append((install.root.appendingPathComponent("compatibilitytools.d"), "Steam"))
        }
        let data = environment["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".local/share")
        protonDirs += [
            (data.appendingPathComponent("Steam/compatibilitytools.d"), "Steam"),
            (home.appendingPathComponent(".steam/root/compatibilitytools.d"), "Steam"),
            (home.appendingPathComponent(".var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d"), "Flatpak Steam"),
            (home.appendingPathComponent(".config/heroic/tools/proton"), "Heroic"),
            (URL(fileURLWithPath: "/usr/share/steam/compatibilitytools.d"), "System"),
        ]
        for extra in (environment["STEAM_EXTRA_COMPAT_TOOLS_PATHS"] ?? "").split(separator: ":") {
            protonDirs.append((URL(fileURLWithPath: String(extra)), "Custom"))
        }
        let wineDirs: [(URL, String)] = [
            (data.appendingPathComponent("lutris/runners/wine"), "Lutris"),
            (home.appendingPathComponent(".config/heroic/tools/wine"), "Heroic"),
            (data.appendingPathComponent("bottles/runners"), "Bottles"),
            (CorePaths.directory("Runners"), "Draconis"),
        ]

        var runners: [Runner] = []
        var seen = Set<String>()
        func add(_ runner: Runner) {
            if seen.insert(runner.path.resolvingSymlinksInPath().path).inserted { runners.append(runner) }
        }
        let fm = FileManager.default
        for (dir, source) in protonDirs {
            for entry in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                guard fm.fileExists(atPath: entry.appendingPathComponent("proton").path),
                      fm.fileExists(atPath: entry.appendingPathComponent("toolmanifest.vdf").path),
                      !entry.lastPathComponent.hasPrefix("UMU-Latest") else { continue }
                add(Runner(kind: .proton, name: displayName(entry), path: entry, source: source))
            }
        }
        for (dir, source) in wineDirs {
            for entry in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                if fm.isExecutableFile(atPath: entry.appendingPathComponent("bin/wine").path) {
                    add(Runner(kind: .wine, name: entry.lastPathComponent, path: entry, source: source))
                }
            }
        }
        if let wine = Executables.find("wine", environment: environment) {
            add(Runner(kind: .wine, name: "System Wine", path: wine.deletingLastPathComponent().deletingLastPathComponent(), source: "System"))
        }
        return runners.sorted { a, b in
            if a.kind != b.kind { return a.kind == .proton }
            if a.isGEProton != b.isGEProton { return a.isGEProton }
            return a.name.localizedStandardCompare(b.name) == .orderedDescending
        }
    }

    /// `compatibilitytool.vdf`'s display name, else the folder name.
    static func displayName(_ dir: URL) -> String {
        if let vdf = VDF.load(dir.appendingPathComponent("compatibilitytool.vdf")),
           let tools = vdf[["compatibilitytools", "compat_tools"]],
           let first = tools.entries.first,
           let name = first.value["display_name"]?.string {
            return name
        }
        return dir.lastPathComponent
    }
}
#endif

public enum Executables {
    /// First match for `name` on PATH.
    public static func find(_ name: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        #if os(Linux)
        if Spawner.inFlatpak {
            let path = (try? Spawner.capture("/usr/bin/flatpak-spawn", ["--host", "sh", "-c", "command -v \(name)"]))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return path.hasPrefix("/") ? URL(fileURLWithPath: path) : nil
        }
        #endif
        #if os(Windows)
        let separator: Character = ";"
        let names = [name, name + ".exe"]
        #else
        let separator: Character = ":"
        let names = [name]
        #endif
        for dir in (environment["PATH"] ?? "").split(separator: separator) {
            for candidate in names {
                let url = URL(fileURLWithPath: String(dir)).appendingPathComponent(candidate)
                if FileManager.default.isExecutableFile(atPath: url.path) { return url }
            }
        }
        return nil
    }
}
