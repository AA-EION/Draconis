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

    /// Open CrossOver.app — used when the user wants to inspect a bottle
    /// or run something inside it manually. Draconis itself drives bottle
    /// creation via `WineBottleCreator` (which wraps `cxbottle --create`)
    /// and launcher installation via `SteamInstaller` / `EAInstaller`.
    public func openCrossOver() {
        NSWorkspace.shared.open(PathResolver.crossOverApp)
    }

    // MARK: - Auto bottle install

    /// Create a fresh "Titanfall 2" bottle via `cxbottle --create`, then
    /// start polling CrossOver's bottle directory every 5 s for progress
    /// updates as the user installs their chosen launcher and the game
    /// inside it. UI observes `autoInstallStage`.
    ///
    /// The wizard drives each step explicitly:
    ///   1. Bottle creation (this method handles).
    ///   2. Launcher install (Steam / EA Desktop / Maxima) — user-driven
    ///      via the wizard's source picker; not all paths are wired up
    ///      yet in this PR.
    ///   3. Game install — user-driven through whichever launcher was
    ///      chosen.
    public func startAutoBottleInstall(
        frontend: BottleInstaller.Frontend,
        bottleName: String? = nil
    ) {
        guard frontend.available else {
            DebugLog.shared.warn("bottle.auto", "\(frontend.displayName) frontend not implemented yet")
            return
        }
        autoInstallStage = .waitingForBottle
        // Kick off bottle creation off-thread. The polling watcher is
        // started in parallel so the UI shows live progress (it will
        // initially report `.waitingForBottle` until the new directory
        // appears, then transition through the launcher / game stages
        // as the user installs the chosen launcher and Titanfall 2).
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
        Task { [weak self] in
            guard let self else { return }
            // 1. Create the bottle if it doesn't already exist.
            //    Caller may pass a custom name (used by the wizard's
            //    "Create new bottle" branch when an existing bottle
            //    already owns "Titanfall 2" — auto-suffixed there to
            //    avoid the `bottleAlreadyExists` no-op path).
            let bottleName = bottleName ?? "Titanfall 2"
            do {
                try await WineBottleCreator.shared.createBottle(
                    name: bottleName,
                    description: "Titanfall 2 / Northstar — created by Draconis (\(frontend.displayName))"
                )
            } catch WineBottleCreator.CreatorError.bottleAlreadyExists(let name) {
                DebugLog.shared.info("bottle.auto", "Reusing existing bottle \"\(name)\"")
            } catch {
                DebugLog.shared.error("bottle.auto", "Bottle creation failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.autoInstallStage = nil
                    BottleInstaller.shared.stopWatching()
                }
                return
            }

            // 2. Find the bottle we just created (or are reusing) so we
            //    can pass it to the launcher installer.
            await self.refreshBottles()
            guard let bottle = await MainActor.run(body: {
                self.bottles.first(where: { $0.name == bottleName })
            }) else {
                DebugLog.shared.error("bottle.auto", "Couldn't locate \"\(bottleName)\" after creation")
                return
            }

            // 3. Install the launcher the user chose. Each path runs the
            //    relevant installer (synchronous from the user's POV —
            //    they'll watch progress in the per-bottle log pane).
            //    `.maxima` doesn't need its own launcher install here;
            //    the wizard flow expects the user to click "Install
            //    Maxima" via the Settings / Maxima section after the
            //    bottle exists.
            do {
                switch frontend {
                case .steam:
                    if !(await SteamInstaller.shared.isSteamInstalled(in: bottle)) {
                        try await SteamInstaller.shared.install(into: bottle)
                    } else {
                        DebugLog.shared.info("bottle.auto", "Steam already installed in bottle, skipping")
                    }
                case .ea:
                    if !(await EAInstaller.shared.isEAInstalled(in: bottle)) {
                        try await EAInstaller.shared.install(into: bottle, silent: false)
                    } else {
                        DebugLog.shared.info("bottle.auto", "EA Desktop already installed in bottle, skipping")
                    }
                case .maxima:
                    // Maxima route: install MaximaSetup.exe into the
                    // bottle now (analogous to how the Steam and EA
                    // branches above install their launchers) so the
                    // user has `maxima-cli.exe` + `maxima.exe` ready
                    // to use for the interactive game-install step.
                    // The user still does the OAuth login + game
                    // download themselves inside Maxima — there's no
                    // way to script EA's qrc:// flow from here — but
                    // at least the binaries are in place.
                    if await !MaximaService.shared.isInstalled(in: bottle) {
                        DebugLog.shared.info("bottle.auto", "Installing Maxima into bottle…")
                        try await MaximaService.shared.downloadAndInstall(into: bottle) { p in
                            Task { @MainActor in
                                self.maximaProgress = p
                            }
                        }
                    } else {
                        DebugLog.shared.info("bottle.auto", "Maxima already installed in bottle, skipping")
                    }
                case .epic:
                    DebugLog.shared.warn("bottle.auto", "Epic Games path not implemented yet")
                }
                await self.refreshBottles()
            } catch {
                DebugLog.shared.error("bottle.auto", "Launcher install failed: \(error.localizedDescription)")
            }
        }
    }

    public func cancelAutoBottleInstall() {
        BottleInstaller.shared.stopWatching()
        autoInstallStage = nil
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
        autoInstallStage = bottle.hasTitanfall2
            ? .done(bottleID: bottle.id)
            : (bottle.hasLauncher
                ? .waitingForTitanfall(bottleID: bottle.id)
                : .waitingForBottle)
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
        // Don't fire twice — the wizard's progress page can re-render
        // on `autoInstallStage` updates and we want this to be a
        // single-shot when we transition into `.waitingForTitanfall`.
        if case .idle = maximaSetupPhase {
            // fall through to the spawn
        } else {
            return
        }

        maximaError = nil
        Task { [weak self] in
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
            } catch {
                DebugLog.shared.error("maxima.install", error.localizedDescription)
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
            try? await Task.sleep(for: pollInterval)
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
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return false
        }
        return p.terminationStatus == 0
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
