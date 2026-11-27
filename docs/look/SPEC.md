# macOS look, measured

Source: `macos-real-play.png`, the real app on a Mac (Retina, 2 px per point), cropped
to the window. CI's `macos-play-reference.png` comes from a virtual Mac that draws no
behind-window blur, so it shows flat grey where the real window is translucent; use it for
layout only.

Values are sRGB at 1×; "over white / over dark" means what the desktop behind was.

| Element | Measured |
|---|---|
| Window | Translucent, heavy blur of the desktop (`.hudWindow` + 8 % black). Out ≈ 0.51 × behind + 25: 151 over white, 49 over #2E2E2E. Corner radius ≈ 16 pt |
| Sidebar | Floating panel inset ≈ 6 pt from the window edge, radius ≈ 18 pt, darker and less blurred glass (≈ 66 over white; colour from behind shows, e.g. blue). Traffic lights at the top left, sidebar toggle at the top right |
| Sidebar sections | Stencil headers LAUNCHER / BOTTLE / BACKEND; rows Play, Mods, Servers, Console (when on); bottle picker + Rescan; CrossOver / Draconis Wine with white check circles |
| Selected row | Light grey (168, 174, 178), radius ≈ 7 pt, full sidebar width minus 6 pt, white bold text |
| Cards | Darker than the window: hero ≈ 78–88, instruction card ≈ 95 over a 136–151 window; thin light rim; radius 26 (hero) / 22 (cards) |
| Prominent button | (211, 219, 226), dark text, rounded rect radius ≈ 6 pt, not a capsule |
| Glass button | (48, 48, 48), white text, same shape |
| Status pills | (226, 226, 226), black text, radius 16 |
| Hero title | "DRACONIS": Helvetica Neue Condensed Black, tracking 8, 48 pt (Orbitron in the bundle is not what renders) |
| Titles | Helvetica Neue Condensed Bold; body text SF Pro |
