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

Draconis is **not** a Wine front-end of its own — it's a polished native launcher that drives **CrossOver** underneath. If you already have a CrossOver bottle with Titanfall 2 installed, Draconis detects it and just launches the game. If you don't, the onboarding wizard sets one up end-to-end.

## ⚠️ Opening Draconis for the first time

Draconis is **not notarised by Apple**, so the first time you launch it macOS will refuse with one of these:

> *"Draconis" cannot be opened because Apple cannot check it for malicious software.*

> *"Draconis" is damaged and can't be opened. You should move it to the Trash.*

Normal for any open-source macOS app without an Apple Developer ID. Pick whichever route is easiest:

### Option A — Right-click → Open *(recommended)*

1. In Finder, **right-click** (or Control-click) `Draconis.app`.
2. Choose **Open**.
3. macOS shows the warning again, this time with an **Open** button. Click it.
4. From now on Draconis launches normally.

### Option B — System Settings

1. Try to launch Draconis normally (it gets blocked).
2. Open **System Settings → Privacy & Security**.
3. Scroll to the **Security** section — there's a line *"Draconis was blocked from use…"* with an **Open Anyway** button.
4. Click it and confirm.

### Option C — Terminal *(if Gatekeeper says "damaged")*

```bash
xattr -dr com.apple.quarantine /Applications/Draconis.app
```

Then launch normally.

---

## Features

- **One-click launch** for both Northstar and vanilla Titanfall 2 from any detected CrossOver bottle.
- **Guided onboarding wizard** that picks up where you left off — detects existing bottles, lets you reuse them or create new ones, and walks you through whichever step is missing.
- **Four install sources**: Maxima (direct EA download), EA app, Steam, or Epic Games *(coming soon)*. Pick one — Draconis handles the rest.
- **Automatic EA authentication** via [Maxima-Draconis](https://github.com/AA-EION/Maxima-Draconis). No need to keep EA Desktop running while you play.
- **Steam CEG fix** — Steam-installed Titanfall 2 binaries are DRM-signed in a way that doesn't run cleanly under Wine. Draconis swaps just the two affected files (~3 MB) so the rest of your Steam install — save games, Northstar mods, the full ~30 GB — stays untouched.
- **Northstar auto-updater** on every launch.
- **Thunderstore mod browser** with install / enable / disable / uninstall.
- **Server browser** backed by the Northstar masterserver.
- **Native Liquid Glass UI** using macOS Tahoe's `.glassEffect()` — no fake blur.

## Requirements

- macOS Tahoe (26) or later.
- [CrossOver](https://www.codeweavers.com/crossover) installed at `/Applications/CrossOver.app`.
- A legal copy of Titanfall 2 on any of:
  - **Steam** *(needs the CEG fix Draconis applies for you)*
  - **EA app**
  - **EA library directly** — purchased on EA, or your Steam/Epic account linked + synced at least once. Draconis can download the game itself via Maxima.
  - **Epic Games** *(coming soon)*

## How it works

The wizard adapts to what's already on your Mac:

1. **No bottles yet** → pick an install source → Draconis creates a fresh `win10_64` bottle, installs the launcher you picked, and waits for Titanfall 2 to arrive in it.
2. **Existing bottle detected** → choose to reuse it or create a new one. If you reuse, Draconis scans what's inside and skips ahead to the first missing piece.
3. **Maxima route specifically** → Draconis installs Maxima into the bottle, then drives the OAuth login + game download from inside Maxima's UI. You only have to sign into EA in your browser. Draconis watches the install and advances when it's truly done.

Once the bottle is ready, the **Play** screen detects whether Northstar is installed and lets you launch either mode. Launches go through CrossOver's `cxstart` so the bottle environment is set up correctly.

## Steam CEG fix

Steam ships Titanfall 2's `Titanfall2.exe` and `Titanfall2_trial.exe` signed with **CEG** (Custom Executable Generation) per-user DRM. On macOS/CrossOver the DRM check fails and the game shows:

> *Engine Error: File corruption detected*

Nothing's actually corrupted — the DRM just can't verify itself under Wine. CEG only touches those two binaries; every other file in the Steam install matches the EA original.

Draconis fixes it by replacing just those two files with EA's originals via Maxima (~3 MB download, under a minute). Your Steam library entry, save games, Northstar mods, and the rest of the install stay untouched. The wizard offers this as a one-click step when it detects a Steam install + Maxima in the same bottle.

## Maxima authentication

[Maxima-Draconis](https://github.com/AA-EION/Maxima-Draconis) is an open-source replacement for EA Desktop / Origin that runs inside the CrossOver bottle. Draconis bundles its host-side helper (`MaximaHelper.app`) and downloads the bottle-side installer (`MaximaSetup.exe`) on demand.

When Maxima is installed in a bottle, Draconis routes launches through it for EA authentication — no need for EA Desktop to be open. The installed Maxima version is tracked; an **Update Maxima** button appears in Settings when a newer release is published.

If your Titanfall 2 EA license isn't linked to your EA account (Steam-only owners), Maxima can't see the game in your library. Linking accounts at [ea.com](https://www.ea.com) resolves this — takes about 30 seconds.

## Building

```bash
# Generate the Xcode project + open it
./bootstrap.sh --open

# Or build from the command line
xcodebuild -project Draconis.xcodeproj \
           -scheme Draconis \
           -configuration Release \
           -derivedDataPath build
```

Output: `build/Build/Products/Release/Draconis.app`. See [BUILD.md](./BUILD.md) for the full build + signing + notarisation walkthrough, and [CLAUDE.md](./CLAUDE.md) for the architecture deep dive.

## Contributors

<a href="https://github.com/AA-EION/Draconis/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=AA-EION/Draconis" />
</a>

Made with [contrib.rocks](https://contrib.rocks).

## Credits

- The Northstar team at [R2Northstar](https://github.com/R2Northstar)
- [Viper](https://github.com/0neGal/viper) by 0neGal — the original launcher that inspired Draconis
- [CodeWeavers](https://www.codeweavers.com/) for CrossOver
- [Maxima-Draconis](https://github.com/AA-EION/Maxima-Draconis) for EA authentication

## License

GPL-3.0-or-later. Draconis is a derivative work in spirit — but not in code — of the Viper launcher, which carries the same licence.
