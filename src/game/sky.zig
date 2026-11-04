//! the day and night cycle. Starlight is gathered from the stars on the
//! starlit patches (game/starlight.zig), never fallen. The unforming
//! shifts the sky for good (`Sky.shift`): it turns the ley's violet,
//! glowing, its sun and moon gone, the glow's own turning the only tell
//! of day and night.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the test harness
const testing=std.testing;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, angles, easing
const m=engine.core.math;
/// every player-facing string, for the time of day's name
const txt=lib.txt;
/// seconds per full day/night cycle
pub const dayLen:f32=600;
/// the game starts mid-morning
const startTod:f32=0.3;
/// daylight rises from sun elevation `dawnAt` over `dawnSpan`
const dawnAt:f32=-0.12;
/// how far above `dawnAt` the sun climbs before daylight is full
const dawnSpan:f32=0.35;
/// the sun keys the light above this elevation, the moon below
const sunAbove:f32=-0.08;
/// dusk glows within this elevation of the horizon
const duskBand:f32=0.25;
/// how strong the dusk glow is at its most
const duskGlow:f32=0.8*0.6;
/// dawn and dusk are named within this elevation of the horizon
const twilightBand:f32=0.15;
/// the key light's direction: the sun swings this far east-west
/// (the moon likewise, by its own constants)
const sunSwing:f32=0.7;
/// the least elevation the sun's light keys from, before `sunLift`
const sunLow:f32=0.1;
/// how much higher than its elevation the sun's light keys from
const sunLift:f32=0.2;
/// how far south the sun's light leans
const sunLean:f32=0.35;
/// how far east-west the moon swings
const moonSwing:f32=0.5;
/// how much higher than its depth the moon's light keys from
const moonLift:f32=0.3;
/// how far north the moon's light leans
const moonLean:f32=-0.3;
/// the sky's colours at the horizon (linear; the haze takes them too, and
/// the dome deepens up from them to its zenith, sky.frag OLD_ZENITH_*):
/// night, a deep violet (the gardener's word: like a real night sky,
/// vibrant hues coming through, never milky)
const nightSky=m.Vice(f32,3){0.011,0.005,0.034};
/// a plain day: saturated, with a dash of cyan, the light's beams showing against it
const daySky=m.Vice(f32,3){0.035,0.15,0.3};
/// a day veiled by the world event: a little violet
const veiledSky=m.Vice(f32,3){0.2,0.12,0.38};
/// the dusk glow near the horizon
const duskSky=m.Vice(f32,3){0.32,0.13,0.08};
/// the shifted sky (after the unforming), the ley's glow: by night, a deep
/// blue violet
const leyNight=m.Vice(f32,3){0.03,0.02,0.09};
/// by day, a rose violet
const leyDay=m.Vice(f32,3){0.24,0.1,0.4};
/// the shifted sky's key light circles this far off the zenith (its glow
/// overhead, no sun to swing it)
const leyLean:f32=0.3;
/// the fog and the horizon turn to the ley's colour over this stretch of
/// the shift (0..1), as the old sky's shattering sweeps down the dome to
/// the horizon (sky.frag FRONT_FROM, FRONT_SPAN)
const fogFrom:f32=0.15;
/// how much of the shift that takes
const fogSpan:f32=0.35;
/// the sky's clock: the time of day, which lights, colours and names it
pub const Sky=struct{
  /// time of day 0..1 (0 midnight, 0.5 noon)
  tod:f32=startTod,
  /// how far the unforming has shifted it, 0 the old sky .. 1 the ley's for
  /// good (set each tick from the event, not saved)
  shift:f32=0,
  /// moves the clock on by `dt` seconds, wrapping at a full day
  pub fn update(s:*Sky,dt:f32)void{s.tod=@mod(s.tod+dt/dayLen,1);}
  /// sun elevation -1..1
  pub fn elevation(s:*const Sky)f32{return-@cos(s.tod*m.tau);}
  /// how much daylight there is, 0..1 (eased in round dawn)
  pub fn daylight(s:*const Sky)f32{return m.smooth(m.clamp01((s.elevation()-dawnAt)/dawnSpan));}
  /// direction toward the key light: the sun by day, a cool moon by night;
  /// once shifted, the glow overhead, circling slowly with the day
  pub fn lightDir(s:*const Sky)m.V3{
    // the clock as an angle, and the sun's elevation
    const az=s.tod*m.tau;
    const e=s.elevation();
    // the old sky's key light
    const old=if(e>sunAbove)m.norm(m.v3(@cos(az)*sunSwing,@max(e,sunLow)+sunLift,sunLean))
      else m.norm(m.v3(-@cos(az)*moonSwing,-e+moonLift,moonLean));
    if(s.shift<=0)return old;
    // the shifted sky's: its glow overhead
    const glow=m.norm(m.v3(@cos(az)*leyLean,1,@sin(az)*leyLean));
    return m.norm(old+(glow-old)*m.splat3(m.smooth(s.shift)));
  }
  /// linear sky/fog colour, with dusk glow near the horizon.
  /// `veil` blends the day colour toward the celestial palette (0..1);
  /// the shift turns it all to the ley's glow, rose by day, deep by night
  pub fn color(s:*const Sky,veil:f32)m.Vice(f32,3){
    // daylight, and the sun's elevation
    const d=s.daylight();
    const e=s.elevation();
    // how much the dusk glows, near the horizon
    const dusk=m.clamp01(1-@abs(e)/duskBand)*duskGlow;
    // how far it has shifted, at the horizon
    const sh=m.smooth(m.clamp01((s.shift-fogFrom)/fogSpan));
    // the colour, built channel by channel
    var o:m.Vice(f32,3)=undefined;
    inline for(0..3)|i|o[i]=m.lerp(m.lerp(m.lerp(nightSky[i],m.lerp(daySky[i],veiledSky[i],veil),d),duskSky[i],dusk),m.lerp(leyNight[i],leyDay[i],d),sh);
    return o;
  }
  /// the time of day's name: dawn or dusk near the horizon, else day or night
  pub fn name(s:*const Sky)[]const u8{
    // the sun's elevation
    const e=s.elevation();
    if(@abs(e)<twilightBand)return if(s.tod<0.5)txt.s.sky.dawn else txt.s.sky.dusk;
    return if(e>0)txt.s.sky.day else txt.s.sky.night;
  }
};
test"the shifted sky is the ley's, with no sun to key it"{
  // noon, the old sky and the shifted one
  const old:Sky=.{.tod=0.5};
  const shifted:Sky=.{.tod=0.5,.shift=1};
  try testing.expect(shifted.color(0)[2]>shifted.color(0)[1]*2);
  try testing.expect(shifted.lightDir()[1]>0.9 and old.color(0)[0]<shifted.color(0)[0]);
}
