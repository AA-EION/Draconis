//! Draconis's palette, fonts and glass materials, after the macOS app's
//! `DraconisTheme` and `TF`, tuned against docs/look (see docs/look/SPEC.md).

use egui::{Color32, FontData, FontDefinitions, FontFamily, FontId};
use liquid_rust::{Color, Material, Shadow, Tone};
use std::sync::Arc;

/// macOS AccentColor (#D1D8DE).
pub const ACCENT: Color = Color { r: 0.820, g: 0.847, b: 0.871, a: 1.0 };
pub const ACCENT32: Color32 = Color32::from_rgb(209, 216, 222);
pub const ERROR: Color32 = Color32::from_rgb(255, 105, 97);
pub const OK: Color32 = Color32::from_rgb(52, 199, 89);
pub const PRIMARY: Color32 = Color32::WHITE;
/// `DraconisTheme.Text`: white at 0.88 / 0.80 / 0.75 / 0.65.
pub const STENCIL: Color32 = Color32::from_rgba_premultiplied(224, 224, 224, 224);
pub const SECONDARY: Color32 = Color32::from_rgba_premultiplied(204, 204, 204, 204);
pub const TERTIARY: Color32 = Color32::from_rgba_premultiplied(191, 191, 191, 191);
pub const FAINT: Color32 = Color32::from_rgba_premultiplied(166, 166, 166, 166);
pub const INK: Color32 = Color32::BLACK;

/// Glass surfaces. Card levels are `DraconisTheme.Card`.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Tint {
    Sidebar,
    Subtle,
    Regular,
    Medium,
    Strong,
    Dark,
    Error,
    /// `.buttonStyle(.glass)`.
    Button,
    /// `.glassProminent` with the accent tint.
    Prominent,
    /// The active (snow-white) status pill.
    Snow,
    /// The selected sidebar row and segment.
    Selected,
}

fn dark(lift: f32, darken: f32) -> Tone {
    Tone { lift, luminance: 0.0, luminance_mix: 0.0, lighten: 0.0, darken_to: 0.0, darken }
}

fn light(luminance: f32, mix: f32) -> Tone {
    Tone { lift: 0.0, luminance, luminance_mix: mix, lighten: 0.0, darken_to: 1.0, darken: 0.0 }
}

impl Tint {
    pub fn material(self) -> Material {
        let base = Material {
            frost: 6.0,
            adaptive: false,
            shadow: Shadow { offset_y: 4.0, blur: 14.0, opacity: 0.10 },
            ..Material::regular()
        };
        let card = |accent: f32| Material { dark_tone: dark(0.03, 0.35), tint: Some(ACCENT.with_alpha(accent)), ..base };
        match self {
            Tint::Sidebar => Material { dark_tone: Tone::NONE, frost: 0.0, refraction: 0.3, shadow: Shadow { opacity: 0.0, ..base.shadow }, ..base },
            Tint::Subtle => card(0.06),
            Tint::Regular => card(0.10),
            Tint::Medium => card(0.14),
            Tint::Strong => card(0.18),
            Tint::Dark => Material { dark_tone: dark(0.0, 0.6), ..base },
            Tint::Error => Material { dark_tone: dark(0.02, 0.4), tint: Some(Color::RED.with_alpha(0.15)), ..base },
            Tint::Button => Material { dark_tone: dark(0.0, 0.72), depth: 10.0, shadow: Shadow { opacity: 0.0, ..base.shadow }, ..base },
            Tint::Prominent => Material { dark_tone: light(0.58, 1.0), tint: Some(ACCENT.with_alpha(0.8)), depth: 10.0, ..base },
            Tint::Snow => Material { dark_tone: light(0.9, 0.45), tint: Some(Color::WHITE.with_alpha(0.55)), depth: 14.0, ..base },
            Tint::Selected => Material { dark_tone: light(0.56, 1.0), tint: Some(ACCENT.with_alpha(0.8)), depth: 8.0, shadow: Shadow { opacity: 0.0, ..base.shadow }, ..base },
        }
    }

    /// Text drawn on this glass.
    pub fn ink(self) -> Color32 {
        match self {
            Tint::Prominent | Tint::Snow => INK,
            Tint::Selected => PRIMARY,
            _ => PRIMARY,
        }
    }
}

const CONDENSED_BLACK: &str = "condensed-black";
const CONDENSED_BOLD: &str = "condensed-bold";

/// Inter stands in for SF Pro, Roboto Mono for SF Mono, Roboto Condensed for Helvetica Neue Condensed,
/// which is what the macOS app renders for `TF.hero`, `TF.title` and stencils.
pub fn fonts(resources: &std::path::Path) -> FontDefinitions {
    let mut defs = FontDefinitions::default();
    let mut add = |name: &str, file: &str| {
        if let Ok(bytes) = std::fs::read(resources.join(file)) {
            defs.font_data.insert(name.to_owned(), Arc::new(FontData::from_owned(bytes)));
        }
    };
    add("inter", "Inter.ttf");
    add(CONDENSED_BLACK, "RobotoCondensed-Black.ttf");
    add(CONDENSED_BOLD, "RobotoCondensed-Bold.ttf");
    add("mono", "RobotoMono-Regular.ttf");
    if defs.font_data.contains_key("mono") {
        defs.families.entry(FontFamily::Monospace).or_default().insert(0, "mono".into());
    }
    if defs.font_data.contains_key("inter") {
        defs.families.entry(FontFamily::Proportional).or_default().insert(0, "inter".into());
    }
    let fallback = defs.families.get(&FontFamily::Proportional).cloned().unwrap_or_default();
    for font in [CONDENSED_BLACK, CONDENSED_BOLD] {
        let mut list: Vec<String> = defs.font_data.contains_key(font).then(|| font.to_owned()).into_iter().collect();
        list.extend(fallback.iter().cloned());
        defs.families.insert(FontFamily::Name(font.into()), list);
    }
    defs
}

/// `TF.hero`.
pub fn hero(size: f32) -> FontId { FontId::new(size, FontFamily::Name(CONDENSED_BLACK.into())) }
/// `TF.display`, `TF.title` and `TF.stencil`.
pub fn title(size: f32) -> FontId { FontId::new(size, FontFamily::Name(CONDENSED_BOLD.into())) }
/// `TF.body`.
pub fn body(size: f32) -> FontId { FontId::new(size, FontFamily::Proportional) }
