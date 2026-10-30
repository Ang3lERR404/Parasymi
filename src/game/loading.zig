//! the loading screen: a living night with the garden's name and a tendril
//! growing across it as far as what is made goes, leaves opening along it
//! as it passes them, under it what is being made and how much is made and
//! left. Shown while the meshes grow (on their own thread), the world wakes
//! and its ground is meshed; then it fades off the first frames of play.
const lib=@import("../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const m=lib.engine.core.math;
const renderer=lib.renderer;
const Camera=lib.engine.render.camera.Camera;
const drawMod=lib.engine.ui.draw;
const Draw=drawMod.Draw;
const Color=drawMod.Color;
const Sky=lib.sky.Sky;
const s=lib.style;
const txt=lib.txt;
/// what is being made, in order (`txt.s.loading.stages` names each)
pub const Stage=enum{forms,world,ground};
/// how much is made of how much, all stages together
pub const Progress=struct{done:u32,total:u32};
/// the night: its colour (opaque) and seed
const night:Color=.{14,12,22,255};
const nightSeed:f32=0.37;
/// the tendril: share of the screen's width (at most `BAR_MAX` px), how
/// thick, how far below the middle; the name sits `TITLE_UP` over it, the
/// stage and counts `LABEL_DOWN` under it
const barShare:f32=0.42;
const barMax:f32=720;
const barH:f32=18;
const barDown:f32=40;
const titleUp:f32=110;
const labelDown:f32=34;
const barSeed:f32=0.2;
/// the tendril's sway as ui.frag draws it (its `tendril`): waves along it,
/// how fast they run, how far they reach (a share of its thickness), so the
/// leaves stay on it
const waves:f32=18;
const waveRate:f32=2;
const waveSeed:f32=7;
const waveReach:f32=0.18;
/// leaves along it, alternating sides: how many, how long and broad, how
/// far each leans back from upright, and the share of the tendril it takes
/// the front to open one fully
const leaves=11;
const leafLen:f32=40;
const leafWide:f32=16;
const leafLean:f32=0.55;
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
pub const Loading=struct{
  ui:Draw,
  /// its own clock (handed to play when it starts, so nothing jumps)
  time:f64=0,
  /// the share shown, easing toward what is made
  shown:f32=0,
  /// 1 while loading, falling to 0 over play's first frames
  fade:f32=1,
  stage:Stage=.forms,
  at:Progress=.{.done=0,.total=1},
  pub fn init(gpa:Allocator)Loading{return.{.ui=.{.gpa=gpa}};}
  pub fn deinit(l:*Loading)void{l.ui.deinit();}
  /// a frame of loading: `at` is how far it has come
  pub fn step(l:*Loading,stage:Stage,at:Progress,dt:f32)void{
    l.stage=stage;
    l.at=at;
    l.time+=dt;
    const want=share(at);
    l.shown=@min(want,l.shown+(want-l.shown)*m.clamp01(dt*ease));
  }
  /// a frame of play once loaded: the screen fades off it
  pub fn fadeStep(l:*Loading,dt:f32)void{
    l.fade=@max(0,l.fade-dt/fadeTime);
    l.shown=1;
    l.at.done=l.at.total;
  }
  pub fn fading(l:*const Loading)bool{return l.fade>0;}
  /// shown again from the start (a garden loaded in play)
  pub fn again(l:*Loading)void{
    l.fade=1;
    l.shown=0;
  }
  /// the screen drawn into `d` (over what is there), at its fade
  pub fn draw(l:*const Loading,d:*Draw,w:f32,h:f32)Allocator.Error!void{
    const a=l.fade;
    const t:f32=@floatCast(@mod(l.time,timeWrap));
    try d.night(w,h,fade(night,a),nightSeed);
    const name=txt.s.window.title;
    const cy=h/2;
    _=try d.text(w/2-Draw.width(name,s.textBanner*2)/2,cy-titleUp,s.textBanner*2,fade(s.gold,a),name);
    const bw=@min(w*barShare,barMax);
    const bx=(w-bw)/2;
    const by=cy+barDown;
    // leaves first, so the tendril lies over their bases
    for(0..leaves)|i|{
      const k=(m.f(i)+0.5)/leaves;
      const side:f32=if(i%2==0)-1 else 1;
      const open=m.smooth(m.clamp01((l.shown-k)/leafOpens));
      const wave=@sin(k*waves+t*waveRate+barSeed*waveSeed)*barH*waveReach;
      const base=[2]f32{bx+k*bw,by+barH/2+wave};
      // swept forward, the way it grows, lifting as they open
      const ang=side*(m.tau/4.0-leafLean*(1-0.3*open));
      try d.leaf(base,ang,leafLen*(0.35+0.65*open),leafWide*(0.6+0.4*open),fade(if(open>0)s.leaf else bud,a),open,m.f(i)*0.37);
    }
    try d.tendril(bx,by,bw,barH,fade(s.growth,a),l.shown,barSeed);
    if(l.shown>0)try d.glow(bx+l.shown*bw,by+barH/2,barH*2.2,fade(tipGlow,a));
    const ly=by+barH+labelDown;
    const stage=txt.nth(txt.s.loading.stages,@intFromEnum(l.stage));
    _=try d.text(bx,ly,s.textLabel,fade(s.white,a),stage);
    var buf:[32]u8=undefined;
    const pct=txt.bufRender(&buf,txt.s.loading.percent,.{@as(u32,@intFromFloat(@floor(share(l.at)*100)))});
    _=try d.text(bx+bw-Draw.width(pct,s.textLabel),ly,s.textLabel,fade(s.gold,a),pct);
    var lb:[64]u8=undefined;
    const done=@min(l.at.done,l.at.total);
    const left=txt.bufRender(&lb,txt.s.loading.left,.{done,l.at.total-done});
    _=try d.text(w/2-Draw.width(left,s.textSmall)/2,ly+labelDown,s.textSmall,fade(s.dim,a),left);
  }
  /// a loading frame: nothing of the world (none of it is made yet) under
  /// the screen, a midnight sky behind it for the world passes
  pub fn scene(l:*Loading,screen:[2]f32)Allocator.Error!renderer.Scene{
    l.ui.clear(@floatCast(l.time));
    try l.draw(&l.ui,screen[0],screen[1]);
    const cam:Camera=.{.aspect=screen[0]/@max(screen[1],1)};
    const sky:Sky=.{.tod=tod};
    const eye=cam.viewEye();
    const ld=sky.lightDir();
    const c=sky.color(0);
    const reach=cam.dist;
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
