//! DIAMOND: where a halo's four blooms became one, floating high over the
//! polyp at its ring's heart; or, once Celestial Defragmentation is known,
//! woven and put down over any dry tile. Small and still, a cut crystal that
//! only catches light. It fragments that light into the halo's ring around
//! it (see `halo.zig`), and holds a field of celestial energy wider than it.
//! Put down by hand, it gathers from its shards as it grows in; grown, or
//! born of a halo, it forms with a flash of light. Blooms sown on the
//! ring's four points brighten the arcs beside them. (The world event will
//! start from it.)
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: vectors, angles, easing
const m=lib.engine.core.math;
/// a field of celestial energy, as the ecology reads it
const Field=lib.ecology.Field;
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
/// the scene's list of moving parts its halo is drawn into
const Parts=lib.parts.Parts;
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the halo it projects and holds: its sizes, timing and drawing
const halo=lib.haloStructure;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.haloFlash,.haloProjection,.haloRing};
/// what a diamond is: one tile, floating as high as the blooms hang, at
/// the heart of its ring, over whatever is under it; it draws itself
/// (`bare`, forming on the GPU) and takes 8 s to gather when put down
pub const def:st.Def=.{.item=.diamond,.size=1,.mesh=.haloDiamond,.floating=true,.hover=halo.hover,.bare=true,.grow=8};
/// what a diamond remembers: how long since it formed, and its arcs' light
pub const State=struct{
  /// seconds since it formed (grown)
  t:f32=0,
  /// per point of its ring: how brightly the arcs beside it shine
  light:[4]f32=@splat(halo.dim),
};
/// counts on from its forming (up to the end of its flash) and lets its
/// arcs brighten or dim with the blooms on its ring's points; never busy
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // the diamond and its remembered state
  const self=ctx.ss.get(i);
  const d=&self.state.diamond;
  d.t=@min(d.t+dt,halo.form+halo.flash);
  halo.relight(&d.light,ctx.plants,ctx.w,self.x,self.y,dt);
  return false;
}
/// `lit`: born whole of a halo, its light still the blooms'
pub fn message(ctx:st.Ctx,i:st.Id,msg:st.Msg)st.Reply{
  switch(msg){
    .lit=>{
      ctx.ss.get(i).state.diamond.light=@splat(1);
      return.done;
    },
    .arrived=>return.ignored,
  }
}
/// its field of celestial energy, `halo.diamondR` round it, once grown
pub fn field(s:*const st.Structure)?Field{
  if(s.grown<1)return null;
  return.{.x=s.x,.y=s.y,.radius=halo.diamondR};
}
/// how far along its halo is: growing in, it gathers as the halo's blooms
/// would bring it together; formed, past 1
fn along(s:*const st.Structure)f32{
  return if(s.grown<1)s.grown else 1+s.state.diamond.t/halo.form;
}
/// draws its halo: the diamond hanging `hover` over its tile, the ring
/// round it, as far formed as it has come
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,_:f32)Allocator.Error!void{
  try halo.draw(out,s.seed,ctr+m.v3(0,def.hover,0),ctr,along(s),s.state.diamond.light);
}
/// its line in the panel: how much of its ring is lit
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  _=try d.print(x,y,style.textBody,style.gold,txt.s.describe.diamond,.{halo.lit(s.state.diamond.light)});
}
/// its bulb: a low sprout, and over it, floating free on a thread of light,
/// the cut diamond: shards spiral in to it, and it splits light into needle
/// rays out to a tilted ring, a spectrum across its width (red inside),
/// motes running round it (it gathers, floats, and projects the halo).
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // how far it bobs now, its heart there, and where the sprout's tip ends
  const bob=iconBob*@sin(ic.t*1.3+ic.phase*6);
  const heart:iconKit.P=.{0,0.52+bob};
  const tip:iconKit.P=.{0,0.24};
  try ic.stem(.{.{0,iconKit.topAt},.{-0.04,0.16},.{0.04,0.24},tip},0.09,iconKit.stemCol);
  try ic.leaf(tip,0.75,0.24,0.14,iconKit.sprout,0.9);
  try ic.leaf(tip,m.pi-0.75,0.22,0.13,iconKit.sprout,0.9);
  try ic.stem(.{tip,.{0.03,0.4},.{-0.03,0.46},.{0,heart[1]-0.1}},0.03,iconThread);
  try ring(ic,heart,true);
  // needle rays of split light running level out to the ring
  for(0..iconRays)|i|{
    // the ray's bearing, where it meets the ring, and how bright it pulses
    const a=ic.t*iconTurn+m.tau*m.ratio(i,iconRays);
    const out=ringAt(heart,a,iconRingR);
    const pulse=0.5+0.5*@sin(ic.t*3+m.f(i)*2.1+ic.phase*5);
    try ic.stem(.{heart,heart,out,out},0.025,fade(iconBand[i%iconBand.len],pulse));
  }
  // shards gathering into it from a spiral, one after another
  for(0..iconShards)|i|{
    // how far in this shard has come (0..1), its bearing on the spiral
    const k=@mod(ic.t*iconGather+ic.phase+m.ratio(i,iconShards),1);
    const a=m.tau*(m.ratio(i,iconShards)+1.25*k);
    // how far out it still is, and where that puts it
    const r=0.5*(1-k)*(1-k);
    const at:iconKit.P=.{heart[0]+r*@cos(a),heart[1]+r*@sin(a)*0.7};
    try ic.gem(at,0.07*(1-0.5*k),fade(iconGem,@sin(k*m.pi)));
  }
  // how brightly its heart flares now
  const flare=0.85+0.15*@sin(ic.t*2.6+ic.phase*3);
  try ic.glow(heart,0.3*flare,iconGlow);
  try ic.gem(heart,0.24,iconGem);
  try ring(ic,heart,false);
  try ic.coat(col);
}
/// the point at bearing `a` on a ring of radius `r` round `c`, tilted away
/// (squashed in y; its far half is the upper one).
fn ringAt(c:iconKit.P,a:f32,r:f32)iconKit.P{
  return.{c[0]+r*@cos(a),c[1]+r*@sin(a)*iconTilt};
}
/// the halo's ring round `c`, its far half (behind the diamond) or near
/// half: a band per colour, red innermost, and motes running round.
fn ring(ic:iconKit.Icon,c:iconKit.P,far:bool)Allocator.Error!void{
  for(iconBand,0..)|band,b|{
    // this band's radius: red innermost
    const r=iconRingR+iconBandW*(m.f(b)-1);
    for(0..iconSegs)|i|{
      // the segment's two bearings
      const a0=m.tau*m.ratio(i,iconSegs);
      const a1=m.tau*m.ratio(i+1,iconSegs);
      if((@sin((a0+a1)/2)>0)!=far)continue;
      // the segment's two ends
      const p=ringAt(c,a0,r);
      const q=ringAt(c,a1,r);
      try ic.stem(.{p,p,q,q},iconBandW,band);
    }
  }
  for(0..iconMotes)|i|{
    // the mote's bearing round the ring
    const a=ic.t*iconRun+m.tau*m.ratio(i,iconMotes)+ic.phase;
    if((@sin(a)>0)!=far)continue;
    try ic.bud(ringAt(c,a,iconRingR),0.035,iconMote,1);
  }
}
/// colour `c` with its alpha scaled by `k` (0..1)
fn fade(c:Color,k:f32)Color{
  return.{c[0],c[1],c[2],m.unorm8(m.ratio(c[3],255)*k)};
}
/// the halo ring's radius in its bulb
const iconRingR:f32=0.42;
/// the width of each colour band of that ring
const iconBandW:f32=0.05;
/// how squashed the ring is, tilted away (1 seen face-on)
const iconTilt:f32=0.5;
/// how many segments each band is drawn in
const iconSegs=24;
/// how many needle rays of split light run to the ring
const iconRays=6;
/// how many shards spiral in at once
const iconShards=3;
/// how many motes run round the ring
const iconMotes=2;
/// how far the floating diamond bobs
const iconBob:f32=0.03;
/// radians a second the rays turn
const iconTurn:f32=0.4;
/// radians a second the motes run round the ring
const iconRun:f32=1.1;
/// shards gathered a second
const iconGather:f32=0.35;
/// the ring's spectrum, inside out
const iconBand=[3]Color{.{255,110,100,190},.{240,230,120,170},.{120,170,255,160}};
/// the near-white of the cut diamond and its shards
const iconGem:Color=.{255,245,235,255};
/// the faint warm glow round its heart
const iconGlow:Color=.{255,240,220,45};
/// the thread of light it floats on
const iconThread:Color=.{255,240,215,140};
/// the bright motes running round the ring
const iconMote:Color=.{255,255,245,255};
