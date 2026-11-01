//! the loading screen: a living night with the garden's name and a tendril
//! growing across it as far as what is made goes, leaves opening along it
//! as it passes them, under it what is being made and how much is made and
//! left. Shown while the meshes grow (on their own thread), the world wakes
//! and its ground is meshed; then it fades off the first frames of play.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the draw batch grows with
const Allocator=std.mem.Allocator;
/// all the maths: easing, clamps, angles
const m=lib.engine.core.math;
/// the garden's renderer, whose frame scene this fills
const renderer=lib.renderer;
/// the camera, for a midnight view behind the screen
const Camera=lib.engine.render.camera.Camera;
/// the UI's draw module
const drawMod=lib.engine.ui.draw;
/// the UI's draw batch the screen is drawn into
const Draw=drawMod.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=drawMod.Color;
/// the sky, for the midnight light and fog
const Sky=lib.sky.Sky;
/// the HUD's shared sizes and colours
const s=lib.style;
/// every player-facing string, for the stage names and counts
const txt=lib.txt;
/// what is being made, in order (`txt.s.loading.stages` names each)
pub const Stage=enum{
  /// the meshes, grown on their own thread
  forms,
  /// the world waking
  world,
  /// its ground being meshed
  ground
};
/// how much is made of how much, all stages together
pub const Progress=struct{
  /// how many things are made
  done:u32,
  /// how many there are to make
  total:u32
};
/// the night behind everything: its colour (opaque)
const night:Color=.{14,12,22,255};
/// the night's seed, so its stars fall the same way each time
const nightSeed:f32=0.37;
/// the tendril: its share of the screen's width (at most `barMax` px); the
/// name sits `titleUp` over it, the stage and counts `labelDown` under it
const barShare:f32=0.42;
/// the tendril's widest, in pixels
const barMax:f32=720;
/// how thick the tendril is, in pixels
const barH:f32=18;
/// how far below the middle of the screen it lies, in pixels
const barDown:f32=40;
/// how far above the tendril the garden's name sits, in pixels
const titleUp:f32=110;
/// how far below it the stage and counts sit, in pixels
const labelDown:f32=34;
/// the tendril's seed, for its shape in ui.frag
const barSeed:f32=0.2;
/// the tendril's sway as ui.frag draws it (its `tendril`), matched so the
/// leaves stay on it: how many waves run along it
const waves:f32=18;
/// how fast the waves run along it
const waveRate:f32=2;
/// how much its seed shifts the waves' phase
const waveSeed:f32=7;
/// how far the waves reach, as a share of its thickness
const waveReach:f32=0.18;
/// leaves along it, alternating sides: how many
const leaves=11;
/// how long a fully open leaf is, in pixels
const leafLen:f32=40;
/// how broad a fully open leaf is, in pixels
const leafWide:f32=16;
/// how far each leaf leans back from upright (radians)
const leafLean:f32=0.55;
/// the share of the tendril the growing front takes to open a leaf fully
const leafOpens:f32=0.06;
/// the glow at the tendril's growing tip
const tipGlow:Color=.{255,215,130,110};
/// a leaf not yet reached: a dim closed bud
const bud:Color=.{60,90,60,200};
/// the shown share eases toward what is made at this rate (1/s), so the
/// tendril grows rather than jumps
const ease:f32=9;
/// the screen fades off play over this long (s)
const fadeTime:f32=0.6;
/// the night sky the world passes draw behind it (hidden by the night, but
/// a real view so nothing in them is degenerate): midnight
const tod:f32=0;
/// shader time wraps this often (s) so f32 keeps its precision
const timeWrap:f64=3600;
/// no hovered tile: a position far off any tile
const noHover:f32=1e9;
/// the loading screen: its own draw batch, clock, the share shown, its
/// fade, and what it is making
pub const Loading=struct{
  /// the screen's own draw batch
  ui:Draw,
  /// its own clock (handed to play when it starts, so nothing jumps)
  time:f64=0,
  /// the share shown, easing toward what is made
  shown:f32=0,
  /// 1 while loading, falling to 0 over play's first frames
  fade:f32=1,
  /// what is being made now
  stage:Stage=.forms,
  /// how far it has come, all stages together
  at:Progress=.{.done=0,.total=1},
  /// a fresh loading screen, drawing with `gpa`
  pub fn init(gpa:Allocator)Loading{return.{.ui=.{.gpa=gpa}};}
  /// frees its draw batch
  pub fn deinit(l:*Loading)void{l.ui.deinit();}
  /// a frame of loading: `at` is how far it has come
  pub fn step(l:*Loading,stage:Stage,at:Progress,dt:f32)void{
    l.stage=stage;
    l.at=at;
    l.time+=dt;
    // the share made, which the shown one eases toward
    const want=share(at);
    l.shown=@min(want,m.damp(l.shown,want,ease,dt));
  }
  /// a frame of play once loaded: the screen fades off it
  pub fn fadeStep(l:*Loading,dt:f32)void{
    l.fade=@max(0,l.fade-dt/fadeTime);
    l.shown=1;
    l.at.done=l.at.total;
  }
  /// whether it is still fading off play
  pub fn fading(l:*const Loading)bool{return l.fade>0;}
  /// shown again from the start (a garden loaded in play)
  pub fn again(l:*Loading)void{
    l.fade=1;
    l.shown=0;
  }
  /// the screen drawn into `d` (over what is there), at its fade
  pub fn draw(l:*const Loading,d:*Draw,w:f32,h:f32)Allocator.Error!void{
    // the fade, and the shader time, wrapped
    const a=l.fade;
    const t:f32=@floatCast(@mod(l.time,timeWrap));
    try d.night(w,h,fade(night,a),nightSeed);
    // the garden's name, and the middle of the screen
    const name=txt.s.window.title;
    const cy=h/2;
    _=try d.text(w/2-Draw.width(name,s.textBanner*2)/2,cy-titleUp,s.textBanner*2,fade(s.gold,a),name);
    // the tendril's width, left edge and top
    const bw=@min(w*barShare,barMax);
    const bx=(w-bw)/2;
    const by=cy+barDown;
    // leaves first, so the tendril lies over their bases
    for(0..leaves)|i|{
      // where this leaf sits along the tendril (0..1) and which side
      const k=(m.f(i)+0.5)/leaves;
      const side:f32=if(i%2==0)-1 else 1;
      // how open it is: fully once the front is a little past it
      const open=m.smooth(m.clamp01((l.shown-k)/leafOpens));
      // the tendril's wave here, and the leaf's base on it
      const wave=@sin(k*waves+t*waveRate+barSeed*waveSeed)*barH*waveReach;
      const base=m.Vice(f32,2){bx+k*bw,by+barH/2+wave};
      // swept forward, the way it grows, lifting as they open
      const ang=side*(m.tau/4.0-leafLean*(1-0.3*open));
      try d.leaf(base,ang,leafLen*(0.35+0.65*open),leafWide*(0.6+0.4*open),fade(if(open>0)s.leaf else bud,a),open,m.f(i)*0.37);
    }
    try d.tendril(bx,by,bw,barH,fade(s.growth,a),l.shown,barSeed);
    if(l.shown>0)try d.glow(bx+l.shown*bw,by+barH/2,barH*2.2,fade(tipGlow,a));
    // the line under the tendril
    const ly=by+barH+labelDown;
    // what is being made, named
    const stage=txt.nth(txt.s.loading.stages,@intFromEnum(l.stage));
    _=try d.text(bx,ly,s.textLabel,fade(s.white,a),stage);
    // room for the percentage, and the percentage itself
    var buf:[32]u8=undefined;
    const pct=txt.bufRender(&buf,txt.s.loading.percent,.{@as(u32,@intFromFloat(@floor(share(l.at)*100)))});
    _=try d.text(bx+bw-Draw.width(pct,s.textLabel),ly,s.textLabel,fade(s.gold,a),pct);
    // room for the counts, how many are made, and the counts line
    var lb:[64]u8=undefined;
    const done=@min(l.at.done,l.at.total);
    const left=txt.bufRender(&lb,txt.s.loading.left,.{done,l.at.total-done});
    _=try d.text(w/2-Draw.width(left,s.textSmall)/2,ly+labelDown,s.textSmall,fade(s.dim,a),left);
  }
  /// a loading frame: nothing of the world (none of it is made yet) under
  /// the screen, a midnight sky behind it for the world passes
  pub fn scene(l:*Loading,screen:m.Vice(f32,2))Allocator.Error!renderer.Scene{
    l.ui.clear(@floatCast(l.time));
    try l.draw(&l.ui,screen[0],screen[1]);
    // a camera at its rest, and a midnight sky
    const cam:Camera=.{.aspect=screen[0]/@max(screen[1],1)};
    const sky:Sky=.{.tod=tod};
    // the eye, the sun's direction, and the fog colour
    const eye=cam.viewEye();
    const ld=sky.lightDir();
    const c=sky.color(0);
    // how far the fog reaches: as far as the camera stands off
    const reach=cam.dist;
    // the shader time, wrapped
    const tf:f32=@floatCast(@mod(l.time,timeWrap));
    return.{
      .push=.{
        .vp=cam.viewProj(),
        .eyeTime=.{eye[0],eye[1],eye[2],tf},
        .fog=.{c[0],c[1],c[2],1/reach},
        .misc=.{0,0,noHover,noHover},
        .sun=.{ld[0],ld[1],ld[2],sky.daylight()},
        .view=.{cam.target[0],cam.target[2],reach,reach},
        .feet=@splat(.{0,0,0,0}),
      },
      .clear=c,
      .instances=@splat(&.{}),
      .parts=@splat(&.{}),
      .bones=&.{},
      .lights=&.{},
      .ui=l.ui.v.items,
      .uiTime=tf,
    };
  }
};
/// how much of the whole is made, 0..1
fn share(at:Progress)f32{
  if(at.total==0)return 1;
  return m.clamp01(m.f(at.done)/m.f(at.total));
}
/// `c` with its alpha scaled by `a`
fn fade(c:Color,a:f32)Color{
  return.{c[0],c[1],c[2],m.unorm8(m.f(c[3])/255*a)};
}
