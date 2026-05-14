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

    // MARK: - Maxima

    public func refreshMaximaState() async {
        guard let bottle = selectedBottle else {
            maximaInstalled = false
            maximaHelperRegistered = false
            return
        }
        maximaInstalled = await MaximaService.shared.isInstalled(in: bottle)
        maximaHelperRegistered = await MaximaService.shared.isHelperRegistered()
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
            await refreshMaximaState()
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
