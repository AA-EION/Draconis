# Draconis — Claude Code guidance

## Project overview

Draconis is a native macOS launcher for **Titanfall 2 + Northstar** built with SwiftUI and the Liquid Glass design system (macOS Tahoe 26+). It drives **CrossOver** as the only Wine backend. The codebase is Swift 5.10 / Swift 6 strict concurrency.

## Key architecture

- `AppEnvironment` — `@MainActor` ObservableObject, single source of truth; all UI state and async actions live here.
- Services are `actor`-isolated singletons (`NorthstarUpdater.shared`, `MaximaService.shared`, etc.). Never call actor methods from synchronous SwiftUI view bodies — use `@Published` properties on `AppEnvironment` instead.
- `PathResolver` — all filesystem paths. Downloads go to `PathResolver.downloadsCache` (`~/Library/Application Support/Draconis/Downloads/`).
- `DownloadCoordinator` — wraps `URLSessionDownloadDelegate` for streamed progress. Reports `fraction = -1` when `Content-Length` is absent.
- Launches go through `WineBackendManager.shared.launch(...)` → `cxstart --bottle <name> [--wait] <exe> [args]`.
- Bottle creation goes through `WineBottleCreator.shared.createBottle(...)` → `cxbottle --create --template win10_64 --bottle <name>`. The previous CrossTie-based flow (bundled `Titanfall2.tie`) was dropped because it forcibly installed Steam, which leads to the Steam-CEG corruption documented below.

## Launch modes (NorthstarLauncher.swift)

Maxima is preferred whenever it's installed in the bottle (`bottle.hasMaxima == true`). When Maxima is absent the launcher falls back to the direct-exe paths it used before.

| Mode | Command | When |
|------|---------|------|
| **Maxima route** (preferred) | `maxima-cli launch Origin.OFR.50.0001456 [--game-args -northstar]` | Bottle has `maxima-cli.exe`. Handles EA auth internally; no Steam-applaunch needed. |
| Vanilla (NS installed, no Maxima) | `NorthstarLauncher.exe -vanilla -novid` | Avoids auth issues when Maxima/EA aren't running |
| Vanilla (NS absent, no Maxima) | `Titanfall2.exe -novid` | Bare-metal fallback |
| Northstar (no Maxima) | `steam.exe -applaunch 1237970 -noOriginStartup -multiple -northstar -novid` | Steam path, requires Steam + EA Desktop in bottle |

## Maxima integration (MaximaService.swift)

- Maxima is **opt-in** — gated behind `env.maximaEnabled` (UserDefaults `"maximaEnabled"`). Not installed by default.
- Installer saved to `PathResolver.downloadsCache/MaximaSetup.exe` (overwritten each install).
- Installed version tracked in UserDefaults key `"maximaInstalledVersion"` using the GitHub release tag.
- `isUpdateAvailable()` compares local tag vs remote. Shows **Update** button; does **not** auto-update.
- `setupMaxima()` skips download if `maxima-cli.exe` already in bottle (re-registers helper only).
- `installedVersion` is `nonisolated` (reads UserDefaults only) so it can be called without `await`.

### Maxima CLI surface (added in the wizard rewrite)

| Method | Wraps | Used for |
|---|---|---|
| `listGames(in:)` | `cxstart --bottle … --wait maxima-cli list-games --json` | Pre-flight detection: is TF2 in the user's EA library, where is it installed? Throws `.notLoggedIn` if OAuth hasn't been completed. |
| `applyCegFix(in:gamePath:)` | `cxstart --bottle … --wait maxima-cli install titanfall-2 --path … --replace-files "Titanfall2.exe,Titanfall2_trial.exe" --only-listed-files` | Surgical CEG fix on a Steam install. ~3 MB download. |
| `launchGame(in:northstar:)` | `cxstart --bottle … maxima-cli launch Origin.OFR.50.0001456 [--game-args -northstar]` | Hot-path launch when Maxima knows about TF2. Used by `NorthstarLauncher` when `bottle.hasMaxima`. |

All three pipe output to the per-bottle log file (`PathResolver.bottleLogFile(for:)`) so the user can debug failures.

## Northstar version detection

- `CrossOverDetector.readNorthstarVersion(in:)` reads `{tf2Root}/ns_version.txt` (written by the Northstar installer).
- `WineBottle.northstarVersion: String?` populated during bottle scan.
- `AppEnvironment.bootstrap()` auto-updates Northstar when `bottle.northstarVersion != latest.tagName`.

## Bottle / launcher detection

- `WineBottle` has `hasSteam`, `hasEAApp`, `hasEpicGames`, `hasMaxima`, `hasLauncher` (= any of Steam/EA/Epic).
- The Maxima route in `NorthstarLauncher.launch` checks `hasMaxima` first and routes through `maxima-cli launch` when present; everything else is fallback.
- `BottleInstaller.detectStage()` uses `hasLauncher` so EA/Steam manual installs advance onboarding steps.

## Onboarding sources

`BottleInstaller.Frontend`:

- `.steam` — `SteamInstaller.install(into:)` downloads `SteamSetup.exe` and runs it silently. User installs TF2 through Steam afterward. **Heads up:** Steam-installed TF2 hits CEG corruption on macOS/CrossOver; apply the Maxima fix afterward.
- `.ea` — `EAInstaller.install(into:silent:)` downloads EA's installer (`EAappInstaller.exe`). EA app handles `link2ea://` natively; simplest path on macOS.
- `.maxima` — bottle is created but no launcher installed by the wizard. User runs `MaximaService.setupMaxima` from Settings and then `maxima-cli install titanfall-2` inside the bottle. Requires the game to be in the user's EA library.
- `.epic` — documented, marked `.available = false` (Coming soon).

## CEG fix

The dialog component lives in `Draconis/Views/Components/CegFixDialog.swift`. Triggered when a Steam install is detected alongside Maxima in the same bottle, it offers two options:

1. **Apply Maxima fix** — calls `env.applyCegFix(in:gamePath:)` → `MaximaService.applyCegFix(...)` → `maxima-cli install --replace-files "Titanfall2.exe,Titanfall2_trial.exe" --only-listed-files`. ~3 MB download, replaces the CEG-signed launcher binaries with EA originals. Preserves Northstar files, save games, the rest of the install.
2. **Leave in place** — closes the dialog. The user can re-open it later from Settings if they hit "File corruption" in-game.

Full root-cause analysis and empirical validation: see Maxima-Draconis CLAUDE.md → "Engine Error: File corruption detected — Update 2026-05-19 (CEG fix confirmed end-to-end)".

## Pending work / known issues

### Performance — bottle scan I/O (raised in PR #8 code review)
`CrossOverDetector.bottles()` calls `locateTitanfall2` (potentially slow recursive search) **plus** `readNorthstarVersion` (one `Data(contentsOf:)`) **plus** the new `locateMaximaCli` for every bottle on every refresh. For users with many bottles this can block the actor for several seconds. Consider caching `northstarVersion` / `hasMaxima` per-bottle keyed by bottle ID, invalidated only when the bottle's `mtime` changes.

### Wizard UX still rough
The wizard wires up the new launchers but the screen flow itself is the same multi-step state machine as before. Pending:
- `.waitingForLauncher(bottleID)` stage between `.waitingForBottle` and `.waitingForTitanfall` so the UI can distinguish "no bottle yet" from "bottle exists, install your launcher".
- "Run game once" confirmation step before offering Maxima install for Steam/Epic paths (currently the user has to know to do this themselves).
- EA-library warning when picking the Maxima source — surface the requirement up front instead of letting `maxima-cli install` fail later.
- Triggering the CEG dialog automatically when relevant (right now it's available but not auto-shown).

### Offline Maxima mode
Maxima supports offline play after a first successful online launch (license files in `C:/ProgramData/Maxima/Licenses/`, valid ~2 weeks). Not yet exposed in the Draconis UI.

### Epic Games path
`BottleInstaller.Frontend.epic` is intentionally `.available = false`. Epic delivers TF2 with EA Desktop bundled the same way Steam does, so the path is likely identical to Steam-with-CEG-fix, but it hasn't been validated by anyone with an Epic copy.

## Code conventions

- No inline comments unless the *why* is non-obvious. No doc-comment blocks.
- All actor-isolated state is only mutated from within the actor or from `@MainActor` context.
- `nonisolated` is acceptable for properties/methods that only touch `let` constants or thread-safe types (e.g. `UserDefaults.standard`).
- `Log.*` (alias for `DebugLog.shared.*`) for all in-app console output. Use `.run` for shell commands, `.ok` for success, `.error` for failures.
- New downloads → `PathResolver.downloadsCache`. New per-bottle logs → `PathResolver.bottleLogFile(for:)`.

## Build

```bash
./bootstrap.sh --open   # generate Draconis.xcodeproj and open in Xcode
```

See `BUILD.md` for signing, notarisation, and DMG packaging.

## Release checklist

**Always do these steps in order before tagging a release:**

1. **Bump `MARKETING_VERSION`** in `project.yml` (e.g. `"0.7.0"` → `"0.8.0"`).  
   This is the single source of truth — `CFBundleShortVersionString` in the built app reads from it.
2. **Update `CHANGELOG.md`** — add a `## [X.Y.Z] — YYYY-MM-DD` section at the top.
3. Commit both files: `chore: bump version to vX.Y.Z`.
4. Merge the release PR (or commit directly to main).
5. Tag on main: `git tag vX.Y.Z <merge-sha> && git push origin vX.Y.Z`.
6. Create the GitHub release targeting that tag, pasting the CHANGELOG section as the release notes.
