//! frame orchestration: terrain chunk meshes, instanced procedural plants and
//! the UI batch, drawn with dynamic rendering into the swapchain.
const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("zglfw");
const m = @import("../core/math.zig");
const Ctx = @import("../gfx/ctx.zig").Ctx;
const sw = @import("../gfx/swapchain.zig");
const Buffer = @import("../gfx/buffer.zig").Buffer;
const pipeline = @import("../gfx/pipeline.zig");
const vertex = @import("../gfx/vertex.zig");
const meshgen = @import("../gfx/meshgen.zig");
const species = @import("../sim/species.zig");
const World = @import("../world/world.zig").World;
const ck = @import("../world/chunk.zig");
const terrain_mesh = @import("terrain_mesh.zig");

pub const FRAMES = 2;
pub const MAX_INSTANCES = 1 << 16;
pub const MAX_UI_VERTS = 1 << 17;

pub const WorldPush = extern struct {
  vp:m.M4,
  eye_time:[4]f32,
  fog:[4]f32,
  misc:[4]f32,
};

pub const Scene = struct {
  push:WorldPush,
  clear:[3]f32,
  /// plant instances grouped by species.
  instances:[species.count][]const vertex.PlantInstance,
  ui:[]const vertex.Ui,
};

pub const Stats = struct { draws:u32 = 0, chunks:u32 = 0, instances:u32 = 0, meshed:u32 = 0 };

const Frame = struct {
  pool:vk.CommandPool,
  cmd:vk.CommandBuffer,
  fence:vk.Fence,
  acquired:vk.Semaphore,
  inst:Buffer,
  ui:Buffer,
  /// buffers retired while this frame was in flight; freed when it comes round again.
  garbage:std.ArrayList(Buffer) = .empty,
};

const Slot = struct { buf:Buffer = .{}, count:u32 = 0, live:bool = false };

pub const Renderer = struct {
  gpa:std.mem.Allocator,
  window:*glfw.Window,
  ctx:Ctx,
  sc:sw.Swapchain,
  vsync:bool,
  frames:[FRAMES]Frame,
  fi:usize = 0,
  world_layout:vk.PipelineLayout,
  ui_layout:vk.PipelineLayout,
  terrain_pipe:vk.Pipeline,
  plant_pipe:vk.Pipeline,
  ui_pipe:vk.Pipeline,
  slots:std.ArrayList(Slot) = .empty,
  free_slots:std.ArrayList(u32) = .empty,
  plant_mesh:Buffer,
  ranges:[species.count][2]u32,
  scratch:std.ArrayList(vertex.Terrain) = .empty,
  stats:Stats = .{},

  pub fn init(gpa:std.mem.Allocator, window:*glfw.Window, vsync:bool) !*Renderer {
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
        .inst = try Buffer.init(c, MAX_INSTANCES * @sizeOf(vertex.PlantInstance), .{.vertex_buffer = true}),
        .ui = try Buffer.init(c, MAX_UI_VERTS * @sizeOf(vertex.Ui), .{.vertex_buffer = true}),
      };
      try c.device.allocateCommandBuffers(&.{.command_pool = f.pool, .level = .primary, .command_buffer_count = 1}, @ptrCast(&f.cmd));
    }

    try r.createPipelines();
    try r.buildPlantMeshes();
    return r;
  }

  fn createPipelines(r:*Renderer) !void {
    const c = &r.ctx;
    r.world_layout = try pipeline.layout(c, @sizeOf(WorldPush));
    r.ui_layout = try pipeline.layout(c, 8);
    const fmt = r.sc.format.format;

    {
      const vs = try c.shader("terrain.vert");
      defer c.device.destroyShaderModule(vs, null);
      const fs = try c.shader("terrain.frag");
      defer c.device.destroyShaderModule(fs, null);
      const binds = [_]vk.VertexInputBindingDescription{pipeline.binding(vertex.Terrain, 0, .vertex)};
      const at = comptime pipeline.attrs(vertex.Terrain, 0, 0);
      r.terrain_pipe = try pipeline.create(c, .{.vert = vs, .frag = fs, .bindings = &binds, .attrs = &at, .layout = r.world_layout, .color_format = fmt, .cull = false});
    }
    {
      const vs = try c.shader("plant.vert");
      defer c.device.destroyShaderModule(vs, null);
      const fs = try c.shader("plant.frag");
      defer c.device.destroyShaderModule(fs, null);
      const binds = [_]vk.VertexInputBindingDescription{
        pipeline.binding(vertex.Plant, 0, .vertex),
        pipeline.binding(vertex.PlantInstance, 1, .instance),
      };
      const at = comptime pipeline.attrs(vertex.Plant, 0, 0) ++ pipeline.attrs(vertex.PlantInstance, 1, 5);
      r.plant_pipe = try pipeline.create(c, .{.vert = vs, .frag = fs, .bindings = &binds, .attrs = &at, .layout = r.world_layout, .color_format = fmt, .cull = false});
    }
    {
      const vs = try c.shader("ui.vert");
      defer c.device.destroyShaderModule(vs, null);
      const fs = try c.shader("ui.frag");
      defer c.device.destroyShaderModule(fs, null);
      const binds = [_]vk.VertexInputBindingDescription{pipeline.binding(vertex.Ui, 0, .vertex)};
      const at = comptime pipeline.attrs(vertex.Ui, 0, 0);
      r.ui_pipe = try pipeline.create(c, .{.vert = vs, .frag = fs, .bindings = &binds, .attrs = &at, .layout = r.ui_layout, .color_format = fmt, .depth = false, .blend = true, .cull = false});
    }
  }

  /// grow every species' mesh once into one shared vertex buffer.
  fn buildPlantMeshes(r:*Renderer) !void {
    var b:meshgen.Builder = .{.gpa = r.gpa};
    defer b.deinit();
    inline for (0..species.count) |i| {
      const first:u32 = @intCast(b.v.items.len);
      try meshgen.plant(&b, @enumFromInt(i));
      r.ranges[i] = .{first, @as(u32, @intCast(b.v.items.len)) - first};
    }
    const bytes = std.mem.sliceAsBytes(b.v.items);
    r.plant_mesh = try Buffer.init(&r.ctx, bytes.len, .{.vertex_buffer = true});
    r.plant_mesh.write(0, bytes);
  }

  pub fn deinit(r:*Renderer) void {
    const c = &r.ctx;
    c.device.deviceWaitIdle() catch {};
    for (&r.frames) |*f| {
      for (f.garbage.items) |*b| b.deinit(c);
      f.garbage.deinit(r.gpa);
      f.inst.deinit(c);
      f.ui.deinit(c);
      c.device.destroySemaphore(f.acquired, null);
      c.device.destroyFence(f.fence, null);
      c.device.destroyCommandPool(f.pool, null);
    }
    for (r.slots.items) |*s| s.buf.deinit(c);
    r.slots.deinit(r.gpa);
    r.free_slots.deinit(r.gpa);
    r.scratch.deinit(r.gpa);
    r.plant_mesh.deinit(c);
    c.device.destroyPipeline(r.terrain_pipe, null);
    c.device.destroyPipeline(r.plant_pipe, null);
    c.device.destroyPipeline(r.ui_pipe, null);
    c.device.destroyPipelineLayout(r.world_layout, null);
    c.device.destroyPipelineLayout(r.ui_layout, null);
    r.sc.deinit(c, r.gpa, false);
    r.ctx.deinit(r.gpa);
    r.gpa.destroy(r);
  }

  fn retire(r:*Renderer, b:Buffer) !void {
    if (b.buf == .null_handle) return;
    try r.frames[r.fi].garbage.append(r.gpa, b);
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
      const bytes = std.mem.sliceAsBytes(r.scratch.items);
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
    return .{@floatFromInt(r.sc.extent.width), @floatFromInt(r.sc.extent.height)};
  }

  pub fn draw(r:*Renderer, scene:*const Scene, resized:bool) !void {
    const c = &r.ctx;
    const f = &r.frames[r.fi];
    _ = try c.device.waitForFences(&.{f.fence}, .true, std.math.maxInt(u64));
    for (f.garbage.items) |*b| b.deinit(c);
    f.garbage.clearRetainingCapacity();

    if (resized) { try r.recreate(); return; }
    const acq = c.device.acquireNextImageKHR(r.sc.handle, std.math.maxInt(u64), f.acquired, .null_handle) catch |e| switch (e) {
      error.OutOfDateKHR => { try r.recreate(); return; },
      else => return e,
    };
    const img = acq.image_index;
    try c.device.resetFences(&.{f.fence});

    // per-frame streams
    var ninst:u32 = 0;
    var first:[species.count]u32 = undefined;
    for (scene.instances, 0..) |list, i| {
      const n:u32 = @intCast(@min(list.len, MAX_INSTANCES - ninst));
      first[i] = ninst;
      f.inst.write(ninst * @sizeOf(vertex.PlantInstance), std.mem.sliceAsBytes(list[0..n]));
      ninst += n;
    }
    const nui:u32 = @intCast(@min(scene.ui.len, MAX_UI_VERTS));
    f.ui.write(0, std.mem.sliceAsBytes(scene.ui[0..nui]));

    const cmd = vk.CommandBufferProxy.init(f.cmd, c.vkd);
    try cmd.resetCommandBuffer(.{});
    try cmd.beginCommandBuffer(&.{.flags = .{.one_time_submit = true}});

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
      .clear_value = .{.color = .{.float_32 = .{scene.clear[0], scene.clear[1], scene.clear[2], 1}}},
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
    const vp = [_]vk.Viewport{.{
      .x = 0, .y = 0,
      .width = @floatFromInt(r.sc.extent.width),
      .height = @floatFromInt(r.sc.extent.height),
      .min_depth = 0, .max_depth = 1,
    }};
    cmd.setViewport(0, &vp);
    cmd.setScissor(0, &.{area});

    var stats:Stats = .{.meshed = r.stats.meshed};
    const zero = [_]vk.DeviceSize{0};
    const stages:vk.ShaderStageFlags = .{.vertex = true, .fragment = true};

    cmd.bindPipeline(.graphics, r.terrain_pipe);
    cmd.pushConstants(r.world_layout, stages, 0, @sizeOf(WorldPush), &scene.push);
    for (r.slots.items) |s| {
      if (!s.live or s.count == 0) continue;
      cmd.bindVertexBuffers(0, &.{s.buf.buf}, &zero);
      cmd.draw(s.count, 1, 0, 0);
      stats.draws += 1;
      stats.chunks += 1;
    }

    if (ninst > 0) {
      cmd.bindPipeline(.graphics, r.plant_pipe);
      cmd.pushConstants(r.world_layout, stages, 0, @sizeOf(WorldPush), &scene.push);
      const bufs = [_]vk.Buffer{r.plant_mesh.buf, f.inst.buf};
      const offs = [_]vk.DeviceSize{0, 0};
      cmd.bindVertexBuffers(0, &bufs, &offs);
      for (scene.instances, 0..) |list, i| {
        if (list.len == 0) continue;
        cmd.draw(r.ranges[i][1], @intCast(list.len), r.ranges[i][0], first[i]);
        stats.draws += 1;
      }
      stats.instances = ninst;
    }

    if (nui > 0) {
      cmd.bindPipeline(.graphics, r.ui_pipe);
      const screen = r.extent();
      cmd.pushConstants(r.ui_layout, stages, 0, 8, &screen);
      cmd.bindVertexBuffers(0, &.{f.ui.buf}, &zero);
      cmd.draw(nui, 1, 0, 0);
      stats.draws += 1;
    }
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
    try cmd.endCommandBuffer();

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
};
