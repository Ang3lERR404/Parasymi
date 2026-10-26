//! the engine under Parasymi: what any game made of procedural meshes on
//! Vulkan 1.3 can stand on, by layer (import only downward). A game reaches
//! it as `@import("engine")` and hands the generic parts (`render.renderer`,
//! `world.World`) a namespace describing itself.
//!   core      math, colour, rng, noise, registry, jobs, text, png
//!   platform  input, display (fullscreen)
//!   anim      joint turns, two-bone IK, skinning matrices, keyframed clips
//!   gfx       Vulkan context, swapchain, buffers, pipelines, mesh layouts, mesh builder, SDF sculpting, growth splines
//!   world     the chunk grid and the streamed chunk map
//!   render    frame orchestration and passes, post (bloom, AA), light, camera
//!   ui        SDF draw batch, font

/// the libraries underneath, for the game's own Vulkan and windowing code
pub const vk = @import("vulkan");
pub const glfw = @import("zglfw");

pub const core = struct {
  pub const math = @import("core/math.zig");
  pub const color = @import("core/color.zig");
  pub const rng = @import("core/rng.zig");
  pub const noise = @import("core/noise.zig");
  pub const registry = @import("core/registry.zig");
  pub const jobs = @import("core/jobs.zig");
  pub const text = @import("core/text.zig");
  pub const png = @import("core/png.zig");
};

pub const platform = struct {
  pub const input = @import("platform/input.zig");
  pub const display = @import("platform/display.zig");
};

pub const anim = struct {
  pub const rig = @import("anim/rig.zig");
  pub const clip = @import("anim/clip.zig");
};

pub const gfx = struct {
  pub const ctx = @import("gfx/ctx.zig");
  pub const swapchain = @import("gfx/swapchain.zig");
  pub const buffer = @import("gfx/buffer.zig");
  pub const pipeline = @import("gfx/pipeline.zig");
  pub const vertex = @import("gfx/vertex.zig");
  pub const meshgen = @import("gfx/meshgen.zig");
  pub const sculpt = @import("gfx/sculpt.zig");
  pub const growth = @import("gfx/growth.zig");
};

pub const world = struct {
  pub const chunk = @import("world/chunk.zig");
  /// the streamed chunk map, over a game's land (see world/world.zig)
  pub const World = @import("world/world.zig").World;
};

pub const render = struct {
  pub const renderer = @import("render/renderer.zig");
  pub const post = @import("render/post.zig");
  pub const light = @import("render/light.zig");
  pub const camera = @import("render/camera.zig");
};

pub const ui = struct {
  pub const draw = @import("ui/draw.zig");
  pub const font = @import("ui/font.zig");
};

/// the shadow casters' fragment shader (depth alone), for a game's shadow passes
pub const shadow_frag = @embedFile("shadow.frag");

test {
  _ = core.math;
  _ = core.color;
  _ = core.rng;
  _ = core.noise;
  _ = core.registry;
  _ = core.jobs;
  _ = core.text;
  _ = core.png;
  _ = platform.input;
  _ = anim.rig;
  _ = anim.clip;
  _ = gfx.meshgen;
  _ = gfx.sculpt;
  _ = gfx.growth;
  _ = world.chunk;
  _ = @import("world/world.zig");
  _ = render.camera;
  _ = render.light;
  _ = ui.draw;
}
