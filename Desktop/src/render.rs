//! One frame: liquid-rust copies the content (the desktop as the window shows
//! it) into the target and draws the glass over it, then egui paints on top.

use crate::glass::Layer;
use liquid_rust::{Frame, Renderer};

pub struct Painter {
    glass: Renderer,
    egui: egui_wgpu::Renderer,
    content: Option<(wgpu::Texture, wgpu::TextureView, (u32, u32))>,
    changed: bool,
}

impl Painter {
    pub fn new(device: &wgpu::Device, format: wgpu::TextureFormat) -> Self {
        Self {
            glass: Renderer::new(device, format),
            egui: egui_wgpu::Renderer::new(device, format, egui_wgpu::RendererOptions::default()),
            content: None,
            changed: true,
        }
    }

    pub fn has_content(&self, size: (u32, u32)) -> bool {
        self.content.as_ref().is_some_and(|c| c.2 == size)
    }

    /// What the glass refracts: premultiplied RGBA, `size` pixels.
    pub fn set_content(&mut self, device: &wgpu::Device, queue: &wgpu::Queue, size: (u32, u32), pixels: &[u8]) {
        let extent = wgpu::Extent3d { width: size.0, height: size.1, depth_or_array_layers: 1 };
        if !self.has_content(size) {
            let texture = device.create_texture(&wgpu::TextureDescriptor {
                label: Some("content"),
                size: extent,
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format: wgpu::TextureFormat::Rgba8UnormSrgb,
                usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
                view_formats: &[],
            });
            let view = texture.create_view(&Default::default());
            self.content = Some((texture, view, size));
        }
        let texture = &self.content.as_ref().expect("content").0;
        queue.write_texture(
            texture.as_image_copy(),
            pixels,
            wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(4 * size.0), rows_per_image: None },
            extent,
        );
        self.changed = true;
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
        let changed = std::mem::take(&mut self.changed);
        let scale = output.pixels_per_point;
        let jobs = ctx.tessellate(output.shapes, scale);
        for (id, deltas) in &output.textures_delta.set {
            for delta in deltas {
                self.egui.update_texture(device, queue, *id, delta);
            }
        }
        let screen = egui_wgpu::ScreenDescriptor { size_in_pixels: [size.0, size.1], pixels_per_point: scale };
        let mut encoder = device.create_command_encoder(&Default::default());
        let content = &self.content.as_ref().expect("content").1;
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
