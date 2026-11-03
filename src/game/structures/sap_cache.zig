//! SAP CACHE: plain storage. Takes anything, gives anything. What goes in
//! drops in through the lid at its mouth, which opens for it, and hangs in
//! the resin; what comes out rises out the same way.
const lib=@import("../../lib.zig");
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
/// the HUD's shared sizes and colours
const style=lib.style;
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// all the maths: vectors, matrices, easing
const m=lib.engine.core.math;
/// colour conversions, for tinting a part by its item's colour
const color=lib.engine.core.color;
/// the scene's list of moving parts this cache adds to each frame
const Parts=lib.parts.Parts;
/// how one part looks: its glow, tint, sway and growth
const Look=lib.parts.Look;
/// the garden's growth timing: how far a grown form has formed
const growth=lib.growth;
/// the cache's mesh: where its gourd, heart and mouth are
const pod=lib.sapCache;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.bellyLump,.itemPod,.sapCacheLid};
/// what a cache is: grown from its seed, one tile across, a store that
/// swaps sap, swaying gently and standing a little under a tile tall
pub const def:st.Def=.{.item=.sapCache,.lineage=.symbiotic,.size=1,.mesh=.sapCache,.store=true,.sap=0.3,.sway=0.5,.tall=0.9,.grow=4,.light=.looks};
/// how much it will take of anything: effectively without end, so conduits
/// and diggers can always hand off to a cache
const wantsMax:u32=1<<16;
/// how fast the ring of held shapes turns round the gourd's heart (turns a second)
const turnRate:f32=0.15;
/// how far out the shapes hang, as a share of the gourd's radius
const ringRadius:f32=0.45;
/// how far under the heart the lowest shape hangs
const liftAmount:f32=-0.05;
/// how much higher the topmost shape hangs than the lowest
const stack:f32=0.12;
/// how far each shape bobs up and down
const bobAmount:f32=0.015;
/// how fast each shape bobs (radians a second)
const bobRate:f32=0.7;
/// the size of a shape holding a single thing
const shapeR:f32=0.055;
/// how much larger a shape grows as its stack fills
const shapeGrow:f32=0.04;
/// the stack size at which a shape hangs at its largest
const shapeFull:f32=20;
/// how brightly the held shapes glow in the resin
const glow:f32=0.2;
/// how long (s) one thing takes to pass through the mouth, in or out
const pass:f32=0.9;
/// how far along one passing thing must be before the next may start
const again:f32=0.6;
/// how high above the mouth something going in is dropped from
const drop:f32=0.16;
/// how far along its way something going in has passed the mouth
const throughAt:f32=0.3;
/// how far along its way something coming out has passed the mouth
const throughOut:f32=0.6;
/// how far above the mouth something coming out lifts away
const liftOut:f32=0.2;
/// the size of the mote that travels in or out
const mote:f32=0.32;
/// how brightly that travelling mote glows
const moteGlow:f32=0.6;
/// how much a stack swells as it swallows what came in
const gulp:f32=0.3;
/// how far out from the mouth the lid's sepals stand
const lidRing:f32=0.022;
/// how far (radians) the sepals swing open while something passes
const lidOpen:f32=1.15;
/// what a cache remembers between ticks: the slots it last saw, and the
/// one thing travelling in and the one travelling out
pub const State=struct{
  /// what each slot held at the last tick, to see what changed
  seen:[st.slots]?items.Stack=@splat(null),
  /// how far the last thing going in has travelled, 0..1 (1: arrived)
  inT:f32=1,
  /// what that thing going in is
  inItem:items.Item=.essence,
  /// the slot it is sinking into
  inSlot:u8=0,
  /// how far the last thing coming out has travelled, 0..1 (1: gone)
  outT:f32=1,
  /// what that thing coming out is
  outItem:items.Item=.essence,
};
/// it wants anything, as much as is brought.
pub fn wants(_:*const st.Structure,_:*const prog.Progression,_:items.Item)u32{return wantsMax;}
/// what it gives first: the newest stack, from the last slot back.
pub fn output(s:*const st.Structure)?items.Item{
  // the slot being looked at, walking back from the last
  var k:usize=st.slots;
  while(k>0){
    k-=1;
    if(s.inv.slot[k])|it|return it.item;
  }
  return null;
}
/// it gives anything it holds.
pub fn gives(s:*const st.Structure,item:items.Item)bool{return s.inv.count(item)>0;}
/// it does no work; it only watches what goes in and comes out, so its
/// mouth opens for each. Returns false: nothing about it needs redrawing.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // the cache itself, and its remembered state
  const self=ctx.ss.get(i);
  const c=&self.state.sapCache;
  c.inT=@min(1,c.inT+dt/pass);
  c.outT=@min(1,c.outT+dt/pass);
  for(self.inv.slot,&c.seen,0..)|slot,*seen,k|{
    // how many the slot holds now, and how many it held last tick
    const n:u16=if(slot)|it|it.n else 0;
    const was:u16=if(seen.*)|it|it.n else 0;
    if(n>was and c.inT>=again){
      c.inT=0;
      c.inItem=slot.?.item;
      c.inSlot=@intCast(k);
    }
    if(n<was and c.outT>=again){
      c.outT=0;
      c.outItem=seen.*.?.item;
    }
    seen.*=slot;
  }
  return false;
}
/// how far open its lid stands (0..1) while something is `t` (0..1) of the
/// way through, opening just ahead of it and closing behind it; `through`
/// is the point of its way where it passes the mouth.
fn opening(t:f32,through:f32)f32{
  return m.smooth(m.clamp01((t-through+0.3)/0.25))*(1-m.smooth(m.clamp01((t-through-0.1)/0.35)));
}
/// what it holds hangs in its resin, one dark shape per stack (larger for
/// a larger stack), turning slowly round the gourd's heart; what goes in
/// drops in through the lid, which opens for it, and sinks to its stack,
/// what comes out rises out of it. All of it sways with the gourd.
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // its state, its frame in the world, and how far its gourd has formed
  const c=&s.state.sapCache;
  const base=s.place(ctr);
  const formed=growth.formed(pod.form,s.grown);
  // the look every part of it shares: swaying with the gourd
  const sway:Look=.{.phase=s.seed,.sway=def.sway,.tall=def.tall,.glow=glow};
  // how many stacks it holds, and which of them is being drawn
  const n=s.inv.used();
  var k:usize=0;
  // where something going in sinks to: the heart, or its stack once found
  var target=pod.podAt;
  for(s.inv.slot,0..)|slot,si|{
    const it=slot orelse continue;
    // the stack's place on the ring: its angle, the ring's reach, its height
    const a=m.ratio(k,n)*m.tau+tf*turnRate+s.seed*6;
    const ring=if(n==1)0 else pod.podR[0]*ringRadius;
    const y=pod.podAt[1]+liftAmount+stack*m.ratio(k,@max(n,2)-1)+bobAmount*@sin(tf*bobRate+m.f(k)*2);
    const at=m.v3(@cos(a)*ring,y,@sin(a)*ring);
    // its size: larger the fuller it is, swelling as it swallows
    var r=shapeR+shapeGrow*m.clamp01(m.f(it.n)/shapeFull);
    if(si==c.inSlot and c.inT<1){
      target=at;
      r*=1+gulp*@sin(m.pi*m.unlerp(0.75,1,c.inT));
    }
    try s.emitLump(out,base,at,r*formed,it.item,glow);
    k+=1;
  }
  if(s.grown<1)return;
  // going in: dropped in through the mouth, then sinking to its stack
  if(c.inT<1){
    // how far along it is, where it started, and where it is now
    const t=c.inT;
    const above=pod.mouth+m.v3(0,drop,0);
    const p=if(t<throughAt)
      m.lerpV(above,pod.mouth,m.smooth(t/throughAt))
    else
      m.lerpV(pod.mouth,target,m.smooth((t-throughAt)/(1-throughAt)));
    // the mote's look: brighter, its item's colour
    var look=sway;
    look.glow=moteGlow;
    look.tint=color.Rgba8.of(c.inItem.info().col).toF4();
    look.drop=p[1];
    // its size, shrinking away as it reaches its stack
    const size=mote*(1-m.smooth(m.unlerp(0.8,1,t)));
    try out.emit(.itemPod,m.mul(base,m.chain(&.{m.translate(p),m.scale3(m.splat3(size))})),look);
  }
  // coming out: up from the gourd's heart, out through the mouth, away
  if(c.outT<1){
    // how far along it is, and where it is now
    const t=c.outT;
    const p=if(t<throughOut)
      m.lerpV(pod.podAt,pod.mouth,m.smooth(t/throughOut))
    else
      pod.mouth+m.v3(0,liftOut*m.smooth((t-throughOut)/(1-throughOut)),0);
    // the mote's look: brighter, its item's colour
    var look=sway;
    look.glow=moteGlow;
    look.tint=color.Rgba8.of(c.outItem.info().col).toF4();
    look.drop=p[1];
    // its size: swelling in at the start, fading out at the end
    const size=mote*m.smooth(m.clamp01(t/0.2))*(1-m.smooth(m.unlerp(0.75,1,t)));
    try out.emit(.itemPod,m.mul(base,m.chain(&.{m.translate(p),m.scale3(m.splat3(size))})),look);
  }
  // the lid: its sepals turned open about their bases while anything passes
  const open=lidOpen*@max(if(c.inT<1)opening(c.inT,throughAt)else 0,if(c.outT<1)opening(c.outT,throughOut)else 0);
  for(0..pod.lidSepals)|j|{
    // this sepal's place round the mouth
    const a=m.ratio(j,pod.lidSepals)*m.tau+0.2;
    // its look: the gourd's sway, grown with it
    var look=sway;
    look.drop=pod.mouth[1];
    look.grown=s.grown;
    try out.emit(.sapCacheLid,m.mul(base,m.chain(&.{m.translate(pod.mouth),m.rotY(a),m.translate(m.v3(lidRing,0,0)),m.rotZ(-open)})),look);
  }
}
/// its line in the panel: plain storage, nothing more to say.
pub fn describe(_:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  _=try d.text(x,y,style.textBody,style.dim,txt.s.describe.cache);
}
/// its bulb: two sprouts curling into a basket round a bead of amber sap
/// (it holds things).
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  try ic.glow(.{0,0.55},0.4,iconGlow);
  try ic.bud(.{0,0.55},0.22,iconSap,0.8);
  for([_]f32{-1,1})|sx|{
    try ic.stem(.{.{0,iconKit.topAt},.{0.55*sx,0.22},.{0.6*sx,0.75},.{0.3*sx,0.9}},0.1,iconKit.stemCol);
    try ic.leaf(.{0.3*sx,0.9},if(sx<0)2.7 else 0.45,0.26,0.16,iconKit.sprout,0.9);
  }
  try ic.coat(col);
}
/// the amber of the sap bead in its bulb
const iconSap:Color=.{255,190,90,255};
/// the soft amber glow behind that bead
const iconGlow:Color=.{255,190,90,90};
