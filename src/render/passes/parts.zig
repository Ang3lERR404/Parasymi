//! parts: library meshes (the wolf, nodes, motes, structures), one
//! instanced draw per mesh with a per-instance transform (or, for beams,
//! motes and the skinned wolf, the parameters part.vert places them by).
const lib=@import("../../lib.zig");
const std=lib.std;
const sliceAsBytes=std.mem.sliceAsBytes;
const vk=lib.engine.vk;
const m=lib.engine.core.math;
const vertex=lib.vertex;
const pipeline=lib.engine.gfx.pipeline;
const meshlib=lib.meshlib;
const ctx=lib.engine.gfx.ctx;
const Ctx=ctx.Ctx;
const Buffer=lib.engine.gfx.buffer.Buffer;
const pass=renderer.pass;
const renderer=lib.renderer;
pub const max=1<<15;
/// skinned parts' bones a frame can hold
pub const maxBones=256;
const bindings=&[_]vk.VertexInputBindingDescription{
  pipeline.binding(vertex.Mesh,0,.vertex),pipeline.binding(vertex.PartInstance,1,.instance),pipeline.binding(vertex.Skin,2,.vertex),
  pipeline.binding(vertex.Grow,3,.vertex),
};
const attrs=&(pipeline.attrs(vertex.Mesh,0,0)++pipeline.attrs(vertex.PartInstance,1,5)++pipeline.attrs(vertex.Skin,2,16)++pipeline.attrs(vertex.Grow,3,21));
pub const desc:pass.Desc=.{
  .vert=@embedFile("part.vert"),.frag=@embedFile("part.frag"),
  .bindings=bindings,.attrs=attrs,.perSample=true,
};
/// this frame's instances and bones, and where each mesh's run of instances
/// starts and how long it is (the glass pass draws the same runs)
pub const Frame=struct{
  inst:Buffer=.{},
  bones:Buffer=.{},
  first:[meshlib.slots]u32=undefined,
  counts:[meshlib.slots]u32=@splat(0),
  /// the push constants both passes draw with (the bones' address in them)
  push:renderer.WorldPush=undefined,
};
pub fn initFrame(c:*const Ctx)ctx.Error!Frame{
  var f:Frame=.{.inst=try Buffer.init(c,max*@sizeOf(vertex.PartInstance),.{.vertex_buffer=true})};
  errdefer f.inst.deinit(c);
  f.bones=try Buffer.init(c,maxBones*@sizeOf(m.M4),.{.storage_buffer=true,.shader_device_address=true});
  return f;
}
pub fn deinitFrame(f:*Frame,c:*const Ctx)void{
  f.inst.deinit(c);
  f.bones.deinit(c);
}
/// upload every instance and bone (before any pass draws them).
pub fn prepare(r:*renderer.Renderer,f:*Frame,scene:*const renderer.Scene,stats:*renderer.Stats)void{
  stats.parts=pass.upload(vertex.PartInstance,&f.inst,&scene.parts,&f.first,&f.counts,max);
  f.bones.write(0,sliceAsBytes(scene.bones[0..@min(scene.bones.len,maxBones)]));
  const at=f.bones.address(&r.ctx);
  f.push=scene.push;
  f.push.bones=.{@truncate(at),@truncate(at>>32)};
}
/// their solid fragments.
pub fn record(r:*renderer.Renderer,f:*Frame,cmd:vk.CommandBufferProxy,_:*const renderer.Scene,stats:*renderer.Stats)void{
  draw(r,f,cmd,stats,.parts);
}
fn draw(r:*renderer.Renderer,f:*const Frame,cmd:vk.CommandBufferProxy,stats:*renderer.Stats,p:renderer.Pass)void{
  if(stats.parts==0)return;
  cmd.bindPipeline(.graphics,r.pipe(p));
  cmd.pushConstants(r.layout(.world),pass.stages,0,@sizeOf(renderer.WorldPush),&f.push);
  cmd.bindVertexBuffers(0,&.{r.ext.meshes.buf,f.inst.buf,r.ext.skins.buf,r.ext.grows.buf},&.{0,0,0,0});
  for(0..meshlib.slots)|i|{
    if(f.counts[i]==0 or (p==.partsGlass and !r.ext.partGlassy[i]))continue;
    const mesh=if(p==.partsShadow)renderer.caster(i)else i;
    cmd.draw(r.ext.partRanges[mesh][1],f.counts[i],r.ext.partRanges[mesh][0],f.first[i]);
    stats.draws+=1;
  }
}
/// the parts' see-through fragments (sap and resin, shadows, beams, the
/// halo), drawn once every solid surface is down: the same instances,
/// blended over what is there, writing no depth.
pub const glass=struct{
  pub const desc:pass.Desc=.{
    .vert=@embedFile("part.vert"),.frag=@embedFile("part_glass.frag"),
    .bindings=bindings,.attrs=attrs,
    .blend=true,.depthWrite=false,.nearer=true,.perSample=true,
  };
  pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,_:*const renderer.Scene,stats:*renderer.Stats)void{
    draw(r,&r.frames[r.fi].pass.parts,cmd,stats,.partsGlass);
  }
};
/// the parts as the key light sees them, into every cascade of its shadow
/// map: the wolf skinned as drawn, structures swaying and growing (what is
/// light itself, the beams, motes and the halo, casts none; part.vert
/// under SHADOW)
pub const shadow=struct{
  pub const desc:pass.Desc=.{
    .vert=@embedFile("part_shadow.vert"),.frag=lib.engine.shadowFrag,
    .bindings=bindings,.attrs=attrs,.target=.shadow,
  };
  pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,_:*const renderer.Scene,stats:*renderer.Stats)void{
    draw(r,&r.frames[r.fi].pass.parts,cmd,stats,.partsShadow);
  }
};
