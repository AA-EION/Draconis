//! How much of the desktop each part of the window lets through, as the two
//! backdrops `render.rs` draws over: black, and grey at that level. The macOS
//! window is a `.hudWindow` material over the desktop with a darker sidebar;
//! the levels were fitted to its screenshots (docs/look/SPEC.md).

/// The window over the desktop, and the sidebar panel over the window.
const WINDOW: f32 = 0.75;
const SIDEBAR: f32 = 0.55;
pub const CORNER: f32 = 16.0;

/// A darker panel in the window's own material (the sidebar), in points.
#[derive(Clone, Copy, PartialEq, Debug)]
pub struct Panel {
    pub rect: [f32; 4],
    pub radius: f32,
}

/// Black and see-through backdrops for a window of `size` pixels; `opaque`
/// windows (Settings) let nothing through inside their corners.
pub fn content(size: (u32, u32), scale: f32, panel: Option<Panel>, opaque: bool) -> (Vec<u8>, Vec<u8>) {
    let black = [0, 0, 0, 255].repeat((size.0 * size.1) as usize);
    let mut grey = Vec::with_capacity(black.len());
    let radius = CORNER * scale;
    for y in 0..size.1 {
        for x in 0..size.0 {
            let inside = corner_alpha(x as f32 + 0.5, y as f32 + 0.5, size, radius);
            let (px, py) = ((x as f32 + 0.5) / scale, (y as f32 + 0.5) / scale);
            let sidebar = panel.map_or(0.0, |p| rounded_coverage(px - p.rect[0], py - p.rect[1], (p.rect[2], p.rect[3]), p.radius, scale));
            let window = if opaque { 0.0 } else { WINDOW + (SIDEBAR - WINDOW) * sidebar };
            let v = (((1.0 - inside) + inside * window) * 255.0).round() as u8;
            grey.extend_from_slice(&[v, v, v, 255]);
        }
    }
    (black, grey)
}

/// Coverage of a rounded rectangle of `size` points at `(x, y)` points from its corner.
fn rounded_coverage(x: f32, y: f32, size: (f32, f32), r: f32, scale: f32) -> f32 {
    let cx = x.clamp(r, size.0 - r);
    let cy = y.clamp(r, size.1 - r);
    let d = ((x - cx).powi(2) + (y - cy).powi(2)).sqrt();
    ((r - d) * scale + 0.5).clamp(0.0, 1.0)
}

/// Coverage of the window's rounded rectangle at a pixel centre.
fn corner_alpha(x: f32, y: f32, size: (u32, u32), r: f32) -> f32 {
    let (w, h) = (size.0 as f32, size.1 as f32);
    let cx = x.clamp(r, w - r);
    let cy = y.clamp(r, h - r);
    let d = ((x - cx).powi(2) + (y - cy).powi(2)).sqrt();
    (r + 0.5 - d).clamp(0.0, 1.0)
}

/// What a blurring compositor shows behind the window (snapshots): the desktop
/// with the macOS window blur, σ 115 pt.
pub fn blurred(desktop: &image::RgbaImage) -> image::RgbaImage {
    use image::imageops;
    let (w, h) = desktop.dimensions();
    let small = imageops::resize(desktop, (w / 8).max(1), (h / 8).max(1), imageops::FilterType::Triangle);
    imageops::resize(&imageops::blur(&small, 115.0 / 8.0), w, h, imageops::FilterType::Triangle)
}
