//! the sign a powered structure wears (docs/radiant-plants.md): while it
//! is lit, a halo crown of radiant fragments gathers over it and comes
//! apart in the dark, and its leaves turn the ley lines' blue from its top
//! downward, the further the brighter its light, so its power reads at a
//! glance. Both follow its shine (`Structure.shine`, its light smoothed):
//! the crown is gathered on the GPU (part.vert, by the instance's `k.y`),
//! the blue laid on there too, over every part it emits while its light is
//! set on the parts list (`Parts.ley`). Each crowned kind names how high
//! its crown hangs (`Def.crown`) and what turns blue (`Def.ley`); each
//! structure is given one of the set designs by its seed when put down.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: vectors, matrices, ramps
const m=lib.engine.core.math;
/// the structures registry: `Structure`, its def and its light
const st=lib.structures;
/// the scene's list of moving parts the crown joins
const Parts=lib.parts.Parts;
/// a structure's light as its parts carry it to the GPU
const Ley=lib.parts.Ley;
/// a placed structure
const Structure=st.Structure;
/// the test expectations
const testing=std.testing;
/// the set designs a crown may be, one each (meshes/light_crown.zig)
pub const Design=enum(u8){
  /// a circlet of tall pearl petals standing on a ring of light
  diadem,
  /// starglass points round a ring of light, motes over them
  circlet,
  /// a cut heart in two crossed rings of light, beads riding them
  orrery,
  /// a little celestial bloom hanging over it
  lotus,
};
/// every crown's library mesh, in `Design`'s order: what a crowned kind
/// draws besides its own (`structures.meshes`)
pub const meshes=.{.lightCrownDiadem,.lightCrownCirclet,.lightCrownOrrery,.lightCrownLotus};
/// how many designs there are
const designs=@typeInfo(Design).@"enum".fields.len;
/// a seed's design is picked by where this many times it falls between
/// whole numbers: seeds near one another wear different crowns
const spread:f32=7.31;
/// below this shine nothing of the crown is drawn (all of it is out of sight)
const dark:f32=0.004;
/// how wide a crown is over one tile of footprint (its ring's radius, m)
const widthPer:f32=0.24;
/// how brightly a crown's fragments hold light in whole light
const glow:f32=0.75;
/// the light a crown sheds round it in whole light (linear: pearl, a breath
/// of the ley's blue), and how far it reaches per tile of footprint
const shed=m.V3{0.5,0.52,0.7};
/// (how far)
const shedReach:f32=2.4;
/// the design a structure of seed `seed` wears: one of the few, as at
/// random, the same every time
pub fn designOf(seed:f32)Design{
  // where the seed falls among the designs
  const k=@mod(seed*spread,1)*designs;
  return@enumFromInt(@min(designs-1,m.floorTo(u8,k)));
}
/// a seed that wears design `d` (`--crown=`, to see each)
pub fn seedOf(d:Design)f32{return(m.f(@intFromEnum(d))+0.5)/designs/spread;}
/// the light structure `s` standing at `ctr` lays on what it draws (its
/// ley-blue and its crown's gathering), if it shows any
pub fn ley(s:*const Structure,ctr:m.V3)?Ley{
  // its kind
  const d=s.def();
  if(d.ley==.none and d.crown<=0)return null;
  if(s.shine<dark)return null;
  // how tall it stands
  const tall=d.tall*s.size();
  return.{.amount=s.shine,.top=ctr[1]+tall,.span=tall,.fronds=d.ley==.fronds};
}
/// its halo crown over it, gathered as far as its shine, and the light it
/// sheds round it (while `Parts.ley` carries its shine to the GPU)
pub fn wear(s:*const Structure,out:*Parts,ctr:m.V3)Allocator.Error!void{
  // its kind, and how far it is gathered
  const d=s.def();
  if(d.crown<=0 or s.shine<dark)return;
  // how large research has grown it, how wide its crown, and where it hangs
  const size=s.size();
  const width=widthPer*m.f(d.size)*size;
  const at=ctr+m.v3(0,d.crown*size,0);
  // the crown's mesh, by its design
  const id:lib.meshlib.Id=switch(designOf(s.seed)){
    inline else=>|k|meshes[@intFromEnum(k)],
  };
  try out.emit(id,m.chain(&.{m.translate(at),m.scale3(m.splat3(width))}),.{.glow=glow*s.shine,.phase=s.seed});
  try out.light(at,shed*m.splat3(m.smooth(m.clamp01(s.shine/0.3))*s.shine),shedReach*m.f(d.size));
}
test"a seed's crown is one of the designs, and every design has a seed"{
  for(0..100)|i|_=designOf(m.ratio(i,100));
  inline for(@typeInfo(Design).@"enum".fields)|f|try testing.expectEqual(@field(Design,f.name),designOf(seedOf(@field(Design,f.name))));
}
