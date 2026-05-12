# Draconis

**Draconis** is a fully open-source launcher for **Titanfall 2 + [Northstar](https://northstar.tf)** built natively for **macOS Tahoe (26+)** with SwiftUI and the Liquid Glass design system.

It is intentionally *not* a Wine front-end of its own — it is a polished native launcher that drives an existing Wine layer underneath:

| Backend                       | Status        | Bottle creation |
| ----------------------------- | ------------- | --------------- |
| CrossOver                     | preferred     | use CrossOver UI |
| Apple Game Porting Toolkit 2  | recommended   | managed by Draconis |
| Kegworks (Wineskin successor) | supported     | use Kegworks UI |
| Whisky (discontinued)         | read-only     | —               |

If you already have a CrossOver bottle with Titanfall 2 + Northstar installed, **Draconis will detect it automatically and just launch the game**. If you don't, Draconis will fall back to GPTK or Kegworks and manage its own prefix under `~/Library/Application Support/Draconis/Bottles/`.

> macOS only. The Linux/Windows port lives in [`/legacy`](./legacy) as the original [Viper](https://github.com/0neGal/viper) launcher (Electron). Draconis is a complete rewrite — there is no shared code.

## Features

- **One-click launch** of Northstar or vanilla Titanfall 2 from any detected bottle.
- **Backend auto-detection** for CrossOver, GPTK, Kegworks, Whisky.
- **Northstar updater** that downloads releases from the official GitHub repository (`R2Northstar/Northstar`) and unzips them on top of the Titanfall 2 install in the prefix.
- **Thunderstore mod browser** with install / enable / disable / uninstall, hitting `northstar.thunderstore.io/api/v1/package/`.
- **Server browser** backed by the Northstar masterserver (`northstar.tf/client/servers`).
- **Steam auto-install** into the active prefix when missing — pulls the official `SteamSetup.exe` from Valve's CDN and runs it via wine.
- **Liquid Glass UI** — uses the macOS Tahoe `.glassEffect()` system natively rather than faking blur with `.ultraThinMaterial`.

## Requirements

- macOS Tahoe (26) or later
- Xcode 26 or later
- A wine/translation layer (CrossOver, GPTK or Kegworks)
- A legal copy of Titanfall 2 (Steam, Origin, or EA App)

## Building

```bash
# 1. Generate Draconis.xcodeproj from project.yml (installs xcodegen if missing)
./bootstrap.sh --open

# 2. Or build straight from the command line
xcodebuild -project Draconis.xcodeproj \
           -scheme Draconis \
           -configuration Release \
           -derivedDataPath build
```

The build output is `build/Build/Products/Release/Draconis.app`.

See [BUILD.md](./BUILD.md) for the full build, signing and notarisation walkthrough.

## How CrossOver detection works

On launch, Draconis scans:

```
/Applications/CrossOver.app
~/Library/Application Support/CrossOver/Bottles/<bottle>/
    drive_c/Program Files (x86)/Origin Games/Titanfall2/
    drive_c/Program Files (x86)/Steam/steamapps/common/Titanfall2/
    drive_c/Program Files/EA Games/Titanfall2/
```

A bottle is marked **Northstar-ready** when `NorthstarLauncher.exe` sits next to `Titanfall2.exe`. When you click *Launch*, Draconis runs:

```
CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine64 \
    NorthstarLauncher.exe -novid
```

with `WINEPREFIX` pointed at your bottle. No Apple Events, no scripting of the CrossOver UI — just a direct wine invocation.

## Project layout

```
Draconis/
├── App/            DraconisApp.swift, AppEnvironment.swift
├── Models/         WineBackend, NorthstarInstall, Mod, Server
├── Services/       CrossOverDetector, WineBackendManager, NorthstarLauncher,
│                   NorthstarUpdater, ThunderstoreClient, ServerBrowserClient,
│                   SteamInstaller, ProcessRunner, PathResolver
├── Views/          ContentView, PlayView, ModsView, ServersView,
│                   SettingsView, OnboardingView, Components/
└── Resources/      Info.plist, Draconis.entitlements, Assets.xcassets
```

## License

GPL-3.0-or-later. Draconis is a derivative work in spirit — but not in code — of the Viper launcher, which carries the same licence.

## Credits

- The Northstar team at [R2Northstar](https://github.com/R2Northstar)
- [Viper](https://github.com/0neGal/viper) by 0neGal, whose feature set inspired Draconis
- Apple's Game Porting Toolkit team
- The Kegworks / former Wineskin maintainers
