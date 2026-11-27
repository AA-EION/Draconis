//! The window: a floating glass sidebar and the selected page, after the
//! macOS `ContentView`, `PlayView`, `ModsView`, `ServersView`, `ConsoleView`
//! and `SettingsView`. State comes from the engine; buttons send commands.

use crate::engine::{Engine, Remote, Sender, State};
use crate::glass;
use crate::theme::{self, Tint};
use crate::widgets::{self, Button, Icons};
use egui::{Align, Layout, RichText, Ui};
use serde_json::json;

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

/// Thunderstore rows laid out at once (each frame lays out every row).
const PACKAGE_ROWS: usize = 60;

pub struct App {
    pub icons: Icons,
    pub section: Section,
    pub mode: Mode,
    engine: Engine,
    logo: Option<egui::TextureHandle>,
    resources: std::path::PathBuf,
    mod_query: String,
    server_query: String,
    asked_mods: bool,
    asked_servers: bool,
    routed: bool,
}

fn text(s: &str, size: f32, color: egui::Color32) -> RichText {
    RichText::new(s).font(theme::body(size)).color(color)
}

impl App {
    pub fn new(resources: std::path::PathBuf, engine: Engine) -> Self {
        Self {
            icons: Icons::new(resources.clone()),
            section: Section::Play,
            mode: Mode::Northstar,
            engine,
            logo: None,
            resources,
            mod_query: String::new(),
            server_query: String::new(),
            asked_mods: false,
            asked_servers: false,
            routed: false,
        }
    }

    fn logo(&mut self, ctx: &egui::Context) -> Option<egui::TextureHandle> {
        if self.logo.is_none() {
            let image = image::open(self.resources.join("icon.png")).ok()?.to_rgba8();
            let size = [image.width() as usize, image.height() as usize];
            self.logo = Some(ctx.load_texture("logo", egui::ColorImage::from_rgba_unmultiplied(size, image.as_raw()), egui::TextureOptions::LINEAR));
        }
        self.logo.clone()
    }

    fn sender(&self) -> Sender {
        self.engine.sender.clone()
    }

    pub fn ui(&mut self, ui: &mut Ui) {
        let remote = self.engine.remote.clone();
        let remote = remote.lock().unwrap();
        if let Some(state) = &remote.state {
            if !self.routed {
                self.routed = true;
                if state.games.is_empty() {
                    self.section = Section::Settings;
                }
            }
        }
        egui::Panel::left("sidebar").exact_size(250.0).resizable(false).show_separator_line(false).frame(egui::Frame::NONE).show(ui, |ui| {
            self.sidebar(ui, remote.state.as_ref());
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
                        match &remote.state {
                            None => self.starting(ui, &remote),
                            Some(state) => {
                                self.banners(ui, state);
                                match self.section {
                                    Section::Play => self.play(ui, state),
                                    Section::Mods => self.mods(ui, state, &remote),
                                    Section::Servers => self.servers(ui, state, &remote),
                                    Section::Console => self.console(ui, &remote),
                                    Section::Settings => self.settings(ui, state),
                                }
                            }
                        }
                    });
                });
                ui.add_space(24.0);
            });
        });
    }

    fn starting(&mut self, ui: &mut Ui, remote: &Remote) {
        widgets::card(ui, "starting", Tint::Regular, 22.0, 22.0, |ui| match &remote.gone {
            Some(message) => {
                ui.label(text(message, 14.0, theme::ERROR));
            }
            None => {
                ui.horizontal(|ui| {
                    ui.add(egui::Spinner::new());
                    ui.label(text("Starting…", 14.0, theme::SECONDARY));
                });
            }
        });
    }

    fn sidebar(&mut self, ui: &mut Ui, state: Option<&State>) {
        let panel = ui.max_rect().shrink(10.0);
        glass::place(ui.make_persistent_id("sidebar-glass"), panel, 24.0, Tint::None, 0);
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
        let sender = self.sender();
        ui.with_layout(Layout::bottom_up(Align::Min), |ui| {
            let scanning = state.is_some_and(|s| s.scanning);
            if Button::new(if scanning { "Scanning…" } else { "Rescan" }).icon("refresh-cw").size(13.0).enabled(!scanning).show(ui, &mut self.icons).clicked() {
                sender.cmd("rescan");
            }
            if let Some(state) = state {
                if state.games.is_empty() {
                    ui.label(text("No Titanfall 2 found", 13.0, theme::FAINT));
                } else {
                    let current = state.selected().map(|g| format!("{} · {}", g.name, g.folder)).unwrap_or_default();
                    egui::ComboBox::from_id_salt("game").selected_text(current).width(ui.available_width()).show_ui(ui, |ui| {
                        for game in &state.games {
                            let label = format!("{} · {}", game.name, game.folder);
                            if ui.selectable_label(state.selected().is_some_and(|g| g.id == game.id), label).clicked() {
                                sender.send(json!({ "cmd": "selectGame", "id": game.id }));
                            }
                        }
                    });
                }
            }
            widgets::stencil(ui, "Game", 10.0, theme::SECONDARY);
        });
    }

    fn banners(&mut self, ui: &mut Ui, state: &State) {
        let sender = self.sender();
        if let Some(version) = &state.newer_version {
            let page = state.releases_page.clone();
            widgets::card(ui, "update", Tint::Medium, 18.0, 16.0, |ui| {
                ui.horizontal(|ui| {
                    ui.label(text(&format!("Draconis {version} is available."), 14.0, theme::PRIMARY));
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        if Button::new("Download").icon("download").size(13.0).show(ui, &mut self.icons).clicked() {
                            let _ = open::that(&page);
                        }
                    });
                });
            });
        }
        if let Some(error) = &state.error {
            widgets::card(ui, "error", Tint::Error, 14.0, 14.0, |ui| {
                ui.horizontal(|ui| {
                    ui.add(egui::Label::new(text(error, 14.0, theme::PRIMARY)).wrap());
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        if Button::new("Dismiss").icon("x").size(13.0).show(ui, &mut self.icons).clicked() {
                            sender.cmd("dismissError");
                        }
                    });
                });
            });
        }
        if let (Some(status), false) = (&state.status, state.launching) {
            ui.label(text(status, 14.0, theme::SECONDARY));
        }
    }

    // MARK: Play

    fn play(&mut self, ui: &mut Ui, state: &State) {
        let logo = self.logo(ui.ctx());
        let game = state.selected().cloned();
        widgets::card(ui, "hero", Tint::Subtle, 26.0, 28.0, |ui| {
            ui.horizontal(|ui| {
                ui.spacing_mut().item_spacing.x = 18.0;
                if let Some(logo) = &logo {
                    ui.add(egui::Image::new(logo).fit_to_exact_size(egui::vec2(96.0, 96.0)));
                }
                ui.vertical(|ui| {
                    ui.spacing_mut().item_spacing.y = 6.0;
                    ui.label(widgets::tracked("DRACONIS", theme::hero(46.0), theme::PRIMARY, 8.0));
                    ui.label(RichText::new(format!("Titanfall 2 + Northstar launcher for {}.", state.os)).font(theme::title(16.0)).color(theme::SECONDARY));
                    if let Some(game) = &game {
                        ui.label(text(&format!("{} · {}", game.name, game.folder), 12.0, theme::TERTIARY));
                    }
                });
            });
        });
        let Some(game) = game else {
            self.setup(ui, state);
            return;
        };
        let launcher_ready = !state.needs_runner || state.selected_runner.is_some();
        let launcher = match game.kind.as_str() {
            "steam" => "Steam".to_owned(),
            "prefix" => state.runners.iter().find(|r| Some(&r.id) == state.selected_runner.as_ref()).map(|r| r.title.clone()).unwrap_or_else(|| "No runner".into()),
            _ => game.name.clone(),
        };
        let northstar = game.northstar_version.as_ref().map(|v| format!("v{v}")).unwrap_or_else(|| "Missing".into());
        ui.columns(3, |cols| {
            widgets::status_pill(&mut cols[0], &mut self.icons, "Titanfall 2", "Installed", "gamepad-2", true);
            widgets::status_pill(&mut cols[1], &mut self.icons, "Launcher", &launcher, "shield-check", launcher_ready);
            widgets::status_pill(&mut cols[2], &mut self.icons, "Northstar", &northstar, "zap", game.has_northstar);
        });
        self.actions(ui, state, &game);
        if state.launching || state.game_running {
            widgets::card(ui, "launching", Tint::Medium, 18.0, 16.0, |ui| {
                ui.horizontal(|ui| {
                    if state.launching { ui.add(egui::Spinner::new()); } else { widgets::icon(ui, &mut self.icons, "circle-check", false, 20.0); }
                    ui.vertical(|ui| {
                        widgets::stencil(ui, if state.launching { "Launching" } else { "Running" }, 11.0, theme::SECONDARY);
                        let message = if state.launching { state.status.clone().unwrap_or_else(|| "Starting…".into()) } else { "Titanfall 2 is running. Launch is available again once it closes.".into() };
                        ui.label(text(&message, 14.0, theme::SECONDARY));
                    });
                });
            });
        }
        self.vr(ui, state);
        if state.northstar_busy || state.tool_busy.is_some() {
            let progress = state.northstar_progress.as_ref().or(state.tool_progress.as_ref());
            widgets::card(ui, "progress", Tint::Regular, 18.0, 16.0, |ui| {
                widgets::stencil(ui, state.tool_busy.as_deref().unwrap_or("Northstar"), 11.0, theme::SECONDARY);
                if let Some(detail) = progress.and_then(|p| p.detail.as_ref()) {
                    ui.label(text(detail, 13.0, theme::SECONDARY));
                }
                widgets::progress(ui, progress.map(|p| p.fraction).filter(|f| *f >= 0.0));
            });
        }
        if state.needs_runner && state.selected_runner.is_none() {
            widgets::card(ui, "runner-notice", Tint::Medium, 18.0, 16.0, |ui| {
                widgets::stencil(ui, "Runner", 11.0, theme::SECONDARY);
                ui.label(text("This copy runs through Wine or Proton. Pick or download one in Settings.", 14.0, theme::SECONDARY));
            });
        }
    }

    fn setup(&mut self, ui: &mut Ui, state: &State) {
        let sender = self.sender();
        let mut open_settings = false;
        widgets::card(ui, "setup", Tint::Strong, 24.0, 22.0, |ui| {
            ui.spacing_mut().item_spacing.y = 12.0;
            widgets::stencil(ui, "Set up Titanfall 2", 11.0, theme::SECONDARY);
            ui.label(text("Draconis didn't find Titanfall 2. Install it with Steam, or open Settings to pick its folder or create a Wine prefix with the EA app.", 14.0, theme::SECONDARY));
            ui.horizontal(|ui| {
                open_settings = Button::new("Open Settings").icon("settings").prominent().show(ui, &mut self.icons).clicked();
                if Button::new(if state.scanning { "Scanning…" } else { "Rescan" }).icon("refresh-cw").show(ui, &mut self.icons).clicked() {
                    sender.cmd("rescan");
                }
            });
        });
        if open_settings {
            self.section = Section::Settings;
        }
    }

    fn actions(&mut self, ui: &mut Ui, state: &State, game: &crate::engine::Game) {
        let sender = self.sender();
        let icons = &mut self.icons;
        let mode = &mut self.mode;
        widgets::card(ui, "actions", Tint::Medium, 22.0, 22.0, |ui| {
            ui.spacing_mut().item_spacing.y = 14.0;
            widgets::segmented(ui, "mode", &[(Mode::Northstar, "Northstar"), (Mode::Vanilla, "Vanilla")], mode);
            let title = if state.game_running { "Running" } else if state.launching { "Launching…" } else if *mode == Mode::Northstar { "Launch Northstar" } else { "Launch" };
            let enabled = !state.launching && !state.game_running && !(*mode == Mode::Northstar && !game.has_northstar);
            if Button::new(title).icon("play").prominent().full_width().size(18.0).enabled(enabled).show(ui, icons).clicked() && enabled {
                sender.send(json!({ "cmd": "launch", "mode": if *mode == Mode::Vanilla { "vanilla" } else { "northstar" } }));
            }
            let caption = match (*mode, game.has_northstar) {
                (Mode::Northstar, true) => "Modded Titanfall 2 with Northstar's community servers.",
                (Mode::Northstar, false) => "Install Northstar to play on community servers.",
                (Mode::Vanilla, true) => "Northstar's vanilla-compatible mode: joins official servers.",
                (Mode::Vanilla, false) => "The unmodified game on official servers.",
            };
            ui.label(text(caption, 13.0, theme::FAINT));
            ui.horizontal(|ui| {
                let busy = state.northstar_busy;
                if !game.has_northstar {
                    if Button::new("Install Northstar").icon("download").size(13.0).enabled(!busy).show(ui, icons).clicked() && !busy {
                        sender.cmd("installNorthstar");
                    }
                } else {
                    if let (false, Some(latest)) = (state.northstar_up_to_date, &state.latest_northstar) {
                        if Button::new(&format!("Update to {latest}")).icon("refresh-cw").size(13.0).enabled(!busy).show(ui, icons).clicked() && !busy {
                            sender.cmd("installNorthstar");
                        }
                    }
                    if Button::new("Uninstall NS").icon("trash").size(13.0).enabled(!busy).show(ui, icons).clicked() && !busy {
                        sender.cmd("uninstallNorthstar");
                    }
                }
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    if widgets::toggle(ui, "auto-update", state.auto_update_northstar).clicked() {
                        sender.send(json!({ "cmd": "setAutoUpdate", "enabled": !state.auto_update_northstar }));
                    }
                    ui.label(text("Auto-update", 14.0, theme::PRIMARY));
                });
            });
        });
    }

    fn vr(&mut self, ui: &mut Ui, state: &State) {
        let sender = self.sender();
        let vr = &state.vr;
        let icons = &mut self.icons;
        let windows = state.os == "Windows";
        widgets::card(ui, "vr", Tint::Regular, 24.0, 22.0, |ui| {
            ui.spacing_mut().item_spacing.y = 12.0;
            ui.horizontal(|ui| {
                widgets::icon(ui, icons, "glasses", false, 16.0);
                widgets::stencil(ui, "Virtual reality", 11.0, theme::SECONDARY);
                if let Some(version) = &vr.installed_version {
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        ui.label(text(&format!("v{version}"), 13.0, theme::FAINT));
                    });
                }
            });
            if !vr.supported {
                ui.label(text("On Linux, VR works with the Steam copy of Titanfall 2 for now.", 14.0, theme::SECONDARY));
            } else if vr.busy {
                ui.horizontal(|ui| {
                    ui.add(egui::Spinner::new());
                    ui.label(text(vr.phase.as_deref().unwrap_or("Working…"), 14.0, theme::SECONDARY));
                });
                if let Some(progress) = vr.progress {
                    widgets::progress(ui, Some(progress));
                }
            } else if vr.installed_version.is_none() {
                ui.label(text("CircuitLord's Titanfall 2 VR mod plays the campaign in VR through OpenXR. It installs into its own TF2VR profile, so the normal game and your Northstar stay as they are. About 180 MB to download, plus 3 GB of game files built on your PC.", 14.0, theme::SECONDARY));
                if Button::new("Install VR mod").icon("download").prominent().show(ui, icons).clicked() {
                    sender.cmd("installVR");
                }
            } else {
                ui.horizontal(|ui| {
                    let running = vr.steam_vr_running || vr.other_runtime.is_some();
                    widgets::icon(ui, icons, if running { "circle-check" } else { "circle-alert" }, false, 16.0);
                    let runtime = if !vr.checked { "Checking for a VR runtime…".to_owned() }
                        else if vr.steam_vr_running { "SteamVR is running.".into() }
                        else if let Some(other) = &vr.other_runtime { format!("{other} is running.") }
                        else if let Some(active) = &vr.active_runtime { format!("No VR runtime is running. The active OpenXR runtime is {active}.") }
                        else { "No VR runtime is running.".into() };
                    ui.label(text(&runtime, 14.0, theme::SECONDARY));
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        if Button::new("Check again").icon("refresh-cw").size(13.0).show(ui, icons).clicked() {
                            sender.cmd("refreshVR");
                        }
                        if vr.steam_vr_installed && !vr.steam_vr_running && Button::new("Start SteamVR").icon("play").size(13.0).show(ui, icons).clicked() {
                            sender.cmd("startSteamVR");
                        }
                    });
                });
                ui.horizontal(|ui| {
                    let title = if state.launching { "Launching…" } else if state.game_running { "Running" } else { "Launch in VR" };
                    let enabled = !state.launching && !state.game_running;
                    if Button::new(title).icon("play").prominent().enabled(enabled).show(ui, icons).clicked() && enabled {
                        sender.cmd("launchVR");
                    }
                    if let (true, Some(latest)) = (vr.update_available, &vr.latest_version) {
                        if Button::new(&format!("Update to {latest}")).icon("refresh-cw").size(13.0).show(ui, icons).clicked() {
                            sender.cmd("installVR");
                        }
                    }
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        if Button::new("Remove VR").icon("trash").size(13.0).show(ui, icons).clicked() {
                            sender.cmd("uninstallVR");
                        }
                    });
                });
            }
            if let Some(error) = &vr.error {
                ui.label(text(error, 14.0, theme::ERROR));
            }
            if vr.supported && state.launching && vr.installed_version.is_some() {
                if let Some(status) = &state.status {
                    ui.horizontal(|ui| {
                        ui.add(egui::Spinner::new());
                        ui.label(text(status, 14.0, theme::SECONDARY));
                    });
                }
            }
            let runtime = if windows {
                "Meta Quest 3: open Steam Link on the headset and connect to this PC. Quest Link, Air Link and Virtual Desktop work too: start yours first."
            } else {
                "Meta Quest 3: open Steam Link on the headset and connect to this PC. WiVRn (Quest, Pico) and Monado work too: start yours first."
            };
            let help = if vr.installed_version.is_some() {
                format!("1. {runtime} If no VR runtime is running, Launch in VR starts SteamVR for you.\n2. Click Launch in VR. The EA app opens first (sign in if it asks), then the game appears in the headset.\nSteam's own Play button starts the normal, flat game, not VR.")
            } else {
                runtime.to_owned()
            };
            ui.label(text(&help, 13.0, theme::FAINT));
        });
    }

    // MARK: Mods

    fn mods(&mut self, ui: &mut Ui, state: &State, remote: &Remote) {
        let sender = self.sender();
        if !self.asked_mods && remote.packages.is_empty() && !state.mods_loading {
            self.asked_mods = true;
            sender.cmd("refreshMods");
        }
        let icons = &mut self.icons;
        widgets::card(ui, "installed-mods", Tint::Regular, 22.0, 20.0, |ui| {
            ui.spacing_mut().item_spacing.y = 10.0;
            ui.horizontal(|ui| {
                widgets::stencil(ui, "Installed mods", 11.0, theme::SECONDARY);
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    if Button::new("Install from zip…").icon("folder-plus").size(13.0).show(ui, icons).clicked() {
                        let sender = sender.clone();
                        std::thread::spawn(move || {
                            if let Some(path) = rfd::FileDialog::new().set_title("Install a mod zip").add_filter("Zip", &["zip"]).pick_file() {
                                sender.send(json!({ "cmd": "installModZip", "path": path }));
                            }
                        });
                    }
                });
            });
            if state.installed_mods.is_empty() {
                let empty = if state.selected().is_none() { "Pick a Titanfall 2 install first." } else { "No mods installed yet." };
                ui.label(text(empty, 14.0, theme::FAINT));
            }
            for m in &state.installed_mods {
                ui.horizontal(|ui| {
                    ui.vertical(|ui| {
                        ui.label(RichText::new(&m.name).font(theme::body(14.0)).strong().color(theme::PRIMARY));
                        ui.label(text(&m.version, 13.0, theme::FAINT));
                    });
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        if Button::new("Remove").icon("trash").size(13.0).show(ui, icons).clicked() {
                            sender.send(json!({ "cmd": "uninstallMod", "id": m.id }));
                        }
                        if widgets::toggle(ui, &format!("mod-{}", m.id), m.enabled).clicked() {
                            sender.send(json!({ "cmd": "setModEnabled", "id": m.id, "enabled": !m.enabled }));
                        }
                    });
                });
            }
        });
        let query = &mut self.mod_query;
        widgets::card(ui, "thunderstore", Tint::Regular, 22.0, 20.0, |ui| {
            ui.spacing_mut().item_spacing.y = 10.0;
            ui.horizontal(|ui| {
                widgets::stencil(ui, "Thunderstore", 11.0, theme::SECONDARY);
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    if Button::new(if state.mods_loading { "Loading…" } else { "Refresh" }).icon("refresh-cw").size(13.0).show(ui, icons).clicked() {
                        sender.cmd("refreshMods");
                    }
                    widgets::search(ui, "mod-search", "Search mods…", query, 260.0);
                });
            });
            if state.mods_loading && remote.packages.is_empty() {
                ui.horizontal(|ui| {
                    ui.add(egui::Spinner::new());
                    ui.label(text("Loading the mod list…", 14.0, theme::SECONDARY));
                });
            }
            let q = query.trim().to_lowercase();
            let matches: Vec<_> = remote.packages.iter().filter(|p| q.is_empty() || p.name.to_lowercase().contains(&q) || p.owner.to_lowercase().contains(&q)).collect();
            if matches.len() > PACKAGE_ROWS {
                ui.label(text(&format!("Showing {PACKAGE_ROWS} of {} mods. Search to narrow it down.", matches.len()), 13.0, theme::FAINT));
            }
            for p in matches.into_iter().take(PACKAGE_ROWS) {
                ui.horizontal(|ui| {
                    let right = 110.0;
                    ui.allocate_ui(egui::vec2(ui.available_width() - right, 0.0), |ui| {
                        ui.vertical(|ui| {
                            ui.label(RichText::new(&p.name).font(theme::body(14.0)).strong().color(theme::PRIMARY));
                            ui.label(text(&format!("{} · {}", p.owner, p.version), 13.0, theme::FAINT));
                            if !p.description.is_empty() {
                                ui.add(egui::Label::new(text(&p.description, 13.0, theme::SECONDARY)).wrap());
                            }
                        });
                    });
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        if state.mod_busy.as_deref() == Some(p.full_name.as_str()) {
                            ui.add(egui::Spinner::new());
                        } else if state.installed_packages.contains(&p.full_name) {
                            widgets::stencil(ui, "Installed", 11.0, theme::SECONDARY);
                        } else {
                            let enabled = state.selected().is_some() && state.mod_busy.is_none();
                            if Button::new("Install").icon("download").size(13.0).enabled(enabled).show(ui, icons).clicked() && enabled {
                                sender.send(json!({ "cmd": "installMod", "id": p.full_name }));
                            }
                        }
                    });
                });
            }
        });
    }

    // MARK: Servers

    fn servers(&mut self, ui: &mut Ui, state: &State, remote: &Remote) {
        let sender = self.sender();
        if !self.asked_servers && remote.servers.is_empty() && !state.servers_loading {
            self.asked_servers = true;
            sender.cmd("refreshServers");
        }
        let q = self.server_query.trim().to_lowercase();
        let servers: Vec<_> = remote.servers.iter().filter(|s| {
            q.is_empty() || [&s.name, &s.description, &s.map, &s.playlist].iter().any(|f| f.to_lowercase().contains(&q))
        }).collect();
        ui.horizontal(|ui| {
            widgets::search(ui, "server-search", "Search servers, maps, playlists…", &mut self.server_query, 320.0);
            if Button::new(if state.servers_loading { "Loading…" } else { "Refresh" }).icon("refresh-cw").size(13.0).show(ui, &mut self.icons).clicked() {
                sender.cmd("refreshServers");
            }
            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                widgets::stencil(ui, &format!("{} servers", servers.len()), 11.0, theme::SECONDARY);
            });
        });
        if state.servers_loading && remote.servers.is_empty() {
            ui.horizontal(|ui| {
                ui.add(egui::Spinner::new());
                ui.label(text("Querying the master server…", 14.0, theme::SECONDARY));
            });
        }
        for server in servers.into_iter().take(200) {
            widgets::card(ui, &format!("server-{}", server.id), Tint::Regular, 14.0, 16.0, |ui| {
                ui.horizontal(|ui| {
                    ui.allocate_ui(egui::vec2(ui.available_width() - 90.0, 0.0), |ui| {
                        ui.vertical(|ui| {
                            let name = if server.password { format!("🔒 {}", server.name) } else { server.name.clone() };
                            ui.label(RichText::new(name).font(theme::body(15.0)).strong().color(theme::PRIMARY));
                            if !server.description.is_empty() {
                                ui.add(egui::Label::new(text(&server.description, 13.0, theme::SECONDARY)).wrap());
                            }
                            let region = server.region.as_ref().map(|r| format!(" · {r}")).unwrap_or_default();
                            ui.label(text(&format!("{} · {}{region}", server.map, server.playlist), 13.0, theme::FAINT));
                        });
                    });
                    ui.with_layout(Layout::right_to_left(Align::Min), |ui| {
                        ui.label(RichText::new(format!("{}/{}", server.players, server.max_players)).font(theme::display(17.0)).color(theme::PRIMARY));
                    });
                });
            });
        }
    }

    // MARK: Console

    fn console(&mut self, ui: &mut Ui, remote: &Remote) {
        let mut clear = false;
        let icons = &mut self.icons;
        widgets::card(ui, "console", Tint::Dark, 22.0, 20.0, |ui| {
            ui.spacing_mut().item_spacing.y = 6.0;
            ui.horizontal(|ui| {
                widgets::stencil(ui, "Console", 11.0, theme::SECONDARY);
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    clear = Button::new("Clear").icon("x").size(13.0).show(ui, icons).clicked();
                });
            });
            let start = remote.console.len().saturating_sub(400);
            for line in &remote.console[start..] {
                let color = match line.level.as_str() { "error" => theme::ERROR, "ok" => theme::OK, _ => theme::SECONDARY };
                let secs = line.time as i64;
                let (h, m, s) = ((secs / 3600 + 24 + local_offset_hours()) % 24, secs / 60 % 60, secs % 60);
                let row = format!("{h:02}:{m:02}:{s:02}  {}  {}: {}", line.level.to_uppercase(), line.scope, line.message);
                ui.add(egui::Label::new(RichText::new(row).monospace().size(12.0).color(color)).wrap());
            }
        });
        if clear {
            self.engine.remote.lock().unwrap().console.clear();
        }
    }

    // MARK: Settings

    fn settings(&mut self, ui: &mut Ui, state: &State) {
        let sender = self.sender();
        let icons = &mut self.icons;
        let windows = state.os == "Windows";
        widgets::card(ui, "games", Tint::Regular, 22.0, 20.0, |ui| {
            ui.spacing_mut().item_spacing.y = 10.0;
            widgets::stencil(ui, "Titanfall 2", 11.0, theme::SECONDARY);
            let prefixes = if windows { "" } else { " in Draconis or Heroic prefixes" };
            ui.label(text(&format!("Draconis finds Steam copies (native, Flatpak, Snap), EA app and Epic copies{prefixes}, and folders you add."), 14.0, theme::SECONDARY));
            for game in &state.games {
                ui.horizontal(|ui| {
                    ui.vertical(|ui| {
                        ui.label(RichText::new(&game.name).font(theme::body(14.0)).strong().color(theme::PRIMARY));
                        ui.label(text(&game.root, 13.0, theme::FAINT));
                    });
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        if state.selected().is_some_and(|g| g.id == game.id) {
                            widgets::stencil(ui, "Selected", 11.0, theme::SECONDARY);
                        } else if Button::new("Use").icon("circle-check").size(13.0).show(ui, icons).clicked() {
                            sender.send(json!({ "cmd": "selectGame", "id": game.id }));
                        }
                    });
                });
            }
            ui.horizontal(|ui| {
                if Button::new("Add a game folder…").icon("folder-plus").size(13.0).show(ui, icons).clicked() {
                    let sender = sender.clone();
                    std::thread::spawn(move || {
                        if let Some(path) = rfd::FileDialog::new().set_title("Titanfall 2 folder").pick_folder() {
                            sender.send(json!({ "cmd": "addGameFolder", "path": path }));
                        }
                    });
                }
                if Button::new("Rescan").icon("refresh-cw").size(13.0).show(ui, icons).clicked() {
                    sender.cmd("rescan");
                }
            });
        });
        if !windows {
            let busy = state.tool_busy.is_some();
            widgets::card(ui, "runner", Tint::Regular, 22.0, 20.0, |ui| {
                ui.spacing_mut().item_spacing.y = 10.0;
                widgets::stencil(ui, "Runner", 11.0, theme::SECONDARY);
                ui.label(text("Steam copies run with the Proton you pick in Steam. Copies in a Wine prefix run with the build below; Proton goes through umu-launcher.", 14.0, theme::SECONDARY));
                if state.runners.is_empty() {
                    ui.label(text("No Proton or Wine found.", 14.0, theme::FAINT));
                } else {
                    let current = state.runners.iter().find(|r| Some(&r.id) == state.selected_runner.as_ref()).map(|r| r.title.clone()).unwrap_or_default();
                    egui::ComboBox::from_id_salt("runner").selected_text(current).width(420.0).show_ui(ui, |ui| {
                        for runner in &state.runners {
                            if ui.selectable_label(Some(&runner.id) == state.selected_runner.as_ref(), &runner.title).clicked() {
                                sender.send(json!({ "cmd": "selectRunner", "id": runner.id }));
                            }
                        }
                    });
                }
                let umu = state.umu_path.as_ref().map(|p| format!("umu-launcher: {p}")).unwrap_or_else(|| "umu-launcher: not installed".into());
                ui.label(text(&umu, 13.0, theme::FAINT));
                ui.horizontal(|ui| {
                    if Button::new("Download GE-Proton").icon("download").size(13.0).enabled(!busy).show(ui, icons).clicked() && !busy {
                        sender.cmd("installGEProton");
                    }
                    if state.umu_path.is_none() && Button::new("Install umu-launcher").icon("download").size(13.0).enabled(!busy).show(ui, icons).clicked() && !busy {
                        sender.cmd("installUmu");
                    }
                });
                if let Some(tool) = &state.tool_busy {
                    ui.label(text(tool, 14.0, theme::PRIMARY));
                    widgets::progress(ui, state.tool_progress.as_ref().map(|p| p.fraction).filter(|f| *f >= 0.0));
                    if let Some(detail) = state.tool_progress.as_ref().and_then(|p| p.detail.as_ref()) {
                        ui.label(text(detail, 13.0, theme::FAINT));
                    }
                }
            });
            widgets::card(ui, "prefix", Tint::Regular, 22.0, 20.0, |ui| {
                ui.spacing_mut().item_spacing.y = 10.0;
                widgets::stencil(ui, "EA app / Epic copy", 11.0, theme::SECONDARY);
                ui.label(text("No Steam? Draconis can make its own Wine prefix (in its data folder, never ~/.wine) and install the EA app there. Sign in, install Titanfall 2 from the EA app, then Rescan. Epic owners: link your Epic account in the EA app.", 14.0, theme::SECONDARY));
                let enabled = !busy && state.selected_runner.is_some();
                if Button::new("Create prefix with the EA app").icon("folder-plus").size(13.0).enabled(enabled).show(ui, icons).clicked() && enabled {
                    sender.cmd("createPrefix");
                }
            });
        }
        widgets::card(ui, "about", Tint::Regular, 22.0, 20.0, |ui| {
            ui.spacing_mut().item_spacing.y = 10.0;
            widgets::stencil(ui, "About", 11.0, theme::SECONDARY);
            ui.label(RichText::new(format!("Draconis {} for {}", state.version, state.os)).font(theme::body(15.0)).strong().color(theme::PRIMARY));
            ui.label(text(&format!("Data folder: {}", state.data_folder), 13.0, theme::FAINT));
            if let Some(crash) = &state.last_crash_report {
                ui.label(text(&format!("Last crash report: {crash}. Attach it to a bug report."), 13.0, theme::SECONDARY));
                if Button::new("Open crash reports").icon("folder-plus").size(13.0).show(ui, icons).clicked() {
                    let _ = open::that(&state.crash_folder);
                }
            }
            ui.horizontal(|ui| {
                if Button::new("Releases").icon("download").size(13.0).show(ui, icons).clicked() {
                    let _ = open::that(&state.releases_page);
                }
                if Button::new("Report a bug").icon("circle-alert").size(13.0).show(ui, icons).clicked() {
                    let _ = open::that(&state.issues_page);
                }
                if Button::new("Check for updates").icon("refresh-cw").size(13.0).show(ui, icons).clicked() {
                    sender.cmd("checkForUpdate");
                }
            });
            ui.label(text("Draconis is free software under the GPL-3.0-or-later. It uses liquid-rust (MIT/Apache-2.0), egui and wgpu (MIT/Apache-2.0), ZIPFoundation (MIT), swift-crypto (Apache-2.0), the Orbitron, Inter and Barlow Condensed fonts (SIL OFL 1.1) and Lucide icons (ISC); see THIRD-PARTY-NOTICES.md. umu-launcher (GPL-3.0) and GE-Proton are downloaded only when you ask.", 13.0, theme::FAINT));
        });
    }
}

/// Hours east of UTC, for console timestamps.
fn local_offset_hours() -> i64 {
    std::env::var("DRACONIS_UTC_OFFSET").ok().and_then(|v| v.parse().ok()).unwrap_or(0)
}
