import Foundation
import SwiftUI
import AppKit
import Combine
import Sentry

/// Single source of truth for app-wide state.
@MainActor
public final class AppEnvironment: ObservableObject {

    // CrossOver bottles and Draconis Wine prefixes
    @Published public private(set) var bottles: [WineBottle] = []
    @Published public var selectedBottleID: String?

    // CrossOver availability (true iff LaunchServices knows the bundle ID)
    @Published public private(set) var crossOverInstalled: Bool = false

    // Launch status
    @Published public var launchInFlight: Bool = false
    @Published public var lastLaunchError: String?

    // Mods
    @Published public private(set) var thunderstorePackages: [ThunderstorePackage] = [] {
        didSet { recomputeModUpdates() }
    }
    @Published public private(set) var installedMods: [InstalledMod] = [] {
        didSet { recomputeModUpdates() }
    }
    @Published public private(set) var modUpdatesAvailable: [String: ThunderstoreVersion] = [:]
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

    // Privacy consent — mirrors ConsentManager so views can react to changes.
    @Published public var privacyConsentAccepted: Bool = ConsentManager.isAccepted

    // Bug report sheet
    @Published public var showBugReport: Bool = false

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
    @Published public var setupStatus: String?
    @Published public var setupError: String?
    @Published public var engineProgress: NorthstarUpdater.Progress?
    private var setupTask: Task<Void, Never>?

    /// Where new bottles go. Defaults to CrossOver when it's installed.
    @Published public var preferredBackend: WineBackend =
        WineBackend(rawValue: UserDefaults.standard.string(forKey: "preferredBackend") ?? "") ?? .crossover {
        didSet { UserDefaults.standard.set(preferredBackend.rawValue, forKey: "preferredBackend") }
    }

    @Published public var epicAccount: String?
    @Published public var epicBusy = false
    @Published public var epicError: String?
    @Published public private(set) var heroicSource: HeroicImporter.Source?

    // Maxima
    @Published public var maximaInstalled: Bool = false
    @Published public var maximaHelperRegistered: Bool = false
    @Published public var maximaSettingUp: Bool = false
    @Published public var maximaProgress: MaximaService.Progress?
    @Published public var maximaError: String?

    /// Cached result of the most recent `maxima-cli list-games --json`
    /// run. `nil` when never fetched; an empty array means Maxima
    /// responded but the user's EA library has no recognised games.
    @Published public var maximaLibrary: [MaximaService.OwnedGame]?
    @Published public var maximaLibraryError: String?

    /// True while a CEG-fix run is in flight. UI hides the button and
    /// shows a spinner while this is `true`.
    @Published public var cegFixRunning: Bool = false
    @Published public var cegFixError: String?
    @Published public var maximaUpdateAvailable: Bool = false
    @Published public var maximaInstalledVersion: String?

    /// True while the user's chosen `MaximaRole` is being applied
    /// (install / uninstall / CEG fix in progress). UI disables the
    /// Apply button + shows a spinner.
    @Published public var applyingMaximaRole: Bool = false
    @Published public var maximaRoleError: String?

    /// Phase of the wizard's Maxima-route auto-install flow. Drives
    /// the copy + button state on the progress page so the user can
    /// see what's happening (Maxima still booting? login? game
    /// downloading? almost done?). Independent of `autoInstallStage`
    /// which is owned by the BottleInstaller poller.
    @Published public var maximaSetupPhase: MaximaSetupPhase = .idle

    /// Handle to the background install + polling task spawned by
    /// `startGameInstallViaUI`. Stored so the wizard can cancel the
    /// 2-hour polling loop if the user backs out / re-enters / closes
    /// Draconis — otherwise the loop leaks and could later flip
    /// `maximaSetupPhase` to a stale value.
    private var maximaInstallTask: Task<Void, Never>?

    /// Public so the OnboardingView can pattern-match phase
    /// transitions without re-implementing the comparison logic.
    public enum MaximaSetupPhase: Equatable, Sendable {
        /// Either the wizard isn't on the Maxima route, or we've
        /// already finished and gone idle.
        case idle
        /// `maxima.exe --install ...` has been spawned. The user is
        /// either logging in or watching the download bar inside
        /// Maxima's own UI. We poll for `FInstall.txt` in the
        /// background.
        case installingGame(pid: pid_t, slug: String, installPath: String)
        /// `FInstall.txt` appeared. We're SIGTERM-ing maxima.exe to
        /// close it gracefully, then we'll move to `.done`.
        case finishing
        /// All done — wizard can advance.
        case done
        /// Something went wrong (maxima.exe exited before marker
        /// appeared, spawn failed, etc.). The user can retry from
        /// the wizard.
        case failed(String)
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
        await refreshEpicAccount()

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
        if !crossOverInstalled, UserDefaults.standard.string(forKey: "preferredBackend") == nil {
            preferredBackend = .draconis
        }
        heroicSource = HeroicImporter.detect()
        DebugLog.shared.info(
            "app",
            crossOverInstalled
                ? "CrossOver detected at \(PathResolver.crossOverApp.path)"
                : "CrossOver not installed."
        )
    }

    public func refreshBottles() async {
        DebugLog.shared.info("app", "Scanning bottles…")
        bottles = await WineBackendManager.shared.allBottles()
        if let id = selectedBottleID, !bottles.contains(where: { $0.id == id }) {
            selectedBottleID = bottles.first?.id
        }
        DebugLog.shared.ok("app", "Found \(bottles.count) bottle(s).")
        await refreshMaximaState()
    }

    /// Open CrossOver.app — used when the user wants to inspect a bottle
    /// or run something inside it manually. Draconis itself drives bottle
    /// creation via `WineBottleCreator` (which wraps `cxbottle --create`)
    /// and launcher installation via `SteamInstaller` / `EAInstaller`.
    public func openCrossOver() {
        NSWorkspace.shared.open(PathResolver.crossOverApp)
    }

    // MARK: - Auto bottle install

    /// Create the bottle (CrossOver) or prefix (Draconis Wine), install the
    /// shared dependencies and the chosen launcher, then watch the bottle
    /// until Titanfall 2 lands. UI observes `autoInstallStage` / `setupStatus`.
    public func startAutoBottleInstall(
        frontend: BottleInstaller.Frontend,
        backend: WineBackend,
        bottleName: String? = nil
    ) {
        guard frontend.available(on: backend) else {
            DebugLog.shared.warn("bottle.auto", "\(frontend.displayName) isn't available with \(backend.displayName)")
            return
        }
        let bottleName = bottleName ?? "Titanfall 2"
        setupError = nil
        autoInstallStage = .waitingForBottle
        setupTask?.cancel()
        setupTask = Task { [weak self] in
            guard let self else { return }
            do {
                if backend == .draconis, !WineEngine.isInstalled {
                    self.setupStatus = "Downloading Draconis Wine…"
                    try await WineEngine.shared.install { p in
                        Task { @MainActor in self.engineProgress = p }
                    }
                    self.engineProgress = nil
                }

                self.setupStatus = "Creating “\(bottleName)”…"
                do {
                    try await WineBackendManager.shared.createBottle(
                        name: bottleName, backend: backend,
                        description: "Titanfall 2 / Northstar — created by Draconis (\(frontend.displayName))")
                } catch WineBottleCreator.CreatorError.bottleAlreadyExists(_), WineEngine.EngineError.prefixExists(_) {
                    DebugLog.shared.info("bottle.auto", "Reusing existing bottle \"\(bottleName)\"")
                }

                await self.refreshBottles()
                guard let bottle = self.bottles.first(where: { $0.name == bottleName && $0.backend == backend }) else {
                    throw WineBackendManager.BackendError.launchFailed("Couldn't find “\(bottleName)” after creating it")
                }
                self.selectedBottleID = bottle.id
                self.watchSetup(of: bottle)

                self.setupStatus = "Installing Visual C++ and DirectX components…"
                do {
                    try await BottleSetup.shared.prepare(bottle)
                } catch {
                    DebugLog.shared.warn("bottle.auto", "Dependency setup incomplete: \(error.localizedDescription)")
                }

                try await self.installFrontend(frontend, into: bottle)
                self.setupStatus = nil
                await self.refreshBottles()
            } catch is CancellationError {
                self.setupStatus = nil
            } catch {
                DebugLog.shared.error("bottle.auto", "Setup failed: \(error.localizedDescription)")
                self.setupError = error.localizedDescription
                self.setupStatus = nil
                if case .waitingForBottle = self.autoInstallStage { self.autoInstallStage = nil }
            }
        }
    }

    private func installFrontend(_ frontend: BottleInstaller.Frontend, into bottle: WineBottle) async throws {
        switch frontend {
        case .steam:
            if !(await SteamInstaller.shared.isSteamInstalled(in: bottle)) {
                setupStatus = "Installing Steam…"
                try await SteamInstaller.shared.install(into: bottle)
            }
            if !bottle.hasTitanfall2 {
                setupStatus = "Opening Titanfall 2 in Steam…"
                try await SteamInstaller.shared.openTitanfallInstall(in: bottle)
            }
        case .ea, .epic:
            if !(await EAInstaller.shared.isEAInstalled(in: bottle)) {
                setupStatus = "Installing the EA app…"
                try await EAInstaller.shared.install(into: bottle, silent: true)
            }
            if frontend == .epic, epicAccount != nil {
                setupStatus = "Handing Titanfall 2 to the EA app…"
                try await EpicService.shared.openInEAApp(bottle: bottle)
            } else if let exe = CrossOverDetector.locateEAApp(in: PathResolver.driveC(in: bottle.prefixURL)) {
                try await WineBackendManager.shared.spawn(executable: exe.path, in: bottle)
            }
        case .maxima:
            if await !MaximaService.shared.isInstalled(in: bottle) {
                setupStatus = "Installing Maxima…"
                try await MaximaService.shared.downloadAndInstall(into: bottle) { p in
                    Task { @MainActor in self.maximaProgress = p }
                }
            }
        }
    }

    private func watchSetup(of bottle: WineBottle) {
        BottleInstaller.shared.startWatching(bottleID: bottle.id, interval: 5) { [weak self] stage in
            guard let self else { return }
            self.autoInstallStage = stage
            Task {
                await self.refreshBottles()
                if case .done(let id) = stage { await self.finishSteamSetupIfNeeded(bottleID: id) }
            }
        }
    }

    /// A Steam copy of Titanfall 2 only gets the EA app (its sign-in) the
    /// first time Steam runs the game, so do that run for the user.
    private func finishSteamSetupIfNeeded(bottleID: String) async {
        guard let bottle = bottles.first(where: { $0.id == bottleID }),
              bottle.hasSteam, bottle.hasTitanfall2, !bottle.hasEAApp, bottle.maximaRole == .none
        else { return }
        await runTitanfallThroughSteam(in: bottle)
    }

    public func runTitanfallThroughSteam(in bottle: WineBottle) async {
        DebugLog.shared.info("steam", "Starting Titanfall 2 once through Steam so it installs the EA app…")
        setupStatus = "Steam is installing the EA app for Titanfall 2…"
        do {
            try await SteamInstaller.shared.launchTitanfallThroughSteam(in: bottle)
        } catch {
            setupError = error.localizedDescription
        }
    }

    // MARK: - Epic / Heroic

    public func refreshEpicAccount() async {
        epicAccount = await EpicService.shared.account()
    }

    public func signInToEpic(code: String) async {
        epicBusy = true
        defer { epicBusy = false }
        epicError = nil
        do {
            epicAccount = try await EpicService.shared.signIn(code: code)
        } catch {
            epicError = error.localizedDescription
        }
    }

    public func signOutOfEpic() async {
        await EpicService.shared.signOut()
        epicAccount = nil
    }

    /// Let the bottle's EA app install / run the Epic copy of Titanfall 2.
    public func openEpicTitanfall(in bottle: WineBottle) async {
        epicBusy = true
        defer { epicBusy = false }
        epicError = nil
        do {
            if !(await EAInstaller.shared.isEAInstalled(in: bottle)) {
                try await EAInstaller.shared.install(into: bottle, silent: true)
            }
            try await EpicService.shared.openInEAApp(bottle: bottle)
        } catch {
            epicError = error.localizedDescription
        }
    }

    public func importFromHeroic() async -> WineBottle? {
        do {
            let name = try HeroicImporter.importTitanfall()
            await refreshBottles()
            let bottle = bottles.first(where: { $0.name == name })
            selectedBottleID = bottle?.id ?? selectedBottleID
            return bottle
        } catch {
            setupError = error.localizedDescription
            return nil
        }
    }

    public func cancelAutoBottleInstall() {
        BottleInstaller.shared.stopWatching()
        setupTask?.cancel()
        setupTask = nil
        setupStatus = nil
        autoInstallStage = nil
        // Tear down the maxima-route install/poll loop too — if the
        // user closes the wizard mid-install, we don't want a 2-hour
        // background poller surviving and later mutating
        // `maximaSetupPhase` against an out-of-date UI.
        maximaInstallTask?.cancel()
        maximaInstallTask = nil
        if case .installingGame = maximaSetupPhase {
            maximaSetupPhase = .idle
        }
    }

    /// Attach the wizard's progress watcher to an existing bottle the
    /// user picked from the bottle-choice page. Same `BottleInstaller`
    /// poller as `startAutoBottleInstall`, but skips bottle creation +
    /// launcher install (the bottle already owns whichever launcher is
    /// in it; the watcher will just report whichever stage matches
    /// what's already present and advance as the user installs the
    /// rest manually inside the existing launcher).
    public func resumeAutoWatching(forBottle bottle: WineBottle) {
        selectedBottleID = bottle.id
        autoInstallStage = bottle.isTitanfallInstallComplete
            ? .done(bottleID: bottle.id)
            : (bottle.hasLauncher || bottle.hasMaxima
                ? .waitingForTitanfall(bottleID: bottle.id)
                : .waitingForBottle)
        watchSetup(of: bottle)
    }

    // MARK: - Maxima CLI integration

    /// Refresh `maximaLibrary` by running `maxima-cli list-games --json`
    /// in the given bottle. Caller is typically a Settings / Maxima
    /// section "Refresh library" button. The CLI requires the user to
    /// have completed OAuth at least once — surface `.notLoggedIn`
    /// errors clearly so the user knows what to do.
    public func loadMaximaLibrary(in bottle: WineBottle) {
        Task { [weak self] in
            guard let self else { return }
            await MainActor.run { self.maximaLibraryError = nil }
            do {
                let games = try await MaximaService.shared.listGames(in: bottle)
                await MainActor.run { self.maximaLibrary = games }
            } catch let error as MaximaService.CliError {
                DebugLog.shared.error("maxima.cli", error.localizedDescription)
                await MainActor.run {
                    self.maximaLibrary = []
                    self.maximaLibraryError = error.localizedDescription
                }
            } catch {
                DebugLog.shared.error("maxima.cli", error.localizedDescription)
                await MainActor.run {
                    self.maximaLibrary = []
                    self.maximaLibraryError = error.localizedDescription
                }
            }
        }
    }

    /// Apply the Steam-CEG fix to a Titanfall 2 install: surgical
    /// replacement of `Titanfall2.exe` + `Titanfall2_trial.exe` with
    /// the EA originals via `maxima-cli install --replace-files
    /// --only-listed-files`. ~3 MB download, <60 s on a normal
    /// connection.
    ///
    /// `gamePath` must point at the TF2 install root (e.g.
    /// `C:\Program Files (x86)\Steam\steamapps\common\Titanfall2`).
    /// Caller is responsible for confirming the user actually wants
    /// to apply this — the dialog component handles that.
    public func applyCegFix(in bottle: WineBottle, gamePath: String) {
        guard !cegFixRunning else { return }
        cegFixRunning = true
        cegFixError = nil
        Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.cegFixRunning = false
                }
            }
            guard let self else { return }
            do {
                try await MaximaService.shared.applyCegFix(
                    in: bottle,
                    gamePath: gamePath
                )
                await self.refreshBottles()
            } catch {
                DebugLog.shared.error("maxima.ceg", error.localizedDescription)
                await MainActor.run {
                    self.cegFixError = error.localizedDescription
                }
            }
        }
    }

    /// Drive a `MaximaRole` choice for a bottle end-to-end:
    /// install/uninstall Maxima as needed, register the helper, apply
    /// the CEG fix for `.fullReplace`, persist the role to UserDefaults
    /// so `WineBottle.maximaRole` reads it back at launch time.
    ///
    /// UI binding lives on the wizard's MaximaRole page — the button
    /// reads `applyingMaximaRole` for spinner state and `maximaRoleError`
    /// for surface display.
    public func applyMaximaRole(_ role: MaximaRole, in bottle: WineBottle) async {
        guard !applyingMaximaRole else { return }
        await MainActor.run {
            self.applyingMaximaRole = true
            self.maximaRoleError = nil
        }
        defer {
            Task { @MainActor [weak self] in
                self?.applyingMaximaRole = false
            }
        }

        do {
            try await MaximaService.shared.applyRole(role, in: bottle) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.maximaProgress = progress
                }
            }
            // Refresh detection so `hasMaxima` + `maximaRole` reads
            // are current before the wizard advances.
            await refreshBottles()
            await refreshMaximaState()
        } catch {
            DebugLog.shared.error("maxima.role", error.localizedDescription)
            SentrySDK.capture(error: error) { scope in
                scope.setTag(value: "applyMaximaRole", key: "operation")
                scope.setTag(value: role.rawValue, key: "maxima.role")
            }
            await MainActor.run {
                self.maximaRoleError = error.localizedDescription
            }
        }
    }

    /// Wizard's Maxima-route end game: spawn `maxima.exe --install
    /// <slug> --install-path <path>` (added in Maxima-Draconis
    /// v0.12.0), then watch the install dir for `FInstall.txt`
    /// (`INSTALL_MARKER_FILENAME` upstream, written by
    /// `ContentManager::update` when the download settles). When the
    /// marker appears, gracefully terminate maxima.exe via SIGTERM
    /// (escalating to SIGKILL after 5s) and mark the phase done.
    /// If maxima exits before the marker appears, surface a clear
    /// error so the user can retry instead of staring at a frozen
    /// wizard.
    ///
    /// Idempotent against `maximaSetupPhase` — if a flow is already
    /// in progress this is a no-op, so re-entering the progress page
    /// doesn't spawn a second maxima.exe.
    public func startGameInstallViaUI(
        slug: String,
        in bottle: WineBottle,
        installPath: String = MaximaService.defaultTitanfall2WindowsPath
    ) {
        // Synchronous lock against the .idle slot — `onAppear` can
        // fire multiple times during view transitions, and
        // `startGameInstallViaUI` contains await points before its
        // first state mutation, so two near-simultaneous calls could
        // both pass an "is idle?" check inside the Task and end up
        // spawning maxima.exe twice. Flip the phase here, before any
        // async work, so the second caller bails immediately.
        if case .idle = maximaSetupPhase {
            // pid 0 is a sentinel — the real pid lands once
            // installGameViaUI returns. We use 0 just to take the
            // slot; consumers shouldn't read pid until phase has
            // transitioned through the async spawn.
            maximaSetupPhase = .installingGame(
                pid: 0,
                slug: slug,
                installPath: installPath
            )
        } else {
            return
        }
        maximaError = nil
        // Cancel any prior task before launching a new one (defensive;
        // the .idle gate above should prevent overlap, but explicit
        // beats implicit).
        maximaInstallTask?.cancel()
        maximaInstallTask = Task { [weak self] in
            guard let self else { return }
            // Early out if FInstall.txt is already on disk from a
            // previous run. We do this inside the Task because
            // `didInstallComplete` is actor-isolated to MaximaService.
            if await MaximaService.shared.didInstallComplete(in: bottle, installPath: installPath) {
                DebugLog.shared.info(
                    "maxima.install",
                    "FInstall.txt already present at \(installPath) — marking done"
                )
                await MainActor.run {
                    self.maximaSetupPhase = .done
                }
                return
            }
            do {
                let pid = try await MaximaService.shared.installGameViaUI(
                    in: bottle,
                    slug: slug,
                    installPath: installPath
                )
                await MainActor.run {
                    self.maximaSetupPhase = .installingGame(
                        pid: pid,
                        slug: slug,
                        installPath: installPath
                    )
                }
                await self.pollForInstallCompletion(
                    pid: pid,
                    bottle: bottle,
                    installPath: installPath
                )
            } catch is CancellationError {
                DebugLog.shared.info("maxima.install", "Install task cancelled")
            } catch {
                DebugLog.shared.error("maxima.install", error.localizedDescription)
                SentrySDK.capture(error: error) { scope in
                    scope.setTag(value: "startGameInstallViaUI", key: "operation")
                    scope.setTag(value: slug, key: "maxima.slug")
                }
                await MainActor.run {
                    self.maximaSetupPhase = .failed(error.localizedDescription)
                    self.maximaError = error.localizedDescription
                }
            }
        }
    }

    /// Polling loop for the `FInstall.txt` marker. Runs in the
    /// background after `installGameViaUI` returns; check every 2s
    /// up to a generous ceiling. If the spawned `maxima.exe` exits
    /// before the marker appears, treat that as user cancellation /
    /// failure rather than success.
    ///
    /// 2s is a deliberate compromise: faster polls would spike disk
    /// I/O on a download that's writing many small files (lots of
    /// FileManager.fileExists calls during file growth races), and
    /// slower polls add visible UI lag.
    private func pollForInstallCompletion(
        pid: pid_t,
        bottle: WineBottle,
        installPath: String
    ) async {
        let pollInterval = Duration.seconds(2)
        // Upper bound: 2 hours. EA's CDN ranges from a few minutes
        // (Titanfall 2 over a fast line) to ~half-hour on slower
        // connections. 2h is way past any realistic completion
        // window — past it we assume something's stuck.
        let maxPolls = (2 * 60 * 60) / 2
        for _ in 0..<maxPolls {
            // `try` (not `try?`) so a wizard close / cancellation
            // propagates out of this loop as `CancellationError`
            // instead of being silently swallowed for the full 2h.
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                DebugLog.shared.info("maxima.install", "Polling loop cancelled")
                return
            }
            // Marker present? We're done.
            if await MaximaService.shared.didInstallComplete(in: bottle, installPath: installPath) {
                DebugLog.shared.ok(
                    "maxima.install",
                    "FInstall.txt detected at \(installPath) — closing maxima.exe"
                )
                await MainActor.run {
                    self.maximaSetupPhase = .finishing
                }
                await MaximaService.shared.signalProcessQuit(pid: pid)
                // Persist `.fullReplace` for this bottle so a future
                // wizard re-entry sees an explicit role and dismisses
                // instead of asking the user to pick again. (D-Bug
                // #45.) Maxima-installed bottles always carry the
                // EA-original binaries by construction — the user
                // already made the equivalent "full replace" choice
                // by picking the Maxima install route at the source
                // picker, so we record it implicitly here.
                MaximaRole.save(.fullReplace, forBottle: bottle.id)
                await self.refreshBottles()
                await MainActor.run {
                    self.maximaSetupPhase = .done
                }
                return
            }
            // Process gone without marker? User canceled or it crashed.
            // `kill(pid, 0)` returns -1 (with errno=ESRCH) when the
            // process no longer exists.
            if Darwin.kill(pid, 0) != 0 {
                let msg = "Maxima closed before the install finished (no FInstall.txt at \(installPath))."
                DebugLog.shared.warn("maxima.install", msg)
                SentrySDK.capture(message: msg) { scope in
                    scope.setTag(value: "pollForInstallCompletion", key: "operation")
                    scope.setLevel(.warning)
                }
                await MainActor.run {
                    self.maximaSetupPhase = .failed(msg)
                    self.maximaError = msg
                }
                return
            }
        }
        // Hit the upper bound. Surface as failure so the user can
        // retry. We do NOT auto-kill maxima here — the user might
        // still want to interact with it.
        let msg = "Install didn't complete after 2 hours. Check Maxima for errors."
        DebugLog.shared.warn("maxima.install", msg)
        SentrySDK.capture(message: msg) { scope in
            scope.setTag(value: "pollForInstallCompletion", key: "operation")
            scope.setLevel(.warning)
        }
        await MainActor.run {
            self.maximaSetupPhase = .failed(msg)
            self.maximaError = msg
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
            syncSentryScope()
            return
        }
        maximaInstalled = await MaximaService.shared.isInstalled(in: bottle)
        maximaHelperRegistered = await MaximaService.shared.isHelperRegistered()
        maximaInstalledVersion = MaximaService.shared.installedVersion
        syncSentryScope()
    }

    // MARK: - Sentry scope sync

    /// Push current environment state into Sentry's scope so every event
    /// (crash, handled error, or manual bug report) carries up-to-date context
    /// without the user having to do anything.
    private func syncSentryScope() {
        guard ConsentManager.isAccepted else { return }
        let bottle = selectedBottle
        let nsVersion = bottle?.northstarVersion
        let maxVersion = maximaInstalledVersion
        SentrySDK.configureScope { scope in
            scope.setTag(value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                         key: "app.version")
            scope.setTag(value: self.crossOverInstalled ? "true" : "false",
                         key: "crossover.installed")
            scope.setTag(value: bottle != nil ? "true" : "false",
                         key: "bottle.exists")
            scope.setTag(value: bottle?.name ?? "none",
                         key: "bottle.name")
            scope.setTag(value: bottle?.hasTitanfall2 == true ? "true" : "false",
                         key: "bottle.hasTF2")
            scope.setTag(value: bottle?.hasNorthstar == true ? "true" : "false",
                         key: "bottle.hasNS")
            scope.setTag(value: bottle?.hasSteam == true ? "true" : "false",
                         key: "bottle.hasSteam")
            scope.setTag(value: bottle?.hasEAApp == true ? "true" : "false",
                         key: "bottle.hasEA")
            scope.setTag(value: bottle?.hasMaxima == true ? "true" : "false",
                         key: "bottle.hasMaxima")
            scope.setTag(value: bottle?.maximaRole.rawValue ?? "none",
                         key: "maxima.role")
            if let v = nsVersion  { scope.setTag(value: v, key: "northstar.version") }
            if let v = maxVersion { scope.setTag(value: v, key: "maxima.version") }
        }
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
            // refreshBottles() refreshes per-bottle `hasMaxima` AND
            // calls refreshMaximaState() — covers the case where the
            // installer just dropped binaries into the bottle (same
            // gap as `updateMaxima`, D-Bug #44).
            await refreshBottles()
            await checkMaximaForUpdate()
        } catch {
            maximaError = error.localizedDescription
            DebugLog.shared.error("maxima", error.localizedDescription)
            SentrySDK.capture(error: error) { scope in
                scope.setTag(value: "setupMaxima", key: "operation")
            }
        }
    }

    /// Downloads and installs the latest Maxima release regardless of whether
    /// a previous version is already in the bottle. Called when the user
    /// explicitly clicks "Update Maxima".
    ///
    /// Internally `downloadAndInstall` runs the NSIS uninstaller first
    /// (best-effort) and then the new installer, so for a brief window
    /// the bottle has no `maxima-cli.exe`. We need to refresh both
    /// `bottle.hasMaxima` (via `refreshBottles`) AND the derived
    /// `env.maximaInstalled` (via `refreshMaximaState`) after the
    /// install completes — `refreshMaximaState` alone wouldn't update
    /// the per-bottle `hasMaxima` field used by `PlayView`'s launcher
    /// pill and Onboarding wizard, leaving the UI showing "Maxima not
    /// installed" until the user manually rescans bottles. (D-Bug #44.)
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
            // refreshBottles() rebuilds the WineBottle list (so
            // `selectedBottle.hasMaxima` reflects the freshly-installed
            // binaries) AND calls refreshMaximaState() internally —
            // a separate refreshMaximaState call would be redundant.
            await refreshBottles()
            await checkMaximaForUpdate()
        } catch {
            maximaError = error.localizedDescription
            DebugLog.shared.error("maxima", error.localizedDescription)
            SentrySDK.capture(error: error) { scope in
                scope.setTag(value: "updateMaxima", key: "operation")
            }
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

    /// Background task tailing the per-bottle log into DebugLog. Held
    /// only while `launchInFlight` is true; cancelled on game exit so
    /// we're not reading a file forever.
    private var logTailTask: Task<Void, Never>?

    public func launch(mode: NorthstarLauncher.LaunchMode) async {
        guard let bottle = selectedBottle else { return }
        guard !launchInFlight else {
            DebugLog.shared.warn("app", "Launch already in flight — ignoring duplicate click.")
            return
        }
        launchInFlight = true

        // Make Draconis's in-app console visible so the user sees the
        // wine + maxima-cli output stream as the launch progresses.
        // The console toggle persists in UserDefaults, so flipping it
        // here also sticks across restarts; that's intentional during
        // the wizard rewrite — once the integration is stable the
        // auto-open behavior can be removed.
        showConsole = true

        // Truncate the log so the tail starts from the new launch's
        // output instead of replaying whatever's left from the
        // previous run. ProcessRunner.detached opens the log in
        // append mode so writes continue from the file's new end.
        let logURL = PathResolver.bottleLogFile(for: bottle)
        try? FileManager.default.removeItem(at: logURL)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)

        // Start streaming the log into DebugLog. The task self-cancels
        // when pollUntilGameExits clears `launchInFlight`.
        logTailTask?.cancel()
        logTailTask = Task { [weak self] in
            await self?.streamBottleLog(at: logURL)
        }

        do {
            _ = try await NorthstarLauncher.shared.launch(bottle: bottle, mode: mode)
            lastLaunchError = nil
        } catch {
            lastLaunchError = error.localizedDescription
            DebugLog.shared.error("app", error.localizedDescription)
            SentrySDK.capture(error: error) { scope in
                scope.setTag(value: "launch", key: "operation")
                scope.setTag(value: mode.rawValue, key: "launch.mode")
            }
            launchInFlight = false
            logTailTask?.cancel()
            logTailTask = nil
            return
        }

        // cxstart returns within a second or two after forking the
        // launch chain. To make `launchInFlight` actually mean "the
        // game is running" (and keep the Play button disabled while
        // it is), we poll the host process list for `Titanfall2.exe`
        // and clear the flag once it disappears.
        Task { [weak self] in
            await self?.pollUntilGameExits()
        }
    }

    private func pollUntilGameExits() async {
        // Give the launch chain time to spawn TF2 before we start
        // polling — otherwise we'd see "no process yet" on the first
        // tick and clear `launchInFlight` immediately.
        try? await Task.sleep(for: .seconds(8))

        // Fallback for when CleanSpawn's responsibility disclaim is
        // unavailable: the game tree is then attributed to Draconis, and
        // Draconis going to App Nap behind the game window throttles it.
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Titanfall 2 is running"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }

        while await Self.isTitanfallRunning() {
            try? await Task.sleep(for: .seconds(3))
        }

        await MainActor.run {
            self.launchInFlight = false
            self.logTailTask?.cancel()
            self.logTailTask = nil
        }
        DebugLog.shared.info("app", "Titanfall 2 process exited.")
    }

    /// Host-side check: is `Titanfall2.exe` currently in the process
    /// list? `pgrep -f` matches against the full command line, which
    /// is where Wine's exec wrapper puts the Windows binary name.
    /// Returns true on exit code 0 (matches found), false otherwise.
    private static func isTitanfallRunning() async -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", "Titanfall2.exe"]
        // Discard pgrep's stdout (we only care about the exit code).
        let devNull = FileHandle(forWritingAtPath: "/dev/null")
        p.standardOutput = devNull
        p.standardError = devNull
        guard let status = try? await ProcessRunner.runUntilExit(p) else {
            return false
        }
        return status == 0
    }

    /// Follow the per-bottle log file and forward each new line to
    /// DebugLog so it shows in Draconis's in-app console. Cheaper than
    /// spawning a Terminal.app `tail -F` and keeps everything in one
    /// pane.
    ///
    /// The loop opens the file, seeks past whatever's already there,
    /// then sleeps + re-reads. New writes by `ProcessRunner.detached`
    /// (append-mode) appear in subsequent reads.
    private func streamBottleLog(at logURL: URL) async {
        // Wait briefly for the log file to exist (ProcessRunner may
        // not have created it yet at the moment we start).
        for _ in 0..<20 {
            if FileManager.default.fileExists(atPath: logURL.path) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let handle = try? FileHandle(forReadingFrom: logURL) else {
            DebugLog.shared.warn("app", "Couldn't open bottle log for tailing: \(logURL.path)")
            return
        }
        defer { try? handle.close() }

        var buffer = Data()
        while !Task.isCancelled {
            do {
                let chunk = try handle.read(upToCount: 8192) ?? Data()
                if chunk.isEmpty {
                    try? await Task.sleep(for: .milliseconds(300))
                    continue
                }
                buffer.append(chunk)
                // Split on newlines (\n) and emit complete lines.
                while let newlineIdx = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[..<newlineIdx]
                    buffer.removeSubrange(...newlineIdx)
                    let raw = String(data: lineData, encoding: .utf8) ?? ""
                    let line = raw.trimmingCharacters(
                        in: .whitespacesAndNewlines.union(.controlCharacters)
                    )
                    if !line.isEmpty {
                        DebugLog.shared.info("bottle.log", line)
                    }
                }
            } catch {
                try? await Task.sleep(for: .milliseconds(500))
            }
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

    private func recomputeModUpdates() {
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
        modUpdatesAvailable = out
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
            SentrySDK.capture(error: error) { scope in
                scope.setTag(value: "installLatestNorthstar", key: "operation")
            }
        }
    }
}
