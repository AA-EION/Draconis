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

---

# Session snapshot — 2026-05-20 (wizard rewrite + clean spawn)

In-flight branch: **`feat/wine-bottle-creator`** in this repo. Not yet PR'd. Multiple uncommitted changes. Don't lose context — this section is the recovery doc if memory rolls over.

## What landed on Maxima-Draconis (backend) — all shipped to master

Released in order, each `v*` is a tagged GitHub release:

| Release | What |
|---|---|
| v0.7.0 | Dropped TF2-specific `-noOriginStartup -multiple` auto-injection from `launch::start_game`. Maxima stays universal across EA-on-Steam titles. |
| v0.8.0 | `--game-path` accepts a directory (resolves exe via `STEAM_GAMES`). CEG warning when path is in `steamapps\common\`. Full root-cause analysis in Maxima's CLAUDE.md. |
| v0.9.0 | `maxima-cli list-games --json` for machine-readable EA library inspection. `set_stdout_suppressed(bool)` on logger so `--json` output stays clean. |
| v0.10.0 | `maxima-cli install <slug> --path <dir>` non-interactive with JSONL progress (`{"event":"progress","percent":N}` per tick). |
| v0.11.0 | `--replace-files <p1,p2,...>` + `--only-listed-files` on `install` — the surgical Steam-CEG fix. Empirically validated: TF2 from Steam reaches Main Menu after replacing just `Titanfall2.exe` + `Titanfall2_trial.exe` (~3 MB). |

**The Maxima side is feature-complete for the Draconis rewrite.** Three CLI primitives Draconis depends on:
- `maxima-cli list-games --json` — library detection
- `maxima-cli install <slug> --path <dir> [--replace-files ... --only-listed-files]` — fresh install OR CEG fix
- `maxima-cli launch Origin.OFR.50.0001456 --game-path <exe> [--game-args ...]` — game launch (Maxima sets up LSX, EA env, bootstrap-spawned game)

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

## Draconis-side changes on this branch (uncommitted)

Files modified or created on `feat/wine-bottle-creator`:

| File | Status | What |
|---|---|---|
| `Draconis/Resources/Titanfall2.tie` | **deleted** | CrossTie that forcibly installed Steam — replaced by `cxbottle --create` |
| `project.yml` | modified | dropped the `.tie` from `resources:` |
| `Draconis/Services/WineBottleCreator.swift` | **new** | `cxbottle --create --template win10_64 --bottle "Titanfall 2"` wrapper |
| `Draconis/Services/EAInstaller.swift` | **new** | Downloads EAappInstaller.exe + runs via `WineBackendManager.launch` |
| `Draconis/Services/CleanSpawn.swift` | **new** | Direct `posix_spawn` with `CLOEXEC_DEFAULT` + `SETSID` + `responsibility_spawnattrs_setdisclaim` (dlsym) |
| `Draconis/Models/MaximaRole.swift` | **new** | `enum MaximaRole: .none / .authOnly / .fullReplace` with UserDefaults persistence keyed by bottle ID |
| `Draconis/Models/WineBackend.swift` | modified | Added `hasMaxima: Bool` and `maximaRole: MaximaRole` computed property |
| `Draconis/Services/CrossOverDetector.swift` | modified | Added `locateMaximaCli` + populates `hasMaxima` during scan |
| `Draconis/Services/BottleInstaller.swift` | modified | Removed `openTitanfall2Crosstie()`. Added `.maxima` case to `Frontend` enum. Marked `.ea` + `.maxima` `available = true`. Added `summary` property. |
| `Draconis/Services/MaximaService.swift` | modified | Added `OwnedGame` struct, `listGames(in:)`, `applyCegFix(in:gamePath:)`, `launchGame(in:gamePath:gameArgs:)`. **`applyRole(_:in:progress:)` started but has signature mismatch — see "In-flight work" below.** |
| `Draconis/Services/NorthstarLauncher.swift` | **rewritten** | Full decision matrix above. Drops `-northstar` flag entirely. Always uses NorthstarLauncher.exe when present. |
| `Draconis/App/AppEnvironment.swift` | modified | `startAutoBottleInstall(frontend:)` dispatches per-frontend installer. `launch(mode:)` streams bottle log into in-app console + polls `pgrep Titanfall2.exe`. Removed `startManualBottleWatching`. Comment cleanup. |
| `Draconis/Views/OnboardingView.swift` | **rewritten** | Dropped automatic/manual branching. Single-track flow: preflight → sourceChoice → progress → maximaRole. References `env.applyMaximaRole(...)`, `env.applyingMaximaRole`, `env.maximaRoleError` — **none of which exist yet on AppEnvironment**. |
| `Draconis/Views/Components/CegFixDialog.swift` | **new** | Sheet with Apply Maxima fix / Leave in place radio choice. Not currently triggered automatically. |
| `Draconis/Views/PlayView.swift` | modified | Removed CrossTie note + onboarding instructions updated |
| `README.md` | modified | Features list rewritten, new "Steam CEG fix" section, onboarding flow updated |
| `CLAUDE.md` | modified | This file — architecture section + launch matrix + spawning section above |

## In-flight work — DONE (2026-05-20 follow-up session)

All seven items below have been completed. Final state:

1. ✅ **`MaximaService.applyRole`** signatures fixed — uses `downloadAndInstall(into:progress:)`, `uninstall(from:progress:)`, and progress is `@escaping @Sendable (Progress) -> Void` with a `{ _ in }` default.
2. ✅ **`AppEnvironment.applyMaximaRole(_:in:)`** + `@Published applyingMaximaRole` + `@Published maximaRoleError` added. Wired through to the wizard's MaximaRole page.
3. ✅ **`BottleInstaller.Frontend`** reordered to `case maxima, ea, steam, epic`. `OnboardingView.selectedSource` defaults to `.maxima`.
4. ✅ **Build clean.** `xcodebuild -project Draconis.xcodeproj -scheme Draconis -configuration Debug build` → `** BUILD SUCCEEDED **`.
5. **Smoke test** — pending user validation post-merge. See "Test infrastructure" below for the bottle state expected.
6. **Commit + push + PR** — pending; this paragraph is the last edit before that step.
7. ✅ **Docs** — this snapshot updated; README still reflects the multi-launcher wizard.

Additional cleanup landed: removed unused `Views/Components/CegFixDialog.swift` (its job is now handled inline by `OnboardingView.maximaRolePage` via the wizard's RoleRow components). Programmatic CEG fix is still available anywhere via `env.applyMaximaRole(.fullReplace, in: bottle)`.

## Architectural decisions taken (don't re-debate these)

- **Maxima stays universal.** No TF2-specific knowledge in the Maxima codebase. Game-specific behavior (Northstar flags, exe names) lives in Draconis.
- **Maxima is opt-in, not default.** Bottle can have Steam or EA alone and still launch TF2; Maxima is an opt-in role.
- **`MaximaRole` is per-bottle, persisted in UserDefaults.** Read via `WineBottle.maximaRole` at launch time. Independent from `hasMaxima` (physical install state).
- **Bottle creation via `cxbottle --create`** directly — no `.tie` file. The old crosstie forced Steam install, which we don't want.
- **Northstar always via `NorthstarLauncher.exe`** — `-northstar` flag on `Titanfall2.exe` is broken on this Wine branch. Vanilla-with-Northstar-installed uses `-vanilla` flag on NorthstarLauncher.
- **`CleanSpawn` for cxstart, not `Foundation.Process`** — see the spawn section above. Critical for game launches.
- **No `maxima-cli serve` integration from Draconis.** Single `maxima-cli launch` works for both vanilla and Northstar (with `--game-path NorthstarLauncher.exe`). If empirically that breaks for Northstar, we add serve in a follow-up — but the user confirmed Maxima-launch-via-CleanSpawn reaches Main Menu, so this is unblocked.

## Out of scope (deferred)

- **Epic Games install path.** `BottleInstaller.Frontend.epic.available = false`. Documented but not wired up.
- **Run-game-once enforcement.** Currently informational copy in the wizard's progress step; not a blocking confirmation. Could become a `[I ran the game once]` button in a future PR.
- **Auto-presentation of `CegFixDialog`.** The component exists; nothing triggers it automatically. Currently the user picks `.fullReplace` from the wizard's maximaRole page instead.
- **First-time bottle migration.** Existing users with pre-wizard bottles default to `maximaRole = .none`. They'd need to re-run onboarding or get a settings UI to pick a role. Not blocking — they can still launch.
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
- Built Draconis.app: `~/Library/Developer/Xcode/DerivedData/Draconis-dlnmihavmcdjlzgdavlvtbxnyien/Build/Products/Debug/Draconis.app`

Confirmed working states:
- `maxima-cli launch Origin.OFR.50.0001456 --game-path "C:\Program Files (x86)\Steam\steamapps\common\Titanfall2\Titanfall2.exe"` from a bottle cmd window — reaches Main Menu.
- Same command from macOS Terminal via `cxstart` — reaches Main Menu.
- Same command via Draconis using `CleanSpawn` (with all three posix_spawn flags + disclaim) — reaches Main Menu.

## Quick orientation for a fresh Claude

If you're picking this up cold:

1. Read this section top to bottom.
2. Check `git status` on `feat/wine-bottle-creator` in this repo — many uncommitted changes.
3. The first thing to do is fix the four signature mismatches in `MaximaService.applyRole` (see "In-flight work #1").
4. Then add the three missing AppEnvironment hooks (see "In-flight work #2").
5. Then reorder the Frontend enum (#3).
6. Build verify (#4).
7. Manual test (#5).
8. Commit + PR (#6).

After that lands, the wizard rewrite is done end-to-end and the user can take it.
