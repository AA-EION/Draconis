//! One frame, see-through like the macOS window.
//!
//! liquid-rust's glass treats its backdrop as opaque, and the desktop behind
//! the window can't be read. So each frame is drawn twice: once over black,
//! once over a grey backdrop whose level is how much of the desktop each part
//! of the window lets through (`backdrop.rs`). The black pass is what the
//! surfaces add; the difference between the passes is what they let through,
//! glass tones included. A last pass writes that as premultiplied colour and
//! alpha, and the compositor puts the real desktop (blurred where it can) behind.

use crate::glass::Layer;
use liquid_rust::{Frame, Renderer};

const OFFSCREEN: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8UnormSrgb;

const COMBINE: &str = r#"
@group(0) @binding(0) var over_black: texture_2d<f32>;
@group(0) @binding(1) var over_grey: texture_2d<f32>;

@vertex fn vs(@builtin(vertex_index) i: u32) -> @builtin(position) vec4f {
    let p = vec2f(f32((i << 1u) & 2u), f32(i & 2u));
    return vec4f(p * 2.0 - 1.0, 0.0, 1.0);
}

fn premultiplied(pos: vec4f) -> vec4f {
    let p = vec2i(pos.xy);
    let a = textureLoad(over_black, p, 0).rgb;
    let b = textureLoad(over_grey, p, 0).rgb;
    let alpha = 1.0 - clamp(dot(b - a, vec3f(1.0 / 3.0)), 0.0, 1.0);
    return vec4f(min(a, vec3f(alpha)), alpha);
}

fn linear(c: vec3f) -> vec3f {
    return select(pow((c + 0.055) / 1.055, vec3f(2.4)), c / 12.92, c <= vec3f(0.04045));
}

@fragment fn fs_raw(@builtin(position) pos: vec4f) -> @location(0) vec4f {
    return premultiplied(pos);
}

@fragment fn fs_srgb(@builtin(position) pos: vec4f) -> @location(0) vec4f {
    let c = premultiplied(pos);
    return vec4f(linear(c.rgb), c.a);
}
"#;

/// A pass's content (backdrop) and the offscreen frame drawn over it.
struct Pass {
    glass: Renderer,
    content: wgpu::Texture,
    frame: wgpu::Texture,
}

pub struct Painter {
    egui: egui_wgpu::Renderer,
    combine: wgpu::RenderPipeline,
    layout: wgpu::BindGroupLayout,
    passes: Option<[Pass; 2]>,
    size: (u32, u32),
    changed: bool,
}

fn texture(device: &wgpu::Device, size: (u32, u32), usage: wgpu::TextureUsages) -> wgpu::Texture {
    device.create_texture(&wgpu::TextureDescriptor {
        label: None,
        size: wgpu::Extent3d { width: size.0, height: size.1, depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: OFFSCREEN,
        usage,
        view_formats: &[wgpu::TextureFormat::Rgba8Unorm],
    })
}

/// The encoded bytes, unconverted: the compositor blends encoded values.
fn raw(texture: &wgpu::Texture) -> wgpu::TextureView {
    texture.create_view(&wgpu::TextureViewDescriptor { format: Some(wgpu::TextureFormat::Rgba8Unorm), ..Default::default() })
}

impl Painter {
    pub fn new(device: &wgpu::Device, format: wgpu::TextureFormat) -> Self {
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor { label: Some("combine"), source: wgpu::ShaderSource::Wgsl(COMBINE.into()) });
        let entry = |binding| wgpu::BindGroupLayoutEntry {
            binding,
            visibility: wgpu::ShaderStages::FRAGMENT,
            ty: wgpu::BindingType::Texture { sample_type: wgpu::TextureSampleType::Float { filterable: false }, view_dimension: wgpu::TextureViewDimension::D2, multisampled: false },
            count: None,
        };
        let layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor { label: None, entries: &[entry(0), entry(1)] });
        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: None, bind_group_layouts: &[Some(&layout)], immediate_size: 0 });
        let combine = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("combine"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState { module: &shader, entry_point: Some("vs"), buffers: &[], compilation_options: Default::default() },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some(if format.is_srgb() { "fs_srgb" } else { "fs_raw" }),
                targets: &[Some(wgpu::ColorTargetState { format, blend: None, write_mask: wgpu::ColorWrites::ALL })],
                compilation_options: Default::default(),
            }),
            primitive: Default::default(),
            depth_stencil: None,
            multisample: Default::default(),
            multiview_mask: None,
            cache: None,
        });
        Self {
            egui: egui_wgpu::Renderer::new(device, OFFSCREEN, egui_wgpu::RendererOptions::default()),
            combine,
            layout,
            passes: None,
            size: (0, 0),
            changed: true,
        }
    }

    pub fn has_content(&self, size: (u32, u32)) -> bool {
        self.passes.is_some() && self.size == size
    }

    /// The two backdrops (sRGB bytes, `size` pixels): black, and the see-through levels.
    pub fn set_content(&mut self, device: &wgpu::Device, queue: &wgpu::Queue, size: (u32, u32), black: &[u8], grey: &[u8]) {
        if !self.has_content(size) {
            let pass = || Pass {
                glass: Renderer::new(device, OFFSCREEN),
                content: texture(device, size, wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST),
                frame: texture(device, size, wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING),
            };
            self.passes = Some([pass(), pass()]);
            self.size = size;
        }
        let extent = wgpu::Extent3d { width: size.0, height: size.1, depth_or_array_layers: 1 };
        for (pass, pixels) in self.passes.as_ref().expect("passes").iter().zip([black, grey]) {
            queue.write_texture(
                pass.content.as_image_copy(),
                pixels,
                wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(4 * size.0), rows_per_image: None },
                extent,
            );
        }
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
        let commands = self.egui.update_buffers(device, queue, &mut encoder, &jobs, &screen);
        let passes = self.passes.as_mut().expect("content");
        for pass in passes.iter_mut() {
            let content = pass.content.create_view(&Default::default());
            let frame = pass.frame.create_view(&Default::default());
            pass.glass.render(device, queue, &mut encoder, &Frame { content: &content, target: &frame, size, scale, content_changed: changed }, &layer.scene);
            let mut labels = encoder
                .begin_render_pass(&wgpu::RenderPassDescriptor {
                    label: Some("labels"),
                    color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                        view: &frame,
                        depth_slice: None,
                        resolve_target: None,
                        ops: wgpu::Operations { load: wgpu::LoadOp::Load, store: wgpu::StoreOp::Store },
                    })],
                    ..Default::default()
                })
                .forget_lifetime();
            self.egui.render(&mut labels, &jobs, &screen);
        }
        let bind = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: None,
            layout: &self.layout,
            entries: &[
                wgpu::BindGroupEntry { binding: 0, resource: wgpu::BindingResource::TextureView(&raw(&passes[0].frame)) },
                wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::TextureView(&raw(&passes[1].frame)) },
            ],
        });
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("combine"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: target,
                    depth_slice: None,
                    resolve_target: None,
                    ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color::TRANSPARENT), store: wgpu::StoreOp::Store },
                })],
                ..Default::default()
            });
            pass.set_pipeline(&self.combine);
            pass.set_bind_group(0, &bind, &[]);
            pass.draw(0..3, 0..1);
        }
        queue.submit(commands.into_iter().chain([encoder.finish()]));
        for id in &output.textures_delta.free {
            self.egui.free_texture(id);
        }
    }
}
