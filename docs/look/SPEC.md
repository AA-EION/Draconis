# macOS look, measured

Sources:
- `macos-{play,mods,servers,console,settings}.png` and `macos-desktop.png`: CI's macOS runner
  (1 px per point, window at 22,42, 980×672) with "Reduce transparency" switched off, and the
  same desktop without the window. The Look comparison workflow regenerates them.
- `macos-real-play.png`: the real app on the owner's Mac (≈1.36 px per point), cropped to the window.

The window material was fitted with `Desktop/look/fit.py` (desktop → screenshot, least squares
over the empty content area and the sidebar): Gaussian blur σ ≈ 115 pt, then in linear light
× 0.79 (sidebar × 0.28), saturation 1.04, then −0.126 (sidebar −0.022) in sRGB. RMSE 0.027.
Linux/Windows can't read or blur the desktop themselves, so the window is see-through for real (`Desktop/src/render.rs`): window 0.75 and sidebar 0.55 of the desktop come through, glass surfaces nest on top; any blur is the compositor's.

Values are sRGB at 1×; "over white / over dark" means what the desktop behind was.

| Element | Measured |
|---|---|
| Window | Translucent, heavy blur of the desktop (`.hudWindow` + 8 % black); see the fit above. Corner radius ≈ 16 pt, 1 pt light rim |
| Sidebar | Floating panel inset 8 pt, 240 pt wide, radius ≈ 18 pt, darker glass (see the fit). Traffic lights: 14 pt circles centred at (26, 26), (49, 26), (72, 26); sidebar toggle at the panel's top right |
| Sidebar sections | Stencil headers LAUNCHER / BOTTLE / BACKEND; rows Play, Mods, Servers, Console (when on); bottle picker + Rescan; CrossOver / Draconis Wine with white check circles |
| Sidebar rows | 32 pt tall from y = 71, inset 10 pt in the panel, radius ≈ 8; selected = light grey glass (167, 174, 179) with white text; headers at y ≈ 62 / 190 / 288 |
| Cards | Darker glass with a thin light rim; radius 26 (hero) / 22 (cards); content column starts at x = 276, hero at y = 82; pills 70 pt tall, 14 pt apart |
| Prominent button | Light glass, (168, 174, 180) over the CI desktop, (211, 219, 226) over white; dark text; rounded rect radius ≈ 8–10 pt, not a capsule |
| Glass button | (48, 48, 48), white text, same shape |
| Status pills | (226, 226, 226), black text, radius 16 |
| Hero title | "DRACONIS": Helvetica Neue Condensed Black, tracking 8, 48 pt (Orbitron in the bundle is not what renders). Linux/Windows: Roboto Condensed Black |
| Titles | Helvetica Neue Condensed Bold → Roboto Condensed Bold; body SF Pro → Inter; mono SF Mono → Roboto Mono; SF Symbols (filled) → Phosphor fill icons |
