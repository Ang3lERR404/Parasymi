//! WEATHER: the rain the garden's air rains soaking back into its ground.
//! The air's moisture lives on the GPU (render/passes/moisture.zig: mist,
//! cloud gathering heavy, rain falling from it, the ground's wetness under
//! it); every so often the game asks for the whole of it back (the scene's
//! `readField`, the engine's `field`), and when it comes, every loaded
//! tile's ground water is soaked back up toward all it holds, as fast as
//! the ground over it is wet (`soaked`). So what a nebularbor drinks, it
//! breathes; what it breathes gathers into cloud; the cloud rains it back.
//! The first rain to fall over the loaded garden is a discovery.
const lib=@import("../lib.zig");
/// the standard library, for its test helpers
const std=lib.std;
/// all the maths: easing, the int-to-float cast
const m=lib.engine.core.math;
/// the field as the engine reads it back: one texel under a world point
const Volume=lib.engine.render.volume.Volume;
/// the chunk grid: each tile's ground water
const ck=lib.ck;
/// the garden's world: its loaded chunks
const World=lib.world.World;
/// how often the whole field is asked for (s of the world's time)
const every:f32=1;
/// the longest stretch one read soaks the ground for (s), so a long wait
/// for it never floods the ground at once
const longest:f32=5;
/// how long ground wet through takes to soak a tile's water most of the way
/// back up to all it holds (s: a third of what is missing left after it)
pub const soakTime:f32=60;
/// rain this heavy over loaded ground (a share of a downpour) is the
/// garden's first rain
const firstRain:f32=0.15;
/// the weather as the game keeps it: when it last read the field back
pub const Weather=struct{
  /// the world's time (s) since the ground was last soaked
  since:f32=0,
  /// whether the field has been asked for and not yet come back
  asked:bool=false,
  /// whether this frame asks for it
  want:bool=false,
  /// the engine's count of fields read back, as of the last soaked
  seen:u32=0,
  /// a frame `moved` s of the world's time on: whether to ask for the field
  /// (`want`), once every `every` s, not again until it comes back
  pub fn tick(w:*Weather,moved:f32)void{
    w.since+=moved;
    w.want=!w.asked and w.since>=every;
    if(w.want)w.asked=true;
  }
  /// the whole field `field` came back (the `reads`th): every loaded
  /// tile's ground water soaked by the wetness over it, for the time since
  /// the last. Returns whether rain is falling over the loaded garden.
  pub fn soak(w:*Weather,world:*World,field:[]const u8,reads:u32)bool{
    if(reads==w.seen or field.len==0)return false;
    w.seen=reads;
    // how long this read soaks for
    const dt=@min(w.since,longest);
    w.since=0;
    w.asked=false;
    // whether rain is falling anywhere loaded
    var raining=false;
    var it=world.map.valueIterator();
    while(it.next())|cp|{
      // the chunk
      const c=cp.*;
      for(0..ck.tileCount)|t|{
        // the tile's place, and the field over its middle
        const wx,const wz=c.tileOf(t);
        const f=Volume.texelIn(field,.{m.f(wx)+0.5,m.f(wz)+0.5});
        // (past 1 the field's alpha is water pooled on wet-through ground)
        c.water[t]=soaked(c.water[t],c.waterCap[t],@min(f[3],1),dt);
        if(f[2]>firstRain)raining=true;
      }
    }
    return raining;
  }
};
/// a tile's ground water `water` (holding at most `cap`) after `dt` s under
/// ground `wet` (0 dry .. 1 wet through): soaked back up toward its cap, as
/// fast as it is wet; never past it, never drawn down
pub fn soaked(water:f32,cap:f32,wet:f32,dt:f32)f32{
  return water+@max(cap-water,0)*m.dampBy(wet/soakTime,dt);
}
/// the test helpers
const testing=std.testing;
test"rain soaks the ground back up to all it holds, never past it, and dry ground not at all"{
  // a tile drunk to half, under ground wet through
  var w:f32=0.4;
  for(0..60)|_|w=soaked(w,0.8,1,1);
  try testing.expectApproxEqAbs(0.8-0.4*@exp(@as(f32,-1)),w,1e-3);
  for(0..6000)|_|w=soaked(w,0.8,1,1);
  try testing.expect(w<=0.8 and w>0.799);
  // dry ground leaves it be; a tile over its cap is not drawn down
  try testing.expectEqual(@as(f32,0.3),soaked(0.3,0.8,0,5));
  try testing.expectEqual(@as(f32,0.9),soaked(0.9,0.8,1,5));
}
test"the field is asked for once a second of the world's time, not again until it comes back"{
  // the weather, a frozen world, then a moving one
  var w=Weather{};
  w.tick(0);
  try testing.expect(!w.want);
  w.tick(0.6);
  w.tick(0.6);
  try testing.expect(w.want);
  w.tick(2);
  try testing.expect(!w.want);
}
