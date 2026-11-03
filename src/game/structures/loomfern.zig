//! LOOMFERN: a fern that weaves fibre by itself, so the wolf need not pull
//! it from moss. Grown, it draws threads from its fronds and winds them
//! into a sheaf on its spindle, one fibre a sheaf, slowly from nothing;
//! fed essence (into its calyx), it weaves several sheaves from each at a
//! far quicker pace. Finished fibre goes to a neighbour that wants it, or
//! a conduit behind it pulls it away; with nowhere to go it lays its
//! sheaves at its foot until it holds `buffer`, then rests.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the test harness: allocator and expectations
const testing=std.testing;
/// all the maths: vectors, matrices, easing
const m=lib.engine.core.math;
/// chunk layout and ground kinds
const ck=lib.ck;
/// the garden's tile world
const World=lib.world.World;
/// what can be held: item kinds and stacks of them
const items=lib.items;
/// the garden's plants (the tests' bench needs a list of them)
const Plants=lib.plants.Plants;
/// the structures registry: `Def`, `Structure`, the hooks' context
const st=lib.structures;
/// the shared structure test bench: ground, running ticks
const bench=st.bench;
/// the tools a bulb icon is drawn with
const iconKit=lib.icon;
/// every player-facing string
const txt=lib.txt;
/// what the gardener has understood
const prog=lib.progression;
/// the HUD's shared sizes and colours
const style=lib.style;
/// colour conversions, for tinting the calyx by essence's colour
const color=lib.engine.core.color;
/// the scene's list of moving parts this fern adds to each frame
const Parts=lib.parts.Parts;
/// how one part looks: its glow, tint, sway and growth
const Look=lib.parts.Look;
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the loomfern's mesh: its fronds, spindle and calyx
const mesh=lib.loomfern;
/// a three-float vector
const V3=m.V3;
/// builds a three-float vector
const v3=m.v3;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.germinatorPool,.loomfernSheaf,.loomfernThread};
/// what a loomfern is: grown from its seed, one tile across, a low store
/// swaying freely in the breeze
pub const def:st.Def=.{.item=.loomfern,.lineage=.symbiotic,.size=1,.mesh=.loomfern,.store=true,.grow=5,.sway=0.7,.tall=0.5,.light=.boost,.draws=1};
/// a lithophage grown beside it: the study of woven stone
pub const meets:st.Meeting=.{.kind=.lithophage,.found=.loomAndStone};
/// seconds a fibre takes unfed
pub const slow:f32=12;
/// seconds a fibre takes while fed essence
pub const fast:f32=3;
/// fibre woven from each essence it is fed
pub const perEssence=4;
/// fibre it holds before it rests
pub const buffer=12;
/// the most essence it takes in
const essenceStock=6;
/// threads drawn to the sheaf at once, the fronds they come from taking
/// turns weave by weave
const threads=3;
/// where in the weave (0..1) each thread starts being drawn out
const threadAt=[threads]f32{0.0,0.2,0.4};
/// how much of the weave a thread takes to reach the sheaf
const threadDraw:f32=0.3;
/// how far into the weave the threads start winding in
const threadWind:f32=0.82;
/// where along a frond a thread is drawn from (0 base .. 1 tip)
const threadFrom:f32=0.72;
/// the sheaf turns this many times a weave (whole turns, so the next one
/// starts where it left off)
const sheafTurns:f32=2;
/// how far into the weave the sheaf starts to grow on the spindle
const sheafFrom:f32=0.08;
/// finished sheaves laid at its foot: one per this many fibre held
const perLaid=3;
/// the most sheaves laid at its foot
const laid=4;
/// how far out from the bole they lie
const laidOut:f32=0.17;
/// how far (radians) they lean in against the bole
const laidLean:f32=1.15;
/// a laid sheaf's size, of the spindle's
const laidSize:f32=0.85;
/// the essence in its calyx: a lens this wide empty .. full
const poolW=m.Vice(f32,2){0.012,0.03};
/// how brightly the sheaves glow
const glow:f32=0.15;
/// how brightly a thread glows unfed, and fed
const threadGlow=m.Vice(f32,2){0.1,0.45};
/// how brightly the essence in its calyx glows
const poolGlow:f32=0.3;
/// what a loomfern remembers: its weave's progress, the essence still in
/// it, and how many fibre it has woven
pub const State=struct{
  /// how far along the fibre being woven is (0..1)
  t:f32=0,
  /// fibre still to weave from the essence last taken in
  fed:u8=0,
  /// fibre woven so far (which fronds give the threads)
  woven:u32=0,
};
/// it roots in living ground only.
pub fn ground(k:ck.Kind)bool{return k==.soil or k==.moss;}
/// takes in an essence when the last is spent, and weaves on, slow unfed
/// and fast fed, adding a fibre each weave. Returns true while weaving
/// (false once it holds `buffer`).
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  _=st.handOff(ctx,i);
  // the fern itself, and its remembered state
  const self=ctx.ss.get(i);
  const f=&self.state.loomfern;
  if(self.inv.count(.fibre)>=buffer)return false;
  if(f.fed==0 and self.inv.spend(.essence,1))f.fed=perEssence;
  f.t+=dt/(if(f.fed>0)fast else slow);
  if(f.t<1)return true;
  if(self.inv.add(.fibre,1)<1)return false;
  f.t=0;
  f.woven+%=1;
  if(f.fed>0)f.fed-=1;
  return true;
}
/// it wants essence only (or sunlit essence for it), up to `essenceStock`, less what it holds.
pub fn wants(s:*const st.Structure,_:*const prog.Progression,item:items.Item)u32{
  return s.inv.wantOf(.essence,item,essenceStock);
}
/// only the fibre it has woven leaves it.
pub fn output(s:*const st.Structure)?items.Item{return if(s.inv.count(.fibre)>0).fibre else null;}
/// it gives fibre only, while it holds some.
pub fn gives(s:*const st.Structure,item:items.Item)bool{return item==.fibre and s.inv.count(.fibre)>0;}
/// the sheaf forming on its spindle and the threads drawn into it from the
/// fronds, the essence standing in its calyx, finished sheaves at its foot;
/// all of it sways with the fern.
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,_:f32)Allocator.Error!void{
  if(s.grown<1)return;
  // its remembered state, and its frame in the world
  const f=&s.state.loomfern;
  const base=s.place(ctr);
  // the look every part of it shares: swaying with the fern
  const sway:Look=.{.phase=s.seed,.sway=def.sway,.tall=def.tall,.glow=glow};
  // whether it is weaving, how far along (0..1), and whether it is fed
  const weaving=s.inv.count(.fibre)<buffer;
  const p=if(weaving)f.t else 0;
  const fed=f.fed>0 or s.inv.count(.essence)>0;
  // the sheaf: growing on the spindle as the weave goes, turning as it
  // winds the threads in
  const sheaf=m.smooth(m.unlerp(sheafFrom,1,p));
  if(sheaf>0){
    // the sheaf's look: swaying from the spindle's height
    var look=sway;
    look.drop=mesh.sheafAt[1];
    try out.emit(.loomfernSheaf,m.mul(base,m.chain(&.{m.translate(mesh.sheafAt),m.rotY(p*sheafTurns*m.tau+s.seed*5),m.scale3(m.splat3(sheaf))})),look);
  }
  // the threads: each drawn out of a leaflet to the sheaf, then wound in,
  // its far end pulled off the frond and into the sheaf
  if(weaving)for(0..threads)|j|{
    // where in the weave this thread starts
    const k0=threadAt[j];
    if(p<=k0)continue;
    // the frond it comes from this weave
    const frond=(@as(usize,f.woven)*2+j*3+m.floorTo(usize,s.seed*7))%mesh.fronds;
    // where it leaves the frond, where it meets the sheaf, the way between
    const from=m.mulPoint(base,mesh.frondAt(frond,threadFrom));
    const to=m.mulPoint(base,mesh.sheafAt);
    const d=to-from;
    // how far the thread sags, and its curve
    const sag=v3(0,-0.04*m.len(d),0);
    const ctrl=[4]V3{from,from+d*m.splat3(0.33)+sag,from+d*m.splat3(0.7)+sag*m.splat3(0.5),to};
    // the thread's flat side, level and across its way
    const side=m.norm(m.cross(d,v3(0,1,0)));
    // the thread's look: brighter when fed
    var look=sway;
    look.glow=if(fed)threadGlow[1]else threadGlow[0];
    look.drop=from[1]-ctr[1];
    if(p<threadWind){
      try out.emitCurve(.loomfernThread,ctrl,side,1,m.smooth(m.clamp01((p-k0)/threadDraw)),look);
    }else{
      // the same curve from the sheaf's end, shortening: wound in
      const back=[4]V3{ctrl[3],ctrl[2],ctrl[1],ctrl[0]};
      try out.emitCurve(.loomfernThread,back,-side,1,1-m.smooth((p-threadWind)/(1-threadWind)),look);
    }
  };
  // essence it was fed, standing in the calyx
  const ess=s.inv.count(.essence);
  if(ess>0 or f.fed>0){
    // how full the calyx stands (0..1), counting what is still being woven
    const lv=m.clamp01((m.f(ess)+m.f(f.fed)/perEssence)/essenceStock);
    // the pool's look: essence-coloured, glowing softly
    var look=sway;
    look.tint=color.Rgba8.of(items.Item.essence.info().col).toF4();
    look.glow=poolGlow;
    look.drop=mesh.poolAt[1];
    try out.emit(.germinatorPool,m.mul(base,m.chain(&.{m.translate(mesh.poolAt),m.scale3(m.splat3(m.lerp(poolW[0],poolW[1],lv)))})),look);
  }
  // finished sheaves laid at its foot, leaning in against the bole, each
  // filling out as the fibre held grows toward it
  const held=s.inv.count(.fibre);
  for(0..laid)|k|{
    // how filled out this sheaf is (0..1)
    const fill=m.clamp01((m.f(held)-m.f(k*perLaid))/perLaid);
    if(fill<=0)break;
    // its angle round the bole, and where it lies
    const a=(m.f(k)+0.5)/laid*m.tau+s.seed*3;
    const at=v3(@cos(a)*laidOut,mesh.sheafH*0.42,@sin(a)*laidOut);
    // its look: swaying from as high as it lies
    var look=sway;
    look.drop=at[1];
    try out.emit(.loomfernSheaf,m.mul(base,m.chain(&.{m.translate(at),m.rotY(-a),m.rotZ(laidLean),m.scale3(m.splat3(laidSize*m.smooth(fill)))})),look);
  }
}
/// its line in the panel: how much fibre it holds (fed or not), with a
/// tendril of the weave's progress, or a note that it is full.
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // its remembered state, and the fibre it holds
  const f=&s.state.loomfern;
  const held=s.inv.count(.fibre);
  if(held>=buffer){
    _=try d.print(x,y,style.textBody,style.dim,txt.s.describe.loomFull,.{held,buffer});
    return;
  }
  // the line's wording: fed or unfed
  const tpl=if(f.fed>0 or s.inv.count(.essence)>0)txt.s.describe.loomFed else txt.s.describe.loom;
  _=try d.print(x,y,style.textBody,style.white,tpl,.{held,buffer});
  try d.tendril(x+style.descBarX,y+2,style.descBarW,style.barH,style.growth,f.t,0.3);
}
/// its bulb: a fern unrolling out of the seed, a crozier at its heart and
/// a sheaf of fibre bound beside it (it weaves fibre).
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  for([_]f32{-1,1})|sx|{
    // this side's frond curve
    const fr=[4]iconKit.P{.{0,iconKit.topAt},.{0.12*sx,0.5},.{0.5*sx,0.75},.{0.72*sx,0.5}};
    try ic.stem(fr,0.07,iconKit.stemCol);
    for(0..3)|k|{
      // where along the frond this leaflet sits
      const at=iconKit.curve(fr,0.4+0.2*m.f(k));
      try ic.leaf(at,if(sx<0)2.2-0.3*m.f(k)else 0.9+0.3*m.f(k),0.2,0.1,iconKit.sprout,0.9);
    }
  }
  try ic.stem(.{.{0,iconKit.topAt},.{0,0.4},.{0.16,0.62},.{0.02,0.6}},0.075,iconKit.sprout);
  try ic.bud(.{0.06,0.56},0.07,iconKit.sprout,0.4);
  try ic.kernel(.{0.0,0.92},0.32,iconFibre);
  try ic.coat(col);
}
/// the moss green of the fibre sheaf in its bulb
const iconFibre:Color=.{120,170,90,255};
// ---- tests ----
test"a loomfern weaves fibre slowly unfed, and fast from essence"{
  // the allocator, the world and its mossy ground
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  _=try bench.ground(&w,.{.width=4,.depth=2,.kind=.moss,.bare=true});
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,0,0,.loomfern,0,0));
  // the loomfern
  const id=ss.at(&w,0,0).?;
  try bench.run(&ss,&w,&plants,&g,slow*2+0.2);
  try testing.expectEqual(@as(u32,2),ss.get(id).inv.count(.fibre));
  // fed one essence: four fibre at the fast pace
  try testing.expectEqual(@as(u16,1),ss.insert(&g,id,.essence,1));
  try testing.expectEqual(@as(u16,0),ss.insert(&g,id,.grit,1));
  try bench.run(&ss,&w,&plants,&g,fast*perEssence+0.2);
  try testing.expectEqual(@as(u32,2+perEssence),ss.get(id).inv.count(.fibre));
  try testing.expectEqual(@as(u32,0),ss.get(id).inv.count(.essence));
  // only fibre leaves it
  try testing.expect(ss.output(id)==.fibre);
  try testing.expect(!ss.gives(id,.essence));
}
test"a loomfern hands its fibre to a neighbour, and rests when full"{
  // the allocator, the world and its mossy ground
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  _=try bench.ground(&w,.{.width=4,.depth=2,.kind=.moss,.bare=true});
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,0,0,.loomfern,0,0));
  try testing.expect(try ss.place(gpa,&w,1,0,.sapCache,0,0));
  try testing.expect(try ss.place(gpa,&w,3,1,.loomfern,0,0));
  _=ss.insert(&g,ss.at(&w,0,0).?,.essence,essenceStock);
  try bench.run(&ss,&w,&plants,&g,30);
  try testing.expect(ss.get(ss.at(&w,1,0).?).inv.count(.fibre)>=9);
  try bench.run(&ss,&w,&plants,&g,slow*(buffer+2));
  // the loomfern with no neighbour, which fills and rests
  const lone=ss.get(ss.at(&w,3,1).?);
  try testing.expectEqual(@as(u32,buffer),lone.inv.count(.fibre));
  try testing.expect(lone.activity<0.01);
}
