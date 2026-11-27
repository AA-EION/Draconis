//! Draconis for Linux and Windows: Liquid Glass (liquid-rust) under an egui
//! interface on wgpu, after the macOS SwiftUI app.
//!
//! `draconis --snapshot out.png [WxH]` renders one frame offscreen.

mod app;
mod engine;
mod glass;
mod render;
mod theme;
mod widgets;

use std::path::PathBuf;
use std::sync::Arc;
use winit::application::ApplicationHandler;
use winit::event::WindowEvent;
use winit::event_loop::{ActiveEventLoop, EventLoop};
use winit::window::{Window, WindowId};

/// Fonts, icons and the logo: next to the binary when installed, the Swift
/// app's resources during development.
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
    ctx.set_visuals(egui::Visuals::dark());
    ctx
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("--snapshot") {
        let out = args.get(1).map_or("draconis.png", String::as_str);
        let size = args.get(2).and_then(|s| s.split_once('x')).and_then(|(w, h)| Some((w.parse().ok()?, h.parse().ok()?))).unwrap_or((1400, 900));
        let section = args.get(3).map(String::as_str);
        let backdrop = args.iter().position(|a| a == "--backdrop").and_then(|i| args.get(i + 1)).map(|p| image::open(p).expect("backdrop image").to_rgba8());
        snapshot(out, size, section.filter(|s| !s.starts_with("--")), backdrop);
        return;
    }
    let event_loop = EventLoop::new().expect("event loop");
    let mut shell = Shell::default();
    event_loop.run_app(&mut shell).expect("run");
}

fn snapshot(out: &str, size: (u32, u32), section: Option<&str>, backdrop: Option<image::RgbaImage>) {
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
    let mut app = app::App::new(resources(), engine::Engine::sample());
    if let Some(name) = section {
        app.section = app::Section::ALL.into_iter().find(|s| format!("{s:?}").eq_ignore_ascii_case(name)).unwrap_or(app.section);
    }
    let mut painter = render::Painter::new(&device, format);
    painter.backdrop_image = backdrop;
    let mut layer = glass::Layer::new();
    let input = || egui::RawInput {
        screen_rect: Some(egui::Rect::from_min_size(egui::Pos2::ZERO, egui::vec2(size.0 as f32, size.1 as f32))),
        ..Default::default()
    };
    let mut output = ctx.run_ui(input(), |ui| app.ui(ui));
    for _ in 0..2 {
        layer.sync();
        let textures = std::mem::take(&mut output.textures_delta.set);
        output = ctx.run_ui(input(), |ui| app.ui(ui));
        for (id, mut earlier) in textures {
            let later = output.textures_delta.set.remove(&id).unwrap_or_default();
            earlier.extend(later);
            output.textures_delta.set.insert(id, earlier);
        }
    }
    layer.sync();
    while layer.scene.update(1.0 / 120.0) {}
    painter.paint(&device, &queue, &view, size, &ctx, output, &layer);
    save(&device, &queue, &target, size, out);
    println!("wrote {out} ({})", adapter.get_info().name);
}

fn save(device: &wgpu::Device, queue: &wgpu::Queue, texture: &wgpu::Texture, size: (u32, u32), out: &str) {
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
        wgpu::TexelCopyBufferInfo {
            buffer: &buffer,
            layout: wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(row), rows_per_image: None },
        },
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
    image.save(out).expect("write PNG");
}

#[derive(Default)]
struct Shell {
    state: Option<Running>,
}

struct Running {
    window: Arc<Window>,
    surface: wgpu::Surface<'static>,
    device: wgpu::Device,
    queue: wgpu::Queue,
    config: wgpu::SurfaceConfiguration,
    ctx: egui::Context,
    input: egui_winit::State,
    painter: render::Painter,
    layer: glass::Layer,
    app: app::App,
    last: std::time::Instant,
}

impl ApplicationHandler for Shell {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.state.is_some() {
            return;
        }
        let attributes = Window::default_attributes()
            .with_title("Draconis")
            .with_inner_size(winit::dpi::LogicalSize::new(1180.0, 760.0))
            .with_min_inner_size(winit::dpi::LogicalSize::new(860.0, 560.0));
        #[cfg(target_os = "linux")]
        let attributes = winit::platform::wayland::WindowAttributesExtWayland::with_name(attributes, "io.github.aa_eion.Draconis", "");
        let window = Arc::new(event_loop.create_window(attributes).expect("window"));
        let instance = wgpu::Instance::new(wgpu::InstanceDescriptor::new_with_display_handle_from_env(Box::new(event_loop.owned_display_handle())));
        let surface = instance.create_surface(window.clone()).expect("surface");
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            compatible_surface: Some(&surface),
            ..Default::default()
        }))
        .expect("GPU adapter");
        let (device, queue) = pollster::block_on(adapter.request_device(&Default::default())).expect("GPU device");
        let caps = surface.get_capabilities(&adapter);
        let format = caps.formats.iter().copied().find(wgpu::TextureFormat::is_srgb).unwrap_or(caps.formats[0]);
        let size = window.inner_size();
        let config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format,
            color_space: wgpu::SurfaceColorSpace::Auto,
            width: size.width.max(1),
            height: size.height.max(1),
            present_mode: wgpu::PresentMode::AutoVsync,
            alpha_mode: caps.alpha_modes[0],
            view_formats: vec![],
            desired_maximum_frame_latency: 2,
        };
        surface.configure(&device, &config);
        let ctx = context();
        let input = egui_winit::State::new(ctx.clone(), egui::ViewportId::ROOT, &window, Some(window.scale_factor() as f32), None, None);
        let painter = render::Painter::new(&device, format);
        // egui asks for frames (animations, engine messages): wake winit.
        let redraw = window.clone();
        ctx.set_request_repaint_callback(move |_| redraw.request_redraw());
        let repaint = ctx.clone();
        let app = app::App::new(resources(), engine::Engine::start(move || repaint.request_repaint()));
        self.state = Some(Running {
            window,
            surface,
            device,
            queue,
            config,
            ctx,
            input,
            painter,
            layer: glass::Layer::new(),
            app,
            last: std::time::Instant::now(),
        });
    }

    fn window_event(&mut self, event_loop: &ActiveEventLoop, _id: WindowId, event: WindowEvent) {
        let Some(state) = self.state.as_mut() else { return };
        let response = state.input.on_window_event(&state.window, &event);
        match event {
            WindowEvent::CloseRequested => event_loop.exit(),
            WindowEvent::Resized(size) => {
                state.config.width = size.width.max(1);
                state.config.height = size.height.max(1);
                state.surface.configure(&state.device, &state.config);
                state.window.request_redraw();
            }
            WindowEvent::RedrawRequested => state.frame(),
            _ => {}
        }
        if response.repaint {
            state.window.request_redraw();
        }
    }
}

impl Running {
    fn frame(&mut self) {
        let input = self.input.take_egui_input(&self.window);
        let output = self.ctx.run_ui(input, |ui| self.app.ui(ui));
        self.input.handle_platform_output(&self.window, output.platform_output.clone());
        self.layer.sync();
        let now = std::time::Instant::now();
        let moving = self.layer.scene.update((now - self.last).as_secs_f32().min(0.05));
        self.last = now;
        let frame = match self.surface.get_current_texture() {
            wgpu::CurrentSurfaceTexture::Success(frame) | wgpu::CurrentSurfaceTexture::Suboptimal(frame) => frame,
            _ => {
                self.surface.configure(&self.device, &self.config);
                self.window.request_redraw();
                return;
            }
        };
        let view = frame.texture.create_view(&Default::default());
        let size = (self.config.width, self.config.height);
        let repaint = output.viewport_output.get(&egui::ViewportId::ROOT).is_some_and(|v| v.repaint_delay.is_zero());
        self.painter.paint(&self.device, &self.queue, &view, size, &self.ctx, output, &self.layer);
        self.queue.present(frame);
        if moving || repaint {
            self.window.request_redraw();
        }
    }
}
