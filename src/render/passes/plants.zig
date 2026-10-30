//! plants: every species' grown mesh variants, instanced; animation lives in plant.vert.
const lib=@import("../../lib.zig");
/// the Vulkan bindings
const vk=lib.engine.vk;
/// the garden's vertex and instance layouts
const vertex=lib.vertex;
/// builds vertex bindings and attributes from a layout
const pipeline=lib.engine.gfx.pipeline;
/// the graphics context and how it fails
const ctx=lib.engine.gfx.ctx;
/// the graphics context, which buffers are made on
const Ctx=ctx.Ctx;
/// a GPU buffer: this frame's instances
const Buffer=lib.engine.gfx.buffer.Buffer;
/// what a pass declares, and the upload helpers
const pass=renderer.pass;
/// the garden's renderer: its scene, meshes and stats
const renderer=lib.renderer;
/// plant instances a frame can hold
pub const max=1<<16;
// binding 2: the same mesh buffer, offset to the next growth key, so a
// confluence blends toward it (see the renderer's `Ext.plantMorph`)
/// where each vertex stream comes from: mesh, instance, next growth key
const bindings=&[_]vk.VertexInputBindingDescription{pipeline.binding(vertex.Mesh,0,.vertex),pipeline.binding(vertex.PlantInstance,1,.instance),pipeline.binding(vertex.Mesh,2,.vertex)};
/// every attribute of those streams, at its shader location
const attrs=&(pipeline.attrs(vertex.Mesh,0,0)++pipeline.attrs(vertex.PlantInstance,1,5)++pipeline.attrs(vertex.MeshPose,2,11));
/// the solid plants pipeline: plant.vert grows and sways each, plant.frag shades it
pub const desc:pass.Desc=.{
  .vert=@embedFile("plant.vert"),.frag=@embedFile("plant.frag"),
  .bindings=bindings,.attrs=attrs,.perSample=true,
};
/// this frame's instances, and where each mesh's run of them starts and how
/// long it is (the glass pass draws the same runs)
pub const Frame=struct{
  /// this frame's plant instances
  inst:Buffer=.{},
  /// where each mesh's run of instances starts
  first:[renderer.plantMeshes]u32=undefined,
  /// how many instances each mesh has
  counts:[renderer.plantMeshes]u32=@splat(0),
};
/// makes one frame's buffer: room for every instance
pub fn initFrame(c:*const Ctx)ctx.Error!Frame{
  return.{.inst=try Buffer.init(c,max*@sizeOf(vertex.PlantInstance),.{.vertex_buffer=true})};
}
/// frees one frame's buffer
pub fn deinitFrame(f:*Frame,c:*const Ctx)void{f.inst.deinit(c);}
/// upload every instance (before any pass draws them).
pub fn prepare(r:*renderer.Renderer,f:*Frame,scene:*const renderer.Scene,stats:*renderer.Stats)void{
  _=r;
  stats.instances=pass.upload(vertex.PlantInstance,&f.inst,&scene.instances,&f.first,&f.counts,max);
}
/// their solid fragments.
pub fn record(r:*renderer.Renderer,f:*Frame,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats)void{
  draw(r,f,cmd,scene,stats,.plants);
}
/// draws every mesh's run of instances with pass `p`'s pipeline, each bound
/// to its next growth key; the shadow pass casts with the coarsest detail
fn draw(r:*renderer.Renderer,f:*const Frame,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats,p:renderer.Pass)void{
  if(stats.instances==0)return;
  cmd.bindPipeline(.graphics,r.pipe(p));
  cmd.pushConstants(r.layout(.world),pass.stages,0,@sizeOf(renderer.WorldPush),&scene.push);
  cmd.bindVertexBuffers(0,&.{r.ext.meshes.buf,f.inst.buf},&.{0,0});
  for(0..renderer.plantMeshes)|i|{
    if(f.counts[i]==0)continue;
    // the mesh drawn: the caster's coarsest one in the shadow pass
    const mesh=if(p==.plantsShadow)renderer.caster(i)else i;
    cmd.bindVertexBuffers(2,&.{r.ext.meshes.buf},&.{r.ext.plantMorph[mesh]});
    cmd.draw(r.ext.plantRanges[mesh][1],f.counts[i],r.ext.plantRanges[mesh][0],f.first[i]);
    stats.draws+=1;
  }
}
/// the plants' see-through fragments (thin petals, a confluence's sap, a
/// placement preview), drawn once every solid surface is down: the same
/// instances, blended over what is there, writing no depth.
pub const glass=struct{
  /// the see-through plants pipeline: blended, writing no depth
  pub const desc:pass.Desc=.{
    .vert=@embedFile("plant.vert"),.frag=@embedFile("plant_glass.frag"),
    .bindings=bindings,.attrs=attrs,
    .blend=true,.depthWrite=false,.nearer=true,.perSample=true,
  };
  /// draws the same runs of instances, blended over what is there
  pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats)void{
    draw(r,&r.frames[r.fi].pass.plants,cmd,scene,stats,.plantsGlass);
  }
};
/// the plants as the key light sees them, into every cascade of its shadow
/// map: the same instances, swaying and growing as they are drawn (what
/// is light itself or clear sap casts none; plant.vert under SHADOW)
pub const shadow=struct{
  /// the shadow pipeline: plant_shadow.vert into the key light's cascades
  pub const desc:pass.Desc=.{
    .vert=@embedFile("plant_shadow.vert"),.frag=lib.engine.shadowFrag,
    .bindings=bindings,.attrs=attrs,.target=.shadow,
  };
  /// draws every caster into the shadow map
  pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats)void{
    draw(r,&r.frames[r.fi].pass.plants,cmd,scene,stats,.plantsShadow);
  }
};
