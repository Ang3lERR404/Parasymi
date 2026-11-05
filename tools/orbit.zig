//! the tools' editors' camera (tools/meshedit.zig, tools/animedit.zig): a
//! free view turning round a target with no limit on its pitch (over the
//! top and under it alike), dragged round as the game's camera turns;
//! zooms and focusing ease it to where it is sent. Claude, linked, turns
//! it too (`Ask`, through the link's `view.txt`), taken at once.
/// the standard library, reached through the game's hub
const std=ps.std;
/// the test helpers
const testing=std.testing;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the engine package
const engine=ps.engine;
/// all the maths: vectors, easing, clamps
const m=engine.core.math;
/// the engine's camera, which the orbit places each frame
const camera=engine.render.camera;
/// a point or direction in the world (m)
const V3=m.V3;
/// makes a `V3` from its three parts
const v3=m.v3;
/// reads a decimal number (an ask's values)
const parseFloat=std.fmt.parseFloat;
/// reads a whole number (an ask's form)
const parseInt=std.fmt.parseInt;
/// are two strings equal?
const eql=std.mem.eql;
/// splits text at each of a byte (an ask's lines)
const splitScalar=std.mem.splitScalar;
/// splits text into words at any of some bytes
const tokenizeAny=std.mem.tokenizeAny;
/// how much nearer each notch of the wheel brings the view (a share of its distance)
const zoomStep:f32=0.88;
/// the nearest the view may come to its target (m)
const distMin:f32=0.08;
/// the farthest the view may draw back from its target (m)
const distMax:f32=40;
/// how long (s) the view takes to ease half way to where it is sent
const ease:f32=0.06;
/// focusing frames a thing from this many times its largest size
pub const focusFit:f32=4;
/// and from no nearer than this (m)
pub const focusMin:f32=0.15;
/// turning round `target` from `dist` away; easing to `goal` and `goalDist`
pub const Orbit=struct{
  /// the point looked at now
  target:V3,
  /// the point being eased toward
  goal:V3,
  /// how far (m) the view is from its target now
  dist:f32,
  /// how far (m) the view is easing toward
  goalDist:f32,
  /// the turn round the target (rad), 0 looking down -z
  yaw:f32=0,
  /// how high over the target the view is (rad); it may pass straight up
  /// and on round, under it alike
  pitch:f32,
  /// looking at `at` from `dist` away, `pitch` (rad) over it
  pub fn init(at:V3,dist:f32,pitch:f32)Orbit{
    return.{.target=at,.goal=at,.dist=dist,.goalDist=dist,.pitch=pitch};
  }
  /// drag round by `px` pixels, as the game's camera turns
  pub fn turn(o:*Orbit,px:m.Vice(f32,2))void{
    o.yaw=@mod(o.yaw-px[0]*camera.orbitSpeed,m.tau);
    o.pitch=@mod(o.pitch+px[1]*camera.orbitSpeed,m.tau);
  }
  /// draw nearer or farther by `steps` notches of the wheel (negative draws
  /// back), kept between `distMin` and `distMax`
  pub fn zoom(o:*Orbit,steps:f32)void{
    o.goalDist=m.clamp(o.goalDist*m.pow(f32,zoomStep,steps),distMin,distMax);
  }
  /// ease toward looking at `at` from `dist` away
  pub fn send(o:*Orbit,at:V3,dist:f32)void{
    o.goal=at;
    o.goalDist=m.clamp(dist,distMin,distMax);
  }
  /// look at `at`, near enough that something `size` across fills the view
  pub fn focus(o:*Orbit,at:V3,size:f32)void{
    o.send(at,@max(size*focusFit,focusMin));
  }
  /// takes Claude's ask (`a`, through the link) at once, no easing: where
  /// to look (`at`, from `origin`), how far, turned how, zoomed, panned
  /// across the view; a focus or a way home is the caller's, sent before
  pub fn take(o:*Orbit,a:Ask,origin:V3)void{
    if(a.at)|p|o.goal=origin+p;
    if(a.dist)|d|o.goalDist=m.clamp(d,distMin,distMax);
    if(a.yaw)|y|o.yaw=@mod(m.rad(y),m.tau);
    if(a.pitch)|p|o.pitch=@mod(m.rad(p),m.tau);
    if(a.zoom)|z|o.zoom(z);
    if(a.pan)|p|{
      // the view's right, up and forward, as the eye looks now
      const cp=@cos(o.pitch);
      const fwd=-v3(@sin(o.yaw)*cp,@sin(o.pitch),@cos(o.yaw)*cp);
      const right=v3(@cos(o.yaw),0,-@sin(o.yaw));
      const up=m.cross(right,fwd);
      o.goal+=right*m.splat3(p[0])+up*m.splat3(p[1])+fwd*m.splat3(p[2]);
    }
    o.target=o.goal;
    o.dist=o.goalDist;
  }
  /// ease on by `dt` and place `c` (a free view aimed at the target)
  pub fn step(o:*Orbit,c:*camera.Camera,dt:f32)void{
    // how far this step eases: half way every `ease` seconds
    const k=1-m.pow(f32,0.5,dt/ease);
    o.target=m.lerpV(o.target,o.goal,k);
    o.dist=m.lerp(o.dist,o.goalDist,k);
    c.target=o.target;
    c.dist=o.dist;
    c.yaw=o.yaw;
    // the pitch's cosine, and the way out from the target to the eye
    const cp=@cos(o.pitch);
    const out=v3(@sin(o.yaw)*cp,@sin(o.pitch),@cos(o.yaw)*cp);
    c.view=.{.free=.{.pos=o.target+out*m.splat3(o.dist),.yaw=o.yaw,.pitch=-o.pitch}};
  }
};
/// Claude's ask of the view, through the link (`view.txt`, a word and its
/// numbers a line); each left out keeps the view as it is
pub const Ask=struct{
  /// the turn round the target (degrees, 0 looking down -z)
  yaw:?f32=null,
  /// how high over the target (degrees; past 90 goes over the top)
  pitch:?f32=null,
  /// how far from the target (m)
  dist:?f32=null,
  /// notches of the wheel nearer (negative: back)
  zoom:?f32=null,
  /// the point looked at, from the subject's foot (m)
  at:?V3=null,
  /// the target moved across the view: right, up, forward (m)
  pan:?V3=null,
  /// the form (meshedit, counted from 1) to frame first
  focus:?usize=null,
  /// back to the view the editor opened with first
  home:bool=false,
  /// what an ask's text can fail to read with
  pub const Error=error{BadView};
  /// the ask from its text; a word it does not know, or a number that
  /// will not read, is `BadView`
  pub fn parse(text:[]const u8)Error!Ask{
    // the ask being read, and the text's lines
    var a=Ask{};
    var lines=splitScalar(u8,text,'\n');
    while(lines.next())|raw|{
      // the line's words, and its first
      var it=tokenizeAny(u8,raw," \t\r");
      const word=it.next() orelse continue;
      if(eql(u8,word,"home")){
        a.home=true;
      }else if(eql(u8,word,"focus")){
        a.focus=parseInt(usize,it.next() orelse return error.BadView,10) catch return error.BadView;
      }else if(eql(u8,word,"at") or eql(u8,word,"pan")){
        // three numbers: x, y and z
        var p=v3(0,0,0);
        inline for(0..3)|i|p[i]=parseFloat(f32,it.next() orelse return error.BadView) catch return error.BadView;
        if(eql(u8,word,"at"))a.at=p else a.pan=p;
      }else{
        // one number, for the word it belongs to
        const x=parseFloat(f32,it.next() orelse return error.BadView) catch return error.BadView;
        if(eql(u8,word,"yaw"))a.yaw=x else if(eql(u8,word,"pitch"))a.pitch=x else if(eql(u8,word,"dist"))a.dist=x else if(eql(u8,word,"zoom"))a.zoom=x else return error.BadView;
      }
    }
    return a;
  }
};
test"an ask is read and taken at once: turned, placed, panned across the view"{
  // an orbit round the origin
  var o=Orbit.init(v3(0,0,0),1.6,m.rad(20));
  const a=try Ask.parse("yaw 90\npitch 0\ndist 0.5\nat 0 0.1 0\npan 0.2 0 0\n");
  o.take(a,v3(1,0,0));
  try testing.expectApproxEqAbs(@as(f32,0.5),o.dist,1e-5);
  try testing.expectApproxEqAbs(m.rad(90),o.yaw,1e-5);
  // looking down -x from +x (yaw 90), right is -z
  try testing.expect(m.dist(o.target,v3(1,0.1,-0.2))<1e-4);
  try testing.expect((try Ask.parse("focus 3\nhome")).focus.?==3);
  try testing.expectError(error.BadView,Ask.parse("spin 3"));
  try testing.expectError(error.BadView,Ask.parse("at 1 2"));
}
test"the camera eases onto a focused thing and turns past straight up"{
  // an orbit round the origin, and the camera it places
  var o=Orbit.init(v3(0,0,0),1.6,m.rad(20));
  var c:camera.Camera=.{};
  o.focus(v3(1,2,3),0.1);
  for(0..200)|_|o.step(&c,0.02);
  try testing.expect(m.dist(o.target,v3(1,2,3))<1e-3);
  try testing.expectApproxEqAbs(@max(0.1*focusFit,focusMin),o.dist,1e-3);
  try testing.expectApproxEqAbs(o.dist,m.dist(c.view.free.pos,o.target),1e-3);
  // dragged over the top, the view still looks at the target
  o.pitch=m.rad(120);
  o.step(&c,0);
  try testing.expect(m.len(c.view.free.pos+c.view.free.forward()*m.splat3(o.dist)-o.target)<1e-3);
}
