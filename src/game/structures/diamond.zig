//! DIAMOND: where a halo's four blooms became one, floating high at the
//! heart of their cross (four grown blooms `halo.reachTiles` out east,
//! south, west and north of a tile are enough: `halo.seek` finds them and
//! puts it down there, forming, the blooms spiralling in to it); or, once Celestial Defragmentation is known,
//! woven and put down over any dry tile. Small and still, a cut crystal that
//! only catches light. It fragments that light into the halo's ring around
//! it (see `halo.zig`). Grown, it is the light grid's big relay: it links
//! further than a bloom, carries four times what one does, and lights a
//! field twice as wide (sim/light.zig); it makes no light of its own.
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
/// the light grid: the relay it holds
const light=lib.light;
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
/// the species registry, to tell a celestial bloom by its radiance
const species=lib.species;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.haloFlash,.haloProjection,.haloRing};
/// what a diamond is: one tile, floating as high as the blooms hang, at
/// the heart of its ring, over whatever is under it; it draws itself
/// (`bare`, forming on the GPU) and takes 8 s to gather when put down
pub const def:st.Def=.{.item=.diamond,.lineage=.radiant,.size=1,.mesh=.haloDiamond,.floating=true,.hover=halo.hover,.bare=true,.grow=8};
/// how a diamond came to be
pub const Born=enum(u8){
  /// woven and put down by hand: it gathers as it grows in
  woven,
  /// of a halo: its four blooms spiral in to it over `halo.form`, then
  /// are consumed into it
  halo,
};
/// what a diamond remembers: how it came to be, how long since, and its arcs' light
pub const State=struct{
  /// how it came to be
  born:Born=.woven,
  /// seconds since it formed (grown); of a halo, since its blooms began
  /// spiralling in
  t:f32=0,
  /// per point of its ring: how brightly the arcs beside it shine
  light:m.Vice(f32,4)=@splat(halo.dim),
};
/// counts on from its forming (up to the end of its flash) and lets its
/// arcs brighten or dim with the blooms on its ring's points. Of a halo,
/// its blooms spiral in first, its arcs lit by them, and are consumed into
/// it as they meet; busy only then.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // the diamond and its remembered state, and how far it had come
  const self=ctx.ss.get(i);
  const d=&self.state.diamond;
  const was=d.t;
  // how long its blooms take to come in first (none, woven)
  const first:f32=if(d.born==.halo)halo.form else 0;
  d.t=@min(d.t+dt,first+halo.form+halo.flash);
  if(d.t<first){
    d.light=@splat(1);
    return true;
  }
  if(d.born==.halo and was<first){
    // they meet: the blooms are consumed into it
    for(0..4)|k|{
      // this point's tile, and the plant on it
      const at=halo.pointAt(self.x,self.y,k);
      const id=ctx.plants.at(ctx.w,at[0],at[1]) orelse continue;
      if(species.get(ctx.plants.list.items(.sp)[id.idx()]).halo)ctx.plants.remove(ctx.w,id);
    }
    ctx.g.say(txt.s.msg.diamondForms,.{});
    ctx.g.discover(.diamond);
    return true;
  }
  halo.relight(&d.light,ctx.plants,ctx.w,self.x,self.y,dt);
  return false;
}
/// a bloom on one of a forming halo's points is drawn in to the ring's
/// heart, where the blooms' cross of beams meets (the GPU spirals it there)
pub fn hold(s:*const st.Structure,wx:i32,wy:i32)?st.Hold{
  // its remembered state
  const d=&s.state.diamond;
  if(d.born!=.halo or d.t>=halo.form)return null;
  for(0..4)|k|{
    // this point's tile
    const at=halo.pointAt(s.x,s.y,k);
    if(at[0]==wx and at[1]==wy)return.{.k=d.t/halo.form,.seat=halo.hover};
  }
  return null;
}
/// `lit`: born whole of a halo, its light still the blooms'
pub fn message(ctx:st.Ctx,i:st.Id,msg:st.Msg)st.Reply{
  switch(msg){
    .lit=>{
      ctx.ss.get(i).state.diamond.light=@splat(1);
      return.done;
    },
    .arrived,.unform,.graft,.petalComing,.petalSnapped,.fastenComing,.fastened=>return.ignored,
  }
}
/// the most light a diamond carries on (glow): four blooms' worth
pub const carry:f32=16;
/// how far a diamond links with other relays (tiles)
pub const linkReach:f32=14;
/// its relay of the light grid once grown and formed: `halo.diamondR`
/// round it, carrying `carry`, linking within `linkReach`
pub fn relay(s:*const st.Structure)?light.Relay{
  if(s.grown<1 or s.fade>0)return null;
  // its remembered state
  const d=&s.state.diamond;
  if(d.born==.halo and d.t<halo.form)return null;
  return.{.at=s.at,.x=s.x,.y=s.y,.radius=halo.diamondR,.carry=carry,.link=linkReach};
}
/// how far along its halo is: growing in, it gathers as the halo's blooms
/// would bring it together; of a halo, as its blooms come in; formed, past 1
fn along(s:*const st.Structure)f32{
  // its remembered state
  const d=&s.state.diamond;
  // unforming, its shards come loose again, back the way they gathered
  if(s.fade>0)return 1-s.fade;
  if(d.born==.halo)return d.t/halo.form;
  return if(s.grown<1)s.grown else 1+d.t/halo.form;
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
test"four grown blooms in a cross form a diamond at their heart, no polyp needed; it relays light further and can be studied"{
  // the test harness and its allocator
  const testing=std.testing;
  const gpa=testing.allocator;
  // chunk layout, the world, the plants and the ecology
  const ck=lib.ck;
  const World=lib.world.World;
  const Plants=lib.plants.Plants;
  const Ecology=lib.ecology.Ecology;
  // the world, streamed in round the origin
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  // the chunk at the origin, laid flat with bare soil
  const c=w.chunkOfTile(0,0).?;
  for(0..16)|y|for(0..16)|x|{const t=y*ck.sizeTiles+x;c.kind[t]=.soil;c.height[t]=1;c.res[t]=0;};
  // the plants and structures
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  // the ecology, the structures' part in the light grid, and what the gardener understands
  var eco:Ecology=.{};
  defer eco.deinit(gpa);
  var rl:std.ArrayList(light.Relay)=.empty;
  defer rl.deinit(gpa);
  var us:std.ArrayList(light.User)=.empty;
  defer us.deinit(gpa);
  var ids:std.ArrayList(st.Id)=.empty;
  defer ids.deinit(gpa);
  var g:prog.Progression=.{};
  // the ring's heart
  const px=7;
  const py=7;
  // runs the light grid, the ecology, the structures and the search for halos together
  const run=struct{
    /// ticks the grid, ecology, structures and the search at 60 Hz for `secs` seconds
    fn runFor(e:*Ecology,p:*Plants,ww:*World,s:*st.Structures,gg:*prog.Progression,r:*std.ArrayList(light.Relay),u:*std.ArrayList(light.User),k:*std.ArrayList(st.Id),secs:f32)!void{
      // the tick length, and the time run so far
      const dt:f32=1.0/60.0;
      var t:f32=0;
      while(t<secs):(t+=dt){
        try st.lightGrid(s,testing.allocator,r,u,k);
        _=try e.tick(testing.allocator,p,ww,.{.relays=r.items,.users=u.items},dt);
        try s.tick(testing.allocator,ww,p,gg,dt);
        _=try halo.seek(.{.gpa=testing.allocator,.w=ww,.plants=p,.g=gg,.ss=s});
      }
    }
  };
  // plants a grown bloom
  const bloom=struct{
    /// plants a full-grown, mana-rich bloom at (x, y)
    fn at(p:*Plants,ww:*World,x:i32,y:i32)!void{
      try testing.expect(try p.placeEx(testing.allocator,ww,x,y,.{.x=x,.y=y,.chunk=undefined,.tile=undefined,.sp=.bloom,.seed=0,.growth=1,.mana=10}));
    }
  };
  // three points: nothing happens
  for(halo.points[0..3])|k|try bloom.at(&plants,&w,px+k[0]*halo.reachTiles,py+k[1]*halo.reachTiles);
  try run.runFor(&eco,&plants,&w,&ss,&g,&rl,&us,&ids,0.5);
  try testing.expectEqual(@as(usize,0),ss.list.items.len);
  // the fourth: a diamond forms at the heart
  try bloom.at(&plants,&w,px+halo.points[3][0]*halo.reachTiles,py+halo.points[3][1]*halo.reachTiles);
  try run.runFor(&eco,&plants,&w,&ss,&g,&rl,&us,&ids,0.1);
  try testing.expectEqual(@as(usize,1),ss.list.items.len);
  // the diamond, born of the halo
  const dia=ss.floaterAt(px,py).?;
  try testing.expectEqual(Born.halo,ss.get(dia).state.diamond.born);
  // how an east point's bloom is held just after the halo starts
  const early=hold(ss.get(dia),px+halo.reachTiles,py).?;
  try testing.expect(early.k>0 and early.k<0.05);
  try testing.expectEqual(prog.Status.locked,g.status(.celestialDefragmentation));
  // they meet: consumed into the diamond
  try run.runFor(&eco,&plants,&w,&ss,&g,&rl,&us,&ids,halo.form+0.5);
  for(halo.points)|k|try testing.expect(plants.at(&w,px+k[0]*halo.reachTiles,py+k[1]*halo.reachTiles)==null);
  // and the diamond's lattice can now be studied
  try testing.expectEqual(prog.Status.open,g.status(.celestialDefragmentation));
  // a solcyriphon 9 tiles off, linked to the diamond:
  // the diamond carries its light on to a vesper 4 tiles beyond it
  try testing.expect(try plants.placeEx(gpa,&w,px-9,py,.{.x=px-9,.y=py,.chunk=undefined,.tile=undefined,.sp=.solcyriphon,.seed=0.1,.growth=1}));
  try testing.expect(try plants.place(gpa,&w,px+4,py+4,.vesper,0.2));
  try run.runFor(&eco,&plants,&w,&ss,&g,&rl,&us,&ids,0.1);
  try testing.expect(eco.light.lit.items[plants.at(&w,px+4,py+4).?.idx()]>light.needAt);
  try testing.expect(eco.light.relayCarried.items[0]>0);
  // it never forms again; the empty points' arcs dim but stay
  try run.runFor(&eco,&plants,&w,&ss,&g,&rl,&us,&ids,10);
  try testing.expectEqual(@as(usize,1),ss.list.items.len);
  for(ss.get(dia).state.diamond.light)|l|try testing.expect(l<0.5 and l>=halo.dim);
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
