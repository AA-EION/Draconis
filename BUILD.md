# Building Draconis

Draconis only builds and runs on **macOS Tahoe (26.0+)** because it depends on the Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glassProminent)`). Build will fail on earlier macOS SDKs.

## Prerequisites

1. Xcode 26 or later (App Store or developer.apple.com).
2. Command-line tools: `xcode-select --install`.
3. Homebrew (`https://brew.sh`).
4. XcodeGen (`bootstrap.sh` will install it if missing).

## One-shot build

```bash
git clone https://github.com/<your-org>/Draconis.git
cd Draconis
./bootstrap.sh --open
```

`bootstrap.sh` runs `xcodegen generate` to produce `Draconis.xcodeproj` from `project.yml`. The project file is intentionally **not** committed to the repo — re-run bootstrap whenever you change `project.yml` or add new source files.

## CLI build

```bash
xcodebuild \
  -project Draconis.xcodeproj \
  -scheme Draconis \
  -configuration Release \
  -derivedDataPath build \
  clean build
```

Output: `build/Build/Products/Release/Draconis.app`.

## Code signing

For local development, the project signs with the ad-hoc identity (`CODE_SIGN_IDENTITY = "-"`). To sign with a Developer ID:

```bash
xcodebuild \
  -project Draconis.xcodeproj \
  -scheme Draconis \
  -configuration Release \
  CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  DEVELOPMENT_TEAM=TEAMID \
  CODE_SIGN_STYLE=Manual
```

Then notarise:

```bash
ditto -c -k --sequesterRsrc --keepParent build/Build/Products/Release/Draconis.app Draconis.zip
xcrun notarytool submit Draconis.zip --apple-id you@example.com --team-id TEAMID --wait
xcrun stapler staple build/Build/Products/Release/Draconis.app
```

## Why no sandbox?

Draconis spawns external wine binaries, reads CrossOver bottles outside its container, and writes into `~/Library/Application Support/Draconis`. Doing this from inside the App Sandbox requires per-path security-scoped bookmarks that would force the user to manually grant access to each bottle directory. We opt out (`com.apple.security.app-sandbox = false`) and rely on Hardened Runtime + notarisation for distribution.

## Running tests

There are no tests in this scaffold yet. Suggested first targets:

- Snapshot tests for the Liquid Glass views (use `swift-snapshot-testing`).
- Mock `URLSession` for `ThunderstoreClient`, `NorthstarUpdater`, `ServerBrowserClient`.
- A fake `ProcessRunner` so `NorthstarLauncher.launch` is testable without a real wine binary.
