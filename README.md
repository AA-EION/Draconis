<p align="center">
  <img src="assets/icon.svg" width="160" alt="Draconis icon" />
</p>

<h1 align="center">Draconis</h1>

<p align="center">
  A (BETA)(Mostly Vibecoded, Cringe, I know) native macOS launcher for <strong>Titanfall 2 + <a href="https://northstar.tf">Northstar</a></strong>, built with SwiftUI and the Liquid Glass design system.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-Tahoe%2026%2B-black?logo=apple" alt="macOS Tahoe 26+" />
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0" />
  <img src="https://img.shields.io/badge/Xcode-26%2B-1575F9?logo=xcode&logoColor=white" alt="Xcode 26+" />
  <img src="https://img.shields.io/github/license/AA-EION/Draconis?color=blue" alt="GPL-3.0" />
</p>

---

Draconis is **not** a Wine front-end of its own — it is a polished native launcher that drives **CrossOver** underneath. If you already have a CrossOver bottle with Titanfall 2 + Northstar installed, **Draconis detects it automatically and just launches the game**. If you don't, the onboarding can create the bottle for you.

## ⚠️ Opening Draconis the first time

Draconis is **not notarised by Apple**. The first time you launch it macOS will refuse with one of these messages:

> *"Draconis" cannot be opened because Apple cannot check it for malicious software.*

> *"Draconis" is damaged and can't be opened. You should move it to the Trash.*

This is normal for any open-source macOS app that isn't paying for an Apple Developer ID. Pick whichever route is easiest for you:

### Option A — Right-click → Open (recommended)

1. In Finder, **right-click** (or Control-click) `Draconis.app`.
2. Choose **Open**.
3. macOS shows the same warning but this time with an **Open** button. Click it.
4. From now on Draconis launches normally with a double-click.

### Option B — System Settings

1. Try to launch Draconis normally (it'll be blocked).
2. Open **System Settings → Privacy & Security**.
3. Scroll to the **Security** section — there will be a line *"Draconis was blocked from use…"* with an **Open Anyway** button.
4. Click it and confirm.

### Option C — Terminal (if Gatekeeper says "damaged")

If macOS quarantined the download and shows the *"damaged"* message, strip the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/Draconis.app
```

Then launch normally.

---

## Features

- **One-click launch** of Northstar or vanilla Titanfall 2 from any detected CrossOver bottle
- **Guided onboarding** with two routes for first-time setup:
  - **Automatic** — Draconis creates a fresh `win10_64` bottle via `cxbottle --create`, then installs the launcher you pick (Steam, EA app, or Maxima)
  - **Manual** — open CrossOver yourself and install whichever launcher you prefer; Draconis polls and advances the onboarding as each piece appears
- **Launcher choice** — Steam, EA app, or **Maxima direct download** (no Steam/EA needed). Epic Games is documented but not yet wired up
- **Steam-CEG fix** — Steam-installed binaries are signed with per-user CEG DRM that breaks under Wine. Draconis can replace just `Titanfall2.exe` + `Titanfall2_trial.exe` with the EA originals via Maxima (~3 MB download, save games and Northstar mods preserved). See [CEG fix](#steam-ceg-fix) below
- **Maxima-aware launch path** — when Maxima is installed in the bottle, Draconis routes launches through `maxima-cli launch` so EA auth is handled cleanly; falls back to direct exe launch otherwise
- **Live bottle location** — reads CrossOver's `BottleDir` preference from `~/Library/Preferences/com.codeweavers.CrossOver.plist`, so a custom bottles folder is picked up automatically
- **Northstar auto-updater** — checks for a new release on every launch and updates automatically when Northstar is already installed
- **Thunderstore mod browser** with install / enable / disable / uninstall support
- **Server browser** backed by the Northstar masterserver
- **Liquid Glass UI** — uses macOS Tahoe's native `.glassEffect()` rather than faking blur with `.ultraThinMaterial`

## Requirements

- macOS Tahoe (26) or later
- [CrossOver](https://www.codeweavers.com/crossover) installed at `/Applications/CrossOver.app`
- A legal copy of Titanfall 2:
  - Steam — works end-to-end (apply the Maxima CEG fix once after install)
  - EA app — works end-to-end
  - Direct via Maxima — requires the game to be in your EA library (purchased on EA, or Steam/Epic linked + synced at least once)
  - Epic Games — install path documented, not yet validated through the wizard

## Onboarding flow

On first launch (or when no Titanfall 2 bottle is detected) Draconis opens an onboarding sheet:

1. **Pick a mode** — Automatic or Manual.
2. **Automatic** → pick a launcher (Steam / EA app / Maxima; Epic is *coming soon*) → click *Start install*. Draconis:
   - Runs `cxbottle --create --template win10_64 --bottle "Titanfall 2"` to create the prefix
   - Downloads + runs the chosen launcher's installer inside the bottle (Steam: `SteamSetup.exe`; EA: `EAappInstaller.exe`; Maxima: `MaximaSetup.exe` plus host-side helper registration)
   - Polls the bottle directory every 5 s and advances the wizard as each component appears
3. **Manual** → Draconis begins polling the bottle as you work in CrossOver yourself. Use whichever installer you prefer; live progress steps update as each piece appears.
4. **Install Titanfall 2** through the launcher you chose. For Steam and EA app this is the launcher's own UI. For Maxima it's the Maxima UI or `maxima-cli install titanfall-2 --path <abs_dir>` from a cmd window inside the bottle.
5. **Run the game once** if you installed via Steam or EA app. The first launch triggers EA Desktop's built-in installation alongside the game and lets it settle. Doing this before installing Maxima prevents EA's auto-setup from overwriting Maxima's protocol registrations.
6. **(Optional) Install Maxima** for EA auth without depending on EA Desktop being open. Required if you want to use the **CEG fix** on a Steam install.

## Steam CEG fix

Steam ships Titanfall 2's `Titanfall2.exe` and `Titanfall2_trial.exe` signed with per-user **CEG** (Custom Executable Generation) DRM. On macOS/CrossOver the runtime validation routes through Wine's `ntdll-Junction_Points` patch and fails, surfacing in-game as:

> *Engine Error: File corruption detected*

Nothing's actually corrupted — the DRM just can't verify itself under Wine. (Same reason [NorthstarProton](https://github.com/R2NorthstarTools/NorthstarProton) disables that Wine patch on Linux / Steam Deck.) CEG only touches those two binaries; every other file in the Steam install matches the EA original.

**The fix.** When Draconis detects a Steam install + Maxima installed in the same bottle, it offers an **Apply Maxima fix** dialog that runs:

```
maxima-cli install titanfall-2 \
  --path "<steam_install>" \
  --replace-files "Titanfall2.exe,Titanfall2_trial.exe" \
  --only-listed-files
```

That replaces just the two CEG-signed binaries with the EA originals — ~3 MB download, under a minute. Your Steam library entry, save games, Northstar files, and the rest of the ~30 GB install are untouched. After the fix, launches proceed cleanly through the full EA auth flow.

This requires [Maxima-Draconis v0.11.0](https://github.com/AA-EION/Maxima-Draconis/releases/tag/v0.11.0) or later inside the bottle.

## Maxima (EA authentication, optional)

[Maxima-Draconis](https://github.com/AA-EION/Maxima-Draconis) is an open-source replacement for EA Desktop that runs inside the CrossOver bottle. It handles EA's authentication handshake so Northstar can launch without the EA app being installed.

When Maxima is enabled:
- **Set up Maxima** downloads `MaximaSetup.exe` from the latest Maxima-Draconis release, installs it inside the bottle, and registers `MaximaHelper.app` as the macOS handler for `qrc://` OAuth redirects.
- The installed version is tracked. When a newer release is available an **Update Maxima** button appears.
- Launches automatically route through `maxima-cli launch Origin.OFR.50.0001456` when Maxima is detected in the bottle. Northstar mode appends `--game-args -northstar`. No Steam-applaunch needed.
- The CEG fix described above is available whenever a Steam install is detected alongside Maxima.

**Known limitation:** if your Titanfall 2 EA license isn't linked to your EA account (Steam-only owners), Maxima can't see the game in your library — it'll surface a "no owned offer found" error. Linking accounts at [ea.com](https://www.ea.com) resolves this permanently.

## How CrossOver detection works

Draconis resolves the bottles location from CrossOver's own preferences:

```
~/Library/Preferences/com.codeweavers.CrossOver.plist  →  BottleDir
```

falling back to `~/Library/Application Support/CrossOver/Bottles` when the key is absent or unusable. Inside each bottle it scans well-known install roots first, then falls back to a depth-limited recursive sweep:

```
<BottleDir>/<bottle>/
    drive_c/Program Files (x86)/Origin Games/Titanfall2/
    drive_c/Program Files (x86)/Steam/steamapps/common/Titanfall2/
    drive_c/Program Files (x86)/EA Games/Titanfall2/
    drive_c/Program Files/Titanfall2/
    …
```

A bottle is marked **Northstar-ready** when `NorthstarLauncher.exe` sits next to `Titanfall2.exe`. The installed Northstar version is read from `ns_version.txt` (written by the Northstar installer) and compared against the latest GitHub release on every launch — Draconis updates automatically when a newer version is available. Launches go through CrossOver's `cxstart` CLI so the bottle environment is set up correctly.

## Building

```bash
# Generate Draconis.xcodeproj and open in Xcode
./bootstrap.sh --open

# Or build from the command line
xcodebuild -project Draconis.xcodeproj \
           -scheme Draconis \
           -configuration Release \
           -derivedDataPath build
```

The build output is `build/Build/Products/Release/Draconis.app`.

See [BUILD.md](./BUILD.md) for the full build, signing, and notarisation walkthrough.

## Project layout

```
Draconis/
├── App/            DraconisApp.swift, AppEnvironment.swift
├── Models/         WineBackend, NorthstarInstall, Mod, Server
├── Services/       CrossOverDetector, WineBackendManager, NorthstarLauncher,
│                   NorthstarUpdater, ThunderstoreClient, ServerBrowserClient,
│                   SteamInstaller, EAInstaller, WineBottleCreator,
│                   BottleInstaller, MaximaService, ProcessRunner,
│                   DownloadCoordinator, PathResolver, DebugLog
├── Views/          ContentView, PlayView, ModsView, ServersView,
│                   SettingsView, OnboardingView, ConsoleView, Components/
└── Resources/      Info.plist, Draconis.entitlements, Assets.xcassets,
                    Draconis.icon
```

## Contributors

<a href="https://github.com/AA-EION/Draconis/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=AA-EION/Draconis" />
</a>

Made with [contrib.rocks](https://contrib.rocks).

## Credits

- The Northstar team at [R2Northstar](https://github.com/R2Northstar)
- [Viper](https://github.com/0neGal/viper) by 0neGal — the original launcher that inspired Draconis
- [CodeWeavers](https://www.codeweavers.com/) for CrossOver and the signed Titanfall 2 install profile

## License

GPL-3.0-or-later. Draconis is a derivative work in spirit — but not in code — of the Viper launcher, which carries the same licence.
