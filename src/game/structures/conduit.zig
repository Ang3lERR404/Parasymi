//! ROOT CONDUIT: the first logistics. One item at a time it pulls from
//! whatever is behind it (a structure's output, or a mature plant, which
//! harvests it) and passes it forward to the next conduit or structure.
//! It also sends a root out to any plant beside it (left, right or behind)
//! and, once that root has reached it, harvests that plant too.
//! Its root digs up out of the soil at the edge it is fed from, arches
//! over its tile and digs back in at its front, so chains join under the
//! ground however they turn; what it carries runs through its core.
const lib=@import("../../lib.zig");
/// all the maths: vectors, matrices, the four ways
const m=lib.engine.core.math;
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// what can be held: item kinds and stacks of them
const items=lib.items;
/// the structures registry: `Def`, `Structure`, the hooks' context
const st=lib.structures;
/// the tools a bulb icon is drawn with
const iconKit=lib.icon;
/// every player-facing string
const txt=lib.txt;
/// what the gardener has understood
const prog=lib.progression;
/// colour conversions, for tinting the carried bead by its item's colour
const color=lib.engine.core.color;
/// the HUD's shared sizes and colours
const style=lib.style;
/// the scene's list of moving parts its arches and roots are added to
const Parts=lib.parts.Parts;
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the mesh library its arches are chosen from
const meshlib=lib.meshlib;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.conduitLeft,.conduitRight,.conduitTap};
/// what a conduit is: grown from its bulb, one tile across, a carrier.
/// decision: a conduit grows (along its arch's growth spline, up out of
/// the soil and back in) but does not sway: its arches join the next conduit's under the ground, and a bend
/// per conduit would pull them apart. It draws its own arches (`emit`),
/// one per edge it is fed from; `mesh` (the straight one) is its preview.
pub const def:st.Def=.{.item=.conduit,.size=1,.mesh=.conduit,.grow=1.5,.carrier=true,.bare=true,.tall=0.25};
/// its arch by the edge it comes in at, counted from the way it faces
/// (1 the side +Z of it in its own frame, 2 behind, 3 the other side)
const archMeshes=[4]?meshlib.Id{null,.conduitLeft,.conduit,.conduitRight};
/// the edge behind it, counted from the way it faces: where it pulls from
const behind:m.Dir=2;
/// essence waiting for room ahead shows here, where the root goes down
const waitAt:f32=0.86;
/// how much its arches flutter in the breeze, though they never sway
const flutterAmount:f32=0.5;
/// tiles per second an item travels along conduits
const speed:f32=2.5;
/// how quickly a root grows out to a plant beside it (fraction per second)
const rootGrow:f32=0.6;
/// how quickly a root withers back once its plant is gone (fraction per second)
const rootWither:f32=1.5;
/// how much a side root flutters
const tapFlutter:f32=0.3;
/// what a conduit remembers: the item running through it, its roots'
/// reach, and which edges it is fed at
pub const State=struct{
  /// the item in transit, if any
  held:?items.Item=null,
  /// how far along its way through the conduit that item is (0..1)
  moveT:f32=0,
  /// how far the root toward each neighbouring tile has grown (0..1),
  /// indexed by world direction; the front one never grows
  reach:[4]f32=.{0,0,0,0},
  /// which side root harvests next, so neighbours take turns
  turn:u8=0,
  /// the edges roots come in at (bit per edge counted from the way it
  /// faces, see `archMeshes`)
  feeds:u8=1<<behind,
  /// the edge the item in transit came in by
  came:m.Dir=behind,
};
/// the one bit standing for edge `r` in `feeds`
fn bit(r:m.Dir)u8{return@as(u8,1)<<r;}
/// which edges its root comes in at: from each conduit facing into it, and
/// from behind when anything else stands there (it pulls from it) or
/// nothing feeds it at all.
pub fn link(ctx:st.Ctx,i:st.Id)void{
  // the conduit, and the edges found feeding it so far
  const self=ctx.ss.get(i);
  var feeds:u8=0;
  for([_]m.Dir{1,2,3})|r|{
    // the world way that edge lies, the step there, and what stands there
    const d=self.dir+%r;
    const v=m.dirVec(d);
    const j=ctx.ss.at(ctx.w,self.x+v.x,self.y+v.z) orelse continue;
    // that neighbour
    const t=ctx.ss.get(j);
    if(t.def().carrier){
      if(t.dir==d+%2)feeds|=bit(r);
    }else if(r==behind)feeds|=bit(r);
  }
  self.state.conduit.feeds=if(feeds==0)bit(behind)else feeds;
}
/// the directions a conduit sends roots: behind, then its two sides.
fn tapDirs(d:m.Dir)[3]m.Dir{return.{d+%2,d+%1,d+%3};}
/// grow roots toward the plants beside a conduit, wither those with none.
fn growRoots(ctx:st.Ctx,self:*st.Structure,dt:f32)void{
  // its remembered state
  const c=&self.state.conduit;
  for(tapDirs(self.dir))|d|{
    // the step that way, whether a plant stands there, and the root reaching toward it
    const v=m.dirVec(d);
    const there=ctx.plants.at(ctx.w,self.x+v.x,self.y+v.z)!=null;
    const r=&c.reach[d];
    r.*=if(there)@min(1,r.*+dt*rootGrow)else@max(0,r.*-dt*rootWither);
  }
  c.reach[self.dir]=0;
}
/// pull one item: from what is behind (a structure, or a plant its root
/// has reached), else from a plant beside it whose root has reached it.
fn pull(ctx:st.Ctx,self:*st.Structure)?items.Item{
  // the structures, its state, the ways it taps and the step behind it
  const ss=ctx.ss;
  const c=&self.state.conduit;
  const taps=tapDirs(self.dir);
  const bv=m.dirVec(taps[0]);
  if(ss.at(ctx.w,self.x+bv.x,self.y+bv.z))|j|{
    if(ss.get(j).def().carrier)return null; // carriers push, they are never pulled
    // what that structure lets go first (nothing: nothing pulled)
    const item=ss.output(j) orelse return null;
    _=ss.get(j).inv.take(item,1);
    c.came=behind;
    return item;
  }
  for(0..taps.len)|k|{
    // the way taken in turn, the step there, and the plant standing there
    const d=taps[(c.turn+k)%taps.len];
    if(c.reach[d]<1)continue;
    const v=m.dirVec(d);
    const p=ctx.plants.at(ctx.w,self.x+v.x,self.y+v.z) orelse continue;
    if(st.harvestOne(ctx.plants,p))|item|{
      c.turn=@intCast((c.turn+k+1)%taps.len);
      c.came=d-%self.dir;
      return item;
    }
  }
  return null;
}
/// grows its roots, then, empty, pulls one thing in; carrying, moves it
/// along and, at the front, hands it on. Returns whether it is busy.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // the structures, this conduit, and the step forward
  const ss=ctx.ss;
  const self=ss.get(i);
  const v=m.dirVec(self.dir);
  growRoots(ctx,self,dt);
  if(self.state.conduit.held==null){
    self.state.conduit.moveT=0;
    // what it pulled in, if anything
    const got=pull(ctx,self);
    self.state.conduit.held=got;
    return got!=null;
  }
  // its remembered state
  const c=&self.state.conduit;
  c.moveT=@min(1,c.moveT+dt*speed);
  if(c.moveT<1)return true;
  // what it carries, and the tile ahead
  const item=c.held.?;
  const fx=self.x+v.x;
  const fz=self.y+v.z;
  const j=ss.at(ctx.w,fx,fz) orelse return false;
  // what stands ahead
  const t=ss.get(j);
  if(t.def().carrier){
    // the way that carrier faces
    const back=m.dirVec(t.dir);
    // never hand back into a carrier facing us
    if(back.x==-v.x and back.z==-v.z)return false;
  }
  // (it comes in at the edge facing this one)
  if(!ss.handIn(ctx.g,j,item,(self.dir+%2)-%t.dir))return!t.def().carrier;
  self.state.conduit.held=null;
  return true;
}
/// take an item handed in at `edge` (counted from the way it faces) into
/// its core, if nothing runs through it.
pub fn receive(s:*st.Structure,_:*const prog.Progression,item:items.Item,edge:m.Dir)bool{
  // its remembered state
  const c=&s.state.conduit;
  if(c.held!=null)return false;
  c.held=item;
  c.moveT=0;
  c.came=edge;
  return true;
}
/// hand back the item running through it, if any, leaving it empty
pub fn release(s:*st.Structure)?items.Item{
  // what it held
  const h=s.state.conduit.held;
  s.state.conduit.held=null;
  return h;
}
/// its arches, one up out of the soil from each edge it is fed at, the
/// item in transit running through the core of the one it came in by; and
/// the roots it has sent out to plants beside it. Each grows along its
/// growth spline: an arch with the conduit, a side root as it reaches.
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,_:f32)Allocator.Error!void{
  // its state, and its frame: at its centre, turned its way
  const c=&s.state.conduit;
  const place=m.chain(&.{m.translate(ctr),m.rotY(m.dirYaw(s.dir))});
  // the arch the item runs through: the one it came in by
  // (essence pulled from a plant beside it, with no arch there, runs
  // through the first)
  const by=if(c.feeds&bit(c.came)!=0)c.came else@as(m.Dir,@intCast(@ctz(c.feeds)));
  // how far along the item is (waiting at the front once there), and its colour
  const along=if(c.moveT>=1)waitAt else c.moveT;
  const col=if(c.held)|it|color.Rgba8.of(it.info().col).toF4()else[4]f32{0,0,0,0};
  for(archMeshes,0..)|id,r|{
    if(c.feeds&bit(@intCast(r))==0)continue;
    // how far along this arch the item runs (-1: it runs in another)
    const carry=if(c.held!=null and r==by)along else-1;
    try out.emit(id.?,place,.{.glow=s.activity,.flutter=flutterAmount,.phase=s.seed,.grown=s.grown,.carry=carry,.carryCol=.{col[0],col[1],col[2]}});
  }
  for(c.reach,0..)|r,d|{
    if(r<=0)continue;
    // a root grows out from the conduit along its spline as it reaches,
    // thickening once there (and withers back down it)
    try out.emit(.conduitTap,m.chain(&.{m.translate(ctr),m.rotY(m.dirYaw(@intCast(d)))}),.{.flutter=tapFlutter,.phase=s.seed,.grown=r*s.grown});
  }
}
/// its line in the panel: what it carries now, or nothing
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  _=try d.print(x,y,style.textBody,style.white,txt.s.describe.carries,.{if(s.state.conduit.held)|it|txt.item(it).name else txt.s.describe.nothing});
}
/// its bulb: a root arching out of the seed and diving back in beside it,
/// a bead of essence running along it (it carries things one way).
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // the arch's curve: out of the seed, over and down beside it
  const arch=[4]iconKit.P{.{0,iconKit.topAt},.{-0.15,0.62},.{0.78,0.9},.{0.7,0.02}};
  try ic.stem(arch,0.13,iconKit.rootCol);
  try ic.leaf(.{-0.04,0.32},2.5,0.32,0.18,iconKit.sprout,0.9);
  // how far along the arch the bead has run (0..1)
  const k=@mod(ic.t*iconRun+ic.phase,1);
  try ic.bud(iconKit.curve(arch,k),0.09,iconBead,@sin(k*m.pi));
  try ic.coat(col);
}
/// the warm gold of the bead running along its bulb's arch
const iconBead:Color=.{255,215,120,255};
/// beads along the arch a second
const iconRun:f32=0.45;
