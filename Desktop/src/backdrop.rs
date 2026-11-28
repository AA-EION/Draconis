//! What the window shows through: the desktop wallpaper, blurred and darkened
//! like the macOS window's `.hudWindow` material, cut to the window's rounded
//! corners. The glass panels then refract this.

use image::{Rgba, RgbaImage, imageops};

/// The desktop blurred once, in linear light, kept small: blur hides detail.
pub struct Desktop {
    small: RgbaImage,
    /// Screen size in pixels.
    screen: (u32, u32),
}

const DOWNSCALE: u32 = 8;
/// The macOS window material, fitted to docs/look/macos-desktop.png against the
/// macOS screenshots (Desktop/look/fit.py): Gaussian blur σ in points, then in
/// linear light × gain, then an sRGB offset.
const SIGMA: f32 = 115.0;
const SATURATE: f32 = 1.04;
const WINDOW: (f32, f32) = (0.79, -0.126);
/// The sidebar is darker glass over the same blur.
const SIDEBAR: (f32, f32) = (0.28, -0.022);
pub const CORNER: f32 = 16.0;

/// A darker panel in the window's own material (the sidebar), in points.
#[derive(Clone, Copy, PartialEq, Debug)]
pub struct Panel {
    pub rect: [f32; 4],
    pub radius: f32,
}

fn to_linear(c: u8) -> f32 {
    let c = c as f32 / 255.0;
    if c <= 0.04045 { c / 12.92 } else { ((c + 0.055) / 1.055).powf(2.4) }
}

fn to_srgb(c: f32) -> f32 {
    let c = c.clamp(0.0, 1.0);
    if c <= 0.0031308 { c * 12.92 } else { 1.055 * c.powf(1.0 / 2.4) - 0.055 }
}

impl Desktop {
    /// `screen` is the whole desktop as it looks without the window, at `scale` pixels per point.
    pub fn new(screen: &RgbaImage, scale: f32) -> Self {
        let (w, h) = screen.dimensions();
        let small = imageops::resize(screen, (w / DOWNSCALE).max(1), (h / DOWNSCALE).max(1), imageops::FilterType::Triangle);
        Self { small: imageops::blur(&small, SIGMA * scale / DOWNSCALE as f32), screen: (w, h) }
    }

    /// The fixed backdrop for when the wallpaper can't be read: dark blue-violet fields.
    pub fn fallback(size: (u32, u32)) -> Self {
        let mut img = RgbaImage::new(size.0 / DOWNSCALE + 1, size.1 / DOWNSCALE + 1);
        let (w, h) = img.dimensions();
        for (x, y, p) in img.enumerate_pixels_mut() {
            let (u, v) = (x as f32 / w as f32, y as f32 / h as f32);
            let glow = |cx: f32, cy: f32, r: f32| (1.0 - ((u - cx).powi(2) + (v - cy).powi(2)).sqrt() / r).max(0.0);
            let a = glow(0.15, 0.2, 0.9);
            let b = glow(0.85, 0.3, 0.8);
            let c = glow(0.5, 0.95, 0.7);
            *p = Rgba([(25.0 + 40.0 * a + 80.0 * b + 10.0 * c) as u8, (30.0 + 55.0 * a + 30.0 * b + 85.0 * c) as u8, (60.0 + 110.0 * a + 100.0 * b + 95.0 * c).min(255.0) as u8, 255]);
        }
        Self { small: img, screen: size }
    }

    /// The window's content for a window at `origin` (screen pixels) of `size` pixels.
    pub fn content(&self, origin: (i32, i32), size: (u32, u32), scale: f32, panel: Option<Panel>) -> Vec<u8> {
        let (sw, sh) = (self.small.width() as f32, self.small.height() as f32);
        let fx = sw / self.screen.0 as f32;
        let fy = sh / self.screen.1 as f32;
        let radius = CORNER * scale;
        let lut: Vec<f32> = (0..=255).map(|c| to_linear(c as u8)).collect();
        let mut out = Vec::with_capacity((size.0 * size.1 * 4) as usize);
        for y in 0..size.1 {
            let sy = ((origin.1 as f32 + y as f32) * fy - 0.5).clamp(0.0, sh - 1.0);
            for x in 0..size.0 {
                let sx = ((origin.0 as f32 + x as f32) * fx - 0.5).clamp(0.0, sw - 1.0);
                let c = bilinear(&self.small, sx, sy);
                let lin = c.map(|v| { let i = v as usize; lut[i] + (lut[(i + 1).min(255)] - lut[i]) * v.fract() });
                let grey = 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2];
                let (px, py) = ((x as f32 + 0.5) / scale, (y as f32 + 0.5) / scale);
                let inside = panel.map_or(0.0, |p| rounded_coverage(px - p.rect[0], py - p.rect[1], (p.rect[2], p.rect[3]), p.radius, scale));
                let gain = WINDOW.0 + (SIDEBAR.0 - WINDOW.0) * inside;
                let lift = WINDOW.1 + (SIDEBAR.1 - WINDOW.1) * inside;
                let a = corner_alpha(x as f32 + 0.5, y as f32 + 0.5, size, radius);
                let channel = |c: f32| ((to_srgb((grey + (c - grey) * SATURATE) * gain) + lift).clamp(0.0, 1.0) * 255.0 * a) as u8;
                out.extend_from_slice(&[channel(lin[0]), channel(lin[1]), channel(lin[2]), (a * 255.0) as u8]);
            }
        }
        out
    }
}

/// Coverage of a rounded rectangle of `size` points at `(x, y)` points from its corner.
fn rounded_coverage(x: f32, y: f32, size: (f32, f32), r: f32, scale: f32) -> f32 {
    let cx = x.clamp(r, size.0 - r);
    let cy = y.clamp(r, size.1 - r);
    let d = ((x - cx).powi(2) + (y - cy).powi(2)).sqrt();
    ((r - d) * scale + 0.5).clamp(0.0, 1.0)
}

fn bilinear(img: &RgbaImage, x: f32, y: f32) -> [f32; 3] {
    let (x0, y0) = (x.floor() as u32, y.floor() as u32);
    let (x1, y1) = ((x0 + 1).min(img.width() - 1), (y0 + 1).min(img.height() - 1));
    let (tx, ty) = (x - x0 as f32, y - y0 as f32);
    let p = |x, y| img.get_pixel(x, y).0;
    let mut c = [0.0; 3];
    for (i, v) in c.iter_mut().enumerate() {
        let top = p(x0, y0)[i] as f32 * (1.0 - tx) + p(x1, y0)[i] as f32 * tx;
        let bottom = p(x0, y1)[i] as f32 * (1.0 - tx) + p(x1, y1)[i] as f32 * tx;
        *v = top * (1.0 - ty) + bottom * ty;
    }
    c
}

/// Coverage of the window's rounded rectangle at a pixel centre.
fn corner_alpha(x: f32, y: f32, size: (u32, u32), r: f32) -> f32 {
    let (w, h) = (size.0 as f32, size.1 as f32);
    let cx = x.clamp(r, w - r);
    let cy = y.clamp(r, h - r);
    let d = ((x - cx).powi(2) + (y - cy).powi(2)).sqrt();
    (r + 0.5 - d).clamp(0.0, 1.0)
}

/// The current desktop wallpaper, scaled to fill a screen of `size` pixels.
pub fn wallpaper(size: (u32, u32)) -> Option<RgbaImage> {
    let image = image::open(wallpaper_path()?).ok()?.to_rgba8();
    let (w, h) = image.dimensions();
    let zoom = (size.0 as f32 / w as f32).max(size.1 as f32 / h as f32);
    let scaled = imageops::resize(&image, (w as f32 * zoom).ceil() as u32, (h as f32 * zoom).ceil() as u32, imageops::FilterType::Triangle);
    let (x, y) = ((scaled.width() - size.0) / 2, (scaled.height() - size.1) / 2);
    Some(imageops::crop_imm(&scaled, x, y, size.0, size.1).to_image())
}

#[cfg(target_os = "linux")]
fn wallpaper_path() -> Option<std::path::PathBuf> {
    use std::process::Command;
    // Inside Flatpak, ask the host's gsettings and read system images through /run/host.
    let flatpak = std::env::var_os("FLATPAK_ID").is_some();
    let host = |path: &str| {
        let path = std::path::PathBuf::from(path.replace("%20", " "));
        let path = match path.strip_prefix("/usr") {
            Ok(rest) if flatpak => std::path::Path::new("/run/host/usr").join(rest),
            _ => path,
        };
        path.is_file().then_some(path)
    };
    let get = |schema: &str, key: &str| {
        let mut command = if flatpak { let mut c = Command::new("flatpak-spawn"); c.args(["--host", "gsettings"]); c } else { Command::new("gsettings") };
        let out = command.args(["get", schema, key]).output().ok()?;
        Some(String::from_utf8(out.stdout).ok()?.trim().trim_matches('\'').to_owned())
    };
    let gsettings = |key: &str| {
        let value = get("org.gnome.desktop.background", key)?;
        host(value.strip_prefix("file://").unwrap_or(&value))
    };
    let dark = get("org.gnome.desktop.interface", "color-scheme").is_some_and(|v| v.contains("dark"));
    let gnome = if dark { gsettings("picture-uri-dark").or_else(|| gsettings("picture-uri")) } else { gsettings("picture-uri") };
    gnome.or_else(|| {
        let home = std::env::var_os("HOME")?;
        let config = std::fs::read_to_string(std::path::Path::new(&home).join(".config/plasma-org.kde.plasma.desktop-appletsrc")).ok()?;
        let line = config.lines().find(|l| l.starts_with("Image="))?;
        host(line.trim_start_matches("Image=").trim_start_matches("file://"))
    })
}

#[cfg(windows)]
fn wallpaper_path() -> Option<std::path::PathBuf> {
    let out = std::process::Command::new("reg").args(["query", r"HKCU\Control Panel\Desktop", "/v", "WallPaper"]).output().ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    let path = text.lines().find(|l| l.contains("REG_SZ"))?.split("REG_SZ").nth(1)?.trim().to_owned();
    let path = std::path::PathBuf::from(path);
    path.is_file().then_some(path)
}

#[cfg(not(any(target_os = "linux", windows)))]
fn wallpaper_path() -> Option<std::path::PathBuf> { None }

/// An opaque window (the Settings window): dark grey inside rounded corners.
pub fn solid(size: (u32, u32), scale: f32) -> Vec<u8> {
    let radius = CORNER * scale;
    let mut out = Vec::with_capacity((size.0 * size.1 * 4) as usize);
    for y in 0..size.1 {
        for x in 0..size.0 {
            let a = corner_alpha(x as f32 + 0.5, y as f32 + 0.5, size, radius);
            let c = (30.0 * a) as u8;
            out.extend_from_slice(&[c, c, c, (a * 255.0) as u8]);
        }
    }
    out
}
