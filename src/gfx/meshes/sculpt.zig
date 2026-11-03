//! mesh: SCULPT. the library's sculpt slots: slot `i` is the `i`th sculpt
//! on the gardener's shelf (sculpts.zig, read at startup, in name order),
//! meshed as one seamless skinned surface (sculpt_doc.zig), its cells
//! twice as wide at each coarser level of detail; empty when the shelf
//! holds fewer. Drawn skinned, its bones turned by its clip.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the mesh builder
const mg=lib.meshgen;
/// the gardener's sculpts
const sculpts=lib.sculpts;
/// sculpt slot `i`: the `i`th sculpt on the shelf, if there is one
pub fn Slot(comptime i:usize)type{
  return struct{
    /// meshes the sculpt into `b` at `b.lod`'s detail (nothing when the
    /// shelf holds no `i`th)
    pub fn build(b:*mg.Builder)Allocator.Error!void{
      if(i>=sculpts.all().len)return;
      // the sculpt as kept, its cells widened for the level of detail
      var doc=sculpts.all()[i].rigged.doc;
      doc.cell*=@floatFromInt(@as(u32,1)<<@intCast(b.lod));
      try doc.mesh(b.gpa,b.io,false,b,sculpts.lookup());
    }
  };
}
