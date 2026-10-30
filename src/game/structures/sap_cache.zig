//! SAP CACHE: plain storage. Takes anything, gives anything. What goes in
//! drops in through the lid at its mouth, which opens for it, and hangs in
//! the resin; what comes out rises out the same way.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const items=lib.items;
const st=lib.structures;
const iconKit=lib.icon;
const txt=lib.txt;
const prog=lib.progression;
const style=lib.style;
const Draw=lib.engine.ui.draw.Draw;
const Color=lib.engine.ui.draw.Color;
const m=lib.engine.core.math;
const color=lib.engine.core.color;
const Parts=lib.parts.Parts;
const Look=lib.parts.Look;
const growth=lib.growth;
const pod=lib.sapCache;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.bellyLump,.itemPod,.sapCacheLid};
pub const def:st.Def=.{.item=.sapCache,.size=1,.mesh=.sapCache,.store=true,.sap=0.3,.sway=0.5,.tall=0.9,.grow=4};
/// effectively unlimited: conduits and diggers will always hand off to a cache
const wantsMax:u32=1<<16;
/// what hangs inside: a ring of `RING` of the gourd's radius, turning
/// slowly, stacked upward from just under its heart, each shape bobbing;
/// a stack of `SHAPE_FULL` hangs largest
const turnRate:f32=0.15;
const ringRadius:f32=0.45;
const liftAmount:f32=-0.05;
const stack:f32=0.12;
const bobAmount:f32=0.015;
const bobRate:f32=0.7;
const shapeR:f32=0.055;
const shapeGrow:f32=0.04;
const shapeFull:f32=20;
const glow:f32=0.2;
/// something going in or coming out takes this long (s) through the mouth;
/// another starts only once one is this far along
const pass:f32=0.9;
const again:f32=0.6;
/// going in, it is dropped in from this far over the mouth, is through it
/// by `THROUGH` of its way and sinks to its stack, which swells a little
/// as it takes it in; coming out, it is out of the mouth at `THROUGH_OUT`
/// and lifts away this far
const drop:f32=0.16;
const throughAt:f32=0.3;
const throughOut:f32=0.6;
const liftOut:f32=0.2;
const mote:f32=0.32;
const moteGlow:f32=0.6;
const gulp:f32=0.3;
/// the lid's sepals stand round the mouth this far out and open this far
/// (radians) as something passes
const lidRing:f32=0.022;
const lidOpen:f32=1.15;
pub const State=struct{
  /// what each slot held at the last tick
  seen:[st.slots]?items.Stack=@splat(null),
  /// the last thing gone in (how far along, 0..1, 1 done; what; into which
  /// slot) and the last come out
  inT:f32=1,
  inItem:items.Item=.essence,
  inSlot:u8=0,
  outT:f32=1,
  outItem:items.Item=.essence,
};
pub fn wants(_:*const st.Structure,_:*const prog.Progression,_:items.Item)u32{return wantsMax;}
/// newest stack first.
pub fn output(s:*const st.Structure)?items.Item{
  var k:usize=st.slots;
  while(k>0){
    k-=1;
    if(s.inv.slot[k])|it|return it.item;
  }
  return null;
}
/// anything it holds.
pub fn gives(s:*const st.Structure,item:items.Item)bool{return s.inv.count(item)>0;}
/// it does no work; it only watches what goes in and comes out, so its
/// mouth opens for each.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  const self=ctx.ss.get(i);
  const c=&self.state.sapCache;
  c.inT=@min(1,c.inT+dt/pass);
  c.outT=@min(1,c.outT+dt/pass);
  for(self.inv.slot,&c.seen,0..)|slot,*seen,k|{
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
/// how far open its lid stands while something is `t` (0..1) through the
/// mouth, opening ahead of it and closing behind it
fn opening(t:f32,through:f32)f32{
  return m.smooth(m.clamp01((t-through+0.3)/0.25))*(1-m.smooth(m.clamp01((t-through-0.1)/0.35)));
}
/// what it holds hangs in its resin, one dark shape per stack (larger for
/// a larger stack), turning slowly round the gourd's heart; what goes in
/// drops in through the lid, which opens for it, and sinks to its stack,
/// what comes out rises out of it. All of it sways with the gourd.
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  const c=&s.state.sapCache;
  const base=s.place(ctr);
  const formed=growth.formed(pod.form,s.grown);
  const sway:Look=.{.phase=s.seed,.sway=def.sway,.tall=def.tall,.glow=glow};
  const n=s.inv.used();
  var k:usize=0;
  var target=pod.podAt;
  for(s.inv.slot,0..)|slot,si|{
    const it=slot orelse continue;
    const a=m.ratio(k,n)*m.tau+tf*turnRate+s.seed*6;
    const ring=if(n==1)0 else pod.podR[0]*ringRadius;
    const y=pod.podAt[1]+liftAmount+stack*m.ratio(k,@max(n,2)-1)+bobAmount*@sin(tf*bobRate+m.f(k)*2);
    const at=m.v3(@cos(a)*ring,y,@sin(a)*ring);
    var r=shapeR+shapeGrow*m.clamp01(m.f(it.n)/shapeFull);
    if(si==c.inSlot and c.inT<1){
      target=at;
      r*=1+gulp*@sin(m.pi*m.clamp01((c.inT-0.75)/0.25));
    }
    var look=sway;
    look.tint=color.Rgba8.of(it.item.info().col).toF4();
    look.drop=at[1];
    try out.emit(.bellyLump,m.mul(base,m.chain(&.{m.translate(at),m.scale3(m.splat3(r*formed))})),look);
    k+=1;
  }
  if(s.grown<1)return;
  // going in: dropped in through the mouth, then sinking to its stack
  if(c.inT<1){
    const t=c.inT;
    const above=pod.mouth+m.v3(0,drop,0);
    const p=if(t<throughAt)
      m.lerpV(above,pod.mouth,m.smooth(t/throughAt))
    else
      m.lerpV(pod.mouth,target,m.smooth((t-throughAt)/(1-throughAt)));
    var look=sway;
    look.glow=moteGlow;
    look.tint=color.Rgba8.of(c.inItem.info().col).toF4();
    look.drop=p[1];
    const size=mote*(1-m.smooth(m.clamp01((t-0.8)/0.2)));
    try out.emit(.itemPod,m.mul(base,m.chain(&.{m.translate(p),m.scale3(m.splat3(size))})),look);
  }
  // coming out: up from the gourd's heart, out through the mouth, away
  if(c.outT<1){
    const t=c.outT;
    const p=if(t<throughOut)
      m.lerpV(pod.podAt,pod.mouth,m.smooth(t/throughOut))
    else
      pod.mouth+m.v3(0,liftOut*m.smooth((t-throughOut)/(1-throughOut)),0);
    var look=sway;
    look.glow=moteGlow;
    look.tint=color.Rgba8.of(c.outItem.info().col).toF4();
    look.drop=p[1];
    const size=mote*m.smooth(m.clamp01(t/0.2))*(1-m.smooth(m.clamp01((t-0.75)/0.25)));
    try out.emit(.itemPod,m.mul(base,m.chain(&.{m.translate(p),m.scale3(m.splat3(size))})),look);
  }
  // the lid: its sepals turned open about their bases while anything passes
  const open=lidOpen*@max(if(c.inT<1)opening(c.inT,throughAt)else 0,if(c.outT<1)opening(c.outT,throughOut)else 0);
  for(0..pod.lidSepals)|j|{
    const a=m.ratio(j,pod.lidSepals)*m.tau+0.2;
    var look=sway;
    look.drop=pod.mouth[1];
    look.grown=s.grown;
    try out.emit(.sapCacheLid,m.mul(base,m.chain(&.{m.translate(pod.mouth),m.rotY(a),m.translate(m.v3(lidRing,0,0)),m.rotZ(-open)})),look);
  }
}
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
const iconSap:Color=.{255,190,90,255};
const iconGlow:Color=.{255,190,90,90};
