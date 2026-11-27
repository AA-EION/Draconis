//! Draconis's palette, fonts and glass materials, after the macOS app's
//! `DraconisTheme` and `TF` palette.

use egui::{Color32, FontData, FontDefinitions, FontFamily, FontId};
use liquid_rust::{Color, Material, Tone};
use std::sync::Arc;

/// macOS AccentColor (#D1D8DE).
pub const ACCENT: Color = Color { r: 0.820, g: 0.847, b: 0.871, a: 1.0 };

/// The accent as an egui colour.
pub const ACCENT32: Color32 = Color32::from_rgb(209, 216, 222);
pub const ERROR: Color32 = Color32::from_rgb(255, 140, 140);
pub const OK: Color32 = Color32::from_rgb(153, 242, 178);
pub const PRIMARY: Color32 = Color32::from_rgb(244, 245, 247);
pub const SECONDARY: Color32 = Color32::from_rgba_premultiplied(204, 204, 204, 204);
pub const TERTIARY: Color32 = Color32::from_rgba_premultiplied(184, 184, 184, 184);
pub const FAINT: Color32 = Color32::from_rgba_premultiplied(140, 140, 140, 140);
pub const INK: Color32 = Color32::from_rgb(12, 14, 18);

/// Card tint levels from `DraconisTheme.Card`.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub enum Tint {
    None,
    Subtle,
    Regular,
    Medium,
    Strong,
    Dark,
    Error,
    /// The snow-white "active" capsule and prominent buttons.
    Snow,
}

impl Tint {
    pub fn material(self) -> Material {
        let tinted = |a: f32| Material { tint: Some(ACCENT.with_alpha(a)), ..Material::regular() };
        match self {
            Tint::None => Material::regular(),
            Tint::Subtle => tinted(0.06),
            Tint::Regular => tinted(0.10),
            Tint::Medium => tinted(0.14),
            Tint::Strong => tinted(0.18),
            Tint::Dark => Material { tint: Some(Color::hex(0x000000).with_alpha(0.22)), ..Material::regular() },
            Tint::Error => Material { tint: Some(Color::RED.with_alpha(0.15)), ..Material::regular() },
            // White-tinted glass reads as snow on macOS even over dark content:
            // start from the light backdrop tone so the tint isn't pulled down.
            Tint::Snow => {
                let light = Material::regular().light_tone;
                Material {
                    tint: Some(Color::hex(0xFFFFFF).with_alpha(0.92)),
                    dark_tone: Tone { luminance: 0.97, luminance_mix: 0.85, lighten: 0.6, ..light },
                    ..Material::regular()
                }
            }
        }
    }

    /// Text drawn on this glass.
    pub fn ink(self) -> Color32 {
        if self == Tint::Snow { INK } else { PRIMARY }
    }
}

const ORBITRON: &str = "orbitron";
const BARLOW: &str = "barlow";

pub fn fonts(resources: &std::path::Path) -> FontDefinitions {
    let mut defs = FontDefinitions::default();
    let mut add = |name: &str, file: &str| {
        if let Ok(bytes) = std::fs::read(resources.join(file)) {
            defs.font_data.insert(name.to_owned(), Arc::new(FontData::from_owned(bytes)));
        }
    };
    add("inter", "Inter.ttf");
    add(ORBITRON, "Orbitron-Black.ttf");
    add("orbitron-bold", "Orbitron-Bold.ttf");
    add(BARLOW, "BarlowCondensed-Bold.ttf");
    if defs.font_data.contains_key("inter") {
        defs.families.entry(FontFamily::Proportional).or_default().insert(0, "inter".into());
    }
    let fallback = defs.families.get(&FontFamily::Proportional).cloned().unwrap_or_default();
    for (family, font) in [(ORBITRON, ORBITRON), ("orbitron-bold", "orbitron-bold"), (BARLOW, BARLOW)] {
        let mut list: Vec<String> = defs.font_data.contains_key(font).then(|| font.to_owned()).into_iter().collect();
        list.extend(fallback.iter().cloned());
        defs.families.insert(FontFamily::Name(family.into()), list);
    }
    defs
}

/// macOS `TF.hero`: Orbitron Black.
pub fn hero(size: f32) -> FontId { FontId::new(size, FontFamily::Name(ORBITRON.into())) }
/// macOS `TF.display`: Orbitron Bold.
pub fn display(size: f32) -> FontId { FontId::new(size, FontFamily::Name("orbitron-bold".into())) }
/// macOS `TF.title` and stencil labels: Barlow Condensed Bold.
pub fn title(size: f32) -> FontId { FontId::new(size, FontFamily::Name(BARLOW.into())) }
/// Body text: Inter.
pub fn body(size: f32) -> FontId { FontId::new(size, FontFamily::Proportional) }
