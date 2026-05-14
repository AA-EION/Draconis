<p align="center">
  <img src="assets/icon.svg" width="160" alt="Draconis icon" />
</p>

<h1 align="center">Draconis</h1>

<p align="center">
  A (BETA) native macOS launcher for <strong>Titanfall 2 + <a href="https://northstar.tf">Northstar</a></strong>, built with SwiftUI and the Liquid Glass design system.
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
  - **Automatic** — Draconis hands CrossOver the signed Titanfall 2 crosstie and polls every 5 s until the bottle is ready
  - **Manual** — open CrossOver yourself and follow its install profile (Steam or EA app inside the bottle)
- **Live bottle location** — reads CrossOver's `BottleDir` preference from `~/Library/Preferences/com.codeweavers.CrossOver.plist`, so a custom bottles folder is picked up automatically
- **Northstar updater** that downloads releases from [`R2Northstar/Northstar`](https://github.com/R2Northstar/Northstar) and applies them in-place
- **Maxima integration** — installs and registers MaximaHelper so Northstar can bypass the EA Desktop authentication requirement
- **Thunderstore mod browser** with install / enable / disable / uninstall support
- **Server browser** backed by the Northstar masterserver
- **Liquid Glass UI** — uses macOS Tahoe's native `.glassEffect()` rather than faking blur with `.ultraThinMaterial`

## Requirements

- macOS Tahoe (26) or later
- [CrossOver](https://www.codeweavers.com/crossover) installed at `/Applications/CrossOver.app`
- A legal copy of Titanfall 2 (Steam works end-to-end today; EA app + Epic are *coming soon* in the auto installer)

## Onboarding flow

On first launch (or when no Titanfall 2 bottle is detected) Draconis opens an onboarding sheet:

1. **Pick a mode** — Automatic or Manual.
2. **Automatic** → pick a frontend (Steam available today; EA app and Epic are greyed out) → click *Start install*. Draconis opens the bundled `Titanfall2.tie` with CrossOver and polls `BottleDir` every 5 s. Three stages are shown:
   - Bottle is being created and Steam is installing
   - Steam is ready — log in and install Titanfall 2, wait for 100%
   - Titanfall 2 detected — ready to launch
3. **Manual** → follow the step list. The *Open CrossOver* button takes you straight into CrossOver where you can use its built-in Titanfall 2 install profile with either Steam or the EA app.
4. **Set up Maxima** from the EA card on the Play tab once Titanfall 2 is installed.

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

A bottle is marked **Northstar-ready** when `NorthstarLauncher.exe` sits next to `Titanfall2.exe`. Launches go through CrossOver's `cxstart` CLI so the bottle environment is set up correctly.

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
│                   SteamInstaller, BottleInstaller, MaximaService,
│                   ProcessRunner, DownloadCoordinator, PathResolver, DebugLog
├── Views/          ContentView, PlayView, ModsView, ServersView,
│                   SettingsView, OnboardingView, ConsoleView, Components/
└── Resources/      Info.plist, Draconis.entitlements, Assets.xcassets,
                    Draconis.icon, Titanfall2.tie
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
