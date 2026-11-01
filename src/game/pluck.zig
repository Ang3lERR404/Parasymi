//! plucking: the gardener taking a ripe plant's yield by paw. Harvest
//! pressed on a ripe plant starts it, and it runs on by itself: each pluck
//! the paws close either side of the yield and draw it back toward the
//! wolf, the plant bending after them, until it comes loose; the plant
//! springs back past upright and settles, and one paw carries the yield to
//! the belly as a bead of its colour. A harvest takes all the plant has
//! ripened, shared over up to `most` plucks.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, angles, easing
const m=engine.core.math;
/// a plant's slot in the garden's list
const PlantId=lib.plants.Id;
/// every plant kind's definition: where its yield is plucked
const species=lib.species;
/// how far the pull draws a plucked yield back toward the wolf (m)
const pluckBack=lib.player.tuning.pluckBack;
/// how long one pluck takes (s)
pub const time:f32=0.8;
/// where in a pluck the yield comes loose (0..1 of it): as the paws' wrench ends
pub const loose=lib.player.tuning.wrenchEnd;
/// the most plucks one harvest is shown as
pub const most:u16=3;
/// the most a plucked plant bends after the paws (radians at its tip)
const bendMost:f32=0.5;
/// how much more than the pull's own angle the plant bends at its tip (the
/// bend grows toward the tip, so the yield, partway up, keeps with the paws)
const bendTip:f32=1.6;
/// the plucked plant's spring: how stiff (cycles a second) and how damped
/// (1: no overshoot; below, it springs back past upright and sways out)
const tugFreq:f32=2.2;
/// (this one: how damped)
const tugDamp:f32=0.22;
/// the spring is stepped at most this long at a time (s)
const tugStep:f32=1.0/240.0;
/// and at most this long a frame, however long the frame (s)
const tugLongest:f32=0.1;
/// a drawn plant's size from its own seed, at full growth, as plant.vert
/// sizes it (SIZE_MIN, SIZE_SPREAD there)
pub fn size(seed:f32)f32{return 0.85+0.3*@mod(seed*7.13,1);}
/// a pluck under way
pub const Pluck=struct{
  /// the plant plucked
  id:PlantId,
  /// where it stands (its own point): a plant moved into its slot since is not it
  at:m.V3,
  /// plucks left, this one among them
  left:u16,
  /// how far through this pluck (s)
  t:f32=0,
  /// whether this pluck's yield has come loose
  freed:bool=false,
  /// how much it has given, all told
  got:u32=0,
  /// how far through this pluck, 0..1
  pub fn share(p:Pluck)f32{return m.clamp01(p.t/time);}
};
/// how far (radians, at its tip) a plant of kind `def`, grown to `s`, bends
/// as the pull draws its yield back in full: enough that the yield keeps
/// with the paws
pub fn bend(def:*const species.Species,s:f32)f32{
  return@min(bendMost,bendTip*m.atan2(pluckBack,@max(def.pluck*s,0.05)));
}
/// the plucked plant's bend after the paws, on a spring: once the yield is
/// let go it springs back past upright and settles
pub const Tug=struct{
  /// the plant bent (null: none)
  id:?PlantId=null,
  /// where it stands, as `Pluck.at`
  at:m.V3=@splat(0),
  /// the way it bends, on the ground (toward the wolf; unit length)
  dir:m.Vice(f32,2)=.{0,0},
  /// how far it is bent (radians at its tip)
  x:f32=0,
  /// how fast it is bending
  v:f32=0,
  /// seconds since its yield last came loose in the paws (it shivers, the
  /// nub left weeping; `vertex.noPluck` long since)
  since:f32=lib.vertex.noPluck,
  /// where that yield came loose, which bursts out round it
  burst:m.V3=@splat(0),
  /// its yield comes loose at `at`: it shivers and bursts from there
  pub fn loosed(t:*Tug,at:m.V3)void{
    t.since=0;
    t.burst=at;
  }
  /// seconds since plant `id`, standing at `at`, last gave up its yield in
  /// the paws (`vertex.noPluck` for any other)
  pub fn sinceOf(t:Tug,id:PlantId,at:m.V3)f32{
    const bent=t.id orelse return lib.vertex.noPluck;
    if(bent!=id or m.len(at-t.at)>1e-4)return lib.vertex.noPluck;
    return t.since;
  }
  /// `dt` toward a bend of `want` radians, in steps short enough that a
  /// long frame never throws it
  pub fn to(t:*Tug,want:f32,dt:f32)void{
    t.since=@min(t.since+dt,lib.vertex.noPluck);
    // the spring's angular frequency, and the time left to step
    const w=tugFreq*m.tau;
    var left=@min(dt,tugLongest);
    while(left>0){
      // this step's length
      const h=@min(left,tugStep);
      t.v+=(w*w*(want-t.x)-2*tugDamp*w*t.v)*h;
      t.x+=t.v*h;
      left-=h;
    }
  }
  /// the bend plant `id`, standing at `at`, is drawn with (as the plant
  /// instance takes it: heading across, along, angle); none for any other
  pub fn of(t:Tug,id:PlantId,at:m.V3)m.Vice(f32,4){
    const bent=t.id orelse return@splat(0);
    if(bent!=id or m.len(at-t.at)>1e-4)return@splat(0);
    return.{t.dir[0],t.dir[1],t.x,0};
  }
};
test"a plucked plant springs back past upright and settles, whatever the frame's length"{
  for([_]f32{1.0/144.0,1.0/30.0,0.5})|dt|{
    // a plant drawn back in full, the time gone, and how far past upright
    // it swung once let go
    var t:Tug=.{};
    var gone:f32=0;
    while(gone<1):(gone+=dt)t.to(bendMost,dt);
    var past:f32=0;
    gone=0;
    while(gone<6):(gone+=dt){
      t.to(0,dt);
      past=@min(past,t.x);
      try std.testing.expect(@abs(t.x)<=bendMost*1.01);
    }
    if(dt<0.1)try std.testing.expect(past<-0.1*bendMost);
    if(dt<0.1)try std.testing.expect(@abs(t.x)<0.01);
  }
}
