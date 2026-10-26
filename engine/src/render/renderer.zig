//! frame orchestration: acquire, record every pass, submit, present. What
//! gets drawn is the game's: it hands `Renderer` one namespace naming its
//! passes (shape in `pass` below), push constants, scene and stats, and
//! the state of its own it keeps on the renderer. Passes record in the
//! order listed, by target: the shadow casters into the key light's shadow
//! map, then the world into the HDR image, then the screen. A new pass is
//! one new file plus one line in the game's list.
const std = @import("std");
const Allocator = std.mem.Allocator;
const sliceAsBytes = std.mem.sliceAsBytes;
const asBytes = std.mem.asBytes;
const vk = @import("vulkan");
const glfw = @import("zglfw");
const m = @import("../core/math.zig");
const registry = @import("../core/registry.zig");
const ctx = @import("../gfx/ctx.zig");
const Ctx = ctx.Ctx;
const sw = @import("../gfx/swapchain.zig");
const Buffer = @import("../gfx/buffer.zig").Buffer;
const pipeline = @import("../gfx/pipeline.zig");
const post_mod = @import("post.zig");
const light = @import("light.zig");
const Post = post_mod.Post;
const HDR_FORMAT = post_mod.HDR_FORMAT;
pub const Antialias = post_mod.Antialias;

/// the UI pass every game can list (as `ui`): the HUD batch, drawn last
pub const ui = @import("passes/ui.zig");

/// the shape of a render pass module. Each pass declares
///   desc:Desc                          its shaders, vertex layout and state
///   Frame                              per-frame resources (optional)
///   initFrame(c) Error!Frame / deinitFrame(*Frame, c)
///                                      (Frame fields default to empty)
///   prepare(r, *Frame, scene, stats)   upload this frame's data (optional;
///                                      every pass's, before any draws)
///   record(r, *Frame, cmd, scene, stats) draw it
/// Passes record in declaration order inside their target's scope.
pub const pass = struct {
  /// which push-constant block the pass uses: the game's world block, or
  /// the UI's (`ui.Push`)
  pub const Layout = enum { world, ui };
  /// what a pass draws into: the key light's shadow map (depth alone, every
  /// cascade at once), the world's HDR image, or the screen after the world
  /// (and its glow): the UI
  pub const Target = enum { shadow, world, screen };

  pub const Desc = struct {
    /// SPIR-V, embedded by the module that compiled it (`@embedFile("x.vert")`)
    vert:[]const u8,
    frag:[]const u8,
    bindings:[]const vk.VertexInputBindingDescription,
    attrs:[]const vk.VertexInputAttributeDescription,
    layout:Layout = .world,
    depth:bool = true,
    /// with `depth`: whether it writes depth (a glass pass only tests it)
    depth_write:bool = true,
    /// with `depth`: only what lies strictly nearer passes. A glass pass
    /// draws the same instances as its solid pass at the very same depth
    /// (`invariant gl_Position`): the fragments the solid pass kept fail
    /// it before they are shaded, the see-through ones (which wrote no
    /// depth there) pass.
    nearer:bool = false,
    blend:bool = false,
    target:Target = .world,
    /// with MSAA, shade every sample: its fragments choose for themselves
    /// whether they are solid or see-through, so the edge between the two
    /// (and the silhouette it makes) lies inside the pixel, not on geometry
    per_sample:bool = false,
  };

  pub const stages:vk.ShaderStageFlags = .{.vertex = true, .fragment = true};

  /// write each mesh's run of instances into `buf` back to back (at most
  /// `max` in all), noting where each run starts and how long it is;
  /// returns how many were written.
  pub fn upload(comptime I:type, buf:*Buffer, lists:[]const []const I, first:[]u32, counts:[]u32, max:u32) u32 {
    var n:u32 = 0;
    for (lists, 0..) |list, i| {
      const k:u32 = @intCast(@min(list.len, max - n));
      first[i] = n;
      counts[i] = k;
      buf.write(n * @sizeOf(I), sliceAsBytes(list[0..k]));
      n += k;
    }
    return n;
  }

  /// `samples`: per pixel of the world's attachments (the screen has one)
  pub fn create(c:*const Ctx, comptime d:Desc, layout:vk.PipelineLayout, screen:vk.Format, samples:u32) ctx.Error!vk.Pipeline {
    const vs = try c.shader(d.vert);
    defer c.device.destroyShaderModule(vs, null);
    const fs = try c.shader(d.frag);
    defer c.device.destroyShaderModule(fs, null);
    return pipeline.create(c, .{
      .vert = vs, .frag = fs,
      .bindings = d.bindings, .attrs = d.attrs,
      .layout = layout,
      .color_format = switch (d.target) { .shadow => .undefined, .world => HDR_FORMAT, .screen => screen },
      .depth = d.depth, .depth_write = d.depth_write, .depth_compare = if (d.nearer) .less else .less_or_equal, .depth_attachment = d.target != .screen, .blend = d.blend, .cull = false,
      .samples = post_mod.sampleFlags(if (d.target == .world) samples else 1), .per_sample = d.per_sample,
      .view_mask = if (d.target == .shadow) light.VIEWS else 0,
      .depth_bias = if (d.target == .shadow) light.BIAS else null,
    });
  }
};

pub const FRAMES = 2;
/// points of light a frame can hold (the rest of a scene's `lights` is dropped)
pub const MAX_LIGHTS = light.MAX_LIGHTS;

/// the renderer fails the way the graphics layer does.
pub const Error = ctx.Error;

/// a captured frame: 4 bytes a pixel, row by row from the top
pub const Shot = struct { w:u32, h:u32, px:[]const u8, bgra:bool };

/// how fast the GPU times follow the frames (share of the way a frame)
const GPU_EASE:f32 = 0.05;

/// the renderer for a game `G`, which declares
///   name:[*:0]const u8      the game's name, as the driver is told it
///   passes                  a namespace of pass modules, one line each, in
///                           record order (list `ui` from this file to get the HUD)
///   Push                    the world passes' push constants, holding at
///                           least `vp:m.M4`, `eye_time`, `view`, `sun:[4]f32`
///                           and `light:[2]u32` (light.glsl reads them)
///   Scene                   what one frame draws: at least `push:Push`,
///                           `clear:[3]f32` and `lights:[]const vertex.Light`
///                           (and `ui`, `ui_time` when it lists `ui`)
///   Stats                   a frame's counts: at least `draws`, `lights:u32`
///                           and `gpu_ms:f32`, every field defaulted
///   Ext                     state of its own the renderer keeps (`r.ext`),
///                           handed to `init`
///   start(r) Error!void     (optional) once every pipeline is made
///   release(r) void         (optional) free what `Ext` holds on the GPU;
///                           also after a failed `init`, so it skips what is
///                           not made yet
///   carry(prev:Stats) Stats (optional) what a frame's counts start from
pub fn Renderer(comptime G:type) type {
  return struct {
    const R = @This();
    const reg = registry.Registry(G.passes);
    pub const Pass = reg.Id;
    pub const Push = G.Push;
    pub const Scene = G.Scene;
    pub const Stats = G.Stats;

    /// what the GPU's time is told apart by: each pass (`Pass` order), then
    /// the glow and the composite (`GLOW`, `COMPOSE`)
    pub const STAGES = reg.count + 2;
    pub const GLOW = reg.count;
    pub const COMPOSE = reg.count + 1;
    /// time stamps a frame writes: one before it, one after each stage
    const STAMPS = STAGES + 1;

    const Frame = struct {
      pool:vk.CommandPool = .null_handle,
      /// freed with its pool
      cmd:vk.CommandBuffer = undefined,
      fence:vk.Fence = .null_handle,
      acquired:vk.Semaphore = .null_handle,
      /// each pass's per-frame resources, side by side
      pass:reg.Struct("Frame") = undefined,
      /// this frame's `light.Lighting`, which every world shader reads by address
      lighting:Buffer = .{},
      /// its GPU time stamps (null where the GPU keeps none), how many it
      /// wrote and the stage each one ends (the first: none)
      queries:vk.QueryPool = .null_handle,
      stamped:u32 = 0,
      stage:[STAMPS]u32 = undefined,
      /// buffers retired while this frame was in flight; freed when it comes round again.
      garbage:std.ArrayList(Buffer) = .empty,
    };

    gpa:Allocator,
    window:*glfw.Window,
    ctx:Ctx,
    sc:sw.Swapchain,
    /// the HDR image the world is drawn into, and the glow taken from it
    post:Post = .{},
    /// the key light's shadow map
    shadow:light.Shadow = .{},
    vsync:bool,
    frames:[FRAMES]Frame = @splat(.{}),
    fi:usize = 0,
    layouts:[2]vk.PipelineLayout = @splat(.null_handle),
    pipes:[reg.count]vk.Pipeline = @splat(.null_handle),
    /// buffers retired since the last frame began; any frame still in flight
    /// may use them, so they join the next frame's garbage (freed only once
    /// that frame, and every frame before it, has finished on the GPU).
    pending:std.ArrayList(Buffer) = .empty,
    stats:Stats = .{},
    /// set before `draw`: copy that frame (UI and all) out for `shot`
    capture:bool = false,
    /// where a captured frame lands, and whether it holds one
    shot_buf:Buffer = .{},
    shot_ready:bool = false,
    /// the GPU's time for each stage of a frame (ms, eased; see `STAGES`)
    gpu_ms:[STAGES]f32 = @splat(0),
    gpu_total:f32 = 0,
    /// the game's own state (see `G.Ext`)
    ext:G.Ext,

    /// `aa` falls back to the most samples the GPU offers (see `antialias`)
    pub fn init(gpa:Allocator, window:*glfw.Window, vsync:bool, aa:Antialias, ext:G.Ext) Error!*R {
      const r = try gpa.create(R);
      errdefer gpa.destroy(r);
      r.* = .{.gpa = gpa, .window = window, .vsync = vsync, .ctx = undefined, .sc = .{}, .ext = ext};
      r.post.aa = aa;
      for (&r.frames) |*f| inline for (reg.ids) |id| {
        if (comptime reg.has(id, "Frame")) @field(f.pass, @tagName(id)) = .{};
      };
      r.ctx = try Ctx.init(gpa, window, G.name);
      errdefer r.ctx.deinit(gpa);
      // everything below starts null, so a half-built renderer frees cleanly
      errdefer r.release();
      r.build() catch |e| return ctx.fold(e);
      if (@hasDecl(G, "start")) try G.start(r);
      return r;
    }

    fn build(r:*R) !void {
      const c = &r.ctx;
      const fb = r.window.getFramebufferSize();
      r.sc = try sw.Swapchain.init(c, r.gpa, @intCast(fb[0]), @intCast(fb[1]), r.vsync, .null_handle);
      r.post = try Post.init(c, r.sc.format.format, r.sc.extent.width, r.sc.extent.height, r.fit(r.post.aa));

      r.shadow = try light.Shadow.init(c);
      for (&r.frames) |*f| {
        f.lighting = try Buffer.init(c, @sizeOf(light.Lighting), .{.storage_buffer = true, .shader_device_address = true});
        f.pool = try c.device.createCommandPool(&.{.flags = .{.reset_command_buffer = true}, .queue_family_index = c.family}, null);
        f.fence = try c.device.createFence(&.{.flags = .{.signaled = true}}, null);
        f.acquired = try c.device.createSemaphore(&.{}, null);
        if (c.props.limits.timestamp_compute_and_graphics == .true) {
          f.queries = try c.device.createQueryPool(&.{.query_type = .timestamp, .query_count = STAMPS}, null);
        }
        inline for (reg.ids) |id| {
          if (comptime reg.has(id, "Frame")) @field(f.pass, @tagName(id)) = try reg.module(id).initFrame(c);
        }
        try c.device.allocateCommandBuffers(&.{.command_pool = f.pool, .level = .primary, .command_buffer_count = 1}, @ptrCast(&f.cmd));
      }

      r.layouts[@intFromEnum(pass.Layout.world)] = try pipeline.layout(c, @sizeOf(Push), &.{r.shadow.set_layout});
      r.layouts[@intFromEnum(pass.Layout.ui)] = try pipeline.layout(c, @sizeOf(ui.Push), &.{});
      try r.makePipes(false);
    }

    /// every pass's pipeline (or with `world_only`, those drawing into the
    /// world, after its sample count changed: the old ones must be destroyed)
    fn makePipes(r:*R, world_only:bool) Error!void {
      const n = r.post.aa.samples();
      inline for (reg.ids) |id| {
        const d = reg.module(id).desc;
        if (!world_only or d.target == .world) {
          r.pipes[@intFromEnum(id)] = try pass.create(&r.ctx, d, r.layout(d.layout), r.sc.format.format, n);
        }
      }
    }

    /// the most samples per pixel both the world's colour and depth can take
    pub fn maxSamples(r:*const R) u32 {
      const l = r.ctx.props.limits;
      const both:u32 = @as(u32, @bitCast(l.framebuffer_color_sample_counts)) & @as(u32, @bitCast(l.framebuffer_depth_sample_counts));
      var n:u32 = 8;
      while (n > 1 and both & n == 0) n /= 2;
      return n;
    }

    /// `aa`, or MSAA with as many samples as the GPU can take
    fn fit(r:*const R, aa:Antialias) Antialias {
      const most = r.maxSamples();
      var a = aa;
      while (a.samples() > most) a = @enumFromInt(@intFromEnum(a) - 1);
      return a;
    }

    /// what the world is smoothed with now
    pub fn antialiasing(r:*const R) Antialias { return r.post.aa; }

    /// smooth edges another way (what the GPU can take of `aa`); waits for
    /// the GPU and remakes the world's images and pipelines
    pub fn antialias(r:*R, aa:Antialias) Error!void {
      const a = r.fit(aa);
      if (a == r.post.aa) return;
      const c = &r.ctx;
      c.device.deviceWaitIdle() catch |e| return ctx.fold(e);
      const remake = a.samples() != r.post.aa.samples();
      try r.post.antialias(c, a);
      if (!remake) return;
      inline for (reg.ids) |id| {
        if (comptime reg.module(id).desc.target == .world) {
          c.device.destroyPipeline(r.pipes[@intFromEnum(id)], null);
          r.pipes[@intFromEnum(id)] = .null_handle;
        }
      }
      try r.makePipes(true);
    }

    /// wait for the display's refresh or not; remakes the swapchain
    pub fn setVsync(r:*R, on:bool) Error!void {
      if (on == r.vsync) return;
      r.vsync = on;
      try r.recreate();
    }

    pub fn pipe(r:*const R, p:Pass) vk.Pipeline { return r.pipes[@intFromEnum(p)]; }
    pub fn layout(r:*const R, l:pass.Layout) vk.PipelineLayout { return r.layouts[@intFromEnum(l)]; }

    pub fn deinit(r:*R) void {
      // nothing to recover: teardown proceeds even if the device was lost
      r.ctx.device.deviceWaitIdle() catch {};
      r.release();
      r.ctx.deinit(r.gpa);
      r.gpa.destroy(r);
    }

    /// free every GPU object the renderer made (null handles are skipped).
    fn release(r:*R) void {
      const c = &r.ctx;
      if (@hasDecl(G, "release")) G.release(r);
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
        f.lighting.deinit(c);
        c.device.destroyQueryPool(f.queries, null);
        c.device.destroySemaphore(f.acquired, null);
        c.device.destroyFence(f.fence, null);
        c.device.destroyCommandPool(f.pool, null);
      }
      r.shot_buf.deinit(c);
      for (r.pipes) |p| c.device.destroyPipeline(p, null);
      for (r.layouts) |l| c.device.destroyPipelineLayout(l, null);
      r.post.deinit(c);
      r.shadow.deinit(c);
      r.sc.deinit(c, r.gpa, false);
    }

    /// free `b` once no frame in flight can still be using it
    pub fn retire(r:*R, b:Buffer) Allocator.Error!void {
      if (b.buf == .null_handle) return;
      try r.pending.append(r.gpa, b);
    }

    fn recreate(r:*R) Error!void {
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
      try r.post.resize(c, r.sc.extent.width, r.sc.extent.height);
    }

    pub fn extent(r:*const R) [2]f32 {
      return .{m.f(r.sc.extent.width), m.f(r.sc.extent.height)};
    }

    pub fn draw(r:*R, scene:*const Scene, resized:bool) Error!void {
      defer r.capture = false;
      r.frame(scene, resized) catch |e| return ctx.fold(e);
    }

    /// the frame last drawn with `capture` set (once; null if none was, or
    /// the swapchain cannot be read). Valid until the next `draw`.
    pub fn shot(r:*R) ?Shot {
      if (!r.shot_ready) return null;
      r.shot_ready = false;
      const w = r.sc.extent.width;
      const h = r.sc.extent.height;
      const bgra = switch (r.sc.format.format) {
        .b8g8r8a8_srgb, .b8g8r8a8_unorm => true,
        else => false,
      };
      return .{.w = w, .h = h, .px = r.shot_buf.map[0 .. @as(usize, w) * h * 4], .bgra = bgra};
    }

    fn frame(r:*R, scene:*const Scene, resized:bool) !void {
      const c = &r.ctx;
      const f = &r.frames[r.fi];
      _ = try c.device.waitForFences(&.{f.fence}, .true, m.maxInt(u64));
      for (f.garbage.items) |*b| b.deinit(c);
      f.garbage.clearRetainingCapacity();
      try f.garbage.appendSlice(r.gpa, r.pending.items);
      r.pending.clearRetainingCapacity();
      r.readTimes(f);

      if (resized) { try r.recreate(); return; }
      const acq = c.device.acquireNextImageKHR(r.sc.handle, m.maxInt(u64), f.acquired, .null_handle) catch |e| switch (e) {
        error.OutOfDateKHR => { try r.recreate(); return; },
        else => return e,
      };
      const img = acq.image_index;
      try c.device.resetFences(&.{f.fence});
      // a capture copies the finished screen into a buffer the CPU reads
      const cap = r.capture and r.sc.readable;
      if (cap) {
        const size = @as(u64, r.sc.extent.width) * r.sc.extent.height * 4;
        if (r.shot_buf.size < size) {
          try r.retire(r.shot_buf);
          r.shot_buf = try Buffer.init(c, size, .{.transfer_dst = true});
        }
      }

      const cmd = vk.CommandBufferProxy.init(f.cmd, c.vkd);
      try cmd.resetCommandBuffer(.{});
      try cmd.beginCommandBuffer(&.{.flags = .{.one_time_submit = true}});
      if (f.queries != .null_handle) cmd.resetQueryPool(f.queries, 0, STAMPS);
      f.stamped = 0;
      stamp(cmd, f, STAGES);
      // every pass's data up, then the shadow casters into the shadow map,
      // the world into the HDR image, its glow, then the screen: the world
      // and its glow composed (and with FXAA filtered), the UI over it
      var stats:Stats = if (@hasDecl(G, "carry")) G.carry(r.stats) else .{};
      stats.gpu_ms = r.gpu_total;
      var sc = scene.*;
      stats.lights = r.lightUp(f, &sc);
      inline for (reg.ids) |id| {
        if (comptime reg.has(id, "prepare")) reg.module(id).prepare(r, &@field(f.pass, @tagName(id)), &sc, &stats);
      }
      r.shadow.begin(cmd);
      r.record(f, cmd, .shadow, &sc, &stats);
      r.shadow.end(cmd);
      r.beginWorld(cmd, scene.clear);
      cmd.bindDescriptorSets(.graphics, r.layout(.world), 0, &.{r.shadow.set}, null);
      r.record(f, cmd, .world, &sc, &stats);
      cmd.endRendering();
      r.post.glow(cmd);
      stamp(cmd, f, GLOW);
      r.beginScreen(cmd, img);
      r.post.compose(cmd, r.sc.extent);
      stamp(cmd, f, COMPOSE);
      r.record(f, cmd, .screen, &sc, &stats);
      r.end(cmd, img, cap);
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
      // decision: a capture waits for its frame (screenshots only)
      if (cap) {
        _ = try c.device.waitForFences(&.{f.fence}, .true, m.maxInt(u64));
        r.shot_ready = true;
      }
      r.fi = (r.fi + 1) % FRAMES;
      r.stats = stats;
      if (pres != .success or acq.result == .suboptimal_khr) try r.recreate();
    }

    /// every pass drawing into `target`, in declaration order
    fn record(r:*R, f:*Frame, cmd:vk.CommandBufferProxy, comptime target:pass.Target, scene:*const Scene, stats:*Stats) void {
      inline for (reg.ids) |id| {
        if (comptime reg.module(id).desc.target == target) {
          reg.module(id).record(r, &@field(f.pass, @tagName(id)), cmd, scene, stats);
          stamp(cmd, f, @intFromEnum(id));
        }
      }
    }

    /// a time stamp once the GPU is through what was recorded before it,
    /// ending `stage`
    fn stamp(cmd:vk.CommandBufferProxy, f:*Frame, stage:u32) void {
      if (f.queries == .null_handle) return;
      cmd.writeTimestamp2(.{.all_commands = true}, f.queries, f.stamped);
      f.stage[f.stamped] = stage;
      f.stamped += 1;
    }

    /// the time stamps `f` wrote when last drawn (its fence is signalled) into
    /// each stage's time and the whole frame's
    fn readTimes(r:*R, f:*Frame) void {
      if (f.stamped < 2) return;
      var t:[STAMPS]u64 = undefined;
      const res = r.ctx.device.getQueryPoolResults(f.queries, 0, f.stamped, f.stamped * @sizeOf(u64), &t, @sizeOf(u64), .{.@"64" = true}) catch return;
      if (res != .success) return;
      const ms_per_tick = r.ctx.props.limits.timestamp_period / m.NS_PER_MS;
      for (1..f.stamped) |i| {
        const ms = m.f(t[i] -% t[i - 1]) * ms_per_tick;
        r.gpu_ms[f.stage[i]] += (ms - r.gpu_ms[f.stage[i]]) * GPU_EASE;
      }
      const whole = m.f(t[f.stamped - 1] -% t[0]) * ms_per_tick;
      r.gpu_total += (whole - r.gpu_total) * GPU_EASE;
    }

    /// write this frame's lighting (the cascades fitted to the view, the
    /// points of light) and point the scene's push constants at it; how many
    /// points it holds
    fn lightUp(r:*R, f:*Frame, scene:*Scene) u32 {
      const p = &scene.push;
      const eye = m.v3(p.eye_time[0], p.eye_time[1], p.eye_time[2]);
      const target = m.v3(p.view[0], 0, p.view[1]);
      // shadows reach the drawn world's far edge as the eye sees it
      const reach = m.len(eye - target) + p.view[3];
      const cas = light.fit(p.vp, eye, target, reach, m.v3(p.sun[0], p.sun[1], p.sun[2]));
      const n:u32 = @intCast(@min(scene.lights.len, light.MAX_LIGHTS));
      var l:light.Lighting = .{
        .cascades = cas.mats, .texel = undefined,
        .info = .{m.f(n), cas.reach, 0, 0},
        .lights = undefined,
      };
      @memcpy(l.texel[0..light.CASCADES], &cas.texel);
      @memcpy(l.lights[0..n], scene.lights[0..n]);
      f.lighting.write(0, asBytes(&l));
      const at = f.lighting.address(&r.ctx);
      p.light = .{@truncate(at), @truncate(at >> 32)};
      return n;
    }

    /// open the world's rendering scope: the HDR image and the depth buffer
    /// (with MSAA, multisampled ones resolved into the HDR image).
    fn beginWorld(r:*R, cmd:vk.CommandBufferProxy, clear:[3]f32) void {
      r.post.beginWorld(cmd);
      const ms = r.post.multisampled();
      sw.barrier(cmd, if (ms) r.post.ms_depth.image else r.sc.depth, sw.depthRange(), .undefined, .depth_attachment_optimal,
        .{.early_fragment_tests = true, .late_fragment_tests = true}, .{.depth_stencil_attachment_write = true},
        .{.early_fragment_tests = true, .late_fragment_tests = true}, .{.depth_stencil_attachment_write = true, .depth_stencil_attachment_read = true});
      const color = [_]vk.RenderingAttachmentInfo{r.post.worldColor(clear)};
      const depth:vk.RenderingAttachmentInfo = .{
        .image_view = if (ms) r.post.ms_depth.views[0] else r.sc.depth_view,
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
    fn beginScreen(r:*R, cmd:vk.CommandBufferProxy, img:u32) void {
      sw.barrier(cmd, r.sc.images[img], sw.colorRange(), .undefined, .color_attachment_optimal,
        .{.color_attachment_output = true}, .{},
        .{.color_attachment_output = true}, .{.color_attachment_write = true});
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

    fn scope(r:*R, cmd:vk.CommandBufferProxy, color:[]const vk.RenderingAttachmentInfo, depth:?*const vk.RenderingAttachmentInfo) void {
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

    /// close the rendering scope and hand the image to presentation (with
    /// `cap`, copied into `shot_buf` on the way).
    fn end(r:*R, cmd:vk.CommandBufferProxy, img:u32, cap:bool) void {
      cmd.endRendering();
      if (cap) r.copyOut(cmd, img);
      sw.barrier(cmd, r.sc.images[img], sw.colorRange(), if (cap) .transfer_src_optimal else .color_attachment_optimal, .present_src_khr,
        if (cap) .{.copy = true} else .{.color_attachment_output = true}, if (cap) .{} else .{.color_attachment_write = true},
        .{}, .{});
    }

    /// the screen image into `shot_buf`, left as a transfer's source
    fn copyOut(r:*R, cmd:vk.CommandBufferProxy, img:u32) void {
      sw.barrier(cmd, r.sc.images[img], sw.colorRange(), .color_attachment_optimal, .transfer_src_optimal,
        .{.color_attachment_output = true}, .{.color_attachment_write = true},
        .{.copy = true}, .{.transfer_read = true});
      cmd.copyImageToBuffer(r.sc.images[img], .transfer_src_optimal, r.shot_buf.buf, &.{.{
        .buffer_offset = 0,
        .buffer_row_length = 0,
        .buffer_image_height = 0,
        .image_subresource = .{.aspect_mask = .{.color = true}, .mip_level = 0, .base_array_layer = 0, .layer_count = 1},
        .image_offset = .{.x = 0, .y = 0, .z = 0},
        .image_extent = .{.width = r.sc.extent.width, .height = r.sc.extent.height, .depth = 1},
      }});
      // the host reads it once the frame's fence is signalled
      const done = [_]vk.MemoryBarrier2{.{
        .src_stage_mask = .{.copy = true},
        .src_access_mask = .{.transfer_write = true},
        .dst_stage_mask = .{.host = true},
        .dst_access_mask = .{.host_read = true},
      }};
      cmd.pipelineBarrier2(&.{.memory_barrier_count = done.len, .p_memory_barriers = &done});
    }

    fn submit(r:*R, f:*Frame, img:u32) !void {
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
}
