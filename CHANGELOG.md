# Changelog

All notable changes to Draconis are documented here.

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
