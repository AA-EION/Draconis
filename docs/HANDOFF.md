# Handoff: Draconis Linux/Windows UI rewrite (state as of 2026-11-27)

You are picking up work on **Draconis** (repo `AA-EION/Draconis`; a sibling repo `AA-EION/Maxima-Draconis` exists but isn't involved here). Read `CLAUDE.md` first: it documents the architecture, hard rules and conventions. This file describes what the previous session did, where things stand, and what's open. Decisions that are still open are presented as options, not as instructions.

## The product

Draconis is a launcher for Titanfall 2 + Northstar (the community mod platform). It has two apps:

- **macOS app** (`Draconis/`, SwiftUI with Liquid Glass, macOS 26+). It runs the game through CrossOver or "Draconis Wine". **The owner wants it left as it is.**
- **Linux/Windows app**: until this rewrite it was `CrossPlatform/` (Swift + SwiftCrossUI: GTK 4 on Linux, WinUI 3 on Windows), released as deb/rpm/AppImage/Flatpak/tarball/Windows zip.

Both build on `Core/` (`DraconisCore`, a Swift package with tests: `swift test --package-path Core`).

## What the owner asked for (their words, paraphrased closely)

- The Linux/Windows app must look **as close as possible to the macOS Liquid Glass version**. "No more guessing": libraries that clone Liquid Glass exist (they pointed at https://github.com/al1h3n/liquid-rust). A rewrite is acceptable if that's what parity takes. macOS stays as is.
- "Make sure the Windows/Linux implementation really is like macOS, compare if necessary with CI/CD and a background." That means screenshot both apps in CI over the same desktop background and compare.
- Standing rule: Wine work must always use bottles or prefixes, never the global `~/.wine`.
- The owner prefers concise code with few comments, and English in user-facing text. They test on a real Linux machine (Ubuntu, deb package, Steam copy of TF2 on a second disk, Meta Quest 3) and report back.

## Released state (main)

- Latest release: **v0.14.3** (https://github.com/AA-EION/Draconis/releases/tag/v0.14.3), built from main `522bf1c`. This is still the **old SwiftCrossUI** Linux/Windows app.
- Releases go through the `release.yml` workflow (`workflow_dispatch` on `main` with input `tag`; pushing a tag directly is refused with 403). The release checklist is in `CLAUDE.md`.
- Recent fixes shipped, all in `CHANGELOG.md`:
  - 0.14.1: a `/proc` read crash (Foundation returns corrupt Data for long `/proc/*/cmdline`; now read with `read(2)`).
  - 0.14.2: a download crash. Per-download `URLSession`s were invalidated from their own delegate; on Linux that frees libcurl's `_MultiHandle` while it's in use. There's now one shared session. Also crash reports on Ubuntu (the Yama `ptrace_scope` restriction, fixed with `PR_SET_PTRACER`) and a stderr log at `Logs/draconis.log`.
  - 0.14.3: VR, as below.
- **VR** (CircuitLord's Titanfall 2 VR mod, OpenXR) works on Linux (Steam copies, through the wrapper `draconis-steam-launch`) and Windows. It's documented in `docs/VR.md`. The owner's last real test got through the asset build. It then stopped because `cabextract` was missing; 0.14.3 now checks for it first. One-click "Launch in VR" starts SteamVR. The Monado/WiVRn sockets are shared with Steam's container. **Nobody has confirmed VR in a headset yet.**
- `docs/VR.md` also covers macOS VR research (`wineopenxr` + DXMT projects; a possible plan for Draconis Wine with WiVRn for macOS). Nothing is implemented for that.

## Work in progress: branch `claude/gifted-mayer-26nc87` (pushed; no PR open)

Commits on top of main: `d7c37db` and `b8feca5`, both marked "wip". **This branch removes the old SwiftCrossUI UI**, so it isn't releasable as it stands. The normal CI (`ci.yml`) runs only on PRs and pushes to main, so the branch hasn't been through it.

### Architecture chosen in this session

1. **`Desktop/`: new Rust UI** (crate `draconis-desktop`, binary `draconis`). It uses winit 0.30 + wgpu 30, egui 0.37 (egui-wgpu, egui-winit) and **liquid-rust 0.2.6** (crates.io, MIT/Apache-2.0).
   - Each frame (`src/render.rs`): a backdrop texture → liquid-rust draws the glass panels → egui paints the labels on top (LoadOp::Load). liquid-rust's own docs describe this layering.
   - `src/glass.rs`: during egui layout, widgets call `glass::place(id, rect, radius, tint, z)`. `Layer::sync()` turns those records into a `liquid_rust::Scene` (add, place, set_material, remove).
   - `src/theme.rs`: fonts (Inter, Orbitron, Barlow Condensed from `Desktop/resources`) and tint levels copied from the macOS `DraconisTheme.Card`, mapped to `Material::regular()` + `tint`. "Snow" (the white active pills and prominent buttons) uses a custom dark_tone, because liquid-rust's stained-glass tint follows the backdrop's lightness and would come out grey.
   - `src/widgets.rs`: card, Button (capsule glass), status_pill, segmented, sidebar_item, toggle, search field, progress bar and icons (the Lucide PNGs in `resources/icons`).
   - `src/app.rs`: every screen (Play with the VR card, Mods, Servers, Console, Settings, banners, set-up card), bound to engine state. `rfd` provides file dialogs and `open` opens links.
   - `src/engine.rs`: spawns the engine, reads JSON lines on a thread and sends commands (`Sender`). `Engine::sample()` supplies fixed state for snapshots.
   - `src/main.rs`: windowed mode, plus `--snapshot out.png [WxH] [section] [--backdrop image.png]` for headless renders (software Vulkan works: lavapipe, `VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json` in the dev container).
   - Building needs Rust ≥ 1.99, because liquid-rust's `rust-version` requires it (`rustup toolchain install stable`). On Linux, winit needs `libxkbcommon-x11` at runtime.
2. **`CrossPlatform/Sources/DraconisEngine`: headless Swift engine** (product `draconis-engine`).
   - The former `AppModel` (with VR), `Settings` and `CrashReports` moved here unchanged except for the UI bits.
   - `Protocol.swift`: `Message` (`state` / `log` / `packages` / `servers`), `Command` (`{"cmd": …, "id", "path", "mode", "enabled"}`), and `EngineState` (a snapshot built by `AppModel.snapshot()`). It also contains `perform(_:)`, which maps every UI command to model calls.
   - `main.swift`: reads commands from stdin on a thread and sends state every 50 ms when it changed. It exits when stdin closes.
   - stdout is the protocol channel, so only stderr goes to `Logs/draconis.log`.
   - `DraconisPlatform` (logic and tests) is unchanged. `swift-cross-ui` is no longer a dependency. The UI resources (fonts, icons, app icon) moved to `Desktop/resources`. The VR wrapper script stays as the engine's resource.
3. **`.github/workflows/look.yml`** ("Look comparison"). It runs on pushes to `claude/**` that touch `Desktop/**`, and on matching PRs.
   - macOS job: builds `Draconis.app` on `macos-26` and sets a generated wallpaper (`Desktop/look/wallpaper.py`, pure Python). It creates a fake Draconis Wine prefix (`~/Library/Application Support/Draconis/Prefixes/Titanfall 2/drive_c/…` with an empty Titanfall2.exe, Northstar `mod.json` at the latest tag, and steam.exe), accepts the privacy consent through `defaults`, launches the app and runs `screencapture`.
   - Linux job: renders every page with `--snapshot` over the same wallpaper.
   - Results come back as the artifacts `look-macos` and `look-linux`.
   - The first run (`d7c37db`) succeeded on both jobs: https://github.com/AA-EION/Draconis/actions/runs/46078577316. A second run, for `b8feca5`, was queued when this handoff was written.

### Reference images (in the repo)

- `docs/look/macos-play-reference.png`: **the real macOS app** from CI, at 1024×768 runner resolution, over the generated wallpaper.
- `docs/look/rust-play-wallpaper.png`: the Rust UI's Play screen over the same wallpaper, from sample data.

What the macOS reference shows, factually (worth checking yourself):
- The window content background is **flat dark grey**; the wallpaper doesn't show through it.
- The sidebar is a dark rounded panel. It has section headers "LAUNCHER" (Play, Mods, Servers), "BOTTLE" (a picker and Rescan) and "BACKEND" (CrossOver, Draconis Wine). There is no Console or Settings entry in the sidebar; on macOS those are in menus or sheets.
- The hero card is a dark glass card with a thin rim. Its wordmark is a condensed heavy face, not obviously Orbitron.
- The status pills are light grey with dark text.
- The mode picker is labelled "Mode" and is a small segmented control: "Northstar" / "Titanfall 2 (vanilla)".
- "Launch" is a wide light silver-blue button with dark text. "Uninstall NS" is a dark button beside it.
- The glass effect looks subtle because there is little content behind it.

The Rust render differs from this in background, layout, wording and fonts. No pixel-level comparison has been done.

### Status of the rewrite: what's verified and what isn't

- ✅ The Rust UI builds (`cargo +stable build --release` in `Desktop/`) and renders headless snapshots of every page.
- ✅ The engine builds (`swift build --product draconis-engine` in `CrossPlatform/`). Run by hand against a stand-in Steam set-up, it detected the game, Northstar, the VR install and SteamVR, and streamed state, logs and packages.
- ⚠️ **The windowed app with the live engine never showed data.** First, egui's repaint callback wasn't wired to winit; that's fixed in `main.rs` (`ctx.set_request_repaint_callback`). Then the state failed to parse: Swift sends `steamVRRunning` / `steamVRInstalled`, which serde's camelCase turns into `steamVrRunning`.
  - The last edit, in `engine.rs`, adds explicit renames for those two fields and `#[serde(default)]` on the structs. That command was interrupted, and the edit is **committed but was never compiled or run**.
  - Check: does `Desktop/` build, and does the window fill with live state? `DRACONIS_ENGINE=<path to draconis-engine>` points the UI at an engine binary; by default it looks next to its own executable.
- ❌ Not done:
  - packaging (`Scripts/package-linux.sh`, the Flatpak manifest, `Scripts/package-windows.ps1`, `release.yml` and `ci.yml` still build the removed SwiftCrossUI target);
  - Windows build of the Rust UI and the engine;
  - interaction testing (clicks, text input, file dialogs, scrolling);
  - the docs/CLAUDE.md update for the new architecture;
  - a version/changelog entry (`AppInfo.version` in the engine says 0.15.0, `project.yml` still says 0.14.3);
  - tests for the protocol.
- The old SwiftCrossUI views are deleted on this branch. They are in git history (e.g. `git show 522bf1c:CrossPlatform/Sources/DraconisCross/PlayView.swift`) and describe every feature the old app had.

### Options that were considered (no decision is binding)

Researched liquid-glass options for Linux/Windows, with pros and cons:
- **liquid-rust (wgpu)**: chosen. The most physically faithful (calibrated against Apple's iOS 26/27 Figma kit; refraction, dispersion, merging shapes, springs). It has no widgets; it needs the app to render its content into a texture.
- **egui-glass / vitreo** (egui + wgpu, live backdrop). Smaller and younger.
- **Calcite** (GPUI fork, a full macOS-style glass widget kit; 0 stars; Linux-verified only).
- **Kyant's Backdrop** (Compose Multiplatform, Apache-2.0, ~4.8k stars, live backdrop on desktop through Skia/JVM).
- **shayann07/liquidglass** (Compose Desktop / .NET / Qt; "measured against iOS recordings").
- Flutter `liquid_glass_renderer` (no Linux or Windows support).
- A pure GTK CSS approximation, which was tried first. The owner rejected it as guessing. The patch is not in the repo.

Two other architecture options were weighed: rewriting the logic in Rust, or linking Swift as a library. The engine-process split was chosen to keep the tested Swift logic.

## Environment notes

- Dev container: Swift 6.4.3 is at `/opt/swift-6.4.3-RELEASE-ubuntu24.04/usr/bin` (not on PATH by default). Rust is in `~/.cargo`. Xvfb, openbox, xdotool and ImageMagick are useful for windowed tests. The software Vulkan driver is at `/opt/lavapipe`.
- A stand-in Steam set-up for end-to-end tests isn't in the repo. The previous session used fake `steam` and `proton` scripts and a fake home in a scratch folder; you'd need to rebuild it.
- GitHub: through the MCP tools or `gh api` (REST only; GraphQL is blocked). Pushes go to `claude/gifted-mayer-26nc87` only. Open PRs only when asked.
- The owner reports bugs from a real Ubuntu machine and expects crash reports in `~/.local/share/draconis/Logs/crashes/` plus `Logs/draconis.log`.

## Open questions for you and the owner

- How close is close enough? Pixel comparison against `look.yml` artifacts, or a visual review by the owner?
- Should the Linux/Windows layout copy the macOS structure exactly (sidebar sections, Console/Settings placement, wording), or keep the platform-specific pages it had? The macOS reference has no Console or Settings in the sidebar.
- Should the window background be flat like macOS, or show a wallpaper-like backdrop (macOS doesn't show the wallpaper behind content)?
- Ship the rewrite as 0.15.0 only when it reaches parity and packaging works on both OSes? Or keep the old SwiftCrossUI app in releases until then?
