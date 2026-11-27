import DraconisCore
import DraconisPlatform
import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// App state and actions for the Linux and Windows launcher.
@MainActor
@Observable
final class AppModel {
    var settings = Settings.load() {
        didSet { if settings != oldValue { settings.save() } }
    }
    var section: AppSection? = .play

    // Games and runners
    var games: [GameInstall] = []
    var runners: [Runner] = []
    var umuRun: URL?
    var scanning = false

    // Northstar
    var latestRelease: NorthstarRelease?
    var northstarBusy = false
    var northstarProgress: NorthstarUpdater.Progress?

    // Launch
    var launching = false
    var gameRunning = false
    var status: String?
    var error: String?

    // Mods
    var packages: [ThunderstorePackage] = []
    var installedMods: [InstalledMod] = []
    var modFilter = ""
    var modsLoading = false
    var modBusy: String?

    // Servers
    var servers: [NorthstarServer] = []
    var serverFilter = ""
    var serversLoading = false

    // Runner downloads / prefix setup
    var toolBusy: String?
    var toolProgress: NorthstarUpdater.Progress?

    // Console
    var console: [ConsoleLine] = []

    // Draconis updates
    var newerVersion: String?

    init() {
        Log.sink = { [weak self] level, scope, message in
            Task { @MainActor in self?.append(level, scope, message) }
        }
    }

    // MARK: - Derived

    var selectedGame: GameInstall? {
        games.first { $0.id == settings.selectedGame } ?? games.first
    }

    var selectedRunner: Runner? {
        runners.first { $0.id == settings.runnerID } ?? runners.first
    }

    var needsRunner: Bool {
        guard let game = selectedGame else { return false }
        if case .steam = game.source { return false }
        #if os(Windows)
        return false
        #else
        return true
        #endif
    }

    var northstarUpToDate: Bool {
        guard let game = selectedGame, let latest = latestRelease else { return false }
        return GameFiles.versionsMatch(installed: game.northstarVersion, releaseTag: latest.tagName)
    }

    var matchingPackages: [ThunderstorePackage] {
        // Northstar itself is managed on the Play page; mod managers aren't mods.
        let hidden: Set<String> = ["northstar-Northstar", "northstar-NorthstarReleaseCandidate", "ebkr-r2modman"]
        let base = packages.filter { !$0.isDeprecated && !$0.hasNsfwContent && !hidden.contains($0.fullName) }
        let query = modFilter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return base }
        return base.filter { $0.name.lowercased().contains(query) || $0.owner.lowercased().contains(query) }
    }

    // Every row is laid out on each update, so long lists stall the UI.
    static let packageRowLimit = 60

    var filteredServers: [NorthstarServer] {
        let query = serverFilter.trimmingCharacters(in: .whitespaces).lowercased()
        let sorted = servers.sorted { $0.playerCount > $1.playerCount }
        guard !query.isEmpty else { return sorted }
        return sorted.filter {
            $0.name.lowercased().contains(query) || $0.map.lowercased().contains(query)
                || $0.playlist.lowercased().contains(query)
        }
    }

    // MARK: - Startup

    func bootstrap() async {
        Log.info("app", "Draconis \(AppInfo.version) starting")
        await rescan()
        if games.isEmpty { section = .settings }
        await refreshNorthstar()
        await checkForDraconisUpdate()
        if settings.autoUpdateNorthstar, latestRelease != nil, let game = selectedGame, game.hasNorthstar, !northstarUpToDate {
            await installNorthstar()
        }
    }

    func rescan() async {
        scanning = true
        defer { scanning = false }
        let folders = settings.extraGameFolders.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let (found, runners, umu) = await Task.detached {
            #if os(Windows)
            let runners: [Runner] = []
            #else
            let runners = RunnerLocator.all()
            #endif
            return (GameLocator.all(extraFolders: folders), runners, RunnerDownloads.umuRun())
        }.value
        games = found
        self.runners = runners
        umuRun = umu
        Log.ok("app", "Found \(found.count) Titanfall 2 install(s), \(runners.count) runner(s)")
        refreshInstalledMods()
    }

    func addGameFolder(_ url: URL) async {
        guard GameFiles.isTitanfallRoot(url) else {
            error = "There's no Titanfall2.exe in \(url.path)."
            return
        }
        if !settings.extraGameFolders.contains(url.path) { settings.extraGameFolders.append(url.path) }
        settings.selectedGame = GameLocator.custom(url).id
        await rescan()
    }

    // MARK: - Northstar

    func refreshNorthstar() async {
        do {
            latestRelease = try await NorthstarUpdater.shared.latestRelease()
        } catch {
            Log.error("northstar", error.localizedDescription)
        }
    }

    func installNorthstar() async {
        guard let game = selectedGame, !northstarBusy else { return }
        northstarBusy = true
        defer { northstarBusy = false; northstarProgress = nil }
        do {
            if latestRelease == nil { await refreshNorthstar() }
            guard let release = latestRelease else { throw NorthstarUpdater.UpdateError.noReleases }
            let zip = try await NorthstarUpdater.shared.downloadRelease(release) { p in
                Task { @MainActor in self.northstarProgress = p }
            }
            try await NorthstarUpdater.shared.install(zipURL: zip, into: game.root, zipRoot: release.zipRoot) { p in
                Task { @MainActor in self.northstarProgress = p }
            }
            status = "Northstar \(release.tagName) installed."
            await rescan()
        } catch {
            fail(error)
        }
    }

    func uninstallNorthstar() async {
        guard let game = selectedGame else { return }
        do {
            try await NorthstarUpdater.shared.uninstall(from: game.root)
            status = "Northstar removed."
            await rescan()
        } catch {
            fail(error)
        }
    }

    // MARK: - Launch

    func launch(_ mode: LaunchMode) async {
        guard let game = selectedGame, !launching, !gameRunning else { return }
        launching = true
        error = nil
        defer { launching = false; status = nil }
        do {
            LaunchPlanner.prepareFiles(game: game, mode: mode)
            var prefixRunning = false
            #if !os(Windows)
            if case .steam(let root, let kind, _) = game.source, game.hasNorthstar {
                try await addNorthstarLaunchOption(root: root, kind: kind)
            }
            let isLooseFolder: Bool = { if case .native = game.source { return true }; return false }()
            if let prefix = game.prefix ?? (isLooseFolder ? defaultPrefix : nil) {
                prefixRunning = try await startEAApp(in: prefix)
            }
            #endif
            let command = try LaunchPlanner.plan(
                game: game, mode: mode, runner: selectedRunner, umuRun: umuRun,
                defaultPrefix: defaultPrefix, prefixRunning: prefixRunning)
            try Spawner.launch(command.executable, command.arguments, environment: command.environment,
                               workingDirectory: command.workingDirectory, log: gameLog)
            let what = mode == .northstar ? "Northstar" : "Titanfall 2"
            status = { if case .steam = game.source { return "Steam is starting \(what)…" }; return "Starting \(what)…" }()
            Log.info("launch", "\(command.executable) \(command.arguments.joined(separator: " "))")
            // Steam and Proton can take a while on a first start.
            for _ in 0..<90 {
                try await Task.sleep(for: .seconds(2))
                if GameProcess.isRunning() { break }
            }
            guard GameProcess.isRunning() else {
                throw LaunchFailure("Titanfall 2 didn't start within 3 minutes. Check Steam or the Console page, then launch again.")
            }
            gameRunning = true
            Log.ok("launch", "\(what) is running")
            Task { await watchUntilExit() }
        } catch {
            fail(error)
        }
    }

    /// Northstar's proxy DLL only loads with `wsock32=n,b`, which Steam passes
    /// to the game only through its launch options. Steam rewrites its config
    /// on exit, so it has to be closed while they're changed.
    func addNorthstarLaunchOption(root: URL, kind: String) async throws {
        let install = SteamInstall(root: root, kind: SteamInstall.Kind(rawValue: kind) ?? .native)
        guard !install.configsNeedingNorthstarOverride(appID: SteamLocator.titanfallAppID).isEmpty else { return }
        if SteamClient.isRunning() {
            status = "Closing Steam once to add Northstar's launch option…"
            guard await SteamClient.shutdown(kind: kind) else {
                throw LaunchFailure("Close Steam, then launch again: Draconis adds Titanfall 2's launch option (\(SteamLaunchOptions.override) %command%) while Steam is closed.")
            }
        }
        try install.addNorthstarOverride(appID: SteamLocator.titanfallAppID)
    }

    var defaultPrefix: URL { PrefixStore.url(named: "Titanfall 2") }
    var gameLog: URL { CorePaths.logs.appendingPathComponent("game.log") }

    /// The EA app signs Titanfall 2 in. Start it in the prefix and wait for
    /// its local service; returns whether the prefix is now running.
    func startEAApp(in prefix: URL) async throws -> Bool {
        if EAApp.isLSXListening() { return true }
        guard let exe = EAApp.executable(inPrefix: prefix) else { return false }
        status = "Starting the EA app…"
        let command = try LaunchPlanner.runInPrefix(
            exe: exe.path, arguments: [], prefix: prefix, runner: selectedRunner, umuRun: umuRun)
        try Spawner.launch(command.executable, command.arguments, environment: command.environment, log: gameLog)
        for _ in 0..<60 {
            try await Task.sleep(for: .seconds(2))
            if EAApp.isLSXListening() { return true }
        }
        throw LaunchFailure("The EA app didn't come up. Open it, sign in, then launch again.")
    }

    func watchUntilExit() async {
        while gameRunning {
            try? await Task.sleep(for: .seconds(3))
            gameRunning = GameProcess.isRunning()
        }
    }

    // MARK: - Runners and prefixes (Linux)

    func installUmu() async {
        await tool("Downloading umu-launcher…") {
            _ = try await RunnerDownloads.installUmu { p in Task { @MainActor in self.toolProgress = p } }
        }
    }

    func installGEProton() async {
        await tool("Downloading GE-Proton…") {
            let release = try await RunnerDownloads.latestGEProton()
            let dir = try await RunnerDownloads.installGEProton(release) { p in
                Task { @MainActor in self.toolProgress = p }
            }
            await MainActor.run { self.settings.runnerID = Runner(kind: .proton, name: release.tag, path: dir, source: "Steam").id }
        }
    }

    /// A fresh Draconis prefix with the EA app, for EA app and Epic copies.
    func createPrefixWithEAApp() async {
        let target = defaultPrefix
        await tool("Creating a Wine prefix…") {
            let prefix = try PrefixStore.validatedForCreation(target)
            try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
            let installer = CorePaths.downloads.appendingPathComponent("EAappInstaller.exe")
            if !FileManager.default.fileExists(atPath: installer.path) {
                await MainActor.run { self.toolBusy = "Downloading the EA app…" }
                let tmp = try await DownloadCoordinator.download(from: EAApp.installerURL) { p in
                    Task { @MainActor in self.toolProgress = p }
                }
                try FileManager.default.moveItem(at: tmp, to: installer)
            }
            await MainActor.run { self.toolBusy = "Installing the EA app…" }
            let command = try await MainActor.run {
                try LaunchPlanner.runInPrefix(exe: installer.path, arguments: ["EAX_LAUNCH_CLIENT=0", "IGNORE_INSTALLED=1"],
                                              prefix: prefix, runner: self.selectedRunner, umuRun: self.umuRun)
            }
            try await Spawner.run(command.executable, command.arguments, environment: command.environment,
                                  log: CorePaths.logs.appendingPathComponent("prefix.log"))
            if let exe = EAApp.executable(inPrefix: prefix) {
                let open = try await MainActor.run {
                    try LaunchPlanner.runInPrefix(exe: exe.path, arguments: [], prefix: prefix,
                                                  runner: self.selectedRunner, umuRun: self.umuRun)
                }
                try Spawner.launch(open.executable, open.arguments, environment: open.environment,
                                   log: CorePaths.logs.appendingPathComponent("prefix.log"))
            }
            await MainActor.run {
                self.status = "The EA app is open. Sign in and install Titanfall 2, then click Rescan."
            }
        }
    }

    private func tool(_ label: String, _ body: @escaping @Sendable () async throws -> Void) async {
        guard toolBusy == nil else { return }
        toolBusy = label
        defer { toolBusy = nil; toolProgress = nil }
        do {
            try await body()
            await rescan()
        } catch {
            fail(error)
        }
    }

    // MARK: - Mods

    func refreshMods() async {
        modsLoading = true
        defer { modsLoading = false }
        do {
            packages = try await ThunderstoreClient.shared.listPackages()
        } catch {
            fail(error)
        }
        refreshInstalledMods()
    }

    func refreshInstalledMods() {
        installedMods = (selectedGame.map { ThunderstoreClient.shared.installedMods(in: $0.root) } ?? [])
            .filter { !GameFiles.coreMods.contains($0.name) }
    }

    func install(_ package: ThunderstorePackage) async {
        guard let game = selectedGame, let version = package.latest else { return }
        modBusy = package.fullName
        defer { modBusy = nil }
        do {
            try await ThunderstoreClient.shared.install(version, into: game.root, packageCache: packages)
            status = "Installed \(package.name)."
        } catch {
            fail(error)
        }
        refreshInstalledMods()
    }

    func installLocalZip(_ url: URL) async {
        guard let game = selectedGame else { return }
        do {
            try await ThunderstoreClient.shared.installLocalZip(at: url, into: game.root)
        } catch {
            fail(error)
        }
        refreshInstalledMods()
    }

    func setEnabled(_ mod: InstalledMod, _ enabled: Bool) {
        guard let game = selectedGame else { return }
        do {
            try ThunderstoreClient.shared.setEnabled(enabled, mod: mod, in: game.root)
        } catch {
            fail(error)
        }
        refreshInstalledMods()
    }

    func uninstall(_ mod: InstalledMod) {
        do {
            try ThunderstoreClient.shared.uninstall(mod)
        } catch {
            fail(error)
        }
        refreshInstalledMods()
    }

    func isInstalled(_ package: ThunderstorePackage) -> Bool {
        installedMods.contains { $0.thunderstoreID?.hasPrefix(package.fullName + "-") == true }
    }

    // MARK: - Servers

    func refreshServers() async {
        serversLoading = true
        defer { serversLoading = false }
        do {
            servers = try await ServerBrowserClient.shared.servers()
        } catch {
            fail(error)
        }
    }

    // MARK: - Draconis updates

    func checkForDraconisUpdate() async {
        var request = URLRequest(url: AppInfo.releasesAPI)
        request.setValue("Draconis-Launcher", forHTTPHeaderField: "User-Agent")
        struct Release: Decodable { let tag_name: String }
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let tag = (try? JSONDecoder().decode(Release.self, from: data))?.tag_name else { return }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        if latest.compare(AppInfo.version, options: .numeric) == .orderedDescending {
            newerVersion = latest
            Log.info("update", "Draconis \(latest) is available")
        }
    }

    // MARK: - Console

    func append(_ level: LogLevel, _ scope: String, _ message: String) {
        console.append(ConsoleLine(time: Date(), level: level, scope: scope, message: message))
        if console.count > 2000 { console.removeFirst(console.count - 2000) }
    }

    func fail(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        let message = error.localizedDescription
        self.error = message
        Log.error("app", message)
    }
}

struct LaunchFailure: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
