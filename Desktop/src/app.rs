//! The window: a floating glass sidebar and the selected page, after the
//! macOS `ContentView` / `PlayView`.

use crate::theme::{self, Tint};
use crate::widgets::{self, Button, Icons};
use crate::glass;
use egui::{Align, Layout, RichText, Ui};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Section { Play, Mods, Servers, Console, Settings }

impl Section {
    pub const ALL: [Section; 5] = [Section::Play, Section::Mods, Section::Servers, Section::Console, Section::Settings];
    fn title(self) -> &'static str {
        match self { Section::Play => "Play", Section::Mods => "Mods", Section::Servers => "Servers", Section::Console => "Console", Section::Settings => "Settings" }
    }
    fn icon(self) -> &'static str {
        match self { Section::Play => "play", Section::Mods => "puzzle", Section::Servers => "server", Section::Console => "terminal", Section::Settings => "settings" }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Mode { Northstar, Vanilla }

pub struct App {
    pub icons: Icons,
    pub section: Section,
    pub mode: Mode,
    pub logo: Option<egui::TextureHandle>,
    resources: std::path::PathBuf,
}

impl App {
    pub fn new(resources: std::path::PathBuf) -> Self {
        Self { icons: Icons::new(resources.clone()), section: Section::Play, mode: Mode::Northstar, logo: None, resources }
    }

    fn logo(&mut self, ctx: &egui::Context) -> Option<egui::TextureHandle> {
        if self.logo.is_none() {
            let image = image::open(self.resources.join("icon.png")).ok()?.to_rgba8();
            let size = [image.width() as usize, image.height() as usize];
            self.logo = Some(ctx.load_texture("logo", egui::ColorImage::from_rgba_unmultiplied(size, image.as_raw()), egui::TextureOptions::LINEAR));
        }
        self.logo.clone()
    }

    pub fn ui(&mut self, ui: &mut Ui) {
        egui::Panel::left("sidebar").exact_size(250.0).resizable(false).frame(egui::Frame::NONE).show(ui, |ui| {
            self.sidebar(ui);
        });
        egui::CentralPanel::default().frame(egui::Frame::NONE).show(ui, |ui| {
            egui::ScrollArea::vertical().show(ui, |ui| {
                ui.add_space(24.0);
                ui.horizontal(|ui| {
                    let width = (ui.available_width() - 48.0).min(900.0);
                    ui.add_space(((ui.available_width() - width) / 2.0).max(24.0));
                    ui.vertical(|ui| {
                        ui.set_width(width);
                        ui.spacing_mut().item_spacing.y = 18.0;
                        match self.section {
                            Section::Play => self.play(ui),
                            other => {
                                widgets::card(ui, "todo", Tint::Regular, 22.0, 20.0, |ui| {
                                    widgets::stencil(ui, other.title(), 11.0, theme::SECONDARY);
                                });
                            }
                        }
                    });
                });
                ui.add_space(24.0);
            });
        });
    }

    fn sidebar(&mut self, ui: &mut Ui) {
        let panel = ui.max_rect().shrink(10.0);
        glass::place(egui::Id::new("sidebar-glass"), panel, 24.0, Tint::None, 0);
        let mut child = ui.new_child(egui::UiBuilder::new().max_rect(panel.shrink(16.0)));
        let ui = &mut child;
        ui.horizontal(|ui| {
            if let Some(logo) = self.logo(ui.ctx()) {
                ui.add(egui::Image::new(&logo).fit_to_exact_size(egui::vec2(30.0, 30.0)));
            }
            ui.label(widgets::tracked("DRACONIS", theme::hero(18.0), theme::PRIMARY, 2.0));
        });
        ui.add_space(14.0);
        for section in Section::ALL {
            if widgets::sidebar_item(ui, &mut self.icons, section.icon(), section.title(), self.section == section).clicked() {
                self.section = section;
            }
            ui.add_space(2.0);
        }
        ui.with_layout(Layout::bottom_up(Align::Min), |ui| {
            Button::new("Rescan").icon("refresh-cw").size(13.0).show(ui, &mut self.icons);
            ui.label(RichText::new("Steam · Titanfall2").font(theme::body(14.0)).color(theme::PRIMARY));
            widgets::stencil(ui, "Game", 10.0, theme::SECONDARY);
        });
    }

    fn play(&mut self, ui: &mut Ui) {
        let logo = self.logo(ui.ctx());
        widgets::card(ui, "hero", Tint::Subtle, 26.0, 28.0, |ui| {
            ui.horizontal(|ui| {
                ui.spacing_mut().item_spacing.x = 18.0;
                if let Some(logo) = &logo {
                    ui.add(egui::Image::new(logo).fit_to_exact_size(egui::vec2(96.0, 96.0)));
                }
                ui.vertical(|ui| {
                    ui.spacing_mut().item_spacing.y = 6.0;
                    ui.label(widgets::tracked("DRACONIS", theme::hero(46.0), theme::PRIMARY, 8.0));
                    ui.label(RichText::new("Titanfall 2 + Northstar launcher for Linux.").font(theme::title(16.0)).color(theme::SECONDARY));
                    ui.label(RichText::new("Steam · Titanfall2").font(theme::body(12.0)).color(theme::TERTIARY));
                });
            });
        });

        ui.columns(3, |cols| {
            widgets::status_pill(&mut cols[0], &mut self.icons, "Titanfall 2", "Installed", "gamepad-2", true);
            widgets::status_pill(&mut cols[1], &mut self.icons, "Launcher", "Steam", "shield-check", true);
            widgets::status_pill(&mut cols[2], &mut self.icons, "Northstar", "v1.31.16", "zap", true);
        });

        let icons = &mut self.icons;
        let mode = &mut self.mode;
        widgets::card(ui, "actions", Tint::Medium, 22.0, 22.0, |ui| {
            ui.spacing_mut().item_spacing.y = 14.0;
            widgets::segmented(ui, "mode", &[(Mode::Northstar, "Northstar"), (Mode::Vanilla, "Vanilla")], mode);
            let title = if *mode == Mode::Northstar { "Launch Northstar" } else { "Launch Vanilla" };
            Button::new(title).icon("play").prominent().full_width().size(18.0).show(ui, icons);
            ui.label(RichText::new("Modded Titanfall 2 with Northstar's community servers.").font(theme::body(13.0)).color(theme::FAINT));
            ui.horizontal(|ui| {
                Button::new("Uninstall NS").icon("trash").size(13.0).show(ui, icons);
            });
        });

        widgets::card(ui, "vr", Tint::Regular, 24.0, 22.0, |ui| {
            ui.spacing_mut().item_spacing.y = 12.0;
            ui.horizontal(|ui| {
                widgets::icon(ui, icons, "glasses", false, 16.0);
                widgets::stencil(ui, "Virtual reality", 11.0, theme::SECONDARY);
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    ui.label(RichText::new("v1.0.33").font(theme::body(13.0)).color(theme::FAINT));
                });
            });
            ui.horizontal(|ui| {
                widgets::icon(ui, icons, "circle-check", false, 16.0);
                ui.label(RichText::new("SteamVR is running.").font(theme::body(14.0)).color(theme::SECONDARY));
            });
            ui.horizontal(|ui| {
                Button::new("Launch in VR").icon("play").prominent().show(ui, icons);
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    Button::new("Remove VR").icon("trash").size(13.0).show(ui, icons);
                });
            });
            ui.label(RichText::new("1. Meta Quest 3: open Steam Link on the headset and connect to this PC.\n2. Click Launch in VR. The EA app opens first, then the game appears in the headset.")
                .font(theme::body(13.0)).color(theme::FAINT));
        });
    }
}
