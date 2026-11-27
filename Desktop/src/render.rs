//! One frame: the window background goes into a content texture, liquid-rust
//! draws the glass over it into the target, then egui paints the labels on top.

use crate::glass::Layer;
use liquid_rust::{Frame, Renderer};

pub struct Painter {
    pub format: wgpu::TextureFormat,
    glass: Renderer,
    egui: egui_wgpu::Renderer,
    background: Option<(wgpu::Texture, wgpu::TextureView, (u32, u32))>,
    /// An image to put behind the glass instead of the lit backdrop (look tests).
    pub backdrop_image: Option<image::RgbaImage>,
}

/// The lit dark backdrop behind the glass: cool light from the top left, a
/// faint violet glow bottom right, as macOS tints a dark desktop.
fn backdrop(w: u32, h: u32) -> Vec<u8> {
    let mut px = Vec::with_capacity((w * h * 4) as usize);
    let glow = |x: f32, y: f32, cx: f32, cy: f32, r: f32| (1.0 - ((x - cx).powi(2) + (y - cy).powi(2)).sqrt() / r).max(0.0).powf(1.6);
    for y in 0..h {
        for x in 0..w {
            let (u, v) = (x as f32 / w as f32, y as f32 / h as f32);
            let aspect = w as f32 / h as f32;
            let base = [0.086 - 0.05 * v, 0.106 - 0.06 * v, 0.133 - 0.07 * v];
            let a = glow(u * aspect, v, 0.0, 0.0, 1.1) * 0.22;
            let b = glow(u * aspect, v, aspect, 1.0, 0.9) * 0.14;
            let c = glow(u * aspect, v, aspect * 0.55, 0.35, 0.5) * 0.05;
            let rgb = [
                base[0] + a * 0.50 + b * 0.57 + c * 0.6,
                base[1] + a * 0.61 + b * 0.50 + c * 0.7,
                base[2] + a * 0.77 + b * 0.80 + c * 0.9,
            ];
            for channel in rgb {
                px.push((channel.clamp(0.0, 1.0) * 255.0) as u8);
            }
            px.push(255);
        }
    }
    px
}

impl Painter {
    pub fn new(device: &wgpu::Device, format: wgpu::TextureFormat) -> Self {
        Self {
            format,
            glass: Renderer::new(device, format),
            egui: egui_wgpu::Renderer::new(device, format, egui_wgpu::RendererOptions::default()),
            background: None,
            backdrop_image: None,
        }
    }

    fn background(&mut self, device: &wgpu::Device, queue: &wgpu::Queue, size: (u32, u32)) -> bool {
        if self.background.as_ref().is_some_and(|b| b.2 == size) {
            return false;
        }
        let extent = wgpu::Extent3d { width: size.0, height: size.1, depth_or_array_layers: 1 };
        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("backdrop"),
            size: extent,
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Rgba8UnormSrgb,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        let pixels = match &self.backdrop_image {
            Some(image) => image::imageops::resize(image, size.0, size.1, image::imageops::FilterType::Triangle).into_raw(),
            None => backdrop(size.0, size.1),
        };
        queue.write_texture(
            texture.as_image_copy(),
            &pixels,
            wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(4 * size.0), rows_per_image: None },
            extent,
        );
        let view = texture.create_view(&Default::default());
        self.background = Some((texture, view, size));
        true
    }

    /// Draw one frame of `output` (from `ctx.run`) into `target`.
    pub fn paint(
        &mut self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        target: &wgpu::TextureView,
        size: (u32, u32),
        ctx: &egui::Context,
        output: egui::FullOutput,
        layer: &Layer,
    ) {
        let changed = self.background(device, queue, size);
        let scale = output.pixels_per_point;
        let jobs = ctx.tessellate(output.shapes, scale);
        for (id, deltas) in &output.textures_delta.set {
            for delta in deltas {
                self.egui.update_texture(device, queue, *id, delta);
            }
        }
        let screen = egui_wgpu::ScreenDescriptor { size_in_pixels: [size.0, size.1], pixels_per_point: scale };
        let mut encoder = device.create_command_encoder(&Default::default());
        let content = &self.background.as_ref().expect("backdrop").1;
        self.glass.render(device, queue, &mut encoder, &Frame { content, target, size, scale, content_changed: changed }, &layer.scene);
        let commands = self.egui.update_buffers(device, queue, &mut encoder, &jobs, &screen);
        {
            let mut pass = encoder
                .begin_render_pass(&wgpu::RenderPassDescriptor {
                    label: Some("labels"),
                    color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                        view: target,
                        depth_slice: None,
                        resolve_target: None,
                        ops: wgpu::Operations { load: wgpu::LoadOp::Load, store: wgpu::StoreOp::Store },
                    })],
                    ..Default::default()
                })
                .forget_lifetime();
            self.egui.render(&mut pass, &jobs, &screen);
        }
        queue.submit(commands.into_iter().chain([encoder.finish()]));
        for id in &output.textures_delta.free {
            self.egui.free_texture(id);
        }
    }
}
