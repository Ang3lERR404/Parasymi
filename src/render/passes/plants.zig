//! plants: every species' grown mesh variants, instanced; animation lives in plant.vert.
const lib=@import("../../lib.zig");
/// views one instance as the bytes its buffer takes
const asBytes=lib.std.mem.asBytes;
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
/// plant instances a frame's shadow cubes can hold together (each cube
/// only those within its light's reach)
pub const cubeMax=1<<14;
/// the points of light's shadow cubes: how many faces, which a caster stands in
const cubeMod=lib.engine.render.cube;
/// faces a shadow cube is drawn in, one at a time
const faces=cubeMod.faces;
/// faces of every shadow cube a frame can hold, each drawing its own instances
const maxFaces=cubeMod.maxCubes*faces;
/// all the maths: distances
const m=lib.engine.core.math;
// binding 2: the same mesh buffer, offset to the next growth key, so a
// confluence blends toward it (see the renderer's `Ext.plantMorph`)
/// where each vertex stream comes from: mesh, instance, next growth key
const bindings=&[_]vk.VertexInputBindingDescription{pipeline.binding(vertex.Mesh,0,.vertex),pipeline.binding(vertex.PlantInstance,1,.instance),pipeline.binding(vertex.Mesh,2,.vertex)};
/// every attribute of those streams, at its shader location
const attrs=&(pipeline.attrs(vertex.Mesh,0,0)++pipeline.attrs(vertex.PlantInstance,1,5)++pipeline.attrs(vertex.MeshPose,2,14));
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
  /// whether any of each mesh's instances is a placement preview (drawn
  /// see-through whole, so the glass pass draws all of its mesh)
  ghosts:[renderer.plantMeshes]bool=@splat(false),
  /// the instances each shadow cube's casters draw: per cube, per mesh,
  /// those within its light's reach, back to back
  cubeInst:Buffer=.{},
  /// where each cube's run of each mesh's instances starts in `cubeInst`
  cubeFirst:[maxFaces][renderer.plantMeshes]u32=undefined,
  /// how many instances each cube draws of each mesh
  cubeCounts:[maxFaces][renderer.plantMeshes]u32=@splat(@splat(0)),
};
/// makes one frame's buffers: room for every instance, and for those the
/// shadow cubes draw
pub fn initFrame(c:*const Ctx)ctx.Error!Frame{
  // the frame, its instance buffer first
  var f:Frame=.{.inst=try Buffer.init(c,max*@sizeOf(vertex.PlantInstance),.{.vertex_buffer=true})};
  errdefer f.inst.deinit(c);
  f.cubeInst=try Buffer.init(c,cubeMax*@sizeOf(vertex.PlantInstance),.{.vertex_buffer=true});
  return f;
}
/// frees one frame's buffers
pub fn deinitFrame(f:*Frame,c:*const Ctx)void{
  f.inst.deinit(c);
  f.cubeInst.deinit(c);
}
/// upload every instance (before any pass draws them), and for each shadow
/// cube held this frame those that may stand in its light
pub fn prepare(r:*renderer.Renderer,f:*Frame,scene:*const renderer.Scene,stats:*renderer.Stats)void{
  stats.instances=pass.upload(vertex.PlantInstance,&f.inst,&scene.instances,&f.first,&f.counts,max);
  for(&f.ghosts,scene.instances)|*gh,list|{
    gh.*=false;
    for(list)|in|if(in.c[1]>0.5){
      gh.*=true;
      break;
    };
  }
  // how many instances the cubes hold so far
  var n:u32=0;
  for(&f.cubeFirst,&f.cubeCounts,0..)|*first,*counts,k|{
    counts.*=@splat(0);
    // the light: where it is and how far it reaches, and which of its faces
    const sp=r.cubeSpheres[k/faces] orelse continue;
    const at=m.v3(sp[0],sp[1],sp[2]);
    const face=k%faces;
    for(scene.instances,0..)|list,i|{
      first[i]=n;
      // how far a caster of this mesh may lean from where it stands
      const size=renderer.casterReach(r.ext.plantReach[renderer.caster(i)]);
      for(list)|in|{
        if(n>=cubeMax)break;
        // where it stands: near enough the light, and inside this face
        const p=m.v3(in.pos[0],in.pos[1],in.pos[2]);
        if(in.c[1]>0.5 or m.dist(p,at)>sp[3]+size or !cubeMod.sees(at,face,p,size))continue;
        f.cubeInst.write(n*@sizeOf(vertex.PlantInstance),asBytes(&in));
        n+=1;
        counts[i]+=1;
      }
    }
  }
}
/// their solid fragments, of the triangles the head pass left.
pub fn record(r:*renderer.Renderer,f:*Frame,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats)void{
  draw(r,f,cmd,scene,stats,.plants);
}
/// draws every mesh's run of instances with pass `p`'s pipeline, each bound
/// to its next growth key; the shadow passes cast with the coarsest detail,
/// a shadow cube's only what lies within its light's reach
fn draw(r:*renderer.Renderer,f:*const Frame,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats,p:renderer.Pass)void{
  if(stats.instances==0)return;
  // whether this draws into a shadow cube, and the instances it draws from
  const cubed=p==.plantsCube;
  const first=if(cubed)&f.cubeFirst[r.cubeNow]else &f.first;
  const counts=if(cubed)&f.cubeCounts[r.cubeNow]else &f.counts;
  cmd.bindPipeline(.graphics,r.pipe(p));
  cmd.pushConstants(r.layout(.world),pass.stages,0,@sizeOf(renderer.WorldPush),&scene.push);
  cmd.bindVertexBuffers(0,&.{r.ext.meshes.buf,if(cubed)f.cubeInst.buf else f.inst.buf},&.{0,0});
  cmd.bindIndexBuffer(r.ext.indices.buf,0,.uint32);
  for(0..renderer.plantMeshes)|i|{
    if(counts[i]==0)continue;
    // the mesh drawn: the caster's coarsest one in the shadow passes
    const mesh=if(p==.plantsShadow or cubed)renderer.caster(i)else i;
    // its welded run, and which of its indices this pass draws: the head
    // pass its always-solid head, the solid pass the rest, the glass pass
    // its see-through tail (all of it if a preview is among them)
    const run=r.ext.plantRuns[mesh];
    const from=if(p==.plants or p==.plantsGlass and !f.ghosts[i])run.early else 0;
    const to=if(p==.plantsHead)run.early else run.count;
    if(from==to)continue;
    cmd.bindVertexBuffers(2,&.{r.ext.meshes.buf},&.{r.ext.plantMorph[mesh]});
    cmd.drawIndexed(to-from,counts[i],run.first+from,@intCast(run.base),first[i]);
    stats.draws+=1;
  }
}
/// the plants' always-solid triangles (each mesh's head, `Run.early`:
/// stems, leaves, thorns, tendrils of plants that are not of light),
/// shaded by plant.frag built without the materials they never take
/// (HEAD): the same colours, from a lighter shader. The solid pass then
/// shades the rest.
pub const head=struct{
  /// the head pipeline: plant.vert as ever, plant_head.frag
  pub const desc:pass.Desc=.{
    .vert=@embedFile("plant.vert"),.frag=@embedFile("plant_head.frag"),
    .bindings=bindings,.attrs=attrs,.perSample=true,
  };
  /// draws every mesh's always-solid head
  pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats)void{
    draw(r,&r.frames[r.fi].pass.plants,cmd,scene,stats,.plantsHead);
  }
};
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
/// the plants as a point of light holding a shadow cube sees them, into each
/// face of its cube in turn: those within its reach and inside that face
/// (`Frame.cubeInst`), swaying and
/// growing as they are drawn, casting as into the key light's map (plant.vert
/// under CUBE, which brings SHADOW)
pub const cube=struct{
  /// the cube pipeline: plant_cube.vert into a face of a light's cube
  pub const desc:pass.Desc=.{
    .vert=@embedFile("plant_cube.vert"),.frag=lib.engine.shadowFrag,
    .bindings=bindings,.attrs=attrs,.target=.cube,
  };
  /// draws the casters within the light's reach into its cube
  pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats)void{
    draw(r,&r.frames[r.fi].pass.plants,cmd,scene,stats,.plantsCube);
  }
};
