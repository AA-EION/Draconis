# Titanfall 2 VR in Draconis

Draconis installs and launches **Titanfall 2 VR by CircuitLord**, an OpenXR conversion of the
campaign built as a Northstar plugin. This page covers how it works on each platform, what was
investigated for macOS, and what's still missing there.

## The mod

| | |
|---|---|
| Mod | Titanfall 2 VR (`Titanfall2VR.dll`, a Northstar plugin), closed source, all rights reserved: Draconis never ships it, it downloads it from the author's release |
| Source of truth | `manifest-v3.json` in [CircuitLord/CircuitLordVRModInstaller](https://github.com/CircuitLord/CircuitLordVRModInstaller) (version, URL, SHA-256; a beta channel exists) |
| Northstar | The version his installer pins, read from `src/Installer/Installers/Titanfall2Installer.cs` at the manifest's `installer.commit` (1.31.13 at the time of writing) |
| Runtime | OpenXR (`TF2VR_OPENXR=1`). Any active OpenXR runtime: SteamVR, Meta Quest Link, Virtual Desktop, WiVRn, Monado… |
| Needs | The EA app signed in, and no `dxgi.dll` / `d3d11.dll` replacement from another mod |

Layout, identical to the official installer (`TitanfallVR.place`):

- `Titanfall2VRLauncher.exe` — Northstar's launcher, renamed
- `TF2VR/` — a separate Northstar profile: Northstar's `R2Northstar/` contents, `plugins/Titanfall2VR.dll`,
  `tools/{crash_monitor,xr_probe}.exe`, `tools/launch.json`, `tools/steam_api64.dll` (Steam playtime),
  `mods/`, licences, and the game-derived assets that `asset_patcher.exe apply <game> <patches> <assets>`
  builds from the installed game (about 3 GB, verified against `patches/manifest.json`)
- `TF2VR/.draconis-vr.json` — what Draconis installed, so updates and removal only touch its own files

The normal `Titanfall2.exe` and the user's own `R2Northstar/` are never modified. VR saves live
in `%LOCALAPPDATA%\Respawn\Titanfall2_VR`.

Launch (`TitanfallVR.launchArguments`): `TF2VR/tools/crash_monitor.exe "<game>\TF2VR" "<game>\Titanfall2VRLauncher.exe"`
followed by `launch.json`'s `arguments` + `vrArguments` with `{profile}`→`TF2VR`, `{width}`→1280,
`{height}`→720, `{sound}`→1, environment `TF2VR_OPENXR=1` and no stale `TF2VR_*`, `VR_*` or
`XR_RUNTIME_JSON` overrides.

## Windows

Everything runs directly: `asset_patcher.exe` (progress from its `progress <done> <total>` lines),
then `crash_monitor.exe`. File hashes use `certutil`. The player starts their runtime first:

- **Meta Quest 3, easiest:** Steam Link on the headset connects to the PC and starts SteamVR.
- Quest Link / Air Link, Virtual Desktop (VDXR), or any other OpenXR runtime set as active.

## Linux (Steam copies)

Titanfall 2 has to run inside Steam's own Proton and runtime container so the Steam DRM, the EA
app link and the VR runtime all behave as for any Steam game. Draconis does that with a launch
wrapper, `draconis-steam-launch` (copied to `<data>/bin/`), placed in Titanfall 2's Steam launch
options together with Northstar's override:

```
WINEDLLOVERRIDES="wsock32=n,b" PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 "<data>/bin/draconis-steam-launch" %command%
```

- A normal launch passes straight through (`exec "$@"`).
- `steam -applaunch 1237970 -draconis-vr-setup` runs `asset_patcher.exe` with Steam's Proton
  (Draconis watches `<data>/VR/asset_patcher.{log,done}`).
- `steam -applaunch 1237970 -draconis-vr` starts the EA app in the game's prefix, waits for it to
  sign in (`onAuthSuccessUpdated` in its log), then runs `crash_monitor.exe` with the arguments
  Draconis wrote to `TF2VR/tools/draconis-launch-args.txt`.

`PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1` lets the container see the host's OpenXR runtimes
(WiVRn, Monado); SteamVR is visible either way. Monado's and WiVRn's IPC sockets
(`$XDG_RUNTIME_DIR/monado_comp_ipc`, `$XDG_RUNTIME_DIR/wivrn/comp_ipc`) aren't, so for a VR launch
the wrapper adds the ones that exist to `PRESSURE_VESSEL_FILESYSTEMS_RW` before Steam's container starts.

"Launch in VR" (`VRRuntimeStatus.plan`): with no runtime running it starts SteamVR (`steam://run/250820`)
and waits for it, unless the active OpenXR runtime is another one, which the player has to start. It
then follows the wrapper's `launch.log` (EA app starting, signed in, VR launcher starting) and counts
the game as started once `Titanfall2VRLauncher.exe` runs: Steam's own processes carry
`Titanfall2.exe`'s path from the beginning. Steam's Play button starts the normal game. Steam rewrites `localconfig.vdf` when it quits, so
Draconis closes Steam once before changing the options (backup: `localconfig.vdf.draconis-backup`).

Two Linux-only fixes, both from [MWGIH/TF2SteamFrame](https://github.com/MWGIH/TF2SteamFrame) (GPL-3.0):

- **Audio:** the mod captures game audio through the virtual device `VAD\Process_Loopback`, which
  Wine's mmdevapi doesn't know, so it fast-fails with `0xC0000409`. `LoopbackPatch` points the one
  instruction that loads that string at the `DEVINTERFACE_AUDIO_RENDER` GUID, which Wine maps to
  the default output device. Only the installed copy of the DLL is changed; the patch checks its
  result and refuses unknown mod builds. The Swift port is byte-identical to TF2SteamFrame's on 1.0.33.
- **VC++ runtime:** the mod needs `msvcp140.dll` 14.40+, newer than what the EA app puts in the
  prefix. `VCRuntime` unpacks Microsoft's `vc_redist.x64.exe` (with `cabextract` or `bsdtar`, no
  Windows program runs) into `compatdata/1237970/pfx/drive_c/windows/system32`, and restores it
  before each VR launch. The install checks for one of those tools before it starts; the deb and
  rpm recommend `cabextract`.

Runtimes (the Play screen shows which one is running):

| Headset | Runtime | Notes |
|---|---|---|
| Meta Quest 3 / 2 / Pro | **SteamVR + Steam Link** (default) | Open Steam Link on the headset, connect to the PC |
| Meta Quest, Pico | [WiVRn](https://github.com/WiVRn/WiVRn) | Open source streaming, no SteamVR. Proton 9+ |
| Index, Vive, wired headsets | SteamVR, or [Monado](https://monado.freedesktop.org) (Lighthouse needs SteamVR's driver installed) | |

**Tested (November 27, 2026):** Ubuntu, Steam copy on a second disk, Proton Experimental, SteamVR 2.18.4,
Meta Quest 3 over Steam Link. SteamVR logs show the VR launcher connect as an OpenXR scene app, render
1936×2068 per eye at 90 Hz and run for 38 minutes before closing normally. In one recorded stretch Steam
Link's encoder took 16 ms per frame (over the 11.1 ms budget) and 39 % of frames arrived late; lowering
Steam Link's resolution or refresh rate (72 Hz) is the first thing to try if it stutters.

Not covered yet: non-Steam copies on Linux (EA app / Heroic prefixes). They would need umu-launcher
with `PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1` and Proton's `Software\Wine\VR` registry keys
(`openxr_vulkan_*_extensions`, `PROTON_VR_RUNTIME`, `state`) set in the prefix, as described on
[vronlinux.org](https://vronlinux.org/docs/games/vr-no-steam/).

## macOS — investigation (updated November 27, 2026)

SteamVR has no macOS build (Valve removed it), so Steam Link VR can't stream from a Mac directly.
What has changed since the first pass: several community projects now run Windows OpenXR/OpenVR
games under Wine on Apple Silicon and stream them to a Quest. None works with stock CrossOver
alone, and all are experimental.

| Project | Wine | D3D11 → Metal | OpenXR side | Headset link | Notes |
|---|---|---|---|---|---|
| [orchardxr/varbor](https://github.com/orchardxr/varbor) (MIT) | NotProton runners (copies of CrossOver's Wine) | DXMT (or ARM64EC DXVK) | `wineopenxr` + Proton's `vrclient`; [WiVRn for macOS](https://github.com/orchardxr/wivrn-macos) | WiVRn app, Wi-Fi | Half-Life: Alyx confirmed; writes `Software\Khronos\OpenXR\1 ActiveRuntime`, `Software\Wine\VR state=1` and `openvrpaths.vrpath` into the prefix on every launch |
| [anoshmisiosdev/oxrsys-winebridge](https://github.com/anoshmisiosdev/oxrsys-winebridge) | CrossOver | stock DXMT (pinned commit) | `wineopenxr` → [OXRSys](https://github.com/demonixis/oxrsys) runtime | OXRSys APK, USB | Pac-Man VR (OpenXR), SUPERHOT VR (OpenComposite); D3D11 only |
| [abgitdev/TrailBridge-VR](https://github.com/abgitdev/TrailBridge-VR) (MIT) | its own Wine 11.10 | patched DXMT 0.80 | own OpenXR runtime (BasaltVR), not conformant | ALVR client, USB or Wi-Fi | BONELAB, Blade & Sorcery, VTOL VR, Skyrim VR; Quest 3 tested |
| [monofunc/wineopenxr](https://github.com/monofunc/wineopenxr) (LGPL-2.1) | CrossOver 26 + files copied into its Wine tree | DXMT fork (zero-copy `MTLTexture` interop) | needs a runtime with `XR_KHR_metal_enable` (Monado fork) | — | bridge only, untested |
| [NikNakk/macos-wine-xr](https://github.com/NikNakk/macos-wine-xr) (LGPL-2.1) | self-built Wine 11.10 | DXMT fork | RPC thunk → Monado fork / Meta XR Simulator | — | research-grade, `hello_xr` level |
| [somsarashvili/macquestlink](https://github.com/somsarashvili/macquestlink) (MIT) | CrossOver Preview 27 | patched DXMT | real SteamVR (Windows) in the bottle + NVENC shim over VideoToolbox | Steam Link, Wi-Fi | Half-Life: Alyx ~70 fps on M4 Max; OpenVR only |

What this means for Titanfall 2 VR, a D3D11 OpenXR game (the best-covered case):

1. **The Windows side is a `wineopenxr` bridge** (a PE DLL + a Unix `.so` in Wine's lib dirs, a
   `wineopenxr64.json` manifest, and `HKLM\Software\Khronos\OpenXR\1\ActiveRuntime` pointing at it),
   with DXMT sharing the eye textures as Metal textures.
2. **The Mac side is a native OpenXR runtime that streams:** WiVRn for macOS (Quest over Wi-Fi, the
   same client as Draconis's Linux WiVRn path) or OXRSys (Quest over USB).
3. **CrossOver can't be the engine.** The bridge's Unix half has to go into Wine's own lib dirs;
   Draconis never modifies `CrossOver.app` (signature, updates, and it's the user's install). Draconis
   Wine (wine-crossover 11 + DXMT 0.80, ours, in `Draconis/Engine`) can carry it, the way VarboR adds
   it to its runner copies.
4. **The mod itself installs as on Windows** (`TitanfallVR`: download, `asset_patcher.exe` under
   Wine, `TF2VR` profile), and probably needs the two Linux fixes: `LoopbackPatch` (Wine's
   mmdevapi is the same) and a current VC++ runtime (`BottleSetup` already installs it).

Plan, unchanged in spirit but now concrete: a "Labs" VR option for **Draconis Wine prefixes only**:
build `wineopenxr` against Draconis Wine (pin one of the bridges above, likely VarboR's since it
targets WiVRn and is MIT; the PE/Unix halves are LGPL like Wine), ship it in the engine, register the
runtime in the prefix (never globally), and point players to WiVRn for macOS. Blockers before
shipping: DXMT's texture interop must be in the DXMT release Draconis pins (oxrsys-winebridge
reports stock DXMT works; the others use forks), and someone has to test it on a Mac with a Quest.
Watch: [ALVR macOS (#2047)](https://github.com/alvr-org/ALVR/issues/2047), VarboR, WiVRn for macOS.
