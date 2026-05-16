import Foundation
import SwiftUI
import AppKit
import Combine

/// Single source of truth for app-wide state.
@MainActor
public final class AppEnvironment: ObservableObject {

    // Discovered CrossOver bottles
    @Published public private(set) var bottles: [WineBottle] = []
    @Published public var selectedBottleID: String?

    // CrossOver availability (true iff LaunchServices knows the bundle ID)
    @Published public private(set) var crossOverInstalled: Bool = false

    // Launch status
    @Published public var launchInFlight: Bool = false
    @Published public var lastLaunchError: String?

    // Mods
    @Published public private(set) var thunderstorePackages: [ThunderstorePackage] = []
    @Published public private(set) var installedMods: [InstalledMod] = []
    @Published public var modsLoading: Bool = false
    @Published public var modsLoadError: String?

    // Server browser
    @Published public private(set) var servers: [NorthstarServer] = []
    @Published public var serversLoading: Bool = false
    @Published public var serverFilter: String = ""

    // Northstar releases / install progress
    @Published public private(set) var northstarReleases: [NorthstarRelease] = []
    @Published public var updating: Bool = false
    @Published public var updateProgress: NorthstarUpdater.Progress?
    @Published public var lastUpdateError: String?

    // Onboarding + console (manual UserDefaults mirror — @AppStorage doesn't
    // integrate with ObservableObject's objectWillChange).
    @Published public var showOnboarding: Bool = false
    @Published public var showConsole: Bool = UserDefaults.standard.bool(forKey: "showConsole") {
        didSet { UserDefaults.standard.set(showConsole, forKey: "showConsole") }
    }
    @Published public var verboseLogging: Bool = UserDefaults.standard.bool(forKey: "verboseLogging") {
        didSet { UserDefaults.standard.set(verboseLogging, forKey: "verboseLogging") }
    }

    // Steam
    @Published public var steamInstalling: Bool = false

    // Auto bottle install (from Onboarding)
    @Published public var autoInstallStage: BottleInstaller.Stage?

    // Maxima
    @Published public var maximaInstalled: Bool = false
    @Published public var maximaHelperRegistered: Bool = false
    @Published public var maximaSettingUp: Bool = false
    @Published public var maximaProgress: MaximaService.Progress?
    @Published public var maximaError: String?
    @Published public var maximaUpdateAvailable: Bool = false
    @Published public var maximaInstalledVersion: String?

    // Maxima section visibility (persisted preference)
    @Published public var maximaEnabled: Bool = UserDefaults.standard.bool(forKey: "maximaEnabled") {
        didSet { UserDefaults.standard.set(maximaEnabled, forKey: "maximaEnabled") }
    }

    // Draconis self-update
    @Published public var draconisUpdateAvailable: DraconisUpdater.Release?
    @Published public var draconisUpdating: Bool = false
    @Published public var draconisUpdateProgress: DraconisUpdater.Progress?
    @Published public var draconisUpdateError: String?

    public var selectedBottle: WineBottle? {
        bottles.first { $0.id == selectedBottleID }
    }

    private var activationObserver: NSObjectProtocol?

    public init() {
        DebugLog.shared.info("app", "Draconis starting up")

        // Re-check Maxima state when the user comes back to Draconis — covers
        // the case where they installed Maxima inside CrossOver or registered
        // the helper from outside, without re-opening the app.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshMaximaState()
            }
        }
    }

    deinit {
        if let observer = activationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Bootstrap

    public func bootstrap() async {
        await refreshCrossOverState()
        await refreshBottles()
        if bottles.isEmpty {
            showOnboarding = true
        } else if selectedBottleID == nil {
            selectedBottleID = bottles.first(where: \.hasNorthstar)?.id
                ?? bottles.first(where: \.hasTitanfall2)?.id
                ?? bottles.first?.id
        }
        try? await refreshNorthstarReleases()
        await refreshMaximaState()
        await checkMaximaForUpdate()
        await checkDraconisForUpdate()

        // Defer Northstar's auto-update when a Draconis update is pending.
        // Running both simultaneously means two progress bars, two downloads
        // competing for bandwidth, and a confusing "is the app about to quit
        // or am I supposed to wait?" situation for the user. The Northstar
        // check will run again the next time Draconis launches, which (if the
        // user updates) is immediately after the self-update relaunch.
        if draconisUpdateAvailable != nil {
            DebugLog.shared.info("app",
                "Draconis update pending — skipping Northstar auto-update this launch")
            return
        }

        // Auto-update Northstar when it is already installed and a newer
        // release is available. If Northstar isn't installed yet we leave the
        // Install button enabled so the user triggers it manually.
        if let bottle = selectedBottle, bottle.hasNorthstar,
           let latest = northstarReleases.first {
            let installed = bottle.northstarVersion
            if Self.northstarVersionMatches(installed: installed, releaseTag: latest.tagName) {
                DebugLog.shared.ok("app", "Northstar is up to date (\(latest.tagName))")
            } else {
                DebugLog.shared.info("app",
                    "Northstar update: installed=\(installed ?? "unknown") → latest=\(latest.tagName)")
                await installLatestNorthstar()
            }
        }
    }

    /// Northstar writes the *unprefixed* semver into `ns_version.txt` (e.g.
    /// `1.30.0`), while GitHub releases are tagged with a `v` prefix (e.g.
    /// `v1.30.0`). Compare after stripping the prefix from both so the
    /// auto-updater doesn't re-extract the same release every launch.
    nonisolated static func northstarVersionMatches(installed: String?, releaseTag: String) -> Bool {
        guard let installed else { return false }
        return stripV(installed) == stripV(releaseTag)
    }

    private nonisolated static func stripV(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    public func refreshCrossOverState() async {
        crossOverInstalled = await WineBackendManager.shared.isCrossOverAvailable()
        DebugLog.shared.info(
            "app",
            crossOverInstalled
                ? "CrossOver detected at \(PathResolver.crossOverApp.path)"
                : "CrossOver not installed."
        )
    }

    public func refreshBottles() async {
        DebugLog.shared.info("app", "Scanning CrossOver bottles…")
        bottles = await WineBackendManager.shared.allBottles()
        if let id = selectedBottleID, !bottles.contains(where: { $0.id == id }) {
            selectedBottleID = bottles.first?.id
        }
        DebugLog.shared.ok("app", "Found \(bottles.count) bottle(s).")
        await refreshMaximaState()
    }

    /// Open CrossOver.app so the user can create a Titanfall 2 bottle from
    /// CrossOver's install profile (which handles win10_64 template + DXVK
    /// settings + Steam install correctly). Draconis no longer drives bottle
    /// creation programmatically — `cxbottle --create` plus our AppleScript
    /// hand-off was brittle and couldn't reach CrossOver's CrossTie database.
    public func openCrossOver() {
        NSWorkspace.shared.open(PathResolver.crossOverApp)
    }

    // MARK: - Auto bottle install

    /// Hand the bundled Titanfall2.tie off to CrossOver and start polling
    /// CrossOver's bottle directory every 5 s. UI observes `autoInstallStage`.
    public func startAutoBottleInstall(frontend: BottleInstaller.Frontend) {
        guard frontend == .steam else {
            DebugLog.shared.warn("bottle.auto", "\(frontend.displayName) frontend not implemented yet")
            return
        }
        autoInstallStage = .waitingForBottle
        _ = BottleInstaller.shared.openTitanfall2Crosstie()
        BottleInstaller.shared.startWatching(interval: 5) { [weak self] stage in
            guard let self else { return }
            self.autoInstallStage = stage
            Task { await self.refreshBottles() }
            if case .waitingForTitanfall(let id) = stage {
                self.selectedBottleID = id
            }
            if case .done(let id) = stage {
                self.selectedBottleID = id
            }
        }
    }

    public func cancelAutoBottleInstall() {
        BottleInstaller.shared.stopWatching()
        autoInstallStage = nil
    }

    // MARK: - Auto bottle install

    /// Start watching for a bottle to appear without opening the CrossTie.
    /// Used by the manual onboarding path so progress steps update as the
    /// user installs things inside CrossOver themselves.
    public func startManualBottleWatching() {
        autoInstallStage = .waitingForBottle
        BottleInstaller.shared.startWatching(interval: 5) { [weak self] stage in
            guard let self else { return }
            self.autoInstallStage = stage
            Task { await self.refreshBottles() }
            if case .waitingForTitanfall(let id) = stage { self.selectedBottleID = id }
            if case .done(let id) = stage { self.selectedBottleID = id }
        }
    }

    // MARK: - Maxima

    public func checkMaximaForUpdate() async {
        maximaUpdateAvailable = await MaximaService.shared.isUpdateAvailable()
        if maximaUpdateAvailable {
            DebugLog.shared.info("maxima",
                "Update available: local=\(MaximaService.shared.installedVersion ?? "?") → newer release found")
        }
    }

    public func refreshMaximaState() async {
        guard let bottle = selectedBottle else {
            maximaInstalled = false
            maximaHelperRegistered = false
            maximaInstalledVersion = nil
            return
        }
        maximaInstalled = await MaximaService.shared.isInstalled(in: bottle)
        maximaHelperRegistered = await MaximaService.shared.isHelperRegistered()
        maximaInstalledVersion = MaximaService.shared.installedVersion
    }

    public func setupMaxima() async {
        guard let bottle = selectedBottle else { return }
        maximaSettingUp = true
        maximaError = nil
        maximaProgress = nil
        defer { maximaSettingUp = false; maximaProgress = nil }
        do {
            // If maxima-cli.exe is already in the bottle, skip the installer
            // and just (re-)register the helper — this is the most common
            // recovery path when the URL handler binding got lost.
            if await MaximaService.shared.isInstalled(in: bottle) {
                maximaProgress = .init(phase: .registeringHelper, fraction: -1,
                                       detail: "Registering MaximaHelper…")
                try await MaximaService.shared.registerHelper()
            } else {
                try await MaximaService.shared.downloadAndInstall(into: bottle) { @Sendable p in
                    Task { @MainActor in self.maximaProgress = p }
                }
            }
            await refreshMaximaState()
            await checkMaximaForUpdate()
        } catch {
            maximaError = error.localizedDescription
            DebugLog.shared.error("maxima", error.localizedDescription)
        }
    }

    /// Downloads and installs the latest Maxima release regardless of whether
    /// a previous version is already in the bottle. Called when the user
    /// explicitly clicks "Update Maxima".
    public func updateMaxima() async {
        guard let bottle = selectedBottle else { return }
        maximaSettingUp = true
        maximaError = nil
        maximaProgress = nil
        defer { maximaSettingUp = false; maximaProgress = nil }
        do {
            try await MaximaService.shared.downloadAndInstall(into: bottle) { @Sendable p in
                Task { @MainActor in self.maximaProgress = p }
            }
            await refreshMaximaState()
            await checkMaximaForUpdate()
        } catch {
            maximaError = error.localizedDescription
            DebugLog.shared.error("maxima", error.localizedDescription)
        }
    }

    public func uninstallMaxima() async {
        maximaSettingUp = true
        maximaError = nil
        maximaProgress = nil
        defer { maximaSettingUp = false; maximaProgress = nil }
        do {
            // If Maxima is in the bottle, run its uninstaller (which also
            // unregisters the helper at the end). Otherwise just unregister
            // the helper so another app can claim qrc://.
            if let bottle = selectedBottle,
               await MaximaService.shared.isInstalled(in: bottle) {
                try await MaximaService.shared.uninstall(from: bottle) { @Sendable p in
                    Task { @MainActor in self.maximaProgress = p }
                }
            } else {
                try await MaximaService.shared.unregisterHelper()
            }
            // Rescan bottles so WineBottle structs reflect the removed files.
            // refreshBottles() calls refreshMaximaState() internally, so a
            // second explicit call is not needed.
            await refreshBottles()
        } catch {
            maximaError = error.localizedDescription
            DebugLog.shared.error("maxima", error.localizedDescription)
        }
    }

    // MARK: - Launch

    public func launch(mode: NorthstarLauncher.LaunchMode) async {
        guard let bottle = selectedBottle else { return }
        launchInFlight = true
        defer { launchInFlight = false }
        do {
            _ = try await NorthstarLauncher.shared.launch(bottle: bottle, mode: mode)
            lastLaunchError = nil
        } catch {
            lastLaunchError = error.localizedDescription
            DebugLog.shared.error("app", error.localizedDescription)
        }
    }

    // MARK: - Mods

    public func refreshThunderstore() async {
        modsLoading = true
        modsLoadError = nil
        defer { modsLoading = false }
        do {
            thunderstorePackages = try await ThunderstoreClient.shared.listPackages()
        } catch {
            thunderstorePackages = []
            modsLoadError = error.localizedDescription
        }
        if let bottle = selectedBottle {
            installedMods = ThunderstoreClient.shared.installedMods(in: bottle)
        }
    }

    public func installMod(_ version: ThunderstoreVersion) async throws {
        guard let bottle = selectedBottle else { return }
        try await ThunderstoreClient.shared.install(version, into: bottle)
        installedMods = ThunderstoreClient.shared.installedMods(in: bottle)
    }

    /// Install a `.zip` from the user's disk (drag-and-drop in the Mods view).
    public func installLocalMod(at url: URL) async {
        guard let bottle = selectedBottle else { return }
        modsLoadError = nil
        do {
            try await ThunderstoreClient.shared.installLocalZip(at: url, into: bottle)
            installedMods = ThunderstoreClient.shared.installedMods(in: bottle)
        } catch {
            modsLoadError = error.localizedDescription
            DebugLog.shared.error("thunderstore", error.localizedDescription)
        }
    }

    public func setMod(_ mod: InstalledMod, enabled: Bool) {
        guard let bottle = selectedBottle else { return }
        do {
            try ThunderstoreClient.shared.setEnabled(enabled, mod: mod, in: bottle)
            installedMods = ThunderstoreClient.shared.installedMods(in: bottle)
        } catch {
            DebugLog.shared.error("thunderstore", "Couldn't toggle \(mod.name): \(error.localizedDescription)")
        }
    }

    public func uninstallMod(_ mod: InstalledMod) {
        guard let bottle = selectedBottle else { return }
        do {
            try ThunderstoreClient.shared.uninstall(mod)
            installedMods = ThunderstoreClient.shared.installedMods(in: bottle)
        } catch {
            DebugLog.shared.error("thunderstore", "Couldn't uninstall \(mod.name): \(error.localizedDescription)")
        }
    }

    /// Map of installed-mod-name → latest Thunderstore version, used by the
    /// Installed list to flag mods with available updates.
    public var modUpdatesAvailable: [String: ThunderstoreVersion] {
        var byModName: [String: ThunderstoreVersion] = [:]
        for pkg in thunderstorePackages {
            guard let latest = pkg.latest else { continue }
            byModName[pkg.name] = latest
        }
        var out: [String: ThunderstoreVersion] = [:]
        for mod in installedMods {
            guard let latest = byModName[mod.name] else { continue }
            if mod.version != latest.versionNumber {
                out[mod.name] = latest
            }
        }
        return out
    }

    // MARK: - Servers

    public func refreshServers() async {
        serversLoading = true
        defer { serversLoading = false }
        do {
            servers = try await ServerBrowserClient.shared.servers()
        } catch {
            servers = []
            DebugLog.shared.error("app", "Server refresh failed: \(error.localizedDescription)")
        }
    }

    public var filteredServers: [NorthstarServer] {
        let needle = serverFilter.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return servers }
        return servers.filter {
            $0.name.localizedCaseInsensitiveContains(needle)
            || $0.map.localizedCaseInsensitiveContains(needle)
            || $0.playlist.localizedCaseInsensitiveContains(needle)
        }
    }

    // MARK: - Northstar updates with progress

    public func refreshNorthstarReleases() async throws {
        northstarReleases = try await NorthstarUpdater.shared
            .availableReleases(includePrerelease: false)
    }

    public func installSteam() async {
        guard let bottle = selectedBottle else { return }
        steamInstalling = true
        defer { steamInstalling = false }
        do {
            try await SteamInstaller.shared.install(into: bottle)
        } catch {
            lastLaunchError = error.localizedDescription
        }
    }

    public func uninstallNorthstar() async {
        guard let bottle = selectedBottle, !updating else { return }
        updating = true
        lastUpdateError = nil
        updateProgress = .init(phase: .extracting, fraction: -1,
                               detail: "Removing Northstar files…")
        defer { updating = false; updateProgress = nil }
        do {
            try await NorthstarUpdater.shared.uninstall(from: bottle)
            await refreshBottles()
        } catch {
            DebugLog.shared.error("app", error.localizedDescription)
            lastUpdateError = error.localizedDescription
        }
    }

    // MARK: - Draconis self-update

    public func checkDraconisForUpdate() async {
        draconisUpdateAvailable = await DraconisUpdater.shared.availableUpdate()
    }

    public func installDraconisUpdate() async {
        guard let release = draconisUpdateAvailable, !draconisUpdating else { return }
        draconisUpdating = true
        draconisUpdateError = nil
        draconisUpdateProgress = nil
        defer {
            draconisUpdating = false
            draconisUpdateProgress = nil
        }
        do {
            try await DraconisUpdater.shared.install(release) { @Sendable p in
                Task { @MainActor in self.draconisUpdateProgress = p }
            }
        } catch {
            draconisUpdateError = error.localizedDescription
            DebugLog.shared.error("draconis.update", error.localizedDescription)
        }
    }

    /// Dismiss the prompt for *this session only* — next launch will check again.
    public func skipDraconisUpdateOnce() {
        draconisUpdateAvailable = nil
    }

    /// Persistently skip the offered tag — only re-prompt when an even newer
    /// release appears.
    public func skipDraconisUpdateForever() {
        guard let tag = draconisUpdateAvailable?.tagName else { return }
        DraconisUpdater.shared.setSkipped(tag)
        draconisUpdateAvailable = nil
    }

    public func installLatestNorthstar() async {
        guard let bottle = selectedBottle else { return }
        updating = true
        updateProgress = .init(phase: .fetchingReleases, fraction: -1,
                               detail: "Looking up latest release…")
        lastUpdateError = nil
        defer { updating = false; updateProgress = nil }

        do {
            let latest = try await NorthstarUpdater.shared.latestRelease()
            DebugLog.shared.ok("app", "Latest Northstar = \(latest.tagName)")

            let zip = try await NorthstarUpdater.shared.downloadRelease(latest) { @Sendable progress in
                Task { @MainActor in self.updateProgress = progress }
            }
            try await NorthstarUpdater.shared.install(
                zipURL: zip, into: bottle
            ) { @Sendable progress in
                Task { @MainActor in self.updateProgress = progress }
            }
            await refreshBottles()
        } catch {
            DebugLog.shared.error("app", error.localizedDescription)
            lastUpdateError = error.localizedDescription
        }
    }
}
