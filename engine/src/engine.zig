//! the engine under Parasymi: what any game made of procedural meshes on
//! Vulkan 1.3 can stand on, by layer (import only downward). A game reaches
//! it as `@import("engine")` and hands the generic parts (`render.renderer`,
//! `world.World`) a namespace describing itself.
//!   core      math, colour, rng, noise, registry, jobs, text, png, dsp
//!   platform  input, display (fullscreen), audio (WASAPI output)
//!   anim      joint turns, two-bone IK, skinning matrices, keyframed clips
//!   gfx       Vulkan context, swapchain, buffers, pipelines, mesh layouts, mesh builder, SDF sculpting, growth splines
//!   world     the chunk grid and the streamed chunk map
//!   render    frame orchestration and passes, post (bloom, AA), light, camera
//!   ui        SDF draw batch, font, layout boxes
/// Vulkan bindings (vulkan-zig), for the game's own Vulkan code
pub const vk=@import("vulkan");
/// GLFW windows and input (zglfw), for the game's own windowing code
pub const glfw=@import("zglfw");
/// Windows audio (WASAPI), for the game's own audio code
pub const wasapi=@import("wasapi");
/// the bottom layer: pure maths and helpers nothing else depends under
pub const core=struct{
  /// vectors, matrices, quaternions, easing: all the maths
  pub const math=@import("core/math.zig");
  /// colour conversions between spaces and packings
  pub const color=@import("core/color.zig");
  /// seeded, repeatable random numbers
  pub const rng=@import("core/rng.zig");
  /// smooth value noise and its layered fractal sum
  pub const noise=@import("core/noise.zig");
  /// the registry helpers: one module per thing, an enum over them, dispatch
  pub const registry=@import("core/registry.zig");
  /// even work spread over threads, identical to running it serially
  pub const jobs=@import("core/jobs.zig");
  /// the strings file: player-facing text read from a cfg
  pub const text=@import("core/text.zig");
  /// a tiny PNG writer, for screenshots
  pub const png=@import("core/png.zig");
  /// sound shaping: oscillators, envelopes, filters, voices
  pub const dsp=@import("core/dsp.zig");
};
/// what touches the machine: keys, the screen, the speakers
pub const platform=struct{
  /// keys and mouse buttons as actions bound from a cfg
  pub const input=@import("platform/input.zig");
  /// windowed and fullscreen switching
  pub const display=@import("platform/display.zig");
  /// sound out through WASAPI, fed from a mixing callback
  pub const audio=@import("platform/audio.zig");
};
/// what moves a skinned body: joints, IK and keyed clips
pub const anim=struct{
  /// joint turns, two-bone IK and skinning matrices
  pub const rig=@import("anim/rig.zig");
  /// keyframed clips, sampled and saved as text
  pub const clip=@import("anim/clip.zig");
};
/// the Vulkan base and the mesh tools built on it
pub const gfx=struct{
  /// the Vulkan instance, device and queues
  pub const ctx=@import("gfx/ctx.zig");
  /// the swapchain the frames are shown through
  pub const swapchain=@import("gfx/swapchain.zig");
  /// GPU buffers and their memory
  pub const buffer=@import("gfx/buffer.zig");
  /// graphics pipelines and their layouts
  pub const pipeline=@import("gfx/pipeline.zig");
  /// vertex layouts: mesh, UI and light
  pub const vertex=@import("gfx/vertex.zig");
  /// the mesh builder and its primitives
  pub const meshgen=@import("gfx/meshgen.zig");
  /// SDF sculpting: forms melted into one surface
  pub const sculpt=@import("gfx/sculpt.zig");
  /// growth splines: how grown things unfurl over time
  pub const growth=@import("gfx/growth.zig");
};
/// the land in chunks, streamed around the player
pub const world=struct{
  /// the chunk grid: sizes and coordinates
  pub const chunk=@import("world/chunk.zig");
  /// the streamed chunk map, over a game's land (see world/world.zig)
  pub const World=@import("world/world.zig").World;
};
/// drawing a frame: passes, post effects, light, camera
pub const render=struct{
  /// the generic frame orchestration a game fills with its passes
  pub const renderer=@import("render/renderer.zig");
  /// post effects: bloom and antialiasing
  pub const post=@import("render/post.zig");
  /// the sun's light and its shadow cascades
  pub const light=@import("render/light.zig");
  /// the air: the overhead map, the volume and its composite
  pub const volume=@import("render/volume.zig");
  /// the camera: orbit, first person and free
  pub const camera=@import("render/camera.zig");
};
/// the HUD's tools: shapes, letters, boxes
pub const ui=struct{
  /// the SDF draw batch shapes and text go into
  pub const draw=@import("ui/draw.zig");
  /// the procedural font's glyphs
  pub const font=@import("ui/font.zig");
  /// layout boxes and their hit tests
  pub const box=@import("ui/box.zig");
};
/// the shadow casters' fragment shader (depth alone), for a game's shadow passes
pub const shadowFrag=@embedFile("shadow.frag");
test{
  _=core.math;
  _=core.color;
  _=core.rng;
  _=core.noise;
  _=core.registry;
  _=core.jobs;
  _=core.text;
  _=core.png;
  _=core.dsp;
  _=platform.input;
  _=platform.audio;
  _=anim.rig;
  _=anim.clip;
  _=gfx.meshgen;
  _=gfx.sculpt;
  _=gfx.growth;
  _=world.chunk;
  _=@import("world/world.zig");
  _=render.camera;
  _=render.light;
  _=render.volume;
  _=ui.draw;
  _=ui.box;
}
