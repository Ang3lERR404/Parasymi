//! shadows traced as rays: what casts them, as it stands this very frame.
//!
//! Each frame the casters' own vertex shaders run once more with nothing
//! rasterized (a `capture` pass, built with CAPTURE), writing every vertex
//! where they placed it (swayed, grown, gathered, skinned) into `caught`,
//! instance by instance. Those vertices, with the meshes' own indices, are
//! built into acceleration structures: one of what blocks every light's
//! rays, one of what blocks only the points of light's (a game's choice,
//! per vertex), and over them the top level the shaders trace through
//! (light.glsl under RAY: `traced`). A triangle a caster leaves out (light
//! itself) has its vertices written as NaN, which a build leaves inactive.
//! The structures are built anew each frame, fast to build, so whatever
//! moves, grows or is added since is in them. Everything here exists only
//! where the GPU can trace rays (`Ctx.rayTracing`).
/// the standard library
const std=@import("std");
/// the allocator the frame's lists are made with
const Allocator=std.mem.Allocator;
/// the instance records seen as their bytes
const sliceAsBytes=std.mem.sliceAsBytes;
/// the hash a frame's key is folded with
const Wyhash=std.hash.Wyhash;
/// one value seen as its bytes, for a frame's key
const asBytes=std.mem.asBytes;
/// how many frames a level is refitted before it is built in full again (a
/// refitted tree slowly loosens as what it holds sways and grows)
const refits:u32=30;
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
/// how many bottom levels a frame may build (a game's choice which holds
/// what: whatever comes and goes often, kept apart from what stays, lets
/// what stays be refitted), each holding casters of one set
pub const levels=4;
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
  /// each bottom level
  low:[levels]Accel=@splat(.{}),
  /// which set each bottom level holds (its first instance's this frame)
  kind:[levels]Caster=@splat(.both),
  /// the top level, holding each bottom level not empty
  top:Accel=.{},
  /// where both levels are built (device-local)
  scratch:Buffer=.{},
  /// the top level's own scratch, bytes
  topScratch:u64=0,
  /// each frame in flight's instance records (host-visible)
  inst:[frames]Buffer=@splat(.{}),
  /// this frame's triangles, each level's geometries, their ranges and
  /// primitive counts
  geoms:[levels]std.ArrayList(vk.AccelerationStructureGeometryKHR)=@splat(.empty),
  /// (each geometry's range)
  ranges:[levels]std.ArrayList(vk.AccelerationStructureBuildRangeInfoKHR)=@splat(.empty),
  /// (each geometry's triangles)
  prims:[levels]std.ArrayList(u32)=@splat(.empty),
  /// how many triangles each level built last frame
  tris:[levels]u64=@splat(0),
  /// what each level caught this frame, as a key: the same as its last
  /// full build's means the same instances of the same meshes in the same
  /// places among the caught vertices, so it is only refitted round where
  /// they moved (`mark`, and its triangles)
  key:[levels]u64=@splat(0),
  /// each level's key when it was last built in full (null: never built)
  builtKey:[levels]?u64=@splat(null),
  /// how many frames each level has been refitted since it was built in full
  since:[levels]u32=@splat(0),
  /// how many levels were refitted, and built in full, since the start
  /// (logged as the renderer closes)
  refitted:u64=0,
  /// (built in full)
  rebuilt:u64=0,
  /// the top level and its instance records; anything half made is freed
  pub fn init(c:*const Ctx,gpa:Allocator)ctx.Error!Rays{
    // the rays being made
    var r:Rays=.{.gpa=gpa};
    errdefer r.deinit(c);
    for(&r.inst)|*b|b.*=try Buffer.init(c,levels*@sizeOf(vk.AccelerationStructureInstanceKHR),.{.acceleration_structure_build_input_read_only_khr=true,.shader_device_address=true});
    // the top level's size, for as many instances as there are sets
    const geom=topGeometry(0);
    const info=topInfo(&geom);
    var size:vk.AccelerationStructureBuildSizesInfoKHR=.{.acceleration_structure_size=0,.update_scratch_size=0,.build_scratch_size=0};
    const most=[_]u32{levels};
    c.device.getAccelerationStructureBuildSizesKHR(.device_khr,&info,&most,&size);
    try r.top.make(c,.top_level_khr,size.acceleration_structure_size);
    r.topScratch=size.build_scratch_size;
    return r;
  }
  /// free everything held
  pub fn deinit(r:*Rays,c:*const Ctx)void{
    for(&r.caught)|*b|b.deinit(c);
    for(&r.low)|*a|a.deinit(c);
    r.top.deinit(c);
    r.scratch.deinit(c);
    for(&r.inst)|*b|b.deinit(c);
    for(&r.geoms,&r.ranges,&r.prims)|*g,*rg,*p|{
      g.deinit(r.gpa);
      rg.deinit(r.gpa);
      p.deinit(r.gpa);
    }
  }
  /// how many triangles of set `s` were built last frame, every level's
  pub fn trisOf(r:*const Rays,s:Caster)u64{
    // the sum so far
    var n:u64=0;
    for(r.tris,r.kind,r.low)|t,k,l|if(k==s and l.handle!=.null_handle){n+=t;};
    return n;
  }
  /// what the shaders' descriptor binds (light.glsl `casters`)
  pub fn handle(r:*const Rays)vk.AccelerationStructureKHR{return r.top.handle;}
  /// a new frame: nothing caught yet
  pub fn begin(r:*Rays)void{
    r.used=0;
    r.key=@splat(0);
    for(&r.geoms,&r.ranges,&r.prims)|*g,*rg,*p|{
      g.clearRetainingCapacity();
      rg.clearRetainingCapacity();
      p.clearRetainingCapacity();
    }
  }
  /// fold `bytes` into level `l`'s key this frame: what a capture pass
  /// caught into it, told apart from another frame's (which instances of
  /// which meshes, in their order). A level whose key and triangles match
  /// its last full build's is refitted, not built anew (`build`).
  pub fn mark(r:*Rays,l:usize,bytes:[]const u8)void{r.key[l]=Wyhash.hash(r.key[l],bytes);}
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
  /// one caught instance of set `s` into level `i`: its `verts` vertices
  /// from `slot` on, its `tris` triangles' indices at `index` (a device
  /// address, each counting from its first vertex)
  pub fn add(r:*Rays,c:*const Ctx,i:usize,s:Caster,slot:u64,verts:u32,index:u64,tris:u32)Allocator.Error!void{
    if(tris==0 or verts==0)return;
    r.kind[i]=s;
    try r.geoms[i].append(r.gpa,.{
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
    try r.ranges[i].append(r.gpa,.{.primitive_count=tris,.primitive_offset=0,.first_vertex=0,.transform_offset=0});
    try r.prims[i].append(r.gpa,tris);
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
  /// build what was caught into each set's bottom level, and the top level
  /// over them, for the world's shaders to trace (frame in flight `fi`'s
  /// instance records); grows a level or the scratch when it must (waiting
  /// for the GPU)
  pub fn build(r:*Rays,c:*const Ctx,cmd:vk.CommandBufferProxy,fi:usize)ctx.Error!void{
    // each set's build, its sizes, and whether it holds anything
    var infos:[levels]vk.AccelerationStructureBuildGeometryInfoKHR=undefined;
    var sizes:[levels]vk.AccelerationStructureBuildSizesInfoKHR=undefined;
    // how much scratch every bottom level wants together
    var need:u64=r.topScratch;
    var sum:u64=0;
    // each level's key this frame: what was caught, its triangles, where they lie
    var keys:[levels]u64=undefined;
    for(0..levels)|i|{
      keys[i]=Wyhash.hash(r.key[i],sliceAsBytes(r.prims[i].items));
      keys[i]=Wyhash.hash(keys[i],asBytes(&r.caught[@intFromEnum(r.kind[i])].buf));
      infos[i]=.{.type=.bottom_level_khr,.flags=.{.prefer_fast_trace_khr=true,.allow_update_khr=true},.mode=.build_khr,.geometry_count=@intCast(r.geoms[i].items.len),.p_geometries=r.geoms[i].items.ptr,.scratch_data=.{.device_address=0}};
      sizes[i]=.{.acceleration_structure_size=0,.update_scratch_size=0,.build_scratch_size=0};
      r.tris[i]=0;
      for(r.prims[i].items)|p|r.tris[i]+=p;
      if(r.geoms[i].items.len==0)continue;
      c.device.getAccelerationStructureBuildSizesKHR(.device_khr,&infos[i],r.prims[i].items.ptr,&sizes[i]);
      sum+=m.alignUp(sizes[i].build_scratch_size,c.scratchAlign);
    }
    need=@max(need,sum)+c.scratchAlign;
    // grown where too small: the device must be idle, a frame in flight may read them
    var short=r.scratch.size<need;
    for(0..levels)|i|short=short or sizes[i].acceleration_structure_size>r.low[i].buf.size;
    if(short){
      c.device.deviceWaitIdle()catch|e|return ctx.fold(e);
      if(r.scratch.size<need){
        r.scratch.deinit(c);
        r.scratch=try Buffer.initRoom(c,.{.storage_buffer=true,.shader_device_address=true},grow(need),&.{});
      }
      for(0..levels)|i|if(sizes[i].acceleration_structure_size>r.low[i].buf.size){
        try r.low[i].make(c,.bottom_level_khr,grow(sizes[i].acceleration_structure_size));
        r.builtKey[i]=null;
      };
    }
    // the scratch's first aligned address, and where each build's begins
    const base=m.alignUp(r.scratch.address(c),c.scratchAlign);
    var at=base;
    // the builds recorded, and their ranges
    var builds:[levels]vk.AccelerationStructureBuildGeometryInfoKHR=undefined;
    var spans:[levels][*]const vk.AccelerationStructureBuildRangeInfoKHR=undefined;
    var n:usize=0;
    // the top level's instance records, one per set built
    var recs:[levels]vk.AccelerationStructureInstanceKHR=undefined;
    for(0..levels)|i|{
      if(r.geoms[i].items.len==0)continue;
      builds[n]=infos[i];
      builds[n].dst_acceleration_structure=r.low[i].handle;
      // the same as its last full build: refitted round where things moved,
      // until it has been refitted long enough to want building anew
      if(r.builtKey[i]==keys[i] and r.since[i]<refits){
        builds[n].mode=.update_khr;
        builds[n].src_acceleration_structure=r.low[i].handle;
        r.since[i]+=1;
        r.refitted+=1;
      }else{
        r.builtKey[i]=keys[i];
        r.since[i]=0;
        r.rebuilt+=1;
      }
      builds[n].scratch_data=.{.device_address=at};
      spans[n]=r.ranges[i].items.ptr;
      at+=m.alignUp(sizes[i].build_scratch_size,c.scratchAlign);
      recs[n]=.{
        .transform=.{.matrix=.{.{1,0,0,0},.{0,1,0,0},.{0,0,1,0}}},
        .instance_custom_index_and_mask=.{.instance_custom_index=0,.mask=masks[@intFromEnum(r.kind[i])]},
        .instance_shader_binding_table_record_offset_and_flags=.{.instance_shader_binding_table_record_offset=0,.flags=@truncate(@as(u32,@bitCast(vk.GeometryInstanceFlagsKHR{.force_opaque_khr=true})))},
        .acceleration_structure_reference=r.low[i].address(c),
      };
      n+=1;
    }
    memory(cmd,.{.vertex_shader=true},.{.shader_write=true},.{.acceleration_structure_build_khr=true},.{.shader_read=true,.acceleration_structure_read_khr=true});
    if(n>0)cmd.buildAccelerationStructuresKHR(builds[0..n],spans[0..n]);
    memory(cmd,.{.acceleration_structure_build_khr=true},.{.acceleration_structure_write_khr=true},.{.acceleration_structure_build_khr=true},.{.acceleration_structure_read_khr=true,.acceleration_structure_write_khr=true});
    // the top level over them, its instances this frame's records
    r.inst[fi].write(0,sliceAsBytes(recs[0..n]));
    const geom=topGeometry(r.inst[fi].address(c));
    var info=topInfo(&geom);
    info.dst_acceleration_structure=r.top.handle;
    info.scratch_data=.{.device_address=base};
    const range=[_]vk.AccelerationStructureBuildRangeInfoKHR{.{.primitive_count=@intCast(n),.primitive_offset=0,.first_vertex=0,.transform_offset=0}};
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
/// one barrier over all memory: what `src` stages did (`srcAccess`) done
/// before `dst` stages do theirs (`dstAccess`)
fn memory(cmd:vk.CommandBufferProxy,src:vk.PipelineStageFlags2,srcAccess:vk.AccessFlags2,dst:vk.PipelineStageFlags2,dstAccess:vk.AccessFlags2)void{
  // the one barrier
  const b=[_]vk.MemoryBarrier2{.{.src_stage_mask=src,.src_access_mask=srcAccess,.dst_stage_mask=dst,.dst_access_mask=dstAccess}};
  cmd.pipelineBarrier2(&.{.memory_barrier_count=b.len,.p_memory_barriers=&b});
}
