//! day/night cycle and starfall. At night starlight motes drift down near the
//! player and hover over the ground until dawn burns them away.
const lib = @import("../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const engine = lib.engine;
const m = engine.core.math;
const Rng = engine.core.rng.Rng;
const World = lib.world.World;
const txt = lib.txt;

/// seconds per full day/night cycle
pub const DAY_LEN:f32 = 300;
/// the game starts mid-morning
const START_TOD:f32 = 0.3;
/// daylight rises from sun elevation `DAWN_AT` over `DAWN_SPAN`
const DAWN_AT:f32 = -0.12;
const DAWN_SPAN:f32 = 0.35;
/// the sun keys the light above this elevation, the moon below
const SUN_ABOVE:f32 = -0.08;
/// dusk glows within this elevation of the horizon, at most this strong
const DUSK_BAND:f32 = 0.25;
const DUSK_GLOW:f32 = 0.8 * 0.6;
/// dawn and dusk are named within this elevation of the horizon
const TWILIGHT_BAND:f32 = 0.15;
/// the key light's direction: the sun swings this far east-west, rises at
/// least `SUN_LOW` plus `SUN_LIFT` and leans this far south; the moon likewise
const SUN_SWING:f32 = 0.7;
const SUN_LOW:f32 = 0.1;
const SUN_LIFT:f32 = 0.2;
const SUN_LEAN:f32 = 0.35;
const MOON_SWING:f32 = 0.5;
const MOON_LIFT:f32 = 0.3;
const MOON_LEAN:f32 = -0.3;
/// sky colours (linear): night, day plain and veiled, dusk glow
const NIGHT_SKY = [3]f32{ 0.008, 0.01, 0.028 };
const DAY_SKY = [3]f32{ 0.16, 0.22, 0.32 };
const VEILED_SKY = [3]f32{ 0.2, 0.12, 0.38 };
const DUSK_SKY = [3]f32{ 0.32, 0.13, 0.08 };

pub const Sky = struct {
  /// time of day 0..1 (0 midnight, 0.5 noon)
  tod:f32 = START_TOD,

  pub fn update(s:*Sky, dt:f32) void { s.tod = @mod(s.tod + dt / DAY_LEN, 1); }

  /// sun elevation -1..1
  pub fn elevation(s:*const Sky) f32 { return -@cos(s.tod * m.tau); }
  pub fn daylight(s:*const Sky) f32 { return m.smooth(m.clamp01((s.elevation() - DAWN_AT) / DAWN_SPAN)); }

  /// direction toward the key light: the sun by day, a cool moon by night.
  pub fn lightDir(s:*const Sky) m.V3 {
    const az = s.tod * m.tau;
    const e = s.elevation();
    if (e > SUN_ABOVE) return m.norm(m.v3(@cos(az) * SUN_SWING, @max(e, SUN_LOW) + SUN_LIFT, SUN_LEAN));
    return m.norm(m.v3(-@cos(az) * MOON_SWING, -e + MOON_LIFT, MOON_LEAN));
  }

  /// linear sky/fog colour, with dusk glow near the horizon.
  /// `veil` blends the day colour toward the celestial palette (0..1).
  pub fn color(s:*const Sky, veil:f32) [3]f32 {
    const d = s.daylight();
    const e = s.elevation();
    const dusk = m.clamp01(1 - @abs(e) / DUSK_BAND) * DUSK_GLOW;
    var o:[3]f32 = undefined;
    inline for (0..3) |i| o[i] = m.lerp(m.lerp(NIGHT_SKY[i], m.lerp(DAY_SKY[i], VEILED_SKY[i], veil), d), DUSK_SKY[i], dusk);
    return o;
  }

  pub fn name(s:*const Sky) []const u8 {
    const e = s.elevation();
    if (@abs(e) < TWILIGHT_BAND) return if (s.tod < 0.5) txt.s.sky.dawn else txt.s.sky.dusk;
    return if (e > 0) txt.s.sky.day else txt.s.sky.night;
  }
};

pub const Mote = struct {
  pos:m.V3,
  vy:f32,
  life:f32 = 1,
  phase:f32,
  /// still falling (it trails light) rather than resting over the ground
  falling:bool = true,
};

/// starfall tuning (tune here, not scattered through update)
const SPAWN_RATE:f32 = 0.9; // motes per second at full night
const SPAWN_R_MIN:f32 = 2;
const SPAWN_R_MAX:f32 = 16;
const SPAWN_HEIGHT:f32 = 7; // how far above ground they start
const FALL_MIN:f32 = 0.8;
const FALL_MAX:f32 = 1.6;
const REST_HOVER:f32 = 0.35; // how far above ground they rest
const HOVER_AMP:f32 = 0.08;  // vertical bob amplitude while resting
const DRIFT:f32 = 0.3; // horizontal sway speed while falling
const LAND_EASE:f32 = 3; // how quickly they settle onto the rest height
const SPAWN_NIGHT:f32 = 0.6; // night deeper than this, stars fall
const FALLING_ABOVE:f32 = 0.05; // above rest by this much, a mote still trails
/// phase rates of the rest bob and the falling sway
const HOVER_RATE:f32 = 40;
const DRIFT_RATE:f32 = 20;
const BURN_BELOW:f32 = 0.4; // night below this, motes start burning away
const BURN_RATE:f32 = 0.4; // life lost per second while burning
/// a mote within this (m) of the wolf twinkles now and then: seconds
/// between twinkles (a gap with none near passes silent)
const TWINKLE_NEAR:f32 = 6;
const TWINKLE_GAP = [2]f32{ 2.5, 8 };

/// a mote near the wolf twinkled, for what hears it (game/sound.zig): how
/// near (0 at `TWINKLE_NEAR` .. 1 touching)
pub const Twinkle = struct { near:f32 };

pub const Starfall = struct {
  motes:std.ArrayList(Mote) = .empty,
  acc:f32 = 0,
  rng:Rng,
  /// seconds until a near mote may twinkle, and one since `twinkled` last took it
  quiet:f32 = 0,
  twinkle:?Twinkle = null,

  pub const MAX = 80;

  pub fn deinit(sf:*Starfall, gpa:Allocator) void { sf.motes.deinit(gpa); }

  /// the twinkle since last asked, once
  pub fn twinkled(sf:*Starfall) ?Twinkle {
    defer sf.twinkle = null;
    return sf.twinkle;
  }

  /// motes land only on walkable tiles.
  pub fn update(sf:*Starfall, gpa:Allocator, sky:*const Sky, around:m.V3, ground:*const World, dt:f32) Allocator.Error!void {
    sf.listen(around, dt);
    const night = 1 - sky.daylight();
    if (night > SPAWN_NIGHT and sf.motes.items.len < MAX) {
      sf.acc += dt * SPAWN_RATE * night;
      while (sf.acc >= 1) : (sf.acc -= 1) {
        const a = sf.rng.range(0, m.tau);
        const r = sf.rng.range(SPAWN_R_MIN, SPAWN_R_MAX);
        const x = around[0] + @cos(a) * r;
        const z = around[2] + @sin(a) * r;
        const h = ground.walkable(m.tileOf(x), m.tileOf(z)) orelse continue;
        try sf.motes.append(gpa, .{ .pos = m.v3(x, h + SPAWN_HEIGHT, z), .vy = -sf.rng.range(FALL_MIN, FALL_MAX), .phase = sf.rng.float() });
      }
    }
    var i:usize = 0;
    while (i < sf.motes.items.len) {
      const mo = &sf.motes.items[i];
      const h = ground.walkable(m.tileOf(mo.pos[0]), m.tileOf(mo.pos[2])) orelse mo.pos[1];
      const rest = h + REST_HOVER + HOVER_AMP * @sin(mo.phase * HOVER_RATE + mo.pos[0]);
      mo.falling = mo.pos[1] > rest + FALLING_ABOVE;
      if (mo.pos[1] > rest) {
        mo.pos[1] = @max(rest, mo.pos[1] + mo.vy * dt);
        mo.pos[0] += @sin(mo.phase * DRIFT_RATE + mo.pos[1]) * DRIFT * dt;
      } else mo.pos[1] += (rest - mo.pos[1]) * @min(1, dt * LAND_EASE);
      if (night < BURN_BELOW) mo.life -= dt * BURN_RATE;
      if (mo.life <= 0) { _ = sf.motes.swapRemove(i); continue; }
      i += 1;
    }
  }

  /// after a quiet gap, the nearest mote within reach twinkles
  fn listen(sf:*Starfall, around:m.V3, dt:f32) void {
    sf.quiet -= dt;
    if (sf.quiet > 0) return;
    sf.quiet = sf.rng.range(TWINKLE_GAP[0], TWINKLE_GAP[1]);
    var nearest:f32 = TWINKLE_NEAR;
    for (sf.motes.items) |mo| nearest = @min(nearest, m.len(mo.pos - around) * mo.life + TWINKLE_NEAR * (1 - mo.life));
    if (nearest < TWINKLE_NEAR) sf.twinkle = .{ .near = 1 - nearest / TWINKLE_NEAR };
  }
};

test "a near mote twinkles now and then, a far one never" {
  var sf:Starfall = .{ .rng = Rng.init(7) };
  defer sf.deinit(testing.allocator);
  try sf.motes.append(testing.allocator, .{ .pos = m.v3(20, 0, 0), .vy = 0, .phase = 0 });
  const here = m.v3(0, 0, 0);
  var heard:u32 = 0;
  // a minute at 60 frames a second
  for (0..3600) |_| {
    sf.listen(here, 1.0 / 60.0);
    if (sf.twinkled() != null) heard += 1;
  }
  try testing.expectEqual(@as(u32, 0), heard);
  sf.motes.items[0].pos = m.v3(2, 0, 0);
  for (0..3600) |_| {
    sf.listen(here, 1.0 / 60.0);
    if (sf.twinkled()) |t| {
      heard += 1;
      try testing.expect(t.near > 0.5 and t.near < 0.8);
    }
  }
  try testing.expect(heard >= 6 and heard <= 25);
}