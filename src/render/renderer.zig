//! frame orchestration: acquire, record every pass inside one dynamic
//! rendering scope, submit, present. What gets drawn lives in the pass
//! modules under `passes/` (shape in `pass` below); they record in the order
//! listed in `passes`. A new pass is one new file plus one line.
const std = @import("std");
const Allocator = std.mem.Allocator;
const sliceAsBytes = std.mem.sliceAsBytes;
const ArenaAllocator = std.heap.ArenaAllocator;
const vk = @import("vulkan");
const glfw = @import("zglfw");
const m = @import("../core/math.zig");
const registry = @import("../core/registry.zig");
const ctx = @import("../gfx/ctx.zig");
const Ctx = ctx.Ctx;
const sw = @import("../gfx/swapchain.zig");
const Buffer = @import("../gfx/buffer.zig").Buffer;
const pipeline = @import("../gfx/pipeline.zig");
const vertex = @import("../gfx/vertex.zig");
const meshgen = @import("../gfx/meshgen.zig");
const meshlib = @import("../gfx/meshlib.zig");
const species = @import("../sim/species.zig");
const World = @import("../world/world.zig").World;
const ck = @import("../world/chunk.zig");
const terrain_mesh = @import("terrain_mesh.zig");
const Post = @import("post.zig").Post;
const HDR_FORMAT = @import("post.zig").HDR_FORMAT;

/// the shape of a render pass module (see passes/). Each pass declares
///   desc:Desc                          its shaders, vertex layout and state
///   Frame                              per-frame resources (optional)
///   initFrame(c) Error!Frame / deinitFrame(*Frame, c)
///                                      (Frame fields default to empty)
///   record(r, *Frame, cmd, scene, stats) upload this frame's data, draw it
/// Passes record in declaration order inside one dynamic-rendering scope.
pub const pass = struct {
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
    /// drawn onto the screen after the world (and its glow): the UI. World
    /// passes draw into the HDR image the glow is taken from.
    screen:bool = false,
  };

  pub const stages:vk.ShaderStageFlags = .{.vertex = true, .fragment = true};

  pub fn create(c:*const Ctx, comptime d:Desc, layout:vk.PipelineLayout, screen:vk.Format) ctx.Error!vk.Pipeline {
    const vs = try c.shader(d.vert);
    defer c.device.destroyShaderModule(vs, null);
    const fs = try c.shader(d.frag);
    defer c.device.destroyShaderModule(fs, null);
    return pipeline.create(c, .{
      .vert = vs, .frag = fs,
      .bindings = d.bindings, .attrs = d.attrs,
      .layout = layout, .color_format = if (d.screen) screen else HDR_FORMAT,
      .depth = d.depth, .depth_attachment = !d.screen, .blend = d.blend, .cull = false,
    });
  }
};

const passes = struct {
  pub const sky = @import("passes/sky.zig");
  pub const terrain = @import("passes/terrain.zig");
  pub const detail = @import("passes/detail.zig");
  pub const plants = @import("passes/plants.zig");
  pub const parts = @import("passes/parts.zig");
  pub const ui = @import("passes/ui.zig");
};
const reg = registry.Registry(passes);
pub const Pass = reg.Id;

pub const FRAMES = 2;
/// every grown plant mesh: each species in each of its variants.
pub const PLANT_MESHES = species.count * meshgen.MAX_VARIANTS * meshgen.LODS;

/// the renderer fails the way the graphics layer does.
pub const Error = ctx.Error;

pub const WorldPush = extern struct {
  vp:m.M4,
  eye_time:[4]f32,
  fog:[4]f32,
  misc:[4]f32,
  sun:[4]f32,
  /// the wolf's paws for contact shadows: world x, y, z, facing yaw
  feet:[2][4]f32,
  /// x,z: what the camera looks at; z,w: horizontal distance from it where
  /// fog starts closing in and where the world is fully hidden
  view:[4]f32,
};

pub const Scene = struct {
  push:WorldPush,
  clear:[3]f32,
  /// plant instances grouped by mesh variant (see meshgen.plantSlot).
  instances:[PLANT_MESHES][]const vertex.PlantInstance,
  /// rigid part instances grouped by mesh (player, nodes, motes, ...).
  parts:[meshlib.SLOTS][]const vertex.PartInstance,
  ui:[]const vertex.Ui,
  /// UI clock (keeps running while the world is paused)
  ui_time:f32,
};

pub const Stats = struct { draws:u32 = 0, chunks:u32 = 0, instances:u32 = 0, parts:u32 = 0, meshed:u32 = 0 };

const Frame = struct {
  pool:vk.CommandPool = .null_handle,
  /// freed with its pool
  cmd:vk.CommandBuffer = undefined,
  fence:vk.Fence = .null_handle,
  acquired:vk.Semaphore = .null_handle,
  /// each pass's per-frame resources, side by side
  pass:reg.Struct("Frame") = undefined,
  /// buffers retired while this frame was in flight; freed when it comes round again.
  garbage:std.ArrayList(Buffer) = .empty,
};

/// a sphere around a chunk (from its centre, `CHUNK_MID_Y` up) holding all
/// of it, its terraces and what grows on its tiles, for culling it to the
/// view: half its diagonal (rounded up) and a margin
pub const CHUNK_MID_Y:f32 = 1.5;
pub const CHUNK_RADIUS:f32 = m.f(ck.SIZE) * 0.71 + 2;

/// milliseconds a frame may spend meshing streamed chunks
const MESH_MS:f64 = 3;
/// smallest buffer made for a chunk (an empty chunk still gets one)
const MIN_CHUNK_BYTES = 64;

pub const Slot = struct {
  /// the chunk's ground mesh
  buf:Buffer = .{},
  count:u32 = 0,
  /// its detail records (one per tile with grass, clods or stones), which
  /// the detail pass grows on the GPU near the camera
  detail:Buffer = .{},
  tiles:u32 = 0,
  /// the chunk's centre (x, z)
  centre:[2]f32 = .{0, 0},
  live:bool = false,
};

pub const Renderer = struct {
  gpa:Allocator,
  window:*glfw.Window,
  ctx:Ctx,
  sc:sw.Swapchain,
  /// the HDR image the world is drawn into, and the glow taken from it
  post:Post = .{},
  vsync:bool,
  frames:[FRAMES]Frame = @splat(.{}),
  fi:usize = 0,
  layouts:[2]vk.PipelineLayout = @splat(.null_handle),
  pipes:[reg.count]vk.Pipeline = @splat(.null_handle),
  /// terrain chunk meshes (see syncWorld)
  slots:std.ArrayList(Slot) = .empty,
  free_slots:std.ArrayList(ck.MeshSlot) = .empty,
  /// every built-once mesh (plant species + part library) in one buffer.
  meshes:Buffer = .{},
  /// (first vertex, count) per plant slot; slots a species does not use are empty
  plant_ranges:[PLANT_MESHES][2]u32 = @splat(.{0, 0}),
  /// per plant slot, the byte offset from its mesh to the next growth key's
  /// (the plant shader blends toward it); 0 where a species has no keys
  plant_morph:[PLANT_MESHES]u64 = @splat(0),
  part_ranges:[meshlib.SLOTS][2]u32 = undefined,
  scratch:std.ArrayList(vertex.Terrain) = .empty,
  detail_scratch:std.ArrayList(vertex.DetailTile) = .empty,
  /// buffers retired since the last frame began; any frame still in flight
  /// may use them, so they join the next frame's garbage (freed only once
  /// that frame, and every frame before it, has finished on the GPU).
  pending:std.ArrayList(Buffer) = .empty,
  stats:Stats = .{},

  pub fn init(gpa:Allocator, window:*glfw.Window, vsync:bool) Error!*Renderer {
    const r = try gpa.create(Renderer);
    errdefer gpa.destroy(r);
    r.* = .{.gpa = gpa, .window = window, .vsync = vsync, .ctx = undefined, .sc = .{}};
    for (&r.frames) |*f| inline for (reg.ids) |id| {
      if (comptime reg.has(id, "Frame")) @field(f.pass, @tagName(id)) = .{};
    };
    r.ctx = try Ctx.init(gpa, window);
    errdefer r.ctx.deinit(gpa);
    // everything below starts null, so a half-built renderer frees cleanly
    errdefer r.release();
    r.build() catch |e| return ctx.fold(e);
    return r;
  }

  fn build(r:*Renderer) !void {
    const c = &r.ctx;
    const fb = r.window.getFramebufferSize();
    r.sc = try sw.Swapchain.init(c, r.gpa, @intCast(fb[0]), @intCast(fb[1]), r.vsync, .null_handle);
    r.post = try Post.init(c, r.sc.format.format, r.sc.extent.width, r.sc.extent.height);

    for (&r.frames) |*f| {
      f.pool = try c.device.createCommandPool(&.{.flags = .{.reset_command_buffer = true}, .queue_family_index = c.family}, null);
      f.fence = try c.device.createFence(&.{.flags = .{.signaled = true}}, null);
      f.acquired = try c.device.createSemaphore(&.{}, null);
      inline for (reg.ids) |id| {
        if (comptime reg.has(id, "Frame")) @field(f.pass, @tagName(id)) = try reg.module(id).initFrame(c);
      }
      try c.device.allocateCommandBuffers(&.{.command_pool = f.pool, .level = .primary, .command_buffer_count = 1}, @ptrCast(&f.cmd));
    }

    r.layouts[@intFromEnum(pass.Layout.world)] = try pipeline.layout(c, @sizeOf(WorldPush));
    r.layouts[@intFromEnum(pass.Layout.ui)] = try pipeline.layout(c, @sizeOf(passes.ui.Push));
    inline for (reg.ids) |id| {
      const d = reg.module(id).desc;
      r.pipes[@intFromEnum(id)] = try pass.create(c, d, r.layout(d.layout), r.sc.format.format);
    }
    try r.buildMeshes();
  }

  pub fn pipe(r:*const Renderer, p:Pass) vk.Pipeline { return r.pipes[@intFromEnum(p)]; }
  pub fn layout(r:*const Renderer, l:pass.Layout) vk.PipelineLayout { return r.layouts[@intFromEnum(l)]; }

  /// grow every species' mesh and every library part once into one buffer.
  fn buildMeshes(r:*Renderer) Error!void {
    // the builder's vertices are scratch: one arena, freed in one go once uploaded
    var arena = ArenaAllocator.init(r.gpa);
    defer arena.deinit();
    var b:meshgen.Builder = .{.gpa = arena.allocator()};
    for (species.ids) |id| for (0..meshgen.LODS) |l| {
      const lod:u32 = @intCast(l);
      b.lod = lod;
      const n = meshgen.variants(id);
      for (0..n) |v| {
        const first:u32 = @intCast(b.v.items.len);
        try meshgen.plant(&b, id, @intCast(v));
        r.plant_ranges[meshgen.plantSlot(id, @intCast(v), lod)] = .{first, @as(u32, @intCast(b.v.items.len)) - first};
      }
      // growth keys blend vertex for vertex into the next key
      if (meshgen.growthKey(id, 0) == null) continue;
      for (0..n - 1) |v| {
        const a = r.plant_ranges[meshgen.plantSlot(id, @intCast(v), lod)];
        const z = r.plant_ranges[meshgen.plantSlot(id, @intCast(v + 1), lod)];
        if (a[1] != z[1]) @panic("growth keys differ in vertex count");
        r.plant_morph[meshgen.plantSlot(id, @intCast(v), lod)] = @as(u64, z[0] - a[0]) * @sizeOf(vertex.Mesh);
      }
    };
    b.lod = 0;
    try meshlib.build(&b, &r.part_ranges);
    const bytes = sliceAsBytes(b.v.items);
    r.meshes = try Buffer.init(&r.ctx, bytes.len, .{.vertex_buffer = true});
    r.meshes.write(0, bytes);
  }

  pub fn deinit(r:*Renderer) void {
    // nothing to recover: teardown proceeds even if the device was lost
    r.ctx.device.deviceWaitIdle() catch {};
    r.release();
    r.ctx.deinit(r.gpa);
    r.gpa.destroy(r);
  }

  /// free every GPU object the renderer made (null handles are skipped).
  fn release(r:*Renderer) void {
    const c = &r.ctx;
    for (&r.frames) |*f| {
      for (f.garbage.items) |*b| b.deinit(c);
      f.garbage.deinit(r.gpa);
    }
    for (r.pending.items) |*b| b.deinit(c);
    r.pending.deinit(r.gpa);
    for (&r.frames) |*f| {
      inline for (reg.ids) |id| {
        if (comptime reg.has(id, "Frame")) reg.module(id).deinitFrame(&@field(f.pass, @tagName(id)), c);
      }
      c.device.destroySemaphore(f.acquired, null);
      c.device.destroyFence(f.fence, null);
      c.device.destroyCommandPool(f.pool, null);
    }
    for (r.slots.items) |*s| {
      s.buf.deinit(c);
      s.detail.deinit(c);
    }
    r.slots.deinit(r.gpa);
    r.free_slots.deinit(r.gpa);
    r.scratch.deinit(r.gpa);
    r.detail_scratch.deinit(r.gpa);
    r.meshes.deinit(c);
    for (r.pipes) |p| c.device.destroyPipeline(p, null);
    for (r.layouts) |l| c.device.destroyPipelineLayout(l, null);
    r.post.deinit(c);
    r.sc.deinit(c, r.gpa, false);
  }

  fn retire(r:*Renderer, b:Buffer) Allocator.Error!void {
    if (b.buf == .null_handle) return;
    try r.pending.append(r.gpa, b);
  }

  /// forget every chunk mesh: the world was replaced (e.g. a save was loaded).
  pub fn dropWorld(r:*Renderer) Allocator.Error!void {
    for (r.slots.items) |s| try r.retire(s.buf);
    r.slots.clearRetainingCapacity();
    r.free_slots.clearRetainingCapacity();
  }

  /// upload meshes for new/dirty chunks (at most `budget`) and drop evicted ones.
  pub fn syncWorld(r:*Renderer, w:*World, budget:u32) Error!void {
    for (w.evicted.items) |si| {
      const i = @intFromEnum(si);
      try r.retire(r.slots.items[i].buf);
      try r.retire(r.slots.items[i].detail);
      r.slots.items[i] = .{};
      try r.free_slots.append(r.gpa, si);
    }
    w.evicted.clearRetainingCapacity();

    r.stats.meshed = 0;
    const start = glfw.getTime();
    var it = w.map.valueIterator();
    while (it.next()) |cp| {
      const c = cp.*;
      if (!c.dirty) continue;
      // at most `budget` chunks, and no more once a frame's share of time
      // is spent (at least one, so streaming always moves on)
      if (r.stats.meshed >= budget) break;
      if (r.stats.meshed > 0 and (glfw.getTime() - start) * m.MS_PER_S > MESH_MS) break;
      try terrain_mesh.build(r.gpa, w.seed, c, &r.scratch, &r.detail_scratch);
      const bytes = sliceAsBytes(r.scratch.items);
      var buf = try Buffer.init(&r.ctx, @max(bytes.len, MIN_CHUNK_BYTES), .{.vertex_buffer = true});
      errdefer buf.deinit(&r.ctx);
      buf.write(0, bytes);
      const dbytes = sliceAsBytes(r.detail_scratch.items);
      var detail = try Buffer.init(&r.ctx, @max(dbytes.len, MIN_CHUNK_BYTES), .{.vertex_buffer = true});
      errdefer detail.deinit(&r.ctx);
      detail.write(0, dbytes);
      const slot = if (c.gpu_slot) |s| s else r.free_slots.pop() orelse blk: {
        try r.slots.append(r.gpa, .{});
        break :blk @as(ck.MeshSlot, @enumFromInt(r.slots.items.len - 1));
      };
      const at = @intFromEnum(slot);
      if (c.gpu_slot != null) {
        try r.retire(r.slots.items[at].buf);
        try r.retire(r.slots.items[at].detail);
      }
      c.gpu_slot = slot;
      const half = m.f(ck.SIZE) / 2;
      r.slots.items[at] = .{
        .buf = buf, .count = @intCast(r.scratch.items.len), .live = true,
        .detail = detail, .tiles = @intCast(r.detail_scratch.items.len),
        .centre = .{m.f(c.originX()) + half, m.f(c.originY()) + half},
      };
      c.dirty = false;
      r.stats.meshed += 1;
    }
  }

  fn recreate(r:*Renderer) Error!void {
    const c = &r.ctx;
    var fb = r.window.getFramebufferSize();
    while (fb[0] == 0 or fb[1] == 0) {
      glfw.waitEvents();
      fb = r.window.getFramebufferSize();
      if (r.window.shouldClose()) return;
    }
    c.device.deviceWaitIdle() catch |e| return ctx.fold(e);
    const old = r.sc;
    r.sc = try sw.Swapchain.init(c, r.gpa, @intCast(fb[0]), @intCast(fb[1]), r.vsync, old.handle);
    var o = old;
    o.deinit(c, r.gpa, false);
    r.post.resize(c, r.sc.extent.width, r.sc.extent.height) catch |e| return ctx.fold(e);
  }

  pub fn extent(r:*const Renderer) [2]f32 {
    return .{m.f(r.sc.extent.width), m.f(r.sc.extent.height)};
  }

  pub fn draw(r:*Renderer, scene:*const Scene, resized:bool) Error!void {
    r.frame(scene, resized) catch |e| return ctx.fold(e);
  }

  fn frame(r:*Renderer, scene:*const Scene, resized:bool) !void {
    const c = &r.ctx;
    const f = &r.frames[r.fi];
    _ = try c.device.waitForFences(&.{f.fence}, .true, m.maxInt(u64));
    for (f.garbage.items) |*b| b.deinit(c);
    f.garbage.clearRetainingCapacity();
    try f.garbage.appendSlice(r.gpa, r.pending.items);
    r.pending.clearRetainingCapacity();

    if (resized) { try r.recreate(); return; }
    const acq = c.device.acquireNextImageKHR(r.sc.handle, m.maxInt(u64), f.acquired, .null_handle) catch |e| switch (e) {
      error.OutOfDateKHR => { try r.recreate(); return; },
      else => return e,
    };
    const img = acq.image_index;
    try c.device.resetFences(&.{f.fence});

    const cmd = vk.CommandBufferProxy.init(f.cmd, c.vkd);
    try cmd.resetCommandBuffer(.{});
    try cmd.beginCommandBuffer(&.{.flags = .{.one_time_submit = true}});
    // the world into the HDR image, then its glow, then the screen: the
    // world and its glow composed, the UI over it
    var stats:Stats = .{.meshed = r.stats.meshed};
    r.beginWorld(cmd, scene.clear);
    inline for (reg.ids) |id| {
      if (comptime !reg.module(id).desc.screen) reg.module(id).record(r, &@field(f.pass, @tagName(id)), cmd, scene, &stats);
    }
    cmd.endRendering();
    r.post.glow(cmd);
    r.beginScreen(cmd, img);
    r.post.compose(cmd, r.sc.extent);
    inline for (reg.ids) |id| {
      if (comptime reg.module(id).desc.screen) reg.module(id).record(r, &@field(f.pass, @tagName(id)), cmd, scene, &stats);
    }
    r.end(cmd, img);
    try cmd.endCommandBuffer();
    try r.submit(f, img);
    const pres = c.device.queuePresentKHR(c.queue, &.{
      .wait_semaphore_count = 1,
      .p_wait_semaphores = @ptrCast(&r.sc.done[img]),
      .swapchain_count = 1,
      .p_swapchains = @ptrCast(&r.sc.handle),
      .p_image_indices = @ptrCast(&img),
    }) catch |e| switch (e) {
      error.OutOfDateKHR => vk.Result.error_out_of_date_khr,
      else => return e,
    };
    r.fi = (r.fi + 1) % FRAMES;
    r.stats = stats;
    if (pres != .success or acq.result == .suboptimal_khr) try r.recreate();
  }

  /// open the world's rendering scope: the HDR image and the depth buffer.
  fn beginWorld(r:*Renderer, cmd:vk.CommandBufferProxy, clear:[3]f32) void {
    r.post.beginWorld(cmd);
    const pre = [_]vk.ImageMemoryBarrier2{.{
      .src_stage_mask = .{.early_fragment_tests = true, .late_fragment_tests = true},
      .src_access_mask = .{.depth_stencil_attachment_write = true},
      .dst_stage_mask = .{.early_fragment_tests = true, .late_fragment_tests = true},
      .dst_access_mask = .{.depth_stencil_attachment_write = true, .depth_stencil_attachment_read = true},
      .old_layout = .undefined,
      .new_layout = .depth_attachment_optimal,
      .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
      .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
      .image = r.sc.depth,
      .subresource_range = sw.depthRange(),
    }};
    cmd.pipelineBarrier2(&.{.image_memory_barrier_count = pre.len, .p_image_memory_barriers = &pre});
    const color = [_]vk.RenderingAttachmentInfo{.{
      .image_view = r.post.hdr.views[0],
      .image_layout = .color_attachment_optimal,
      .resolve_mode = .{},
      .resolve_image_layout = .undefined,
      .load_op = .clear,
      .store_op = .store,
      .clear_value = .{.color = .{.float_32 = .{clear[0], clear[1], clear[2], 1}}},
    }};
    const depth:vk.RenderingAttachmentInfo = .{
      .image_view = r.sc.depth_view,
      .image_layout = .depth_attachment_optimal,
      .resolve_mode = .{},
      .resolve_image_layout = .undefined,
      .load_op = .clear,
      .store_op = .dont_care,
      .clear_value = .{.depth_stencil = .{.depth = 1, .stencil = 0}},
    };
    r.scope(cmd, &color, &depth);
  }

  /// open the screen's rendering scope: the swapchain image, no depth.
  fn beginScreen(r:*Renderer, cmd:vk.CommandBufferProxy, img:u32) void {
    const pre = [_]vk.ImageMemoryBarrier2{.{
      .src_stage_mask = .{.color_attachment_output = true},
      .src_access_mask = .{},
      .dst_stage_mask = .{.color_attachment_output = true},
      .dst_access_mask = .{.color_attachment_write = true},
      .old_layout = .undefined,
      .new_layout = .color_attachment_optimal,
      .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
      .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
      .image = r.sc.images[img],
      .subresource_range = sw.colorRange(),
    }};
    cmd.pipelineBarrier2(&.{.image_memory_barrier_count = pre.len, .p_image_memory_barriers = &pre});
    const color = [_]vk.RenderingAttachmentInfo{.{
      .image_view = r.sc.views[img],
      .image_layout = .color_attachment_optimal,
      .resolve_mode = .{},
      .resolve_image_layout = .undefined,
      .load_op = .dont_care,
      .store_op = .store,
      .clear_value = .{.color = .{.float_32 = .{0, 0, 0, 1}}},
    }};
    r.scope(cmd, &color, null);
  }

  fn scope(r:*Renderer, cmd:vk.CommandBufferProxy, color:[]const vk.RenderingAttachmentInfo, depth:?*const vk.RenderingAttachmentInfo) void {
    const area:vk.Rect2D = .{.offset = .{.x = 0, .y = 0}, .extent = r.sc.extent};
    cmd.beginRendering(&.{
      .render_area = area,
      .layer_count = 1,
      .view_mask = 0,
      .color_attachment_count = @intCast(color.len),
      .p_color_attachments = color.ptr,
      .p_depth_attachment = depth,
    });
    cmd.setViewport(0, &.{.{
      .x = 0, .y = 0,
      .width = m.f(r.sc.extent.width),
      .height = m.f(r.sc.extent.height),
      .min_depth = 0, .max_depth = 1,
    }});
    cmd.setScissor(0, &.{area});
  }

  /// close the rendering scope and hand the image to presentation.
  fn end(r:*Renderer, cmd:vk.CommandBufferProxy, img:u32) void {
    cmd.endRendering();
    const post = [_]vk.ImageMemoryBarrier2{.{
      .src_stage_mask = .{.color_attachment_output = true},
      .src_access_mask = .{.color_attachment_write = true},
      .dst_stage_mask = .{},
      .dst_access_mask = .{},
      .old_layout = .color_attachment_optimal,
      .new_layout = .present_src_khr,
      .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
      .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
      .image = r.sc.images[img],
      .subresource_range = sw.colorRange(),
    }};
    cmd.pipelineBarrier2(&.{.image_memory_barrier_count = post.len, .p_image_memory_barriers = &post});
  }

  fn submit(r:*Renderer, f:*Frame, img:u32) !void {
    const c = &r.ctx;
    const wait = [_]vk.SemaphoreSubmitInfo{.{.semaphore = f.acquired, .value = 0, .stage_mask = .{.color_attachment_output = true}, .device_index = 0}};
    const signal = [_]vk.SemaphoreSubmitInfo{.{.semaphore = r.sc.done[img], .value = 0, .stage_mask = .{.all_commands = true}, .device_index = 0}};
    const cbi = [_]vk.CommandBufferSubmitInfo{.{.command_buffer = f.cmd, .device_mask = 0}};
    try c.device.queueSubmit2(c.queue, &.{.{
      .wait_semaphore_info_count = wait.len,
      .p_wait_semaphore_infos = &wait,
      .command_buffer_info_count = cbi.len,
      .p_command_buffer_infos = &cbi,
      .signal_semaphore_info_count = signal.len,
      .p_signal_semaphore_infos = &signal,
    }}, f.fence);
  }
};
