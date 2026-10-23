//! day/night cycle and starfall. At night starlight motes drift down near the
//! player and hover over the ground until dawn burns them away.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../core/math.zig");
const Rng = @import("../core/rng.zig").Rng;
const World = @import("../world/world.zig").World;

/// seconds per full day/night cycle
pub const DAY_LEN:f32 = 300;

pub const Sky = struct {
  /// time of day 0..1 (0 midnight, 0.5 noon)
  tod:f32 = 0.3,

  pub fn update(s:*Sky, dt:f32) void { s.tod = @mod(s.tod + dt / DAY_LEN, 1); }

  /// sun elevation -1..1
  pub fn elevation(s:*const Sky) f32 { return -@cos(s.tod * m.tau); }
  pub fn daylight(s:*const Sky) f32 { return m.smooth(m.clamp01((s.elevation() + 0.12) / 0.35)); }

  /// direction toward the key light: the sun by day, a cool moon by night.
  pub fn lightDir(s:*const Sky) m.V3 {
    const az = s.tod * m.tau;
    const e = s.elevation();
    if (e > -0.08) return m.norm(m.v3(@cos(az) * 0.7, @max(e, 0.1) + 0.2, 0.35));
    return m.norm(m.v3(-@cos(az) * 0.5, -e + 0.3, -0.3));
  }

  /// linear sky/fog colour, with dusk glow near the horizon.
  /// `veil` blends the day colour toward the celestial palette (0..1).
  pub fn color(s:*const Sky, veil:f32) [3]f32 {
    const d = s.daylight();
    const e = s.elevation();
    const dusk = m.clamp01(1 - @abs(e) / 0.25) * 0.8;
    const night = [3]f32{ 0.008, 0.01, 0.028 };
    const day = [3]f32{ m.lerp(0.16, 0.2, veil), m.lerp(0.22, 0.12, veil), m.lerp(0.32, 0.38, veil) };
    const glow = [3]f32{ 0.32, 0.13, 0.08 };
    var o:[3]f32 = undefined;
    inline for (0..3) |i| o[i] = m.lerp(m.lerp(night[i], day[i], d), glow[i], dusk * 0.6);
    return o;
  }

  pub fn name(s:*const Sky) []const u8 {
    const e = s.elevation();
    if (@abs(e) < 0.15) return if (s.tod < 0.5) "DAWN" else "DUSK";
    return if (e > 0) "DAY" else "NIGHT";
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
const BURN_BELOW:f32 = 0.4; // daylight below this, motes start burning away
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
    if (night > 0.6 and sf.motes.items.len < MAX) {
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
      const rest = h + REST_HOVER + HOVER_AMP * @sin(mo.phase * 40 + mo.pos[0]);
      mo.falling = mo.pos[1] > rest + 0.05;
      if (mo.pos[1] > rest) {
        mo.pos[1] = @max(rest, mo.pos[1] + mo.vy * dt);
        mo.pos[0] += @sin(mo.phase * 20 + mo.pos[1]) * DRIFT * dt;
      } else mo.pos[1] += (rest - mo.pos[1]) * @min(1, dt * LAND_EASE);
      if (night < BURN_BELOW) mo.life -= dt * BURN_RATE;
      if (mo.life <= 0) { _ = sf.motes.swapRemove(i); continue; }
      i += 1;
    }
  }
};