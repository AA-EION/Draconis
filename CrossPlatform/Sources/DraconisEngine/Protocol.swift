import DraconisCore
import DraconisPlatform
import Foundation

/// The engine and the UI (Desktop/, Rust) talk in JSON lines. The engine
/// writes `Message`s to stdout; the UI writes `Command`s to stdin.
enum Message: Encodable {
    case state(EngineState)
    case log(ConsoleLine)
    case packages([PackageInfo])
    case servers([ServerInfo])

    enum CodingKeys: String, CodingKey { case type, state, line, packages, servers }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .state(let s): try c.encode("state", forKey: .type); try c.encode(s, forKey: .state)
        case .log(let l): try c.encode("log", forKey: .type); try c.encode(l, forKey: .line)
        case .packages(let p): try c.encode("packages", forKey: .type); try c.encode(p, forKey: .packages)
        case .servers(let s): try c.encode("servers", forKey: .type); try c.encode(s, forKey: .servers)
        }
    }
}

struct Command: Decodable {
    var cmd: String
    var id: String?
    var path: String?
    var mode: String?
    var name: String?
    var enabled: Bool?
}

struct ProgressInfo: Codable, Equatable {
    var fraction: Double
    var detail: String?
}

struct GameInfo: Codable, Equatable {
    var id, name, root, folder: String
    var kind: String
    var hasNorthstar: Bool
    var northstarVersion: String?
}

struct RunnerInfo: Codable, Equatable {
    var id, title: String
}

struct ModInfo: Codable, Equatable {
    var id, name, version: String
    var enabled: Bool
}

struct PackageInfo: Codable, Equatable {
    var fullName, name, owner, version, description: String
}

struct ServerInfo: Codable, Equatable {
    var id, name, description, map, playlist: String
    var region: String?
    var players, maxPlayers: Int
    var password: Bool
}

struct VRState: Codable, Equatable {
    var supported: Bool
    var installedVersion: String?
    var latestVersion: String?
    var updateAvailable: Bool
    var busy: Bool
    var phase: String?
    var progress: Double?
    var error: String?
    var steamVRRunning: Bool
    var steamVRInstalled: Bool
    var otherRuntime: String?
    var activeRuntime: String?
    var checked: Bool
}

struct EngineState: Codable, Equatable {
    var version: String
    var os: String
    var dataFolder: String
    var crashFolder: String
    var lastCrashReport: String?
    var releasesPage, issuesPage: String
    var games: [GameInfo]
    var selectedGame: String?
    var runners: [RunnerInfo]
    var selectedRunner: String?
    var needsRunner: Bool
    var umuPath: String?
    var scanning: Bool
    var latestNorthstar: String?
    var northstarUpToDate: Bool
    var northstarBusy: Bool
    var northstarProgress: ProgressInfo?
    var launching, gameRunning: Bool
    var status, error: String?
    var installedMods: [ModInfo]
    var installedPackages: [String]
    var modsLoading: Bool
    var modBusy: String?
    var serversLoading: Bool
    var toolBusy: String?
    var toolProgress: ProgressInfo?
    var newerVersion: String?
    var autoUpdateNorthstar: Bool
    var vr: VRState
}

extension Runner {
    var title: String { "\(name) (\(kind == .proton ? "Proton" : "Wine"), \(source))" }
}

extension AppModel {
    static var os: String {
        #if os(Windows)
        return "Windows"
        #elseif os(Linux)
        return "Linux"
        #else
        return "macOS"
        #endif
    }

    func snapshot() -> EngineState {
        let progress = { (p: NorthstarUpdater.Progress?) in p.map { ProgressInfo(fraction: $0.fraction, detail: $0.detail) } }
        return EngineState(
            version: AppInfo.version, os: Self.os,
            dataFolder: CorePaths.dataDirectory.path,
            crashFolder: CrashReports.folder.path,
            lastCrashReport: CrashReports.previous().first?.path,
            releasesPage: AppInfo.releasesPage.absoluteString, issuesPage: AppInfo.issuesPage.absoluteString,
            games: games.map { game in
                let kind: String
                switch game.source {
                case .steam: kind = "steam"
                case .prefix: kind = "prefix"
                case .native: kind = "native"
                }
                return GameInfo(id: game.id, name: game.name, root: game.root.path, folder: game.root.lastPathComponent,
                                kind: kind, hasNorthstar: game.hasNorthstar, northstarVersion: game.northstarVersion)
            },
            selectedGame: selectedGame?.id,
            runners: runners.map { RunnerInfo(id: $0.id, title: $0.title) },
            selectedRunner: selectedRunner?.id,
            needsRunner: needsRunner,
            umuPath: umuRun?.path,
            scanning: scanning,
            latestNorthstar: latestRelease?.tagName,
            northstarUpToDate: northstarUpToDate,
            northstarBusy: northstarBusy,
            northstarProgress: progress(northstarProgress),
            launching: launching, gameRunning: gameRunning,
            status: status, error: error,
            installedMods: installedMods.map { ModInfo(id: $0.id, name: $0.name, version: $0.version, enabled: $0.enabled) },
            installedPackages: packages.filter(isInstalled).map(\.fullName),
            modsLoading: modsLoading, modBusy: modBusy,
            serversLoading: serversLoading,
            toolBusy: toolBusy, toolProgress: progress(toolProgress),
            newerVersion: newerVersion,
            autoUpdateNorthstar: settings.autoUpdateNorthstar,
            vr: VRState(
                supported: vrSupported, installedVersion: vrRecord?.version, latestVersion: vrLatest?.mod.version,
                updateAvailable: vrUpdateAvailable, busy: vrBusy, phase: vrPhase, progress: vrProgress, error: vrError,
                steamVRRunning: vrRuntime?.steamVRRunning ?? false, steamVRInstalled: vrRuntime?.steamVRInstalled ?? false,
                otherRuntime: vrRuntime?.otherRunning, activeRuntime: vrRuntime?.activeOpenXR, checked: vrRuntime != nil)
        )
    }

    /// Mods worth listing: no deprecated/NSFW packages, no Northstar itself or mod managers.
    func browsablePackages() -> [PackageInfo] {
        let hidden: Set<String> = ["northstar-Northstar", "northstar-NorthstarReleaseCandidate", "ebkr-r2modman"]
        return packages.filter { !$0.isDeprecated && !$0.hasNsfwContent && !hidden.contains($0.fullName) }.map {
            PackageInfo(fullName: $0.fullName, name: $0.name, owner: $0.owner,
                        version: $0.latest?.versionNumber ?? "", description: $0.latest?.description ?? "")
        }
    }

    func serverList() -> [ServerInfo] {
        servers.map {
            ServerInfo(id: $0.id, name: $0.displayName, description: $0.displayDescription, map: $0.map, playlist: $0.playlist,
                       region: $0.region, players: $0.playerCount, maxPlayers: $0.maxPlayers, password: $0.hasPassword)
        }
    }

    func perform(_ command: Command) async {
        switch command.cmd {
        case "rescan": await rescan()
        case "selectGame":
            settings.selectedGame = command.id
            refreshInstalledMods()
            await refreshVR()
        case "selectRunner": settings.runnerID = command.id
        case "addGameFolder": if let path = command.path { await addGameFolder(URL(fileURLWithPath: path, isDirectory: true)) }
        case "launch": await launch(command.mode == "vanilla" ? .vanilla : .northstar)
        case "installNorthstar": await installNorthstar()
        case "uninstallNorthstar": await uninstallNorthstar()
        case "setAutoUpdate": settings.autoUpdateNorthstar = command.enabled ?? settings.autoUpdateNorthstar
        case "refreshMods": await refreshMods()
        case "installMod":
            if let package = packages.first(where: { $0.fullName == command.id }) { await install(package) }
        case "installModZip": if let path = command.path { await installLocalZip(URL(fileURLWithPath: path)) }
        case "setModEnabled":
            if let mod = installedMods.first(where: { $0.id == command.id }) { setEnabled(mod, command.enabled ?? true) }
        case "uninstallMod":
            if let mod = installedMods.first(where: { $0.id == command.id }) { uninstall(mod) }
        case "refreshServers": await refreshServers()
        case "installUmu": await installUmu()
        case "installGEProton": await installGEProton()
        case "createPrefix": await createPrefixWithEAApp()
        case "installVR": await installVR()
        case "uninstallVR": await uninstallVR()
        case "launchVR": await launchVR()
        case "startSteamVR": startSteamVR()
        case "refreshVR": await refreshVR()
        case "checkForUpdate": await checkForDraconisUpdate()
        case "dismissError": error = nil
        default: Log.warn("engine", "Unknown command \(command.cmd)")
        }
    }
}

extension LogLevel: @retroactive Codable {}
