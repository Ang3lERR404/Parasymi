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
/// part instances a frame's shadow cubes can hold together (each cube only
/// those that may stand in its light)
pub const cubeMax=1<<13;
/// the points of light's shadow cubes: how many faces, which a caster stands in
const cubeMod=lib.engine.render.cube;
/// faces a shadow cube is drawn in, one at a time
const faces=cubeMod.faces;
/// faces of every shadow cube a frame can hold, each drawing its own instances
const maxFaces=cubeMod.maxCubes*faces;
/// views one instance as the bytes its buffer takes
const asBytes=std.mem.asBytes;
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
  /// the instances each shadow cube's casters draw: per cube, per mesh,
  /// those that may stand in its light, back to back
  cubeInst:Buffer=.{},
  /// where each cube's run of each mesh's instances starts in `cubeInst`
  cubeFirst:[maxFaces][meshlib.slots]u32=undefined,
  /// how many instances each cube draws of each mesh
  cubeCounts:[maxFaces][meshlib.slots]u32=@splat(@splat(0)),
};
/// makes one frame's buffers: room for every instance and bone, and for
/// the instances the shadow cubes draw
pub fn initFrame(c:*const Ctx)ctx.Error!Frame{
  // the frame, its instance buffer first
  var f:Frame=.{.inst=try Buffer.init(c,max*@sizeOf(vertex.PartInstance),.{.vertex_buffer=true})};
  errdefer f.inst.deinit(c);
  f.bones=try Buffer.init(c,maxBones*@sizeOf(m.M4),.{.storage_buffer=true,.shader_device_address=true});
  errdefer f.bones.deinit(c);
  f.cubeInst=try Buffer.init(c,cubeMax*@sizeOf(vertex.PartInstance),.{.vertex_buffer=true});
  return f;
}
/// frees one frame's buffers
pub fn deinitFrame(f:*Frame,c:*const Ctx)void{
  f.inst.deinit(c);
  f.bones.deinit(c);
  f.cubeInst.deinit(c);
}
/// upload every instance and bone (before any pass draws them), and for
/// each shadow cube held this frame the instances that may stand in its light
pub fn prepare(r:*renderer.Renderer,f:*Frame,scene:*const renderer.Scene,stats:*renderer.Stats)void{
  stats.parts=pass.upload(vertex.PartInstance,&f.inst,&scene.parts,&f.first,&f.counts,max);
  f.bones.write(0,sliceAsBytes(scene.bones[0..@min(scene.bones.len,maxBones)]));
  // where the bones' buffer lies on the device
  const at=f.bones.address(&r.ctx);
  f.push=scene.push;
  f.push.bones=.{@truncate(at),@truncate(at>>32)};
  // how many instances the cubes hold so far
  var n:u32=0;
  for(&f.cubeFirst,&f.cubeCounts,0..)|*first,*counts,k|{
    counts.*=@splat(0);
    // the light: where it is and how far it reaches, and which of its faces
    const sp=r.cubeSpheres[k/faces] orelse continue;
    const light=m.v3(sp[0],sp[1],sp[2]);
    const face=k%faces;
    for(scene.parts,0..)|list,i|{
      first[i]=n;
      // how far this mesh reaches from its origin, unscaled
      const size=renderer.casterReach(r.ext.partReach[renderer.caster(i)]);
      for(list)|in|{
        if(n>=cubeMax)break;
        if(!stands(in,light,sp[3],face,size))continue;
        f.cubeInst.write(n*@sizeOf(vertex.PartInstance),asBytes(&in));
        n+=1;
        counts[i]+=1;
      }
    }
  }
}
/// whether part `in`, its mesh reaching `size` from its origin, may stand
/// in the light of a point at `light` reaching `reach`, inside its cube's
/// face `face`: placed by a matrix, its origin (the matrix's last column)
/// near enough for its size as the matrix stretches it; along a curve, any
/// of its control points near enough; skinned, always (its bones carry it,
/// few are drawn); a star mote, a burst or a placement preview never (they
/// cast no shadow)
fn stands(in:vertex.PartInstance,light:m.V3,reach:f32,face:usize,size:f32)bool{
  if(in.flags&vertex.partGhost!=0)return false;
  return switch(@as(u32,@intFromFloat(@round(in.e[0])))){
    0=>blk:{
      // how far the matrix stretches the mesh, at most, and where it stands
      const stretch=@max(m.len(m.v3(in.c0[0],in.c0[1],in.c0[2])),@max(m.len(m.v3(in.c1[0],in.c1[1],in.c1[2])),m.len(m.v3(in.c2[0],in.c2[1],in.c2[2]))));
      const p=m.v3(in.c3[0],in.c3[1],in.c3[2]);
      break:blk m.dist(p,light)<=reach+size*stretch and cubeMod.sees(light,face,p,size*stretch);
    },
    1=>blk:{
      for([_]m.Vice(f32,4){in.c0,in.c1,in.c2,in.c3})|c|{
        // this control point
        const p=m.v3(c[0],c[1],c[2]);
        if(m.dist(p,light)<=reach+size and cubeMod.sees(light,face,p,size))break:blk true;
      }
      break:blk false;
    },
    3=>true,
    else=>false,
  };
}
/// their solid fragments, of the triangles the head pass left.
pub fn record(r:*renderer.Renderer,f:*Frame,cmd:vk.CommandBufferProxy,_:*const renderer.Scene,stats:*renderer.Stats)void{
  draw(r,f,cmd,stats,.parts,null);
}
/// draws every mesh's run of instances with pass `p`'s pipeline, each bound
/// to its next key: the see-through pass skips meshes with nothing
/// see-through, the shadow passes cast each with its coarsest level of
/// detail, a shadow cube's only what may stand in its light (its push
/// pointing at the cube's faces, `light`)
fn draw(r:*renderer.Renderer,f:*const Frame,cmd:vk.CommandBufferProxy,stats:*renderer.Stats,p:renderer.Pass,light:?m.Vice(u32,2))void{
  if(stats.parts==0)return;
  // whether this draws into a shadow cube, and the instances it draws from
  const cubed=p==.partsCube;
  const first=if(cubed)&f.cubeFirst[r.cubeNow]else &f.first;
  const counts=if(cubed)&f.cubeCounts[r.cubeNow]else &f.counts;
  // the push: the bones' address in it, and the cube's faces' if any
  var push=f.push;
  if(light)|l|push.light=l;
  cmd.bindPipeline(.graphics,r.pipe(p));
  cmd.pushConstants(r.layout(.world),pass.stages,0,@sizeOf(renderer.WorldPush),&push);
  cmd.bindVertexBuffers(0,&.{r.ext.meshes.buf,if(cubed)f.cubeInst.buf else f.inst.buf,r.ext.skins.buf,r.ext.grows.buf},&.{0,0,0,0});
  cmd.bindIndexBuffer(r.ext.indices.buf,0,.uint32);
  for(0..meshlib.slots)|i|{
    if(counts[i]==0 or ((p==.partsGlass or p==.partsAir) and !r.ext.partGlassy[i]))continue;
    // the mesh drawn: the caster's coarsest one in the shadow passes
    const mesh=if(p==.partsShadow or cubed)renderer.caster(i)else i;
    // its welded run, and which of its indices this pass draws: the head
    // pass its always-solid head, the solid, glass and air passes the
    // rest (its see-through tail), the shadow passes all of it
    const run=r.ext.partRuns[mesh];
    const from=if(p==.partsShadow or cubed or p==.partsHead)0 else run.early;
    const to=if(p==.partsHead)run.early else run.count;
    if(from==to)continue;
    cmd.bindVertexBuffers(4,&.{r.ext.meshes.buf},&.{r.ext.partMorph[mesh]});
    cmd.drawIndexed(to-from,counts[i],run.first+from,@intCast(run.base),first[i]);
    stats.draws+=1;
  }
}
/// the parts' always-solid triangles (each mesh's head, `Run.early`: every
/// role `vertex.seeThrough` leaves out), shaded by part.frag built without
/// the materials they never take (HEAD): the same colours, from a lighter
/// shader. The solid pass then shades the rest.
pub const head=struct{
  /// the head pipeline: part.vert as ever, part_head.frag
  pub const desc:pass.Desc=.{
    .vert=@embedFile("part.vert"),.frag=@embedFile("part_head.frag"),
    .bindings=bindings,.attrs=attrs,.perSample=true,
  };
  /// draws every mesh's always-solid head
  pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,_:*const renderer.Scene,stats:*renderer.Stats)void{
    draw(r,&r.frames[r.fi].pass.parts,cmd,stats,.partsHead,null);
  }
};
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
    draw(r,&r.frames[r.fi].pass.parts,cmd,stats,.partsGlass,null);
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
    draw(r,&r.frames[r.fi].pass.parts,cmd,stats,.partsShadow,null);
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
    draw(r,&r.frames[r.fi].pass.parts,cmd,stats,.partsAir,null);
  }
};
/// the parts as a point of light holding a shadow cube sees them, into each
/// face of its cube in turn: those that may stand in its light there (`Frame.cubeInst`),
/// the wolf skinned as drawn, structures swaying and growing, casting as
/// into the key light's map (part.vert under CUBE, which brings SHADOW)
pub const cube=struct{
  /// the cube pipeline: part_cube.vert into a face of a light's cube
  pub const desc:pass.Desc=.{
    .vert=@embedFile("part_cube.vert"),.frag=lib.engine.shadowFrag,
    .bindings=bindings,.attrs=attrs,.target=.cube,
  };
  /// draws the casters that may stand in the light into its cube
  pub fn record(r:*renderer.Renderer,_:*void,cmd:vk.CommandBufferProxy,scene:*const renderer.Scene,stats:*renderer.Stats)void{
    draw(r,&r.frames[r.fi].pass.parts,cmd,stats,.partsCube,scene.push.light);
  }
};
