import DraconisCore
import DraconisPlatform
import Foundation

/// Preferences, saved as JSON in Draconis's data folder.
struct Settings: Codable, Equatable {
    var selectedGame: String?
    var extraGameFolders: [String] = []
    var runnerID: String?
    var autoUpdateNorthstar = true
    var showConsole = false
    var setupDone = false

    static var file: URL { CorePaths.dataDirectory.appendingPathComponent("settings.json") }

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: file),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return settings
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? FileManager.default.createDirectory(at: CorePaths.dataDirectory, withIntermediateDirectories: true)
        try? data.write(to: Settings.file, options: .atomic)
    }
}

enum AppInfo {
    static let version = "0.13.3"
    static let releasesAPI = URL(string: "https://api.github.com/repos/AA-EION/Draconis/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/AA-EION/Draconis/releases/latest")!
    static let issuesPage = URL(string: "https://github.com/AA-EION/Draconis/issues/new")!
}

struct ConsoleLine: Identifiable, Hashable {
    let id = UUID()
    let time: Date
    let level: LogLevel
    let scope: String
    let message: String
}

enum AppSection: String, CaseIterable, Identifiable, CustomStringConvertible {
    case play, mods, servers, console, settings
    var id: String { rawValue }
    var description: String {
        switch self {
        case .play: return "Play"
        case .mods: return "Mods"
        case .servers: return "Servers"
        case .console: return "Console"
        case .settings: return "Settings"
        }
    }
}

extension AppSection {
    var icon: String {
        switch self {
        case .play: return "play"
        case .mods: return "puzzle"
        case .servers: return "server"
        case .console: return "terminal"
        case .settings: return "settings"
        }
    }
}
