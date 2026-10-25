//! frame orchestration: acquire, record every pass, submit, present. What
//! gets drawn lives in the pass modules under `passes/` (shape in `pass`
//! below); they record in the order listed in `passes`, by target: the
//! shadow casters into the key light's shadow map, then the world into the
//! HDR image, then the screen. A new pass is one new file plus one line.
const std = @import("std");
const Allocator = std.mem.Allocator;
const sliceAsBytes = std.mem.sliceAsBytes;
const ArenaAllocator = std.heap.ArenaAllocator;
const Thread = std.Thread;
const Atomic = std.atomic.Value;
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
const vertex = @import("../gfx/vertex.zig");
const meshgen = @import("../gfx/meshgen.zig");
const meshlib = @import("../gfx/meshlib.zig");
const species = @import("../sim/species.zig");
const World = @import("../world/world.zig").World;
const ck = @import("../world/chunk.zig");
const terrain_mesh = @import("terrain_mesh.zig");
const jobs = @import("../core/jobs.zig");
const post_mod = @import("post.zig");
const light = @import("light.zig");
const Post = post_mod.Post;
const HDR_FORMAT = post_mod.HDR_FORMAT;
pub const Antialias = post_mod.Antialias;

/// the shape of a render pass module (see passes/). Each pass declares
///   desc:Desc                          its shaders, vertex layout and state
///   Frame                              per-frame resources (optional)
///   initFrame(c) Error!Frame / deinitFrame(*Frame, c)
///                                      (Frame fields default to empty)
///   prepare(r, *Frame, scene, stats)   upload this frame's data (optional;
///                                      every pass's, before any draws)
///   record(r, *Frame, cmd, scene, stats) draw it
/// Passes record in declaration order inside their target's scope.
pub const pass = struct {
  /// which push-constant block the pass uses.
  pub const Layout = enum { world, ui };
  /// what a pass draws into: the key light's shadow map (depth alone, every
  /// cascade at once), the world's HDR image, or the screen after the world
  /// (and its glow): the UI
  pub const Target = enum { shadow, world, screen };

  pub const Desc = struct {
    vert:[]const u8,
    frag:[]const u8,
    bindings:[]const vk.VertexInputBindingDescription,
    attrs:[]const vk.VertexInputAttributeDescription,
    layout:Layout = .world,
    depth:bool = true,
    /// with `depth`: whether it writes depth (a glass pass only tests it)
    depth_write:bool = true,
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
      .depth = d.depth, .depth_write = d.depth_write, .depth_attachment = d.target != .screen, .blend = d.blend, .cull = false,
      .samples = post_mod.sampleFlags(if (d.target == .world) samples else 1), .per_sample = d.per_sample,
      .view_mask = if (d.target == .shadow) light.VIEWS else 0,
      .depth_bias = if (d.target == .shadow) light.BIAS else null,
    });
  }
};

const passes = struct {
  // what casts the key light's shadows, drawn first into its shadow map
  pub const plants_shadow = @import("passes/plants.zig").shadow;
  pub const parts_shadow = @import("passes/parts.zig").shadow;
  pub const sky = @import("passes/sky.zig");
  pub const terrain = @import("passes/terrain.zig");
  pub const detail = @import("passes/detail.zig");
  pub const plants = @import("passes/plants.zig");
  pub const parts = @import("passes/parts.zig");
  // see-through fragments of plants and parts, over every solid one
  pub const plants_glass = @import("passes/plants.zig").glass;
  pub const parts_glass = @import("passes/parts.zig").glass;
  pub const ui = @import("passes/ui.zig");
};
const reg = registry.Registry(passes);
pub const Pass = reg.Id;

pub const FRAMES = 2;
/// points of light a frame can hold (the rest of `Scene.lights` is dropped)
pub const MAX_LIGHTS = light.MAX_LIGHTS;
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
  /// where the parts pass finds this frame's bones (a buffer address; 0 in
  /// every other pass)
  bones:[2]u32 = .{0, 0},
  /// where every pass finds this frame's `light.Lighting` (a buffer
  /// address, set by the renderer)
  light:[2]u32 = .{0, 0},
};

pub const Scene = struct {
  push:WorldPush,
  clear:[3]f32,
  /// plant instances grouped by mesh variant (see meshgen.plantSlot).
  instances:[PLANT_MESHES][]const vertex.PlantInstance,
  /// rigid part instances grouped by mesh (player, nodes, motes, ...).
  parts:[meshlib.SLOTS][]const vertex.PartInstance,
  /// skinned parts' bones (see `vertex.Skin`): each matrix carries a vertex
  /// from where it was built to where it is this frame
  bones:[]const m.M4,
  /// points of light, most telling first (the renderer takes the first
  /// `light.MAX_LIGHTS`)
  lights:[]const vertex.Light,
  ui:[]const vertex.Ui,
  /// UI clock (keeps running while the world is paused)
  ui_time:f32,
};

/// a captured frame: 4 bytes a pixel, row by row from the top
pub const Shot = struct { w:u32, h:u32, px:[]const u8, bgra:bool };

pub const Stats = struct { draws:u32 = 0, chunks:u32 = 0, instances:u32 = 0, parts:u32 = 0, meshed:u32 = 0, lights:u32 = 0 };

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
  /// buffers retired while this frame was in flight; freed when it comes round again.
  garbage:std.ArrayList(Buffer) = .empty,
};

/// a sphere around a chunk (from its centre, `CHUNK_MID_Y` up) holding all
/// of it, its terraces and what grows on its tiles, for culling it to the
/// view: half its diagonal (rounded up) and a margin
pub const CHUNK_MID_Y:f32 = 1.5;
pub const CHUNK_RADIUS:f32 = m.f(ck.SIZE) * 0.71 + 2;

/// milliseconds a frame may spend meshing streamed chunks
pub const MESH_MS:f64 = 3;
/// streamed chunks meshed together over the pool, each into its own scratch
const MESH_BATCH = 8;
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

/// every built-once mesh (plant species + part library), grown on a thread
/// of its own while the loading screen shows, one mesh at one level of
/// detail at a time (`done` of `UNITS`); `Renderer.meshesReady` takes them
/// in once it is through.
const Growing = struct {
  /// the builder's vertices are scratch: one arena, freed in one go once uploaded
  arena:ArenaAllocator,
  b:meshgen.Builder = undefined,
  thread:?Thread = null,
  done:Atomic(u32) = .init(0),
  finished:Atomic(bool) = .init(false),
  /// set when the renderer goes before the meshes are through: stop early
  stop:Atomic(bool) = .init(false),
  failed:bool = false,
  plant_ranges:[PLANT_MESHES][2]u32 = @splat(.{0, 0}),
  plant_morph:[PLANT_MESHES]u64 = @splat(0),
  part_ranges:[meshlib.SLOTS][2]u32 = undefined,
  part_glassy:[meshlib.SLOTS]bool = @splat(false),

  /// each species' variants at one level of detail, then each library mesh
  /// at one level of detail
  const UNITS:u32 = @intCast((species.ids.len + meshlib.count) * meshgen.LODS);

  fn run(g:*Growing) void {
    g.failed = std.meta.isError(g.all());
    g.finished.store(true, .release);
  }

  fn all(g:*Growing) Allocator.Error!void {
    const b = &g.b;
    for (species.ids) |id| for (0..meshgen.LODS) |l| {
      if (g.stop.load(.monotonic)) return;
      const lod:u32 = @intCast(l);
      b.lod = lod;
      const n = meshgen.variants(id);
      for (0..n) |v| {
        const first:u32 = @intCast(b.v.items.len);
        try meshgen.plant(b, id, @intCast(v));
        g.plant_ranges[meshgen.plantSlot(id, @intCast(v), lod)] = .{first, @as(u32, @intCast(b.v.items.len)) - first};
      }
      // growth keys blend vertex for vertex into the next key
      if (meshgen.growthKey(id, 0) != null) for (0..n - 1) |v| {
        const a = g.plant_ranges[meshgen.plantSlot(id, @intCast(v), lod)];
        const z = g.plant_ranges[meshgen.plantSlot(id, @intCast(v + 1), lod)];
        if (a[1] != z[1]) @panic("growth keys differ in vertex count");
        g.plant_morph[meshgen.plantSlot(id, @intCast(v), lod)] = @as(u64, z[0] - a[0]) * @sizeOf(vertex.Mesh);
      };
      _ = g.done.fetchAdd(1, .monotonic);
    };
    for (0..meshgen.LODS) |l| for (0..meshlib.count) |i| {
      if (g.stop.load(.monotonic)) return;
      try meshlib.buildOne(b, @enumFromInt(i), @intCast(l), &g.part_ranges);
      _ = g.done.fetchAdd(1, .monotonic);
    };
    b.lod = 0;
    for (&g.part_glassy, g.part_ranges) |*gl, rg| {
      for (b.v.items[rg[0]..][0..rg[1]]) |v| if (vertex.seeThrough(@enumFromInt(v.part))) {
        gl.* = true;
        break;
      };
    }
    _ = try b.skinOf(b.v.items.len);
    _ = try b.growOf(b.v.items.len);
  }

  /// wait for the thread (asked to stop early) and free what it built
  fn end(g:*Growing, gpa:Allocator) void {
    g.stop.store(true, .monotonic);
    if (g.thread) |t| t.join();
    g.arena.deinit();
    gpa.destroy(g);
  }
};

pub const Renderer = struct {
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
  /// terrain chunk meshes (see syncWorld)
  slots:std.ArrayList(Slot) = .empty,
  free_slots:std.ArrayList(ck.MeshSlot) = .empty,
  /// every built-once mesh (plant species + part library) in one buffer.
  meshes:Buffer = .{},
  /// each vertex of `meshes`' skin weights (zero where a mesh is not skinned)
  skins:Buffer = .{},
  /// beside `meshes`: where each vertex grows out of (`vertex.Grow`)
  grows:Buffer = .{},
  /// (first vertex, count) per plant slot; slots a species does not use are empty
  plant_ranges:[PLANT_MESHES][2]u32 = @splat(.{0, 0}),
  /// per plant slot, the byte offset from its mesh to the next growth key's
  /// (the plant shader blends toward it); 0 where a species has no keys
  plant_morph:[PLANT_MESHES]u64 = @splat(0),
  part_ranges:[meshlib.SLOTS][2]u32 = undefined,
  /// per part slot: whether any of its vertices can be see-through (sap,
  /// resin, shadow, beam, halo); the glass pass draws only those
  part_glassy:[meshlib.SLOTS]bool = @splat(false),
  /// one chunk's ground and detail per place in a meshing batch
  scratch:[MESH_BATCH]std.ArrayList(vertex.Terrain) = @splat(.empty),
  detail_scratch:[MESH_BATCH]std.ArrayList(vertex.DetailTile) = @splat(.empty),
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
  /// the meshes while they are still growing (see `meshesReady`)
  growing:?*Growing = null,

  /// `aa` falls back to the most samples the GPU offers (see `antialias`)
  pub fn init(gpa:Allocator, window:*glfw.Window, vsync:bool, aa:Antialias) Error!*Renderer {
    const r = try gpa.create(Renderer);
    errdefer gpa.destroy(r);
    r.* = .{.gpa = gpa, .window = window, .vsync = vsync, .ctx = undefined, .sc = .{}};
    r.post.aa = aa;
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
    r.post = try Post.init(c, r.sc.format.format, r.sc.extent.width, r.sc.extent.height, r.fit(r.post.aa));

    r.shadow = try light.Shadow.init(c);
    for (&r.frames) |*f| {
      f.lighting = try Buffer.init(c, @sizeOf(light.Lighting), .{.storage_buffer = true, .shader_device_address = true});
      f.pool = try c.device.createCommandPool(&.{.flags = .{.reset_command_buffer = true}, .queue_family_index = c.family}, null);
      f.fence = try c.device.createFence(&.{.flags = .{.signaled = true}}, null);
      f.acquired = try c.device.createSemaphore(&.{}, null);
      inline for (reg.ids) |id| {
        if (comptime reg.has(id, "Frame")) @field(f.pass, @tagName(id)) = try reg.module(id).initFrame(c);
      }
      try c.device.allocateCommandBuffers(&.{.command_pool = f.pool, .level = .primary, .command_buffer_count = 1}, @ptrCast(&f.cmd));
    }

    r.layouts[@intFromEnum(pass.Layout.world)] = try pipeline.layout(c, @sizeOf(WorldPush), &.{r.shadow.set_layout});
    r.layouts[@intFromEnum(pass.Layout.ui)] = try pipeline.layout(c, @sizeOf(passes.ui.Push), &.{});
    try r.makePipes(false);
    try r.growMeshes();
  }

  /// every pass's pipeline (or with `world_only`, those drawing into the
  /// world, after its sample count changed: the old ones must be destroyed)
  fn makePipes(r:*Renderer, world_only:bool) Error!void {
    const n = r.post.aa.samples();
    inline for (reg.ids) |id| {
      const d = reg.module(id).desc;
      if (!world_only or d.target == .world) {
        r.pipes[@intFromEnum(id)] = try pass.create(&r.ctx, d, r.layout(d.layout), r.sc.format.format, n);
      }
    }
  }

  /// the most samples per pixel both the world's colour and depth can take
  pub fn maxSamples(r:*const Renderer) u32 {
    const l = r.ctx.props.limits;
    const both:u32 = @as(u32, @bitCast(l.framebuffer_color_sample_counts)) & @as(u32, @bitCast(l.framebuffer_depth_sample_counts));
    var n:u32 = 8;
    while (n > 1 and both & n == 0) n /= 2;
    return n;
  }

  /// `aa`, or MSAA with as many samples as the GPU can take
  fn fit(r:*const Renderer, aa:Antialias) Antialias {
    const most = r.maxSamples();
    var a = aa;
    while (a.samples() > most) a = @enumFromInt(@intFromEnum(a) - 1);
    return a;
  }

  /// what the world is smoothed with now
  pub fn antialiasing(r:*const Renderer) Antialias { return r.post.aa; }

  /// smooth edges another way (what the GPU can take of `aa`); waits for
  /// the GPU and remakes the world's images and pipelines
  pub fn antialias(r:*Renderer, aa:Antialias) Error!void {
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
  pub fn setVsync(r:*Renderer, on:bool) Error!void {
    if (on == r.vsync) return;
    r.vsync = on;
    try r.recreate();
  }

  pub fn pipe(r:*const Renderer, p:Pass) vk.Pipeline { return r.pipes[@intFromEnum(p)]; }
  pub fn layout(r:*const Renderer, l:pass.Layout) vk.PipelineLayout { return r.layouts[@intFromEnum(l)]; }

  /// start growing every species' mesh and every library part on a thread
  /// of their own (here, if no thread can be had)
  fn growMeshes(r:*Renderer) Allocator.Error!void {
    const g = try r.gpa.create(Growing);
    g.* = .{.arena = ArenaAllocator.init(r.gpa)};
    g.b = .{.gpa = g.arena.allocator()};
    r.growing = g;
    g.thread = Thread.spawn(.{}, Growing.run, .{g}) catch |e| blk: {
      std.log.warn("meshes grown without a thread: {t}", .{e});
      g.run();
      break :blk null;
    };
  }

  /// how many of the meshes' units are grown, of how many
  pub fn meshProgress(r:*const Renderer) [2]u32 {
    const g = r.growing orelse return .{Growing.UNITS, Growing.UNITS};
    return .{g.done.load(.monotonic), Growing.UNITS};
  }

  /// whether every mesh is grown and in one buffer: once they are through,
  /// uploads them (the first call after that) and frees the scratch. The
  /// world can be drawn only after this says so.
  pub fn meshesReady(r:*Renderer) Error!bool {
    const g = r.growing orelse return true;
    if (!g.finished.load(.acquire)) return false;
    if (g.thread) |t| t.join();
    g.thread = null;
    defer {
      g.end(r.gpa);
      r.growing = null;
    }
    if (g.failed) return error.OutOfMemory;
    const b = &g.b;
    r.plant_ranges = g.plant_ranges;
    r.plant_morph = g.plant_morph;
    r.part_ranges = g.part_ranges;
    r.part_glassy = g.part_glassy;
    const bytes = sliceAsBytes(b.v.items);
    r.meshes = try Buffer.init(&r.ctx, bytes.len, .{.vertex_buffer = true});
    r.meshes.write(0, bytes);
    const skin = sliceAsBytes(b.skin.items);
    r.skins = try Buffer.init(&r.ctx, skin.len, .{.vertex_buffer = true});
    r.skins.write(0, skin);
    const grow = sliceAsBytes(b.grow.items);
    r.grows = try Buffer.init(&r.ctx, grow.len, .{.vertex_buffer = true});
    r.grows.write(0, grow);
    return true;
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
    if (r.growing) |g| g.end(r.gpa);
    r.growing = null;
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
    for (&r.scratch, &r.detail_scratch) |*v, *d| {
      v.deinit(r.gpa);
      d.deinit(r.gpa);
    }
    r.meshes.deinit(c);
    r.skins.deinit(c);
    r.grows.deinit(c);
    r.shot_buf.deinit(c);
    for (r.pipes) |p| c.device.destroyPipeline(p, null);
    for (r.layouts) |l| c.device.destroyPipelineLayout(l, null);
    r.post.deinit(c);
    r.shadow.deinit(c);
    r.sc.deinit(c, r.gpa, false);
  }

  fn retire(r:*Renderer, b:Buffer) Allocator.Error!void {
    if (b.buf == .null_handle) return;
    try r.pending.append(r.gpa, b);
  }

  /// forget every chunk mesh: the world was replaced (e.g. a save was loaded).
  pub fn dropWorld(r:*Renderer) Allocator.Error!void {
    for (r.slots.items) |s| {
      try r.retire(s.buf);
      try r.retire(s.detail);
    }
    r.slots.clearRetainingCapacity();
    r.free_slots.clearRetainingCapacity();
  }

  /// upload meshes for new/dirty chunks (at most `budget`, and no more once
  /// `ms` milliseconds are spent) and drop evicted ones.
  pub fn syncWorld(r:*Renderer, w:*World, budget:u32, ms:f64) Error!void {
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
    // dirty chunks a batch at a time: meshed together over the pool, then
    // uploaded here. At most `budget` chunks, and no more batches once a
    // frame's share of time is spent (at least one, so streaming moves on).
    while (r.stats.meshed < budget) {
      if (r.stats.meshed > 0 and (glfw.getTime() - start) * m.MS_PER_S > ms) break;
      var batch:[MESH_BATCH]*ck.Chunk = undefined;
      var n:usize = 0;
      var it = w.map.valueIterator();
      while (it.next()) |cp| {
        if (n == batch.len or r.stats.meshed + n >= budget) break;
        if (cp.*.dirty) {
          batch[n] = cp.*;
          n += 1;
        }
      }
      if (n == 0) break;
      var failed:[MESH_BATCH]?Allocator.Error = @splat(null);
      jobs.each(w.io, n, 1, Meshing, .{
        .gpa = r.gpa, .seed = w.seed, .cs = batch[0..n],
        .out = r.scratch[0..n], .detail = r.detail_scratch[0..n], .failed = failed[0..n],
      }, Meshing.run);
      for (failed[0..n]) |e| if (e) |err| return err;
      for (batch[0..n], r.scratch[0..n], r.detail_scratch[0..n]) |c, vs, ds| try r.upload(c, vs.items, ds.items);
    }
  }

  /// one range of a batch of chunks' ground meshed, each into its own scratch
  const Meshing = struct {
    gpa:Allocator,
    seed:u64,
    cs:[]const *ck.Chunk,
    out:[]std.ArrayList(vertex.Terrain),
    detail:[]std.ArrayList(vertex.DetailTile),
    failed:[]?Allocator.Error,

    fn run(j:Meshing, lo:usize, hi:usize) void {
      for (lo..hi) |k| terrain_mesh.build(j.gpa, j.seed, j.cs[k], &j.out[k], &j.detail[k]) catch |e| {
        j.failed[k] = e;
      };
    }
  };

  /// a meshed chunk's ground and detail into buffers of its own slot (the
  /// old ones retired), and it is clean
  fn upload(r:*Renderer, c:*ck.Chunk, verts:[]const vertex.Terrain, tiles:[]const vertex.DetailTile) Error!void {
    const bytes = sliceAsBytes(verts);
    var buf = try Buffer.init(&r.ctx, @max(bytes.len, MIN_CHUNK_BYTES), .{.vertex_buffer = true});
    errdefer buf.deinit(&r.ctx);
    buf.write(0, bytes);
    const dbytes = sliceAsBytes(tiles);
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
      .buf = buf, .count = @intCast(verts.len), .live = true,
      .detail = detail, .tiles = @intCast(tiles.len),
      .centre = .{m.f(c.originX()) + half, m.f(c.originY()) + half},
    };
    c.dirty = false;
    r.stats.meshed += 1;
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
    try r.post.resize(c, r.sc.extent.width, r.sc.extent.height);
  }

  pub fn extent(r:*const Renderer) [2]f32 {
    return .{m.f(r.sc.extent.width), m.f(r.sc.extent.height)};
  }

  pub fn draw(r:*Renderer, scene:*const Scene, resized:bool) Error!void {
    defer r.capture = false;
    r.frame(scene, resized) catch |e| return ctx.fold(e);
  }

  /// the frame last drawn with `capture` set (once; null if none was, or
  /// the swapchain cannot be read). Valid until the next `draw`.
  pub fn shot(r:*Renderer) ?Shot {
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
    // every pass's data up, then the shadow casters into the shadow map,
    // the world into the HDR image, its glow, then the screen: the world
    // and its glow composed (and with FXAA filtered), the UI over it
    var stats:Stats = .{.meshed = r.stats.meshed};
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
    r.beginScreen(cmd, img);
    r.post.compose(cmd, r.sc.extent);
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
  fn record(r:*Renderer, f:*Frame, cmd:vk.CommandBufferProxy, comptime target:pass.Target, scene:*const Scene, stats:*Stats) void {
    inline for (reg.ids) |id| {
      if (comptime reg.module(id).desc.target == target) reg.module(id).record(r, &@field(f.pass, @tagName(id)), cmd, scene, stats);
    }
  }

  /// write this frame's lighting (the cascades fitted to the view, the
  /// points of light) and point the scene's push constants at it; how many
  /// points it holds
  fn lightUp(r:*Renderer, f:*Frame, scene:*Scene) u32 {
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
  fn beginWorld(r:*Renderer, cmd:vk.CommandBufferProxy, clear:[3]f32) void {
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
  fn beginScreen(r:*Renderer, cmd:vk.CommandBufferProxy, img:u32) void {
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

  /// close the rendering scope and hand the image to presentation (with
  /// `cap`, copied into `shot_buf` on the way).
  fn end(r:*Renderer, cmd:vk.CommandBufferProxy, img:u32, cap:bool) void {
    cmd.endRendering();
    if (cap) r.copyOut(cmd, img);
    sw.barrier(cmd, r.sc.images[img], sw.colorRange(), if (cap) .transfer_src_optimal else .color_attachment_optimal, .present_src_khr,
      if (cap) .{.copy = true} else .{.color_attachment_output = true}, if (cap) .{} else .{.color_attachment_write = true},
      .{}, .{});
  }

  /// the screen image into `shot_buf`, left as a transfer's source
  fn copyOut(r:*Renderer, cmd:vk.CommandBufferProxy, img:u32) void {
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
