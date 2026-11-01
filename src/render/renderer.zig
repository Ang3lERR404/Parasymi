//! the garden's renderer: the engine's frame orchestration (engine
//! render/renderer.zig) given the garden's passes (under `passes/`), push
//! constants and scene, and the state it keeps beside them: every grown
//! mesh (plant species and part library, grown as a task of their own while the
//! loading screen shows) and each streamed chunk's ground. A new pass is
//! one new file plus one line in `passes`.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every growing and upload call may fail with
const Allocator=std.mem.Allocator;
/// views a slice of vertices as the bytes a buffer takes
const sliceAsBytes=std.mem.sliceAsBytes;
/// the arena the growing meshes' scratch lives in, freed in one go
const ArenaAllocator=std.heap.ArenaAllocator;
/// the I/O the meshes grow on, apart, while the loading screen shows
const Io=std.Io;
/// a value the frames and the growing task both read and write safely: progress and flags
const Atomic=std.atomic.Value;
/// the engine package
const engine=lib.engine;
/// the window library, for its clock
const glfw=engine.glfw;
/// all the maths: matrices, conversions
const m=engine.core.math;
/// spreads chunk meshing over the pool (`jobs.each`)
const jobs=engine.core.jobs;
/// a GPU buffer: meshes, skins, ground
const Buffer=engine.gfx.buffer.Buffer;
/// the Vulkan bindings
const vk=engine.vk;
/// the engine's frame orchestration, given the garden below
const er=engine.render.renderer;
/// the garden's vertex and instance layouts
const vertex=lib.vertex;
/// the garden's plant meshes, grown from their genomes
const meshgen=lib.meshgen;
/// the library of part meshes
const meshlib=lib.meshlib;
/// the species registry, one plant mesh set each
const species=lib.species;
/// the garden's streamed world of chunks
const World=lib.world.World;
/// one chunk: its tiles and its ground mesh's slot
const ck=lib.ck;
/// meshes a chunk's ground and its detail records
const terrainMesh=lib.terrainMesh;
/// the window's title
pub const name="Parasymi";
/// the engine's renderer made for the garden (this file is its `G`)
pub const Renderer=er.Renderer(@This());
/// one render pass, as the registry knows it
pub const Pass=Renderer.Pass;
/// what a pass declares: its target and hooks
pub const pass=er.pass;
/// how the edges are smoothed
pub const Antialias=er.Antialias;
/// a captured frame: its size and pixels
pub const Shot=er.Shot;
/// how the renderer can fail: as the graphics layer does
pub const Error=er.Error;
/// frames in flight at once
pub const frames=er.frames;
/// points of light a frame can hold (the rest of `Scene.lights` is dropped)
pub const maxLights=er.maxLights;
/// stages the GPU's time is told apart by: each pass, then glow and composite
pub const stageCount=Renderer.stageCount;
/// the stage the bloom's glow is timed as
pub const glow=Renderer.glow;
/// the stage the final composite is timed as
pub const compose=Renderer.compose;
/// the garden's render passes, recorded in declaration order inside their target
pub const passes=struct{
  // what casts the key light's shadows, drawn first into its shadow map
  /// plants cast into the key light's shadow map
  pub const plantsShadow=@import("passes/plants.zig").shadow;
  /// parts cast into the key light's shadow map
  pub const partsShadow=@import("passes/parts.zig").shadow;
  /// the ground seen from above into the overhead map, for the fog
  pub const terrainOverhead=@import("passes/terrain.zig").overhead;
  // the moisture in the air, stepped on in the engine's field before the world
  /// the moisture field carried a step on: drifting, spreading, drying
  pub const moistureField=@import("passes/moisture.zig").field;
  /// what everything breathing moisture breathed since, laid onto it
  pub const moistureSources=@import("passes/moisture.zig").sources;
  /// the sky dome behind everything
  pub const sky=@import("passes/sky.zig");
  /// the baked ground of every streamed chunk
  pub const terrain=@import("passes/terrain.zig");
  /// the grass, clods and stones the GPU grows on the ground near the camera
  pub const detail=@import("passes/detail.zig");
  /// the plants' solid fragments
  pub const plants=@import("passes/plants.zig");
  /// the parts' solid fragments: the wolf, nodes, motes, structures
  pub const parts=@import("passes/parts.zig");
  // see-through fragments of plants and parts, over every solid one
  /// the plants' see-through fragments, blended over the solids
  pub const plantsGlass=@import("passes/plants.zig").glass;
  /// the parts' see-through fragments, blended over the solids
  pub const partsGlass=@import("passes/parts.zig").glass;
  /// the air over everything, marched after the world into its volume
  pub const fog=@import("passes/fog.zig");
  /// the air round what glows, lit after the fog's march
  pub const partsAir=@import("passes/parts.zig").air;
  /// the HUD, over the finished picture
  pub const ui=er.ui;
};
/// every grown plant mesh: each species in each of its variants.
pub const plantMeshes=species.count*meshgen.maxVariants*meshgen.lods;
/// what every world pass is pushed each draw (at most 192 bytes, matching
/// common.glsl's `Push`)
pub const WorldPush=extern struct{
  /// the camera's view-projection matrix
  vp:m.M4,
  /// xyz the camera's eye, w the time (s)
  eyeTime:m.Vice(f32,4),
  /// rgb the fog and sky colour (linear), w the fog's density
  fog:m.Vice(f32,4),
  /// x the veil 0..1, y ley sight 0/1, zw the hovered tile (x, z)
  misc:m.Vice(f32,4),
  /// xyz the way toward the key light (sun or moon), w daylight 0..1
  sun:m.Vice(f32,4),
  /// the wolf's paws for contact shadows: world x, y, z; the first's w its
  /// facing yaw (both paws face alike), the second's w how far the
  /// unforming has shifted the sky (common.glsl `SHIFT`)
  feet:[2]m.Vice(f32,4),
  /// x,y: what the camera looks at (x, z); z,w: horizontal distance from it
  /// fog starts closing in and where the world is fully hidden
  view:m.Vice(f32,4),
  /// where the parts pass finds this frame's bones (a buffer address; 0 in
  /// every other pass)
  bones:m.Vice(u32,2)=.{0,0},
  /// where every pass finds this frame's lighting (a buffer address, set by
  /// the renderer)
  light:m.Vice(u32,2)=.{0,0},
};
/// the push every pass takes: the world's
pub const Push=WorldPush;
comptime{
  if(@sizeOf(WorldPush)>192)@compileError("WorldPush must stay within 192 bytes");
}
/// everything a frame draws, handed to the renderer
pub const Scene=struct{
  /// what each world pass is pushed
  push:WorldPush,
  /// the colour the frame clears to (linear)
  clear:m.Vice(f32,3),
  /// plant instances grouped by mesh variant (see meshgen.plantSlot).
  instances:[plantMeshes][]const vertex.PlantInstance,
  /// rigid part instances grouped by mesh (player, nodes, motes, ...).
  parts:[meshlib.slots][]const vertex.PartInstance,
  /// skinned parts' bones (see `vertex.Skin`): each matrix carries a vertex
  /// from where it was built to where it is this frame
  bones:[]const m.M4,
  /// points of light, most telling first (the renderer takes the first
  /// `maxLights`)
  lights:[]const vertex.Light,
  /// what breathes moisture into the air this frame
  moisture:[]const vertex.Moisture=&.{},
  /// how far the world moved since the last frame (s; 0 while frozen): the
  /// air's moisture is stepped on by it
  step:f32=0,
  /// where (world x, z) the air's moisture is read back from (the engine's
  /// `probed`): the hovered tile's middle, if any
  probe:?m.Vice(f32,2)=null,
  /// the HUD's quads, drawn last
  ui:[]const vertex.Ui,
  /// UI clock (keeps running while the world is paused)
  uiTime:f32,
};
/// what a frame counted, for the stats overlay
pub const Stats=struct{
  /// draw calls recorded
  draws:u32=0,
  /// chunks of ground drawn (past culling)
  chunks:u32=0,
  /// plant instances drawn
  instances:u32=0,
  /// part instances drawn
  parts:u32=0,
  /// chunks meshed this frame
  meshed:u32=0,
  /// points of light taken
  lights:u32=0,
  /// the GPU's time for a whole frame (ms, eased; 0 where it keeps no time stamps)
  gpuMs:f32=0,
};
/// a frame's counts start from how many chunks were meshed before it
pub fn carry(prev:Stats)Stats{return.{.meshed=prev.meshed};}
/// the mesh a caster drawn from `slot` (a plant's or a part's) casts with:
/// the same mesh at its coarsest level of detail (a slot table lays each
/// mesh's levels side by side). A shadow needs no fine detail, and every
/// caster is drawn into every cascade.
pub fn caster(slot:usize)usize{return slot-slot%meshgen.lods+meshgen.lods-1;}
/// a sphere around a chunk (from its centre, `chunkMidY` up) holding all
/// of it, its terraces and what grows on its tiles, for culling it to the
/// view: half its diagonal (rounded up) and a margin
pub const chunkMidY:f32=1.5;
/// how far beyond the chunk's middle its culling sphere reaches
pub const chunkRadius:f32=m.f(ck.sizeTiles)*0.71+2;
/// a tool's meshes are made with room for one this-th more (`setParts`)
const toolRoom=2;
/// milliseconds a frame may spend meshing streamed chunks
pub const meshMs:f64=3;
/// streamed chunks meshed together over the pool, each into its own scratch
const meshBatch=8;
/// smallest buffer made for a chunk (an empty chunk still gets one)
const minChunkBytes=64;
/// one streamed chunk's ground on the GPU: its mesh, its detail records and where it is
pub const Slot=struct{
  /// the chunk's ground mesh
  buf:Buffer=.{},
  /// how many vertices its ground mesh holds
  count:u32=0,
  /// its detail records (one per tile with grass, clods or stones), which
  /// the detail pass grows on the GPU near the camera
  detail:Buffer=.{},
  /// how many detail records it holds
  tiles:u32=0,
  /// the chunk's centre (x, z)
  centre:m.Vice(f32,2)=.{0,0},
  /// whether this slot holds a chunk now (false once evicted)
  live:bool=false,
  /// whether its ground is drawn into the overhead map as it is now
  overhead:bool=false,
};
/// the meshes built when one thing stands alone (`--plant`, `--structure`):
/// one species' (or none) and these library meshes
pub const Only=struct{
  /// the one species built, or none
  species:?species.Id=null,
  /// the library meshes built
  parts:[]const meshlib.Id,
};
/// what the garden keeps on the renderer (`r.ext`)
pub const Ext=struct{
  /// with `only`, those meshes alone are built (`--plant`, `--structure`)
  only:?Only=null,
  /// the I/O the meshes grow on, beside the loading screen (null: grown
  /// here, before the first frame)
  io:?Io=null,
  /// terrain chunk meshes (see syncWorld)
  slots:std.ArrayList(Slot)=.empty,
  /// slots freed by evicted chunks, ready for the next one
  freeSlots:std.ArrayList(ck.MeshSlot)=.empty,
  /// the slot the overhead map's refresh goes on from (passes/terrain.zig)
  overheadTurn:usize=0,
  /// every built-once mesh (plant species + part library) in one buffer.
  meshes:Buffer=.{},
  /// each vertex of `meshes`' skin weights (zero where a mesh is not skinned)
  skins:Buffer=.{},
  /// beside `meshes`: where each vertex grows out of (`vertex.Grow`)
  grows:Buffer=.{},
  /// (first vertex, count) per plant slot; slots a species does not use are empty
  plantRanges:[plantMeshes]m.Vice(u32,2)=@splat(.{0,0}),
  /// per plant slot, the byte offset from its mesh to the next growth key's
  /// (the plant shader blends toward it); 0 where a species has no keys
  plantMorph:[plantMeshes]u64=@splat(0),
  /// (first vertex, count) per part slot
  partRanges:[meshlib.slots]m.Vice(u32,2)=@splat(.{0,0}),
  /// per part slot, the byte offset from its mesh to its next key's (the
  /// part shader blends toward it); 0 where it has none
  partMorph:[meshlib.slots]u64=@splat(0),
  /// per part slot: whether any of its vertices can be see-through (sap,
  /// resin, shadow, beam, halo); the glass pass draws only those
  partGlassy:[meshlib.slots]bool=@splat(false),
  /// one chunk's ground and detail per place in a meshing batch
  scratch:[meshBatch]std.ArrayList(vertex.Terrain)=@splat(.empty),
  /// the same per place in a batch, for the detail records
  detailScratch:[meshBatch]std.ArrayList(vertex.DetailTile)=@splat(.empty),
  /// the meshes while they are still growing (see `meshesReady`)
  growing:?*Growing=null,
  /// how many vertices of `meshes` a tool last put in (`setParts`; 0: none)
  toolVerts:usize=0,
};
/// every built-once mesh (plant species + part library), grown as a task of their own
/// of its own while the loading screen shows, one mesh at one level of
/// detail at a time (`done` of `units`); `meshesReady` takes them in once
/// it is through.
const Growing=struct{
  /// the builder's vertices are scratch: one arena, freed in one go once uploaded
  arena:ArenaAllocator,
  /// the builder the growing task pours every mesh into
  b:meshgen.Builder=undefined,
  /// the growing running apart on the I/O, and that I/O, or null when growing ran here
  apart:?struct{io:Io,future:Io.Future(void)}=null,
  /// how many units are grown so far
  done:Atomic(u32)=.init(0),
  /// set once the growing is through
  finished:Atomic(bool)=.init(false),
  /// set when the renderer goes before the meshes are through: stop early
  stop:Atomic(bool)=.init(false),
  /// whether growing ran out of memory
  failed:bool=false,
  /// (first vertex, count) per plant slot, as grown
  plantRanges:[plantMeshes]m.Vice(u32,2)=@splat(.{0,0}),
  /// per plant slot, the byte offset to the next growth key's mesh
  plantMorph:[plantMeshes]u64=@splat(0),
  /// (first vertex, count) per part slot, as grown
  partRanges:[meshlib.slots]m.Vice(u32,2)=@splat(.{0,0}),
  /// per part slot, the byte offset to its next key's mesh
  partMorph:[meshlib.slots]u64=@splat(0),
  /// per part slot: whether any of it can be see-through
  partGlassy:[meshlib.slots]bool=@splat(false),
  /// `--plant`/`--structure`: those meshes alone; every other range stays
  /// empty, so draws of it draw nothing
  only:?Only=null,
  /// each species' variants at one level of detail, then each library mesh
  /// at one level of detail
  fn units(g:*const Growing)u32{
    // how many meshes: the one species and the parts shown, or all of them
    const n=if(g.only)|o|@as(usize,if(o.species!=null)1 else 0)+o.parts.len else species.ids.len+meshlib.count;
    return@intCast(n*meshgen.lods);
  }
  /// the growing task.s body: grows everything, then marks it finished (or failed)
  fn run(g:*Growing)void{
    g.failed=std.meta.isError(g.all());
    g.finished.store(true,.release);
  }
  /// grows every species' variants, then every library mesh, at each level
  /// of detail, in order; returns early when asked to stop
  fn all(g:*Growing)Allocator.Error!void{
    // the builder everything pours into
    const b=&g.b;
    for(species.ids)|id|for(0..meshgen.lods)|l|{
      if(g.stop.load(.monotonic))return;
      if(g.only)|o|if(o.species!=id)continue;
      // this level of detail
      const lod:u32=@intCast(l);
      b.lod=lod;
      // how many variants this species has
      const n=meshgen.variants(id);
      for(0..n)|v|{
        // where this variant's vertices begin
        const first:u32=@intCast(b.v.items.len);
        try meshgen.plant(b,id,@intCast(v));
        g.plantRanges[meshgen.plantSlot(id,@intCast(v),lod)]=.{first,@as(u32,@intCast(b.v.items.len))-first};
      }
      // growth keys blend vertex for vertex into the next key
      if(meshgen.growthKey(id,0)!=null)for(0..n-1)|v|{
        // this key's range and the next key's
        const a=g.plantRanges[meshgen.plantSlot(id,@intCast(v),lod)];
        const z=g.plantRanges[meshgen.plantSlot(id,@intCast(v+1),lod)];
        if(a[1]!=z[1])@panic("growth keys differ in vertex count");
        g.plantMorph[meshgen.plantSlot(id,@intCast(v),lod)]=@as(u64,z[0]-a[0])*@sizeOf(vertex.Mesh);
      };
      _=g.done.fetchAdd(1,.monotonic);
    };
    // the library meshes to build: those shown alone, or all of them
    const shown:[]const meshlib.Id=if(g.only)|o|o.parts else meshlib.ids;
    for(0..meshgen.lods)|l|for(shown)|id|{
      if(g.stop.load(.monotonic))return;
      try meshlib.buildOne(b,id,@intCast(l),&g.partRanges);
      _=g.done.fetchAdd(1,.monotonic);
    };
    b.lod=0;
    // keys blend vertex for vertex into the next key, built after them
    for(shown)|id|if(meshlib.next(id))|nx|for(0..meshgen.lods)|l|{
      // this key's range and the next key's
      const a=g.partRanges[meshlib.slot(id,@intCast(l))];
      const z=g.partRanges[meshlib.slot(nx,@intCast(l))];
      if(z[1]==0)continue;
      if(a[1]!=z[1])@panic("part keys differ in vertex count");
      if(z[0]<a[0])@panic("a part's next key is built before it");
      g.partMorph[meshlib.slot(id,@intCast(l))]=@as(u64,z[0]-a[0])*@sizeOf(vertex.Mesh);
    };
    glassy(b.v.items,&g.partRanges,&g.partGlassy);
    _=try b.skinOf(b.v.items.len);
    _=try b.growOf(b.v.items.len);
  }
  /// wait for the growing task (asked to stop early) and free what it built
  fn end(g:*Growing,gpa:Allocator)void{
    g.stop.store(true,.monotonic);
    if(g.apart)|*a|a.future.await(a.io);
    g.arena.deinit();
    gpa.destroy(g);
  }
};
/// start growing every species' mesh and every library part as a task
/// of their own on the I/O (here, if none can be had)
pub fn start(r:*Renderer)Error!void{
  // the growing state, made on the heap so the growing task can hold it
  const g=try r.gpa.create(Growing);
  g.*=.{.arena=ArenaAllocator.init(r.gpa),.only=r.ext.only};
  g.b=.{.gpa=g.arena.allocator()};
  r.ext.growing=g;
  // no I/O to grow on: grown here, before the first frame
  const io=r.ext.io orelse return g.run();
  // a task of its own beside the frames (the I/O's, never a thread of ours)
  const future=io.concurrent(Growing.run,.{g})catch|e|{
    std.log.warn("meshes grown without a task of their own: {t}",.{e});
    return g.run();
  };
  g.apart=.{.io=io,.future=future};
}
/// free what the garden keeps on the renderer (null handles are skipped)
pub fn release(r:*Renderer)void{
  // the graphics context, and what the garden keeps
  const c=&r.ctx;
  const x=&r.ext;
  if(x.growing)|g|g.end(r.gpa);
  x.growing=null;
  for(x.slots.items)|*s|{
    s.buf.deinit(c);
    s.detail.deinit(c);
  }
  x.slots.deinit(r.gpa);
  x.freeSlots.deinit(r.gpa);
  for(&x.scratch,&x.detailScratch)|*v,*d|{
    v.deinit(r.gpa);
    d.deinit(r.gpa);
  }
  x.meshes.deinit(c);
  x.skins.deinit(c);
  x.grows.deinit(c);
}
/// how many of the meshes' units are grown, of how many
pub fn meshProgress(r:*const Renderer)m.Vice(u32,2){
  // the growing state; none left means all is grown
  const g=r.ext.growing orelse return.{1,1};
  return.{g.done.load(.monotonic),g.units()};
}
/// whether every mesh is grown and in one buffer: once they are through,
/// uploads them (the first call after that) and frees the scratch. The
/// world can be drawn only after this says so.
pub fn meshesReady(r:*Renderer)Error!bool{
  // what the garden keeps, and the growing state (none: already in)
  const x=&r.ext;
  const g=x.growing orelse return true;
  if(!g.finished.load(.acquire))return false;
  if(g.apart)|*a|a.future.await(a.io);
  g.apart=null;
  defer{
    g.end(r.gpa);
    x.growing=null;
  }
  if(g.failed)return error.OutOfMemory;
  // the builder holding every grown vertex
  const b=&g.b;
  x.plantRanges=g.plantRanges;
  x.plantMorph=g.plantMorph;
  x.partRanges=g.partRanges;
  x.partMorph=g.partMorph;
  x.partGlassy=g.partGlassy;
  // read by every plant and part draw, every frame: in device memory
  x.meshes=try Buffer.initWith(&r.ctx,.{.vertex_buffer=true},sliceAsBytes(b.v.items));
  x.skins=try Buffer.initWith(&r.ctx,.{.vertex_buffer=true},sliceAsBytes(b.skin.items));
  x.grows=try Buffer.initWith(&r.ctx,.{.vertex_buffer=true},sliceAsBytes(b.grow.items));
  return true;
}
/// per part slot: whether any of its run of `verts` can be see-through
fn glassy(verts:[]const vertex.Mesh,ranges:*const[meshlib.slots]m.Vice(u32,2),out:*[meshlib.slots]bool)void{
  for(out,ranges)|*gl,rg|{
    gl.*=false;
    for(verts[rg[0]..][0..rg[1]])|v|if(vertex.seeThrough(@enumFromInt(v.part))){
      gl.*=true;
      break;
    };
  }
}
/// put the meshes `b` holds in place of every built-once mesh, each part
/// slot drawing its run of `ranges` and plants nothing: a tool remaking a
/// mesh as it is edited (tools/meshedit.zig). Its first `kept` vertices are
/// as it last put them, so only those after are copied in while the
/// buffers have room; else they are made anew with room to spare (the old
/// go once no frame in flight reads them). With nothing in `b` they stay,
/// drawn by no slot.
pub fn setParts(r:*Renderer,b:*meshgen.Builder,ranges:[meshlib.slots]m.Vice(u32,2),kept:usize)Error!void{
  // what the garden keeps
  const x=&r.ext;
  x.plantRanges=@splat(.{0,0});
  x.plantMorph=@splat(0);
  x.partMorph=@splat(0);
  if(b.v.items.len==0){
    x.partRanges=@splat(.{0,0});
    x.partGlassy=@splat(false);
    return;
  }
  // how many vertices the tool put in
  const n=b.v.items.len;
  _=try b.skinOf(n);
  _=try b.growOf(n);
  x.partRanges=ranges;
  glassy(b.v.items,&x.partRanges,&x.partGlassy);
  // the first vertex not already in the buffers as the tool last put it
  const from=@min(kept,x.toolVerts);
  x.toolVerts=n;
  // the buffers' use: vertices
  const usage:vk.BufferUsageFlags=.{.vertex_buffer=true};
  if(x.meshes.size>=n*@sizeOf(vertex.Mesh) and from>0){
    try x.meshes.overwrite(&r.ctx,from*@sizeOf(vertex.Mesh),sliceAsBytes(b.v.items[from..]));
    try x.skins.overwrite(&r.ctx,from*@sizeOf(vertex.Skin),sliceAsBytes(b.skin.items[from..]));
    try x.grows.overwrite(&r.ctx,from*@sizeOf(vertex.Grow),sliceAsBytes(b.grow.items[from..]));
    return;
  }
  try r.retire(x.meshes);
  try r.retire(x.skins);
  try r.retire(x.grows);
  x.meshes=.{};
  x.skins=.{};
  x.grows=.{};
  // how many vertices the new buffers have room for
  const room=n+n/toolRoom;
  x.meshes=try Buffer.initRoom(&r.ctx,usage,room*@sizeOf(vertex.Mesh),sliceAsBytes(b.v.items));
  x.skins=try Buffer.initRoom(&r.ctx,usage,room*@sizeOf(vertex.Skin),sliceAsBytes(b.skin.items));
  x.grows=try Buffer.initRoom(&r.ctx,usage,room*@sizeOf(vertex.Grow),sliceAsBytes(b.grow.items));
}
/// forget every chunk mesh: the world was replaced (e.g. a save was loaded).
pub fn dropWorld(r:*Renderer)Allocator.Error!void{
  for(r.ext.slots.items)|s|{
    try r.retire(s.buf);
    try r.retire(s.detail);
  }
  r.ext.slots.clearRetainingCapacity();
  r.ext.freeSlots.clearRetainingCapacity();
}
/// upload meshes for new/dirty chunks (at most `budget`, and no more once
/// `ms` milliseconds are spent) and drop evicted ones.
pub fn syncWorld(r:*Renderer,w:*World,budget:u32,ms:f64)Error!void{
  // what the garden keeps
  const x=&r.ext;
  for(w.evicted.items)|si|{
    // this evicted chunk's slot, as an index
    const i=@intFromEnum(si);
    try r.retire(x.slots.items[i].buf);
    try r.retire(x.slots.items[i].detail);
    x.slots.items[i]=.{};
    try x.freeSlots.append(r.gpa,si);
  }
  w.evicted.clearRetainingCapacity();
  r.stats.meshed=0;
  // when meshing began this frame (s)
  const begun=glfw.getTime();
  // dirty chunks a batch at a time: meshed together over the pool, then
  // uploaded here. At most `budget` chunks, and no more batches once a
  // frame's share of time is spent (at least one, so streaming moves on).
  while(r.stats.meshed<budget){
    if(r.stats.meshed>0 and (glfw.getTime()-begun)*m.msPerS>ms)break;
    // this batch's dirty chunks, and how many
    var batch:[meshBatch]*ck.Chunk=undefined;
    var n:usize=0;
    // walks every loaded chunk
    var it=w.map.valueIterator();
    while(it.next())|cp|{
      if(n==batch.len or r.stats.meshed+n>=budget)break;
      if(cp.*.dirty){
        batch[n]=cp.*;
        n+=1;
      }
    }
    if(n==0)break;
    // each place's error, if its meshing failed
    var failed:[meshBatch]?Allocator.Error=@splat(null);
    jobs.each(w.io,n,1,Meshing,.{
      .gpa=r.gpa,.seed=w.seed,.cs=batch[0..n],
      .out=x.scratch[0..n],.detail=x.detailScratch[0..n],.failed=failed[0..n],
    },Meshing.run);
    for(failed[0..n])|e|if(e)|err|return err;
    for(batch[0..n],x.scratch[0..n],x.detailScratch[0..n])|c,vs,ds|try upload(r,c,vs.items,ds.items);
  }
}
/// one range of a batch of chunks' ground meshed, each into its own scratch
const Meshing=struct{
  /// where each chunk's scratch lists are allocated
  gpa:Allocator,
  /// the world's seed, which the ground's look is drawn from
  seed:u64,
  /// the chunks of the batch
  cs:[]const*ck.Chunk,
  /// each chunk's ground vertices, built into
  out:[]std.ArrayList(vertex.Terrain),
  /// each chunk's detail records, built into
  detail:[]std.ArrayList(vertex.DetailTile),
  /// each chunk's error, if its meshing failed
  failed:[]?Allocator.Error,
  /// meshes chunks `lo..hi` of the batch, each into its own scratch
  fn run(j:Meshing,lo:usize,hi:usize)void{
    for(lo..hi)|k|terrainMesh.build(j.gpa,j.seed,j.cs[k],&j.out[k],&j.detail[k])catch|e|{
      j.failed[k]=e;
    };
  }
};
/// a meshed chunk's ground and detail into buffers of its own slot (the
/// old ones retired), and it is clean
fn upload(r:*Renderer,c:*ck.Chunk,verts:[]const vertex.Terrain,tiles:[]const vertex.DetailTile)Error!void{
  // what the garden keeps
  const x=&r.ext;
  // the ground's vertices as bytes, and its buffer
  const bytes=sliceAsBytes(verts);
  var buf=try Buffer.init(&r.ctx,@max(bytes.len,minChunkBytes),.{.vertex_buffer=true});
  errdefer buf.deinit(&r.ctx);
  buf.write(0,bytes);
  // the detail records as bytes, and their buffer
  const dbytes=sliceAsBytes(tiles);
  var detail=try Buffer.init(&r.ctx,@max(dbytes.len,minChunkBytes),.{.vertex_buffer=true});
  errdefer detail.deinit(&r.ctx);
  detail.write(0,dbytes);
  // the chunk's slot: its own, a freed one, or a new one at the end
  const slot=if(c.gpuSlot)|s|s else x.freeSlots.pop() orelse blk:{
    try x.slots.append(r.gpa,.{});
    break:blk@as(ck.MeshSlot,@enumFromInt(x.slots.items.len-1));
  };
  // that slot as an index
  const at=@intFromEnum(slot);
  if(c.gpuSlot!=null){
    try r.retire(x.slots.items[at].buf);
    try r.retire(x.slots.items[at].detail);
  }
  c.gpuSlot=slot;
  // half a chunk's width, from its corner to its centre
  const half=m.f(ck.sizeTiles)/2;
  x.slots.items[at]=.{
    .buf=buf,.count=@intCast(verts.len),.live=true,
    .detail=detail,.tiles=@intCast(tiles.len),
    .centre=.{m.f(c.originX())+half,m.f(c.originY())+half},
  };
  c.dirty=false;
  r.stats.meshed+=1;
}
