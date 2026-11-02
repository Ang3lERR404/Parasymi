//! what every constellate part put down shares (act 2): a petal, leaf, bud
//! or stem the star hyena builds of fragments is a structure of its own,
//! a web holding its shape that floats over its tile, bobbing and turned
//! its own way, until a combo takes it in (a petal drifting to a core, its
//! own file says how). Not a kind: the parts' kinds draw through it.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the drawing calls may fail with
const Allocator=std.mem.Allocator;
/// all the maths: vectors, turns
const m=lib.engine.core.math;
/// the structures registry: `Structure`
const st=lib.structures;
/// the library meshes a part is drawn with
const meshlib=lib.meshlib;
/// the scene's list of moving parts it draws itself into
const Parts=lib.parts.Parts;
/// the HUD's shared sizes and colours
const style=lib.style;
/// every player-facing string
const txt=lib.txt;
/// the UI's draw batch, which the hover text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// how far a part bobs as it floats (m)
pub const bob:f32=0.04;
/// how fast it bobs (rad/s)
pub const bobRate:f32=0.9;
/// where a part floats this frame: over its tile, bobbing its own way
pub fn floatAt(s:*const st.Structure,ctr:m.V3,tf:f32)m.V3{
  return ctr+m.v3(0,bob*@sin(tf*bobRate+s.seed*9),0);
}
/// draw part `s` (its web `mesh`) floating over its tile, turned its own way
pub fn float(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32,mesh:meshlib.Id)Allocator.Error!void{
  try out.emit(mesh,m.chain(&.{m.translate(floatAt(s,ctr,tf)),m.rotY(s.seed*m.tau)}),.{.phase=s.seed});
}
/// a part's line in the panel while nothing has taken it in
pub fn describe(d:*Draw,x:f32,y:f32)Allocator.Error!void{
  _=try d.print(x,y,style.textBody,style.white,txt.s.describe.partFloats,.{});
}
/// a part bulb's glow: deep blue, soft
pub const iconGlow:Color=.{60,110,255,80};
/// a part bulb's light: pale sea-glass blue
pub const iconLight:Color=.{150,210,255,220};
/// how long a part takes to drift over to what takes it in (s)
pub const drifting:f32=6;
/// how far off what takes a part in may stand for it to drift over
/// (tiles, between them)
pub const reach:i32=4;
/// a part drifting over to a stem's joint: the stem (none: it waits),
/// where that stem stands, how far over it has come, and which joint
pub const Drift=struct{
  /// the stem it drifts to
  to:?st.Ref=null,
  /// where that stem stands (its middle on the ground)
  toAt:m.V3=@splat(0),
  /// how far over it has come (0 here .. 1 fastened)
  k:f32=0,
  /// the joint it fastens at (0 lowest, 1 middle, 2 highest)
  joint:u8=0,
};
/// how far over a part has come after `dt` s more, having come `k`
pub fn advance(k:f32,dt:f32)f32{return @min(k+dt/drifting,1);}
/// how much higher than where a part floats alone each joint of a stem
/// takes it, its foot on the joint (part.vert `PLEXUS_STEM`: rings 3, 6, 9)
pub const jointLift=[3]f32{0.35,0.8,1.15};
/// how far to the side of a stem's middle each joint holds what fastens
/// there, toward where it comes from
const jointSide:f32=0.06;
/// one tick of part `i` (its drift `d`) fastening as `what` over `dt` s:
/// drifting, it comes over and fastens (gone from here at the end of the
/// tick), its stem gone or full by then waiting again; waiting, it asks
/// the stems within `reach` (only those put down before it, for a branch,
/// so two stems never drift to each other) and drifts to the first with a
/// joint free. Busy while it drifts.
pub fn fasten(ctx:st.Ctx,i:st.Id,d:*Drift,what:st.Fasten,dt:f32)bool{
  if(d.to)|to|{
    // its stem, gone: it waits again
    const j=ctx.ss.where.get(to) orelse {
      d.*=.{};
      return false;
    };
    d.k=advance(d.k,dt);
    if(d.k<1)return true;
    // over: it fastens, or, the stem full by now, waits again
    switch(ctx.ss.send(ctx,j,.{.fastened=what})){
      .joint=>ctx.ss.get(i).fade=1,
      .ignored,.done,.took=>d.*=.{},
    }
    return false;
  }
  // where it stands
  const self=ctx.ss.get(i);
  const here=m.Vice(i32,2){self.x,self.y};
  for(ctx.ss.list.items,0..)|*o,k|{
    if(o.kind()!=.stem or k==i.idx())continue;
    if(what==.branch and k>i.idx())continue;
    if(@max(@abs(o.x-here[0]),@abs(o.y-here[1]))>reach)continue;
    switch(ctx.ss.send(ctx,.of(k),.{.fastenComing=what})){
      .joint=>|jt|{
        // (the stem named afresh: the reply moves nothing, all the same)
        const host=ctx.ss.get(.of(k));
        d.*=.{.to=host.ref(),.toAt=host.at,.joint=jt};
        return true;
      },
      .ignored,.done,.took=>{},
    }
  }
  return false;
}
/// draw part `s` (its web `mesh`) drifting over to its stem's joint by `d`:
/// rising to the joint's height on the side it comes from, turning to lean
/// out from the stem, fading into it as it fastens
pub fn driftTo(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32,mesh:meshlib.Id,d:Drift)Allocator.Error!void{
  // how far over it is, eased, and where it is bound for
  const e=m.smooth(d.k);
  const away=m.v3(ctr[0]-d.toAt[0],0,ctr[2]-d.toAt[2]);
  const side=if(m.len(away)>1e-3)m.norm(away)else m.v3(1,0,0);
  const there=m.v3(d.toAt[0]+side[0]*jointSide,ctr[1]+jointLift[d.joint],d.toAt[2]+side[2]*jointSide);
  const at=m.lerpV(floatAt(s,ctr,tf),there,e);
  const face=m.lerp(s.seed*m.tau,m.atan2(side[0],side[2]),e);
  try out.emit(mesh,m.chain(&.{m.translate(at),m.rotY(face)}),.{.phase=s.seed,.fade=1-0.6*e*e});
}
