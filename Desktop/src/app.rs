//! The windows, after the macOS `ContentView` (sidebar + Play, Mods, Servers,
//! Console) and `SettingsView` (its own window). Layout values in points come
//! from docs/look. State comes from the engine; buttons send commands.

use crate::engine::{Engine, Game, Package, Remote, Sender, Server, State};
use crate::glass;
use crate::theme::{self, Tint};
use crate::widgets::{self, Button, Icons, WindowButton};
use egui::{Align, Color32, Layout, Rect, RichText, Sense, Ui, UiBuilder, pos2, vec2};
use serde_json::json;
use std::collections::HashMap;
use std::sync::mpsc;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Section { Play, Mods, Servers, Console }

impl Section {
    pub const ALL: [Section; 4] = [Section::Play, Section::Mods, Section::Servers, Section::Console];
    fn title(self) -> &'static str {
        match self { Section::Play => "Play", Section::Mods => "Mods", Section::Servers => "Servers", Section::Console => "Console" }
    }
    fn icon(self) -> &'static str {
        match self { Section::Play => "play", Section::Mods => "puzzle-piece", Section::Servers => "hard-drives", Section::Console => "terminal-window" }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Tab { General, Runner, Advanced, About }

impl Tab {
    fn title(self) -> &'static str {
        match self { Tab::General => "General", Tab::Runner => "Runner", Tab::Advanced => "Advanced", Tab::About => "About" }
    }
    fn icon(self) -> &'static str {
        match self { Tab::General => "gear-six", Tab::Runner => "wine", Tab::Advanced => "terminal-window", Tab::About => "info" }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Mode { Northstar, Vanilla }

#[derive(Clone, Copy, PartialEq, Eq)]
enum ModsTab { Browse, Installed }

#[derive(Clone, Copy, PartialEq, Eq)]
enum Sort { Rating, Downloads, Updated, Name }

impl Sort {
    const ALL: [Sort; 4] = [Sort::Rating, Sort::Downloads, Sort::Updated, Sort::Name];
    fn title(self) -> &'static str {
        match self { Sort::Rating => "Top rated", Sort::Downloads => "Most downloaded", Sort::Updated => "Recently updated", Sort::Name => "Name (A–Z)" }
    }
}

/// What the windows ask the shell to do.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Action { Close, Minimize, Zoom, Drag, OpenSettings, CloseSettings, MinimizeSettings, DragSettings }

/// Viewer preferences that the engine doesn't keep.
#[derive(serde::Serialize, serde::Deserialize, Default)]
#[serde(default, rename_all = "camelCase")]
struct Prefs {
    show_console: bool,
    hide_deprecated: bool,
    hide_nsfw: bool,
}

fn prefs_path() -> Option<std::path::PathBuf> {
    let base = if cfg!(windows) {
        std::env::var_os("LOCALAPPDATA").map(|d| std::path::PathBuf::from(d).join("Draconis"))
    } else {
        std::env::var_os("XDG_DATA_HOME").map(std::path::PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".local/share")))
            .map(|d| d.join("draconis"))
    };
    base.map(|d| d.join("ui.json"))
}

/// Thunderstore icons, fetched on a thread as rows come into view.
#[derive(Default)]
struct Remote2 {
    textures: HashMap<String, Option<egui::TextureHandle>>,
    inbox: Option<mpsc::Receiver<(String, Option<egui::ColorImage>)>>,
    outbox: Option<mpsc::Sender<String>>,
}

impl Remote2 {
    fn get(&mut self, ctx: &egui::Context, url: &str) -> Option<egui::TextureHandle> {
        if self.outbox.is_none() {
            let (ask, asked) = mpsc::channel::<String>();
            let (answer, answers) = mpsc::channel();
            let repaint = ctx.clone();
            std::thread::spawn(move || {
                for url in asked {
                    let image = ureq::get(&url).call().ok()
                        .and_then(|mut r| r.body_mut().read_to_vec().ok())
                        .and_then(|bytes| image::load_from_memory(&bytes).ok())
                        .map(|i| {
                            let i = i.resize_exact(112, 112, image::imageops::FilterType::Triangle).to_rgba8();
                            egui::ColorImage::from_rgba_unmultiplied([112, 112], i.as_raw())
                        });
                    if answer.send((url, image)).is_err() {
                        break;
                    }
                    repaint.request_repaint();
                }
            });
            self.outbox = Some(ask);
            self.inbox = Some(answers);
        }
        if let Some(inbox) = &self.inbox {
            for (url, image) in inbox.try_iter() {
                let texture = image.map(|i| ctx.load_texture(&url, i, egui::TextureOptions::LINEAR));
                self.textures.insert(url, texture);
            }
        }
        match self.textures.get(url) {
            Some(t) => t.clone(),
            None => {
                self.textures.insert(url.to_owned(), None);
                if let Some(out) = &self.outbox { let _ = out.send(url.to_owned()); }
                None
            }
        }
    }
}

pub struct App {
    pub icons: Icons,
    pub section: Section,
    pub tab: Tab,
    pub mode: Mode,
    pub actions: Vec<Action>,
    pub focused: bool,
    pub sidebar_hidden: bool,
    engine: Engine,
    logo: Option<egui::TextureHandle>,
    resources: std::path::PathBuf,
    prefs: Prefs,
    mods_tab: ModsTab,
    sort: Sort,
    category: String,
    mod_query: String,
    server_query: String,
    console_filter: Option<&'static str>,
    autoscroll: bool,
    asked_mods: bool,
    asked_servers: bool,
    thumbs: Remote2,
}

fn text(s: &str, size: f32, color: Color32) -> RichText {
    RichText::new(s).font(theme::body(size)).color(color)
}

fn count(n: i64) -> String {
    match n {
        n if n >= 1_000_000 => format!("{:.1}M", n as f64 / 1e6),
        n if n >= 1_000 => format!("{:.1}k", n as f64 / 1e3),
        n => n.to_string(),
    }
}

/// Lays `add` out in `rect` as its own region.
fn region<R>(ui: &mut Ui, rect: Rect, add: impl FnOnce(&mut Ui) -> R) -> R {
    let mut child = ui.new_child(UiBuilder::new().max_rect(rect).layout(Layout::top_down(Align::Min)));
    add(&mut child)
}

/// The floating sidebar, in window points.
pub fn sidebar_panel(height: f32) -> crate::backdrop::Panel {
    crate::backdrop::Panel { rect: [8.0, 8.0, 240.0, height - 16.0], radius: 18.0 }
}

impl App {
    pub fn new(resources: std::path::PathBuf, engine: Engine) -> Self {
        let prefs = prefs_path().and_then(|p| std::fs::read(p).ok()).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        Self {
            icons: Icons::new(resources.clone()),
            section: Section::Play,
            tab: Tab::General,
            mode: Mode::Northstar,
            actions: Vec::new(),
            focused: true,
            sidebar_hidden: false,
            engine,
            logo: None,
            resources,
            prefs,
            mods_tab: ModsTab::Browse,
            sort: Sort::Rating,
            category: "All".into(),
            mod_query: String::new(),
            server_query: String::new(),
            console_filter: None,
            autoscroll: true,
            asked_mods: false,
            asked_servers: false,
            thumbs: Remote2::default(),
        }
    }

    /// Snapshots: show the Console row like the macOS look test does.
    pub fn show_console(&mut self, on: bool) {
        self.prefs.show_console = on;
    }

    fn save_prefs(&self) {
        if let (Some(path), Ok(bytes)) = (prefs_path(), serde_json::to_vec_pretty(&self.prefs)) {
            if let Some(dir) = path.parent() { let _ = std::fs::create_dir_all(dir); }
            let _ = std::fs::write(path, bytes);
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

    // MARK: Main window

    pub fn ui(&mut self, ui: &mut Ui) {
        let remote = self.engine.remote.clone();
        let remote = remote.lock().unwrap();
        let full = ui.max_rect();
        let ctrl_comma = ui.input_mut(|i| i.consume_key(egui::Modifiers::COMMAND, egui::Key::Comma));
        if ctrl_comma {
            self.actions.push(Action::OpenSettings);
        }
        if !self.prefs.show_console && self.section == Section::Console {
            self.section = Section::Play;
        }
        self.drop_zips(ui);

        let bar = ui.interact(Rect::from_min_size(full.min, vec2(full.width(), 52.0)), ui.scope_id().with("titlebar"), Sense::click_and_drag());
        if bar.double_clicked() {
            self.actions.push(Action::Zoom);
        } else if bar.drag_started() {
            self.actions.push(Action::Drag);
        }

        let sidebar = Rect::from_min_max(full.min + vec2(8.0, 8.0), pos2(full.min.x + 248.0, full.max.y - 8.0));
        let detail = if self.sidebar_hidden { full } else { Rect::from_min_max(pos2(sidebar.max.x, full.min.y), full.max) };
        region(ui, detail, |ui| {
            ui.set_clip_rect(detail.intersect(ui.clip_rect()));
            match &remote.state {
                None => self.starting(ui, &remote),
                Some(state) => match self.section {
                    Section::Play => self.play(ui, state),
                    Section::Mods => self.mods(ui, state, &remote),
                    Section::Servers => self.servers(ui, state, &remote),
                    Section::Console => self.console(ui, &remote),
                },
            }
        });
        if !self.sidebar_hidden {
            glass::place(ui.scope_id().with("sidebar"), sidebar, 18.0, Tint::Sidebar, 0);
            let content = Rect::from_min_max(pos2(sidebar.min.x + 10.0, sidebar.min.y + 40.0), pos2(sidebar.max.x - 10.0, sidebar.max.y - 10.0));
            region(ui, content, |ui| self.sidebar(ui, remote.state.as_ref()));
        }
        if let Some(button) = widgets::traffic_lights(ui, full.min + vec2(26.0, 26.0), self.focused) {
            self.actions.push(match button { WindowButton::Close => Action::Close, WindowButton::Minimize => Action::Minimize, WindowButton::Zoom => Action::Zoom });
        }
        let toggle_x = if self.sidebar_hidden { full.min.x + 104.0 } else { sidebar.max.x - 24.0 };
        let toggle = Rect::from_center_size(pos2(toggle_x, full.min.y + 26.0), vec2(24.0, 22.0));
        let gear = toggle.translate(vec2(-30.0, 0.0));
        if self.icon_button(ui, "sidebar", toggle, "sidebar-simple") {
            self.sidebar_hidden = !self.sidebar_hidden;
        }
        if !self.sidebar_hidden && self.icon_button(ui, "settings", gear, "gear-six") {
            self.actions.push(Action::OpenSettings);
        }
        widgets::window_rim(ui, full);
    }

    fn icon_button(&mut self, ui: &mut Ui, id: &str, rect: Rect, icon: &str) -> bool {
        let r = ui.interact(rect, ui.scope_id().with(id), Sense::click());
        if r.hovered() {
            ui.painter().rect_filled(rect, 6.0, Color32::from_white_alpha(18));
        }
        self.icons.paint(ui, icon, Rect::from_center_size(rect.center(), egui::Vec2::splat(17.0)), Color32::from_white_alpha(220));
        r.clicked()
    }

    /// Zips dropped on the window install as local mods (macOS: drop on the Mods view).
    fn drop_zips(&mut self, ui: &Ui) {
        let dropped: Vec<_> = ui.input(|i| i.raw.dropped_files.iter().map(|f| f.path().to_path_buf()).collect());
        for path in dropped.into_iter().filter(|p| p.extension().is_some_and(|e| e.eq_ignore_ascii_case("zip"))) {
            self.sender().send(json!({ "cmd": "installModZip", "path": path }));
            self.section = Section::Mods;
            self.mods_tab = ModsTab::Installed;
        }
    }

    fn starting(&mut self, ui: &mut Ui, remote: &Remote) {
        ui.add_space(82.0);
        ui.horizontal(|ui| {
            ui.add_space(28.0);
            ui.vertical(|ui| {
                ui.set_width(ui.available_width() - 28.0);
                widgets::card(ui, "starting", Tint::Regular, 22.0, 22.0, |ui| match &remote.gone {
                    Some(message) => { widgets::label(ui, message, 13.0, theme::ERROR); }
                    None => {
                        ui.horizontal(|ui| {
                            ui.add(egui::Spinner::new());
                            ui.label(text("Starting…", 13.0, theme::SECONDARY));
                        });
                    }
                });
            });
        });
    }

    fn sidebar(&mut self, ui: &mut Ui, state: Option<&State>) {
        ui.spacing_mut().item_spacing = vec2(0.0, 0.0);
        let header = |ui: &mut Ui, title: &str| {
            ui.horizontal(|ui| {
                ui.add_space(4.0);
                widgets::stencil(ui, title, 11.0, theme::STENCIL);
            });
            ui.add_space(5.0);
        };
        header(ui, "Launcher");
        for section in Section::ALL {
            if section == Section::Console && !self.prefs.show_console {
                continue;
            }
            if widgets::sidebar_item(ui, &mut self.icons, section.icon(), section.title(), self.section == section).clicked() {
                self.section = section;
            }
        }
        ui.add_space(16.0);
        header(ui, "Game");
        let sender = self.sender();
        match state {
            Some(state) if !state.games.is_empty() => {
                let options: Vec<(String, String)> = state.games.iter().map(|g| (g.id.clone(), g.name.clone())).collect();
                let current = state.selected().map(|g| g.name.clone()).unwrap_or_default();
                let icon = state.selected().map(|g| if g.kind == "steam" { "steam-logo" } else { "wine" });
                ui.horizontal(|ui| {
                    ui.add_space(7.0);
                    widgets::menu_picker(ui, &mut self.icons, "game", icon, &current, &options, |id| sender.send(json!({ "cmd": "selectGame", "id": id })));
                });
            }
            Some(_) => {
                ui.horizontal(|ui| {
                    ui.add_space(4.0);
                    ui.label(text("No Titanfall 2 found", 11.0, theme::FAINT));
                });
            }
            None => {}
        }
        ui.add_space(7.0);
        let scanning = state.is_some_and(|s| s.scanning);
        ui.horizontal(|ui| {
            ui.add_space(6.0);
            if Button::new(if scanning { "Scanning…" } else { "Rescan" }).icon("arrow-clockwise").pad(vec2(14.0, 6.0)).enabled(!scanning).show(ui, &mut self.icons).clicked() {
                sender.cmd("rescan");
            }
        });
        if let Some(state) = state {
            ui.add_space(20.0);
            header(ui, "Backend");
            let steam = state.games.iter().any(|g| g.kind == "steam");
            widgets::backend_row(ui, &mut self.icons, "steam-logo", "Steam", steam);
            if state.os != "Windows" {
                widgets::backend_row(ui, &mut self.icons, "wine", "Proton / Wine", !state.runners.is_empty());
                widgets::backend_row(ui, &mut self.icons, "cube", "umu-launcher", state.umu_path.is_some());
            }
        }
    }

    /// The scrolling detail column: 28 pt padding, at most 880 pt wide, under a 54 pt toolbar.
    fn page(ui: &mut Ui, id: &str, add: impl FnOnce(&mut Ui)) {
        let area = ui.max_rect();
        let top = Rect::from_min_max(pos2(area.min.x, area.min.y + 54.0), area.max);
        region(ui, top, |ui| {
            egui::ScrollArea::vertical().id_salt(id).auto_shrink([false, false]).show(ui, |ui| {
                ui.add_space(28.0);
                let width = (ui.available_width() - 56.0).min(880.0);
                ui.horizontal(|ui| {
                    ui.add_space((ui.available_width() - width) / 2.0);
                    ui.vertical(|ui| {
                        ui.set_width(width);
                        ui.spacing_mut().item_spacing.y = 22.0;
                        add(ui);
                    });
                });
                ui.add_space(60.0);
            });
        });
    }

    // MARK: Play

    fn play(&mut self, ui: &mut Ui, state: &State) {
        let logo = self.logo(ui.ctx());
        Self::page(ui, "play", |ui| {
            let game = state.selected().cloned();
            widgets::card(ui, "hero", Tint::Subtle, 26.0, 28.0, |ui| {
                ui.horizontal(|ui| {
                    ui.spacing_mut().item_spacing.x = 18.0;
                    if let Some(logo) = &logo {
                        ui.add(egui::Image::new(logo).fit_to_exact_size(vec2(96.0, 96.0)));
                    }
                    ui.vertical(|ui| {
                        ui.spacing_mut().item_spacing.y = 2.0;
                        ui.label(widgets::tracked("DRACONIS", theme::hero(48.0), theme::PRIMARY, 8.0));
                        ui.label(RichText::new(format!("Titanfall 2 + Northstar launcher for {}.", state.os)).font(theme::title(16.0)).color(Color32::from_white_alpha(199)));
                        if let Some(game) = &game {
                            ui.add_space(6.0);
                            ui.horizontal(|ui| {
                                ui.spacing_mut().item_spacing.x = 6.0;
                                let icon = if game.kind == "steam" { "steam-logo" } else { "wine" };
                                widgets::icon(ui, &mut self.icons, icon, 12.0, Color32::from_white_alpha(184));
                                ui.label(text(&format!("Titanfall 2 — {}", game.name), 12.0, Color32::from_white_alpha(184)));
                            });
                        }
                    });
                });
            });
            let Some(game) = game else {
                self.setup(ui, state);
                return;
            };
            self.pills(ui, state, &game);
            if state.northstar_busy || state.tool_busy.is_some() {
                let progress = state.northstar_progress.as_ref().or(state.tool_progress.as_ref());
                widgets::card(ui, "progress", Tint::Regular, 18.0, 16.0, |ui| {
                    ui.spacing_mut().item_spacing.y = 8.0;
                    ui.horizontal(|ui| {
                        widgets::stencil(ui, state.tool_busy.as_deref().unwrap_or("Northstar"), 11.0, theme::STENCIL);
                        if let Some(detail) = progress.and_then(|p| p.detail.as_ref()) {
                            ui.with_layout(Layout::right_to_left(Align::Center), |ui| { ui.label(text(detail, 12.0, theme::TERTIARY)); });
                        }
                    });
                    widgets::progress(ui, progress.map(|p| p.fraction).filter(|f| *f >= 0.0));
                });
            }
            if let Some(error) = &state.error {
                let sender = self.sender();
                widgets::card(ui, "error", Tint::Error, 14.0, 14.0, |ui| {
                    ui.horizontal(|ui| {
                        widgets::icon(ui, &mut self.icons, "warning-octagon", 16.0, theme::ERROR);
                        ui.allocate_ui(vec2(ui.available_width() - 90.0, 0.0), |ui| { widgets::label(ui, error, 13.0, theme::PRIMARY); });
                        ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                            if Button::new("Dismiss").show(ui, &mut self.icons).clicked() { sender.cmd("dismissError"); }
                        });
                    });
                });
            }
            self.actions_card(ui, state, &game);
            if let Some(version) = &state.newer_version {
                let page = state.releases_page.clone();
                widgets::card(ui, "update", Tint::Medium, 18.0, 16.0, |ui| {
                    ui.horizontal(|ui| {
                        ui.label(text(&format!("Draconis {version} is available."), 13.0, theme::PRIMARY));
                        ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                            if Button::new("Download").icon("download-simple").show(ui, &mut self.icons).clicked() { let _ = open::that(&page); }
                        });
                    });
                });
            }
            if state.launching || state.game_running {
                widgets::card(ui, "launching", Tint::Medium, 18.0, 16.0, |ui| {
                    ui.spacing_mut().item_spacing.y = 8.0;
                    widgets::stencil(ui, if state.launching { "Launching" } else { "Running" }, 11.0, theme::STENCIL);
                    ui.horizontal(|ui| {
                        if state.launching { ui.add(egui::Spinner::new().size(14.0)); }
                        let message = if state.launching { state.status.clone().unwrap_or_else(|| "Starting…".into()) } else { "Titanfall 2 is running. Launch is available again once it closes.".into() };
                        ui.label(text(&message, 13.0, theme::TERTIARY));
                    });
                });
            }
            if state.needs_runner && state.selected_runner.is_none() {
                let mut open = false;
                widgets::card(ui, "runner-notice", Tint::Strong, 22.0, 22.0, |ui| {
                    ui.spacing_mut().item_spacing.y = 14.0;
                    ui.label(RichText::new("Pick a runner").font(theme::title(16.0)).color(theme::PRIMARY));
                    widgets::label(ui, "This copy runs through Wine or Proton. Pick one, or download GE-Proton, in Settings → Runner.", 13.0, theme::TERTIARY);
                    open = Button::new("Open Settings").icon("gear-six").prominent().pad(vec2(14.0, 8.0)).show(ui, &mut self.icons).clicked();
                });
                if open {
                    self.tab = Tab::Runner;
                    self.actions.push(Action::OpenSettings);
                }
            }
            self.vr(ui, state);
        });
    }

    fn pills(&mut self, ui: &mut Ui, state: &State, game: &Game) {
        let launcher_ready = !state.needs_runner || state.selected_runner.is_some();
        let launcher = match game.kind.as_str() {
            "steam" => "Steam".to_owned(),
            "prefix" => state.runners.iter().find(|r| Some(&r.id) == state.selected_runner.as_ref()).map(|r| r.title.clone()).unwrap_or_else(|| "Missing".into()),
            _ => game.name.clone(),
        };
        let northstar = if game.has_northstar { game.northstar_version.clone().unwrap_or_else(|| "Ready".into()) } else { "Not installed".into() };
        let (row, _) = ui.allocate_exact_size(vec2(ui.available_width(), 70.0), Sense::hover());
        let pill = (row.width() - 28.0) / 3.0;
        let items = [
            ("Titanfall 2", "Detected".to_owned(), "seal-check", true),
            ("Launcher", launcher, if launcher_ready { "seal-check" } else { "warning" }, launcher_ready),
            ("Northstar", northstar, if game.has_northstar { "shield-check" } else { "question" }, game.has_northstar),
        ];
        for (i, (label, value, icon, active)) in items.into_iter().enumerate() {
            let rect = Rect::from_min_size(row.min + vec2((pill + 14.0) * i as f32, 0.0), vec2(pill, row.height()));
            region(ui, rect, |ui| widgets::status_pill(ui, &mut self.icons, label, &value, icon, active));
        }
    }

    fn setup(&mut self, ui: &mut Ui, state: &State) {
        let sender = self.sender();
        let mut open = false;
        widgets::card(ui, "setup", Tint::Strong, 22.0, 22.0, |ui| {
            ui.spacing_mut().item_spacing.y = 14.0;
            ui.label(RichText::new("Set up Titanfall 2").font(theme::title(16.0)).color(theme::PRIMARY));
            let prefix = if state.os == "Windows" { "" } else { ", or create a Wine prefix with the EA app" };
            widgets::label(ui, &format!("Draconis didn't find Titanfall 2.\n\n1. Install it with Steam, the EA app or Epic.\n2. Or open Settings to add its folder{prefix}.\n3. When the game is detected, Draconis takes over launching it."), 13.0, theme::TERTIARY);
            ui.horizontal(|ui| {
                ui.spacing_mut().item_spacing.x = 12.0;
                open = Button::new("Open Settings").icon("gear-six").prominent().pad(vec2(14.0, 8.0)).show(ui, &mut self.icons).clicked();
                if Button::new(if state.scanning { "Scanning…" } else { "Rescan" }).icon("arrow-clockwise").pad(vec2(14.0, 8.0)).show(ui, &mut self.icons).clicked() {
                    sender.cmd("rescan");
                }
            });
        });
        if open {
            self.actions.push(Action::OpenSettings);
        }
    }

    fn actions_card(&mut self, ui: &mut Ui, state: &State, game: &Game) {
        let sender = self.sender();
        let icons = &mut self.icons;
        let mode = &mut self.mode;
        widgets::card(ui, "actions", Tint::Regular, 22.0, 18.0, |ui| {
            ui.spacing_mut().item_spacing.y = 16.0;
            ui.horizontal(|ui| {
                let seg_width = 2.0 * 150.0;
                ui.add_space(((ui.available_width() - seg_width - 50.0) / 2.0).max(0.0));
                ui.label(text("Mode", 13.0, theme::PRIMARY));
                ui.add_space(4.0);
                widgets::segmented(ui, "mode", &[(Mode::Northstar, "Northstar"), (Mode::Vanilla, "Titanfall 2 (vanilla)")], mode);
            });
            ui.horizontal(|ui| {
                ui.spacing_mut().item_spacing.x = 12.0;
                let busy = state.northstar_busy;
                let pad = vec2(12.0, 12.0);
                let mut side: Vec<(String, &str, &str)> = Vec::new();
                if !game.has_northstar {
                    side.push((if busy { "Installing…" } else { "Install Northstar" }.into(), "arrow-circle-down", "installNorthstar"));
                } else {
                    if let (false, false, Some(latest)) = (state.northstar_up_to_date, state.auto_update_northstar, &state.latest_northstar) {
                        side.push((format!("Update to {latest}"), "arrow-circle-up", "installNorthstar"));
                    }
                    side.push((if busy { "Removing…" } else { "Uninstall NS" }.into(), "trash", "uninstallNorthstar"));
                }
                let side_width: f32 = side.iter().map(|(t, _, _)| ui.painter().layout_no_wrap(t.clone(), theme::title(14.0), Color32::WHITE).size().x + 14.0 + 7.0 + 36.0 + 12.0).sum();
                let title = if state.game_running { "Running" } else if state.launching { "Launching…" } else { "Launch" };
                let enabled = !state.launching && !state.game_running && !busy && !(*mode == Mode::Northstar && !game.has_northstar);
                if Button::new(title).icon("play").prominent().title_font(16.0, pad).width(ui.available_width() - side_width).enabled(enabled).show(ui, icons).clicked() {
                    sender.send(json!({ "cmd": "launch", "mode": if *mode == Mode::Vanilla { "vanilla" } else { "northstar" } }));
                }
                for (title, icon, cmd) in side {
                    if Button::new(&title).icon(icon).title_font(14.0, vec2(18.0, 12.0)).enabled(!busy && !state.launching).show(ui, icons).clicked() {
                        sender.cmd(cmd);
                    }
                }
            });
        });
    }

    fn vr(&mut self, ui: &mut Ui, state: &State) {
        let sender = self.sender();
        let vr = &state.vr;
        let icons = &mut self.icons;
        let windows = state.os == "Windows";
        widgets::card(ui, "vr", Tint::Regular, 22.0, 22.0, |ui| {
            ui.spacing_mut().item_spacing.y = 12.0;
            ui.horizontal(|ui| {
                ui.spacing_mut().item_spacing.x = 6.0;
                widgets::icon(ui, icons, "eyeglasses", 14.0, theme::STENCIL);
                widgets::stencil(ui, "Virtual reality", 11.0, theme::STENCIL);
                if let Some(version) = &vr.installed_version {
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| { ui.label(text(&version.to_string(), 12.0, theme::FAINT)); });
                }
            });
            if !vr.supported {
                widgets::label(ui, "On Linux, VR works with the Steam copy of Titanfall 2 for now.", 13.0, theme::TERTIARY);
            } else if vr.busy {
                ui.horizontal(|ui| {
                    ui.add(egui::Spinner::new().size(14.0));
                    ui.label(text(vr.phase.as_deref().unwrap_or("Working…"), 13.0, theme::TERTIARY));
                });
                if let Some(progress) = vr.progress { widgets::progress(ui, Some(progress)); }
            } else if vr.installed_version.is_none() {
                widgets::label(ui, "CircuitLord's Titanfall 2 VR mod plays the campaign in VR through OpenXR. It installs into its own TF2VR profile, so the normal game and your Northstar stay as they are. About 180 MB to download, plus 3 GB of game files built on your PC.", 13.0, theme::TERTIARY);
                if Button::new("Install VR mod").icon("download-simple").prominent().pad(vec2(14.0, 8.0)).show(ui, icons).clicked() {
                    sender.cmd("installVR");
                }
            } else {
                ui.horizontal(|ui| {
                    ui.spacing_mut().item_spacing.x = 6.0;
                    let running = vr.steam_vr_running || vr.other_runtime.is_some();
                    widgets::icon(ui, icons, if running { "check-circle" } else { "warning" }, 14.0, if running { theme::PRIMARY } else { theme::FAINT });
                    let runtime = if !vr.checked { "Checking for a VR runtime…".to_owned() }
                        else if vr.steam_vr_running { "SteamVR is running.".into() }
                        else if let Some(other) = &vr.other_runtime { format!("{other} is running.") }
                        else if let Some(active) = &vr.active_runtime { format!("No VR runtime is running. The active OpenXR runtime is {active}.") }
                        else { "No VR runtime is running.".into() };
                    ui.label(text(&runtime, 13.0, theme::TERTIARY));
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        if Button::new("Check again").icon("arrow-clockwise").show(ui, icons).clicked() { sender.cmd("refreshVR"); }
                        if vr.steam_vr_installed && !vr.steam_vr_running && Button::new("Start SteamVR").icon("play").show(ui, icons).clicked() { sender.cmd("startSteamVR"); }
                    });
                });
                ui.horizontal(|ui| {
                    ui.spacing_mut().item_spacing.x = 12.0;
                    let title = if state.launching { "Launching…" } else if state.game_running { "Running" } else { "Launch in VR" };
                    let enabled = !state.launching && !state.game_running;
                    if Button::new(title).icon("play").prominent().title_font(14.0, vec2(18.0, 9.0)).enabled(enabled).show(ui, icons).clicked() { sender.cmd("launchVR"); }
                    if let (true, Some(latest)) = (vr.update_available, &vr.latest_version) {
                        if Button::new(&format!("Update to {latest}")).icon("arrow-circle-up").title_font(14.0, vec2(18.0, 9.0)).show(ui, icons).clicked() { sender.cmd("installVR"); }
                    }
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        if Button::new("Remove VR").icon("trash").title_font(14.0, vec2(18.0, 9.0)).show(ui, icons).clicked() { sender.cmd("uninstallVR"); }
                    });
                });
            }
            if let Some(error) = &vr.error { widgets::label(ui, error, 13.0, theme::ERROR); }
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
            widgets::label(ui, &help, 12.0, theme::FAINT);
        });
    }

    // MARK: Mods

        /// A fixed header with 20 pt padding under the toolbar; the list goes in the rest.
    fn header(ui: &mut Ui, height: f32, add: impl FnOnce(&mut Ui)) -> Rect {
        let area = ui.max_rect();
        let head = Rect::from_min_size(pos2(area.min.x + 20.0, area.min.y + 54.0 + 20.0), vec2(area.width() - 40.0, height));
        region(ui, head, add);
        Rect::from_min_max(pos2(area.min.x, head.max.y + 20.0), area.max)
    }

    fn mods(&mut self, ui: &mut Ui, state: &State, remote: &Remote) {
        let sender = self.sender();
        if !self.asked_mods && remote.packages.is_empty() && !state.mods_loading {
            self.asked_mods = true;
            sender.cmd("refreshMods");
        }
        let q = self.mod_query.trim().to_lowercase();
        let mut packages: Vec<&Package> = remote.packages.iter().filter(|p| {
            (!self.prefs.hide_deprecated || !p.deprecated)
                && (!self.prefs.hide_nsfw || !p.nsfw)
                && (self.category == "All" || p.categories.contains(&self.category))
                && (q.is_empty() || p.name.to_lowercase().contains(&q) || p.owner.to_lowercase().contains(&q) || p.description.to_lowercase().contains(&q))
        }).collect();
        match self.sort {
            Sort::Rating => packages.sort_by_key(|p| std::cmp::Reverse(p.rating)),
            Sort::Downloads => packages.sort_by_key(|p| std::cmp::Reverse(p.downloads)),
            Sort::Updated => packages.sort_by(|a, b| b.updated.total_cmp(&a.updated)),
            Sort::Name => packages.sort_by_key(|p| p.name.to_lowercase()),
        }
        let mut categories = vec!["All".to_owned()];
        for p in &remote.packages {
            for c in &p.categories {
                if !categories.contains(c) { categories.push(c.clone()); }
            }
        }
        let mut prefs_changed = false;
        let list = Self::header(ui, 66.0, |ui| {
            ui.spacing_mut().item_spacing = vec2(12.0, 10.0);
            ui.horizontal(|ui| {
                ui.allocate_ui_with_layout(vec2(280.0, 32.0), Layout::centered_and_justified(egui::Direction::LeftToRight), |ui| {
                    widgets::segmented(ui, "mods-tab", &[(ModsTab::Browse, "Thunderstore"), (ModsTab::Installed, "Installed")], &mut self.mods_tab);
                });
                let refresh = ui.painter().layout_no_wrap("Refresh".into(), theme::body(13.0), Color32::WHITE).size().x + 13.0 + 7.0 + 24.0;
                widgets::search(ui, &mut self.icons, "mod-search", "Search mods…", &mut self.mod_query, ui.available_width() - refresh - 12.0);
                if Button::new(if state.mods_loading { "Loading…" } else { "Refresh" }).icon("arrow-clockwise").enabled(!state.mods_loading).show(ui, &mut self.icons).clicked() {
                    sender.cmd("refreshMods");
                }
            });
            ui.horizontal(|ui| {
                ui.spacing_mut().item_spacing.x = 10.0;
                if self.mods_tab == ModsTab::Browse {
                    ui.label(text("Sort", 11.0, theme::PRIMARY));
                    let sorts: Vec<(String, String)> = Sort::ALL.iter().map(|s| (s.title().to_owned(), s.title().to_owned())).collect();
                    let mut sort = self.sort;
                    widgets::menu_picker(ui, &mut self.icons, "sort", None, self.sort.title(), &sorts, |key| sort = Sort::ALL.into_iter().find(|s| s.title() == key).unwrap_or(sort));
                    self.sort = sort;
                    ui.add_space(8.0);
                    ui.label(text("Category", 11.0, theme::PRIMARY));
                    let options: Vec<(String, String)> = categories.iter().map(|c| (c.clone(), c.clone())).collect();
                    let mut category = self.category.clone();
                    widgets::menu_picker(ui, &mut self.icons, "category", None, &self.category, &options, |key| category = key.to_owned());
                    self.category = category;
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        widgets::stencil(ui, &format!("{} mods", packages.len()), 11.0, theme::STENCIL);
                        if widgets::checkbox(ui, "Hide NSFW", self.prefs.hide_nsfw).clicked() { self.prefs.hide_nsfw ^= true; prefs_changed = true; }
                        if widgets::checkbox(ui, "Hide deprecated", self.prefs.hide_deprecated).clicked() { self.prefs.hide_deprecated ^= true; prefs_changed = true; }
                    });
                } else {
                    widgets::stencil(ui, &format!("{} installed", state.installed_mods.len()), 11.0, theme::STENCIL);
                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        if Button::new("Install from zip…").icon("folder-simple-plus").show(ui, &mut self.icons).clicked() {
                            let sender = sender.clone();
                            std::thread::spawn(move || {
                                if let Some(path) = rfd::FileDialog::new().set_title("Install a mod zip").add_filter("Zip", &["zip"]).pick_file() {
                                    sender.send(json!({ "cmd": "installModZip", "path": path }));
                                }
                            });
                        }
                        ui.label(text("Drop a .zip here to install a local mod", 11.0, theme::FAINT));
                    });
                }
            });
        });
        if prefs_changed { self.save_prefs(); }
        region(ui, list, |ui| match self.mods_tab {
            ModsTab::Browse => {
                if packages.is_empty() {
                    ui.add_space(40.0);
                    ui.vertical_centered(|ui| {
                        if state.mods_loading { ui.add(egui::Spinner::new()); ui.label(text("Fetching Thunderstore…", 13.0, theme::SECONDARY)); }
                        else { ui.label(text("No mods found.", 13.0, theme::SECONDARY)); }
                    });
                    return;
                }
                let row_height = 92.0;
                egui::ScrollArea::vertical().id_salt("packages").auto_shrink([false, false]).show_rows(ui, row_height, packages.len(), |ui, range| {
                    ui.spacing_mut().item_spacing.y = 12.0;
                    for p in &packages[range] {
                        ui.horizontal(|ui| {
                            ui.add_space(20.0);
                            ui.allocate_ui(vec2(ui.available_width() - 20.0, row_height - 12.0), |ui| self.package_row(ui, state, p));
                        });
                    }
                });
            }
            ModsTab::Installed => {
                egui::ScrollArea::vertical().id_salt("installed").auto_shrink([false, false]).show(ui, |ui| {
                    ui.spacing_mut().item_spacing.y = 10.0;
                    if state.installed_mods.is_empty() {
                        ui.add_space(40.0);
                        ui.vertical_centered(|ui| {
                            widgets::icon(ui, &mut self.icons, "puzzle-piece", 22.0, theme::SECONDARY);
                            let place = state.selected().map(|g| g.name.clone()).unwrap_or_else(|| "this game".into());
                            ui.label(text(&format!("No mods installed in {place}."), 13.0, theme::SECONDARY));
                            ui.label(text("Browse Thunderstore above, or drop a .zip anywhere on this window.", 11.0, theme::FAINT));
                        });
                    }
                    for m in &state.installed_mods {
                        ui.horizontal(|ui| {
                            ui.add_space(20.0);
                            ui.allocate_ui(vec2(ui.available_width() - 20.0, 0.0), |ui| {
                                widgets::card(ui, ("mod", &m.id), Tint::Regular, 14.0, 14.0, |ui| {
                                    ui.horizontal(|ui| {
                                        ui.vertical(|ui| {
                                            ui.spacing_mut().item_spacing.y = 2.0;
                                            ui.horizontal(|ui| {
                                                ui.label(RichText::new(&m.name).font(theme::title(15.0)).color(theme::PRIMARY));
                                                if state.installed_packages.iter().any(|p| p.ends_with(&m.name)) { chip(ui, "PACKAGE", Tint::Dark); }
                                            });
                                            ui.label(text(&m.version, 11.0, theme::SECONDARY));
                                        });
                                        ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                                            let (r, more) = ui.allocate_exact_size(vec2(22.0, 22.0), Sense::click());
                                            self.icons.paint(ui, "dots-three-circle", Rect::from_center_size(r.center(), egui::Vec2::splat(18.0)), theme::SECONDARY);
                                            egui::Popup::menu(&more).show(|ui| {
                                                if ui.button("Uninstall").clicked() { sender.send(json!({ "cmd": "uninstallMod", "id": m.id })); }
                                            });
                                            if widgets::toggle(ui, m.enabled).clicked() {
                                                sender.send(json!({ "cmd": "setModEnabled", "id": m.id, "enabled": !m.enabled }));
                                            }
                                        });
                                    });
                                });
                            });
                        });
                    }
                    ui.add_space(20.0);
                });
            }
        });
    }

    fn package_row(&mut self, ui: &mut Ui, state: &State, p: &Package) {
        let sender = self.sender();
        let thumb = p.icon.as_deref().and_then(|url| self.thumbs.get(ui.ctx(), url));
        widgets::card(ui, ("pkg", &p.full_name), Tint::Regular, 18.0, 14.0, |ui| {
            ui.set_height(row_inner(ui));
            ui.horizontal_top(|ui| {
                ui.spacing_mut().item_spacing.x = 14.0;
                let (rect, _) = ui.allocate_exact_size(vec2(56.0, 56.0), Sense::hover());
                match &thumb {
                    Some(t) => { egui::Image::new(t).corner_radius(12).paint_at(ui, rect); }
                    None => { ui.painter().rect_filled(rect, 12.0, Color32::from_white_alpha(25)); }
                }
                let right = 96.0;
                ui.allocate_ui(vec2(ui.available_width() - right, 64.0), |ui| {
                    ui.vertical(|ui| {
                        ui.spacing_mut().item_spacing.y = 4.0;
                        ui.horizontal(|ui| {
                            ui.spacing_mut().item_spacing.x = 6.0;
                            ui.label(RichText::new(&p.name).font(theme::title(16.0)).color(theme::PRIMARY));
                            ui.label(text(&format!("by {}", p.owner), 11.0, theme::SECONDARY));
                            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                                if p.pinned { chip(ui, "PINNED", Tint::Selected); }
                                if p.deprecated { chip(ui, "DEPRECATED", Tint::Error); }
                            });
                        });
                        ui.add(egui::Label::new(text(&p.description, 12.0, theme::SECONDARY)).truncate());
                        ui.horizontal(|ui| {
                            ui.spacing_mut().item_spacing.x = 6.0;
                            for c in p.categories.iter().take(4) { chip(ui, c, Tint::Medium); }
                            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                                ui.spacing_mut().item_spacing.x = 3.0;
                                ui.label(text(&p.rating.to_string(), 10.0, theme::SECONDARY));
                                widgets::icon(ui, &mut self.icons, "star", 10.0, theme::SECONDARY);
                                ui.add_space(6.0);
                                ui.label(text(&count(p.downloads), 10.0, theme::SECONDARY));
                                widgets::icon(ui, &mut self.icons, "arrow-circle-down", 10.0, theme::SECONDARY);
                            });
                        });
                    });
                });
                ui.vertical_centered(|ui| {
                    ui.spacing_mut().item_spacing.y = 6.0;
                    let installed = state.installed_packages.contains(&p.full_name);
                    let busy = state.mod_busy.as_deref() == Some(p.full_name.as_str());
                    let title = if busy { "Installing…" } else if installed { "Reinstall" } else { "Install" };
                    let enabled = state.selected().is_some() && state.mod_busy.is_none();
                    if Button::new(title).icon(if installed { "arrow-clockwise" } else { "arrow-circle-down" }).enabled(enabled).show(ui, &mut self.icons).clicked() {
                        sender.send(json!({ "cmd": "installMod", "id": p.full_name }));
                    }
                    if let Some(page) = &p.page {
                        let link = ui.add(egui::Label::new(text("Page", 11.0, theme::SECONDARY)).sense(Sense::click()));
                        if link.on_hover_cursor(egui::CursorIcon::PointingHand).clicked() { let _ = open::that(page); }
                    }
                });
            });
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
        let servers: Vec<&Server> = remote.servers.iter().filter(|s| {
            q.is_empty() || [&s.name, &s.description, &s.map, &s.playlist].iter().any(|f| f.to_lowercase().contains(&q))
        }).collect();
        let list = Self::header(ui, 32.0, |ui| {
            ui.horizontal(|ui| {
                ui.spacing_mut().item_spacing.x = 12.0;
                let tail = 200.0;
                widgets::search(ui, &mut self.icons, "server-search", "Search servers, maps, playlists…", &mut self.server_query, ui.available_width() - tail);
                if Button::new(if state.servers_loading { "Loading…" } else { "Refresh" }).icon("arrow-clockwise").enabled(!state.servers_loading).show(ui, &mut self.icons).clicked() {
                    sender.cmd("refreshServers");
                }
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    widgets::stencil(ui, &format!("{} servers", servers.len()), 11.0, theme::STENCIL);
                });
            });
        });
        region(ui, list, |ui| {
            if servers.is_empty() {
                ui.add_space(40.0);
                ui.vertical_centered(|ui| {
                    if state.servers_loading { ui.add(egui::Spinner::new()); ui.label(text("Querying masterserver…", 13.0, theme::SECONDARY)); }
                    else { ui.label(text("No servers.", 13.0, theme::SECONDARY)); }
                });
                return;
            }
            let row_height = 86.0;
            egui::ScrollArea::vertical().id_salt("servers").auto_shrink([false, false]).show_rows(ui, row_height, servers.len(), |ui, range| {
                ui.spacing_mut().item_spacing.y = 10.0;
                for server in &servers[range] {
                    ui.horizontal(|ui| {
                        ui.add_space(20.0);
                        ui.allocate_ui(vec2(ui.available_width() - 20.0, row_height - 10.0), |ui| self.server_row(ui, server));
                    });
                }
            });
        });
    }

    fn server_row(&mut self, ui: &mut Ui, server: &Server) {
        widgets::card(ui, ("server", &server.id), Tint::Regular, 14.0, 14.0, |ui| {
            ui.set_height(row_inner(ui));
            ui.horizontal_top(|ui| {
                ui.allocate_ui(vec2(ui.available_width() - 80.0, 0.0), |ui| {
                    ui.vertical(|ui| {
                        ui.spacing_mut().item_spacing.y = 3.0;
                        ui.horizontal(|ui| {
                            if server.password { widgets::icon(ui, &mut self.icons, "lock-simple", 12.0, theme::SECONDARY); }
                            ui.add(egui::Label::new(RichText::new(&server.name).font(theme::title(15.0)).color(theme::PRIMARY)).truncate());
                        });
                        ui.add(egui::Label::new(text(&server.description, 12.0, theme::SECONDARY)).truncate());
                        ui.horizontal(|ui| {
                            ui.spacing_mut().item_spacing.x = 4.0;
                            let mut meta = |ui: &mut Ui, icon: &str, value: &str| {
                                widgets::icon(ui, &mut self.icons, icon, 10.0, theme::SECONDARY);
                                ui.label(text(value, 10.0, theme::SECONDARY));
                                ui.add_space(8.0);
                            };
                            meta(ui, "map-trifold", &server.map);
                            meta(ui, "list-bullets", &server.playlist);
                            if let Some(region) = &server.region { meta(ui, "globe", region); }
                        });
                    });
                });
                ui.with_layout(Layout::top_down(Align::Max), |ui| {
                    ui.spacing_mut().item_spacing.y = 0.0;
                    ui.label(RichText::new(format!("{} / {}", server.players, server.max_players)).font(theme::title(22.0)).color(theme::PRIMARY));
                    widgets::stencil(ui, "Players", 9.0, theme::STENCIL);
                });
            });
        });
    }

    // MARK: Console

    fn console(&mut self, ui: &mut Ui, remote: &Remote) {
        let area = ui.max_rect();
        let head = Rect::from_min_size(pos2(area.min.x + 14.0, area.min.y + 54.0 + 14.0), vec2(area.width() - 28.0, 26.0));
        let mut clear = false;
        let lines: Vec<_> = remote.console.iter().filter(|l| self.console_filter.is_none_or(|f| l.level == f)).collect();
        region(ui, head, |ui| {
            ui.horizontal(|ui| {
                ui.spacing_mut().item_spacing.x = 10.0;
                widgets::stencil(ui, "Console", 12.0, theme::STENCIL);
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    if Button::new("Clear").icon("trash").show(ui, &mut self.icons).clicked() { clear = true; }
                    if Button::new("Copy").icon("copy").show(ui, &mut self.icons).clicked() {
                        let all: Vec<String> = lines.iter().map(|l| format!("{} {} {}: {}", clock(l.time), l.level.to_uppercase(), l.scope, l.message)).collect();
                        ui.ctx().copy_text(all.join("\n"));
                    }
                    let auto = Button::new("Autoscroll").icon("arrow-line-down");
                    if (if self.autoscroll { auto.prominent() } else { auto }).show(ui, &mut self.icons).clicked() { self.autoscroll ^= true; }
                    let levels: Vec<(String, String)> = ["ALL", "INFO", "OK", "WARN", "ERROR"].iter().map(|l| (l.to_string(), l.to_string())).collect();
                    let current = self.console_filter.map(str::to_uppercase).unwrap_or_else(|| "ALL".into());
                    let mut filter = self.console_filter;
                    widgets::menu_picker(ui, &mut self.icons, "level", Some("funnel"), &current, &levels, |key| {
                        filter = match key { "INFO" => Some("info"), "OK" => Some("ok"), "WARN" => Some("warn"), "ERROR" => Some("error"), _ => None };
                    });
                    self.console_filter = filter;
                });
            });
        });
        let panel = Rect::from_min_max(pos2(area.min.x + 14.0, head.max.y + 14.0), pos2(area.max.x - 14.0, area.max.y - 14.0));
        glass::place(ui.scope_id().with("console-panel"), panel, 14.0, Tint::Dark, 0);
        region(ui, panel.shrink2(vec2(14.0, 8.0)), |ui| {
            egui::ScrollArea::vertical().id_salt("console").auto_shrink([false, false]).stick_to_bottom(self.autoscroll).show_rows(ui, 16.0, lines.len(), |ui, range| {
                ui.spacing_mut().item_spacing.y = 2.0;
                for line in &lines[range] {
                    ui.horizontal(|ui| {
                        ui.spacing_mut().item_spacing.x = 8.0;
                        let mono = |s: &str, size: f32, c: Color32| RichText::new(s).monospace().size(size).color(c);
                        let cell = |ui: &mut Ui, width: f32, label: egui::Label| { ui.allocate_ui_with_layout(vec2(width, 14.0), Layout::left_to_right(Align::Center), |ui| { ui.set_width(width); ui.add(label) }); };
                        cell(ui, 64.0, egui::Label::new(mono(&clock(line.time), 10.0, theme::FAINT)));
                        let (icon, color) = match line.level.as_str() {
                            "error" => ("warning-octagon", theme::ERROR),
                            "warn" => ("warning", Color32::from_rgb(255, 204, 0)),
                            "ok" => ("check-circle", theme::OK),
                            _ => ("info", Color32::from_rgb(10, 132, 255)),
                        };
                        widgets::icon(ui, &mut self.icons, icon, 11.0, color);
                        cell(ui, 130.0, egui::Label::new(mono(&line.scope, 10.0, theme::SECONDARY)).truncate());
                        ui.add(egui::Label::new(mono(&line.message, 11.0, theme::PRIMARY)).truncate());
                    });
                }
            });
        });
        if clear {
            self.engine.remote.lock().unwrap().console.clear();
        }
    }

    // MARK: Settings window

    pub fn settings_ui(&mut self, ui: &mut Ui) {
        let remote = self.engine.remote.clone();
        let remote = remote.lock().unwrap();
        let full = ui.max_rect();
        let bar = ui.interact(Rect::from_min_size(full.min, vec2(full.width(), 86.0)), ui.scope_id().with("settings-bar"), Sense::click_and_drag());
        if bar.drag_started() { self.actions.push(Action::DragSettings); }
        if ui.input(|i| i.key_pressed(egui::Key::Escape)) { self.actions.push(Action::CloseSettings); }
        ui.painter().rect_filled(full, egui::CornerRadius::same(crate::backdrop::CORNER as u8), Color32::from_rgb(30, 30, 30));
        ui.painter().hline(full.x_range(), full.min.y + 86.0, egui::Stroke::new(1.0, Color32::from_black_alpha(140)));
        if let Some(b) = widgets::traffic_lights(ui, full.min + vec2(20.0, 20.0), true) {
            self.actions.push(match b { WindowButton::Close => Action::CloseSettings, _ => Action::MinimizeSettings });
        }
        let windows = remote.state.as_ref().is_some_and(|s| s.os == "Windows");
        let tabs: Vec<Tab> = [Tab::General, Tab::Runner, Tab::Advanced, Tab::About].into_iter().filter(|t| !(windows && *t == Tab::Runner)).collect();
        let title = ui.painter().layout_no_wrap(self.tab.title().into(), theme::body(13.0).clone(), theme::PRIMARY);
        ui.painter().galley(pos2(full.center().x - title.size().x / 2.0, full.min.y + 13.0), title, theme::PRIMARY);
        let tab_w = 62.0;
        let start = full.center().x - tab_w * tabs.len() as f32 / 2.0;
        for (i, tab) in tabs.iter().enumerate() {
            let r = Rect::from_min_size(pos2(start + tab_w * i as f32, full.min.y + 34.0), vec2(tab_w - 4.0, 46.0));
            let resp = ui.interact(r, ui.scope_id().with(("tab", i)), Sense::click());
            let selected = self.tab == *tab;
            if selected || resp.hovered() {
                ui.painter().rect_filled(r, 8.0, Color32::from_white_alpha(if selected { 26 } else { 12 }));
            }
            let color = if selected { Color32::from_rgb(10, 132, 255) } else { theme::SECONDARY };
            self.icons.paint(ui, tab.icon(), Rect::from_center_size(pos2(r.center().x, r.min.y + 15.0), egui::Vec2::splat(20.0)), color);
            let g = ui.painter().layout_no_wrap(tab.title().into(), theme::body(11.0), color);
            ui.painter().galley(pos2(r.center().x - g.size().x / 2.0, r.min.y + 29.0), g, color);
            if resp.clicked() { self.tab = *tab; }
        }
        let body = Rect::from_min_max(pos2(full.min.x, full.min.y + 87.0), full.max);
        let Some(state) = remote.state.as_ref() else { return };
        region(ui, body, |ui| {
            egui::ScrollArea::vertical().id_salt("settings").auto_shrink([false, false]).show(ui, |ui| {
                ui.add_space(20.0);
                ui.horizontal(|ui| {
                    ui.add_space(20.0);
                    ui.vertical(|ui| {
                        ui.set_width(ui.available_width() - 20.0);
                        ui.spacing_mut().item_spacing.y = 18.0;
                        match self.tab {
                            Tab::General => self.general_tab(ui, state),
                            Tab::Runner => self.runner_tab(ui, state),
                            Tab::Advanced => self.advanced_tab(ui, state),
                            Tab::About => self.about_tab(ui, state),
                        }
                    });
                });
                ui.add_space(20.0);
            });
        });
        widgets::window_rim(ui, full);
    }

    fn general_tab(&mut self, ui: &mut Ui, state: &State) {
        let sender = self.sender();
        let icons = &mut self.icons;
        group(ui, |ui| {
            let selected = state.selected();
            form_row(ui, "Active game", |ui| { ui.label(text(selected.map_or("None", |g| g.name.as_str()), 13.0, theme::PRIMARY).strong()); });
            if let Some(game) = selected {
                separator(ui);
                form_row(ui, "Titanfall 2", |ui| { ui.add(egui::Label::new(text(&game.root, 12.0, theme::PRIMARY)).truncate()); });
                separator(ui);
                form_row(ui, "Northstar", |ui| { ui.label(text(game.northstar_version.as_deref().unwrap_or("Not installed"), 13.0, theme::PRIMARY).strong()); });
            }
        });
        group(ui, |ui| {
            let mut first = true;
            for game in &state.games {
                if !first { separator(ui); }
                first = false;
                form_row(ui, &game.name, |ui| {
                    if state.selected().is_some_and(|g| g.id == game.id) {
                        widgets::icon(ui, icons, "check-circle", 15.0, Color32::from_rgb(10, 132, 255));
                    } else if Button::new("Use").show(ui, icons).clicked() {
                        sender.send(json!({ "cmd": "selectGame", "id": game.id }));
                    }
                });
            }
            if !state.games.is_empty() { separator(ui); }
            ui.horizontal(|ui| {
                ui.spacing_mut().item_spacing.x = 10.0;
                if Button::new("Add a game folder…").icon("folder-simple-plus").show(ui, icons).clicked() {
                    let sender = sender.clone();
                    std::thread::spawn(move || {
                        if let Some(path) = rfd::FileDialog::new().set_title("Titanfall 2 folder").pick_folder() {
                            sender.send(json!({ "cmd": "addGameFolder", "path": path }));
                        }
                    });
                }
                if Button::new("Rescan").icon("arrow-clockwise").show(ui, icons).clicked() { sender.cmd("rescan"); }
            });
            ui.label(text(if state.os == "Windows" {
                "Draconis finds Steam, EA app and Epic copies, and folders you add."
            } else {
                "Draconis finds Steam copies (native, Flatpak, Snap), EA app and Epic copies in Draconis or Heroic prefixes, and folders you add."
            }, 11.0, theme::FAINT));
        });
        let mut prefs_changed = false;
        group(ui, |ui| {
            form_row(ui, "Update Northstar automatically", |ui| {
                if widgets::toggle(ui, state.auto_update_northstar).clicked() {
                    sender.send(json!({ "cmd": "setAutoUpdate", "enabled": !state.auto_update_northstar }));
                }
            });
            separator(ui);
            form_row(ui, "Show Console", |ui| {
                if widgets::toggle(ui, self.prefs.show_console).clicked() { self.prefs.show_console ^= true; prefs_changed = true; }
            });
        });
        if prefs_changed { self.save_prefs(); }
        group(ui, |ui| {
            if link_row(ui, &mut self.icons, "folder-simple", "Open the data folder") { let _ = open::that(&state.data_folder); }
            separator(ui);
            if link_row(ui, &mut self.icons, "terminal-window", "Open the logs folder") { let _ = open::that(std::path::Path::new(&state.data_folder).join("Logs")); }
        });
    }

    fn runner_tab(&mut self, ui: &mut Ui, state: &State) {
        let sender = self.sender();
        let busy = state.tool_busy.is_some();
        let icons = &mut self.icons;
        group(ui, |ui| {
            ui.label(text("Steam copies run with the Proton you pick in Steam. Copies in a Wine prefix run with the runner below; Proton goes through umu-launcher.", 12.0, theme::SECONDARY));
            separator(ui);
            form_row(ui, "Runner", |ui| {
                if state.runners.is_empty() {
                    ui.label(text("None found", 13.0, theme::FAINT));
                } else {
                    let options: Vec<(String, String)> = state.runners.iter().map(|r| (r.id.clone(), r.title.clone())).collect();
                    let current = state.runners.iter().find(|r| Some(&r.id) == state.selected_runner.as_ref()).map(|r| r.title.clone()).unwrap_or_else(|| "Choose…".into());
                    widgets::menu_picker(ui, icons, "runner", Some("wine"), &current, &options, |id| sender.send(json!({ "cmd": "selectRunner", "id": id })));
                }
            });
            separator(ui);
            form_row(ui, "umu-launcher", |ui| {
                match &state.umu_path {
                    Some(path) => { ui.add(egui::Label::new(text(path, 12.0, theme::PRIMARY)).truncate()); }
                    None => {
                        if Button::new("Install").icon("download-simple").enabled(!busy).show(ui, icons).clicked() { sender.cmd("installUmu"); }
                    }
                }
            });
            separator(ui);
            form_row(ui, "GE-Proton", |ui| {
                if Button::new("Download latest").icon("download-simple").enabled(!busy).show(ui, icons).clicked() { sender.cmd("installGEProton"); }
            });
            if let Some(tool) = &state.tool_busy {
                separator(ui);
                ui.label(text(tool, 12.0, theme::PRIMARY));
                widgets::progress(ui, state.tool_progress.as_ref().map(|p| p.fraction).filter(|f| *f >= 0.0));
                if let Some(detail) = state.tool_progress.as_ref().and_then(|p| p.detail.as_ref()) { ui.label(text(detail, 11.0, theme::FAINT)); }
            }
        });
        group(ui, |ui| {
            ui.label(RichText::new("EA app / Epic copy").font(theme::title(15.0)).color(theme::PRIMARY));
            ui.label(text("No Steam? Draconis can make its own Wine prefix (in its data folder, never ~/.wine) and install the EA app there. Sign in, install Titanfall 2 from the EA app, then Rescan. Epic owners: link your Epic account in the EA app.", 12.0, theme::SECONDARY));
            let enabled = !busy && state.selected_runner.is_some();
            if Button::new("Create prefix with the EA app").icon("folder-simple-plus").enabled(enabled).show(ui, icons).clicked() { sender.cmd("createPrefix"); }
        });
    }

    fn advanced_tab(&mut self, ui: &mut Ui, state: &State) {
        group(ui, |ui| {
            ui.label(RichText::new("Crash reports").font(theme::title(15.0)).color(theme::PRIMARY));
            let message = match &state.last_crash_report {
                Some(crash) => format!("Last crash report: {crash}. Attach it to a bug report."),
                None => "Draconis writes a report here if it crashes. Attach it to a bug report.".into(),
            };
            ui.label(text(&message, 12.0, theme::SECONDARY));
            if Button::new("Open crash reports").icon("folder-simple").show(ui, &mut self.icons).clicked() { let _ = open::that(&state.crash_folder); }
        });
        group(ui, |ui| {
            ui.label(RichText::new("Logs").font(theme::title(15.0)).color(theme::PRIMARY));
            ui.label(text(&format!("{}/Logs/draconis.log", state.data_folder), 12.0, theme::SECONDARY));
        });
    }

    fn about_tab(&mut self, ui: &mut Ui, state: &State) {
        let sender = self.sender();
        let logo = self.logo(ui.ctx());
        ui.vertical_centered(|ui| {
            ui.spacing_mut().item_spacing.y = 6.0;
            if let Some(logo) = &logo { ui.add(egui::Image::new(logo).fit_to_exact_size(vec2(72.0, 72.0))); }
            ui.label(widgets::tracked("DRACONIS", theme::hero(28.0), theme::PRIMARY, 4.0));
            ui.label(text(&format!("Version {}", state.version), 12.0, theme::SECONDARY));
            ui.label(text(&format!("Open-source Titanfall 2 + Northstar launcher for {}.", state.os), 13.0, theme::PRIMARY));
        });
        ui.horizontal(|ui| {
            ui.spacing_mut().item_spacing.x = 10.0;
            let w = (ui.available_width() - 20.0) / 3.0;
            if Button::new("Report a Bug").icon("bug").width(w).show(ui, &mut self.icons).clicked() { let _ = open::that(&state.issues_page); }
            if Button::new("Releases").icon("download-simple").width(w).show(ui, &mut self.icons).clicked() { let _ = open::that(&state.releases_page); }
            if Button::new("Check for Updates").icon("arrow-clockwise").width(w).show(ui, &mut self.icons).clicked() { sender.cmd("checkForUpdate"); }
        });
        ui.label(text("Licensed under GPL-3.0-or-later. Uses liquid-rust, egui, wgpu and resvg (MIT/Apache-2.0), ZIPFoundation (MIT), swift-crypto (Apache-2.0), the Inter and Roboto Condensed fonts (SIL OFL 1.1) and Phosphor icons (MIT); see THIRD-PARTY-NOTICES.md. umu-launcher (GPL-3.0) and GE-Proton are downloaded only when you ask.", 11.0, theme::FAINT));
    }
}

/// Row height inside a fixed-height list card.
fn row_inner(ui: &Ui) -> f32 {
    (ui.max_rect().height()).max(0.0)
}

fn clock(time: f64) -> String {
    let secs = time as i64 + local_offset_seconds();
    format!("{:02}:{:02}:{:02}", secs / 3600 % 24, secs / 60 % 60, secs % 60)
}

/// Seconds east of UTC, for console timestamps.
fn local_offset_seconds() -> i64 {
    std::env::var("DRACONIS_UTC_OFFSET").ok().and_then(|v| v.parse::<i64>().ok()).map_or(0, |h| h * 3600)
}

fn chip(ui: &mut Ui, title: &str, tint: Tint) {
    let galley = ui.painter().layout_no_wrap(title.to_owned(), theme::body(10.0), tint.ink());
    let (rect, response) = ui.allocate_exact_size(galley.size() + vec2(16.0, 4.0), Sense::hover());
    glass::place(response.id.with(title), rect, 99.0, tint, 2);
    ui.painter().galley(rect.center() - galley.size() / 2.0, galley, tint.ink());
}

/// A `Form(.grouped)` section.
fn group(ui: &mut Ui, add: impl FnOnce(&mut Ui)) {
    egui::Frame::NONE.fill(Color32::from_rgb(40, 40, 42)).corner_radius(10).stroke(egui::Stroke::new(1.0, Color32::from_white_alpha(14))).inner_margin(egui::Margin::symmetric(14, 10)).show(ui, |ui| {
        ui.set_width(ui.available_width());
        ui.spacing_mut().item_spacing.y = 10.0;
        add(ui);
    });
}

fn form_row(ui: &mut Ui, label: &str, value: impl FnOnce(&mut Ui)) {
    ui.horizontal(|ui| {
        ui.set_min_height(24.0);
        ui.label(text(label, 13.0, theme::SECONDARY));
        ui.with_layout(Layout::right_to_left(Align::Center), value);
    });
}

fn separator(ui: &mut Ui) {
    let (rect, _) = ui.allocate_exact_size(vec2(ui.available_width(), 1.0), Sense::hover());
    ui.painter().hline(rect.x_range(), rect.center().y, egui::Stroke::new(1.0, Color32::from_white_alpha(18)));
}

fn link_row(ui: &mut Ui, icons: &mut Icons, icon: &str, title: &str) -> bool {
    let (rect, response) = ui.allocate_exact_size(vec2(ui.available_width(), 30.0), Sense::click());
    if response.hovered() { ui.painter().rect_filled(rect.expand2(vec2(6.0, 0.0)), 6.0, Color32::from_white_alpha(10)); }
    icons.paint(ui, icon, Rect::from_center_size(pos2(rect.min.x + 12.0, rect.center().y), egui::Vec2::splat(15.0)), theme::PRIMARY);
    let g = ui.painter().layout_no_wrap(title.to_owned(), theme::body(13.0), theme::PRIMARY);
    ui.painter().galley(pos2(rect.min.x + 30.0, rect.center().y - g.size().y / 2.0), g, theme::PRIMARY);
    response.clicked()
}
