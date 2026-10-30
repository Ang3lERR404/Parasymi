//! the wolf's springs: arms, lean, head, ears, tail and the sloshing belly.
const lib = @import("../../lib.zig");
const engine = lib.engine;
const m = engine.core.math;
const noise = engine.core.noise;
const skel = lib.skeleton;
const belly_mesh = lib.wolf_belly;
const v3 = m.v3;
const ARM_DAMP = lib.player.tuning.ARM_DAMP;
const ARM_FREQ = lib.player.tuning.ARM_FREQ;
const ARM_SWING = lib.player.tuning.ARM_SWING;
const BANK = lib.player.tuning.BANK;
const BANK_DAMP = lib.player.tuning.BANK_DAMP;
const BANK_MAX = lib.player.tuning.BANK_MAX;
const BELLY_ROOM = lib.player.tuning_look.BELLY_ROOM;
const BELLY_ROOM_MIN = lib.player.tuning_look.BELLY_ROOM_MIN;
const CURL_FLEX = lib.player.tuning_look.CURL_FLEX;
const CURL_REST = lib.player.tuning_look.CURL_REST;
const CURL_SWING = lib.player.tuning_look.CURL_SWING;
const DIG = lib.player.tuning.DIG;
const DIG_DEPTH = lib.player.tuning.DIG_DEPTH;
const DIG_RATE = lib.player.tuning.DIG_RATE;
const EAR_BACK = lib.player.tuning_look.EAR_BACK;
const EAR_DAMP = lib.player.tuning_look.EAR_DAMP;
const EAR_FLICK = lib.player.tuning_look.EAR_FLICK;
const EAR_FLICK_EVERY = lib.player.tuning_look.EAR_FLICK_EVERY;
const EAR_FREQ = lib.player.tuning_look.EAR_FREQ;
const ELBOW_REST = lib.player.tuning.ELBOW_REST;
const ELBOW_SWING = lib.player.tuning.ELBOW_SWING;
const FINGER_DAMP = lib.player.tuning_look.FINGER_DAMP;
const FINGER_FREQ = lib.player.tuning_look.FINGER_FREQ;
const FLEX_LAG = lib.player.tuning_look.FLEX_LAG;
const FLEX_RATE = lib.player.tuning_look.FLEX_RATE;
const FLEX_WAVE = lib.player.tuning_look.FLEX_WAVE;
const GAZE_NOD = lib.player.tuning.GAZE_NOD;
const GAZE_NOD_DOWN = lib.player.tuning.GAZE_NOD_DOWN;
const GAZE_NOD_UP = lib.player.tuning.GAZE_NOD_UP;
const GRIP_CLOSE = lib.player.tuning_look.GRIP_CLOSE;
const GRIP_LAG = lib.player.tuning_look.GRIP_LAG;
const GRIP_OPEN = lib.player.tuning_look.GRIP_OPEN;
const HEAD_DAMP = lib.player.tuning.HEAD_DAMP;
const HEAD_FREQ = lib.player.tuning.HEAD_FREQ;
const LEAN_ACCEL = lib.player.tuning.LEAN_ACCEL;
const LEAN_DAMP = lib.player.tuning.LEAN_DAMP;
const LEAN_FREQ = lib.player.tuning.LEAN_FREQ;
const LEAN_MAX = lib.player.tuning.LEAN_MAX;
const LEAN_STRIDE = lib.player.tuning.LEAN_STRIDE;
const LEAN_WORK = lib.player.tuning.LEAN_WORK;
const LOOK_IDLE = lib.player.tuning.LOOK_IDLE;
const LOOK_IDLE_RATE = lib.player.tuning.LOOK_IDLE_RATE;
const LOOK_MAX = lib.player.tuning.LOOK_MAX;
const LOOK_TURN = lib.player.tuning.LOOK_TURN;
const LOOK_WORK = lib.player.tuning.LOOK_WORK;
const LUMP_R = lib.player.tuning_look.LUMP_R;
const PEC_C = lib.player.tuning_look.PEC_C;
const PEC_K = lib.player.tuning_look.PEC_K;
const PEC_MASS = lib.player.tuning_look.PEC_MASS;
const PEC_MAX = lib.player.tuning_look.PEC_MAX;
const PRY_GRIP = lib.player.tuning.PRY_GRIP;
const Player = lib.player.player.Player;
const REST_FIST = lib.player.tuning.REST_FIST;
const REST_FLAT = lib.player.tuning.REST_FLAT;
const RUMP_C = lib.player.tuning_look.RUMP_C;
const RUMP_K = lib.player.tuning_look.RUMP_K;
const RUMP_KICK = lib.player.tuning_look.RUMP_KICK;
const RUMP_MAX = lib.player.tuning_look.RUMP_MAX;
const SLOSH = lib.player.tuning_look.SLOSH;
const SPREAD_DAMP = lib.player.tuning_look.SPREAD_DAMP;
const SPREAD_OPEN = lib.player.tuning_look.SPREAD_OPEN;
const SPREAD_SHUT = lib.player.tuning_look.SPREAD_SHUT;
const STEP_KICK = lib.player.tuning_look.STEP_KICK;
const STOW_CUP = lib.player.tuning.STOW_CUP;
const STOW_TIME = lib.player.tuning.STOW_TIME;
const TAIL_DAMP = lib.player.tuning_look.TAIL_DAMP;
const TAIL_FREQ = lib.player.tuning_look.TAIL_FREQ;
const TAIL_FREQ_STEP = lib.player.tuning_look.TAIL_FREQ_STEP;
const TAIL_GAIT = lib.player.tuning_look.TAIL_GAIT;
const TAIL_IDLE = lib.player.tuning_look.TAIL_IDLE;
const TAIL_IDLE_RATE = lib.player.tuning_look.TAIL_IDLE_RATE;
const TAIL_TURN = lib.player.tuning_look.TAIL_TURN;
const TAIL_TURN_MAX = lib.player.tuning_look.TAIL_TURN_MAX;
const WRENCH_END = lib.player.tuning.WRENCH_END;
const lumps = lib.player.tuning_look.lumps;

/// what lags on springs: lean and bank, arms, head, ears, tail
pub fn springs(p:*Player, dt:f32) void {
  const st = p.stride;
  // the generic gesture gives way to the gathering pose
  const work = p.reach.x * (1 - p.squat.x);
  p.lean.to(m.clamp(LEAN_STRIDE * st + p.accel[2] * LEAN_ACCEL, -LEAN_MAX, LEAN_MAX) + LEAN_WORK * work, LEAN_FREQ, LEAN_DAMP, dt);
  p.bank.to(m.clamp(-p.turn * BANK * st, -BANK_MAX, BANK_MAX), LEAN_FREQ, BANK_DAMP, dt);
  for (0..2) |s| {
    // each arm swings with the opposite leg: back as its own leg comes forward
    const ph = @mod(p.phase + 0.5 * m.f(s), 1);
    const swing = @sin(ph * m.tau + m.half_pi) * ARM_SWING * st;
    const dig = DIG + @sin(p.t * DIG_RATE + m.f(s) * 1.7) * DIG_DEPTH;
    p.arm[s].to(m.lerp(swing, dig, work), ARM_FREQ, ARM_DAMP, dt);
    p.elbow[s].to(ELBOW_REST + ELBOW_SWING * st * m.clamp01(-p.arm[s].x * 2) + 0.7 * work, ARM_FREQ, ARM_DAMP, dt);
    // ears lie back with speed and flick now and then, one, then the other
    const due = @mod(p.t + m.f(s) * 1.3, EAR_FLICK_EVERY) < dt and noise.grad(0xEA2 +% s, p.t * 0.7, 0.5) > 0;
    if (due) p.ear[s].v += EAR_FLICK;
    p.ear[s].to(-EAR_BACK * st, EAR_FREQ, EAR_DAMP, dt);
  }
  const idle = (1 - st) * (1 - work);
  for (&p.curl, &p.spread, 0..) |*hand, *spread, s| {
    const flex = m.clamp01(noise.grad(0xF1C +% s, p.t * FLEX_RATE, 0.5) * 2);
    const stroke = p.t * DIG_RATE + m.f(s) * 1.7 - 0.6;
    var sum:f32 = 0;
    for (hand, 0..) |*c, i| {
      const fi = m.f(i);
      var target = CURL_REST + CURL_SWING * st * m.clamp01(-p.arm[s].x * 1.5);
      target += CURL_FLEX * idle * flex * m.clamp01(@sin(p.t * FLEX_WAVE - fi * FLEX_LAG + m.f(s) * 2.1));
      const rake = 0.5 + 0.5 * @sin(stroke - fi * GRIP_LAG);
      target = m.lerp(target, m.lerp(GRIP_OPEN, GRIP_CLOSE, rake), work);
      // gathering: shut on the node, opening as the paw comes back to it,
      // cupped round a unit on its way to the belly
      const k = p.gather orelse 0;
      const regrip = 1 - m.smooth(m.clamp01((k - WRENCH_END) / (1 - WRENCH_END) * 2)) * m.smooth(m.clamp01((1 - k) * 8));
      const hold = m.lerp(GRIP_OPEN, PRY_GRIP, regrip);
      const cup = m.clamp01(p.stow[s] / STOW_TIME * 4);
      target = m.lerp(target, m.lerp(hold, STOW_CUP, cup), p.squat.x);
      // resting: the paw on the belly lies flat, the one on the hip curls
      target = m.lerp(target, if (s == 1) REST_FLAT else REST_FIST, p.rest_pose.x * (1 - p.squat.x));
      c.to(target, FINGER_FREQ, FINGER_DAMP, dt);
      sum += c.x;
    }
    const shut = m.clamp01(sum / (skel.FINGERS * GRIP_CLOSE));
    spread.to(m.lerp(SPREAD_OPEN, SPREAD_SHUT, shut), FINGER_FREQ, SPREAD_DAMP, dt);
  }
  var look = m.clamp(p.turn * LOOK_TURN, -LOOK_MAX, LOOK_MAX) + LOOK_IDLE * idle * noise.grad(0x100C, p.t * LOOK_IDLE_RATE, 0.5);
  var nod = LOOK_WORK * (work + p.squat.x) + 0.12 * idle * noise.grad(0x40D, p.t * LOOK_IDLE_RATE, 3.5);
  // seen from its own eyes, the head looks where they do, ahead of the
  // body still turning to them, and nods up and down with them
  if (p.aim) |a| look = m.clamp(m.angleDiff(p.facing, a), -LOOK_MAX, LOOK_MAX);
  if (p.gaze) |up| nod = m.clamp(-up * GAZE_NOD, GAZE_NOD_UP, GAZE_NOD_DOWN) + LOOK_WORK * (work + p.squat.x);
  p.look.to(look, HEAD_FREQ, HEAD_DAMP, dt);
  p.nod.to(nod, HEAD_FREQ, HEAD_DAMP, dt);
  // tail: each joint chases the one before it, steered by turning and gait
  var target = m.clamp(-p.turn * TAIL_TURN, -TAIL_TURN_MAX, TAIL_TURN_MAX) + @sin(p.t * TAIL_IDLE_RATE) * TAIL_IDLE * (1 - st) + @sin(p.phase * m.tau) * TAIL_GAIT * st;
  for (&p.tail, 0..) |*j, i| {
    j.to(target, TAIL_FREQ - m.f(i) * TAIL_FREQ_STEP, TAIL_DAMP, dt);
    target = j.x;
  }
}

/// the belly's lumps and the resin lag behind the body's acceleration
/// (inertia), overshoot when it stops, and settle back on their springs;
/// a footfall drops them a little.
pub fn slosh(p:*Player, fell:bool, dt:f32) void {
  const room = p.bellyRoom();
  const force = -p.accel * m.splat3(SLOSH);
  for (&p.lump, lumps) |*s, l| {
    if (fell) s.vel[1] -= STEP_KICK * p.stride;
    m.springDamper(&s.pos, &s.vel, l.rest * m.splat3(room), l.k, l.c, l.mass, force * m.splat3(l.mass), dt);
    // stay inside the sac; hitting its wall stops the outward motion
    const d = m.len(s.pos);
    if (d > room) {
      const n = s.pos / m.splat3(d);
      s.pos = n * m.splat3(room);
      s.vel -= n * m.splat3(@max(m.dot(s.vel, n), 0));
    }
  }
  for (&p.pec, PEC_K) |*s, k| {
    if (fell) s.vel[1] -= RUMP_KICK * 0.6 * p.stride;
    m.springDamper(&s.pos, &s.vel, v3(0, 0, 0), k, PEC_C, PEC_MASS, force * m.splat3(PEC_MASS), dt);
    const d = m.len(s.pos);
    if (d > PEC_MAX) s.pos *= m.splat3(PEC_MAX / d);
  }
  for (&p.rump) |*s| {
    if (fell) s.vel[1] -= RUMP_KICK * p.stride;
    m.springDamper(&s.pos, &s.vel, v3(0, 0, 0), RUMP_K, RUMP_C, PEC_MASS, force * m.splat3(PEC_MASS), dt);
    const d = m.len(s.pos);
    if (d > RUMP_MAX) s.pos *= m.splat3(RUMP_MAX / d);
  }
}

/// how far a lump's centre may stray from the gut's centre (in the gut
/// bone's frame, which swells with it): within `BELLY_ROOM` of the sac,
/// and never poking through it
pub fn bellyRoom(_:*const Player) f32 {
  return @max(@min(belly_mesh.DOWN, @min(belly_mesh.RX, belly_mesh.RZ)) * BELLY_ROOM - LUMP_R, BELLY_ROOM_MIN);
}
