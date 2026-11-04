//! STORM SPIRE: the last of the weather, a kin of the weftstone, of both
//! lineages: a woven spire whose rings of vanes charge the air, five
//! offshoots each flying a lantern on a fine thread up into the rain
//! cloud. While rain falls on it and it holds a ley crystal, it charges,
//! its lanterns flickering brighter in the cloud like a heartbeat; full, a
//! bolt runs up the spire and every thread, the lanterns flash together,
//! and the crystal is spent: the cloud breaks into a storm. For two
//! minutes the spire feeds the cloud over it (heavy rain that will not
//! rain itself out) and lightning strikes the ground round it, each flash
//! lighting the fog. The first storm is a discovery (`firstStorm`).
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the test harness: allocator and expectations
const testing=std.testing;
/// all the maths: vectors, easing and conversions
const m=lib.engine.core.math;
/// the engine's noise: the sine hash bolts are kinked by
const noise=lib.engine.core.noise;
/// chunk sizes and tile kinds
const ck=lib.ck;
/// what can be held: item kinds
const items=lib.items;
/// the structures registry: `Def`, `Structure`, the hooks' context
const st=lib.structures;
/// every player-facing string
const txt=lib.txt;
/// what the gardener has understood
const prog=lib.progression;
/// the HUD's shared sizes and colours
const style=lib.style;
/// the scene's list of moving parts it draws itself into
const Parts=lib.parts.Parts;
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// the tools its bulb's icon is drawn with
const iconKit=lib.icon;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the spire's mesh: where its crown, offshoot tips and lanterns are
const mesh=lib.stormSpireMesh;
/// a point in 3D
const V3=m.V3;
/// builds a point
const v3=m.v3;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.stormBolt,.stormLantern,.stormThread};
/// what a storm spire is: of the convergent lineage, one tile across,
/// grown in twenty seconds, drawn by itself (its lanterns reach up into the
/// cloud, far over a tile), swaying a little more the higher
pub const def:st.Def=.{.item=.stormSpire,.lineage=.convergent,.size=1,.mesh=.stormSpire,.grow=20,.bare=true,.sway=0.3,.tall=2.0,.sap=0.3};
/// rain this heavy over it (a share of a downpour) is enough to charge in
const rainNeeded:f32=0.15;
/// how long a charge takes under rain (s)
const chargeTime:f32=30;
/// how fast a charge fades with no rain (a share a second): slowly, so it
/// builds over a grove's showers
const fadeRate:f32=0.002;
/// how long a storm lasts once struck (s)
const stormTime:f32=120;
/// how much cloud it feeds over itself a second through a storm, and how far
/// round (the moisture field's cloud: past `MOISTURE_RAIN_AT`, 1.4, it rains)
const stormCloud:f32=1.5;
/// (how far round, units)
const stormReach:f32=3;
/// how long the strike's bolts show (s)
const strikeLife:f32=0.5;
/// how many bolts strike the ground round it a minute through a storm, how
/// far round, and how long each shows (s)
const groundStrikes:f32=18;
/// (how far round, units)
const groundReach:f32=7;
/// (how long each shows)
const groundLife:f32=0.3;
/// how high over the ground a bolt leaves the cloud
const cloudH:f32=5.5;
/// how brightly a bolt glows, and the light its flash throws: its colour
/// and how far it reaches (a bolt lights the fog round it)
const boltGlow:f32=3;
/// (its colour)
const flashCol=v3(0.75,0.65,1.0);
/// (how far its flash reaches)
const flashReach:f32=10;
/// how brightly a lantern glows at full charge, and the light it throws in the cloud
const lanternGlow=v3(0.6,0.45,1.0);
/// (how far its light reaches)
const lanternReach:f32=2.5;
/// how many ley crystals it holds, waiting to be spent
const holds:u32=5;
/// how far its mesh reaches past its scale, for culling: its lanterns, high in the cloud
const meshReach:f32=5.5;
/// what a storm spire remembers: its charge, the storm it struck, and when
pub const State=struct{
  /// how charged it is, 0..1
  charge:f32=0,
  /// seconds left of the storm it struck (0: none)
  storm:f32=0,
  /// seconds since its last strike
  struck:f32=1e3,
  /// whether rain fell on it at the last tick
  wet:bool=false,
  /// how many storms it has struck (each storm's bolts their own)
  storms:u32=0,
};
/// a spire charged `charge` after `dt` s, with `rain` falling on it and a
/// ley crystal to spend or not: charging under rain, fading without; and
/// whether it strikes now (full, with a crystal)
pub fn charged(charge:f32,rain:f32,crystal:bool,dt:f32)struct{f32,bool}{
  if(rain<rainNeeded or !crystal)return.{@max(charge-fadeRate*dt,0),false};
  const c=charge+dt/chargeTime;
  return if(c>=1).{0,true}else.{c,false};
}
/// how far round it (tiles) its lanterns fly into the cloud: the rain it
/// charges in is the heaviest within
const cloudReach:i32=3;
/// the heaviest rain over the tiles within `cloudReach` of tile (x, y)
fn rainNear(w:*const lib.world.World,x:i32,y:i32)f32{
  // the heaviest found so far
  var most:f32=0;
  var dy:i32=-cloudReach;
  while(dy<=cloudReach):(dy+=1){
    var dx:i32=-cloudReach;
    while(dx<=cloudReach):(dx+=1){
      const c=w.chunkOfTile(x+dx,y+dy) orelse continue;
      most=@max(most,c.rain[ck.localIndex(x+dx,y+dy)]);
    }
  }
  return most;
}
/// it wants ley crystals, up to what it holds
pub fn wants(s:*const st.Structure,_:*const prog.Progression,item:items.Item)u32{
  if(item!=.leyCrystal)return 0;
  return holds-@min(s.inv.count(.leyCrystal),holds);
}
/// under rain it charges on its ley crystals; full, it strikes the cloud
/// into a storm, spending one. Busy while it charges or storms.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // the spire, its state, and the rain on it
  const self=ctx.ss.get(i);
  const ss=&self.state.stormSpire;
  const rain=rainNear(ctx.w,self.x,self.y);
  ss.wet=rain>=rainNeeded;
  ss.struck+=dt;
  ss.storm=@max(ss.storm-dt,0);
  // (never in its own storm: it strikes once a storm)
  const charge,const strikes=charged(ss.charge,rain,self.inv.count(.leyCrystal)>0 and ss.storm<=0,dt);
  ss.charge=charge;
  if(strikes){
    _=self.inv.take(.leyCrystal,1);
    ss.struck=0;
    ss.storm=stormTime;
    ss.storms+%=1;
    ctx.g.discover(.firstStorm);
  }
  return ss.storm>0 or ss.charge>0;
}
/// through a storm it feeds the cloud over it, so the rain stays heavy
pub fn breath(s:*const st.Structure)?st.Breath{
  if(s.state.stormSpire.storm<=0)return null;
  return.{.reach=stormReach,.low=0,.high=stormCloud};
}
/// a number 0..1 from `a`, `b` and `c`, the same for the same three
fn hash(a:f32,b:f32,c:f32)f32{
  return noise.sineHash(3,.{a,b,c},noise.sineWeights[0..3].*);
}
/// a bolt from `from` to `to` (world), kinked by `key`, glowing, its flash lighting the air
fn bolt(out:*Parts,from:V3,to:V3,key:f32,bright:f32)Allocator.Error!void{
  // its two kinks between, thrown off its line, and the way they lie across it
  const d=m.dist(from,to);
  var c:[4]V3=.{from,m.lerpV(from,to,0.33),m.lerpV(from,to,0.66),to};
  for(c[1..3],0..)|*p,k|p.*+=v3(hash(key,m.f(k),1)-0.5,(hash(key,m.f(k),2)-0.5)*0.3,hash(key,m.f(k),3)-0.5)*m.splat3(0.25*d);
  const side=m.norm(v3(hash(key,4,5)-0.5,0,hash(key,6,7)-0.5)+v3(1e-3,0,0));
  try out.emitCurve(.stormBolt,c,side,1,1,.{.glow=boltGlow*bright,.phase=key});
}
/// how far a lantern wanders off where it rests, each way (m), how far it
/// bobs, and how slowly (radians a second)
const wander=v3(0.7,0.18,0.7);
/// (how slowly it wanders)
const wanderRate:f32=0.12;
/// how far a thread bows off its straight line, slack in the air (a share of its length)
const slack:f32=0.08;
/// when (a share of its growth) its lanterns begin to rise from the offshoots' tips
const riseFrom:f32=0.8;
/// where lantern `k` of spire `s` flies now (world), the spire's frame
/// `base`, at time `tf`: risen from its offshoot's tip as the spire grows,
/// then wandering on the air on its own, each its own way
fn lanternAt(s:*const st.Structure,base:m.M4,k:usize,tf:f32)V3{
  // its own phase, and how far it has risen
  const ph=s.seed*13+m.f(k)*2.1;
  const risen=m.smooth(m.unlerp(riseFrom,1,s.grown));
  const drift=v3(@sin(tf*wanderRate+ph)+0.4*@sin(tf*wanderRate*2.3+ph*3),@sin(tf*wanderRate*3.1+ph*5),@cos(tf*wanderRate*0.8+ph*2)+0.4*@cos(tf*wanderRate*1.9+ph))*wander;
  return m.lerpV(m.mulPoint(base,mesh.tipAt(k)),m.mulPoint(base,mesh.kiteAt(k))+drift,risen);
}
/// its lanterns flown free on their threads: each thread hung slack from
/// its offshoot's tip to its lantern, the lantern turning slowly, glowing
/// `lit` (0..1)
fn fly(s:*const st.Structure,out:*Parts,base:m.M4,tf:f32,lit:f32)Allocator.Error!void{
  if(s.grown<=riseFrom)return;
  for(0..mesh.kites)|k|{
    // the tip it is tied to, where it flies, and the way it bows across
    const tip=m.mulPoint(base,mesh.tipAt(k));
    const at=lanternAt(s,base,k,tf);
    const d=at-tip;
    const across=m.norm(v3(d[2],0,-d[0])+v3(1e-3,0,0));
    const bow=across*m.splat3(slack*m.len(d)*@sin(tf*wanderRate*1.7+m.f(k)));
    const end=at-v3(0,mesh.look.kiteR*1.2,0);
    try out.emitCurve(.stormThread,.{tip,m.lerpV(tip,end,0.33)+bow,m.lerpV(tip,end,0.66)+bow*m.splat3(0.6),end},across,1,1,.{.phase=s.seed,.glow=lit});
    try out.emit(.stormLantern,m.chain(&.{m.translate(at),m.rotY(tf*0.2+m.f(k)*1.3)}),.{.phase=s.seed+m.f(k),.fade=def.sap,.glow=lit});
  }
}
/// itself; its lanterns glowing in the cloud as it charges, flickering
/// like a heartbeat; the strike up its threads into the cloud; through a
/// storm, lightning striking the ground round it
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // its state, and its frame in the world
  const ss=&s.state.stormSpire;
  const base=s.place(ctr);
  try out.emitReaching(def.mesh,base,.{.phase=s.seed,.fade=def.sap,.sway=def.sway,.tall=def.tall,.grown=s.grown},meshReach);
  if(s.grown<1)return try fly(s,out,base,tf,0);
  // its lanterns: a beat that quickens and brightens as it charges, all
  // of them at once as it strikes
  const beat=0.5+0.5*@sin(tf*m.lerp(1.5,7,ss.charge));
  const flash=m.clamp01(1-ss.struck/strikeLife);
  const lit=@max(ss.charge*ss.charge*(0.4+0.6*beat),flash);
  try fly(s,out,base,tf,lit);
  if(lit>0.02)for(0..mesh.kites)|k|try out.light(lanternAt(s,base,k,tf),lanternGlow*m.splat3(lit*1.5),lanternReach);
  // the strike: a bolt up the spire to each offshoot's tip, up its thread
  // to its lantern, and from the lantern up into the cloud
  if(flash>0){
    const top=m.mulPoint(base,mesh.topAt());
    for(0..mesh.kites)|k|{
      // this lantern, and the tip its thread leaves
      const kite=lanternAt(s,base,k,tf);
      const tip=m.mulPoint(base,mesh.tipAt(k));
      const key=m.f(ss.storms)*7+m.f(k)+@floor(tf*12)*0.37;
      try bolt(out,tip,kite,key,flash);
      try bolt(out,kite,kite+v3(hash(key,8,9)-0.5,1.6,hash(key,10,11)-0.5),key+0.5,flash);
    }
    try bolt(out,ctr,top,m.f(ss.storms)*3+@floor(tf*12),flash);
    try out.light(top+v3(0,2,0),flashCol*m.splat3(1.8*flash),flashReach);
  }
  // through a storm: bolts out of the cloud striking the ground round it,
  // each in its own slot of time, each its own place
  if(ss.storm>0){
    // which slot of time this is, and how far through it
    const slot=@floor(tf*groundStrikes/60);
    const into=tf*groundStrikes/60-slot;
    const life=groundLife*groundStrikes/60;
    if(into<life){
      // where it strikes, and how bright it is through its moment
      const a=hash(slot,m.f(ss.storms),12)*m.tau;
      const r=groundReach*@sqrt(hash(slot,m.f(ss.storms),13));
      const at=ctr+v3(@cos(a)*r,0,@sin(a)*r);
      const bright=1-into/life;
      try bolt(out,at+v3(0,cloudH,0),at,slot*1.7+m.f(ss.storms),bright);
      try out.light(at+v3(0,1.5,0),flashCol*m.splat3(2.2*bright),flashReach);
    }
  }
}
/// its line in the panel: how charged it is, and what it waits on
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // its state, and what it is doing
  const ss=&s.state.stormSpire;
  const doing=if(ss.storm>0)txt.s.describe.storming else if(s.inv.count(.leyCrystal)==0)txt.s.describe.noCrystal else if(!ss.wet)txt.s.describe.waitingRain else txt.s.describe.charging;
  _=try d.print(x,y,style.textBody,style.white,txt.s.describe.storm,.{ss.charge*100,doing});
}
/// its bulb: a spire with a lantern floating over it on a thread, a bolt
/// flickering up between
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // the lantern's place, bobbing on its thread
  const lantern:iconKit.P=.{0.32,0.85+0.03*@sin(ic.t*1.3+ic.phase*4)};
  const top:iconKit.P=.{0,0.62};
  try ic.stem(.{.{0,iconKit.topAt},.{0.03,0.3},.{-0.02,0.48},top},0.06,iconKit.stemCol);
  for(vanes)|h|{
    try ic.leaf(.{0,h},0.15,0.16,0.03,iconVane,1);
    try ic.leaf(.{0,h},m.pi-0.15,0.16,0.03,iconVane,1);
  }
  try ic.stem(.{top,.{0.12,0.72},.{0.25,0.75},lantern},0.012,iconThread);
  // its charge: the lantern beating brighter
  const beat=0.5+0.5*@sin(ic.t*4+ic.phase*3);
  try ic.glow(lantern,0.16+0.06*beat,iconGlow);
  try ic.bud(lantern,0.07,iconLantern,0.6+0.4*beat);
  try ic.coat(col);
}
/// the heights its vanes fan out at, in the icon
const vanes=[_]f32{0.36,0.48};
/// the icon's vanes: pale lilac
const iconVane:Color=.{205,190,235,255};
/// the icon's thread: lilac
const iconThread:Color=.{190,160,240,255};
/// the icon's lantern: pale violet light
const iconLantern:Color=.{220,200,255,255};
/// its glow
const iconGlow:Color=.{180,140,255,100};
test"a storm spire charges only under rain with a crystal, and strikes when full"{
  // dry: a charge fades, never strikes
  var c,var strikes=charged(0.5,0,true,10);
  try testing.expect(c<0.5 and !strikes);
  // rain but no crystal: the same
  c,strikes=charged(0.5,1,false,10);
  try testing.expect(c<0.5 and !strikes);
  // rain and a crystal: it charges, then strikes and starts again
  c,strikes=charged(0,1,true,chargeTime*0.5);
  try testing.expect(c>0.4 and !strikes);
  c,strikes=charged(c,1,true,chargeTime);
  try testing.expect(strikes and c==0);
}
