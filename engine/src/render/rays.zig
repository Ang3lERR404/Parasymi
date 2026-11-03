//! shadows traced as rays: what casts them, as it stands this very frame.
//!
//! Each frame the casters' own vertex shaders run once more with nothing
//! rasterized (a `capture` pass, built with CAPTURE), writing every vertex
//! where they placed it (swayed, grown, gathered, skinned) into `caught`,
//! instance by instance. Those vertices, with the meshes' own indices, are
//! built into acceleration structures: bottom levels the game names (a
//! chunk's plants, the parts), each of what blocks every light's rays or
//! of what blocks only the points of light's (a game's choice, per
//! vertex), and over them the top level the shaders trace through
//! (light.glsl under RAY: `traced`). A triangle a caster leaves out (light
//! itself) has its vertices written as NaN, which a build leaves inactive.
//! A level holding the same meshes as when it was last built is refitted
//! round where they moved, cheap, and built anew only when what it holds
//! changes (or now and then, as a refitted tree loosens); one left
//! uncaught a while is let go. Everything here exists only where the GPU
//! can trace rays (`Ctx.rayTracing`).
/// the standard library
const std=@import("std");
/// the allocator the frame's lists are made with
const Allocator=std.mem.Allocator;
/// the instance records seen as their bytes
const sliceAsBytes=std.mem.sliceAsBytes;
/// the hash a level's key is folded with
const Wyhash=std.hash.Wyhash;
/// one value seen as its bytes, for a level's key
const asBytes=std.mem.asBytes;
/// each level's place in the list, by the name the game gave it
const LevelMap=std.AutoHashMapUnmanaged(u64,u32);
/// how many frames a level is refitted before it is built in full again (a
/// refitted tree slowly loosens as what it holds sways and grows); levels
/// first built together start apart in this count, so they are not all
/// built anew in the same frame
const refits:u32=30;
/// how many frames a level is kept uncaught before it is let go: past the
/// frames in flight, so none of them still traces it, and no longer (kept
/// long, a camera turning round a big garden kept every patch's level and
/// outgrew the device)
const keep:u64=frames+2;
/// how much scratch one batch of builds takes together (bytes; one build
/// alone may take more): a frame's builds go batch after batch, reusing
/// it. All at once, a garden's every patch wanted hundreds of megabytes.
const scratchBatch:u64=64<<20;
/// the Vulkan bindings: acceleration structures, barriers, rendering scopes
const vk=@import("vulkan");
/// all the maths: alignment, conversions
const m=@import("../core/math.zig");
/// the Vulkan context and its error fold
const ctx=@import("../gfx/ctx.zig");
/// the device context everything is made on
const Ctx=ctx.Ctx;
/// a GPU buffer: what is caught, the structures, their scratch
const Buffer=@import("../gfx/buffer.zig").Buffer;
/// which rays a caster blocks: those of every light (and so of the key
/// light), or only the points of light's
pub const Caster=enum{
  /// every light's rays meet it
  both,
  /// only the points of light's rays meet it
  points
};
/// how many sets of casters there are, each its caught vertices
const sets=2;
/// the rays a structure is met by, one bit each (light.glsl `RAYS_KEY`,
/// `RAYS_POINT`): the key light's, the points of light's
const masks=[sets]u8{1|2,2};
/// bytes a caught vertex takes (a vec4: where it is, and one more)
pub const stride:u64=16;
/// bytes before a capture table's slots (light.glsl `Capture`): the two
/// sets' addresses
pub const tableHead=16;
/// frames in flight, each with its own top level's instances (the
/// renderer's `frames`)
pub const frames=2;
/// a buffer grown (caught sets, levels, scratch) takes this share more than
/// was asked (1/4), so it grows rarely without doubling: doubled, a big
/// garden's caught vertices, levels and scratch outgrew the device
const growShare:u64=4;
/// `n` with a quarter's room to spare
fn grow(n:u64)u64{return n+n/growShare;}
/// the least vertices a caught set holds
const leastRoom:u64=1<<18;
/// the most levels a frame's top level holds: made once, as the shaders'
/// descriptor binds it (a garden's patches in view, two sets each, come to
/// a few hundred)
pub const maxLevels:u32=1<<14;
/// a built acceleration structure: its buffer, handle and size
const Accel=struct{
  /// the buffer it lives in
  buf:Buffer=.{},
  /// its handle
  handle:vk.AccelerationStructureKHR=.null_handle,
  /// make one of `kind` `size` bytes long (any earlier one freed first)
  fn make(a:*Accel,c:*const Ctx,kind:vk.AccelerationStructureTypeKHR,size:u64)ctx.Error!void{
    a.deinit(c);
    a.buf=try Buffer.initRoom(c,.{.acceleration_structure_storage_khr=true,.shader_device_address=true},size,&.{});
    a.handle=c.device.createAccelerationStructureKHR(&.{.buffer=a.buf.buf,.offset=0,.size=size,.type=kind},null)catch|e|return ctx.fold(e);
  }
  /// free it and leave it empty
  fn deinit(a:*Accel,c:*const Ctx)void{
    if(a.handle!=.null_handle)c.device.destroyAccelerationStructureKHR(a.handle,null);
    a.buf.deinit(c);
    a.*=.{};
  }
  /// where the top level finds it
  fn address(a:*const Accel,c:*const Ctx)u64{
    return c.device.getAccelerationStructureDeviceAddressKHR(&.{.acceleration_structure=a.handle});
  }
};
/// a level's structure it outgrew, kept till no frame in flight traces it
const Retired=struct{
  /// the structure
  accel:Accel,
  /// the frame it was outgrown
  frame:u64,
};
/// one bottom level: what the game caught into it under one name, kept
/// from frame to frame so it can be refitted
const Level=struct{
  /// the name the game gave it (a chunk's plants of one set, the parts)
  id:u64,
  /// the structure itself
  accel:Accel=.{},
  /// which set it holds
  kind:Caster=.both,
  /// this frame's triangles: its geometries, their ranges and primitive counts
  geoms:std.ArrayList(vk.AccelerationStructureGeometryKHR)=.empty,
  /// (each geometry's range)
  ranges:std.ArrayList(vk.AccelerationStructureBuildRangeInfoKHR)=.empty,
  /// (each geometry's triangles)
  prims:std.ArrayList(u32)=.empty,
  /// how many triangles it built this frame
  tris:u64=0,
  /// what it caught this frame, as a key: each geometry's indices, vertex
  /// count and triangles, in order. The same as its last full build's
  /// means the same meshes in the same order, so it is only refitted
  /// round where they moved (wherever among the caught vertices they lie).
  key:u64=0,
  /// its key when it was last built in full (null: never built)
  builtKey:?u64=null,
  /// how many frames it has been refitted since it was built in full
  since:u32=0,
  /// the last frame anything was caught into it
  last:u64=0,
  /// free what it holds
  fn deinit(l:*Level,c:*const Ctx,gpa:Allocator)void{
    l.accel.deinit(c);
    l.geoms.deinit(gpa);
    l.ranges.deinit(gpa);
    l.prims.deinit(gpa);
  }
};
/// what the shaders trace through, and how each frame's is caught and built
pub const Rays=struct{
  /// the allocator the frame's lists grow in
  gpa:Allocator,
  /// each set's caught vertices, written by the capture passes
  caught:[sets]Buffer=@splat(.{}),
  /// how many vertices each caught set has room for
  room:u64=0,
  /// how many vertices this frame's capture asked for
  used:u64=0,
  /// every bottom level kept, caught this frame or not long ago
  low:std.ArrayList(Level)=.empty,
  /// each level's place in `low`, by its name
  byId:LevelMap=.empty,
  /// the frames begun so far
  frame:u64=0,
  /// the top level, holding each bottom level caught this frame
  top:Accel=.{},
  /// where both levels are built (device-local)
  scratch:Buffer=.{},
  /// the top level's own scratch, bytes
  topScratch:u64=0,
  /// each frame in flight's instance records (host-visible)
  inst:[frames]Buffer=@splat(.{}),
  /// this frame's builds, their ranges, scratch sizes and the top level's
  /// records (kept to grow in)
  builds:std.ArrayList(vk.AccelerationStructureBuildGeometryInfoKHR)=.empty,
  /// (each build's ranges)
  spans:std.ArrayList([*]const vk.AccelerationStructureBuildRangeInfoKHR)=.empty,
  /// (each build's level, by its place in `low`)
  built:std.ArrayList(u32)=.empty,
  /// (the top level's records)
  recs:std.ArrayList(vk.AccelerationStructureInstanceKHR)=.empty,
  /// how many levels were refitted, and built in full, since the start
  /// (logged as the renderer closes)
  refitted:u64=0,
  /// (built in full)
  rebuilt:u64=0,
  /// levels' structures outgrown, each with the frame it was, freed `keep`
  /// frames on
  retired:std.ArrayList(Retired)=.empty,
  /// the top level and its instance records; anything half made is freed
  pub fn init(c:*const Ctx,gpa:Allocator)ctx.Error!Rays{
    // the rays being made
    var r:Rays=.{.gpa=gpa};
    errdefer r.deinit(c);
    for(&r.inst)|*b|b.*=try Buffer.init(c,maxLevels*@sizeOf(vk.AccelerationStructureInstanceKHR),.{.acceleration_structure_build_input_read_only_khr=true,.shader_device_address=true});
    // the top level's size, for as many levels as it may hold
    const geom=topGeometry(0);
    const info=topInfo(&geom);
    var size:vk.AccelerationStructureBuildSizesInfoKHR=.{.acceleration_structure_size=0,.update_scratch_size=0,.build_scratch_size=0};
    const most=[_]u32{maxLevels};
    c.device.getAccelerationStructureBuildSizesKHR(.device_khr,&info,&most,&size);
    try r.top.make(c,.top_level_khr,size.acceleration_structure_size);
    r.topScratch=size.build_scratch_size;
    return r;
  }
  /// free everything held
  pub fn deinit(r:*Rays,c:*const Ctx)void{
    for(&r.caught)|*b|b.deinit(c);
    for(r.low.items)|*l|l.deinit(c,r.gpa);
    r.low.deinit(r.gpa);
    r.byId.deinit(r.gpa);
    r.top.deinit(c);
    r.scratch.deinit(c);
    for(&r.inst)|*b|b.deinit(c);
    r.builds.deinit(r.gpa);
    r.spans.deinit(r.gpa);
    r.built.deinit(r.gpa);
    r.recs.deinit(r.gpa);
    for(r.retired.items)|*o|o.accel.deinit(c);
    r.retired.deinit(r.gpa);
  }
  /// how many triangles of set `s` were built this frame, every level's
  pub fn trisOf(r:*const Rays,s:Caster)u64{
    // the sum so far
    var n:u64=0;
    for(r.low.items)|l|if(l.kind==s and l.last==r.frame){n+=l.tris;};
    return n;
  }
  /// how many levels were caught this frame
  pub fn levelsNow(r:*const Rays)usize{return r.built.items.len;}
  /// what the shaders' descriptor binds (light.glsl `casters`)
  pub fn handle(r:*const Rays)vk.AccelerationStructureKHR{return r.top.handle;}
  /// a new frame: nothing caught yet
  pub fn begin(r:*Rays)void{
    r.used=0;
    r.frame+=1;
  }
  /// room for `n` vertices this frame: the slot the first goes in (a
  /// capture pass's `prepare`; the room is made by `fit`)
  pub fn reserve(r:*Rays,n:u64)u64{
    // the slot handed out
    const at=r.used;
    r.used+=n;
    return at;
  }
  /// make room for every vertex asked for this frame, once every pass is
  /// prepared and before any is captured (waits for the GPU when the room
  /// must grow: rarely, it grows a quarter past what was asked)
  pub fn fit(r:*Rays,c:*const Ctx)ctx.Error!void{
    if(r.used<=r.room and r.room>0)return;
    c.device.deviceWaitIdle()catch|e|return ctx.fold(e);
    r.room=@max(grow(r.used),leastRoom);
    for(&r.caught)|*b|{
      b.deinit(c);
      b.*=try Buffer.initRoom(c,.{.storage_buffer=true,.shader_device_address=true,.acceleration_structure_build_input_read_only_khr=true},r.room*stride,&.{});
    }
  }
  /// where set `s`'s caught vertices lie on the device (the capture
  /// shader's table names it)
  pub fn caughtAt(r:*const Rays,c:*const Ctx,s:Caster)u64{return r.caught[@intFromEnum(s)].address(c);}
  /// the level named `id`, holding set `s`, ready for this frame's
  /// triangles: kept from an earlier frame, or made (empty, unbuilt)
  fn level(r:*Rays,id:u64,s:Caster)Allocator.Error!*Level{
    // its place, if kept
    const got=try r.byId.getOrPut(r.gpa,id);
    if(!got.found_existing){
      errdefer _=r.byId.remove(id);
      got.value_ptr.*=@intCast(r.low.items.len);
      try r.low.append(r.gpa,.{.id=id});
    }
    // the level, cleared the first time it is caught into this frame
    const l=&r.low.items[got.value_ptr.*];
    if(l.last!=r.frame){
      l.last=r.frame;
      l.key=0;
      l.geoms.clearRetainingCapacity();
      l.ranges.clearRetainingCapacity();
      l.prims.clearRetainingCapacity();
    }
    l.kind=s;
    return l;
  }
  /// one caught instance of set `s` into the level named `id`: its `verts`
  /// vertices from `slot` on, its `tris` triangles' indices at `index` (a
  /// device address, each counting from its first vertex)
  pub fn add(r:*Rays,c:*const Ctx,id:u64,s:Caster,slot:u64,verts:u32,index:u64,tris:u32)Allocator.Error!void{
    if(tris==0 or verts==0)return;
    const l=try r.level(id,s);
    try l.geoms.append(r.gpa,.{
      .geometry_type=.triangles_khr,
      .geometry=.{.triangles=.{
        .vertex_format=.r32g32b32_sfloat,
        .vertex_data=.{.device_address=r.caughtAt(c,s)+slot*stride},
        .vertex_stride=stride,
        .max_vertex=verts-1,
        .index_type=.uint32,
        .index_data=.{.device_address=index},
        .transform_data=.{.device_address=0},
      }},
      .flags=.{.opaque_khr=true},
    });
    try l.ranges.append(r.gpa,.{.primitive_count=tris,.primitive_offset=0,.first_vertex=0,.transform_offset=0});
    try l.prims.append(r.gpa,tris);
    // what this geometry is, folded into the level's key
    const what=[_]u64{index,verts,tris};
    l.key=Wyhash.hash(l.key,asBytes(&what));
  }
  /// let go of every level left uncaught `keep` frames, and every one
  /// outgrown as long ago (no frame in flight traces it any more)
  fn forget(r:*Rays,c:*const Ctx)void{
    // the outgrown one looked at
    var k:usize=0;
    while(k<r.retired.items.len){
      if(r.frame-r.retired.items[k].frame<keep){
        k+=1;
        continue;
      }
      r.retired.items[k].accel.deinit(c);
      _=r.retired.swapRemove(k);
    }
    // the level looked at
    var i:usize=0;
    while(i<r.low.items.len){
      const l=&r.low.items[i];
      if(r.frame-l.last<keep){
        i+=1;
        continue;
      }
      _=r.byId.remove(l.id);
      l.deinit(c,r.gpa);
      _=r.low.swapRemove(i);
      if(i<r.low.items.len)r.byId.putAssumeCapacity(r.low.items[i].id,@intCast(i));
    }
  }
  /// open the capture passes' scope: nothing drawn into, nothing
  /// rasterized. (What earlier frames read of what is caught and built is
  /// done first: a barrier waits on every command before it in the queue.)
  pub fn open(_:*const Rays,cmd:vk.CommandBufferProxy)void{
    memory(cmd,.{.fragment_shader=true,.acceleration_structure_build_khr=true},.{.acceleration_structure_read_khr=true,.shader_read=true},
      .{.vertex_shader=true,.acceleration_structure_build_khr=true},.{.shader_write=true,.acceleration_structure_write_khr=true});
    // a pixel's worth, never drawn into
    const area:vk.Rect2D=.{.offset=.{.x=0,.y=0},.extent=.{.width=1,.height=1}};
    cmd.beginRendering(&.{.render_area=area,.layer_count=1,.view_mask=0,.color_attachment_count=0,.p_color_attachments=null});
    cmd.setViewport(0,&.{.{.x=0,.y=0,.width=1,.height=1,.min_depth=0,.max_depth=1}});
    cmd.setScissor(0,&.{area});
  }
  /// close it
  pub fn close(_:*const Rays,cmd:vk.CommandBufferProxy)void{cmd.endRendering();}
  /// build what was caught into each level caught this frame (refitted
  /// where it holds what it held), and the top level over them, for the
  /// world's shaders to trace (frame in flight `fi`'s instance records);
  /// grows a level, the top level or the scratch when it must (waiting
  /// for the GPU)
  pub fn build(r:*Rays,c:*const Ctx,cmd:vk.CommandBufferProxy,fi:usize)ctx.Error!void{
    r.forget(c);
    r.builds.clearRetainingCapacity();
    r.spans.clearRetainingCapacity();
    r.built.clearRetainingCapacity();
    r.recs.clearRetainingCapacity();
    for(r.low.items,0..)|*l,i|{
      if(l.last!=r.frame or l.geoms.items.len==0)continue;
      // (past the top level's room the rest cast nothing this frame)
      if(r.builds.items.len==maxLevels)break;
      // its key this frame: what was caught, and which caught buffer holds it
      l.key=Wyhash.hash(l.key,asBytes(&r.caught[@intFromEnum(l.kind)].buf));
      l.tris=0;
      for(l.prims.items)|p|l.tris+=p;
      var info:vk.AccelerationStructureBuildGeometryInfoKHR=.{.type=.bottom_level_khr,.flags=.{.prefer_fast_trace_khr=true,.allow_update_khr=true},.mode=.build_khr,.geometry_count=@intCast(l.geoms.items.len),.p_geometries=l.geoms.items.ptr,.scratch_data=.{.device_address=0}};
      var size:vk.AccelerationStructureBuildSizesInfoKHR=.{.acceleration_structure_size=0,.update_scratch_size=0,.build_scratch_size=0};
      c.device.getAccelerationStructureBuildSizesKHR(.device_khr,&info,l.prims.items.ptr,&size);
      // outgrown: made anew at its size, the old one let go once no frame
      // in flight traces it (a patch grows as its plants do: never a wait)
      if(size.acceleration_structure_size>l.accel.buf.size){
        if(l.accel.handle!=.null_handle)try r.retired.append(r.gpa,.{.accel=l.accel,.frame=r.frame});
        l.accel=.{};
        try l.accel.make(c,.bottom_level_khr,size.acceleration_structure_size);
        l.builtKey=null;
      }
      info.dst_acceleration_structure=l.accel.handle;
      // the same as its last full build: refitted round where things moved,
      // until it has been refitted long enough to want building anew
      if(l.builtKey==l.key and l.since<refits){
        info.mode=.update_khr;
        info.src_acceleration_structure=l.accel.handle;
        l.since+=1;
        r.refitted+=1;
      }else{
        // (first built: started somewhere in the count, by its name)
        l.since=if(l.builtKey==null)@intCast(l.id%refits)else 0;
        l.builtKey=l.key;
        r.rebuilt+=1;
      }
      // its scratch, for now, as a size: made an address once all are known
      info.scratch_data=.{.device_address=if(info.mode==.update_khr)size.update_scratch_size else size.build_scratch_size};
      try r.builds.append(r.gpa,info);
      try r.spans.append(r.gpa,l.ranges.items.ptr);
      try r.built.append(r.gpa,@intCast(i));
    }
    // the scratch the builds want: batch after batch, each within
    // `scratchBatch` together (one alone may be larger), reusing it; and
    // the top level's after them
    var need=r.topScratch;
    var run:u64=0;
    for(r.builds.items)|b|{
      // (its size, set aside above)
      const size=m.alignUp(b.scratch_data.device_address,c.scratchAlign);
      if(run>0 and run+size>scratchBatch)run=0;
      run+=size;
      need=@max(need,run);
    }
    need+=c.scratchAlign;
    const n:u32=@intCast(r.builds.items.len);
    if(r.scratch.size<need){
      c.device.deviceWaitIdle()catch|e|return ctx.fold(e);
      r.scratch.deinit(c);
      r.scratch=try Buffer.initRoom(c,.{.storage_buffer=true,.shader_device_address=true},grow(need),&.{});
    }
    // the scratch's first aligned address, and where each build's begins
    const base=m.alignUp(r.scratch.address(c),c.scratchAlign);
    var at=base;
    // the batch being gathered: its first build
    var from:usize=0;
    memory(cmd,.{.vertex_shader=true},.{.shader_write=true},.{.acceleration_structure_build_khr=true},.{.shader_read=true,.acceleration_structure_read_khr=true});
    for(r.builds.items,r.built.items,0..)|*b,i,k|{
      // (its size, set aside above)
      const size=m.alignUp(b.scratch_data.device_address,c.scratchAlign);
      if(at>base and at-base+size>scratchBatch){
        // the batch so far built, its scratch free again once it is done
        cmd.buildAccelerationStructuresKHR(r.builds.items[from..k],r.spans.items[from..k]);
        built(cmd);
        from=k;
        at=base;
      }
      b.scratch_data=.{.device_address=at};
      at+=size;
      // the level built, its record in the top level
      const l=&r.low.items[i];
      try r.recs.append(r.gpa,.{
        .transform=.{.matrix=.{.{1,0,0,0},.{0,1,0,0},.{0,0,1,0}}},
        .instance_custom_index_and_mask=.{.instance_custom_index=0,.mask=masks[@intFromEnum(l.kind)]},
        .instance_shader_binding_table_record_offset_and_flags=.{.instance_shader_binding_table_record_offset=0,.flags=@truncate(@as(u32,@bitCast(vk.GeometryInstanceFlagsKHR{.force_opaque_khr=true})))},
        .acceleration_structure_reference=l.accel.address(c),
      });
    }
    if(n>from)cmd.buildAccelerationStructuresKHR(r.builds.items[from..],r.spans.items[from..]);
    built(cmd);
    // the top level over them, its instances this frame's records
    r.inst[fi].write(0,sliceAsBytes(r.recs.items));
    const geom=topGeometry(r.inst[fi].address(c));
    var info=topInfo(&geom);
    info.dst_acceleration_structure=r.top.handle;
    info.scratch_data=.{.device_address=base};
    const range=[_]vk.AccelerationStructureBuildRangeInfoKHR{.{.primitive_count=n,.primitive_offset=0,.first_vertex=0,.transform_offset=0}};
    cmd.buildAccelerationStructuresKHR(&.{info},&.{&range});
    memory(cmd,.{.acceleration_structure_build_khr=true},.{.acceleration_structure_write_khr=true},.{.fragment_shader=true},.{.acceleration_structure_read_khr=true});
  }
};
/// the top level's one geometry: instance records at `at` (a device address)
fn topGeometry(at:u64)vk.AccelerationStructureGeometryKHR{
  return.{.geometry_type=.instances_khr,.geometry=.{.instances=.{.array_of_pointers=.false,.data=.{.device_address=at}}},.flags=.{.opaque_khr=true}};
}
/// the top level's build over `geom`, fast to build (it is rebuilt every frame)
fn topInfo(geom:*const vk.AccelerationStructureGeometryKHR)vk.AccelerationStructureBuildGeometryInfoKHR{
  return.{.type=.top_level_khr,.flags=.{.prefer_fast_build_khr=true},.mode=.build_khr,.geometry_count=1,.p_geometries=@ptrCast(geom),.scratch_data=.{.device_address=0}};
}
/// what one batch of builds wrote (its levels, its scratch) done before the
/// next build reads or writes either
fn built(cmd:vk.CommandBufferProxy)void{
  memory(cmd,.{.acceleration_structure_build_khr=true},.{.acceleration_structure_write_khr=true},.{.acceleration_structure_build_khr=true},.{.acceleration_structure_read_khr=true,.acceleration_structure_write_khr=true});
}
/// one barrier over all memory: what `src` stages did (`srcAccess`) done
/// before `dst` stages do theirs (`dstAccess`)
fn memory(cmd:vk.CommandBufferProxy,src:vk.PipelineStageFlags2,srcAccess:vk.AccessFlags2,dst:vk.PipelineStageFlags2,dstAccess:vk.AccessFlags2)void{
  // the one barrier
  const b=[_]vk.MemoryBarrier2{.{.src_stage_mask=src,.src_access_mask=srcAccess,.dst_stage_mask=dst,.dst_access_mask=dstAccess}};
  cmd.pipelineBarrier2(&.{.memory_barrier_count=b.len,.p_memory_barriers=&b});
}
