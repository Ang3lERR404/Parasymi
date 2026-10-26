//! the garden's renderer: the engine's frame orchestration (engine
//! render/renderer.zig) given the garden's passes (under `passes/`), push
//! constants and scene, and the state it keeps beside them: every grown
//! mesh (plant species and part library, grown on a thread while the
//! loading screen shows) and each streamed chunk's ground. A new pass is
//! one new file plus one line in `passes`.
const std = @import("std");
const Allocator = std.mem.Allocator;
const sliceAsBytes = std.mem.sliceAsBytes;
const ArenaAllocator = std.heap.ArenaAllocator;
const Thread = std.Thread;
const Atomic = std.atomic.Value;
const engine = @import("engine");
const glfw = engine.glfw;
const m = engine.core.math;
const jobs = engine.core.jobs;
const Buffer = engine.gfx.buffer.Buffer;
const er = engine.render.renderer;
const vertex = @import("../gfx/vertex.zig");
const meshgen = @import("../gfx/meshgen.zig");
const meshlib = @import("../gfx/meshlib.zig");
const species = @import("../sim/species.zig");
const World = @import("../world/world.zig").World;
const ck = @import("../world/chunk.zig");
const terrain_mesh = @import("terrain_mesh.zig");

pub const name = "Parasymi";
pub const Renderer = er.Renderer(@This());
pub const Pass = Renderer.Pass;
pub const pass = er.pass;
pub const Antialias = er.Antialias;
pub const Shot = er.Shot;
pub const Error = er.Error;
pub const FRAMES = er.FRAMES;
/// points of light a frame can hold (the rest of `Scene.lights` is dropped)
pub const MAX_LIGHTS = er.MAX_LIGHTS;
pub const STAGES = Renderer.STAGES;
pub const GLOW = Renderer.GLOW;
pub const COMPOSE = Renderer.COMPOSE;

pub const passes = struct {
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
  pub const ui = er.ui;
};

/// every grown plant mesh: each species in each of its variants.
pub const PLANT_MESHES = species.count * meshgen.MAX_VARIANTS * meshgen.LODS;

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
  /// where every pass finds this frame's lighting (a buffer address, set by
  /// the renderer)
  light:[2]u32 = .{0, 0},
};
pub const Push = WorldPush;
comptime {
  if (@sizeOf(WorldPush) > 192) @compileError("WorldPush must stay within 192 bytes");
}

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
  /// `MAX_LIGHTS`)
  lights:[]const vertex.Light,
  ui:[]const vertex.Ui,
  /// UI clock (keeps running while the world is paused)
  ui_time:f32,
};

/// `gpu_ms`: the GPU's time for a whole frame (eased; 0 where it keeps no time stamps)
pub const Stats = struct { draws:u32 = 0, chunks:u32 = 0, instances:u32 = 0, parts:u32 = 0, meshed:u32 = 0, lights:u32 = 0, gpu_ms:f32 = 0 };

/// a frame's counts start from how many chunks were meshed before it
pub fn carry(prev:Stats) Stats { return .{.meshed = prev.meshed}; }

/// the mesh a caster drawn from `slot` (a plant's or a part's) casts with:
/// the same mesh at its coarsest level of detail (a slot table lays each
/// mesh's levels side by side). A shadow needs no fine detail, and every
/// caster is drawn into every cascade.
pub fn caster(slot:usize) usize { return slot - slot % meshgen.LODS + meshgen.LODS - 1; }

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

/// the meshes built when one thing stands alone (`--plant`, `--structure`):
/// one species' (or none) and these library meshes
pub const Only = struct {
  species:?species.Id = null,
  parts:[]const meshlib.Id,
};

/// what the garden keeps on the renderer (`r.ext`)
pub const Ext = struct {
  /// with `only`, those meshes alone are built (`--plant`, `--structure`)
  only:?Only = null,
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
  part_ranges:[meshlib.SLOTS][2]u32 = @splat(.{0, 0}),
  /// per part slot: whether any of its vertices can be see-through (sap,
  /// resin, shadow, beam, halo); the glass pass draws only those
  part_glassy:[meshlib.SLOTS]bool = @splat(false),
  /// one chunk's ground and detail per place in a meshing batch
  scratch:[MESH_BATCH]std.ArrayList(vertex.Terrain) = @splat(.empty),
  detail_scratch:[MESH_BATCH]std.ArrayList(vertex.DetailTile) = @splat(.empty),
  /// the meshes while they are still growing (see `meshesReady`)
  growing:?*Growing = null,
};

/// every built-once mesh (plant species + part library), grown on a thread
/// of its own while the loading screen shows, one mesh at one level of
/// detail at a time (`done` of `units`); `meshesReady` takes them in once
/// it is through.
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
  part_ranges:[meshlib.SLOTS][2]u32 = @splat(.{0, 0}),
  part_glassy:[meshlib.SLOTS]bool = @splat(false),
  /// `--plant`/`--structure`: those meshes alone; every other range stays
  /// empty, so draws of it draw nothing
  only:?Only = null,

  /// each species' variants at one level of detail, then each library mesh
  /// at one level of detail
  fn units(g:*const Growing) u32 {
    const n = if (g.only) |o| @as(usize, if (o.species != null) 1 else 0) + o.parts.len else species.ids.len + meshlib.count;
    return @intCast(n * meshgen.LODS);
  }

  fn run(g:*Growing) void {
    g.failed = std.meta.isError(g.all());
    g.finished.store(true, .release);
  }

  fn all(g:*Growing) Allocator.Error!void {
    const b = &g.b;
    for (species.ids) |id| for (0..meshgen.LODS) |l| {
      if (g.stop.load(.monotonic)) return;
      if (g.only) |o| if (o.species != id) continue;
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
    const lib:[]const meshlib.Id = if (g.only) |o| o.parts else meshlib.ids;
    for (0..meshgen.LODS) |l| for (lib) |id| {
      if (g.stop.load(.monotonic)) return;
      try meshlib.buildOne(b, id, @intCast(l), &g.part_ranges);
      _ = g.done.fetchAdd(1, .monotonic);
    };
    b.lod = 0;
    glassy(b.v.items, &g.part_ranges, &g.part_glassy);
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

/// start growing every species' mesh and every library part on a thread
/// of their own (here, if no thread can be had)
pub fn start(r:*Renderer) Error!void {
  const g = try r.gpa.create(Growing);
  g.* = .{.arena = ArenaAllocator.init(r.gpa), .only = r.ext.only};
  g.b = .{.gpa = g.arena.allocator()};
  r.ext.growing = g;
  g.thread = Thread.spawn(.{}, Growing.run, .{g}) catch |e| blk: {
    std.log.warn("meshes grown without a thread: {t}", .{e});
    g.run();
    break :blk null;
  };
}

/// free what the garden keeps on the renderer (null handles are skipped)
pub fn release(r:*Renderer) void {
  const c = &r.ctx;
  const x = &r.ext;
  if (x.growing) |g| g.end(r.gpa);
  x.growing = null;
  for (x.slots.items) |*s| {
    s.buf.deinit(c);
    s.detail.deinit(c);
  }
  x.slots.deinit(r.gpa);
  x.free_slots.deinit(r.gpa);
  for (&x.scratch, &x.detail_scratch) |*v, *d| {
    v.deinit(r.gpa);
    d.deinit(r.gpa);
  }
  x.meshes.deinit(c);
  x.skins.deinit(c);
  x.grows.deinit(c);
}

/// how many of the meshes' units are grown, of how many
pub fn meshProgress(r:*const Renderer) [2]u32 {
  const g = r.ext.growing orelse return .{1, 1};
  return .{g.done.load(.monotonic), g.units()};
}

/// whether every mesh is grown and in one buffer: once they are through,
/// uploads them (the first call after that) and frees the scratch. The
/// world can be drawn only after this says so.
pub fn meshesReady(r:*Renderer) Error!bool {
  const x = &r.ext;
  const g = x.growing orelse return true;
  if (!g.finished.load(.acquire)) return false;
  if (g.thread) |t| t.join();
  g.thread = null;
  defer {
    g.end(r.gpa);
    x.growing = null;
  }
  if (g.failed) return error.OutOfMemory;
  const b = &g.b;
  x.plant_ranges = g.plant_ranges;
  x.plant_morph = g.plant_morph;
  x.part_ranges = g.part_ranges;
  x.part_glassy = g.part_glassy;
  // read by every plant and part draw, every frame: in device memory
  x.meshes = try Buffer.initWith(&r.ctx, .{.vertex_buffer = true}, sliceAsBytes(b.v.items));
  x.skins = try Buffer.initWith(&r.ctx, .{.vertex_buffer = true}, sliceAsBytes(b.skin.items));
  x.grows = try Buffer.initWith(&r.ctx, .{.vertex_buffer = true}, sliceAsBytes(b.grow.items));
  return true;
}

/// per part slot: whether any of its run of `verts` can be see-through
fn glassy(verts:[]const vertex.Mesh, ranges:*const [meshlib.SLOTS][2]u32, out:*[meshlib.SLOTS]bool) void {
  for (out, ranges) |*gl, rg| {
    gl.* = false;
    for (verts[rg[0]..][0..rg[1]]) |v| if (vertex.seeThrough(@enumFromInt(v.part))) {
      gl.* = true;
      break;
    };
  }
}

/// put the meshes `b` holds in place of every built-once mesh, each part
/// slot drawing its run of `ranges` and plants nothing: a tool remaking a
/// mesh as it is edited (tools/meshedit.zig). The old buffers go once no
/// frame in flight reads them; with nothing in `b` they stay, drawn by no slot.
pub fn setParts(r:*Renderer, b:*meshgen.Builder, ranges:[meshlib.SLOTS][2]u32) Error!void {
  const x = &r.ext;
  x.plant_ranges = @splat(.{0, 0});
  x.plant_morph = @splat(0);
  if (b.v.items.len == 0) {
    x.part_ranges = @splat(.{0, 0});
    x.part_glassy = @splat(false);
    return;
  }
  _ = try b.skinOf(b.v.items.len);
  _ = try b.growOf(b.v.items.len);
  x.part_ranges = ranges;
  glassy(b.v.items, &x.part_ranges, &x.part_glassy);
  try r.retire(x.meshes);
  try r.retire(x.skins);
  try r.retire(x.grows);
  x.meshes = .{};
  x.skins = .{};
  x.grows = .{};
  x.meshes = try Buffer.initWith(&r.ctx, .{.vertex_buffer = true}, sliceAsBytes(b.v.items));
  x.skins = try Buffer.initWith(&r.ctx, .{.vertex_buffer = true}, sliceAsBytes(b.skin.items));
  x.grows = try Buffer.initWith(&r.ctx, .{.vertex_buffer = true}, sliceAsBytes(b.grow.items));
}

/// forget every chunk mesh: the world was replaced (e.g. a save was loaded).
pub fn dropWorld(r:*Renderer) Allocator.Error!void {
  for (r.ext.slots.items) |s| {
    try r.retire(s.buf);
    try r.retire(s.detail);
  }
  r.ext.slots.clearRetainingCapacity();
  r.ext.free_slots.clearRetainingCapacity();
}

/// upload meshes for new/dirty chunks (at most `budget`, and no more once
/// `ms` milliseconds are spent) and drop evicted ones.
pub fn syncWorld(r:*Renderer, w:*World, budget:u32, ms:f64) Error!void {
  const x = &r.ext;
  for (w.evicted.items) |si| {
    const i = @intFromEnum(si);
    try r.retire(x.slots.items[i].buf);
    try r.retire(x.slots.items[i].detail);
    x.slots.items[i] = .{};
    try x.free_slots.append(r.gpa, si);
  }
  w.evicted.clearRetainingCapacity();

  r.stats.meshed = 0;
  const begun = glfw.getTime();
  // dirty chunks a batch at a time: meshed together over the pool, then
  // uploaded here. At most `budget` chunks, and no more batches once a
  // frame's share of time is spent (at least one, so streaming moves on).
  while (r.stats.meshed < budget) {
    if (r.stats.meshed > 0 and (glfw.getTime() - begun) * m.MS_PER_S > ms) break;
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
      .out = x.scratch[0..n], .detail = x.detail_scratch[0..n], .failed = failed[0..n],
    }, Meshing.run);
    for (failed[0..n]) |e| if (e) |err| return err;
    for (batch[0..n], x.scratch[0..n], x.detail_scratch[0..n]) |c, vs, ds| try upload(r, c, vs.items, ds.items);
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
  const x = &r.ext;
  const bytes = sliceAsBytes(verts);
  var buf = try Buffer.init(&r.ctx, @max(bytes.len, MIN_CHUNK_BYTES), .{.vertex_buffer = true});
  errdefer buf.deinit(&r.ctx);
  buf.write(0, bytes);
  const dbytes = sliceAsBytes(tiles);
  var detail = try Buffer.init(&r.ctx, @max(dbytes.len, MIN_CHUNK_BYTES), .{.vertex_buffer = true});
  errdefer detail.deinit(&r.ctx);
  detail.write(0, dbytes);
  const slot = if (c.gpu_slot) |s| s else x.free_slots.pop() orelse blk: {
    try x.slots.append(r.gpa, .{});
    break :blk @as(ck.MeshSlot, @enumFromInt(x.slots.items.len - 1));
  };
  const at = @intFromEnum(slot);
  if (c.gpu_slot != null) {
    try r.retire(x.slots.items[at].buf);
    try r.retire(x.slots.items[at].detail);
  }
  c.gpu_slot = slot;
  const half = m.f(ck.SIZE) / 2;
  x.slots.items[at] = .{
    .buf = buf, .count = @intCast(verts.len), .live = true,
    .detail = detail, .tiles = @intCast(tiles.len),
    .centre = .{m.f(c.originX()) + half, m.f(c.originY()) + half},
  };
  c.dirty = false;
  r.stats.meshed += 1;
}
