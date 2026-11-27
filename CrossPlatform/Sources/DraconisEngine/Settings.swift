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
    static let appID = "io.github.aa_eion.Draconis"
    static let version = "0.15.0"
    static let releasesAPI = URL(string: "https://api.github.com/repos/AA-EION/Draconis/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/AA-EION/Draconis/releases/latest")!
    static let issuesPage = URL(string: "https://github.com/AA-EION/Draconis/issues/new")!
}

struct ConsoleLine: Codable, Hashable {
    let time: Date
    let level: LogLevel
    let scope: String
    let message: String
}
