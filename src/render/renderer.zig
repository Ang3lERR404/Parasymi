//! frame orchestration: acquire, record every pass inside one dynamic
//! rendering scope, submit, present. What gets drawn lives in the pass
//! modules under `passes/` (see render/pass.zig); they record in the order
//! listed in `passes`. A new pass is one new file plus one line.
const std = @import("std");
const Allocator = std.mem.Allocator;
const sliceAsBytes = std.mem.sliceAsBytes;
const vk = @import("vulkan");
const glfw = @import("zglfw");
const m = @import("../core/math.zig");
const registry = @import("../core/registry.zig");
const Ctx = @import("../gfx/ctx.zig").Ctx;
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
const pass = @import("pass.zig");

const passes = struct {
  pub const terrain = @import("passes/terrain.zig");
  pub const plants = @import("passes/plants.zig");
  pub const parts = @import("passes/parts.zig");
  pub const ui = @import("passes/ui.zig");
};
const reg = registry.Registry(passes);
pub const Pass = reg.Id;

pub const FRAMES = 2;

pub const WorldPush = extern struct {
  vp:m.M4,
  eye_time:[4]f32,
  fog:[4]f32,
  misc:[4]f32,
  sun:[4]f32,
};

pub const Scene = struct {
  push:WorldPush,
  clear:[3]f32,
  /// plant instances grouped by species.
  instances:[species.count][]const vertex.PlantInstance,
  /// rigid part instances grouped by mesh (player, nodes, motes, ...).
  parts:[meshlib.count][]const vertex.PartInstance,
  ui:[]const vertex.Ui,
  /// UI clock (keeps running while the world is paused)
  ui_time:f32,
};

pub const Stats = struct { draws:u32 = 0, chunks:u32 = 0, instances:u32 = 0, parts:u32 = 0, meshed:u32 = 0 };

const Frame = struct {
  pool:vk.CommandPool,
  cmd:vk.CommandBuffer,
  fence:vk.Fence,
  acquired:vk.Semaphore,
  /// each pass's per-frame resources, side by side
  pass:reg.Struct("Frame"),
  /// buffers retired while this frame was in flight; freed when it comes round again.
  garbage:std.ArrayList(Buffer) = .empty,
};

pub const Slot = struct { buf:Buffer = .{}, count:u32 = 0, live:bool = false };

pub const Renderer = struct {
  gpa:Allocator,
  window:*glfw.Window,
  ctx:Ctx,
  sc:sw.Swapchain,
  vsync:bool,
  frames:[FRAMES]Frame,
  fi:usize = 0,
  layouts:[2]vk.PipelineLayout,
  pipes:[reg.count]vk.Pipeline,
  /// terrain chunk meshes (see syncWorld)
  slots:std.ArrayList(Slot) = .empty,
  free_slots:std.ArrayList(u32) = .empty,
  /// every built-once mesh (plant species + part library) in one buffer.
  meshes:Buffer,
  plant_ranges:[species.count][2]u32,
  part_ranges:[meshlib.count][2]u32,
  scratch:std.ArrayList(vertex.Terrain) = .empty,
  stats:Stats = .{},

  pub fn init(gpa:Allocator, window:*glfw.Window, vsync:bool) !*Renderer {
    const r = try gpa.create(Renderer);
    errdefer gpa.destroy(r);
    r.* = undefined;
    r.gpa = gpa;
    r.window = window;
    r.vsync = vsync;
    r.fi = 0;
    r.slots = .empty;
    r.free_slots = .empty;
    r.scratch = .empty;
    r.stats = .{};
    r.ctx = try Ctx.init(gpa, window);
    const c = &r.ctx;
    const fb = window.getFramebufferSize();
    r.sc = try sw.Swapchain.init(c, gpa, @intCast(fb[0]), @intCast(fb[1]), vsync, .null_handle);

    for (&r.frames) |*f| {
      f.* = .{
        .pool = try c.device.createCommandPool(&.{.flags = .{.reset_command_buffer = true}, .queue_family_index = c.family}, null),
        .cmd = undefined,
        .fence = try c.device.createFence(&.{.flags = .{.signaled = true}}, null),
        .acquired = try c.device.createSemaphore(&.{}, null),
        .pass = undefined,
      };
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
    return r;
  }

  pub fn pipe(r:*const Renderer, p:Pass) vk.Pipeline { return r.pipes[@intFromEnum(p)]; }
  pub fn layout(r:*const Renderer, l:pass.Layout) vk.PipelineLayout { return r.layouts[@intFromEnum(l)]; }

  /// grow every species' mesh and every library part once into one buffer.
  fn buildMeshes(r:*Renderer) !void {
    var b:meshgen.Builder = .{.gpa = r.gpa};
    defer b.deinit();
    for (species.ids) |id| {
      const first:u32 = @intCast(b.v.items.len);
      try meshgen.plant(&b, id);
      r.plant_ranges[@intFromEnum(id)] = .{first, @as(u32, @intCast(b.v.items.len)) - first};
    }
    try meshlib.build(&b, &r.part_ranges);
    const bytes = sliceAsBytes(b.v.items);
    r.meshes = try Buffer.init(&r.ctx, bytes.len, .{.vertex_buffer = true});
    r.meshes.write(0, bytes);
  }

  pub fn deinit(r:*Renderer) void {
    const c = &r.ctx;
    c.device.deviceWaitIdle() catch {};
    for (&r.frames) |*f| {
      for (f.garbage.items) |*b| b.deinit(c);
      f.garbage.deinit(r.gpa);
      inline for (reg.ids) |id| {
        if (comptime reg.has(id, "Frame")) reg.module(id).deinitFrame(&@field(f.pass, @tagName(id)), c);
      }
      c.device.destroySemaphore(f.acquired, null);
      c.device.destroyFence(f.fence, null);
      c.device.destroyCommandPool(f.pool, null);
    }
    for (r.slots.items) |*s| s.buf.deinit(c);
    r.slots.deinit(r.gpa);
    r.free_slots.deinit(r.gpa);
    r.scratch.deinit(r.gpa);
    r.meshes.deinit(c);
    for (r.pipes) |p| c.device.destroyPipeline(p, null);
    for (r.layouts) |l| c.device.destroyPipelineLayout(l, null);
    r.sc.deinit(c, r.gpa, false);
    r.ctx.deinit(r.gpa);
    r.gpa.destroy(r);
  }

  fn retire(r:*Renderer, b:Buffer) !void {
    if (b.buf == .null_handle) return;
    try r.frames[r.fi].garbage.append(r.gpa, b);
  }

  /// forget every chunk mesh: the world was replaced (e.g. a save was loaded).
  pub fn dropWorld(r:*Renderer) !void {
    for (r.slots.items) |s| try r.retire(s.buf);
    r.slots.clearRetainingCapacity();
    r.free_slots.clearRetainingCapacity();
  }

  /// upload meshes for new/dirty chunks (at most `budget`) and drop evicted ones.
  pub fn syncWorld(r:*Renderer, w:*World, budget:u32) !void {
    for (w.evicted.items) |si| {
      try r.retire(r.slots.items[si].buf);
      r.slots.items[si] = .{};
      try r.free_slots.append(r.gpa, si);
    }
    w.evicted.clearRetainingCapacity();

    r.stats.meshed = 0;
    var it = w.map.valueIterator();
    while (it.next()) |cp| {
      const c = cp.*;
      if (!c.dirty) continue;
      if (r.stats.meshed >= budget) break;
      try terrain_mesh.build(r.gpa, w.seed, c, &r.scratch);
      const bytes = sliceAsBytes(r.scratch.items);
      var buf = try Buffer.init(&r.ctx, @max(bytes.len, 64), .{.vertex_buffer = true});
      buf.write(0, bytes);
      if (c.gpu_slot == ck.NONE) {
        c.gpu_slot = r.free_slots.pop() orelse blk: {
          try r.slots.append(r.gpa, .{});
          break :blk @intCast(r.slots.items.len - 1);
        };
      } else try r.retire(r.slots.items[c.gpu_slot].buf);
      r.slots.items[c.gpu_slot] = .{.buf = buf, .count = @intCast(r.scratch.items.len), .live = true};
      c.dirty = false;
      r.stats.meshed += 1;
    }
  }

  fn recreate(r:*Renderer) !void {
    const c = &r.ctx;
    var fb = r.window.getFramebufferSize();
    while (fb[0] == 0 or fb[1] == 0) {
      glfw.waitEvents();
      fb = r.window.getFramebufferSize();
      if (r.window.shouldClose()) return;
    }
    try c.device.deviceWaitIdle();
    const old = r.sc;
    r.sc = try sw.Swapchain.init(c, r.gpa, @intCast(fb[0]), @intCast(fb[1]), r.vsync, old.handle);
    var o = old;
    o.deinit(c, r.gpa, false);
  }

  pub fn extent(r:*const Renderer) [2]f32 {
    return .{m.f(r.sc.extent.width), m.f(r.sc.extent.height)};
  }

  pub fn draw(r:*Renderer, scene:*const Scene, resized:bool) !void {
    const c = &r.ctx;
    const f = &r.frames[r.fi];
    _ = try c.device.waitForFences(&.{f.fence}, .true, m.maxInt(u64));
    for (f.garbage.items) |*b| b.deinit(c);
    f.garbage.clearRetainingCapacity();

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
    r.begin(cmd, img, scene.clear);

    var stats:Stats = .{.meshed = r.stats.meshed};
    inline for (reg.ids) |id| try reg.module(id).record(r, &@field(f.pass, @tagName(id)), cmd, scene, &stats);

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

  /// transition the targets and open the dynamic-rendering scope.
  fn begin(r:*Renderer, cmd:vk.CommandBufferProxy, img:u32, clear:[3]f32) void {
    const pre = [_]vk.ImageMemoryBarrier2{
      .{
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
      },
      .{
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
      },
    };
    cmd.pipelineBarrier2(&.{.image_memory_barrier_count = pre.len, .p_image_memory_barriers = &pre});

    const color = [_]vk.RenderingAttachmentInfo{.{
      .image_view = r.sc.views[img],
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
    const area:vk.Rect2D = .{.offset = .{.x = 0, .y = 0}, .extent = r.sc.extent};
    cmd.beginRendering(&.{
      .render_area = area,
      .layer_count = 1,
      .view_mask = 0,
      .color_attachment_count = color.len,
      .p_color_attachments = &color,
      .p_depth_attachment = &depth,
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
