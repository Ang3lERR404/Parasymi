//! the starlit patches as the garden sees and hears them (where they lie is
//! world/starlit.zig's). By day a patch is a hint: its dark-blue field on
//! the ground (terrain.frag), a very faint haze over it and small star
//! sparks rising a little way and fading. By night a column of 5 to 9
//! coloured searchlights pours down on it from the sky, each wandering a
//! little and drifting through the rainbow, and sparks drift down it and
//! vanish; a wolf standing in one hears it twinkle now and then. When the
//! unforming begins each patch shoots its light up into the sky, where it
//! becomes stars, and stays dark.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error drawing may fail with
const Allocator=std.mem.Allocator;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, ramps, easing
const m=engine.core.math;
/// the sine hash each searchlight's and spark's draws come from
const noise=engine.core.noise;
/// the random stream the twinkles' gaps are drawn from
const Rng=engine.core.rng.Rng;
/// where the patches lie
const starlit=lib.starlit;
/// one patch
const Patch=starlit.Patch;
/// the game: its world, sky, camera, parts and the unforming
const Game=lib.play.Game;
/// the test harness
const testing=std.testing;
/// a patch's field: its blue when poorest and when richest (the richest
/// nearly the constellate lineage's own blue; linear, the same as
/// terrain.frag's STAR_POOR and STAR_RICH, lit)
const poorGlow=m.Vice(f32,3){0.32,0.5,1.0};
/// (the richest)
const richGlow=m.Vice(f32,3){0.06,0.22,1.0};
/// how bright its faint haze is, how far over the ground it hangs (m) and
/// how far it reaches (a share of the patch's radius)
const hazeLight:f32=0.12;
/// (how high)
const hazeHigh:f32=1.2;
/// (how far)
const hazeReach:f32=1.8;
/// its sparks by day: how many for each metre of its radius and at the
/// least, how far they rise (m), how big they are, how brightly they glow
const daySparks:f32=3;
/// (at the least)
const daySparksMin:f32=4;
/// (how far they rise)
const dayRise:f32=1.6;
/// (how big)
const daySize:f32=0.9;
/// (how bright)
const dayGlow:f32=1.1;
/// its sparks by night: how many for each metre of its radius and at the
/// least, how high they drift down from (m), how big, how bright, and how
/// much of a rainbow hue tints each over its patch's blue
const nightSparks:f32=3;
/// (at the least)
const nightSparksMin:f32=6;
/// (how high)
const nightFall:f32=9;
/// (how big)
const nightSize:f32=1.1;
/// (how bright)
const nightGlow:f32=1.4;
/// (how much rainbow)
const nightHue:f32=0.55;
/// its night column (the gardener's draft v2): the fewest and most
/// searchlights (each patch its own count), how high over the patch they
/// shine from (m), how far each one's foot wanders from the middle and how
/// wide it is (shares of the patch's width), how far round a foot swings
/// (radians), how far past the ground they reach (a share of their
/// height), how bright each is
const columnFew=5;
/// (the most)
const columnMost=9;
/// (how high)
const columnHigh:f32=16;
/// (how far a foot wanders)
const columnLand:f32=0.45;
/// (how wide a foot is)
const columnFoot:f32=0.35;
/// (how far round it swings)
const columnWander:f32=0.6;
/// (how far past the ground)
const columnReach:f32=1.25;
/// (how bright)
const columnLight:f32=5;
/// how far round the patch's middle the searchlights shine from (a share
/// of its radius): apart, each colour keeps to its own shaft
const columnSpread:f32=0.9;
/// a searchlight's slow and fast swings: the range each one's pace is
/// drawn from (radians a second)
const swingSlow=m.Vice(f32,2){0.09,0.18};
/// (its faster swing)
const swingFast=m.Vice(f32,2){0.21,0.37};
/// how fast a searchlight's colour drifts through the rainbow (turns a
/// second), how much white softens it (never white itself), how far it
/// breathes either way and the range of its breath's pace (radians a second)
const hueRate:f32=0.02;
/// (how much white)
const pearl:f32=0.06;
/// (how far it breathes)
const breath:f32=0.25;
/// (its pace)
const breathRate=m.Vice(f32,2){0.4,0.9};
/// the weights a patch's draws are hashed with (its seed, the light, which draw)
const drawWeights=m.Vice(f32,3){127.1,311.7,74.7};
/// the unforming: seconds a patch takes to shoot its light up into the
/// sky, how much brighter it flares as it goes, how high up it reaches
/// (m) and how narrow its upward lights are (the cosine of their half-width)
const shootTime:f32=4;
/// (how much brighter)
const shootFlare:f32=2.5;
/// (how high)
const shootReach:f32=40;
/// (how narrow)
const shootHalf:f32=0.97;
/// a twinkle near: how deep in a shining patch's night the wolf must stand
/// for one, the seconds between twinkles (least and most) and how far off
/// round the wolf one is heard (m)
const twinkleFrom:f32=0.15;
/// (the gaps)
const twinkleGap=m.Vice(f32,2){2.5,8};
/// (how far off)
const twinkleOff:f32=3;
/// how far round the camera's target patches are gathered beyond the
/// drawn reach (tiles), and the steps the gathering is kept for (tiles)
const gatherPad:f32=24;
/// (the steps)
const gatherStep:f32=16;
/// a spark near the wolf twinkled, for what hears it (game/sound.zig)
pub const Twinkle=struct{
  /// how near and bright it was: 0 faint .. 1 in the heart of a column
  near:f32,
  /// where it was (heard from there)
  at:m.V3=@splat(0),
};
/// the patches round the camera, kept while it stays near, and the
/// twinkles the wolf hears in them
pub const Starlight=struct{
  /// the random stream the twinkles' gaps and places are drawn from
  rng:Rng,
  /// seconds until a spark near may twinkle
  quiet:f32=0,
  /// the twinkle since `twinkled` last took it
  twinkle:?Twinkle=null,
  /// the patches round the camera
  near:starlit.Near=.{.world=0},
  /// the step and reach they were gathered for (none: never yet)
  key:?m.Vice(i32,3)=null,
  /// the twinkle since last asked, once
  pub fn twinkled(sl:*Starlight)?Twinkle{
    defer sl.twinkle=null;
    return sl.twinkle;
  }
  /// after a quiet gap, a spark round the wolf twinkles if it stands in a
  /// shining patch by night
  pub fn listen(sl:*Starlight,g:*const Game,dt:f32)void{
    sl.quiet-=dt;
    if(sl.quiet>0)return;
    sl.quiet=sl.rng.range(twinkleGap[0],twinkleGap[1]);
    // how deep in a shining patch's night the wolf stands
    const deep=fieldAt(g,g.player.pos)*(1-g.sky.daylight())*(1-dark(g));
    if(deep<twinkleFrom)return;
    // a spark somewhere round it
    const a=sl.rng.range(0,m.tau);
    const r=sl.rng.range(0.5,twinkleOff);
    sl.twinkle=.{.near=deep,.at=g.player.pos+m.v3(@cos(a)*r,sl.rng.range(0.5,3),@sin(a)*r)};
  }
  /// the patches round `around`, `reach` tiles out, gathered again only
  /// once the camera has moved a step on or the reach changed
  fn gather(sl:*Starlight,world:u64,around:m.V3,reach:f32)void{
    // the step it stands in, and the reach
    const key=m.Vice(i32,3){m.tileOf(around[0]/gatherStep),m.tileOf(around[2]/gatherStep),m.tileOf(reach/gatherStep)};
    if(sl.key)|k|if(k[0]==key[0] and k[1]==key[1] and k[2]==key[2] and sl.near.world==world)return;
    sl.key=key;
    // how far round it to gather
    const r=reach+gatherPad;
    sl.near=starlit.Near.of(world,m.tileOf(around[0]-r),m.tileOf(around[2]-r),m.tileOf(around[0]+r),m.tileOf(around[2]+r));
  }
  /// every patch round the camera within `reach`: its haze and sparks by
  /// day, its column and sparks by night, its light shot up at the unforming
  pub fn draw(sl:*Starlight,g:*Game,reach:f32,tf:f32)Allocator.Error!void{
    sl.gather(g.world.seed,g.cam.target,reach);
    // how far the patches have gone dark, how deep the night is
    const gone=dark(g);
    if(gone>=1)return;
    const night=1-g.sky.daylight();
    for(sl.near.all())|p|{
      // its middle on the ground
      const at=m.v3(p.at[0],g.heightAt(m.tileOf(p.at[0]),m.tileOf(p.at[1])),p.at[1]);
      if(m.dist(at,g.cam.target)>reach+p.r)continue;
      // its own blue, and how much of it is left
      const blue=m.lerpV(poorGlow,richGlow,p.rich);
      const left=1-gone;
      try g.parts.light(at+m.v3(0,hazeHigh,0),blue*m.splat3(hazeLight*left),p.r*hazeReach);
      try sparks(g,p,at,blue,night,left,tf);
      if(gone>0)try shoot(g,p,at,gone,tf)else if(night>0)try column(g,p,at,night,tf);
    }
  }
};
/// how far the patches have gone dark: 0 shining .. 1 dark for good, as
/// the unforming shoots their light up into the sky
pub fn dark(g:*const Game)f32{
  if(g.unforming.phase==.waiting)return 0;
  return m.clamp01(g.unforming.t/shootTime);
}
/// how far inside a patch the ground under `at` lies (0 off any, or not streamed)
fn fieldAt(g:*const Game,at:m.V3)f32{
  // the tile, and its chunk
  const tx=m.tileOf(at[0]);
  const ty=m.tileOf(at[2]);
  const c=g.world.chunkOfTile(tx,ty) orelse return 0;
  return c.star[lib.ck.localIndex(tx,ty)];
}
/// a draw 0..1 for light `k` of patch `p`, the `which`th
fn drawOf(p:Patch,k:usize,which:u32)f32{return noise.sineHash(3,.{p.seed*97.3,m.f(k),m.f(which)},drawWeights);}
/// how many searchlights patch `p` has: 5 to 9, its own
pub fn lightsOf(p:Patch)usize{
  return columnFew+@as(usize,@intFromFloat(@floor(drawOf(p,0,9)*m.f(columnMost-columnFew+1)*0.999)));
}
/// a patch's sparks: rising a little way by day, drifting down its column
/// by night, each tinted its patch's blue (and by night a rainbow hue)
fn sparks(g:*Game,p:Patch,at:m.V3,blue:m.V3,night:f32,left:f32,tf:f32)Allocator.Error!void{
  // by day: how many, and how bright
  const day=1-night;
  if(day*left>0){
    const n:usize=@intFromFloat(daySparksMin+daySparks*p.r);
    for(0..n)|k|try g.parts.emitSpark(at,p.seed*31+m.f(k)*1.618,dayRise,p.r,daySize,.{.glow=dayGlow*day*left,.phase=m.ratio(k,n),.tint=.{blue[0],blue[1],blue[2],0.85}});
  }
  if(night*left>0){
    const n:usize=@intFromFloat(nightSparksMin+nightSparks*p.r);
    for(0..n)|k|{
      // its own hue, drifting, over its patch's blue
      const hue=m.lerpV(blue,lib.view.rainbow(drawOf(p,k,7)+tf*hueRate),nightHue);
      try g.parts.emitSpark(at,p.seed*53+m.f(k)*1.618,-nightFall,p.r*columnLand,nightSize,.{.glow=nightGlow*night*left,.phase=m.ratio(k,n),.tint=.{hue[0],hue[1],hue[2],0.85}});
    }
  }
}
/// a patch's night column (draft v2): its searchlights high over it
/// pointing down, each wandering a little over the patch, overlapping into
/// one column that shifts through the rainbow from within
fn column(g:*Game,p:Patch,at:m.V3,night:f32,tf:f32)Allocator.Error!void{
  // how wide each one's foot is, as the cosine of its half-width
  const t=p.r*columnFoot/columnHigh;
  const half=1/@sqrt(1+t*t);
  const n=lightsOf(p);
  for(0..n)|k|{
    // this light's own random draws
    const h=[_]f32{drawOf(p,k,1),drawOf(p,k,2),drawOf(p,k,3),drawOf(p,k,4),drawOf(p,k,5),drawOf(p,k,6)};
    // where it lands: a point wandering within the patch, on two paces of its own
    const a=m.ratio(k,n)*m.tau+h[0]+columnWander*@sin(tf*m.lerp(swingSlow[0],swingSlow[1],h[1])+h[2]*m.tau);
    const d=p.r*columnLand*(0.5+0.5*@sin(tf*m.lerp(swingFast[0],swingFast[1],h[3])*0.5+h[4]*m.tau));
    const land=at+m.v3(@cos(a)*d,0,@sin(a)*d);
    // where it shines from: high over the patch, spread round its middle
    // the way it lands, so each colour keeps to its own shaft in the air
    const from=at+m.v3(@cos(a+h[5])*p.r*columnSpread,columnHigh,@sin(a+h[5])*p.r*columnSpread);
    // its colour, drifting through the rainbow, and its breath
    const col=m.lerpV(lib.view.rainbow(m.ratio(k,n)+tf*hueRate*(0.6+h[3])),m.v3(1,1,1),pearl);
    const swell=1+breath*@sin(tf*m.lerp(breathRate[0],breathRate[1],h[4])+h[5]*m.tau);
    try g.parts.spot(from,m.norm(land-from),half,col*m.splat3(columnLight*swell*night),columnHigh*columnReach);
  }
}
/// a patch shooting its light up into the sky (the unforming, `gone` of
/// the way): its searchlights turned upward from the ground, flaring, then
/// fading as the light leaves to become stars
fn shoot(g:*Game,p:Patch,at:m.V3,gone:f32,tf:f32)Allocator.Error!void{
  // how bright it is now: a flare that fades away
  const glow=shootFlare*(1-gone)*(1-gone)*m.smooth(m.clamp01(gone*6));
  const n=lightsOf(p);
  for(0..n)|k|{
    // where on the patch it leaves from, and the way up it leans
    const a=m.ratio(k,n)*m.tau+drawOf(p,k,1);
    const d=p.r*columnLand*drawOf(p,k,2);
    const from=at+m.v3(@cos(a)*d,0.2,@sin(a)*d);
    const way=m.norm(m.v3(@cos(a)*0.08,1,@sin(a)*0.08));
    const col=m.lerpV(lib.view.rainbow(m.ratio(k,n)+tf*hueRate),m.v3(1,1,1),pearl);
    try g.parts.spot(from,way,shootHalf,col*m.splat3(columnLight*glow),shootReach*(0.3+0.7*m.smooth(gone)));
  }
}
test"a patch has five to nine searchlights, each its own"{
  // how many each of many patches has
  var seen=m.Vice(bool,10){false,false,false,false,false,false,false,false,false,false};
  for(0..400)|i|{
    // a patch of its own seed
    const p=Patch{.at=.{0,0},.r=3,.rich=0.5,.pool=false,.seed=m.ratio(i,400)};
    const n=lightsOf(p);
    try testing.expect(n>=columnFew and n<=columnMost);
    seen[n]=true;
  }
  for(columnFew..columnMost+1)|n|try testing.expect(seen[n]);
}
