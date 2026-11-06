//! where the garden is heard from and how: the ear (the view's), the echo of the place it stands in (the ground rising round it, structures crowding near) and how much of the way to a sound the ground hides.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the maths: vectors, lerps, clamps
const m=lib.engine.core.math;
/// the engine's sound pieces: the ear, the place's echo
const dsp=lib.engine.core.dsp;
/// the playable game, whose ground and structures are heard round
const Game=lib.play.game.Game;
/// the species registry: which plants are radiant, how high they hang
const species=lib.species;
/// a radiant plant gathering, as the sounds are told of it
const Gathering=lib.sound.forming.Gathering;
/// how far from the wolf a radiant plant gathering is heard (m)
const formingHeard:f32=14;
/// the radiant plant gathering that is heard now: the one heard last
/// (`was`) told once more as it turns whole, else the nearest still
/// gathering within hearing of the wolf; null with none
pub fn formingState(g:*const Game,was:?u32)?Gathering{
  // the plant columns
  const s=g.plants.list.slice();
  if(was)|w|if(w<s.len and species.get(s.items(.sp)[w]).lineage==.radiant and s.items(.growth)[w]>=1)return gathering(g,w);
  // the nearest gathering, and how far it is (squared)
  var best:?u32=null;
  var near:f32=formingHeard*formingHeard;
  for(s.items(.sp),s.items(.growth),s.items(.health),s.items(.at),0..)|sp,growth,health,at,i|{
    if(growth>=1 or health<=0 or species.get(sp).lineage!=.radiant)continue;
    // how far it is from the wolf, across the ground (squared)
    const d=at-g.player.pos;
    const d2=d[0]*d[0]+d[2]*d[2];
    if(d2<near){
      near=d2;
      best=@intCast(i);
    }
  }
  return if(best)|b|gathering(g,b)else null;
}
/// plant `i` as the sounds are told of it: how far gathered, heard from
/// where it hangs, as hidden as the way to it is
fn gathering(g:*const Game,i:u32)Gathering{
  // the plant columns, and where it hangs
  const s=g.plants.list.slice();
  const c=s.items(.at)[i];
  const at=m.v3(c[0],@max(g.heightAt(s.items(.x)[i],s.items(.y)[i]),0)+species.get(s.items(.sp)[i]).hover,c[2]);
  return.{.id=i,.growth=s.items(.growth)[i],.at=at,.muffle=muffle(g,at)};
}
/// how many ways round the ear the ground is looked at
const around=16;
/// how far out each way (m)
const rings=m.Vice(f32,4){3,6,12,24};
/// how steeply the ground must rise round the ear (rise over run) to count
/// as a wall all that way
const wallSteep:f32=0.45;
/// structures this near (m, along the ground) crowd the ear, the nearer
/// the more, and this many tall ones crowd it fully
/// (this one: how near)
const crowdNear:f32=10;
/// (how many crowd it fully)
const crowdFull:f32=4;
/// the echo of an open meadow, and of a hollow walled all round
/// (this one: the meadow's)
const openSpace:dsp.Space=.{.rt60=0.5,.wet=0.08,.dampHz=3500};
/// (the hollow's)
const walledSpace:dsp.Space=.{.rt60=2.6,.wet=0.45,.dampHz=6000};
/// what a full crowd of structures adds: seconds of ringing, and echo heard
/// (this one: seconds)
const crowdRing:f32=0.6;
/// (echo heard)
const crowdWet:f32=0.2;
/// how far apart (m) the way to a sound is looked along, at most how many times
/// (this one: how far apart)
const lineStep:f32=1;
/// (how many times)
const lineMost=48;
/// how far over the way (m) the ground must reach to hide a sound wholly
const hideOver:f32=1.5;
/// the ends of the way left unlooked at (m): what stands on the ground is
/// not hidden by the ground it stands on
const lineEnds:f32=1;
/// a sound's place never sits lower than this over the ground (m)
const overGround:f32=0.3;
/// the ground the garden stands on, for what hears round it
const Ground=struct{
  /// the game whose ground it is
  g:*const Game,
  /// the ground's height under `p`
  pub fn at(gr:Ground,p:m.V3)f32{
    // the tile under it
    const t=m.tileAt(p);
    return gr.g.heightAt(t[0],t[1]);
  }
};
/// where the game is heard from: the view's ear
pub fn ear(g:*const Game)dsp.Ear{return.{.at=g.cam.hearing(),.side=g.cam.side()};}
/// the echo of the place the ear is in now
pub fn space(g:*const Game)dsp.Space{
  // where it hears from, and how crowded it is
  const at=g.cam.hearing();
  var crowd:f32=0;
  for(g.structs.list.items)|*s|{
    // how far off along the ground
    const d=m.len(m.v3(s.at[0]-at[0],0,s.at[2]-at[2]));
    if(d<crowdNear)crowd+=(1-d/crowdNear)*s.def().tall;
  }
  return spaceOver(Ground,.{.g=g},at,m.clamp01(crowd/crowdFull));
}
/// how much of the way to a sound at `p` the ground hides (0 open .. 1 hidden)
pub fn muffle(g:*const Game,p:m.V3)f32{return hiddenOver(Ground,.{.g=g},g.cam.hearing(),p);}
/// the echo of a place at `at` over ground `gr` (any `t` with `at(t,p)f32`),
/// `crowd` (0..1) crowded by structures: the steeper the ground rises round
/// it, the longer and more of it, a crowd adding to both
pub fn spaceOver(comptime t:type,gr:t,at:m.V3,crowd:f32)dsp.Space{
  // the ground under the ear, and how walled it is all round
  const base=gr.at(at);
  var walls:f32=0;
  for(0..around)|i|{
    // this way round, and the steepest the ground rises along it
    const a=m.tau*m.f(i)/m.f(around);
    const dir=m.v3(@cos(a),0,@sin(a));
    var steep:f32=0;
    for(rings)|r|steep=@max(steep,(gr.at(at+dir*m.splat3(r))-base)/r);
    walls+=m.clamp01(steep/wallSteep);
  }
  walls/=m.f(around);
  return.{
    .rt60=m.lerp(openSpace.rt60,walledSpace.rt60,walls)+crowdRing*crowd,
    .wet=m.lerp(openSpace.wet,walledSpace.wet,walls)+crowdWet*crowd,
    .dampHz=m.lerp(openSpace.dampHz,walledSpace.dampHz,walls),
  };
}
/// how much of the way from `from` to a sound at `p` ground `gr` hides
/// (0 open .. 1 hidden): the most it reaches over the straight way, past
/// its ends
pub fn hiddenOver(comptime t:type,gr:t,from:m.V3,p:m.V3)f32{
  // the sound kept over the ground it is on, and the way to it
  const to=m.v3(p[0],@max(p[1],gr.at(p)+overGround),p[2]);
  const len=m.dist(from,to);
  if(len<2*lineEnds)return 0;
  // how many looks along it
  const n=@min(m.floorTo(usize,(len-2*lineEnds)/lineStep)+1,lineMost);
  var hidden:f32=0;
  for(0..n)|i|{
    // how far along, the point on the way there, and how far the ground reaches over it
    const k=(lineEnds+(len-2*lineEnds)*(m.f(i)+0.5)/m.f(n))/len;
    const q=m.lerpV(from,to,k);
    hidden=@max(hidden,m.clamp01((gr.at(q)-q[1])/hideOver));
  }
  return hidden;
}
/// the test helpers
const testing=lib.std.testing;
/// a ground for the tests: flat at 0, a ridge `ridge` high along x = 10,
/// and a pit's walls rising round the middle when `pit`
const Test=struct{
  /// how high the ridge is (m)
  ridge:f32=0,
  /// whether the middle is a pit
  pit:bool=false,
  /// the height under `p`
  pub fn at(tg:Test,p:m.V3)f32{
    // how far from the middle along the ground
    const r=m.len(m.v3(p[0],0,p[2]));
    const wall:f32=if(tg.pit and r>4)20 else 0;
    const hill:f32=if(@abs(p[0]-10)<2)tg.ridge else 0;
    return@max(wall,hill);
  }
};
test"a ridge between the ear and a sound hides it; open ground does not"{
  // the ear over flat ground, a sound beyond where the ridge would be
  const ear0=m.v3(0,1.5,0);
  const sound=m.v3(20,0,0);
  try testing.expectEqual(@as(f32,0),hiddenOver(Test,.{},ear0,sound));
  try testing.expectEqual(@as(f32,1),hiddenOver(Test,.{.ridge=5},ear0,sound));
  // a low ridge hides it only partly
  const low=hiddenOver(Test,.{.ridge=1.6},ear0,sound);
  try testing.expect(low>0 and low<1);
  // a sound on the ridge itself is not hidden by it
  try testing.expect(hiddenOver(Test,.{.ridge=5},ear0,m.v3(10,5,0))<0.5);
}
test"a pit echoes long and loud, an open meadow little, and a crowd of structures more"{
  // the ear in the open, among structures, and in a pit
  const open=spaceOver(Test,.{},m.v3(0,1,0),0);
  const crowded=spaceOver(Test,.{},m.v3(0,1,0),1);
  const pit=spaceOver(Test,.{.pit=true},m.v3(0,1,0),0);
  try testing.expectApproxEqAbs(openSpace.rt60,open.rt60,1e-4);
  try testing.expect(crowded.rt60>open.rt60 and crowded.wet>open.wet);
  try testing.expect(pit.rt60>2 and pit.wet>0.35);
}
