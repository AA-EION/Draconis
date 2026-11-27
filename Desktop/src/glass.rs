//! Widgets record where their glass goes while egui lays out a frame; the
//! liquid-rust scene follows those records, and the glass is drawn before
//! egui paints the labels on top.

use crate::theme::Tint;
use liquid_rust::{Glass, GlassId, Rect, Scene, Shape};
use std::cell::RefCell;
use std::collections::HashMap;

#[derive(Clone, Copy, PartialEq, Debug)]
pub struct Spec {
    pub rect: egui::Rect,
    pub radius: f32,
    pub tint: Tint,
    pub z: i32,
}

thread_local! {
    static FRAME: RefCell<Vec<(egui::Id, Spec)>> = const { RefCell::new(Vec::new()) };
}

/// Place glass of `tint` behind `rect` this frame. `radius >= 99` is a capsule.
pub fn place(id: egui::Id, rect: egui::Rect, radius: f32, tint: Tint, z: i32) {
    FRAME.with(|f| f.borrow_mut().push((id, Spec { rect, radius, tint, z })));
}

fn shape(radius: f32) -> Shape {
    if radius >= 99.0 { Shape::Capsule } else { Shape::Rounded(radius) }
}

fn rect(r: egui::Rect) -> Rect {
    Rect::new(r.min.x, r.min.y, r.width(), r.height())
}

/// The liquid-rust scene, kept in step with what egui laid out.
pub struct Layer {
    pub scene: Scene,
    live: HashMap<egui::Id, (GlassId, Spec)>,
}

impl Layer {
    pub fn new() -> Self {
        let mut scene = Scene::new();
        scene.appearance.dark = true;
        // Labels follow the dark scheme, so small glass must not flip to light.
        scene.appearance.adapt_to_content = false;
        Self { scene, live: HashMap::new() }
    }

    /// Apply this frame's records: add new glass, move or restyle the rest,
    /// drop what wasn't laid out.
    pub fn sync(&mut self) {
        let frame = FRAME.with(|f| std::mem::take(&mut *f.borrow_mut()));
        let mut seen = HashMap::with_capacity(frame.len());
        for (id, spec) in frame {
            seen.insert(id, ());
            match self.live.get_mut(&id) {
                Some((glass, old)) => {
                    if old.rect != spec.rect {
                        self.scene.place(*glass, rect(spec.rect));
                    }
                    if old.tint != spec.tint {
                        self.scene.set_material(*glass, spec.tint.material());
                    }
                    if old.radius != spec.radius {
                        self.scene.set_shape(*glass, shape(spec.radius));
                    }
                    *old = spec;
                }
                None => {
                    let glass = self.scene.add(
                        Glass::new(rect(spec.rect)).shape(shape(spec.radius)).material(spec.tint.material()).z(spec.z),
                    );
                    self.live.insert(id, (glass, spec));
                }
            }
        }
        let stale: Vec<_> = self.live.keys().filter(|id| !seen.contains_key(*id)).copied().collect();
        for id in stale {
            if let Some((glass, _)) = self.live.remove(&id) {
                self.scene.remove(glass);
            }
        }
    }
}
