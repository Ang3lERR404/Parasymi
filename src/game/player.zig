//! the player: an anthropomorphic wolf woven from vines, leaves and sap.
//! Movement is tile-aware (no wading, one terrace step at a time) and every
//! motion is procedural, posing one skeleton (gfx/meshes/wolf_skeleton.zig)
//! that the GPU skins the wolf's single body over:
//! - feet are planted in the world and stay there through their stance;
//!   each swings on an arc to where it will be needed, the gait's phase
//!   choosing when, or, standing, whenever a foot is left behind;
//! - the digitigrade legs reach them by inverse kinematics;
//! - the pelvis bobs low at each footfall, sways over the planted foot,
//!   rolls and turns with the stride, and the chest turns against it;
//! - arms, lean, head and ears follow on springs, so motion carries,
//!   overshoots a little and settles; the head steadies against the bob;
//! - a spring-driven tail, breathing that quickens with effort, panting,
//!   and a sap belly that swells with what it carries.
const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const m = @import("../core/math.zig");
const noise = @import("../core/noise.zig");
const items = @import("../sim/items.zig");
const World = @import("../world/world.zig").World;
const skel = @import("../gfx/meshes/wolf_skeleton.zig");
const body_mesh = @import("../gfx/meshes/wolf_body.zig");
const belly_mesh = @import("../gfx/meshes/wolf_belly.zig");
const meshlib = @import("../gfx/meshlib.zig");
const parts = @import("parts.zig");
const Parts = parts.Parts;

pub const SLOTS = 24;
pub const REACH:f32 = 2.4;
const STEP_UP:f32 = 0.45;
const WALK_SPEED:f32 = 4.0;
const SPRINT_SPEED:f32 = 6.5;
const ACCEL_RESPONSE:f32 = 12; // how quickly velocity matches the wish
const PROBE:f32 = 0.25; // body radius probed ahead of the centre
const STRIDE_RESPONSE:f32 = 6; // how quickly stride eases in/out
const TURN_RESPONSE:f32 = 10; // how quickly facing matches the target
const GROUND_FREQ:f32 = 18; // spring frequency for following terrain height
const WORK_DRAG:f32 = 0.85; // velocity kept each frame while the hands work
const FACE_MIN_SPEED:f32 = 0.3; // slower than this, the wolf keeps its facing
const MIN_DT:f32 = 1e-4; // guards rates divided by the frame time
const FULLNESS_RESPONSE:f32 = 2; // how quickly the belly's look follows its fill
/// the belly answers every item carried: it is (1 - 1/e) of the way to
/// full with this many held, and keeps swelling toward full past it
const BELLY_ITEMS:f32 = 250;
/// a full belly pushes the arms out round it (radians) and the feet apart
/// (metres each side)
const BELLY_ARMS:f32 = 0.42;
const BELLY_STANCE:f32 = 0.07;
/// stretched thin, the full sac lets more show through it
const SAP_STRETCH:f32 = 0.14;
const REACH_FREQ:f32 = 6; // spring frequency into and out of the work gesture
/// what the wolf works on or carries sits this high above its feet
const CHEST_HEIGHT:f32 = 1.0;

/// the gait: a full cycle (both feet) covers `CYCLE + CYCLE_PER_SPEED *
/// speed` metres; a foot is planted for `duty` of it, more of it walking
/// slowly than running
const CYCLE:f32 = 1.2;
const CYCLE_PER_SPEED:f32 = 0.2;
const DUTY_SLOW:f32 = 0.6;
const DUTY_FAST:f32 = 0.38;
/// below this stride the wolf stands: feet only step to stay under it
const STANDING:f32 = 0.15;
/// a standing foot further than this from where it rests steps back under
const SETTLE:f32 = 0.06;
const SETTLE_TIME:f32 = 0.26;
/// a striding foot's swing lasts its share of the cycle, as if walking at
/// least `SWING_SPEED_MIN`, held within these seconds
const SWING_SPEED_MIN:f32 = 0.5;
const SWING_MIN:f32 = 0.12;
const SWING_MAX:f32 = 0.4;
/// a planted foot never trails the hip by more than this before it lifts
const TRAIL_MAX:f32 = 0.5;
/// a foot this far from the body (a load, a teleport) is put straight back
const LOST:f32 = 1.2;
/// how high a swinging foot lifts (standing, and more at full stride), and
/// how far its toes hang as it swings
const LIFT:f32 = 0.05;
const LIFT_STRIDE:f32 = 0.08;
const TOE_HANG:f32 = 0.55;
/// the lift's arc over the swing (sin^this: under 1 rises fast, hangs high)
const LIFT_ARC:f32 = 0.8;
/// the metatarsal folds this much more under the leg mid-swing
const SWING_FOLD:f32 = 0.45;
/// the pelvis: how far it sinks with stride and bobs at each footfall,
/// sways over the planted foot, turns and rolls with the stride
const SINK:f32 = 0.045;
const BOB:f32 = 0.028;
const SWAY:f32 = 0.018;
const HIP_TURN:f32 = 0.13;
const HIP_ROLL:f32 = 0.05;
/// the chest turns against the hips by this share
const COUNTER:f32 = 1.4;
/// lean: forward with stride, more into acceleration (radians per m/s^2),
/// into turns (radians per rad/s), and down into the work
const LEAN_STRIDE:f32 = 0.14;
const LEAN_ACCEL:f32 = 0.018;
const LEAN_MAX:f32 = 0.3;
const BANK:f32 = 0.05;
const BANK_MAX:f32 = 0.2;
const LEAN_WORK:f32 = 0.38;
const LEAN_FREQ:f32 = 5;
const LEAN_DAMP:f32 = 0.7;
const BANK_DAMP:f32 = 0.8;
/// arms: swing against the legs, hang out a little, bend at the elbow
/// (more as they come forward); their springs make them lag and carry
const ARM_SWING:f32 = 0.62;
const ARM_OUT:f32 = 0.13;
const ELBOW_REST:f32 = 0.3;
const ELBOW_SWING:f32 = 0.55;
const ARM_FREQ:f32 = 9;
const ARM_DAMP:f32 = 0.55;
/// the work gesture: reach forward and dig
const DIG:f32 = -1.1;
const DIG_RATE:f32 = 9;
const DIG_DEPTH:f32 = 0.22;
/// breathing: a tempo that quickens with effort, the chest swelling and
/// panting with the jaw a little open at a run
const BREATH_RATE:f32 = 1.7;
const BREATH_RATE_RUN:f32 = 4.2;
const BREATH:f32 = 0.02;
const BREATH_RUN:f32 = 0.03;
const PANT:f32 = 0.09;
/// the head: steadied against the bob and lean, turning into turns,
/// looking about when idle, down into the work
const HEAD_FREQ:f32 = 7;
const HEAD_DAMP:f32 = 0.8;
const LOOK_TURN:f32 = 0.18;
const LOOK_MAX:f32 = 0.6;
const LOOK_IDLE:f32 = 0.28;
const LOOK_IDLE_RATE:f32 = 0.23;
const LOOK_WORK:f32 = 0.45;
/// ears: lie back with speed, flick now and then
const EAR_BACK:f32 = 0.45;
const EAR_FREQ:f32 = 14;
const EAR_DAMP:f32 = 0.35;
const EAR_FLICK:f32 = 9;
const EAR_FLICK_EVERY:f32 = 3.5;
/// fingers: a loose curl at rest (radians at the knuckle), curling more as
/// the arm swings forward; idle, now and then they flex in a ripple one
/// after the next; digging, they open and rake shut with each stroke, a
/// beat apart. The tip joint follows the knuckle. Open fingers fan out.
const CURL_REST:f32 = 0.42;
const CURL_SWING:f32 = 0.45;
const CURL_FLEX:f32 = 0.7;
const FLEX_RATE:f32 = 0.35;
const FLEX_WAVE:f32 = 5.5;
const FLEX_LAG:f32 = 0.75;
const GRIP_OPEN:f32 = 0.05;
const GRIP_CLOSE:f32 = 1.35;
const GRIP_LAG:f32 = 0.3;
const TIP_SHARE:f32 = 0.9;
const TIP_REST:f32 = 0.15;
const SPREAD_OPEN:f32 = 0.6;
const SPREAD_SHUT:f32 = -0.35;
const FINGER_FREQ:f32 = 10;
const FINGER_DAMP:f32 = 0.5;
/// the fingers' spread springs this damped
const SPREAD_DAMP:f32 = 0.7;

/// paw beans and the nose: sap made denser (80%) and browner than the belly
const BEAN_OPACITY:f32 = 0.8;
/// how much the beans, nose, inner ears and belly lumps glow; the belly's
/// sap glows from `BELLY_GLOW` up by `BELLY_GLOW_FULL` as it fills
const BEAN_GLOW:f32 = 0.15;
const NOSE_GLOW:f32 = 0.1;
const EAR_GLOW:f32 = 0.3;
const LUMP_GLOW:f32 = 0.25;
const BELLY_GLOW:f32 = 0.35;
const BELLY_GLOW_FULL:f32 = 0.65;
const BEAN_TINT = [4]f32{ 0.72, 0.5, 0.38, 1 };
const NOSE_TINT = [4]f32{ 0.3, 0.22, 0.2, 1 };
/// a planted foot's central pad flattens by this fraction
const PAD_FLATTEN:f32 = 0.1;
const PAD_FREQ:f32 = 14;
/// the inner ears' sap
const EAR_OPACITY:f32 = 0.5;
/// the belly's sap at its centre lets the body behind show through faintly;
/// the pectorals are solidified sap, 30% less see-through; the rear's
/// resin is a little denser again
const SAP_OPACITY:f32 = 0.72;
const PEC_OPACITY:f32 = 1 - (1 - SAP_OPACITY) * 0.7;
const RUMP_OPACITY:f32 = 1 - (1 - SAP_OPACITY) * 0.6;
/// how strongly the wolf's acceleration is felt by what hangs in and on its
/// body (m/s^2 down to a few centimetres of lag)
const SLOSH:f32 = 0.05;
/// a footfall drops the belly's contents a little
const STEP_KICK:f32 = 0.18;
/// the body's glow (the eyes carry it; the hide barely), how much its fur
/// leaves stir
const BODY_GLOW:f32 = 0.6;
const BODY_FLUTTER:f32 = 0.3;
/// a body this large is culled and detailed about its middle
const BODY_MID:f32 = 0.8;

/// one of the heavier things carried, hanging in the sap on its own spring.
const Lump = struct {
  /// rest place within the belly (unit ball, scaled by the room inside)
  rest:V3,
  k:f32,
  c:f32,
  mass:f32,
};
const lumps = [_]Lump{
  .{ .rest = v3(0.35, -0.3, 0.3), .k = 55, .c = 5, .mass = 0.7 },
  .{ .rest = v3(-0.4, -0.35, 0.15), .k = 70, .c = 6, .mass = 0.9 },
  .{ .rest = v3(0.05, -0.6, -0.1), .k = 40, .c = 4, .mass = 1.0 },
  .{ .rest = v3(0.4, 0.15, -0.2), .k = 80, .c = 7, .mass = 0.5 },
  .{ .rest = v3(-0.25, 0.05, 0.45), .k = 62, .c = 5.5, .mass = 0.6 },
};
const LUMP_R:f32 = 0.055;
/// the pectorals: dense gel on a spring each (left, right)
const PEC_K = [2]f32{ 60, 55 };
const PEC_C:f32 = 6;
const PEC_MASS:f32 = 0.8;
const PEC_MAX:f32 = 0.02;
/// the rear: resin a little firmer than the chest, bouncing with each step
const RUMP_K:f32 = 70;
const RUMP_C:f32 = 5;
const RUMP_MAX:f32 = 0.02;
const RUMP_KICK:f32 = 0.12;
/// a lump keeps within this share of the sac, and at least this much room
const BELLY_ROOM:f32 = 0.8;
const BELLY_ROOM_MIN:f32 = 0.01;

/// the tail's steering: turning swings it out (capped), an idle sway at rest
/// gives way to the gait's swing in stride; it lifts with stride; each
/// joint's spring is softer than the one before
const TAIL_TURN:f32 = 0.1;
const TAIL_TURN_MAX:f32 = 0.6;
const TAIL_IDLE_RATE:f32 = 1.3;
const TAIL_IDLE:f32 = 0.16;
const TAIL_GAIT:f32 = 0.12;
const TAIL_LIFT:f32 = 0.25;
const TAIL_DROOP:f32 = 0.16;
const TAIL_FREQ:f32 = 7;
const TAIL_FREQ_STEP:f32 = 1.2;
const TAIL_DAMP:f32 = 0.45;

const V3 = m.V3;
const v3 = m.v3;
const M4 = m.M4;
const T = m.translate;
const S = m.scale3;
const Bone = skel.Bone;

/// a point mass on a spring: offset from its rest place and velocity.
const Spring3 = struct {
  pos:V3 = v3(0, 0, 0),
  vel:V3 = v3(0, 0, 0),
};
/// a damped angular spring (critically damped is `damp` 1)
const Swing = struct {
  x:f32 = 0,
  v:f32 = 0,
  fn to(s:*Swing, target:f32, freq:f32, damp:f32, dt:f32) void {
    const w = freq * m.tau / 4;
    s.v += (w * w * (target - s.x) - 2 * damp * w * s.v) * dt;
    s.x += s.v * dt;
  }
};

/// one foot: where its ball is in the world, and its swing (`t` 1 planted)
const Foot = struct {
  at:V3 = v3(0, 0, 0),
  from:V3 = v3(0, 0, 0),
  t:f32 = 1,
  dur:f32 = SETTLE_TIME,
  lift:f32 = LIFT,
  /// where in the gait it was last frame
  phase:f32 = 0,
  /// 1 planted .. 0 lifted, eased (the central pad flattens with it)
  pad:f32 = 1,
  pad_v:f32 = 0,
  fn planted(f:*const Foot) bool { return f.t >= 1; }
};

pub const Player = struct {
  /// feet position (y follows the terrain)
  pos:V3,
  vel:V3 = v3(0, 0, 0),
  y_v:f32 = 0,
  facing:f32 = 0,
  turn:f32 = 0,
  inv:items.Inventory(SLOTS) = .{},

  // animation state
  t:f32 = 0,
  /// where in the gait cycle (0..1), and how far into stride (0 standing)
  phase:f32 = 0,
  stride:f32 = 0,
  /// the cycle's length and stance share this frame
  cycle:f32 = CYCLE,
  duty:f32 = DUTY_SLOW,
  breath:f32 = 0,
  /// how full the belly looks, easing toward the inventory's fill
  fullness:f32 = 0,
  /// velocity last frame and the acceleration felt since, in the wolf's own
  /// frame (x right, z forward)
  last_vel:V3 = v3(0, 0, 0),
  accel:V3 = v3(0, 0, 0),
  feet:[2]Foot = @splat(.{}),
  placed:bool = false,
  /// what lags on springs: the lean and bank of the body, each arm's swing
  /// and elbow, the head's turn and nod, the ears
  lean:Swing = .{},
  bank:Swing = .{},
  arm:[2]Swing = @splat(.{}),
  elbow:[2]Swing = @splat(.{}),
  look:Swing = .{},
  nod:Swing = .{},
  ear:[2]Swing = @splat(.{}),
  /// each finger's curl, each hand's spread
  curl:[2][skel.FINGERS]Swing = @splat(@splat(.{ .x = CURL_REST })),
  spread:[2]Swing = @splat(.{}),
  /// what hangs in the belly (relative to its centre) and the resin's
  /// give (relative to its rest)
  lump:[lumps.len]Spring3 = @splat(.{}),
  pec:[2]Spring3 = @splat(.{}),
  rump:[2]Spring3 = @splat(.{}),
  tail:[skel.TAIL]Swing = @splat(.{}),
  /// 0..1 blend toward the work gesture (gathering, planting, harvesting)
  reach:Swing = .{},
  /// where the hands are busy (gathering, weaving, ...); null while idle
  work:?V3 = null,

  /// tile-aware: no wading, one terrace step at a time.
  pub fn move(p:*Player, wish:[2]f32, sprint:bool, ground:*const World, dt:f32) void {
    const speed:f32 = if (sprint) SPRINT_SPEED else WALK_SPEED;
    const target = v3(wish[0] * speed, 0, wish[1] * speed);
    const k = @min(1, dt * ACCEL_RESPONSE);
    p.vel += (target - p.vel) * m.splat3(k);
    if (p.work != null) p.vel *= m.splat3(WORK_DRAG);

    const here = ground.walkable(m.tileOf(p.pos[0]), m.tileOf(p.pos[2])) orelse p.pos[1];
    // resolve each axis separately so the wolf slides along cliffs
    inline for (.{ 0, 2 }) |axis| {
      var next = p.pos;
      next[axis] += p.vel[axis] * dt;
      // probe a little ahead so the body does not clip into terrace walls
      var probe = next;
      probe[axis] += if (p.vel[axis] > 0) PROBE else -PROBE;
      const ok = if (ground.walkable(m.tileOf(probe[0]), m.tileOf(probe[2]))) |h| h - here <= STEP_UP else false;
      if (ok) p.pos[axis] = next[axis] else p.vel[axis] = 0;
    }
    // the body follows the ground as it is drawn, so its paws meet it
    const h = if (ground.walkable(m.tileOf(p.pos[0]), m.tileOf(p.pos[2])) != null) ground.surfaceAt(p.pos[0], p.pos[2]) else here;
    m.spring(&p.pos[1], &p.y_v, h, GROUND_FREQ, dt);

    // face where we move, or what we work on
    var want = p.facing;
    if (p.work) |w| {
      want = m.atan2(w[0] - p.pos[0], w[2] - p.pos[2]);
    } else if (@abs(p.vel[0]) + @abs(p.vel[2]) > FACE_MIN_SPEED) {
      want = m.atan2(p.vel[0], p.vel[2]);
    }
    const diff = m.angleDiff(p.facing, want);
    const turn = diff * @min(1, dt * TURN_RESPONSE);
    p.facing += turn;
    p.turn = turn / @max(dt, MIN_DT);
  }

  fn groundSpeed(p:*const Player) f32 { return @sqrt(p.vel[0] * p.vel[0] + p.vel[2] * p.vel[2]); }
  fn heading(p:*const Player) M4 { return m.chain(&.{ T(p.pos), m.rotY(p.facing) }); }

  /// where a foot rests under the standing wolf, in the world
  fn rest(p:*const Player, ground:?*const World, s:usize) V3 {
    const x = restFoot[s][0] + skel.sign(s) * BELLY_STANCE * p.fullness;
    const r = m.mulV(p.heading(), .{ x, 0, restFoot[s][2], 1 });
    return p.onGround(ground, v3(r[0], 0, r[2]));
  }

  /// `at` set down on the ground as it is drawn (level with the body
  /// without a world), so a paw never sinks into a slope
  fn onGround(p:*const Player, ground:?*const World, at:V3) V3 {
    const y = if (ground) |g| g.surfaceAt(at[0], at[2]) else p.pos[1];
    return v3(at[0], y, at[2]);
  }

  pub fn animate(p:*Player, ground:?*const World, dt:f32) void {
    p.t += dt;
    const spd = p.groundSpeed();
    p.stride += (m.clamp01(spd / WALK_SPEED) - p.stride) * @min(1, dt * STRIDE_RESPONSE);
    p.cycle = CYCLE + CYCLE_PER_SPEED * spd;
    p.duty = m.lerp(DUTY_SLOW, DUTY_FAST, m.clamp01((spd - 1) / (SPRINT_SPEED - 1)));
    p.phase = @mod(p.phase + spd / p.cycle * dt, 1);
    const effort = m.clamp01(spd / SPRINT_SPEED);
    p.breath += dt * m.lerp(BREATH_RATE, BREATH_RATE_RUN, effort);

    p.fullness += (p.bellyFill() - p.fullness) * @min(1, dt * FULLNESS_RESPONSE);
    p.reach.to(if (p.work != null) 1 else 0, REACH_FREQ, 1, dt);

    // what the body feels: its acceleration, turned into its own frame
    const a = (p.vel - p.last_vel) / m.splat3(@max(dt, MIN_DT));
    p.last_vel = p.vel;
    const al = m.mulV(m.rotY(-p.facing), .{ a[0], a[1], a[2], 0 });
    p.accel = v3(al[0], al[1], al[2]);

    const fell = p.step(ground, spd, dt);
    p.slosh(fell, dt);
    p.springs(dt);
  }

  /// how full the belly is to look at (0..1) for what it holds
  fn bellyFill(p:*const Player) f32 { return 1 - @exp(-m.f(p.inv.total()) / BELLY_ITEMS); }

  /// the feet: plant, lift, swing to where they are wanted. Returns whether
  /// one came down this frame.
  fn step(p:*Player, ground:?*const World, spd:f32, dt:f32) bool {
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
          f.lift = LIFT + LIFT_STRIDE * p.stride;
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
        }
      }
      m.spring(&f.pad, &f.pad_v, if (f.planted()) 1 else 0, PAD_FREQ, dt);
    }
    return fell;
  }

  /// what lags on springs: lean and bank, arms, head, ears, tail
  fn springs(p:*Player, dt:f32) void {
    const st = p.stride;
    const work = p.reach.x;
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
        c.to(target, FINGER_FREQ, FINGER_DAMP, dt);
        sum += c.x;
      }
      const shut = m.clamp01(sum / (skel.FINGERS * GRIP_CLOSE));
      spread.to(m.lerp(SPREAD_OPEN, SPREAD_SHUT, shut), FINGER_FREQ, SPREAD_DAMP, dt);
    }
    const look = m.clamp(p.turn * LOOK_TURN, -LOOK_MAX, LOOK_MAX) + LOOK_IDLE * idle * noise.grad(0x100C, p.t * LOOK_IDLE_RATE, 0.5);
    p.look.to(look, HEAD_FREQ, HEAD_DAMP, dt);
    p.nod.to(LOOK_WORK * work + 0.12 * idle * noise.grad(0x40D, p.t * LOOK_IDLE_RATE, 3.5), HEAD_FREQ, HEAD_DAMP, dt);
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
  fn slosh(p:*Player, fell:bool, dt:f32) void {
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
  fn bellyRoom(_:*const Player) f32 {
    return @max(@min(belly_mesh.DOWN, @min(belly_mesh.RX, belly_mesh.RZ)) * BELLY_ROOM - LUMP_R, BELLY_ROOM_MIN);
  }

  /// the skeleton's pose this frame, in wolf space (see wolf_skeleton)
  pub fn pose(p:*const Player) skel.Pose {
    const st = p.stride;
    const work = p.reach.x;
    const ph = p.phase * m.tau;
    var q:skel.Pose = .{};
    // the pelvis: lowest just after each footfall, over the planted foot
    const bob = BOB * st * (0.5 + 0.5 * @cos(2 * ph - p.duty * m.tau));
    q.hip = v3(SWAY * st * @sin(ph), skel.HIP_Y - SINK * st - bob - 0.07 * work, 0);
    q.pelvis = .{ .x = 0.25 * p.lean.x, .y = HIP_TURN * st * @sin(ph), .z = HIP_ROLL * st * @cos(ph) + p.bank.x };
    q.waist = .{ .x = 0.35 * p.lean.x, .y = -0.5 * COUNTER * q.pelvis.y, .z = -0.4 * q.pelvis.z };
    q.chest = .{ .x = 0.4 * p.lean.x, .y = -0.5 * COUNTER * q.pelvis.y, .z = -0.4 * q.pelvis.z };
    const breath = @sin(p.breath);
    q.breath = 1 + m.lerp(BREATH, BREATH_RUN, st) * breath;
    // the head holds its gaze: it takes back the body's lean and bob
    const body_pitch = q.pelvis.x + q.waist.x + q.chest.x;
    q.neck = .{ .x = -0.4 * body_pitch + 0.5 * p.nod.x, .y = 0.4 * p.look.x - 0.3 * q.chest.y };
    q.head = .{ .x = -0.6 * body_pitch + 0.5 * p.nod.x - bob * 1.5 + 0.02 * breath, .y = 0.6 * p.look.x - 0.3 * q.chest.y, .z = -0.5 * p.bank.x };
    q.jaw = PANT * st * (0.6 + 0.4 * breath);
    q.gut = p.fullness;
    for (0..2) |s| {
      const x = skel.sign(s);
      q.arms[s] = .{
        .root = .{ .x = p.arm[s].x, .z = x * (ARM_OUT + BELLY_ARMS * p.fullness + 0.02 * breath + 0.1 * work), .y = -x * 0.15 * work },
        .mid = p.elbow[s].x,
        .low = .{ .x = 0.2 + 0.3 * work },
      };
      q.ears[s] = .{ .x = p.ear[s].x, .z = 0.15 * x * p.ear[s].x };
      for (&q.hands[s].curl, &q.hands[s].tip, p.curl[s]) |*c, *tp, sp| {
        c.* = sp.x;
        tp.* = TIP_REST + TIP_SHARE * sp.x;
      }
      q.hands[s].spread = p.spread[s].x;
    }
    // the tail lifts with the stride and droops at rest, each joint bending
    // a little further
    for (&q.tail, p.tail, 0..) |*j, sp, i| j.* = .{ .x = (if (i == 0) -TAIL_LIFT * st else TAIL_DROOP * (1 - 0.6 * st)), .z = sp.x };
    q.legs = p.legs(q);
    return q;
  }

  /// each leg reaching its foot, by inverse kinematics in the pelvis's frame
  fn legs(p:*const Player, q:skel.Pose) [2]skel.Limb {
    var out:[2]skel.Limb = undefined;
    const to_wolf = m.inverseRigid(p.heading());
    const pelvis = m.chain(&.{ T(q.hip), q.pelvis.m4() });
    const into = m.inverseRigid(pelvis);
    const pelvis_pitch = q.pelvis.x;
    for (&out, 0..) |*l, s| {
      const f = p.feet[s];
      const fw = m.mulV(to_wolf, .{ f.at[0], f.at[1], f.at[2], 1 });
      const fp = m.mulV(into, fw);
      const swing = if (f.planted()) @as(f32, 0) else @sin(f.t * m.pi);
      l.* = solveLeg(v3(fp[0], fp[1], fp[2]) - v3(skel.sign(s) * skel.HIP_X, 0, 0), SWING_FOLD * swing, pelvis_pitch, TOE_HANG * swing);
    }
    return out;
  }

  /// emit every part; returns where each paw (left, right) touches down.
  pub fn rig(p:*const Player, out:*Parts) Allocator.Error![2]V3 {
    const q = p.pose();
    const root = p.heading();
    var w = skel.fk(q);
    for (&w) |*b| b.* = m.mul(root, b.*);
    const skin = skel.skin(w, &bindInv(), q.breath);
    const base = try out.pose(&skin);
    const mid = p.pos + v3(0, BODY_MID, 0);
    const at = struct {
      fn f(ws:*const [skel.COUNT]M4, b:Bone) M4 { return ws[@intFromEnum(b)]; }
    }.f;

    try out.emitSkinned(.wolf_body, base, mid, .{ .glow = BODY_GLOW, .flutter = BODY_FLUTTER, .phase = 0.1 });
    try out.emitSkinned(.wolf_ears, base, mid, .{ .glow = EAR_GLOW, .phase = 0.5, .fade = EAR_OPACITY });
    try out.emit(.paw_bean, m.chain(&.{ at(&w, .head), T(body_mesh.NOSE), m.rotX(-body_mesh.NOSE_TILT), S(v3(0.015, 0.0105, 0.011)) }), .{ .glow = NOSE_GLOW, .fade = BEAN_OPACITY, .tint = NOSE_TINT });

    // the belly: a sap sac that inflates with the inventory, drops and sags
    // as it fills, with the heavier things inside showing through as shadows
    const b = p.fullness;
    const gut = at(&w, .gut);
    var held:usize = 0;
    for (p.inv.slot) |slot| if (slot != null) {
      held += 1;
    };
    for (p.lump[0..@min(held, lumps.len)]) |l| {
      try out.emit(.belly_lump, m.chain(&.{ gut, T(l.pos), S(m.splat3(LUMP_R)) }), .{ .glow = LUMP_GLOW, .phase = 0.3 });
    }
    // (the shader creases it as it fills, the folds crossing at its button)
    const cross = belly_mesh.crossing();
    try out.emitSkinned(.wolf_belly, base, mid, .{
      .glow = BELLY_GLOW + BELLY_GLOW_FULL * b, .phase = 0.3, .fade = SAP_OPACITY - SAP_STRETCH * b, .give = .{ b, cross[1], cross[2] },
    });

    // the pectorals and the rear: resin, its surface given by its spring
    // (and, on the chest, a slow idle) while its base holds
    for ([_]meshlib.Id{ .wolf_pec_l, .wolf_pec_r }, [_]f32{ -1, 1 }, 0..) |id, side, i| {
      const give = p.pec[i].pos + v3(0, 0.003 * @sin(p.t * m.tau / 3 + side * 1.3), 0);
      try out.emitSkinned(id, base, mid, .{ .phase = 0.6, .fade = PEC_OPACITY, .give = .{ give[0], give[1], give[2] } });
    }
    for ([_]meshlib.Id{ .wolf_rump_l, .wolf_rump_r }, 0..) |id, i| {
      const give = p.rump[i].pos;
      try out.emitSkinned(id, base, mid, .{ .phase = 0.15, .fade = RUMP_OPACITY, .give = .{ give[0], give[1], give[2] } });
    }

    var feet:[2]V3 = undefined;
    for (skel.sides, 0..) |sd, s| {
      const x = skel.sign(s);
      // the beans: a palm pad and one under each fingertip; one
      // central pad on each foot that flattens while planted, four toe pads
      const bean:parts.Look = .{ .glow = BEAN_GLOW, .fade = BEAN_OPACITY, .tint = BEAN_TINT };
      const hand = at(&w, sd.hand);
      try out.emit(.paw_pad, m.chain(&.{ hand, T(body_mesh.PALM * v3(x, 1, 1)), m.rotZ(x * m.pi / 2.0), S(v3(0.018, 0.005, 0.016)) }), bean);
      for (sd.tips) |tb| {
        try out.emit(.paw_bean, m.chain(&.{ at(&w, tb), T(body_mesh.TIP_PAD * v3(x, 1, 1)), S(v3(0.0042, 0.0085, 0.0075)) }), bean);
      }
      const foot = at(&w, sd.foot);
      try out.emit(.paw_pad, m.chain(&.{ foot, T(body_mesh.PAD_AT), S(v3(0.021, 0.006 * (1 - PAD_FLATTEN * p.feet[s].pad), 0.02)) }), bean);
      for (body_mesh.TOES) |tp| {
        try out.emit(.paw_bean, m.chain(&.{ foot, T(v3(tp[0], body_mesh.SOLE_Y + 0.002, tp[1])), S(v3(0.0065, 0.004, 0.008)) }), bean);
      }
      feet[s] = m.mulPoint(foot, v3(0, 0, 0.04));
    }
    return feet;
  }

  pub fn chest(p:*const Player) V3 { return p.pos + v3(0, CHEST_HEIGHT, 0); }

  pub fn inReach(p:*const Player, wx:i32, wz:i32) bool {
    const c = m.tileCentre(wx, wz, 0);
    const dx = c[0] - p.pos[0];
    const dz = c[2] - p.pos[2];
    return dx * dx + dz * dz <= REACH * REACH;
  }
};

/// where each foot's ball rests under the standing wolf (wolf space)
const restFoot = blk: {
  @setEvalBranchQuota(100000);
  var out:[2]V3 = undefined;
  const w = skel.fk(.{});
  for (&out, skel.sides) |*o, sd| o.* = m.origin(w[@intFromEnum(sd.foot)]);
  break :blk out;
};

/// the skeleton's bind pose, inverted (what the skin matrices start from)
fn bindInv() [skel.COUNT]M4 { return skel.inverses(skel.bind()); }

/// the leg reaching `d` (the ball, from the hip joint, in the pelvis's
/// frame). Digitigrade: the metatarsal keeps its angle to the thigh (`fold`
/// more mid-swing), so thigh and metatarsal act as one link and the shin as
/// the other, solved by the law of cosines; the knee always folds back.
/// The foot is kept level with the ground (the pelvis tilted by
/// `pelvis_pitch`), its toes hanging by `hang`.
pub fn solveLeg(d:V3, fold:f32, pelvis_pitch:f32, hang:f32) skel.Limb {
  // out to the side first (the hip's roll), then in its own plane
  const ab = m.atan2(d[0], -d[1]);
  const plane = m.mulV(m.rotZ(-ab), .{ d[0], d[1], d[2], 0 });
  const dy = plane[1];
  const dz = plane[2];
  const delta = skel.REST_KNEE + skel.REST_HOCK - fold;
  // thigh and metatarsal as one link: its length and the angle it sits at
  // from the thigh's own
  const cy = skel.THIGH + skel.META * @cos(delta);
  const cz = skel.META * @sin(delta);
  const lv = @sqrt(cy * cy + cz * cz);
  const phi = m.atan2(cz, cy);
  const l2 = skel.SHIN;
  const reach = @sqrt(dy * dy + dz * dz);
  const dist = m.clamp(reach, @abs(lv - l2) + 1e-3, lv + l2 - 1e-3);
  // the direction toward the ball, as a limb's turn about X
  const beta = m.atan2(-dz, -dy);
  const g1 = m.acos((lv * lv + dist * dist - l2 * l2) / (2 * lv * dist));
  const g2 = m.acos((l2 * l2 + dist * dist - lv * lv) / (2 * l2 * dist));
  const th = beta - g1 - phi;
  const shin = beta + g2;
  const meta = th + delta;
  return .{
    .root = .{ .x = th, .z = ab },
    .mid = shin - th,
    .low = .{ .x = meta - shin },
    .foot = -meta - pelvis_pitch + hang,
  };
}

/// tests step at the 60 Hz tick and allow this much float slack
const TEST_DT:f32 = 1.0 / 60.0;
const TEST_EPS:f32 = 1e-4;

test "belly contents lag a sprint, overshoot a stop, then settle" {
  var p:Player = .{ .pos = v3(0, 0, 0) };
  _ = p.inv.add(.grit, 50);
  const dt:f32 = TEST_DT;
  for (0..120) |_| p.animate(null, dt);
  const rest_at = p.lump[0].pos;
  // a burst of speed forward (+z): the lump swings back
  p.vel = v3(0, 0, 4);
  p.animate(null, dt);
  for (0..3) |_| p.animate(null, dt);
  try testing.expect(p.lump[0].pos[2] < rest_at[2] - 0.005);
  // run steadily, then stop dead: it overshoots forward
  for (0..120) |_| p.animate(null, dt);
  p.vel = v3(0, 0, 0);
  for (0..4) |_| p.animate(null, dt);
  try testing.expect(p.lump[0].pos[2] > rest_at[2] + 0.005);
  // and it never leaves the sac
  for (p.lump) |l| try testing.expect(m.len(l.pos) <= p.bellyRoom() + TEST_EPS);
  for (p.pec) |q| try testing.expect(m.len(q.pos) <= PEC_MAX + TEST_EPS);
  for (p.rump) |q| try testing.expect(m.len(q.pos) <= RUMP_MAX + TEST_EPS);
}

test "the leg reaches its resting foot in its resting pose" {
  const w = skel.fk(.{});
  for (skel.sides, 0..) |sd, s| {
    const foot = m.origin(w[@intFromEnum(sd.foot)]);
    const l = solveLeg(foot - v3(skel.sign(s) * skel.HIP_X, skel.HIP_Y, 0), 0, 0, 0);
    try testing.expectApproxEqAbs(skel.REST_THIGH, l.root.x, 1e-3);
    try testing.expectApproxEqAbs(skel.REST_KNEE, l.mid, 1e-3);
    try testing.expectApproxEqAbs(skel.REST_HOCK, l.low.x, 1e-3);
  }
}

test "a planted foot stays where it is planted while the wolf walks" {
  var p:Player = .{ .pos = v3(0, 0, 0) };
  p.animate(null, TEST_DT);
  p.vel = v3(0, 0, WALK_SPEED);
  for (0..240) |_| {
    p.pos += p.vel * m.splat3(TEST_DT);
    const before = p.feet;
    p.animate(null, TEST_DT);
    for (before, p.feet) |a, b| if (a.planted() and b.planted()) try testing.expect(m.len(a.at - b.at) < 1e-5);
  }
  // and both feet keep up with it
  for (p.feet, 0..) |f, s| try testing.expect(m.len(f.at - p.rest(null, s)) < TRAIL_MAX + 0.1);
}
