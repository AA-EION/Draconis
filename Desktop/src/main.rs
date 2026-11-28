//! Draconis for Linux and Windows: Liquid Glass (liquid-rust) under an egui
//! interface on wgpu, after the macOS SwiftUI app.
//!
//! `draconis --snapshot out.png [WxH] [page] [--backdrop desktop.png --at X,Y]`
//! renders one frame offscreen over a desktop image; `page` is play, mods,
//! servers, console or settings.

mod app;
mod backdrop;
mod engine;
mod glass;
mod render;
mod theme;
mod widgets;

use app::{Action, App};
use std::path::PathBuf;
use std::sync::Arc;
use winit::application::ApplicationHandler;
use winit::dpi::{LogicalSize, PhysicalPosition};
use winit::event::{ElementState, MouseButton, WindowEvent};
use winit::event_loop::{ActiveEventLoop, EventLoop};
use winit::window::{CursorIcon, ResizeDirection, Window, WindowId};

/// Fonts, icons and the logo: next to the binary when installed, the source tree during development.
fn resources() -> PathBuf {
    let exe = std::env::current_exe().ok().and_then(|p| p.parent().map(|d| d.join("resources")));
    if let Some(dir) = exe.filter(|d| d.is_dir()) {
        return dir;
    }
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("resources")
}

fn context() -> egui::Context {
    let ctx = egui::Context::default();
    ctx.set_fonts(theme::fonts(&resources()));
    let mut visuals = egui::Visuals::dark();
    visuals.selection.bg_fill = egui::Color32::from_rgb(10, 132, 255);
    visuals.window_corner_radius = egui::CornerRadius::same(8);
    ctx.set_visuals(visuals);
    ctx
}

fn arg<'a>(args: &'a [String], flag: &str) -> Option<&'a str> {
    args.iter().position(|a| a == flag).and_then(|i| args.get(i + 1)).map(String::as_str)
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("--snapshot") {
        let out = args.get(1).map_or("draconis.png", String::as_str);
        let size = args.get(2).and_then(|s| s.split_once('x')).and_then(|(w, h)| Some((w.parse().ok()?, h.parse().ok()?))).unwrap_or((980, 672));
        let page = args.get(3).map(String::as_str).filter(|s| !s.starts_with("--")).unwrap_or("play");
        let desktop = arg(&args, "--backdrop").map(|p| image::open(p).expect("backdrop image").to_rgba8());
        let at = arg(&args, "--at").and_then(|s| s.split_once(',')).and_then(|(x, y)| Some((x.parse().ok()?, y.parse().ok()?)));
        snapshot(out, size, page, desktop, at);
        return;
    }
    let event_loop = EventLoop::new().expect("event loop");
    let mut shell = Shell::default();
    event_loop.run_app(&mut shell).expect("run");
}

struct Gpu {
    instance: wgpu::Instance,
    adapter: wgpu::Adapter,
    device: wgpu::Device,
    queue: wgpu::Queue,
}

fn snapshot(out: &str, size: (u32, u32), page: &str, desktop: Option<image::RgbaImage>, at: Option<(i32, i32)>) {
    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor::new_without_display_handle_from_env());
    let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions::default())).expect("GPU adapter");
    let (device, queue) = pollster::block_on(adapter.request_device(&Default::default())).expect("GPU device");
    let format = wgpu::TextureFormat::Rgba8UnormSrgb;
    let target = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("snapshot"),
        size: wgpu::Extent3d { width: size.0, height: size.1, depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });
    let view = target.create_view(&Default::default());
    let ctx = context();
    let mut app = App::new(resources(), engine::Engine::sample());
    app.show_console(true);
    let settings = page == "settings";
    if let Some(section) = app::Section::ALL.into_iter().find(|s| format!("{s:?}").eq_ignore_ascii_case(page)) {
        app.section = section;
    }
    let screen = desktop.as_ref().map_or(size, |d| d.dimensions());
    let origin = at.unwrap_or(((screen.0 as i32 - size.0 as i32) / 2, (screen.1 as i32 - size.1 as i32) / 2));
    let mut painter = render::Painter::new(&device, format);
    let pixels = if settings {
        backdrop::solid(size, 1.0)
    } else {
        let material = desktop.as_ref().map_or_else(|| backdrop::Desktop::fallback(size), |d| backdrop::Desktop::new(d, 1.0));
        material.content(origin, size, 1.0, Some(app::sidebar_panel(size.1 as f32)))
    };
    painter.set_content(&device, &queue, size, &pixels);
    let mut layer = glass::Layer::new();
    let input = || egui::RawInput {
        screen_rect: Some(egui::Rect::from_min_size(egui::Pos2::ZERO, egui::vec2(size.0 as f32, size.1 as f32))),
        ..Default::default()
    };
    let run = |app: &mut App| ctx.run_ui(input(), |ui| if settings { app.settings_ui(ui) } else { app.ui(ui) });
    let mut output = run(&mut app);
    for _ in 0..3 {
        layer.sync();
        let textures = std::mem::take(&mut output.textures_delta.set);
        output = run(&mut app);
        for (id, mut earlier) in textures {
            let later = output.textures_delta.set.remove(&id).unwrap_or_default();
            earlier.extend(later);
            output.textures_delta.set.insert(id, earlier);
        }
    }
    layer.sync();
    while layer.scene.update(1.0 / 120.0) {}
    painter.paint(&device, &queue, &view, size, &ctx, output, &layer);
    let mut image = read_back(&device, &queue, &target, size);
    if let Some(desktop) = &desktop {
        let mut under = image::imageops::crop_imm(desktop, origin.0.max(0) as u32, origin.1.max(0) as u32, size.0, size.1).to_image();
        image::imageops::overlay(&mut under, &image, 0, 0);
        image = under;
    }
    image.save(out).expect("write PNG");
    println!("wrote {out} ({})", adapter.get_info().name);
}

fn read_back(device: &wgpu::Device, queue: &wgpu::Queue, texture: &wgpu::Texture, size: (u32, u32)) -> image::RgbaImage {
    let row = (size.0 * 4).div_ceil(256) * 256;
    let buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: None,
        size: u64::from(row * size.1),
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut encoder = device.create_command_encoder(&Default::default());
    encoder.copy_texture_to_buffer(
        texture.as_image_copy(),
        wgpu::TexelCopyBufferInfo { buffer: &buffer, layout: wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(row), rows_per_image: None } },
        wgpu::Extent3d { width: size.0, height: size.1, depth_or_array_layers: 1 },
    );
    queue.submit([encoder.finish()]);
    buffer.slice(..).map_async(wgpu::MapMode::Read, |_| {});
    device.poll(wgpu::PollType::wait_indefinitely()).expect("GPU finished");
    let data = buffer.slice(..).get_mapped_range().expect("mapped");
    let mut image = image::RgbaImage::new(size.0, size.1);
    for y in 0..size.1 {
        let start = (y * row) as usize;
        image.as_mut()[(y * size.0 * 4) as usize..((y + 1) * size.0 * 4) as usize].copy_from_slice(&data[start..start + (size.0 * 4) as usize]);
    }
    // Premultiplied → straight alpha for PNG.
    for p in image.pixels_mut() {
        if p[3] > 0 && p[3] < 255 {
            for c in 0..3 {
                p[c] = ((p[c] as u32 * 255) / p[3] as u32).min(255) as u8;
            }
        }
    }
    image
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Kind { Main, Settings }

/// One OS window: its surface, egui state and glass layer.
struct View {
    kind: Kind,
    window: Arc<Window>,
    surface: wgpu::Surface<'static>,
    config: wgpu::SurfaceConfiguration,
    ctx: egui::Context,
    input: egui_winit::State,
    painter: render::Painter,
    layer: glass::Layer,
    last: std::time::Instant,
    cursor: PhysicalPosition<f64>,
    /// The desktop under the main window, darkened and blurred.
    desktop: Option<backdrop::Desktop>,
    placed: Option<((i32, i32), (u32, u32), bool)>,
}

#[derive(Default)]
struct Shell {
    gpu: Option<Gpu>,
    app: Option<App>,
    views: Vec<View>,
}

impl Shell {
    fn open(&mut self, event_loop: &ActiveEventLoop, kind: Kind) {
        let (title, size, min) = match kind {
            Kind::Main => ("Draconis", LogicalSize::new(1180.0, 760.0), LogicalSize::new(980.0, 620.0)),
            Kind::Settings => ("Draconis Settings", LogicalSize::new(580.0, 628.0), LogicalSize::new(520.0, 420.0)),
        };
        let attributes = Window::default_attributes()
            .with_title(title)
            .with_inner_size(size)
            .with_min_inner_size(min)
            .with_decorations(false)
            .with_transparent(true);
        #[cfg(target_os = "linux")]
        let attributes = winit::platform::wayland::WindowAttributesExtWayland::with_name(attributes, "io.github.aa_eion.Draconis", "");
        #[cfg(target_os = "linux")]
        let attributes = winit::platform::x11::WindowAttributesExtX11::with_name(attributes, "io.github.aa_eion.Draconis", "draconis");
        let main = self.views.iter().find(|v| v.kind == Kind::Main).map(|v| (v.window.outer_position(), v.window.outer_size()));
        let attributes = match main {
            Some((Ok(p), s)) if kind == Kind::Settings => {
                let scale = event_loop.primary_monitor().map_or(1.0, |m| m.scale_factor());
                let w = (580.0 * scale) as i32;
                attributes.with_position(PhysicalPosition::new(p.x + (s.width as i32 - w) / 2, p.y + (60.0 * scale) as i32))
            }
            _ => attributes,
        };
        let window = Arc::new(event_loop.create_window(attributes).expect("window"));
        if self.gpu.is_none() {
            let instance = wgpu::Instance::new(wgpu::InstanceDescriptor::new_with_display_handle_from_env(Box::new(event_loop.owned_display_handle())));
            let surface = instance.create_surface(window.clone()).expect("surface");
            let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions { compatible_surface: Some(&surface), ..Default::default() })).expect("GPU adapter");
            let (device, queue) = pollster::block_on(adapter.request_device(&Default::default())).expect("GPU device");
            self.gpu = Some(Gpu { instance, adapter, device, queue });
            drop(surface);
        }
        let gpu = self.gpu.as_ref().expect("gpu");
        let surface = gpu.instance.create_surface(window.clone()).expect("surface");
        let caps = surface.get_capabilities(&gpu.adapter);
        let format = caps.formats.iter().copied().find(wgpu::TextureFormat::is_srgb).unwrap_or(caps.formats[0]);
        // Rounded corners need a see-through surface; without one they come out black.
        let alpha_mode = [wgpu::CompositeAlphaMode::PreMultiplied, wgpu::CompositeAlphaMode::PostMultiplied]
            .into_iter().find(|m| caps.alpha_modes.contains(m)).unwrap_or(caps.alpha_modes[0]);
        let size = window.inner_size();
        let config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format,
            color_space: wgpu::SurfaceColorSpace::Auto,
            width: size.width.max(1),
            height: size.height.max(1),
            present_mode: wgpu::PresentMode::AutoVsync,
            alpha_mode,
            view_formats: vec![],
            desired_maximum_frame_latency: 2,
        };
        surface.configure(&gpu.device, &config);
        let ctx = context();
        let input = egui_winit::State::new(ctx.clone(), egui::ViewportId::ROOT, &window, Some(window.scale_factor() as f32), None, None);
        let redraw = window.clone();
        ctx.set_request_repaint_callback(move |_| redraw.request_redraw());
        if self.app.is_none() {
            let repaint = ctx.clone();
            self.app = Some(App::new(resources(), engine::Engine::start(move || repaint.request_repaint())));
        }
        let desktop = (kind == Kind::Main).then(|| desktop_for(&window));
        self.views.push(View {
            kind,
            window,
            surface,
            config,
            ctx,
            input,
            painter: render::Painter::new(&gpu.device, format),
            layer: glass::Layer::new(),
            last: std::time::Instant::now(),
            cursor: PhysicalPosition::new(0.0, 0.0),
            desktop,
            placed: None,
        });
    }

    fn act(&mut self, event_loop: &ActiveEventLoop, actions: Vec<Action>) {
        let find = |views: &[View], kind| views.iter().position(|v| v.kind == kind);
        for action in actions {
            let main = find(&self.views, Kind::Main);
            let settings = find(&self.views, Kind::Settings);
            match action {
                Action::Close => event_loop.exit(),
                Action::Minimize => if let Some(i) = main { self.views[i].window.set_minimized(true) },
                Action::Zoom => if let Some(i) = main { let w = &self.views[i].window; w.set_maximized(!w.is_maximized()) },
                Action::Drag => if let Some(i) = main { let _ = self.views[i].window.drag_window(); },
                Action::DragSettings => if let Some(i) = settings { let _ = self.views[i].window.drag_window(); },
                Action::MinimizeSettings => if let Some(i) = settings { self.views[i].window.set_minimized(true) },
                Action::OpenSettings => match settings {
                    Some(i) => self.views[i].window.focus_window(),
                    None => self.open(event_loop, Kind::Settings),
                },
                Action::CloseSettings => if let Some(i) = settings { self.views.remove(i); },
            }
        }
    }
}

/// The wallpaper, or the fixed backdrop, as the window's material.
fn desktop_for(window: &Window) -> backdrop::Desktop {
    let monitor = window.current_monitor().map(|m| (m.size().width, m.size().height)).unwrap_or((1920, 1080));
    let scale = window.scale_factor() as f32;
    match backdrop::wallpaper(monitor) {
        Some(image) => backdrop::Desktop::new(&image, scale),
        None => backdrop::Desktop::fallback(monitor),
    }
}

/// Which edge of a borderless window the pointer is on, for resizing.
fn edge(window: &Window, p: PhysicalPosition<f64>) -> Option<ResizeDirection> {
    if window.is_maximized() {
        return None;
    }
    let size = window.inner_size();
    let m = 6.0 * window.scale_factor();
    let (l, r, t, b) = (p.x < m, p.x > size.width as f64 - m, p.y < m, p.y > size.height as f64 - m);
    Some(match (l, r, t, b) {
        (true, _, true, _) => ResizeDirection::NorthWest,
        (_, true, true, _) => ResizeDirection::NorthEast,
        (true, _, _, true) => ResizeDirection::SouthWest,
        (_, true, _, true) => ResizeDirection::SouthEast,
        (true, ..) => ResizeDirection::West,
        (_, true, ..) => ResizeDirection::East,
        (_, _, true, _) => ResizeDirection::North,
        (.., true) => ResizeDirection::South,
        _ => return None,
    })
}

impl ApplicationHandler for Shell {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.views.is_empty() {
            self.open(event_loop, Kind::Main);
        }
    }

    fn window_event(&mut self, event_loop: &ActiveEventLoop, id: WindowId, event: WindowEvent) {
        let Some(index) = self.views.iter().position(|v| v.window.id() == id) else { return };
        let (Some(gpu), Some(app)) = (self.gpu.as_ref(), self.app.as_mut()) else { return };
        let view = &mut self.views[index];
        let mut resize = None;
        match &event {
            WindowEvent::CursorMoved { position, .. } => {
                view.cursor = *position;
                if let Some(dir) = edge(&view.window, *position) {
                    view.window.set_cursor(CursorIcon::from(dir));
                }
            }
            WindowEvent::MouseInput { state: ElementState::Pressed, button: MouseButton::Left, .. } => resize = edge(&view.window, view.cursor),
            _ => {}
        }
        if let Some(dir) = resize {
            let _ = view.window.drag_resize_window(dir);
            return;
        }
        let response = view.input.on_window_event(&view.window, &event);
        match event {
            WindowEvent::CloseRequested => {
                if view.kind == Kind::Main { event_loop.exit() } else { self.views.remove(index); }
                return;
            }
            WindowEvent::Focused(focused) if view.kind == Kind::Main => app.focused = focused,
            WindowEvent::Resized(size) => {
                view.config.width = size.width.max(1);
                view.config.height = size.height.max(1);
                view.surface.configure(&gpu.device, &view.config);
                view.window.request_redraw();
            }
            WindowEvent::Moved(_) => view.window.request_redraw(),
            WindowEvent::RedrawRequested => {
                view.frame(gpu, app);
                let actions = std::mem::take(&mut app.actions);
                if !actions.is_empty() {
                    self.act(event_loop, actions);
                }
                return;
            }
            _ => {}
        }
        if response.repaint {
            view.window.request_redraw();
        }
    }
}

impl View {
    /// Rebuild the content when the window moved or changed size.
    fn place(&mut self, gpu: &Gpu, sidebar: bool) {
        let size = (self.config.width, self.config.height);
        let origin = match (self.window.inner_position(), self.window.current_monitor()) {
            (Ok(p), Some(m)) => (p.x - m.position().x, p.y - m.position().y),
            // Wayland doesn't say where the window is: centre it on the wallpaper.
            (_, Some(m)) => ((m.size().width as i32 - size.0 as i32) / 2, (m.size().height as i32 - size.1 as i32) / 2),
            _ => (0, 0),
        };
        if self.placed == Some((origin, size, sidebar)) && self.painter.has_content(size) {
            return;
        }
        self.placed = Some((origin, size, sidebar));
        let scale = self.window.scale_factor() as f32;
        let panel = sidebar.then(|| app::sidebar_panel(size.1 as f32 / scale));
        let pixels = match &self.desktop {
            Some(desktop) => desktop.content(origin, size, scale, panel),
            None => backdrop::solid(size, scale),
        };
        self.painter.set_content(&gpu.device, &gpu.queue, size, &pixels);
    }

    fn frame(&mut self, gpu: &Gpu, app: &mut App) {
        self.place(gpu, !app.sidebar_hidden);
        let input = self.input.take_egui_input(&self.window);
        let kind = self.kind;
        let output = self.ctx.run_ui(input, |ui| if kind == Kind::Main { app.ui(ui) } else { app.settings_ui(ui) });
        self.input.handle_platform_output(&self.window, output.platform_output.clone());
        self.layer.sync();
        let now = std::time::Instant::now();
        let moving = self.layer.scene.update((now - self.last).as_secs_f32().min(0.05));
        self.last = now;
        let frame = match self.surface.get_current_texture() {
            wgpu::CurrentSurfaceTexture::Success(frame) | wgpu::CurrentSurfaceTexture::Suboptimal(frame) => frame,
            _ => {
                self.surface.configure(&gpu.device, &self.config);
                self.window.request_redraw();
                return;
            }
        };
        let view = frame.texture.create_view(&Default::default());
        let size = (self.config.width, self.config.height);
        let repaint = output.viewport_output.get(&egui::ViewportId::ROOT).is_some_and(|v| v.repaint_delay.is_zero());
        self.painter.paint(&gpu.device, &gpu.queue, &view, size, &self.ctx, output, &self.layer);
        gpu.queue.present(frame);
        if moving || repaint {
            self.window.request_redraw();
        }
    }
}
