//! day/night cycle and starfall. At night starlight motes drift down near the
//! player and hover over the ground until dawn burns them away.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../core/math.zig");
const Rng = @import("../core/rng.zig").Rng;
const World = @import("../world/world.zig").World;
const txt = @import("text.zig");

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
    if (e > SUN_ABOVE) return m.norm(m.v3(@cos(az) * 0.7, @max(e, 0.1) + 0.2, 0.35));
    return m.norm(m.v3(-@cos(az) * 0.5, -e + 0.3, -0.3));
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
const SPAWN_RATE:f32 = 2.5; // motes per second at full night
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

pub const Starfall = struct {
  motes:std.ArrayList(Mote) = .empty,
  acc:f32 = 0,
  rng:Rng,

  pub const MAX = 80;

  pub fn deinit(sf:*Starfall, gpa:Allocator) void { sf.motes.deinit(gpa); }

  /// motes land only on walkable tiles.
  pub fn update(sf:*Starfall, gpa:Allocator, sky:*const Sky, around:m.V3, ground:*const World, dt:f32) Allocator.Error!void {
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
};