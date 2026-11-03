//! ARSTHRAXIA: the lab, a bloom that studies. It condenses the chosen
//! technology's units of research one at a time: by itself, slowly, and at
//! full pace for each unit whose per-unit ingredients it is fed (eaten as
//! the unit starts).
//!
//! It is seen through by its work, never by bobbing or breathing: idle, it
//! stands still in the wind, its satellites (thought-buds, warm hearts lit
//! in them) clustered shut over its flower. Studying, thought climbs its
//! nerves from the roots in violet pulses (part.vert), its flower's whorls
//! open and turn against each other, the buds split apart, spin round
//! where they clustered and open, shedding wisps of energy from their
//! hearts that condense into a core there,
//! swelling as the unit condenses; a unit done flares it and sends one
//! surge of light up its nerves.
//! What is learned grows on it: Arsthraxia sends vines climbing its stems;
//! each minor study along it an offshoot out of them (a bough with a
//! flower and a satellite of its own) and another satellite round its core.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: vectors, matrices, easing
const m=lib.engine.core.math;
/// what can be held: item kinds and stacks of them
const items=lib.items;
/// the structures registry: `Def`, `Structure`, the hooks' context
const st=lib.structures;
/// the tools a bulb icon is drawn with
const iconKit=lib.icon;
/// every player-facing string
const txt=lib.txt;
/// what the gardener has understood: the tree, the study, the lab's pace
const prog=lib.progression;
/// the HUD's shared sizes and colours
const style=lib.style;
/// the scene's list of moving parts it is drawn into
const Parts=lib.parts.Parts;
/// how one part looks: its glow, tint, sway and growth
const Look=lib.parts.Look;
/// its mesh: where its stalk, flower heart and offshoots are
const mesh=lib.arsthraxia;
/// its evolved mesh: how far over its heart its flower floats
const wovenMesh=lib.arsthraxiaConvergent;
/// the garden's growth timing: how far a grown form has formed
const growth=lib.growth;
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// a point or direction in the world
const V3=m.V3;
/// makes a `V3` from its three parts
const v3=m.v3;
// decision: drawn by its own `emit` (`bare`), so its look carries what it
// is doing (its nerves' light, a unit's surge) instead of the shared breath
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.driftFlower,.arsthraxiaCore,.arsthraxiaCup,.arsthraxiaBud0,.arsthraxiaBud1,.arsthraxiaBud2,.arsthraxiaBud3,.arsthraxiaBudHeart,.arsthraxiaShoot,.arsthraxiaVines,.arsthraxiaWhorl,.arsthraxiaWisp,.arsthraxiaWoven,.arsthraxiaWovenWhorl,.arsthraxiaWovenCup};
/// what the lab is: 2×2, keeping what it is fed, swaying from its root two
/// tiles tall, growing in over 8 s; shown whole (`preview`) before it is put down
pub const def:st.Def=.{.item=.arsthraxia,.lineage=.symbiotic,.evolves=.convergent,.size=2,.mesh=.arsthraxia,.preview=.arsthraxiaWhole,.store=true,.sway=0.8,.tall=2.0,.grow=8,.bare=true,.light=.needs,.draws=3,.crown=2.95,.ley=.leaves};
/// most of one ingredient it will hold
const stock=20;
/// the satellites round its core from the start; one more per growth
const satellites=3;
/// how many offshoots it may grow: one per minor study along Arsthraxia
const shoots=3;
/// how far up its stalk each offshoot leaves it (0 root .. 1 the flower)
const shootTimes=[shoots]f32{0.48,0.66,0.8};
/// the bearing each offshoot reaches out toward (radians)
const shootBearing=[shoots]f32{0.6,2.85,4.85};
/// how large each offshoot grows, against its mesh
const shootScale=[shoots]f32{1.3,1.15,1.0};
/// seconds an offshoot takes to grow out
const shootGrow:f32=6;
/// seconds the vines take to climb its stems
const vinesGrow:f32=9;
/// how much wider its satellites spin with each offshoot grown
const reachStep:f32=0.1;
/// how high its core hangs over its ground; it forms over the last
/// of its growth, once the flower has opened (`mesh.coreForm`)
const coreH:f32=2.2;
/// how far the core bobs up and down
const coreBob:f32=0.08;
/// how fast it bobs (radians a second)
const coreBobRate:f32=1.4;
/// the energy condensing in it: its radius as a unit starts .. as it is done
const coreRadius=m.Vice(f32,2){0.05,0.19};
/// its light as a unit starts .. as it is done
const coreGlow=m.Vice(f32,2){0.3,0.75};
/// how much brighter it runs while fed (a share more)
const fedGlow:f32=0.6;
/// the burst of light added at a unit's flare
const flareGlow:f32=1.4;
/// a unit's flare fades out over 1/this seconds (its surge climbs the
/// nerves as it does)
const flareFade:f32=1.6;
/// how quickly it eases into running brighter for a fed unit (per second)
const fedEase:f32=2;
/// the violet light it sheds round it (linear colour)
const lightCol=v3(0.55,0.32,1.0);
/// how strong that light is at full glow
const lightGloop:f32=0.5;
/// how far that light reaches (world units)
const lightReach:f32=4.5;
/// its flower while it studies: how fast the outer whorl turns (rad/s at
/// full study)
const whorlTurn:f32=0.35;
/// how fast the inner cup turns, the other way and faster (rad/s)
const cupTurn:f32=-0.6;
/// how much flatter the outer whorl lies, opened
const whorlOpen:f32=0.16;
/// how much wider it spreads, opened
const whorlWide:f32=0.05;
/// how far out the satellites spin round the core's heart
const orbitR:f32=0.4;
/// how fast they spin round it (rad/s)
const spinRate:f32=4.8;
/// how much faster each next one spins, so they never fall in step
const spinSpread:f32=0.11;
/// how each one's orbit tilts (radians), taken in turn
const orbitTilt=[_]f32{0.35,0.95,0.6,1.2,0.2,0.8};
/// how fast each satellite turns about itself (rad/s)
const selfSpin:f32=7;
/// resting, fused as one core: how far each satellite sits from its heart
const fusedR:f32=0.075;
/// how much larger each is while fused
const fusedScale:f32=1.9;
/// how fast the fused core turns, all together (rad/s)
const fusedTurn:f32=0.3;
/// the satellites' thought-buds, by how far open, closed first
const budIds=[mesh.budKeys]lib.meshlib.Id{.arsthraxiaBud0,.arsthraxiaBud1,.arsthraxiaBud2,.arsthraxiaBud3};
/// how brightly a bud's heart glows, closed and open
const heartGlow=m.Vice(f32,2){0.35,1.2};
/// the warm light the core's buds throw round it together, at rest and
/// split open
const budGloop=m.Vice(f32,2){0.25,0.9};
/// how far that light reaches (world units)
const budReach:f32=2.2;
/// the warm light an offshoot's bud throws, at rest and open
const tipGloop=m.Vice(f32,2){0.1,0.4};
/// how far that light reaches
const tipReach:f32=1.2;
/// the wisps: their light, more while fed
const wispGlow:f32=1.6;
/// an offshoot's own satellite: how far over its flower it hangs
const tipLift:f32=0.12;
/// how far round that point it spins
const tipOrbit:f32=0.045;
/// how fast it spins (rad/s)
const tipSpin:f32=2.2;
/// how large it is, against a core satellite
const tipScale:f32=0.7;
/// how far an evolved one's floating flower bobs on its tethers (m)
const floatBob:f32=0.012;
/// how fast it bobs (rad/s)
const floatRate:f32=1.1;
/// what the lab remembers: its study under way, what has grown on it,
/// and how its flower and light stand
pub const State=struct{
  /// the unit under way: how far condensed, whether it was fed
  lab:prog.Lab=.{},
  /// how far each offshoot has grown out (0..1)
  shoot:[shoots]f32=@splat(0),
  /// how far the vines have climbed (0..1)
  vines:f32=0,
  /// how much wider its satellites spin, grown with its offshoots
  reach:f32=1,
  /// a unit just finished: 1, fading to 0
  flare:f32=0,
  /// eases toward 1 while the unit under way was fed
  fed:f32=0,
  /// how far its flower's outer whorl and inner cup have turned
  turn:m.Vice(f32,2)=@splat(0),
  /// evolved by the unforming from the symbiotic lineage into the
  /// convergent one: drawn woven of both (meshes/arsthraxia_convergent.zig)
  evolved:bool=false,
  /// drift flowers taken in as stemless branches, once evolved: each
  /// quickens its study by `branchBoost`
  branches:u16=0,
  /// how far the newest branch has grown in (0..1)
  graft:f32=1,
};
/// how much faster an evolved arsthraxia studies for each stemless branch
/// it bears (linear: 0.6% each)
pub const branchBoost:f32=0.006;
/// how far off its axis its branches are held
const branchR:f32=0.22;
/// seconds a new branch takes to grow in
const graftGrow:f32=3;
/// the most branches drawn on it (more still count)
const branchesDrawn=48;
/// `unform`: the unforming takes the symbiotic lineage, but an arsthraxia
/// evolves instead
pub fn message(ctx:st.Ctx,i:st.Id,msg:st.Msg)st.Reply{
  switch(msg){
    .unform=>{
      ctx.ss.get(i).state.arsthraxia.evolved=true;
      return.done;
    },
    .graft=>{
      // the arsthraxia's state: only an evolved one bears branches
      const a=&ctx.ss.get(i).state.arsthraxia;
      if(!a.evolved)return.ignored;
      a.branches+|=1;
      a.graft=0;
      return.done;
    },
    .lit,.arrived,.petalComing,.petalSnapped,.fastenComing,.fastened=>return.ignored,
  }
}
/// it studies only in the light grid's light, until the unforming evolves
/// it: then it is freed, and studies without
pub fn lightUse(s:*const st.Structure)st.Use{return if(s.state.arsthraxia.evolved).none else def.light;}
/// condenses the study a little (a flare when a unit is done), turns its
/// flower with its work and grows what is learned on it. Returns whether
/// it is studying.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // the lab, its remembered state, and what is understood along its lineage
  const self=ctx.ss.get(i);
  const a=&self.state.arsthraxia;
  var study=ctx.g.study();
  // its stemless branches quicken it, a little each
  study.speed*=1+branchBoost*m.f(a.branches);
  a.graft=@min(1,a.graft+dt/graftGrow);
  if(ctx.g.labTick(&a.lab,self.inv.bag(),study,dt))a.flare=1;
  a.flare=@max(0,a.flare-dt*flareFade);
  a.fed=m.damp(a.fed,if(a.lab.fed)1 else 0,fedEase,dt);
  // its flower turns while it studies, easing in and out with it
  // how busy it is, eased (0..1)
  const busy=m.smooth(self.activity);
  a.turn[0]=@mod(a.turn[0]+dt*whorlTurn*busy,m.tau);
  a.turn[1]=@mod(a.turn[1]+dt*cupTurn*busy,m.tau);
  // it grows with what is learned along Arsthraxia, an offshoot at a time
  if(study.vines)a.vines=@min(1,a.vines+dt/vinesGrow);
  // how many offshoots have grown, eased, summed
  var grown:f32=0;
  for(&a.shoot,0..)|*sh,k|{
    sh.*=if(k<study.growth)@min(1,sh.*+dt/shootGrow)else sh.*;
    grown+=m.smooth(sh.*);
  }
  a.reach=1+reachStep*grown;
  return a.lab.active;
}
/// it wants the current study's per-unit ingredients, up to `stock` of
/// each; nothing else, and nothing while no study is chosen
pub fn wants(s:*const st.Structure,g:*const prog.Progression,item:items.Item)u32{
  // the study chosen now
  const id=g.current orelse return 0;
  for(prog.tree.get(id).perUnit)|ing|{
    // (a sunlit stand-in is taken for what it stands in for)
    const w=s.inv.wantOf(ing.item,item,stock);
    if(w>0)return w;
  }
  return 0;
}
/// where satellite `k` of `n` spins round the core's heart at time `tf`,
/// and which way it is going, both a unit out
fn orbit(k:usize,tf:f32)struct{at:V3,ahead:V3}{
  // how far round it has spun, and the tilted plane it spins in
  const turn=tf*spinRate*(1+spinSpread*m.f(k))+m.ratio(k,satellites)*m.tau;
  const plane=m.chain(&.{m.rotY(m.f(k)*m.goldenAngle),m.rotX(orbitTilt[k%orbitTilt.len])});
  return.{
    .at=m.mulPoint(plane,v3(@cos(turn),0,@sin(turn))),
    .ahead=m.mulPoint(plane,v3(-@sin(turn),0,@cos(turn))),
  };
}
/// where satellite `k` rests, fused into one core with the others, a unit out
fn fused(k:usize,tf:f32)V3{
  // its height on the sphere, the ring's radius there, and its bearing
  const y=1-2*(m.f(k)+0.5)/m.f(satellites+shoots);
  const r=@sqrt(@max(0,1-y*y));
  const a=m.f(k)*m.goldenAngle+tf*fusedTurn;
  return v3(@cos(a)*r,y,@sin(a)*r);
}
/// turns +y to `dir` (unit) the shortest way round, spun `spin` about it
/// first: no twist leaps as `dir` swings about
fn facing(dir:V3,spin:f32)m.M4{
  // how far it tilts from upright, and toward which bearing
  const tilt=m.acos(dir[1]);
  const bearing=m.atan2(-dir[2],dir[0]);
  return m.chain(&.{m.rotY(bearing),m.rotZ(-tilt),m.rotY(spin-bearing)});
}
/// a satellite: a thought-bud at `at` facing `dir`, `size` its scale and
/// `open` how far it has opened (0..1), its heart glowing in it; `fed`
/// brightens that heart
fn bud(out:*Parts,at:V3,dir:V3,spin:f32,size:f32,open:f32,fed:f32,look:Look)Allocator.Error!void{
  // where it stands and which way it faces, as it is drawn
  const frame=m.chain(&.{m.translate(at),facing(dir,spin),m.scale3(m.splat3(size))});
  // the key it is drawn from, and how far on into the next it is blended
  const kf=m.clamp01(open)*m.f(mesh.budKeys-1);
  const key=@min(m.floorTo(usize,kf),mesh.budKeys-2);
  var petals=look;
  petals.morph=kf-m.f(key);
  try out.emit(budIds[key],frame,petals);
  // its heart, lit from within
  var heart=look;
  heart.glow=m.lerp(heartGlow[0],heartGlow[1],open)*(1+fedGlow*fed);
  try out.emit(.arsthraxiaBudHeart,m.chain(&.{frame,m.translate(mesh.budHeartAt),m.scale3(m.splat3(mesh.budHeartR))}),heart);
}
/// a wisp of energy from `from` (going `ahead`) curling into the core at `heart`
fn wisp(out:*Parts,from:V3,ahead:V3,heart:V3,reach:f32,look:Look)Allocator.Error!void{
  // the way to the heart, the lag that curls it, and the curve's four points
  const d=heart-from;
  const lag=ahead*m.splat3(-m.len(d)*0.35);
  const ctrl=[4]V3{from,from+d*m.splat3(0.25)+lag,from+d*m.splat3(0.7)+lag*m.splat3(0.5),heart};
  try out.emitCurve(.arsthraxiaWisp,ctrl,m.norm(m.cross(d,v3(0,1,0))),1,reach,look);
}
/// where offshoot `k` is placed on its mesh as it stands
fn shootAt(base:m.M4,k:usize)m.M4{
  return m.mul(base,m.chain(&.{m.translate(mesh.stalkAt(shootTimes[k])),m.rotY(shootBearing[k]),m.scale3(m.splat3(shootScale[k]))}));
}
/// all of it: its stems, its flower's whorls, what research has grown on
/// it, the satellites and the energy condensing among them; placed on its
/// mesh as it stands (`place`), swaying with it from its root.
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // its state, its frame, how busy it is (eased), and the sway all share
  const a=&s.state.arsthraxia;
  const base=s.place(ctr);
  const busy=m.smooth(s.activity);
  const sway:Look=.{.phase=s.seed,.sway=def.sway,.tall=def.tall};
  // its nerves light with its study (glow) and carry a unit's surge (flutter)
  // the look of its body
  var body=sway;
  body.glow=busy;
  body.flutter=a.flare;
  body.fade=def.sap;
  body.grown=s.grown;
  // evolved by the unforming, it is drawn woven of both lineages
  const woven=a.evolved;
  try out.emit(if(woven).arsthraxiaWoven else .arsthraxia,base,body);
  // its flower: the whorls open and turn against each other while it studies
  // the flower's look, and how far its whorl opens
  var flower=body;
  flower.drop=mesh.heartAt[1];
  const open=v3(1+whorlWide*busy,1-whorlOpen*busy,1+whorlWide*busy);
  // (evolved, its flower floats over its heart, bobbing a little on its tethers)
  const bloomAt=if(woven)mesh.heartAt+v3(0,wovenMesh.lift+floatBob*@sin(tf*floatRate+s.seed*7),0)else mesh.heartAt;
  flower.drop=bloomAt[1];
  try out.emit(if(woven).arsthraxiaWovenWhorl else .arsthraxiaWhorl,m.mul(base,m.chain(&.{m.translate(bloomAt),m.rotY(a.turn[0]),m.scale3(open)})),flower);
  try out.emit(if(woven).arsthraxiaWovenCup else .arsthraxiaCup,m.mul(base,m.chain(&.{m.translate(bloomAt),m.rotY(a.turn[1])})),flower);
  // its stemless branches: drift flowers held up its stems in a spiral,
  // the newest growing in
  for(0..@min(a.branches,branchesDrawn))|k|{
    // how high up it sits, its bearing round the stems, and its size
    const y=0.3+1.05*@mod(m.f(k)*m.goldenShare,1);
    const ang=m.f(k)*m.goldenAngle+s.seed*m.tau;
    const size=0.6*(if(k+1==a.branches)m.smooth(a.graft)else 1);
    // where it sits, held just off the stems
    const at=v3(@cos(ang)*branchR,y,@sin(ang)*branchR);
    var look=sway;
    look.glow=0.4;
    try out.emit(.driftFlower,m.mul(base,m.chain(&.{m.translate(at),m.rotY(ang),m.rotZ(0.6),m.scale3(m.splat3(size))})),look);
  }
  // the vines Arsthraxia sends climbing its stems, by how far they have grown
  if(a.vines>0){
    // the vines' look: grown as far as they have climbed
    var vines=sway;
    vines.grown=a.vines*s.grown;
    try out.emit(.arsthraxiaVines,base,vines);
  }
  // the offshoots, growing out of the stems with what is learned; thought
  // runs out along their nerves too
  for(a.shoot,0..)|g,k|{
    if(g<=0)continue;
    // this offshoot's look
    var look=body;
    look.drop=shootTimes[k];
    look.grown=g*s.grown;
    try out.emit(.arsthraxiaShoot,shootAt(base,k),look);
  }
  // the core forms last, once the flower has opened
  // how far the core has formed (0..1)
  const form=growth.formed(mesh.coreForm,s.grown);
  if(form<=0)return;
  // the core's heart, bobbing
  const heart=ctr+v3(0,coreH+coreBob*@sin(tf*coreBobRate+s.seed*5),0);
  // studying, the satellites split apart and spin out round it
  // how far apart the satellites are, how far out, and how fed the unit is
  const split=busy;
  const reach=orbitR*a.reach;
  const fed=a.fed;
  // the satellites' look
  var sat=sway;
  // the wisps' look: brighter fed, seen only as they split
  var thread=sway;
  thread.glow=wispGlow*(1+fedGlow*fed);
  thread.fade=split;
  thread.drop=heart[1]-ctr[1];
  for(0..satellites+shoots)|k|{
    // the later ones come with the offshoots, growing as they do
    const appear=if(k<satellites)1 else m.smooth(a.shoot[k-satellites]);
    if(appear<=0)continue;
    // its orbit, where it is between resting and spinning, and its size
    const o=orbit(k,tf);
    const rest=fused(k,tf);
    const at=m.lerpV(heart+rest*m.splat3(fusedR*a.reach),heart+o.at*m.splat3(reach),split);
    const r=m.lerp(fusedScale,1,split)*a.reach*form*appear;
    // it faces out from the core, closed in the cluster, opening as it spins out
    const outward=m.lerpV(rest,o.at,split);
    const dir=if(m.len(outward)>1e-3)m.norm(outward)else rest;
    sat.drop=at[1]-ctr[1];
    try bud(out,at,dir,tf*selfSpin+m.f(k),r,split*appear,fed,sat);
    if(split>0.02){
      thread.phase=s.seed+m.f(k)*0.17;
      try wisp(out,at,o.ahead,heart,split*appear,thread);
    }
  }
  // each offshoot's own satellite, spun slowly over its flower, shedding
  // its wisp into the core too
  // where an offshoot's flower ends, and the way it points
  const tip=mesh.shootTip();
  for(a.shoot,0..)|g,k|{
    // (once its flower has opened)
    const grow=growth.formed(mesh.shootForm,g);
    if(grow<=0)continue;
    // how far round it has spun, the point over its flower, and where it is
    const turn=tf*tipSpin+m.f(k)*2.1;
    const over=m.mulPoint(shootAt(base,k),tip.at+tip.axis*m.splat3(tipLift));
    const at=over+v3(@cos(turn),0,@sin(turn))*m.splat3(tipOrbit*a.reach);
    sat.drop=at[1]-ctr[1];
    try bud(out,at,v3(0,1,0),tf*selfSpin,tipScale*a.reach*grow*form,split,fed,sat);
    try out.light(at,mesh.budLight*m.splat3(m.lerp(tipGloop[0],tipGloop[1],split)*grow*form),tipReach);
    if(split>0.02){
      thread.phase=s.seed+0.5+m.f(k)*0.23;
      try wisp(out,at,v3(-@sin(turn),0,@cos(turn)),heart,split*grow,thread);
    }
  }
  // the buds' hearts warm the air round the core
  try out.light(heart,mesh.budLight*m.splat3(m.lerp(budGloop[0],budGloop[1],split)*form),budReach);
  // the energy condensing where the old core stood: swelling as the unit
  // condenses, flaring as it is done and gathering anew
  // how far the unit has condensed (eased), and the core's radius
  const dense=m.smooth(m.clamp01(a.lab.t));
  const rad=@max(m.lerp(coreRadius[0],coreRadius[1],dense),coreRadius[1]*a.flare)*a.reach*split*form;
  if(rad<=1e-3)return;
  // how bright it glows
  const glow=m.lerp(coreGlow[0],coreGlow[1],dense)*(1+fedGlow*fed)+flareGlow*a.flare;
  // the core's look
  var core=sway;
  core.glow=glow;
  core.fade=dense;
  core.flutter=a.flare;
  core.drop=heart[1]-ctr[1];
  try out.emit(.arsthraxiaCore,m.chain(&.{m.translate(heart),m.rotY(tf*0.7),m.scale3(m.splat3(rad))}),core);
  try out.light(heart,lightCol*m.splat3(lightGloop*glow*split*form),lightReach);
}
/// its line in the panel: what it studies and how fast, with a tendril
/// showing how far along it is (or a nudge to choose a study)
pub fn describe(s:*const st.Structure,d:*Draw,g:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // the study chosen now
  const id=g.current orelse {
    _=try d.text(x,y,style.textBody,style.dim,txt.s.describe.chooseStudy);
    return;
  };
  // that study's entry in the tree
  const r=prog.tree.get(id);
  // how much of the study it adds a minute, at the pace it goes now
  const perMin=s.state.arsthraxia.lab.pace(g,g.study())*percent*m.sPerMin;
  _=try d.print(x,y,style.textBody,style.white,txt.s.describe.studies,.{txt.research(id).name,perMin});
  try d.tendril(x+style.descBarX,y+2,style.descBarW,style.barH,style.researchTendril,m.ratio(g.progress.get(id),r.units),0.3);
}
/// the study's progress as a share, shown as a percentage
const percent:f32=100;
/// its bulb: a sprout opening into a violet flower, satellites spinning
/// over it round a core of light (it studies).
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // where the sprout opens into its flower, and the core of light over it
  const top:iconKit.P=.{0,0.62};
  const heart:iconKit.P=.{0,0.86};
  try ic.stem(.{.{0,iconKit.topAt},.{0.12,0.3},.{-0.12,0.5},top},0.11,iconKit.stemCol);
  try ic.leaf(.{0.04,0.3},0.25,0.3,0.17,iconKit.sprout,0.9);
  for(0..iconPetals)|i|{
    try ic.leaf(top,m.halfPi+m.tau*m.ratio(i,iconPetals),0.26,0.17,iconPetal,1);
  }
  try ic.glow(heart,0.3,iconGlow);
  try ic.bud(heart,0.07,iconCore,1);
  for(0..iconSatellites)|i|{
    // this satellite's bearing round the core
    const a=m.tau*m.ratio(i,iconSatellites)+0.4;
    try ic.bud(.{heart[0]+@cos(a)*0.2,heart[1]+@sin(a)*0.09},0.045,iconSatellite,0.6);
  }
  try ic.coat(col);
}
/// how many petals its bulb's flower has
const iconPetals=5;
/// how many satellites spin over it
const iconSatellites=3;
/// the violet of those petals
const iconPetal:Color=.{200,150,255,255};
/// the warm white of the core of light
const iconCore:Color=.{255,230,190,255};
/// the amber of the satellites
const iconSatellite:Color=.{255,190,90,255};
/// the soft violet glow round the core
const iconGlow:Color=.{190,140,255,90};
