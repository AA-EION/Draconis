# Changelog

All notable changes to Draconis are documented here.

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
