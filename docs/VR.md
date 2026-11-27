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
(WiVRn, Monado); SteamVR is visible either way. Steam rewrites `localconfig.vdf` when it quits, so
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
  before each VR launch.

Runtimes (the Play screen shows which one is running):

| Headset | Runtime | Notes |
|---|---|---|
| Meta Quest 3 / 2 / Pro | **SteamVR + Steam Link** (default) | Open Steam Link on the headset, connect to the PC |
| Meta Quest, Pico | [WiVRn](https://github.com/WiVRn/WiVRn) | Open source streaming, no SteamVR. Proton 9+ |
| Index, Vive, wired headsets | SteamVR, or [Monado](https://monado.freedesktop.org) (Lighthouse needs SteamVR's driver installed) | |

Not covered yet: non-Steam copies on Linux (EA app / Heroic prefixes). They would need umu-launcher
with `PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1` and Proton's `Software\Wine\VR` registry keys
(`openxr_vulkan_*_extensions`, `PROTON_VR_RUNTIME`, `state`) set in the prefix, as described on
[vronlinux.org](https://vronlinux.org/docs/games/vr-no-steam/).

## macOS — investigation (November 2026)

There is no turnkey way to play a Windows VR game on a Mac today:

- **SteamVR is gone from macOS.** Valve stopped shipping it (the `macos_default` branch was removed), so
  Steam Link VR has nothing to stream from a Mac.
- **ALVR** officially supports Windows and Linux hosts only. Its macOS issue
  ([alvr-org/ALVR#2047](https://github.com/alvr-org/ALVR/issues/2047)) has an unpublished proof of
  concept (May 2026): patched ALVR + patched CrossOver + a modified DXMT, streaming The Lab and Half-Life:
  Alyx to a Quest 3S at 90 fps on an M4 Pro. No code was released.
- **OXRSys** (formerly OpenXR-OSX, [demonixis/oxrsys](https://github.com/demonixis/oxrsys), MPL-2.0): a native
  macOS OpenXR runtime with Quest/Pico, Vision Pro and simulator clients, streaming with VideoToolbox over
  Wi-Fi or USB. It serves native macOS OpenXR apps (Metal / MoltenVK); nothing connects Wine's Windows
  OpenXR loader to it yet.
- **Threshold XR** ([NikNakk/threshold-xr](https://github.com/NikNakk/threshold-xr)): a macOS manager for a
  Monado-based stack on Apple Silicon (Monado, xrizer, DXMT, KosmicKrisp, Wine with a Windows-side Monado
  client that must match the service build). Milestone 1, no CI; a native OpenXR app (Open Brush) has
  reached "In headset"; no Windows D3D11 game has been shown.

What a Mac path needs, and how it maps onto Draconis Wine (wine-crossover 11 + DXMT 0.80, already in
the macOS app):

1. A Windows-side OpenXR runtime inside the Wine prefix that forwards to a macOS runtime (OXRSys or
   Monado). Threshold XR's Windows Monado client is the closest existing piece.
2. D3D11 swapchain sharing between DXMT (Metal) and that runtime: OpenXR's `XR_KHR_D3D11_enable`
   images must be backed by Metal textures the runtime can read. This is the patch the ALVR proof of
   concept made to DXMT.
3. The same mod install as on Windows (`TitanfallVR` in Core already does it), run through
   `WineBackendManager`.

Plan: keep VR off on macOS until one of these stacks runs a D3D11 OpenXR game under Wine. Then add
it to the macOS app as a "Labs" option on Draconis Wine prefixes (not CrossOver, whose Wine can't be
patched), reusing `TitanfallVR` for the install and launch. Watch: the ALVR CrossOver work in #2047,
OXRSys's support matrix, and Threshold XR's Wine bridge.
