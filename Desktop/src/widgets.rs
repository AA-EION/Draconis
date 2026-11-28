//! Controls after the macOS views, sized from docs/look: cards, `.glass` /
//! `.glassProminent` buttons, status pills, the segmented and menu pickers,
//! sidebar rows, switches, checkboxes and the window's traffic lights.

use crate::glass;
use crate::theme::{self, Tint};
use egui::text::{LayoutJob, TextFormat};
use egui::{Color32, CornerRadius, FontId, Pos2, Rect, Response, Sense, Stroke, Ui, Vec2, pos2, vec2};
use std::collections::HashMap;
use std::path::PathBuf;

/// Phosphor icons (MIT), rasterised from SVG at the size they're drawn and tinted.
pub struct Icons {
    dir: PathBuf,
    loaded: HashMap<(String, u32), Option<egui::TextureHandle>>,
}

impl Icons {
    pub fn new(resources: PathBuf) -> Self {
        Self { dir: resources.join("icons"), loaded: HashMap::new() }
    }

    fn texture(&mut self, ctx: &egui::Context, name: &str, px: u32) -> Option<egui::TextureHandle> {
        let dir = &self.dir;
        self.loaded
            .entry((name.to_owned(), px))
            .or_insert_with(|| {
                let svg = std::fs::read(dir.join(format!("{name}.svg"))).ok()?;
                let tree = resvg::usvg::Tree::from_data(&svg, &Default::default()).ok()?;
                let mut pixmap = resvg::tiny_skia::Pixmap::new(px, px)?;
                let s = px as f32 / tree.size().width();
                resvg::render(&tree, resvg::tiny_skia::Transform::from_scale(s, s), &mut pixmap.as_mut());
                let image = egui::ColorImage::from_rgba_premultiplied([px as usize, px as usize], pixmap.data());
                Some(ctx.load_texture(format!("{name}@{px}"), image, egui::TextureOptions::LINEAR))
            })
            .clone()
    }

    pub fn paint(&mut self, ui: &Ui, name: &str, rect: Rect, color: Color32) {
        let px = (rect.width() * ui.ctx().pixels_per_point()).ceil() as u32;
        if let Some(t) = self.texture(ui.ctx(), name, px.max(1)) {
            ui.painter().image(t.id(), rect, Rect::from_min_max(Pos2::ZERO, pos2(1.0, 1.0)), color);
        }
    }
}

pub fn icon(ui: &mut Ui, icons: &mut Icons, name: &str, size: f32, color: Color32) {
    let (rect, _) = ui.allocate_exact_size(Vec2::splat(size), Sense::hover());
    icons.paint(ui, name, rect, color);
}

/// Text with letter spacing (SwiftUI `.tracking`).
pub fn tracked(text: &str, font: FontId, color: Color32, spacing: f32) -> LayoutJob {
    let mut job = LayoutJob::default();
    job.append(text, 0.0, TextFormat { font_id: font, color, extra_letter_spacing: spacing, ..Default::default() });
    job
}

/// `stencilLabel()`: condensed bold, uppercase, tracking 2.5.
pub fn stencil(ui: &mut Ui, text: &str, size: f32, color: Color32) -> Response {
    ui.label(tracked(&text.to_uppercase(), theme::title(size), color, 2.5))
}

pub fn label(ui: &mut Ui, text: &str, size: f32, color: Color32) -> Response {
    ui.add(egui::Label::new(egui::RichText::new(text).font(theme::body(size)).color(color)).wrap())
}

/// `.glassEffect(.regular.tint(...), in: .rect(cornerRadius:))` around the content.
pub fn card<R>(ui: &mut Ui, id: impl egui::AsIdSalt, tint: Tint, radius: f32, padding: f32, add: impl FnOnce(&mut Ui) -> R) -> R {
    let inner = egui::Frame::NONE.inner_margin(padding).show(ui, |ui| {
        ui.set_width(ui.available_width());
        add(ui)
    });
    glass::place(ui.scope_id().with(id), inner.response.rect, radius, tint, 0);
    inner.inner
}

pub struct Button<'a> {
    title: &'a str,
    icon: Option<&'a str>,
    prominent: bool,
    width: Option<f32>,
    font: FontId,
    pad: Vec2,
    enabled: bool,
}

impl<'a> Button<'a> {
    /// A regular `.glass` button: system font 13, like a SwiftUI `Label` in a button.
    pub fn new(title: &'a str) -> Self {
        Self { title, icon: None, prominent: false, width: None, font: theme::body(13.0), pad: vec2(12.0, 6.0), enabled: true }
    }
    pub fn icon(mut self, name: &'a str) -> Self { self.icon = Some(name); self }
    pub fn prominent(mut self) -> Self { self.prominent = true; self }
    pub fn width(mut self, width: f32) -> Self { self.width = Some(width); self }
    /// `TF.title(size)` label with the given padding, as on the Play screen.
    pub fn title_font(mut self, size: f32, pad: Vec2) -> Self { self.font = theme::title(size); self.pad = pad; self }
    pub fn pad(mut self, pad: Vec2) -> Self { self.pad = pad; self }
    pub fn enabled(mut self, enabled: bool) -> Self { self.enabled = enabled; self }

    pub fn show(self, ui: &mut Ui, icons: &mut Icons) -> Response {
        let tint = if self.prominent { Tint::Prominent } else { Tint::Button };
        let mut ink = tint.ink();
        if !self.enabled {
            ink = ink.gamma_multiply(0.4);
        }
        let galley = ui.painter().layout_no_wrap(self.title.to_owned(), self.font.clone(), ink);
        let icon_size = (self.font.size * 1.05).round();
        let gap = if self.icon.is_some() { 7.0 } else { 0.0 };
        let content = vec2(galley.size().x + self.icon.map_or(0.0, |_| icon_size + gap), galley.size().y.max(icon_size));
        let size = vec2(self.width.unwrap_or(content.x + self.pad.x * 2.0), content.y + self.pad.y * 2.0);
        let (rect, response) = ui.allocate_exact_size(size, if self.enabled { Sense::click() } else { Sense::hover() });
        let radius = (rect.height() * 0.2).clamp(6.0, 10.0);
        glass::place(response.id, rect, radius, tint, 1);
        if self.enabled && response.hovered() {
            ui.painter().rect_filled(rect, radius, Color32::from_white_alpha(if self.prominent { 30 } else { 14 }));
        }
        let mut x = rect.center().x - content.x / 2.0;
        if let Some(name) = self.icon {
            let r = Rect::from_min_size(pos2(x, rect.center().y - icon_size / 2.0), Vec2::splat(icon_size));
            icons.paint(ui, name, r, ink);
            x += icon_size + gap;
        }
        ui.painter().galley(pos2(x, rect.center().y - galley.size().y / 2.0), galley, ink);
        response
    }
}

/// `StatusPill`: snow-white when active, dark glass otherwise.
pub fn status_pill(ui: &mut Ui, icons: &mut Icons, label: &str, value: &str, icon_name: &str, active: bool) {
    let tint = if active { Tint::Snow } else { Tint::Dark };
    let (ink, faint) = if active { (Color32::BLACK, Color32::from_black_alpha(184)) } else { (Color32::WHITE, Color32::from_white_alpha(199)) };
    let inner = egui::Frame::NONE.inner_margin(14.0).show(ui, |ui| {
        ui.set_width(ui.available_width());
        ui.with_layout(egui::Layout::top_down(egui::Align::Min), |ui| {
        ui.spacing_mut().item_spacing = vec2(5.0, 8.0);
        ui.horizontal(|ui| {
            icon(ui, icons, icon_name, 11.0, faint);
            ui.label(tracked(&label.to_uppercase(), theme::title(10.0), faint, 2.5));
        });
        ui.label(egui::RichText::new(value).font(theme::title(18.0)).color(ink));
        });
    });
    glass::place(ui.scope_id().with(label), inner.response.rect, 16.0, tint, 1);
}

/// `.pickerStyle(.segmented)`: a small dark track with a light selected segment.
pub fn segmented<T: PartialEq + Copy>(ui: &mut Ui, id: &str, options: &[(T, &str)], selection: &mut T) -> Response {
    let font = theme::body(13.0);
    let widths: Vec<f32> = options.iter().map(|(_, l)| ui.painter().layout_no_wrap((*l).to_owned(), font.clone(), Color32::WHITE).size().x + 26.0).collect();
    let width = widths.iter().copied().fold(0.0, f32::max) * options.len() as f32 + 4.0;
    let (rect, response) = ui.allocate_exact_size(vec2(width, 24.0), Sense::hover());
    glass::place(ui.scope_id().with(id), rect, 7.0, Tint::Button, 1);
    let inner = rect.shrink(2.0);
    let w = inner.width() / options.len() as f32;
    for (i, (value, label)) in options.iter().enumerate() {
        let r = Rect::from_min_size(pos2(inner.min.x + w * i as f32, inner.min.y), vec2(w, inner.height()));
        let segment = ui.interact(r, ui.scope_id().with((id, i)), Sense::click());
        let selected = *value == *selection;
        if selected {
            glass::place(segment.id, r, 6.0, Tint::Selected, 2);
        }
        if segment.clicked() {
            *selection = *value;
        }
        let color = if selected { Color32::BLACK } else { Color32::WHITE };
        let galley = ui.painter().layout_no_wrap((*label).to_owned(), font.clone(), color);
        ui.painter().galley(r.center() - galley.size() / 2.0, galley, color);
    }
    response
}

/// A sidebar row (`Label` in a `List(.sidebar)`): light glass when selected.
pub fn sidebar_item(ui: &mut Ui, icons: &mut Icons, icon_name: &str, title: &str, selected: bool) -> Response {
    let (rect, response) = ui.allocate_exact_size(vec2(ui.available_width(), 32.0), Sense::click());
    if selected {
        glass::place(response.id, rect, 8.0, Tint::Selected, 1);
    } else if response.hovered() {
        ui.painter().rect_filled(rect, 8.0, Color32::from_white_alpha(12));
    }
    icons.paint(ui, icon_name, Rect::from_center_size(pos2(rect.min.x + 19.0, rect.center().y), Vec2::splat(16.0)), Color32::WHITE);
    let galley = ui.painter().layout_no_wrap(title.to_owned(), theme::title(14.0), Color32::WHITE);
    ui.painter().galley(pos2(rect.min.x + 36.0, rect.center().y - galley.size().y / 2.0), galley, Color32::WHITE);
    response
}

/// `.pickerStyle(.menu)`: a compact button showing the choice; the menu is egui's popup.
pub fn menu_picker(ui: &mut Ui, icons: &mut Icons, id: &str, icon_name: Option<&str>, current: &str, options: &[(String, String)], mut pick: impl FnMut(&str)) {
    let font = theme::body(13.0);
    let galley = ui.painter().layout_no_wrap(current.to_owned(), font, Color32::WHITE);
    let lead = if icon_name.is_some() { 18.0 } else { 0.0 };
    let width = (galley.size().x + lead + 40.0).max(if icon_name.is_some() { 0.0 } else { 64.0 }).min(ui.available_width());
    let (rect, response) = ui.allocate_exact_size(vec2(width, 24.0), Sense::click());
    glass::place(response.id, rect, 6.0, Tint::Button, 1);
    if let Some(name) = icon_name {
        icons.paint(ui, name, Rect::from_center_size(pos2(rect.min.x + 15.0, rect.center().y), Vec2::splat(14.0)), Color32::WHITE);
    }
    let text = Rect::from_min_max(pos2(rect.min.x + 8.0 + lead, rect.min.y), pos2(rect.max.x - 24.0, rect.max.y));
    ui.painter().with_clip_rect(text).galley(pos2(text.min.x, rect.center().y - galley.size().y / 2.0), galley, Color32::WHITE);
    icons.paint(ui, "caret-up-down", Rect::from_center_size(pos2(rect.max.x - 13.0, rect.center().y), Vec2::splat(12.0)), Color32::WHITE);
    egui::Popup::menu(&response).id(ui.scope_id().with(id)).show(|ui| {
        ui.set_min_width(width.max(180.0));
        for (key, title) in options {
            if ui.selectable_label(title == current, title).clicked() {
                pick(key);
            }
        }
    });
}

/// A status row in the sidebar's BACKEND section: a check when present.
pub fn backend_row(ui: &mut Ui, icons: &mut Icons, icon_name: &str, title: &str, present: bool) {
    let (rect, _) = ui.allocate_exact_size(vec2(ui.available_width(), 33.0), Sense::hover());
    icons.paint(ui, icon_name, Rect::from_center_size(pos2(rect.min.x + 19.0, rect.center().y), Vec2::splat(15.0)), Color32::WHITE);
    let galley = ui.painter().layout_no_wrap(title.to_owned(), theme::body(12.0), Color32::WHITE);
    ui.painter().galley(pos2(rect.min.x + 36.0, rect.center().y - galley.size().y / 2.0), galley, Color32::WHITE);
    let (name, color) = if present { ("check-circle", Color32::WHITE) } else { ("circle-dashed", Color32::from_white_alpha(90)) };
    icons.paint(ui, name, Rect::from_center_size(pos2(rect.max.x - 14.0, rect.center().y), Vec2::splat(15.0)), color);
}

/// A macOS switch.
pub fn toggle(ui: &mut Ui, on: bool) -> Response {
    let (rect, response) = ui.allocate_exact_size(vec2(38.0, 22.0), Sense::click());
    let t = ui.ctx().animate_bool(response.id, on);
    let track = Color32::from_white_alpha(46).lerp_to_gamma(Color32::from_rgb(10, 132, 255), t);
    ui.painter().rect_filled(rect, 11.0, track);
    let knob = pos2(egui::lerp(rect.min.x + 11.0..=rect.max.x - 11.0, t), rect.center().y);
    ui.painter().circle_filled(knob + vec2(0.0, 0.5), 9.5, Color32::from_black_alpha(50));
    ui.painter().circle_filled(knob, 9.0, Color32::WHITE);
    response
}

/// A macOS checkbox with its label.
pub fn checkbox(ui: &mut Ui, title: &str, on: bool) -> Response {
    let galley = ui.painter().layout_no_wrap(title.to_owned(), theme::body(11.0), Color32::WHITE);
    let (rect, response) = ui.allocate_exact_size(vec2(14.0 + 6.0 + galley.size().x, 16.0), Sense::click());
    let boxr = Rect::from_center_size(pos2(rect.min.x + 7.0, rect.center().y), Vec2::splat(14.0));
    if on {
        ui.painter().rect_filled(boxr, 3.5, Color32::from_rgb(10, 132, 255));
        let p = |x: f32, y: f32| pos2(boxr.min.x + x, boxr.min.y + y);
        ui.painter().line(vec![p(3.5, 7.2), p(6.0, 9.8), p(10.5, 4.2)], Stroke::new(1.8, Color32::WHITE));
    } else {
        ui.painter().rect(boxr, 3.5, Color32::from_black_alpha(60), Stroke::new(1.0, Color32::from_white_alpha(110)), egui::StrokeKind::Inside);
    }
    ui.painter().galley(pos2(boxr.max.x + 6.0, rect.center().y - galley.size().y / 2.0), galley, Color32::WHITE);
    response
}

/// The capsule search field from the Mods and Servers headers.
pub fn search(ui: &mut Ui, icons: &mut Icons, id: &str, hint: &str, text: &mut String, width: f32) -> Response {
    let (rect, _) = ui.allocate_exact_size(vec2(width, 32.0), Sense::hover());
    glass::place(ui.make_persistent_id((id, "field")), rect, 99.0, Tint::Medium, 1);
    icons.paint(ui, "magnifying-glass", Rect::from_center_size(pos2(rect.min.x + 20.0, rect.center().y), Vec2::splat(14.0)), theme::FAINT);
    let inner = Rect::from_min_max(pos2(rect.min.x + 34.0, rect.min.y + 6.0), pos2(rect.max.x - 12.0, rect.max.y - 6.0));
    ui.put(
        inner,
        egui::TextEdit::singleline(text)
            .id_salt(id)
            .frame(egui::Frame::NONE)
            .hint_text(egui::RichText::new(hint).color(theme::FAINT))
            .font(theme::body(13.0))
            .text_color(theme::PRIMARY),
    )
}

/// A linear progress bar; `None` sweeps (unknown size).
pub fn progress(ui: &mut Ui, fraction: Option<f64>) {
    let (rect, _) = ui.allocate_exact_size(vec2(ui.available_width(), 5.0), Sense::hover());
    let painter = ui.painter();
    painter.rect_filled(rect, 2.5, Color32::from_white_alpha(30));
    let fill = match fraction {
        Some(f) => Rect::from_min_size(rect.min, vec2(rect.width() * f.clamp(0.0, 1.0) as f32, rect.height())),
        None => {
            let t = (ui.input(|i| i.time) * 0.8).fract() as f32;
            ui.ctx().request_repaint();
            let w = rect.width() * 0.3;
            Rect::from_min_size(pos2(rect.min.x + (rect.width() + w) * t - w, rect.min.y), vec2(w, rect.height())).intersect(rect)
        }
    };
    painter.rect_filled(fill, 2.5, theme::ACCENT32);
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum WindowButton { Close, Minimize, Zoom }

/// The traffic lights; glyphs appear while the pointer is over the group.
pub fn traffic_lights(ui: &mut Ui, origin: Pos2, focused: bool) -> Option<WindowButton> {
    let buttons = [
        (WindowButton::Close, Color32::from_rgb(255, 95, 87), Color32::from_rgb(226, 63, 56)),
        (WindowButton::Minimize, Color32::from_rgb(254, 188, 46), Color32::from_rgb(222, 161, 30)),
        (WindowButton::Zoom, Color32::from_rgb(40, 200, 64), Color32::from_rgb(29, 170, 49)),
    ];
    let group = Rect::from_min_max(origin - vec2(8.0, 8.0), origin + vec2(54.0, 8.0));
    let hovered = ui.rect_contains_pointer(group);
    let mut clicked = None;
    for (i, (kind, fill, rim)) in buttons.into_iter().enumerate() {
        let c = origin + vec2(23.0 * i as f32, 0.0);
        let r = ui.interact(Rect::from_center_size(c, Vec2::splat(14.0)), ui.scope_id().with(("traffic", i)), Sense::click());
        let (fill, rim) = if focused || hovered { (fill, rim) } else { (Color32::from_white_alpha(40), Color32::from_white_alpha(20)) };
        ui.painter().circle(c, 6.5, fill, Stroke::new(0.5, rim));
        if hovered {
            let ink = Color32::from_black_alpha(150);
            let s = Stroke::new(1.2, ink);
            match kind {
                WindowButton::Close => {
                    ui.painter().line_segment([c + vec2(-2.8, -2.8), c + vec2(2.8, 2.8)], s);
                    ui.painter().line_segment([c + vec2(-2.8, 2.8), c + vec2(2.8, -2.8)], s);
                }
                WindowButton::Minimize => { ui.painter().line_segment([c + vec2(-3.5, 0.0), c + vec2(3.5, 0.0)], s); }
                WindowButton::Zoom => {
                    ui.painter().add(egui::Shape::convex_polygon(vec![c + vec2(-3.4, -1.2), c + vec2(-3.4, 3.4), c + vec2(1.2, 3.4)], ink, Stroke::NONE));
                    ui.painter().add(egui::Shape::convex_polygon(vec![c + vec2(3.4, 1.2), c + vec2(3.4, -3.4), c + vec2(-1.2, -3.4)], ink, Stroke::NONE));
                }
            }
        }
        if r.clicked() {
            clicked = Some(kind);
        }
    }
    clicked
}

/// The window's 1 pt light rim (macOS draws it over the content).
pub fn window_rim(ui: &Ui, rect: Rect) {
    ui.painter().rect_stroke(rect.shrink(0.5), CornerRadius::same(crate::backdrop::CORNER as u8), Stroke::new(1.0, Color32::from_white_alpha(38)), egui::StrokeKind::Inside);
}
