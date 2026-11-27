//! The Swift engine (`draconis-engine`, CrossPlatform/Sources/DraconisEngine)
//! holds Draconis's logic. It runs as a child process: commands go to its
//! stdin, state, console lines, mods and servers come back as JSON lines.

use serde::Deserialize;
use serde_json::{Value, json};
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::{Arc, Mutex};

#[derive(Deserialize, Clone, Debug, Default)]
#[serde(rename_all = "camelCase", default)]
pub struct Progress {
    pub fraction: f64,
    pub detail: Option<String>,
}

#[derive(Deserialize, Clone, Debug, Default)]
#[serde(rename_all = "camelCase", default)]
pub struct Game {
    pub id: String,
    pub name: String,
    pub root: String,
    pub folder: String,
    pub kind: String,
    pub has_northstar: bool,
    pub northstar_version: Option<String>,
}

#[derive(Deserialize, Clone, Debug, Default)]
#[serde(default)]
pub struct Runner {
    pub id: String,
    pub title: String,
}

#[derive(Deserialize, Clone, Debug, Default)]
#[serde(default)]
pub struct Mod {
    pub id: String,
    pub name: String,
    pub version: String,
    pub enabled: bool,
}

#[derive(Deserialize, Clone, Debug, Default)]
#[serde(rename_all = "camelCase", default)]
pub struct Package {
    pub full_name: String,
    pub name: String,
    pub owner: String,
    pub version: String,
    pub description: String,
}

#[derive(Deserialize, Clone, Debug, Default)]
#[serde(rename_all = "camelCase", default)]
pub struct Server {
    pub id: String,
    pub name: String,
    pub description: String,
    pub map: String,
    pub playlist: String,
    pub region: Option<String>,
    pub players: i64,
    pub max_players: i64,
    pub password: bool,
}

#[derive(Deserialize, Clone, Debug, Default)]
#[serde(rename_all = "camelCase", default)]
pub struct Vr {
    pub supported: bool,
    pub installed_version: Option<String>,
    pub latest_version: Option<String>,
    pub update_available: bool,
    pub busy: bool,
    pub phase: Option<String>,
    pub progress: Option<f64>,
    pub error: Option<String>,
    #[serde(rename = "steamVRRunning")]
    pub steam_vr_running: bool,
    #[serde(rename = "steamVRInstalled")]
    pub steam_vr_installed: bool,
    pub other_runtime: Option<String>,
    pub active_runtime: Option<String>,
    pub checked: bool,
}

#[derive(Deserialize, Clone, Debug, Default)]
#[serde(rename_all = "camelCase", default)]
pub struct State {
    pub version: String,
    pub os: String,
    pub data_folder: String,
    pub crash_folder: String,
    pub last_crash_report: Option<String>,
    pub releases_page: String,
    pub issues_page: String,
    pub games: Vec<Game>,
    pub selected_game: Option<String>,
    pub runners: Vec<Runner>,
    pub selected_runner: Option<String>,
    pub needs_runner: bool,
    pub umu_path: Option<String>,
    pub scanning: bool,
    pub latest_northstar: Option<String>,
    pub northstar_up_to_date: bool,
    pub northstar_busy: bool,
    pub northstar_progress: Option<Progress>,
    pub launching: bool,
    pub game_running: bool,
    pub status: Option<String>,
    pub error: Option<String>,
    pub installed_mods: Vec<Mod>,
    pub installed_packages: Vec<String>,
    pub mods_loading: bool,
    pub mod_busy: Option<String>,
    pub servers_loading: bool,
    pub tool_busy: Option<String>,
    pub tool_progress: Option<Progress>,
    pub newer_version: Option<String>,
    pub auto_update_northstar: bool,
    pub vr: Vr,
}

impl State {
    pub fn selected(&self) -> Option<&Game> {
        self.selected_game.as_ref().and_then(|id| self.games.iter().find(|g| &g.id == id)).or(self.games.first())
    }
}

#[derive(Deserialize, Clone, Debug)]
pub struct Line {
    pub time: f64,
    pub level: String,
    pub scope: String,
    pub message: String,
}

/// Everything the engine has told the UI so far.
#[derive(Default)]
pub struct Remote {
    pub state: Option<State>,
    pub console: Vec<Line>,
    pub packages: Vec<Package>,
    pub servers: Vec<Server>,
    pub gone: Option<String>,
}

/// Sends commands to the engine; cheap to clone into a dialog thread.
#[derive(Clone, Default)]
pub struct Sender(Arc<Mutex<Option<ChildStdin>>>);

impl Sender {
    pub fn send(&self, command: Value) {
        if let Some(stdin) = self.0.lock().unwrap().as_mut() {
            let _ = writeln!(stdin, "{command}");
            let _ = stdin.flush();
        }
    }

    pub fn cmd(&self, name: &str) {
        self.send(json!({ "cmd": name }));
    }
}

pub struct Engine {
    pub remote: Arc<Mutex<Remote>>,
    pub sender: Sender,
    child: Option<Child>,
}

/// `draconis-engine` next to the UI binary, or `DRACONIS_ENGINE`.
fn engine_path() -> PathBuf {
    if let Some(path) = std::env::var_os("DRACONIS_ENGINE") {
        return path.into();
    }
    let name = if cfg!(windows) { "draconis-engine.exe" } else { "draconis-engine" };
    std::env::current_exe().ok().and_then(|p| p.parent().map(|d| d.join(name))).unwrap_or_else(|| name.into())
}

impl Engine {
    pub fn start(repaint: impl Fn() + Send + 'static) -> Self {
        let remote = Arc::new(Mutex::new(Remote::default()));
        let spawned = Command::new(engine_path()).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn();
        let mut child = match spawned {
            Ok(child) => child,
            Err(err) => {
                remote.lock().unwrap().gone = Some(format!("Couldn't start draconis-engine: {err}"));
                return Self { remote, sender: Sender::default(), child: None };
            }
        };
        let stdout = child.stdout.take().expect("piped stdout");
        let shared = remote.clone();
        std::thread::spawn(move || {
            for line in BufReader::new(stdout).lines() {
                let Ok(line) = line else { break };
                let Ok(message) = serde_json::from_str::<Value>(&line) else { continue };
                let mut remote = shared.lock().unwrap();
                match message["type"].as_str() {
                    Some("state") => match serde_json::from_value::<State>(message["state"].clone()) {
                        Ok(state) => remote.state = Some(state),
                        Err(err) => eprintln!("draconis: unreadable engine state: {err}"),
                    },
                    Some("log") => {
                        if let Ok(line) = serde_json::from_value(message["line"].clone()) {
                            remote.console.push(line);
                            let excess = remote.console.len().saturating_sub(2000);
                            remote.console.drain(..excess);
                        }
                    }
                    Some("packages") => remote.packages = serde_json::from_value(message["packages"].clone()).unwrap_or_default(),
                    Some("servers") => remote.servers = serde_json::from_value(message["servers"].clone()).unwrap_or_default(),
                    _ => {}
                }
                drop(remote);
                repaint();
            }
            shared.lock().unwrap().gone = Some("draconis-engine stopped. See Logs/draconis.log in the data folder.".into());
            repaint();
        });
        Self { remote, sender: Sender(Arc::new(Mutex::new(child.stdin.take()))), child: Some(child) }
    }

    /// For snapshots and look tests: a fixed state, no process.
    pub fn sample() -> Self {
        let remote = Remote { state: Some(sample_state()), ..Default::default() };
        Self { remote: Arc::new(Mutex::new(remote)), sender: Sender::default(), child: None }
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        *self.sender.0.lock().unwrap() = None; // EOF: the engine exits
        if let Some(mut child) = self.child.take() {
            let _ = child.wait();
        }
    }
}

fn sample_state() -> State {
    let game = Game {
        id: "/games/Titanfall2".into(),
        name: "Steam".into(),
        root: "/games/Titanfall2".into(),
        folder: "Titanfall2".into(),
        kind: "steam".into(),
        has_northstar: true,
        northstar_version: Some("1.31.16".into()),
    };
    State {
        version: env!("CARGO_PKG_VERSION").into(),
        os: if cfg!(windows) { "Windows" } else { "Linux" }.into(),
        data_folder: "~/.local/share/draconis".into(),
        releases_page: "https://github.com/AA-EION/Draconis/releases/latest".into(),
        issues_page: "https://github.com/AA-EION/Draconis/issues/new".into(),
        selected_game: Some(game.id.clone()),
        games: vec![game],
        latest_northstar: Some("v1.31.16".into()),
        northstar_up_to_date: true,
        auto_update_northstar: true,
        vr: Vr {
            supported: true,
            installed_version: Some("1.0.33".into()),
            latest_version: Some("1.0.33".into()),
            steam_vr_running: true,
            steam_vr_installed: true,
            checked: true,
            ..Default::default()
        },
        ..Default::default()
    }
}
