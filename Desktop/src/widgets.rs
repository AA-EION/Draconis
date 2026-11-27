//! Glass controls after the macOS views: cards, `.glass` / `.glassProminent`
//! buttons, status capsules, the segmented picker and sidebar rows.

use crate::glass;
use crate::theme::{self, Tint};
use egui::text::{LayoutJob, TextFormat};
use egui::{Color32, FontId, Response, Sense, Ui, Vec2};
use std::collections::HashMap;
use std::path::PathBuf;

/// Lucide icons (ISC), light for dark glass and dark for snow glass.
pub struct Icons {
    dir: PathBuf,
    loaded: HashMap<(String, bool), Option<egui::TextureHandle>>,
}

impl Icons {
    pub fn new(resources: PathBuf) -> Self {
        Self { dir: resources.join("icons"), loaded: HashMap::new() }
    }

    pub fn get(&mut self, ctx: &egui::Context, name: &str, dark: bool) -> Option<egui::TextureHandle> {
        let dir = &self.dir;
        self.loaded
            .entry((name.to_owned(), dark))
            .or_insert_with(|| {
                let path = dir.join(format!("{name}-{}.png", if dark { "dark" } else { "light" }));
                let image = image::open(path).ok()?.to_rgba8();
                let size = [image.width() as usize, image.height() as usize];
                let pixels = egui::ColorImage::from_rgba_unmultiplied(size, image.as_raw());
                Some(ctx.load_texture(name, pixels, egui::TextureOptions::LINEAR))
            })
            .clone()
    }
}

/// Text with letter spacing, for the hero wordmark and stencil labels.
pub fn tracked(text: &str, font: FontId, color: Color32, spacing: f32) -> LayoutJob {
    let mut job = LayoutJob::default();
    job.append(text, 0.0, TextFormat { font_id: font, color, extra_letter_spacing: spacing, ..Default::default() });
    job
}

/// Uppercase HUD label (macOS `stencilLabel()`).
pub fn stencil(ui: &mut Ui, text: &str, size: f32, color: Color32) -> Response {
    ui.label(tracked(&text.to_uppercase(), theme::title(size), color, size * 0.18))
}

pub fn icon(ui: &mut Ui, icons: &mut Icons, name: &str, dark: bool, size: f32) {
    if let Some(texture) = icons.get(ui.ctx(), name, dark) {
        ui.add(egui::Image::new(&texture).fit_to_exact_size(Vec2::splat(size)));
    } else {
        ui.add_space(size);
    }
}

/// A glass card filling the width, like `.glassEffect(.regular.tint(...), in: .rect(cornerRadius:))`.
pub fn card<R>(ui: &mut Ui, id: &str, tint: Tint, radius: f32, padding: f32, add: impl FnOnce(&mut Ui) -> R) -> R {
    let inner = egui::Frame::NONE.inner_margin(padding).show(ui, |ui| {
        ui.set_width(ui.available_width());
        add(ui)
    });
    glass::place(ui.id().with(id), inner.response.rect, radius, tint, 0);
    inner.inner
}

pub struct Button<'a> {
    pub title: &'a str,
    pub icon: Option<&'a str>,
    pub prominent: bool,
    pub full_width: bool,
    pub size: f32,
    pub enabled: bool,
}

impl<'a> Button<'a> {
    pub fn new(title: &'a str) -> Self {
        Self { title, icon: None, prominent: false, full_width: false, size: 14.0, enabled: true }
    }
    pub fn icon(mut self, name: &'a str) -> Self { self.icon = Some(name); self }
    pub fn prominent(mut self) -> Self { self.prominent = true; self }
    pub fn full_width(mut self) -> Self { self.full_width = true; self }
    pub fn size(mut self, size: f32) -> Self { self.size = size; self }
    pub fn enabled(mut self, enabled: bool) -> Self { self.enabled = enabled; self }

    /// `.buttonStyle(.glass)` / `.glassProminent`: capsule glass, label on top.
    pub fn show(self, ui: &mut Ui, icons: &mut Icons) -> Response {
        let tint = if self.prominent { Tint::Snow } else { Tint::None };
        let mut ink = tint.ink();
        if !self.enabled {
            ink = ink.gamma_multiply(0.45);
        }
        let galley = ui.painter().layout_no_wrap(self.title.to_owned(), theme::title(self.size), ink);
        let icon_size = self.size + 2.0;
        let gap = if self.icon.is_some() { 8.0 } else { 0.0 };
        let content = Vec2::new(galley.size().x + self.icon.map_or(0.0, |_| icon_size + gap), galley.size().y.max(icon_size));
        let pad = Vec2::new(18.0, if self.full_width { 12.0 } else { 9.0 });
        let width = if self.full_width { ui.available_width() } else { content.x + pad.x * 2.0 };
        let (rect, response) = ui.allocate_exact_size(Vec2::new(width, content.y + pad.y * 2.0), Sense::click());
        let response = if self.enabled { response } else { response.on_hover_cursor(egui::CursorIcon::NotAllowed) };
        let hovered = self.enabled && response.hovered();
        let glass_tint = match (self.prominent, hovered) {
            (true, _) => Tint::Snow,
            (false, true) => Tint::Medium,
            (false, false) => Tint::None,
        };
        glass::place(response.id, rect, 99.0, glass_tint, 1);
        let mut x = rect.center().x - content.x / 2.0;
        if let Some(name) = self.icon {
            if let Some(texture) = icons.get(ui.ctx(), name, self.prominent) {
                let r = egui::Rect::from_min_size(egui::pos2(x, rect.center().y - icon_size / 2.0), Vec2::splat(icon_size));
                ui.painter().image(texture.id(), r, egui::Rect::from_min_max(egui::pos2(0.0, 0.0), egui::pos2(1.0, 1.0)),
                                   Color32::WHITE.gamma_multiply(if self.enabled { 1.0 } else { 0.45 }));
            }
            x += icon_size + gap;
        }
        ui.painter().galley(egui::pos2(x, rect.center().y - galley.size().y / 2.0), galley, ink);
        if self.enabled { response } else { response.with_new_rect(rect) }
    }
}

/// The macOS status capsule: snow-white when active, dark glass otherwise.
pub fn status_pill(ui: &mut Ui, icons: &mut Icons, label: &str, value: &str, icon_name: &str, active: bool) {
    let tint = if active { Tint::Snow } else { Tint::Dark };
    let ink = tint.ink();
    let inner = egui::Frame::NONE.inner_margin(14.0).show(ui, |ui| {
        ui.set_width(ui.available_width());
        ui.horizontal(|ui| {
            ui.spacing_mut().item_spacing.x = 6.0;
            icon(ui, icons, icon_name, active, 13.0);
            stencil(ui, label, 10.0, ink.gamma_multiply(0.75));
        });
        ui.add_space(4.0);
        ui.label(egui::RichText::new(value).font(theme::display(18.0)).color(ink));
    });
    glass::place(ui.id().with(label), inner.response.rect, 16.0, tint, 1);
}

/// A capsule segmented control (macOS `.pickerStyle(.segmented)`).
pub fn segmented<T: PartialEq + Copy>(ui: &mut Ui, id: &str, options: &[(T, &str)], selection: &mut T) {
    let height = 38.0;
    let (rect, _) = ui.allocate_exact_size(Vec2::new(ui.available_width(), height), Sense::hover());
    glass::place(ui.id().with(id), rect, 99.0, Tint::Dark, 1);
    let inner = rect.shrink(4.0);
    let w = inner.width() / options.len() as f32;
    for (i, (value, label)) in options.iter().enumerate() {
        let r = egui::Rect::from_min_size(egui::pos2(inner.min.x + w * i as f32, inner.min.y), Vec2::new(w, inner.height()));
        let response = ui.interact(r, ui.id().with((id, i)), Sense::click());
        let selected = *value == *selection;
        if selected {
            glass::place(response.id, r, 99.0, Tint::Snow, 2);
        }
        if response.clicked() {
            *selection = *value;
        }
        let color = if selected { theme::INK } else { theme::SECONDARY };
        let galley = ui.painter().layout_no_wrap((*label).to_owned(), theme::title(15.0), color);
        ui.painter().galley(r.center() - galley.size() / 2.0, galley, color);
    }
}

/// A sidebar row; the selected one sits on tinted capsule glass.
pub fn sidebar_item(ui: &mut Ui, icons: &mut Icons, icon_name: &str, title: &str, selected: bool) -> Response {
    let (rect, response) = ui.allocate_exact_size(Vec2::new(ui.available_width(), 38.0), Sense::click());
    if selected {
        glass::place(response.id, rect, 99.0, Tint::Medium, 1);
    } else if response.hovered() {
        glass::place(response.id, rect, 99.0, Tint::None, 1);
    }
    let color = if selected { theme::PRIMARY } else { theme::SECONDARY };
    if let Some(texture) = icons.get(ui.ctx(), icon_name, false) {
        let r = egui::Rect::from_center_size(egui::pos2(rect.min.x + 24.0, rect.center().y), Vec2::splat(17.0));
        ui.painter().image(texture.id(), r, egui::Rect::from_min_max(egui::pos2(0.0, 0.0), egui::pos2(1.0, 1.0)), Color32::WHITE);
    }
    let galley = ui.painter().layout_no_wrap(title.to_owned(), theme::title(16.0), color);
    ui.painter().galley(egui::pos2(rect.min.x + 44.0, rect.center().y - galley.size().y / 2.0), galley, color);
    response
}

/// A macOS `.switch` toggle: a capsule track with a glass knob.
pub fn toggle(ui: &mut Ui, id: &str, on: bool) -> Response {
    let (rect, response) = ui.allocate_exact_size(Vec2::new(46.0, 26.0), Sense::click());
    let t = ui.ctx().animate_bool(response.id, on);
    glass::place(response.id.with("track"), rect, 99.0, if on { Tint::Strong } else { Tint::Dark }, 1);
    if on {
        ui.painter().rect_filled(rect.shrink(1.0), egui::CornerRadius::same(13), theme::ACCENT32.gamma_multiply(0.85));
    }
    let knob = egui::Rect::from_center_size(egui::pos2(egui::lerp(rect.min.x + 13.0..=rect.max.x - 13.0, t), rect.center().y), Vec2::splat(22.0));
    glass::place(ui.make_persistent_id((id, "knob")), knob, 99.0, Tint::Snow, 2);
    response
}

/// A capsule search field on dark glass.
pub fn search(ui: &mut Ui, id: &str, hint: &str, text: &mut String, width: f32) -> Response {
    let (rect, _) = ui.allocate_exact_size(Vec2::new(width, 34.0), Sense::hover());
    glass::place(ui.make_persistent_id((id, "field")), rect, 99.0, Tint::Dark, 1);
    let inner = rect.shrink2(Vec2::new(14.0, 6.0));
    ui.put(
        inner,
        egui::TextEdit::singleline(text)
            .id_salt(id)
            .frame(egui::Frame::NONE)
            .hint_text(egui::RichText::new(hint).color(theme::FAINT))
            .font(theme::body(14.0))
            .text_color(theme::PRIMARY),
    )
}

/// A thin capsule progress bar; `None` sweeps (unknown size).
pub fn progress(ui: &mut Ui, fraction: Option<f64>) {
    let (rect, _) = ui.allocate_exact_size(Vec2::new(ui.available_width(), 8.0), Sense::hover());
    let painter = ui.painter();
    painter.rect_filled(rect, egui::CornerRadius::same(4), Color32::from_white_alpha(22));
    let fill = match fraction {
        Some(f) => egui::Rect::from_min_size(rect.min, Vec2::new(rect.width() * f.clamp(0.0, 1.0) as f32, rect.height())),
        None => {
            let t = (ui.input(|i| i.time) * 0.8).fract() as f32;
            ui.ctx().request_repaint();
            let w = rect.width() * 0.3;
            egui::Rect::from_min_size(egui::pos2(rect.min.x + (rect.width() + w) * t - w, rect.min.y), Vec2::new(w, rect.height())).intersect(rect)
        }
    };
    painter.rect_filled(fill, egui::CornerRadius::same(4), theme::ACCENT32);
}
