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
- **Game launches via maxima-cli go through `CleanSpawn.spawn(...)` — NOT `Foundation.Process`.** See "Why CleanSpawn" below; this is a real macOS gotcha worth knowing about.

## Why CleanSpawn (the spawning-Wine-from-a-.app problem)

The exact same `cxstart maxima-cli.exe launch …` invocation reaches the Titanfall 2 main menu when run from `Terminal.app` and freezes TF2 a few seconds into launch (after LSX `GetAllGameInfo`) when run from Draconis via `Foundation.Process`. Reproduced consistently in both directions, both on the same bottle, both with the CEG fix applied.

Three things differ between `Foundation.Process` spawning and shell `fork → setsid → exec` spawning. Setting them on `posix_spawn` directly closes the gap:

| Flag | Why it matters |
|---|---|
| `POSIX_SPAWN_CLOEXEC_DEFAULT` | Without it, every non-`O_CLOEXEC` file descriptor Draconis holds (Mach ports, IOSurface handles, AppKit / CoreFoundation internals — a SwiftUI app has dozens) leaks into the child. Wine's macOS driver chokes on the polluted FD table. |
| `POSIX_SPAWN_SETSID` | Without it, cxstart stays in Draconis's session and process group. Wine's `msync` (Mach-based mutex implementation) appears to need its own session to behave correctly. |
| `responsibility_spawnattrs_setdisclaim(attr, 1)` (private API resolved via `dlsym`) | **This was the critical missing piece.** Without it, macOS keeps the child attributed to Draconis as "responsible process," and Draconis's App Nap / throttling state cascades down. When TF2 takes window focus during launch and Draconis goes background, the kernel throttles the whole subtree — Wine freezes during d3d init. With disclaim set, the child is its own responsible process, same as a `Terminal.app`-spawned binary. |

`Foundation.Process` doesn't expose any of these. It's designed for spawning app-helper processes that share lifecycle with the parent, not independent long-running processes like games. `Draconis/Services/CleanSpawn.swift` wraps `posix_spawn` directly with all three flags set; `MaximaService.launchGame` uses it. The trade-off is that we don't get back a `Process` object — only a PID — so lifetime tracking relies on `pgrep Titanfall2.exe` polling in `AppEnvironment.pollUntilGameExits`.

## Launch modes (NorthstarLauncher.swift)

The launch path is driven by **three variables**: whether Northstar is installed (`bottle.hasNorthstar`), the user's chosen mode (`vanilla` / `northstar`), and the bottle's persisted `MaximaRole` (`.none` / `.authOnly` / `.fullReplace`). The full 7-row decision matrix lives further down in this file under "Launch decision matrix" — that's the authoritative table.

Two invariants that never change regardless of the row:
1. **Never pass `-northstar` to `Titanfall2.exe`.** This Wine branch silently falls through to vanilla. Northstar always means `NorthstarLauncher.exe`.
2. **Vanilla with Northstar installed still uses NorthstarLauncher** (with `-vanilla`). Northstar's `wsock32.dll` proxy applies engine fixes even in vanilla mode.

## Maxima integration (MaximaService.swift)

- Maxima is **opt-in** — determined by `MaximaRole` per bottle (`.none` = no Maxima; `.authOnly` / `.fullReplace` = active). Not installed by default.
- Installer saved to `PathResolver.downloadsCache/MaximaSetup.exe` (overwritten each install).
- Installed version tracked in UserDefaults key `"maximaInstalledVersion"` using the GitHub release tag.
- `isUpdateAvailable()` compares local tag vs remote. Shows **Update** button; does **not** auto-update.
- `setupMaxima()` skips download if `maxima-cli.exe` already in bottle (re-registers helper only).
- `installedVersion` is `nonisolated` (reads UserDefaults only) so it can be called without `await`.

### Maxima CLI / UI surface

| Method | Wraps | Used for |
|---|---|---|
| `listGames(in:)` | `cxstart --bottle … --wait maxima-cli list-games --json` | Pre-flight detection: is TF2 in the user's EA library, where is it installed? Throws `.notLoggedIn` if OAuth hasn't been completed. |
| `applyCegFix(in:gamePath:)` | `cxstart --bottle … --wait maxima-cli install titanfall-2 --path … --replace-files "Titanfall2.exe,Titanfall2_trial.exe" --only-listed-files` | Surgical CEG fix on a Steam install. ~3 MB download. |
| `launchGame(in:gamePath:gameArgs:)` | `cxstart --bottle … maxima-cli launch Origin.OFR.50.0001456 --game-path … [--game-args …]*` | Hot-path launch when Maxima drives auth. The exe path + args come from `NorthstarLauncher`'s decision matrix. |
| `installGameViaUI(in:slug:installPath:)` | `cxstart --bottle … maxima.exe --install <slug> --install-path <path>` | Onboarding's Maxima route: spawns `maxima.exe` with v0.12.0+'s headless-install flags. Returns `pid_t` so the caller can SIGTERM it once `FInstall.txt` lands. |
| `didInstallComplete(in:installPath:)` | `FileManager.fileExists(at: <installPath>/FInstall.txt)` | The truth source for "is the game fully installed?". Maxima writes this marker only after `ContentManager` confirms `is_done()`; relying on `Titanfall2.exe` presence alone gives false positives mid-download. |
| `signalProcessQuit(pid:)` | `kill(pid, SIGTERM)` → poll → `kill(pid, SIGKILL)` | Gracefully terminate a spawned `maxima.exe` once the marker appears. 5-second escalation window. |

All `cxstart`-based methods pipe output to the per-bottle log file (`PathResolver.bottleLogFile(for:)`) so the user can debug failures.

## Northstar version detection

- `CrossOverDetector.readNorthstarVersion(in:)` reads `{tf2Root}/ns_version.txt` (written by the Northstar installer).
- `WineBottle.northstarVersion: String?` populated during bottle scan.
- `AppEnvironment.bootstrap()` auto-updates Northstar when `bottle.northstarVersion != latest.tagName`.

## Bottle / launcher detection

- `WineBottle` has `hasSteam`, `hasEAApp`, `hasEpicGames`, `hasMaxima`, `hasLauncher` (= any of Steam/EA/Epic).
- The Maxima route in `NorthstarLauncher.launch` checks `hasMaxima` first and routes through `maxima-cli launch` when present; everything else is fallback.
- `BottleInstaller.detectStage()` uses `hasLauncher` so EA/Steam manual installs advance onboarding steps.

## Onboarding sources

`BottleInstaller.Frontend` (order matters — this is the order the wizard renders the picker, "most reliable on macOS" first):

- `.maxima` — `startAutoBottleInstall` creates the bottle, then calls `MaximaService.downloadAndInstall(into:)` to install Maxima v0.12.0+. The wizard's progress page then auto-spawns `maxima.exe --install titanfall-2 --install-path "C:\Program Files (x86)\Origin Games\Titanfall2"` (PR-D, depends on Maxima-Draconis v0.12.0). User logs into EA in their host browser; Maxima downloads the game; Draconis watches for `FInstall.txt` and SIGTERMs Maxima when the install is truly done. Requires the game to be in the user's EA library.
- `.ea` — `EAInstaller.install(into:silent:)` downloads EA's installer (`EAappInstaller.exe`). EA app handles `link2ea://` natively; simplest path on macOS when the user owns TF2 on EA.
- `.steam` — `SteamInstaller.install(into:)` downloads `SteamSetup.exe` and runs it silently. User installs TF2 through Steam afterward. **Heads up:** Steam-installed TF2 hits CEG corruption on macOS/CrossOver; apply the Maxima fix afterward (see "CEG fix" below).
- `.epic` — documented, marked `.available = false` (Coming soon).

## CEG fix

Surfaced through the wizard's `MaximaRole` picker rather than a separate dialog (`CegFixDialog.swift` was removed once the per-bottle role concept landed — the role IS the choice). Three roles exist; the Steam path makes `.fullReplace` the recommended default:

| Role | Behavior | When picked |
|---|---|---|
| `.fullReplace` | Install Maxima + run `applyCegFix(in:gamePath:)` → `maxima-cli install --replace-files "Titanfall2.exe,Titanfall2_trial.exe" --only-listed-files`. ~3 MB download, replaces just the CEG-signed launcher binaries with EA originals. Save games + Northstar files + the rest of the install untouched. | Recommended for Steam installs on macOS/CrossOver. |
| `.authOnly` | Install Maxima as the `link2ea://` handler but leave the Steam binaries alone. | When the user's Wine build tolerates Steam CEG (rare on macOS), or for offline-license caching only. |
| `.none` | Don't install Maxima. EA Desktop in the bottle handles auth instead. | EA app-installed bottles where the user doesn't want Maxima at all. |

`applyRole(_:in:progress:)` in `MaximaService` is the single entry point that drives whichever path the role selects. The role is persisted per-bottle via `MaximaRole.save(_:forBottle:)` (UserDefaults, namespaced `draconis.maximaRole.<bottle.id>`).

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

### Privacy consent revocation UI
Currently there is no in-app way to withdraw consent — only `defaults delete org.draconis.launcher` from Terminal. A "Withdraw consent" / "Reset privacy" option in Settings → About would be more discoverable. `ConsentManager.revoke()` already exists; it just needs a button that also quits the app (since the consent screen is shown before the main window).

### SwiftUI Picker + container views gotcha
SwiftUI's `Picker` with `.segmented` style expands container views (`HStack`, `VStack`, `Group`) into individual segments rather than treating the container as one label. `HStack { Image; Text }` inside `ForEach` produces two segments per item instead of one. **Rule:** only use plain `Text` (or `Label`) as direct children of `Picker { ForEach { } }` — never a container with multiple children.

## Code conventions

- No inline comments unless the *why* is non-obvious. No doc-comment blocks.
- All actor-isolated state is only mutated from within the actor or from `@MainActor` context.
- `nonisolated` is acceptable for properties/methods that only touch `let` constants or thread-safe types (e.g. `UserDefaults.standard`).
- `Log.*` (alias for `DebugLog.shared.*`) for all in-app console output. Use `.run` for shell commands, `.ok` for success, `.error` for failures.
- New downloads → `PathResolver.downloadsCache`. New per-bottle logs → `PathResolver.bottleLogFile(for:)`.

## Error tracking & privacy consent (Sentry)

Draconis integrates `sentry-cocoa` v9.14.0 (SPM) for crash reports and bug feedback.

### Key files

| File | Role |
|---|---|
| `Draconis/Services/ConsentManager.swift` | `ConsentManager` — reads/writes `UserDefaults.standard["privacyConsentAccepted"]`; `SentryConfig` — idempotent `boot()` that configures and starts the SDK |
| `Draconis/Services/BugReporter.swift` | `BugReportContext` (Sendable snapshot of AppEnvironment state) + `BugReporter` actor that submits a Sentry `Event` + `SentryFeedback` pair (sentry-cocoa v9 API) |
| `Draconis/Views/PrivacyConsentView.swift` | Full-window overlay shown until consent; "Decline & Quit" calls `NSApp.terminate`; "Accept & Continue" calls `ConsentManager.accept()` + sets `env.privacyConsentAccepted` |
| `Draconis/Views/BugReportSheet.swift` | Sheet triggered by Help menu (⌘⌥B) or Settings → About; auto-collects context + last 60 console lines |

### Consent sequencing

`DraconisApp.init()` calls `SentryConfig.boot()` only when `ConsentManager.isAccepted` is already `true`. First-time users see `PrivacyConsentView` which blocks the entire window; `ConsentManager.accept()` persists consent, then calls `SentryConfig.boot()`, then fires a `privacy_consent_accepted` Sentry event.

`SentryConfig.boot()` is idempotent — safe to call from both paths (returning users and first-time acceptors). The SDK is **never started before consent**.

### What's sent automatically (all launches, post-consent)

- Unhandled exceptions (Sentry default)
- Handled errors captured by `SentrySDK.capture(event:)` at each `catch` site in `AppEnvironment`

### What's sent on user-initiated bug reports

- Structured tags: app version, bottle state, Northstar/Maxima versions, Maxima phase
- Extra: last 60 console lines (home path sanitized to `~`), recent launch/update/Maxima errors
- `SentryFeedback` (v9 API, replaces removed `SentryUserFeedback`) linked to the same event via `associatedEventId`: user description + optional name + optional contact

### GDPR compliance notes

- Consent is required before the SDK starts; there is no opt-out after acceptance other than deleting `org.draconis.launcher` prefs.
- The DSN points to Sentry's EU ingest (`ingest.de.sentry.io`); data is stored in the EU.
- `sendDefaultPii = true` means Sentry may collect IP addresses; this is disclosed in the consent notice.

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

## What landed on Maxima-Draconis (backend) — all shipped to master

Released in order, each `v*` is a tagged GitHub release:

| Release | What |
|---|---|
| v0.7.0 | Dropped TF2-specific `-noOriginStartup -multiple` auto-injection from `launch::start_game`. Maxima stays universal across EA-on-Steam titles. |
| v0.8.0 | `--game-path` accepts a directory (resolves exe via `STEAM_GAMES`). CEG warning when path is in `steamapps\common\`. Full root-cause analysis in Maxima's CLAUDE.md. |
| v0.9.0 | `maxima-cli list-games --json` for machine-readable EA library inspection. `set_stdout_suppressed(bool)` on logger so `--json` output stays clean. |
| v0.10.0 | `maxima-cli install <slug> --path <dir>` non-interactive with JSONL progress (`{"event":"progress","percent":N}` per tick). |
| v0.11.0 | `--replace-files <p1,p2,...>` + `--only-listed-files` on `install` — the surgical Steam-CEG fix. Empirically validated: TF2 from Steam reaches Main Menu after replacing just `Titanfall2.exe` + `Titanfall2_trial.exe` (~3 MB). |
| v0.12.0 | `maxima.exe --install <slug> --install-path <abs>` headless-driven install: spawn Maxima with these args from Draconis, user logs into EA, game downloads. New `FInstall.txt` completion marker (`INSTALL_MARKER_FILENAME`) written to `<install-path>` when `ContentManager` confirms `is_done()` — Draconis polls for it instead of trusting exe-presence. Panic hook to `maxima.panic.log` for crashes that don't unwind through main. |
| v0.12.1 | Downloader retry layer: exponential backoff + jitter (500ms / 1s / 2s / 4s / 8s base + 0-250ms), surface error after exhausted (was silently `Ok`). `DownloadQueueUpdate` emitted on enqueue so the UI shows the in-flight install immediately (previously only fired on `InstallFinished`). On-disk version sync — ship-binary crates + NSIS `PRODUCT_VERSION` aligned with the release tag via `[workspace.package] version` inheritance. |

**The Maxima side is feature-complete for the Draconis rewrite.** Four CLI/UI primitives Draconis depends on:
- `maxima-cli list-games --json` — library detection
- `maxima-cli install <slug> --path <dir> [--replace-files ... --only-listed-files]` — fresh install OR CEG fix
- `maxima-cli launch Origin.OFR.50.0001456 --game-path <exe> [--game-args ...]` — game launch (Maxima sets up LSX, EA env, bootstrap-spawned game)
- `maxima.exe --install <slug> --install-path <abs>` — wizard's Maxima route end-to-end: login + auto-install. Marker file `FInstall.txt` is the completion signal Draconis polls for.

## Steam-CEG root cause (resolved, confirmed)

**Symptom:** TF2 from Steam reproducibly hits `Engine Error: File corruption detected` after LSX `GetAllGameInfo` on macOS/CrossOver.

**Cause:** Steam ships `Titanfall2.exe` and `Titanfall2_trial.exe` signed per-user with **Steam CEG** (Custom Executable Generation). The runtime validation routes through Wine's `ntdll-Junction_Points` patch, which CrossOver inherits from wine-staging — that patch breaks CEG's filesystem ops. The binary's own integrity check fails, surfacing as the generic "File corruption" dialog.

NorthstarProton (Linux) explicitly disables the same Wine patch in their [protonprep-valve-staging.sh](https://github.com/R2NorthstarTools/NorthstarProton/blob/master/patches/protonprep-valve-staging.sh) with comment `ntdll-Junction_Points - breaks CEG drm` — same root cause, different platform.

**Fix (shipped in Maxima v0.11.0):** replace just those two launcher binaries with the EA originals via Maxima's `install --replace-files --only-listed-files`. ~3 MB download, <60 s, leaves save games / Northstar files / the rest of the install untouched. Empirically validated on the user's bottle (May 19 14:45 — binaries on disk dated then).

## The `Foundation.Process` spawn problem (resolved, **critical context**)

**Symptom:** the EXACT same `cxstart maxima-cli.exe launch ...` invocation:
- ✅ reaches TF2 Main Menu when run from `Terminal.app`
- ✅ reaches Main Menu when run from a Bash shell (via Claude Code or otherwise)
- ❌ freezes TF2 a few seconds into launch (black screen, LSX trace stops at `GetAllGameInfo`) when run via `Foundation.Process` from a `.app` like Draconis

**Cause:** `Foundation.Process` calls `posix_spawn` without flags. Three flags that shell `fork → setsid → exec` effectively sets are missing:

| Flag | Why it matters | Set via |
|---|---|---|
| `POSIX_SPAWN_CLOEXEC_DEFAULT` | macOS `.app`s have dozens of non-CLOEXEC FDs open (Mach ports, IOSurface, AppKit, CoreFoundation). They leak into children and confuse Wine's macOS driver. | `posix_spawnattr_setflags`, `0x4000` |
| `POSIX_SPAWN_SETSID` | Without it, the child stays in Draconis's session and process group. Wine's `msync` (Mach-based mutex impl) needs its own session. | `posix_spawnattr_setflags`, `0x0400` |
| `responsibility_spawnattrs_setdisclaim(attr, 1)` (private API, dlsym) | **THIS was the missing piece.** Without it, macOS keeps the child responsibility-attributed to Draconis, and Draconis's App Nap / throttling cascades down. When TF2 takes window focus and Draconis goes background, the kernel throttles the whole chain — Wine freezes during d3d init. | `dlsym(handle, "responsibility_spawnattrs_setdisclaim")` |

`Foundation.Process` doesn't expose any of these. The fix lives in `Draconis/Services/CleanSpawn.swift` — a direct `posix_spawn` wrapper with all three flags set. Returns `pid_t` only (no `Process` handle), so lifetime tracking uses `pgrep Titanfall2.exe` polling in `AppEnvironment.pollUntilGameExits`.

**`MaximaService.launchGame` uses CleanSpawn exclusively for the cxstart invocation.** Other Wine launches (Steam installer, EA installer, bottle creation) still go through `WineBackendManager.launch` → `ProcessRunner.detached` because they're short-lived helpers that don't need the disclaim.

## Launch decision matrix (the actual code path)

`NorthstarLauncher.launch(bottle:mode:)` walks this matrix:

| Northstar in bottle | Mode | `bottle.maximaRole` | Command |
|---|---|---|---|
| yes | vanilla | `.fullReplace` / `.authOnly` | `maxima-cli launch Origin.OFR.50.0001456 --game-path …\NorthstarLauncher.exe --game-args -noOriginStartup --game-args -vanilla` |
| yes | vanilla | `.none` | `cxstart NorthstarLauncher.exe -noOriginStartup -vanilla` (requires `bottle.hasEAApp`) |
| yes | northstar | `.fullReplace` / `.authOnly` | `maxima-cli launch ... --game-path …\NorthstarLauncher.exe --game-args -noOriginStartup` |
| yes | northstar | `.none` | `cxstart NorthstarLauncher.exe -noOriginStartup` (requires `bottle.hasEAApp`) |
| no | vanilla | `.fullReplace` / `.authOnly` | `maxima-cli launch ... --game-path …\Titanfall2.exe` |
| no | vanilla | `.none` | `cxstart Titanfall2.exe` (requires `bottle.hasEAApp`) |
| no | northstar | * | `throw LaunchError.northstarNotFound` |

**Two never-broken invariants:**
1. **Never pass `-northstar` to `Titanfall2.exe`.** This Wine branch ignores it and falls through to vanilla. Northstar always means launching `NorthstarLauncher.exe`.
2. **Vanilla mode with Northstar installed still uses NorthstarLauncher** (with `-vanilla`). Northstar's wsock32 proxy patches engine bugs even in vanilla mode. `-vanilla` flag disables mod loading.

## Architectural decisions taken (don't re-debate these)

- **Maxima stays universal.** No TF2-specific knowledge in the Maxima codebase. Game-specific behavior (Northstar flags, exe names) lives in Draconis.
- **Maxima is opt-in, not default.** Bottle can have Steam or EA alone and still launch TF2; Maxima is an opt-in role.
- **`MaximaRole` is per-bottle, persisted in UserDefaults.** Read via `WineBottle.maximaRole` at launch time. Independent from `hasMaxima` (physical install state).
- **Bottle creation via `cxbottle --create`** directly — no `.tie` file. The old crosstie forced Steam install, which we don't want.
- **Northstar always via `NorthstarLauncher.exe`** — `-northstar` flag on `Titanfall2.exe` is broken on this Wine branch. Vanilla-with-Northstar-installed uses `-vanilla` flag on NorthstarLauncher.
- **`CleanSpawn` for cxstart, not `Foundation.Process`** — see the spawn section above. Critical for game launches.
- **No `maxima-cli serve` integration from Draconis.** Single `maxima-cli launch` works for both vanilla and Northstar (with `--game-path NorthstarLauncher.exe`). The Maxima route in onboarding uses `maxima.exe --install <slug>` instead (Maxima-Draconis v0.12.0+).
- **`FInstall.txt` is the truth source for "install complete".** Exe presence alone gives false positives mid-download. `BottleInstaller.detectStage` requires the marker for Maxima-installed bottles before advancing to `.done`.

## Out of scope (deferred)

- **Epic Games install path.** `BottleInstaller.Frontend.epic.available = false`. Documented but not wired up.
- **Run-game-once enforcement.** Currently informational copy in the wizard's progress step; not a blocking confirmation. Could become a `[I ran the game once]` button in a future PR.
- **First-time bottle migration.** Existing users with pre-wizard bottles default to `maximaRole = .none` (or `.authOnly` if Maxima is physically installed). They'd need to re-run onboarding or get a settings UI to pick a role. Not blocking — they can still launch.
- **`maxima-cli serve` mode integration.** If Maxima's launch mode ever stops working for Northstar (e.g., because Northstar's wsock32 emits link2ea independently and needs `/authorize`), we'd add `MaximaService.startServe(in:)` + a poll-for-port helper. Not needed yet.

## Test infrastructure / current bottle state

User's macOS dev machine:

- `/Applications/CrossOver.app` (current CrossOver, version per `cxbottle --help`)
- `~/Library/Application Support/CrossOver/Bottles/Titanfall 2/` — the active test bottle
  - Steam at `drive_c/Program Files (x86)/Steam/`
  - TF2 at `drive_c/Program Files (x86)/Steam/steamapps/common/Titanfall2/`
  - Maxima at `drive_c/Program Files/Maxima/`
  - Northstar files extracted alongside TF2 (via Draconis's Northstar updater)
  - Bottle log: `~/Library/Application Support/Draconis/Logs/crossover_Titanfall 2.log` (streamed into Draconis's in-app console while a launch is in flight)
- Maxima's own log: `<bottle>/drive_c/users/crossover/AppData/Local/Maxima/Logs/maxima-cli.log`
- Built Draconis.app: `build/Build/Products/Debug/Draconis.app` (via `xcodebuild -derivedDataPath build`)

Confirmed working states:
- `maxima-cli launch Origin.OFR.50.0001456 --game-path "C:\Program Files (x86)\Steam\steamapps\common\Titanfall2\Titanfall2.exe"` from a bottle cmd window — reaches Main Menu.
- Same command from macOS Terminal via `cxstart` — reaches Main Menu.
- Same command via Draconis using `CleanSpawn` (with all three posix_spawn flags + disclaim) — reaches Main Menu.
