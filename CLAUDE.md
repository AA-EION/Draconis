# Draconis — Claude Code guidance

## Project overview

Draconis is a native macOS launcher for **Titanfall 2 + Northstar** built with SwiftUI and the Liquid Glass design system (macOS Tahoe 26+). It drives **CrossOver** as the only Wine backend. The codebase is Swift 5.10 / Swift 6 strict concurrency.

## Key architecture

- `AppEnvironment` — `@MainActor` ObservableObject, single source of truth; all UI state and async actions live here.
- Services are `actor`-isolated singletons (`NorthstarUpdater.shared`, `MaximaService.shared`, etc.). Never call actor methods from synchronous SwiftUI view bodies — use `@Published` properties on `AppEnvironment` instead.
- `PathResolver` — all filesystem paths. Downloads go to `PathResolver.downloadsCache` (`~/Library/Application Support/Draconis/Downloads/`).
- `DownloadCoordinator` — wraps `URLSessionDownloadDelegate` for streamed progress. Reports `fraction = -1` when `Content-Length` is absent.
- Launches go through `WineBackendManager.shared.launch(...)` → `cxstart --bottle <name> [--wait] <exe> [args]`.

## Launch modes (NorthstarLauncher.swift)

| Mode | Command | Notes |
|------|---------|-------|
| Northstar | `steam.exe -applaunch 1237970 -noOriginStartup -multiple -northstar -novid` | `-noOriginStartup -multiple` required by Maxima; prevents Origin hang in Wine |
| Vanilla (NS installed) | `NorthstarLauncher.exe -vanilla -novid` | Avoids auth issues when Maxima/EA aren't running |
| Vanilla (NS absent) | `Titanfall2.exe -novid` | Fallback when Northstar not installed |

## Maxima integration (MaximaService.swift)

- Maxima is **opt-in beta** — gated behind `env.maximaEnabled` (UserDefaults `"maximaEnabled"`).
- Installer saved to `PathResolver.downloadsCache/MaximaSetup.exe` (overwritten each install).
- Installed version tracked in UserDefaults key `"maximaInstalledVersion"` using the GitHub release tag.
- `isUpdateAvailable()` compares local tag vs remote. Shows **Update** button; does **not** auto-update.
- `setupMaxima()` skips download if `maxima-cli.exe` already in bottle (re-registers helper only).
- `updateMaxima()` always downloads — used by the Update button.
- `installedVersion` is `nonisolated` (reads UserDefaults only) so it can be called without `await`.

## Northstar version detection

- `CrossOverDetector.readNorthstarVersion(in:)` reads `{tf2Root}/ns_version.txt` (written by the Northstar installer).
- `WineBottle.northstarVersion: String?` populated during bottle scan.
- `AppEnvironment.bootstrap()` auto-updates Northstar when `bottle.northstarVersion != latest.tagName`.

## Bottle / launcher detection

- `WineBottle` has `hasSteam`, `hasEAApp`, `hasEpicGames`, `hasLauncher` (= any of the three).
- Northstar launch button requires `hasSteam` specifically (goes through `steam.exe`).
- `BottleInstaller.detectStage()` uses `hasLauncher` so EA/Epic manual installs advance onboarding steps.

## Pending work / known issues

### Performance — bottle scan I/O (raised in PR #8 code review)
`CrossOverDetector.bottles()` now calls `locateTitanfall2` (potentially slow recursive search) **plus** `readNorthstarVersion` (one `Data(contentsOf:)`) for every bottle on every refresh. For users with many bottles this can block the actor for several seconds. Consider:
- Caching `northstarVersion` per-bottle keyed by bottle ID in a Dictionary, invalidated only when the bottle's `mtime` changes.
- Or reading `ns_version.txt` lazily when a bottle is selected rather than during the full scan.

### EA app / Epic auto-install (onboarding)
`BottleInstaller.Frontend.available` is `true` only for `.steam`. EA app and Epic frontends are greyed out in automatic onboarding. Implementation would require a different CrossTie or a manual drive to install the launcher without Steam.

### Offline Maxima mode
Maxima supports offline play after a first successful online launch (license files in `C:/ProgramData/Maxima/Licenses/`, valid ~2 weeks). Not yet exposed in the Draconis UI.

### Maxima Steam-only accounts
If TF2 is owned only on Steam and the EA account isn't linked, Maxima will warn and attempt a passthrough. Documented in README. No action needed from Draconis side.

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
