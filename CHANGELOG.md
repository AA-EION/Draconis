# Changelog

All notable changes to Draconis are documented here.

---

## [Unreleased]

### Linux and Windows: new app, built to look like the macOS one
- New interface: see-through Liquid Glass (the desktop and other windows show
  through), with the
  macOS layout (sidebar with Launcher / Game / Backend, traffic-light window
  buttons, Settings in its own window). Colours, sizes and blur were measured
  against the macOS app.
- Mods: Thunderstore icons, categories, downloads and ratings, sort and
  category menus, hide deprecated/NSFW, and drop a .zip on the window to install it.
- Console: level filter, autoscroll, copy. Turn it on in Settings → General.
- Under the hood: the interface is now Rust (egui, wgpu, liquid-rust) and the
  logic a separate Swift process. GTK 4 and the Windows App SDK are no longer
  needed; a Vulkan or OpenGL driver is.

---

## [0.14.3] — 2026-11-27

### Changed
- **One-click VR launch.** "Launch in VR" starts SteamVR when no VR runtime is running and waits for it. The VR card then shows each step: Steam starting the game, the EA app starting and signing in, the VR launcher starting. Once installed, the card lists the steps and notes that Steam's own Play button starts the normal game.

### Fixed
- **VR install no longer fails at the end without cabextract.** It checks for cabextract (or bsdtar) first and says how to install it. The deb and rpm now recommend cabextract.
- **Monado and WiVRn on Linux.** Steam's container couldn't reach their sockets. A VR launch now shares them with it.
- **Launch in VR said "Running" too early,** while Steam was still starting the EA app.
- A Proton prefix that was never set up now gets a clear message instead of "The file doesn't exist".

---

## [0.14.2] — 2026-11-27

### Fixed
- **Linux: the app closed during downloads** (the VR mod, Northstar, mods). Each download had its own network session, closed from inside its own completion callback. On Linux that can free libcurl's handle while it's still in use (`_MultiHandle deallocated with non-zero retain count`). All downloads now share one session that stays open.
- **Linux: crash reports were never written on Ubuntu.** Ubuntu only lets a process's ancestors read its memory, and Swift's crash reporter runs as Draconis's child, so it gave up. Draconis now allows it.

### Added
- **Linux:** when started from the desktop, Draconis keeps its console and error output in `Logs/draconis.log` (the previous run in `draconis.previous.log`).

---

## [0.14.1] — 2026-11-27

### Fixed
- **Linux: random crashes, most often while installing the VR mod or a mod.** Draconis checks whether SteamVR, Steam or the game is running by reading each process's command line in `/proc`. Foundation returned corrupt data for long command lines (Steam's browser processes have them), and decoding it crashed the app. Those files are now read directly.

---

## [0.14.0] — 2026-11-27

### Added
- **Titanfall 2 VR on Linux and Windows.** A new VR card on the Play screen installs and launches CircuitLord's Titanfall 2 VR mod (OpenXR, campaign). It's downloaded from the author's own release with its checksums, with the Northstar version his installer uses, and goes into a separate `TF2VR` profile: the normal game and your Northstar stay as they are. Draconis builds the mod's game assets (about 3 GB) and shows which VR runtime is running.
  - **Meta Quest 3:** open Steam Link on the headset and connect to your PC; it starts SteamVR. "Start SteamVR" is on the card.
  - **Linux:** works with the Steam copy of the game, through Steam's own Proton, with SteamVR / Steam Link, WiVRn or Monado. Draconis adds a small launch wrapper to Titanfall 2's Steam launch options (normal launches are unaffected), fixes the mod's audio crash under Wine and puts the VC++ runtime it needs into the game's prefix. Both fixes come from [TF2SteamFrame](https://github.com/MWGIH/TF2SteamFrame).
  - **Windows:** any copy; SteamVR, Quest Link, Virtual Desktop or any OpenXR runtime.
  - **macOS:** not yet. SteamVR no longer exists for macOS; [docs/VR.md](docs/VR.md) has what was investigated and the plan.

### Fixed
- **Linux: the dock showed Draconis as "example" with no icon.** The window identified itself as SwiftCrossUI's placeholder app (`com.example.SwiftCrossUIApp`), so desktops couldn't match it to Draconis's launcher entry. It now uses `io.github.aa_eion.Draconis` and sets its own icon, also for the AppImage and tarball.
- **Installing mods could crash the app** when an Install button was clicked again before the first install had started. Only one mod installs at a time now, and the other Install buttons are disabled meanwhile (the same for the GE-Proton, umu and EA-app prefix buttons, which ignored their disabled state).

### Added
- **Crash reports on Linux.** The packages ship Swift's crash backtracer; if Draconis crashes, a report is written to `~/.local/share/draconis/Logs/crashes/` and Settings → About links to it.

## [0.13.3] — 2026-11-27

### Fixed
- **Linux: "Launch Northstar" started vanilla Titanfall 2** (the same bug as Viper). Northstar's `wsock32.dll` only loads when Proton is told to prefer it, and Steam passes that to the game only through its launch options. Draconis now adds `WINEDLLOVERRIDES="wsock32=n,b" %command%` to Titanfall 2's launch options (keeping any you had, with a backup of Steam's config). Steam rewrites its config when it quits, so if it's running Draconis closes it once first. Vanilla launches are unaffected: without `-northstar` the game starts vanilla.
- **Launching gave no feedback** and Launch could be pressed again. The button now reads "Launching…" and a card says what's happening (closing Steam, Steam starting the game) until Titanfall 2 is running; then it reads "Running" until the game closes. If the game doesn't start within 3 minutes, Draconis says so.

## [0.13.2] — 2026-11-27

### Fixed
- **Linux/Windows: clicks inside cards and buttons did nothing.** The glass rim of every card and button was drawn on top of its contents and caught the clicks; it is now drawn underneath.
- **Linux: Titanfall 2 in Steam wasn't always found.** Draconis needed Steam's install record for the game; like Viper, it now also finds `steamapps/common/Titanfall2` in any Steam library, and it checks Flatpak Steam's `~/.var/app/com.valvesoftware.Steam/.steam/steam`. Where it looked and what it found are written to the Console page.
- **The Mods search froze the app** while it laid out every matching mod on each keystroke. Searches now apply after a short pause in typing, and the list shows up to 60 mods with a count of the rest.

## [0.13.1] — 2026-11-27

### Fixed
- **The Linux .deb and .rpm wouldn't install** on distributions that renamed libxml2 (Debian 13, Ubuntu 25.10: "draconis depends on libxml2 but it is not installable"). Draconis never used it; the packages now only require GTK 4 and libcurl.

---

## [0.13.0] — 2026-11-27

Works with [Maxima-Draconis v0.17.0](https://github.com/AA-EION/Maxima-Draconis/releases/tag/v0.17.0).

### Added
- **Draconis for Linux and Windows.** The same screens as the macOS app (Play, Mods, Servers, Console, Settings) and its look: glass cards, status pills, capsule buttons, Orbitron / Barlow Condensed / Inter on Linux, Mica on Windows. Built with [SwiftCrossUI](https://github.com/moreSwift/swift-cross-ui) (GTK 4 / WinUI 3) on a core shared with the Mac app.
  - **Linux:** finds Titanfall 2 in Steam (native, Flatpak, Snap and every library folder), Heroic, Draconis's own prefixes and folders you add. Steam copies start through Steam (`-northstar` for Northstar, with a warning when Steam's Proton isn't GE-Proton and `wsock32` isn't overridden); other copies run `NorthstarLauncher.exe -noOriginStartup` through umu-launcher + Proton or plain Wine, after starting the EA app in the prefix. Runners: Steam's Protons, GE-Proton (one-click, SHA-512-checked), Heroic / Lutris / Bottles builds, system Wine. Draconis can create a prefix with the EA app, only under its own data folder.
  - **Windows:** finds Steam, EA app and Epic copies and runs the game directly.
  - Packages: AppImage, deb, rpm, Flatpak and tar.gz for Linux; a zip for Windows. Every release builds all three platforms.
- When GitHub's API is rate-limited, Northstar updates come from Thunderstore instead.
- **Draconis Wine — play without CrossOver.** A free, open-source Wine backend: `wine-crossover` 11.0 (built from CodeWeavers' published sources) plus DXMT 0.80 (Direct3D 11 → Metal), downloaded once (~450 MB, checksum-pinned). Each game gets its own prefix under `~/Library/Application Support/Draconis/Prefixes/`; every command gets an explicit `WINEPREFIX`, never the global `~/.wine`. Pick it on the first wizard page.
- **Epic Games copies.** Sign in to Epic in your browser (through the open-source legendary CLI). Draconis then hands Titanfall 2 to the bottle's EA app, which links the account and downloads the game. No Epic launcher needed.
- **Import from Heroic.** If the Heroic Games Launcher already set up the Epic copy, the wizard reuses that bottle or prefix.
- **Bottle dependencies like CrossOver's own Titanfall 2 install:** the latest Visual C++ runtimes and d3dcompiler_47. CrossOver bottles also get MSync and Titanfall 2's CrossOver profile id.

### Changed
- Northstar's version is read from `Northstar.Client/mod.json` (current releases don't ship `ns_version.txt`). Updates remove the old core mods first and keep `ns_startup_args*.txt`.
- Enabling and disabling mods writes the current `enabledmods.json` format (`"Version": 1`, per-version entries).
- Server names no longer show Source colour codes.
- **Maxima is experimental.** The EA app, Steam and Epic come first in the wizard. Maxima is listed last and only works in CrossOver bottles.
- **Steam path:** after Steam installs, Steam opens on Titanfall 2's install page. Once the game is installed, Draconis runs it once through Steam so Steam installs the EA app. A launch without the EA app does the same.
- Launches without Maxima start the EA app if needed and wait until it's running before starting the game.
- Northstar mode clears a `run_northstar.txt` that would silently force vanilla.

### Fixed
- Third-party licences: Orbitron's OFL now ships with the app; DXMT is credited as LGPL-2.1-or-later (it was listed as MIT). See `THIRD-PARTY-NOTICES.md`.
- Downloads that return an HTTP error no longer leave a broken file behind.
- **Steam's window stayed empty with Draconis Wine** (Dock icon, no window). Steam now runs its built-in browser without the GPU through a small wrapper, the fix from [steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine) (MIT). The EA app's browser also runs without the GPU there.
- Visual C++ installs now show their progress windows instead of running invisibly. One that stalls (Wine's installer can hang) is stopped after 10 minutes and setup carries on; Wine has its own copy of those libraries.
- **Creating a Draconis Wine prefix failed (exit 53)** when a disk image was mounted, such as the Draconis DMG: Wine gave drive C: to that volume instead of the prefix. Draconis now links C: and Z: before Wine's first start, and recreates a prefix left broken by this. Steam's and the EA app's Wine settings also apply only to those programs now.
- **Steam install stalled during bottle creation.** `cxbottle --create` output went to pipes nobody read. Output now goes to a log file.

---

## [0.12.1] — 2026-10-09

Bundles MaximaHelper from [Maxima-Draconis v0.15.2](https://github.com/AA-EION/Maxima-Draconis/releases/tag/v0.15.2).

### Fixed
- **EA login never finished after logging in through the browser** — the bundled MaximaHelper registered for `qrc://` links too late: when macOS launched it for the login redirect, the link arrived before the helper was listening and was dropped, so Maxima never received the login. The helper now registers before launch completes and exits on its own if no link arrives.

---

## [0.12.0] — 2026-10-09

Built for [Maxima-Draconis v0.15.0](https://github.com/AA-EION/Maxima-Draconis/releases/tag/v0.15.0), where `maxima-cli` starts a long-lived `maxima-server` inside the bottle; still works with v0.14.0.

### Added
- **Withdraw Consent** button in Settings → About. Shows a confirmation alert, clears the stored privacy consent via `ConsentManager.revoke()`, then quits; the privacy notice is shown again on next launch.

### Fixed
- **Crash from double-resumed continuation** when a Wine installer/uninstaller exited quickly — the `terminationHandler` is now installed before `Process.run()`, and a failing `run()` resumes exactly once. Installer/uninstaller waits go through the new `WineBackendManager.launchAndWait`.
- **Role switch to `.none` could leave Maxima installed** — `applyRole(.none)` no longer swallows uninstall errors, so the role is only persisted when the uninstall succeeded.
- **Maxima reinstalled on every launch** after dismissing the `qrc://` handler prompt — the installed version tag is now saved before `registerHelper()`.
- **Blocked Swift Concurrency threads** — `ProcessRunner.capture`, `MaximaService` CLI/installer calls, bottle creation, the `pgrep` game poll and the installers no longer call `waitUntilExit()`; they suspend until the process exits.
- **`CleanSpawn`** no longer `dlclose`s the handle that backs the cached `responsibility_spawnattrs_setdisclaim` pointer.
- **Mods tab performance** — `modUpdatesAvailable` is now a published value recomputed only when the Thunderstore package list or installed mods change, instead of rebuilding two dictionaries on every SwiftUI read.
- **`MaximaService.launchGame` / `NorthstarLauncher.launch`** return the spawned `pid_t` instead of an empty placeholder `Process`.
- **Wrong error when CrossOver is missing** — launching without `cxstart` now reports "CrossOver (or its cxstart helper) wasn't found" instead of "Titanfall 2 wasn't found".
- **Updating a Thunderstore mod could delete a different mod** — older-version cleanup now only removes folders named exactly `Author-Mod-<version>`, so `Author-Mod-Extras-1.0.0` is left alone.
- **Onboarding re-downloaded Titanfall 2 for Steam bottles that had Maxima** (e.g. after the CEG fix) — Maxima's `FInstall.txt` marker is now only required for copies Maxima downloaded itself, via a single `WineBottle.isTitanfallInstallComplete` check shared by the wizard and stage detection.
- **Server-based Maxima compatibility** — every `maxima-cli` call (library check, CEG fix, launch) now goes through `CleanSpawn`, so the in-bottle `maxima-server` it starts is never responsibility-attributed to Draconis (which would bring back the launch freeze). Output is captured via files instead of pipes, removing a deadlock on large EA libraries. "Login pending" errors from the CLI surface as "not logged in".
- **Mod browser** follows Thunderstore's move of the Northstar API to `thunderstore.io/c/northstar/api/v1/package/`.
- **"Not logged in" detection** recognises Maxima-Draconis v0.15's login messages ("login failed or was cancelled", "the EA login didn't finish"), so an unfinished EA login shows the login prompt instead of a generic CLI error.
- Draconis holds a user-initiated activity while Titanfall 2 runs, as a fallback against App Nap if the responsibility-disclaim API is ever unavailable.

---

## [0.11.0] — 2026-05-22

### Added
- **Privacy & GDPR consent screen** — shown on first launch before any other content. Users must read both the Privacy Notice and GPL-3.0 license tabs before accepting. Acceptance is stored in `~/Library/Preferences/org.draconis.launcher.plist` and remembered permanently. Decline & Quit terminates the app.
- **Sentry crash reporting** (`sentry-cocoa` v9.14.0, SPM). Captures unhandled exceptions and handled errors at every `catch` site in `AppEnvironment`. Never starts before consent. Data stored on EU servers (`ingest.de.sentry.io`).
- **Automatic Sentry scope sync** — bottle state, Maxima role, and version tags are pushed to the Sentry scope on every `refreshMaximaState()` call, so automatic crash reports always carry full context without user action.
- **Bug report sheet** (`Help → Report a Bug…` ⌘⌥B, or Settings → About). Auto-collects bottle state, versions, and last 60 console lines (home path sanitised to `~`). Description required; name and contact optional. Submits a Sentry `Event` + linked `SentryFeedback`.
- **dSYM generation** — `DEBUG_INFORMATION_FORMAT: dwarf-with-dsym` added to `project.yml` so Sentry's symbolication pipeline works on all builds.

---

## [0.10.0] — 2026-05-22

This release rewrites the install flow for new users and folds Maxima setup into a coherent, multi-launcher experience. Requires [Maxima-Draconis v0.13.0](https://github.com/AA-EION/Maxima-Draconis/releases/tag/v0.13.0) (auto-downloaded by Draconis at install time when the Maxima route is picked).

### Added
- **Onboarding wizard rewrite** ([#16](https://github.com/AA-EION/Draconis/pull/16)) — the wizard now asks the user to pick an install source (**Maxima**, **EA app**, **Steam**, or **Epic**) up front, creates a CrossOver bottle via `cxbottle` with the right Wine profile, walks them through installing the chosen launcher + Titanfall 2 inside it, and finishes by configuring Maxima at the right scope. The pre-existing CrossTie (`Titanfall2.tie`) flow was removed — it baked the EA-Desktop assumption into the bottle template and didn't compose with Maxima or Steam paths.
- **`MaximaRole` per bottle** ([#16](https://github.com/AA-EION/Draconis/pull/16)) — every bottle records how Maxima should participate in its launch chain: `.none` (no Maxima, launcher handles auth), `.authOnly` (Maxima registers as `link2ea://` handler, binaries untouched), or `.fullReplace` (Maxima + CEG-fix replaces Steam-signed `Titanfall2.exe` / `Titanfall2_trial.exe` with the EA originals). Persisted in `UserDefaults` keyed by bottle ID, read by `NorthstarLauncher` at launch time. Steam bottles see all three roles in the wizard; EA bottles see `.none` / `.authOnly`; Maxima-installed bottles default to `.fullReplace` and skip the picker.
- **Auto-driven Maxima install via `maxima.exe --install`** ([#17](https://github.com/AA-EION/Draconis/pull/17)) — the wizard's Maxima route spawns `maxima.exe --install <slug> --install-path <path>` (added in Maxima-Draconis v0.12.0), watches the install dir for `FInstall.txt` (the marker Maxima writes when the download settles), then SIGTERMs `maxima.exe` and advances the wizard. The user sees Maxima's own UI for login + download progress, Draconis takes over once the marker appears. Polling loop is `Task`-isolated and cancellation-aware (`try`, not `try?`) so closing the wizard mid-install actually stops the loop instead of running for 2 hours in the background.
- **`MaximaInstallStatusCard` on the progress page** — phase-driven status (`.idle` / `.installingGame` / `.finishing` / `.done` / `.failed`) with auto-fire of `startGameInstallViaUI` on entry. Cancellable via the cached `Task<Void, Never>` handle so the wizard exits clean.
- **Settings → Maxima tab** ([#20](https://github.com/AA-EION/Draconis/pull/20)) — install / update / uninstall, MaximaHelper registration, per-bottle role display, and an "Open Onboarding wizard…" button moved here from the old PlayView toggle card. Setup hint text adapts to whichever piece is missing.

### Fixed
- **Launcher pill said "Missing" for Maxima bottles** ([#18](https://github.com/AA-EION/Draconis/pull/18)) — `launcherStatusValue` and `hasLauncher` predicates didn't recognise `hasMaxima` as a launcher, so a bottle running only Maxima failed the Launch button's `.disabled` check. Pill now treats Maxima as a first-class launcher (ordered first), and added a `hasAnyFrontend` helper used by both the pill and the Launch button.
- **Post-update Maxima showed as not-installed** ([#19](https://github.com/AA-EION/Draconis/pull/19)) — `setupMaxima` / `updateMaxima` only called `refreshMaximaState`, leaving per-bottle `WineBottle.hasMaxima` stale. Both call sites now use `refreshBottles` (which calls `refreshMaximaState` internally).
- **Wizard offered Maxima alongside EA after a Maxima install** ([#19](https://github.com/AA-EION/Draconis/pull/19)) — `startGameInstallViaUI` never wrote a `MaximaRole` on completion. Re-entering the wizard saw the install but no explicit role and re-prompted the user. Persists `.fullReplace` when `FInstall.txt` appears (Maxima-installed games carry the EA originals by construction).
- **`noTitanfallCard` referenced the dropped CrossOver-profile flow** ([#19](https://github.com/AA-EION/Draconis/pull/19)) — rewrote the copy to direct users to the Onboarding wizard; `instructionsCard` helper gained an optional `primaryActionIcon` parameter.
- **Settings → Maxima couldn't uninstall in some states** ([#20](https://github.com/AA-EION/Draconis/pull/20)) — the first cut gated Uninstall behind `maximaInstalled && maximaHelperRegistered`. If binaries were present but the helper unbound (a common partial state), the user had no UI path out. Refactored to one-button-per-row, each shown when its operation is meaningful: Set up / Update / Register Helper / Uninstall / Unregister Helper.

### Changed
- **`CleanSpawn` for all game launches** ([#16](https://github.com/AA-EION/Draconis/pull/16)) — `posix_spawn` with `CLOEXEC_DEFAULT + SETSID + responsibility_spawnattrs_setdisclaim`. Replaces `Foundation.Process` for spawning Wine chains, which used to deadlock in `.app` contexts when the launched process had to outlive Draconis. The Maxima install spawn + game launches both go through it.
- **Reordered Frontend enum** ([#16](https://github.com/AA-EION/Draconis/pull/16)) — `Maxima` first in the picker so it surfaces as the default-recommended path on macOS. Other launchers still available, but the wizard copy now leads with the Maxima story.
- **Settings window height** 460 → 540 to fit the new Maxima tab without forcing a scroll on first paint.

### Removed
- **`maximaEnabled` user pref + UserDefaults mirror** ([#20](https://github.com/AA-EION/Draconis/pull/20)) — redundant with `MaximaRole`. The truth is "is `maxima-cli.exe` in this bottle + did the user pick a role", not a separate toggle.
- **`maximaToggleCard` / `maximaCard` / `maximaInfoPopover` / `showMaximaInfo` / `maximaVersionLabel` / `maximaSetupNote` from PlayView** — moved to Settings tab.
- **`Titanfall2.tie` CrossTie + `WineBottleCreator` template** ([#16](https://github.com/AA-EION/Draconis/pull/16)) — replaced by `cxbottle` direct creation. All CrossTie references swept from the UI.

---

## [0.9.2] — 2026-05-16

### Fixed
- **Northstar was reinstalled on every launch** — `bootstrap()` compared the version Northstar writes into `ns_version.txt` (`1.30.0`) against the GitHub release tag (`v1.30.0`) literally; the strings never matched so the auto-updater downloaded and re-extracted the same release every time Draconis started. Both sides are now normalised (leading `v`/`V` stripped) before comparison, so an up-to-date install is recognised as up-to-date.
- **Draconis and Northstar updaters ran simultaneously** — when a self-update was offered on launch, `bootstrap()` also fired the Northstar auto-update in parallel, producing two progress bars, two competing downloads, and an unclear "is the app about to relaunch or am I supposed to wait?" state. Northstar's auto-update is now deferred whenever a Draconis update prompt is on screen; it'll run on the next launch (typically right after the self-update relaunch).
- **Self-updater hung on "Quitting to apply update…"** — `NSApplication.shared.terminate(nil)` was called while the update sheet was still presented, so AppKit's terminate cycle waited indefinitely on the modal. All open windows (and any attached sheets) are now closed before `terminate` is invoked, and an `exit(0)` fallback fires 1.5 s later in case AppKit still stalls. The swap helper (which has been waiting on the parent PID) can then proceed cleanly.
- **Stale Draconis DMG volumes** — if the user had left a previous DMG mounted (from the original install or a prior interrupted update), `hdiutil attach` would mount the new copy as `/Volumes/Draconis 1`, `/Volumes/Draconis 2`, …, polluting Finder's sidebar. The self-updater now enumerates `hdiutil info -plist` and force-detaches every volume whose mount-point starts with `/Volumes/Draconis` before mounting the new DMG.
- **Release notes wiped on tag push** — the `release.yml` workflow used to overwrite the GitHub release body with a hardcoded install snippet, throwing away any changelog the user had added. It now extracts the matching `## [X.Y.Z]` section from `CHANGELOG.md` and appends install instructions below it, so the published release page actually documents what changed.

---

## [0.9.1] — 2026-05-16

### Fixed
- **Thunderstore mod install — folder layout** — installing a Thunderstore mod used to extract the entire zip into `R2Northstar/mods/`, producing a nested `mods/mods/<ModFolder>/mod.json` Northstar never loaded, leaving `manifest.json` / `icon.png` / `README.md` as litter in the mods root, and dropping `plugins/` entirely. Mods are now extracted to `R2Northstar/packages/<Author-ModName-version>/` — the modern layout documented at [docs.northstar.tf](https://docs.northstar.tf/Wiki/using-northstar/packages/) and used by FlightCore / thermite / r2modman. The full Thunderstore structure (`mods/`, `plugins/`, `manifest.json`) is preserved inside each package folder so Northstar's recursive mod loader picks everything up.
- **Mod enable/disable** — the toggle now writes `R2Northstar/enabledmods.json` (Northstar's standard file) instead of renaming folders with a `.` prefix. Stale dot-prefixed folders from earlier builds are healed on the next toggle.
- **Stale package versions on update** — older `<Author-ModName>-x.y.z/` folders are removed before a new version is extracted, so Northstar can't accidentally load two copies of the same mod at once.
- **Installed-mod listing** — Draconis reads both the legacy `R2Northstar/mods/<ModName>/` and the modern `R2Northstar/packages/<full_name>/mods/<ModName>/` layouts so everything Northstar actually loads is visible in the Installed tab.

### Added
- **Mod dependencies resolved automatically** — when installing a Thunderstore mod, declared `manifest.dependencies` are fetched from the live Thunderstore listing and installed too (skipping Northstar itself and anything already in the bottle). The package list is fetched once and reused for the whole recursion, so a deep dependency tree doesn't trigger multiple multi-MB downloads.
- **Drag-and-drop local mod install** — drop a `.zip` from Finder anywhere on the Mods view to install it. `manifest.json` is peeked out of the zip with `unzip -p` so the package folder is named `<name>-<version_number>` (falling back to the zip basename when no manifest is present).
- **Browse sort + filters** — sort by top-rated / most-downloaded / recently updated / name, filter by category, and persisted toggles for *Hide deprecated* and *Hide NSFW*.
- **Installed-mod QoL** — `UPDATE` badge with one-click update when a newer Thunderstore version is available, `PACKAGE` badge for mods that came from a Thunderstore package folder, *Reveal in Finder* + *Uninstall* in a context menu and the row's `⋯` menu, and a *Page* link that opens the mod's Thunderstore listing from each browse row.
- **Per-row install spinner** — installing one mod no longer blocks the Install buttons for every other row in the list.

### Changed
- `ThunderstoreClient.uninstall(_:)` removes the whole `R2Northstar/packages/<full_name>/` directory when the mod came from a package (since `mods/`, `plugins/`, and the manifest are co-installed), and only removes the inner folder for legacy `R2Northstar/mods/<ModName>/` installs.

---

## [0.9.0] — 2026-05-16

### Added
- **In-app self-update** — Draconis now checks GitHub Releases on launch and offers to update itself when a newer version is published. The prompt has three options: **Update Now** (downloads the DMG, swaps the bundle, and relaunches), **Remind Me Later** (re-prompts on next launch), and **Skip This Version** (only re-prompts when an even newer release appears). No admin permissions required, no Gatekeeper friction between versions — the new bundle is fetched via `URLSession` so it never receives the `com.apple.quarantine` attribute, and the swap happens via a detached shell helper that survives Draconis quitting (same pattern Sparkle uses). Approved updates work for installs in `/Applications/` and `~/Applications/`; apps on external volumes go to the correct per-volume Trash.

---

## [0.8.1] — 2026-05-16

### Added
- **`DraconisTheme` style guide** — new `Components/DraconisTheme.swift` centralises all opacity constants into two public namespaces (`DraconisTheme.Text` and `DraconisTheme.Card`). All views and `TitanfallTypography` now reference these named constants instead of inline magic numbers, making future theme adjustments a single-file change.
- **Orbitron font bundled** — `Orbitron-Black.ttf`, `Orbitron-Bold.ttf`, and `Orbitron-VariableFont_wght.ttf` are now shipped inside the app bundle (`Resources/Fonts/`). `ATSApplicationFontsPath` in `Info.plist` registers them automatically at launch; `TF.hero()` and `TF.display()` resolve to Orbitron without code changes.

### Changed
- **Accent colour corrected** — `AccentColor.colorset` colour-space changed from `display-p3` to `srgb` so `#c4e7fb` renders exactly as specified (neutral near-white with a very light blue-gray tint).
- **Liquid Glass translucency** — white backdrop overlay reduced from `0.78 → 0.55` opacity; more of the frosted window-behind blur is now visible.
- **Marble palette** — removed all orange, red, and yellow tints from glass card backgrounds; replaced with neutral `accentColor` or low-opacity black tints. Maxima action buttons switch from `.orange` to `.accentColor`. Error icon/text colours remain red (semantic), but card surfaces are neutral.
- **Contrast** — `StencilLabel` default opacity raised `0.78 → 0.88`. All `.primary.opacity()` values below `0.65` raised ~10–15 pp across the codebase.

---

## [0.8.0] — 2026-05-16

### Fixed
- **Maxima info button** — the `ⓘ` button next to the Maxima toggle was a silent no-op; it now opens a popover with a plain-language description of what Maxima does and a link to the project page.
- **Maxima uninstall refresh** — after uninstalling Maxima, Draconis now reflects the change immediately in the UI without requiring a restart. The uninstall path adds a 1.5 s FS-settle delay, force-removes any leftover install directories the NSIS uninstaller may have missed, clears the persisted version tag, and triggers a full bottle rescan before updating the status pills.

### Added
- **Uninstall Northstar** — a new **Uninstall NS** button appears in the Play tab next to Launch whenever Northstar is installed. A confirmation dialog is shown before any files are removed. The uninstaller removes `NorthstarLauncher.exe`, `Northstar.dll`, `R2Northstar/` (mods and plugins), `ns_version.txt`, startup arg files, and the Northstar-patched `bin/x64_retail/wsock32.dll`, leaving `Titanfall2.exe` and the base game fully intact.

### Changed
- **Light theme / Liquid Glass refresh** — the app now enforces light mode with a white backdrop (frosted blur + 78 % white overlay) so text stays legible while preserving the Liquid Glass card aesthetic. Accent colour updated to `#c4e7fb` (soft steel-blue). All hardcoded `.white` foreground tokens replaced with `.primary` / `.primary.opacity()`. Glass card tints changed from invisible `.white.opacity(0.04)` to `.accentColor.opacity(0.18)` for visible depth.
- **Manual setup wizard** — removed all mentions of "CrossTie" from the manual-install page (CrossTie is an automatic-mode concept). The three progress steps now describe what the user does themselves: create a win10_64 bottle, install a launcher and Titanfall 2, and wait for Draconis to detect the game.

---

## [0.7.0] — 2026-05-15

### Added
- **Northstar auto-update on launch** — when Northstar is already installed Draconis compares the version in `ns_version.txt` against the latest GitHub release and updates automatically. The Install button only appears when Northstar is absent.
- **EA App and Epic Games detection** — `WineBottle` now reports `hasEAApp`, `hasEpicGames`, `hasLauncher`, and `northstarVersion`. The "Launcher" status pill on the Play tab shows whichever launcher (Steam / EA App / Epic) is installed in the bottle.
- **Maxima version tracking** — installed version stored in UserDefaults using the GitHub release tag. A new **Update Maxima** button appears when a newer release is available; Maxima does not auto-update.
- **Maxima toggle** — the EA Launcher (Maxima) section on the Play tab is now hidden behind a toggle with an info tooltip explaining it is beta software. Enable it only if you need EA account authentication.
- **Manual onboarding monitoring** — entering manual setup mode now starts live polling (same progress steps as automatic mode), updating as CrossOver creates the bottle and the launcher appears.
- **CrossTie safety note** — onboarding and the Play tab now explain that the Titanfall 2 CrossTie may appear untrusted inside CrossOver even though it comes from CrossOver's own database and is safe to run.
- **`updateMaxima()` action** — separate from `setupMaxima()`; always downloads and reinstalls, used by the Update button.

### Changed
- Northstar launch args: added `-noOriginStartup -multiple` before `-northstar` (required by Maxima to prevent Northstar from trying to start Origin, which doesn't exist in Wine).
- Vanilla mode now launches via `NorthstarLauncher.exe -vanilla` when Northstar is installed, avoiding auth issues when Maxima/EA aren't running. Falls back to `Titanfall2.exe -novid` when Northstar is absent.
- `BottleInstaller.detectStage()` uses `hasLauncher` (Steam ∨ EA App ∨ Epic) instead of `hasSteam` only, so manual EA/Epic installs advance the progress steps correctly.
- Maxima installer (`MaximaSetup.exe`) is now saved to `~/Library/Application Support/Draconis/Downloads/` alongside Northstar zips, overwriting any previous copy.
- `DownloadCoordinator` now reports indeterminate progress (fraction `-1`) when the server omits `Content-Length`, replacing the previous bogus `0%` display.
- `CrossOverDetector` reads `ns_version.txt` and detects EA Desktop / Epic Games Launcher during bottle scans.

### Fixed
- `-novid` flag restored in both Northstar (`steam.exe -applaunch`) and vanilla (`NorthstarLauncher.exe -vanilla`) launch paths (accidentally dropped, caught by code review).

---

## [0.6.0] — 2026-05-14

### Added
- **Automated bottle creation** (`feat/auto-bottle-install`): Draconis hands CrossOver the bundled `Titanfall2.tie` and polls the bottle directory every 5 s through three stages (creating bottle → waiting for Steam → waiting for Titanfall 2).
- Frontend picker in onboarding (Steam available; EA app and Epic greyed out pending implementation).
- `BottleInstaller` service with `openTitanfall2Crosstie()` and `startWatching(interval:onStage:)`.
- `cancelAutoBottleInstall()` in `AppEnvironment`.

### Changed
- CrossOver.app resolved via LaunchServices (`NSWorkspace.urlForApplication(withBundleIdentifier:)`) with a fallback to `/Applications/CrossOver.app`.
- Onboarding shows live progress steps with spinner / checkmark / dotted-circle states.

---

## [0.5.x and earlier]

Initial private development. CrossOver-only backend, Northstar updater, Thunderstore mod browser, server browser, Maxima integration skeleton, Liquid Glass UI.
