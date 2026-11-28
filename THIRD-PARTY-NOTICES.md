# Third-party notices

Draconis is licensed under GPL-3.0-or-later (see `LICENSE`). It includes or
downloads the following third-party software.

## Bundled in the apps

| Component | Used by | Licence |
|---|---|---|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | all | MIT |
| [Orbitron](https://github.com/theleagueof/orbitron) font | macOS | SIL Open Font License 1.1 (`OFL.txt`) |
| [Inter](https://github.com/rsms/inter) font | Linux, Windows | SIL Open Font License 1.1 (`OFL-Inter.txt`) |
| [Roboto Condensed](https://github.com/googlefonts/RobotoCondensed) and [Roboto Mono](https://github.com/googlefonts/robotomono) fonts (static instances) | Linux, Windows | SIL Open Font License 1.1 (`OFL-RobotoCondensed.txt`, `OFL-RobotoMono.txt`) |
| [Phosphor](https://phosphoricons.com) icons | Linux, Windows | MIT (`LICENSE-Phosphor.txt`) |
| [liquid-rust](https://github.com/al1h3n/liquid-rust), [egui](https://github.com/emilk/egui), [wgpu](https://github.com/gfx-rs/wgpu), [winit](https://github.com/rust-windowing/winit), [resvg](https://github.com/linebender/resvg), [ureq](https://github.com/algesten/ureq), [rfd](https://github.com/PolyMeilex/rfd) and their Rust dependencies | Linux, Windows | MIT / Apache-2.0 (dependency licences listed by `cargo about` / Cargo.lock) |
| [sentry-cocoa](https://github.com/getsentry/sentry-cocoa) | macOS | MIT |
| MaximaHelper from [Maxima-Draconis](https://github.com/AA-EION/Maxima-Draconis) | macOS | GPL-3.0 |
| [swift-crypto](https://github.com/apple/swift-crypto), swift-collections, swift-log, swift-system, swift-subprocess, swift-asn1 | Linux, Windows | Apache-2.0 |
| steamwebhelper wrapper from [steam-on-m1-wine](https://github.com/notpop/steam-on-m1-wine) (`Tools/steamwebhelper-wrapper`) | macOS (Draconis Wine) | MIT |
| Swift runtime and Foundation | all | Apache-2.0 with Runtime Library Exception |

Vulkan (or Direct3D 12 / OpenGL) drivers and, on Linux, libxkbcommon are used from the system, not bundled.

## Downloaded at runtime, on request

| Component | Platform | Licence |
|---|---|---|
| [Northstar](https://github.com/R2Northstar/Northstar) | all | MIT |
| Mods from [Thunderstore](https://thunderstore.io/c/northstar/) | all | per mod |
| wine-crossover build ([yaagl](https://github.com/yaagl/anime-game-wine)) | macOS | LGPL-2.1-or-later |
| [DXMT](https://github.com/3Shain/dxmt) | macOS | LGPL-2.1-or-later |
| [legendary](https://github.com/legendary-gl/legendary) | macOS (Epic) | GPL-3.0 |
| d3dcompiler_47 (via [mozilla/fxc2](https://github.com/mozilla/fxc2)) | macOS | Microsoft redistributable |
| Microsoft Visual C++ Redistributable | macOS | Microsoft software licence |
| EA app installer, Steam installer | macOS, Linux | vendor licences |
| [Maxima-Draconis](https://github.com/AA-EION/Maxima-Draconis) (`MaximaSetup.exe`) | macOS | GPL-3.0 |
| [umu-launcher](https://github.com/Open-Wine-Components/umu-launcher) | Linux | GPL-3.0 |
| [GE-Proton](https://github.com/GloriousEggroll/proton-ge-custom) | Linux | BSD-3-Clause and component licences |

## Downloaded for Titanfall 2 VR (Linux and Windows, only when you install it)

| Component | Licence |
|---|---|
| [Titanfall 2 VR](https://github.com/CircuitLord/CircuitLordVRModInstaller) by CircuitLord | Closed source, all rights reserved. Downloaded from the author's release; Draconis never redistributes it |
| [Northstar](https://github.com/R2Northstar/Northstar) (the version the VR installer pins) | MIT |
| Microsoft Visual C++ runtime DLLs, from Microsoft's `vc_redist.x64.exe` (Linux only, into the game's prefix) | Microsoft Visual C++ Redistributable licence |

The Linux audio fix and VC++ runtime handling are adapted from [MWGIH/TF2SteamFrame](https://github.com/MWGIH/TF2SteamFrame) (GPL-3.0); `draconis-steam-launch` is based on its `tf2vr-frame-launch`.

