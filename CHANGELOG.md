# Changelog

All notable changes to Draconis are documented here.

---

## [0.8.2] — 2026-05-16

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
