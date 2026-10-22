//! the shape of a render pass module (see render/passes/). Each pass declares
//!   desc:Desc                          its shaders, vertex layout and state
//!   Frame                              per-frame resources (optional)
//!   initFrame(c) Error!Frame / deinitFrame(*Frame, c)
//!                                      (Frame fields default to empty)
//!   record(r, *Frame, cmd, scene, stats) upload this frame's data, draw it
//! Passes record in declaration order inside one dynamic-rendering scope.
const vk = @import("vulkan");
const ctx = @import("../gfx/ctx.zig");
const Ctx = ctx.Ctx;
const pipeline = @import("../gfx/pipeline.zig");

/// which push-constant block the pass uses.
pub const Layout = enum { world, ui };

pub const Desc = struct {
  vert:[]const u8,
  frag:[]const u8,
  bindings:[]const vk.VertexInputBindingDescription,
  attrs:[]const vk.VertexInputAttributeDescription,
  layout:Layout = .world,
  depth:bool = true,
  blend:bool = false,
};

pub const stages:vk.ShaderStageFlags = .{.vertex = true, .fragment = true};

pub fn create(c:*const Ctx, comptime d:Desc, layout:vk.PipelineLayout, fmt:vk.Format) ctx.Error!vk.Pipeline {
  const vs = try c.shader(d.vert);
  defer c.device.destroyShaderModule(vs, null);
  const fs = try c.shader(d.frag);
  defer c.device.destroyShaderModule(fs, null);
  return pipeline.create(c, .{
    .vert = vs, .frag = fs,
    .bindings = d.bindings, .attrs = d.attrs,
    .layout = layout, .color_format = fmt,
    .depth = d.depth, .blend = d.blend, .cull = false,
  });
}
