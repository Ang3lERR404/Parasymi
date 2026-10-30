//! turning what stands in the garden (R): a rooted plant or structure pulls
//! its roots up out of the ground, heaves itself up on them, steps round a
//! quarter and digs them back in facing its new way; a floating (celestial)
//! one only turns where it hangs. Its facing changes at once; how it gets
//! there is timed from when it began (`Turn.at`, game seconds), so nothing
//! ticks it.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the test expectations
const testing=std.testing;
/// the engine package
const engine=lib.engine;
/// all the maths: easing, directions, angles
const m=engine.core.math;
/// how long one rooted turn takes (s)
pub const time:f32=1.5;
/// how long a floating turn takes (s): it only spins where it hangs
const floatTime:f32=0.9;
/// a turn long finished
const never:f64=-1e9;
/// the rooted turn's beats, each a window of shares of `time`: the roots
/// come up, the body rises, steps round, sinks while the roots dig back in;
/// when the roots come up
const pull=[2]f32{0,0.24};
/// when the body rises
const riseHeight=[2]f32{0.1,0.32};
/// when it steps round to its new facing
const step=[2]f32{0.32,0.68};
/// when the body sinks back down
const sinkAmount=[2]f32{0.68,0.92};
/// when the roots dig back in
const digAmount=[2]f32{0.74,1};
/// how far it rocks as it heaves itself free and settles (radians), and
/// how many times
const rock:f32=0.07;
/// how many times it rocks over a whole turn
const rocks:f32=5;
/// a thing's turn: the way it faced before and when it began
pub const Turn=struct{
  /// the way it faced before
  from:m.Dir=0,
  /// when it began (game seconds; `never` for none)
  at:f64=never,
  /// 0 as it begins .. 1 done
  pub fn progress(t:Turn,now:f64,rooted:bool)f32{
    // how long the turn takes
    const span:f64=if(rooted)time else floatTime;
    return m.clamp01(@floatCast((now-t.at)/span));
  }
  /// whether it is still turning
  pub fn busy(t:Turn,now:f64,rooted:bool)bool{return t.progress(now,rooted)<1;}
};
/// how a turning thing is drawn this moment, about its centre
pub const Pose=struct{
  /// yaw still to turn to face its new way (radians; 0 once there)
  spin:f32=0,
  /// how far it is lifted (0 rooted .. 1 at the top of its heave)
  lift:f32=0,
  /// how far its roots are out of the ground (0 dug in .. 1 out)
  out:f32=0,
  /// its rocking: a lean about x and about z (radians)
  rock:[2]f32=.{0,0},
  /// 0..1 through its turn
  k:f32=1,
  /// whether it is done moving
  pub fn still(p:Pose)bool{return p.k>=1;}
};
/// how far through beat `b` (a window of shares) a turn `k` through it is, eased 0..1
fn beat(k:f32,b:[2]f32)f32{return m.smooth(m.clamp01((k-b[0])/(b[1]-b[0])));}
/// the pose of `t`, now facing `to`
pub fn pose(t:Turn,to:m.Dir,now:f64,rooted:bool)Pose{
  // how far through its turn it is
  const k=t.progress(now,rooted);
  if(k>=1)return.{};
  // the quarters still to turn: one either way, or two
  const d=t.from-%to;
  // which way and how many quarters, and the yaw that leaves to turn
  const q:f32=if(d==3)-1 else m.f(d);
  const left=-q*m.halfPi;
  if(!rooted)return.{.spin=left*(1-m.smooth(k)),.k=k};
  // how high it is lifted, and how far its roots are out
  const lift=beat(k,riseHeight)*(1-beat(k,sinkAmount));
  const out=beat(k,pull)*(1-beat(k,digAmount));
  // it rocks most as it tears free and as it settles, not while stepping
  const heave=out*(1-lift*0.6);
  // the phase of its rocking
  const a=rocks*m.pi*k;
  return.{
    .spin=left*(1-beat(k,step)),.lift=lift,.out=out,.k=k,
    .rock=.{rock*heave*@sin(a),rock*heave*@cos(a*1.3)},
  };
}
test"a turn ends facing its new way, rooted again"{
  // a rooted turn from facing 0, begun at 10 s
  const t:Turn=.{.from=0,.at=10};
  // halfway through
  const mid=pose(t,1,10+time/2,true);
  try testing.expect(mid.lift>0.9 and mid.out>0.9);
  try testing.expect(@abs(mid.spin)>0 and @abs(mid.spin)<m.halfPi);
  // once it is over
  const done=pose(t,1,10+time,true);
  try testing.expect(done.still() and done.spin==0 and done.lift==0 and done.out==0);
  // the short way round: 3 -> 0 is one quarter, not three
  const wrap=pose(.{.from=3,.at=0},0,0,true);
  try testing.expectApproxEqAbs(m.halfPi,@abs(wrap.spin),1e-5);
  // a floater only turns
  const fl=pose(t,1,10+floatTime/2,false);
  try testing.expect(fl.lift==0 and fl.out==0 and fl.spin!=0);
  try testing.expect(!t.busy(10+time,true));
}
