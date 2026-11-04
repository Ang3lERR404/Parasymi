//! the view cut into cells, each listing the points of light that reach it,
//! so a surface (or a ray through the air) visits only the lights that can
//! touch it, never every light the frame makes: as many lights as a garden
//! throws, each shaded point paying only for its own.
//!
//! The screen is cut into `x` by `y` tiles and each tile along the eye's
//! depth into `slices` slices (the nearest from the eye to `nearSlice`, the
//! rest each a constant share deeper, the last running on), and each tile
//! has one more cell holding its whole depth, for the air's rays. Every
//! frame a compute pass (cells.comp) tests each light's sphere of reach
//! against each cell's planes and writes a bit for each light that touches
//! it, one 32-bit word for every 32 lights; nothing is dropped, however
//! many share a cell. The shaders find a point's cell from where it lands
//! in the eye's clip space (lighting.glsl `cellAt`) and walk its bits in
//! the order the frame holds the lights, so what each sums is what it
//! summed over all of them; a point outside every cell (behind the eye, off
//! the screen: a shadow cube's face, the overhead map) walks every light.
/// the standard library
const std=@import("std");
/// the Vulkan bindings: the compute pipeline, its layout, barriers
const vk=@import("vulkan");
/// the maths: logarithms for the slices of depth
const m=@import("../core/math.zig");
/// the Vulkan context and its error fold
const ctx=@import("../gfx/ctx.zig");
/// the device context the pass is made on
const Ctx=ctx.Ctx;
/// tiles across the screen (lighting.glsl CELLS_X)
pub const x=32;
/// tiles down it (lighting.glsl CELLS_Y)
pub const y=18;
/// slices of depth a tile is cut into (lighting.glsl SLICES)
pub const slices=32;
/// the cells in all: every slice of every tile, and each tile's whole depth
/// (lighting.glsl CELLS)
pub const count=x*y*(slices+1);
/// how deep the nearest slice reaches from the eye (world units): what is
/// nearer is all one slice
pub const nearSlice:f32=1;
/// the shallowest the slices' whole run may be (as a multiple of the
/// nearest slice's reach), so a short view still cuts into slices
const leastRun:f32=4;
/// invocations a group of the compute pass (cells.comp local_size_x)
const group=64;
/// the 32-bit words a cell's list takes for `n` lights: a bit each
pub fn words(n:usize)usize{return (n+31)/32;}
/// the bytes every cell's list takes for `n` lights
pub fn bytes(n:usize)usize{return count*words(n)*4;}
/// how the eye's depth is cut into slices for a view reaching `far`:
/// x the nearest slice's far edge, y slices for each e-fold beyond it
/// (lighting.glsl `sliceOf`)
pub fn slicing(far:f32)m.Vice(f32,4){
  // the run of depth the slices after the nearest share, as e-folds
  const run=@log(@max(far/nearSlice,leastRun));
  return.{nearSlice,m.f(slices-2)/run,0,0};
}
/// which slice a point `w` deep before the eye falls in (as lighting.glsl
/// `sliceOf` finds it), for `s` from `slicing`
pub fn sliceOf(s:m.Vice(f32,4),w:f32)usize{
  if(w<s[0])return 0;
  return @min(1+@as(usize,@intFromFloat(@log(w/s[0])*s[1])),slices-1);
}
/// the compute pass filling the cells' lists, and its layout (its push:
/// the lighting record's address)
pub const Pass=struct{
  /// the layout: one push of the record's address, no sets
  layout:vk.PipelineLayout=.null_handle,
  /// the compute pipeline (cells.comp)
  pipe:vk.Pipeline=.null_handle,
  /// make the pass; anything half made is freed again on failure
  pub fn init(c:*const Ctx)ctx.Error!Pass{
    // the pass being made
    var p:Pass=.{};
    p.create(c)catch|e|{
      p.deinit(c);
      return ctx.fold(e);
    };
    return p;
  }
  /// the steps of `init`: the layout, then the pipeline
  fn create(p:*Pass,c:*const Ctx)!void{
    // the push: the record's address, two words
    const range=[_]vk.PushConstantRange{.{.stage_flags=.{.compute=true},.offset=0,.size=8}};
    p.layout=try c.device.createPipelineLayout(&.{.set_layout_count=0,.p_set_layouts=null,.push_constant_range_count=range.len,.p_push_constant_ranges=&range},null);
    // the shader, freed once the pipeline holds it
    const mod=try c.shader(@embedFile("cells.comp"));
    defer c.device.destroyShaderModule(mod,null);
    // the pipeline's one stage
    const info=[_]vk.ComputePipelineCreateInfo{.{
      .stage=.{.stage=.{.compute=true},.module=mod,.p_name="main"},
      .layout=p.layout,
      .base_pipeline_index=-1,
    }};
    _=try c.device.createComputePipelines(.null_handle,&info,null,@ptrCast(&p.pipe));
  }
  /// free the pipeline and its layout and leave it empty
  pub fn deinit(p:*Pass,c:*const Ctx)void{
    c.device.destroyPipeline(p.pipe,null);
    c.device.destroyPipelineLayout(p.layout,null);
    p.*=.{};
  }
  /// fill the cells' lists for the `n` lights of the record at `record`,
  /// and hand them to the world's shaders (nothing to do for none)
  pub fn fill(p:*const Pass,cmd:vk.CommandBufferProxy,record:u64,n:usize)void{
    if(n==0)return;
    // the record's address as two words, for the push
    const at=[2]u32{@truncate(record),@truncate(record>>32)};
    cmd.bindPipeline(.compute,p.pipe);
    cmd.pushConstants(p.layout,.{.compute=true},0,8,&at);
    // one invocation a word of a cell's list
    const all=count*words(n);
    cmd.dispatch(@intCast((all+group-1)/group),1,1);
    // the lists written before any shader reads them
    const b=[_]vk.MemoryBarrier2{.{
      .src_stage_mask=.{.compute_shader=true},.src_access_mask=.{.shader_storage_write=true},
      .dst_stage_mask=.{.vertex_shader=true,.fragment_shader=true,.compute_shader=true},.dst_access_mask=.{.shader_storage_read=true},
    }};
    cmd.pipelineBarrier2(&.{.memory_barrier_count=b.len,.p_memory_barriers=&b});
  }
};
/// the test helpers
const testing=std.testing;
test"each slice of depth begins where the last ends, the nearest at the eye, the last running on"{
  // a view reaching 120 units
  const s=slicing(120);
  try testing.expectEqual(@as(usize,0),sliceOf(s,0));
  try testing.expectEqual(@as(usize,0),sliceOf(s,nearSlice*0.99));
  try testing.expectEqual(@as(usize,1),sliceOf(s,nearSlice*1.01));
  // the last slice begins at the far edge of the view and runs on beyond it
  try testing.expectEqual(@as(usize,slices-2),sliceOf(s,119.9));
  try testing.expectEqual(@as(usize,slices-1),sliceOf(s,120.1));
  try testing.expectEqual(@as(usize,slices-1),sliceOf(s,1e6));
  // slices only deepen with depth, one step at a time
  var was:usize=0;
  var w:f32=0;
  while(w<200):(w+=0.05){
    const now=sliceOf(s,w);
    try testing.expect(now==was or now==was+1);
    was=now;
  }
  try testing.expectEqual(@as(usize,slices-1),was);
  // a short view still cuts into slices
  try testing.expect(slicing(0.5)[1]>0);
}
test"a cell's list holds a bit for every light, however many"{
  try testing.expectEqual(@as(usize,0),words(0));
  try testing.expectEqual(@as(usize,1),words(1));
  try testing.expectEqual(@as(usize,1),words(32));
  try testing.expectEqual(@as(usize,2),words(33));
  try testing.expectEqual(@as(usize,count*4*125),bytes(4000));
}
