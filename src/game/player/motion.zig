//! the wolf's motion each frame: gait stages, footsteps and the gathering pry.
const lib = @import("../../lib.zig");
const engine = lib.engine;
const m = engine.core.math;
const World = lib.world.World;
const skel = lib.skeleton;
const belly_mesh = lib.wolf_belly;
const V3 = m.V3;
const v3 = m.v3;
const Bone = skel.Bone;
const BELLY_ITEMS = lib.player.tuning.BELLY_ITEMS;
const BREATH_RATE = lib.player.tuning.BREATH_RATE;
const BREATH_RATE_RUN = lib.player.tuning.BREATH_RATE_RUN;
const CYCLE = lib.player.tuning.CYCLE;
const CYCLE_PER_SPEED = lib.player.tuning.CYCLE_PER_SPEED;
const DUTY_FAST = lib.player.tuning.DUTY_FAST;
const DUTY_SLOW = lib.player.tuning.DUTY_SLOW;
const FULLNESS_RESPONSE = lib.player.tuning.FULLNESS_RESPONSE;
const GAITS = lib.player.tuning.GAITS;
const GATHER_AT = lib.player.tuning.GATHER_AT;
const GRIP_SIDE = lib.player.tuning.GRIP_SIDE;
const GRIP_UP = lib.player.tuning.GRIP_UP;
const Gait = lib.player.tuning.Gait;
const HAND_DAMP = lib.player.tuning.HAND_DAMP;
const HAND_FREQ = lib.player.tuning.HAND_FREQ;
const LIFT = lib.player.tuning.LIFT;
const LIFT_ARC = lib.player.tuning.LIFT_ARC;
const LIFT_STRIDE = lib.player.tuning.LIFT_STRIDE;
const LOST = lib.player.tuning.LOST;
const MIN_DT = lib.player.tuning.MIN_DT;
const PAD_FREQ = lib.player.tuning_look.PAD_FREQ;
const PRY_BACK = lib.player.tuning.PRY_BACK;
const PRY_UP = lib.player.tuning.PRY_UP;
const Player = lib.player.player.Player;
const REACH_FREQ = lib.player.tuning.REACH_FREQ;
const REST_AFTER = lib.player.tuning.REST_AFTER;
const REST_FREQ = lib.player.tuning.REST_FREQ;
const REST_FULL = lib.player.tuning.REST_FULL;
const REST_FULL_IN = lib.player.tuning.REST_FULL_IN;
const SETTLE = lib.player.tuning.SETTLE;
const SETTLE_TIME = lib.player.tuning.SETTLE_TIME;
const SPRINT_SPEED = lib.player.tuning.SPRINT_SPEED;
const SQUAT_FREQ = lib.player.tuning.SQUAT_FREQ;
const STAGE_AT = lib.player.tuning.STAGE_AT;
const STAGE_BLEND = lib.player.tuning.STAGE_BLEND;
const STANDING = lib.player.tuning.STANDING;
const STOW_TIME = lib.player.tuning.STOW_TIME;
const STRIDE_RESPONSE = lib.player.tuning.STRIDE_RESPONSE;
const SWING_MAX = lib.player.tuning.SWING_MAX;
const SWING_MIN = lib.player.tuning.SWING_MIN;
const SWING_SPEED_MIN = lib.player.tuning.SWING_SPEED_MIN;
const TRAIL_MAX = lib.player.tuning.TRAIL_MAX;
const WALK_SPEED = lib.player.tuning.WALK_SPEED;
const pryPull = lib.player.ik.pryPull;

pub fn animate(p:*Player, ground:?*const World, dt:f32) void {
  p.t += dt;
  const spd = p.groundSpeed();
  const g = p.gait();
  const walk = WALK_SPEED * g.walk;
  const sprint = SPRINT_SPEED * g.sprint;
  p.stride += (m.clamp01(spd / walk) - p.stride) * @min(1, dt * STRIDE_RESPONSE);
  p.cycle = (CYCLE + CYCLE_PER_SPEED * spd) * g.stride;
  p.duty = m.lerp(DUTY_SLOW, DUTY_FAST, m.clamp01((spd - 1) / (sprint - 1)));
  p.phase = @mod(p.phase + spd / p.cycle * dt, 1);
  const effort = m.clamp01(spd / sprint);
  p.breath += dt * m.lerp(BREATH_RATE, BREATH_RATE_RUN, effort);

  p.fullness += (p.bellyFill() - p.fullness) * @min(1, dt * FULLNESS_RESPONSE);
  p.reach.to(if (p.work != null) 1 else 0, REACH_FREQ, 1, dt);
  p.pry(dt);
  p.still = if (p.stride < STANDING and p.work == null and p.gather == null) p.still + dt else 0;
  const heavy = m.smooth(m.clamp01((p.fullness - REST_FULL) / (REST_FULL_IN - REST_FULL)));
  p.rest_pose.to(if (p.still > REST_AFTER) heavy else 0, REST_FREQ, 1, dt);

  // what the body feels: its acceleration, turned into its own frame
  const a = (p.vel - p.last_vel) / m.splat3(@max(dt, MIN_DT));
  p.last_vel = p.vel;
  const al = m.mulV(m.rotY(-p.facing), .{ a[0], a[1], a[2], 0 });
  p.accel = v3(al[0], al[1], al[2]);

  const fell = p.step(ground, spd, dt);
  p.slosh(fell, dt);
  p.springs(dt);
}

/// which of the belly's stages the wolf is in: 0 light .. 1 heavy .. 2
/// full, blending over `STAGE_BLEND` about each threshold
pub fn stage(p:*const Player) f32 {
  var out:f32 = 0;
  for (STAGE_AT) |at| out += m.smooth(m.clamp01((p.fullness - at) / STAGE_BLEND + 0.5));
  return out;
}

/// the gait for the belly's load (`GAITS` blended by `stage`)
pub fn gait(p:*const Player) Gait {
  const st = p.stage();
  const i:usize = if (st >= 1) 1 else 0;
  const k = st - m.f(i);
  const a = GAITS[i];
  const b = GAITS[i + 1];
  var out:Gait = undefined;
  inline for (@typeInfo(Gait).@"struct".fields) |fl| @field(out, fl.name) = m.lerp(@field(a, fl.name), @field(b, fl.name), k);
  return out;
}

/// how full the belly is to look at (0..1) for what it holds
pub fn bellyFill(p:*const Player) f32 { return 1 - @exp(-m.f(p.inv.total()) / BELLY_ITEMS); }

/// the feet: plant, lift, swing to where they are wanted. Returns whether
/// one came down this frame.
pub fn step(p:*Player, ground:?*const World, spd:f32, dt:f32) bool {
  if (!p.placed) {
    for (&p.feet, 0..) |*f, s| f.at = p.rest(ground, s);
    p.placed = true;
  }
  const moving = p.stride > STANDING;
  // how far ahead of the hip a foot lands, so it passes under the hip
  // mid-stance
  const ahead = if (spd > 0.1) p.vel / m.splat3(spd) * m.splat3(p.duty * p.cycle * 0.5 * m.clamp01(spd / 1.5)) else v3(0, 0, 0);
  var fell = false;
  for (&p.feet, 0..) |*f, s| {
    const other = &p.feet[1 - s];
    if (m.len(f.at - p.rest(ground, s)) > LOST) {
      f.* = .{ .at = p.rest(ground, s), .phase = f.phase };
      continue;
    }
    const ph = @mod(p.phase + 0.5 * m.f(s), 1);
    if (f.planted()) {
      const off = m.len(f.at - p.rest(ground, s));
      // a foot trailing too far always lifts (the other one is down by then)
      var lift = off > TRAIL_MAX and other.planted();
      if (moving) {
        // the gait lifts it as its stance ends
        lift = lift or (ph >= p.duty and f.phase < p.duty);
      } else {
        // standing, a foot left behind steps back under (one at a time)
        lift = lift or (other.planted() and off > SETTLE and off >= m.len(other.at - p.rest(ground, 1 - s)));
      }
      if (lift) {
        f.from = f.at;
        f.t = 0;
        f.dur = if (moving) m.clamp((1 - p.duty) * p.cycle / @max(spd, SWING_SPEED_MIN), SWING_MIN, SWING_MAX) else SETTLE_TIME;
        f.lift = (LIFT + LIFT_STRIDE * p.stride) * p.gait().lift;
      }
    }
    f.phase = ph;
    if (!f.planted()) {
      f.t = @min(1, f.t + dt / f.dur);
      const left = (1 - f.t) * f.dur;
      const to = p.onGround(ground, p.rest(ground, s) + p.vel * m.splat3(left) + ahead);
      const k = m.smooth(f.t);
      f.at = m.lerpV(f.from, to, k);
      f.at[1] = m.lerp(f.from[1], to[1], k) + f.lift * m.pow(f32, @sin(f.t * m.pi), LIFT_ARC);
      if (f.planted()) {
        f.at[1] = to[1];
        fell = true;
        p.fell[s] = .{.weight = p.stage() / 2, .pace = m.clamp01(spd / (SPRINT_SPEED * p.gait().sprint))};
      }
    }
    m.spring(&f.pad, &f.pad_v, if (f.planted()) 1 else 0, PAD_FREQ, dt);
  }
  return fell;
}

/// gathering: the squat eases in and out, each unit come loose sends a
/// paw (one, then the other) to the belly, and the wrists chase where the
/// pry wants them
pub fn pry(p:*Player, dt:f32) void {
  p.squat.to(if (p.gather != null) 1 else 0, SQUAT_FREQ, 1, dt);
  for (&p.stow) |*t| t.* = @max(t.* - dt, 0);
  const k = p.gather orelse {
    p.last_pry = 0;
    return;
  };
  if (k < p.last_pry and p.squat.x > 0.5) {
    p.stow[p.next_stow] = STOW_TIME;
    p.next_stow +%= 1;
  }
  p.last_pry = k;
  const q = p.pose();
  for (&p.wrist, 0..) |*w, s| {
    const want = p.wristWant(q, s, k);
    // just crouching, the wrists start where they are wanted
    if (p.squat.x < 0.02) w.* = .{ .pos = want };
    m.springDamper(&w.pos, &w.vel, want, HAND_FREQ * HAND_FREQ, 2 * HAND_DAMP * HAND_FREQ, 1, v3(0, 0, 0), dt);
  }
}

/// where wrist `s` is wanted (wolf space) at unit share `k`: on the node,
/// pulled back and up through the pry, or at the belly while stowing
pub fn wristWant(p:*const Player, q:skel.Pose, s:usize, k:f32) V3 {
  const node = p.workLocal();
  const x = skel.sign(s);
  const pull = pryPull(k);
  const grip = node + v3(x * GRIP_SIDE, GRIP_UP + PRY_UP * pull, -PRY_BACK * pull);
  const stow = m.smooth(m.clamp01(@sin(p.stow[s] / STOW_TIME * m.pi) * 1.6));
  if (stow <= 0) return grip;
  const w = skel.fk(q);
  const belly = m.mulPoint(w[@intFromEnum(Bone.gut)], v3(x * belly_mesh.RX * 0.3, belly_mesh.DOWN * 0.15, belly_mesh.RZ * 1.15));
  return m.lerpV(grip, belly, stow);
}

/// the node worked on, in the wolf's own frame (a little ahead without one)
pub fn workLocal(p:*const Player) V3 {
  const at = p.work orelse return v3(0, 0, GATHER_AT);
  const l = m.mulV(m.inverseRigid(p.heading()), .{ at[0], at[1], at[2], 1 });
  return v3(l[0], l[1], l[2]);
}
