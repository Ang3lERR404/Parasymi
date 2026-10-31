//! parts: library meshes (the wolf, nodes, motes, structures), one
//! instanced draw per mesh with a per-instance transform (or, for beams,
//! motes and the skinned wolf, the parameters part.vert places them by).
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// views the bones as the bytes their buffer takes
const sliceAsBytes=std.mem.sliceAsBytes;
/// the Vulkan bindings
const vk=lib.engine.vk;
/// all the maths: matrices
const m=lib.engine.core.math;
/// the garden's vertex and instance layouts
const vertex=lib.vertex;
/// builds vertex bindings and attributes from a layout
const pipeline=lib.engine.gfx.pipeline;
/// the library of part meshes, one run of instances each
const meshlib=lib.meshlib;
/// the graphics context and how it fails
const ctx=lib.engine.gfx.ctx;
/// the graphics context, which buffers are made on
const Ctx=ctx.Ctx;
/// a GPU buffer: instances, bones
const Buffer=lib.engine.gfx.buffer.Buffer;
/// what a pass declares, and the upload helpers
const pass=renderer.pass;
/// the garden's renderer: its scene, meshes and stats
const renderer=lib.renderer;
/// part instances a frame can hold
pub const max=1<<15;
/// skinned parts' bones a frame can hold
pub const maxBones=256;
// binding 4: the same mesh buffer, offset to the mesh's next key, so an
// instance blends into it (see the renderer's `Ext.partMorph`)
/// where each vertex stream comes from: mesh, instance, skin weights, growth timing, next key
const bindings=&[_]vk.VertexInputBindingDescription{
  pipeline.binding(vertex.Mesh,0,.vertex),pipeline.binding(vertex.PartInstance,1,.instance),pipeline.binding(vertex.Skin,2,.vertex),
  pipeline.binding(vertex.Grow,3,.vertex),pipeline.binding(vertex.Mesh,4,.vertex),
};
/// every attribute of those streams, at its shader location
const attrs=&(pipeline.attrs(vertex.Mesh,0,0)++pipeline.attrs(vertex.PartInstance,1,5)++pipeline.attrs(vertex.Skin,2,17)++pipeline.attrs(vertex.Grow,3,22)++pipeline.attrs(vertex.MeshPose,4,24));
/// the solid parts pipeline: part.vert places each instance, part.frag shades it
pub const desc:pass.Desc=.{
  .vert=@embedFile("part.vert"),.frag=@embedFile("part.frag"),
  .bindings=bindings,.attrs=attrs,.perSample=true,
};
/// this frame's instances and bones, and where each mesh's run of instances
/// starts and how long it is (the glass pass draws the same runs)
pub const Frame=struct{
  /// this frame's part instances
  inst:Buffer=.{},
  /// this frame's bones, read by address in part.vert
  bones:Buffer=.{},
  /// where each mesh's run of instances starts
  first:[meshlib.slots]u32=undefined,
  /// how many instances each mesh has
  counts:[meshlib.slots]u32=@splat(0),
  /// the push constants both passes draw with (the bones' address in them)
  push:renderer.WorldPush=undefined,
};
/// makes one frame's buffers: room for every instance and bone
pub fn initFrame(c:*const Ctx)ctx.Error!Frame{
  // the frame, its instance buffer first
  var f:Frame=.{.inst=try Buffer.init(c,max*@sizeOf(vertex.PartInstance),.{.vertex_buffer=true})};
  errdefer f.inst.deinit(c);
  f.bones=try Buffer.init(c,maxBones*@sizeOf(m.M4),.{.storage_buffer=true,.shader_device_address=true});
  return f;
}
/// frees one frame's buffers
pub fn deinitFrame(f:*Frame,c:*const Ctx)void{
  f.inst.deinit(c);
  f.bones.deinit(c);
}
/// upload every instance and bone (before any pass draws them).
pub fn prepare(r:*renderer.Renderer,f:*Frame,scene:*const renderer.Scene,stats:*renderer.Stats)void{
  stats.parts=pass.upload(vertex.PartInstance,&f.inst,&scene.parts,&f.first,&f.counts,max);
  f.bones.write(0,sliceAsBytes(scene.bones[0..@min(scene.bones.len,maxBones)]));
  // where the bones' buffer lies on the device
  const at=f.bones.address(&r.ctx);
  f.push=scene.push;
  f.push.bones=.{@truncate(at),@truncate(at>>32)};
}
/// their solid fragments.
pub fn record(r:*renderer.Renderer,f:*Frame,cmd:vk.CommandBufferProxy,_:*const renderer.Scene,stats:*renderer.Stats)void{
  draw(r,f,cmd,stats,.parts);
}
/// draws every mesh's run of instances with pass `p`'s pipeline, each bound
/// to its next key: the see-through pass skips meshes with nothing
/// see-through, the shadow pass casts each with its coarsest level of detail
fn draw(r:*renderer.Renderer,f:*const Frame,cmd:vk.CommandBufferProxy,stats:*renderer.Stats,p:renderer.Pass)void{
  if(stats.parts==0)return;
  cmd.bindPipeline(.graphics,r.pipe(p));
  cmd.pushConstants(r.layout(.world),pass.stages,0,@sizeOf(renderer.WorldPush),&f.push);
  cmd.bindVertexBuffers(0,&.{r.ext.meshes.buf,f.inst.buf,r.ext.skins.buf,r.ext.grows.buf},&.{0,0,0,0});
  for(0..meshlib.slots)|i|{
    if(f.counts[i]==0 or ((p==.partsGlass or p==.partsAir) and !r.ext.partGlassy[i]))continue;
    // the mesh drawn: the caster's coarsest one in the shadow pass
    const mesh=if(p==.partsShadow)renderer.caster(i)else i;
    cmd.bindVertexBuffers(4,&.{r.ext.meshes.buf},&.{r.ext.partMorph[mesh]});
    cmd.draw(r.ext.partRanges[mesh][1],f.counts[i],r.ext.partRanges[mesh][0],f.first[i]);
    stats.draws+=1;
  }
}
/// the parts' see-through fragments (sap and resin, shadows, beams, the
/// halo), drawn once every solid surface is down: the same instances,
/// blended over what is there, writing no depth.
pub const glass=struct{
  /// the see-through parts pipeline: blended, writing no depth
  pub const desc:pass.Desc=.{
    .vert=@embedFile("part.vert"),.frag=@embedFile("part_glass.frag"),
    .bindings=bindings,.attrs=attrs,
    .blend=true,.depthWrite=false,.nearer=true,.perSample=true,
  };
  /// draws the same runs of instances, blended over what is there
  pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,_:*const renderer.Scene,stats:*renderer.Stats)void{
    draw(r,&r.frames[r.fi].pass.parts,cmd,stats,.partsGlass);
  }
};
/// the parts as the key light sees them, into every cascade of its shadow
/// map: the wolf skinned as drawn, structures swaying and growing (what is
/// light itself, the beams, motes and the halo, casts none; part.vert
/// under SHADOW)
pub const shadow=struct{
  /// the shadow pipeline: part_shadow.vert into the key light's cascades
  pub const desc:pass.Desc=.{
    .vert=@embedFile("part_shadow.vert"),.frag=lib.engine.shadowFrag,
    .bindings=bindings,.attrs=attrs,.target=.shadow,
  };
  /// draws every caster into the shadow map
  pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,_:*const renderer.Scene,stats:*renderer.Stats)void{
    draw(r,&r.frames[r.fi].pass.parts,cmd,stats,.partsShadow);
  }
};
/// the air round what glows (beams, flashes, the halo, energy, the
/// constellate's lines and points): the same instances drawn again into the
/// fog's volume after its march, each glow spread wider and its light added
/// to the air there as much as the air is dense (part.frag under AIR), so
/// what glows lights the mist round it
pub const air=struct{
  /// the air pipeline: added onto the volume, testing the world's depth
  /// itself (the volume has none of its own)
  pub const desc:pass.Desc=.{
    .vert=@embedFile("part_air.vert"),.frag=@embedFile("part_air.frag"),
    .bindings=bindings,.attrs=attrs,
    .depth=false,.blend=true,.additive=true,.target=.volume,
  };
  /// draws the runs with anything see-through (every glow is), lighting the air
  pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,_:*const renderer.Scene,stats:*renderer.Stats)void{
    draw(r,&r.frames[r.fi].pass.parts,cmd,stats,.partsAir);
  }
};
