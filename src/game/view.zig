//! what gets drawn: turns the game state into a render Scene (plant
//! instances, rigid parts, HUD, sky/fog/light push constants). Read-only with
//! respect to the simulation.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type drawing may fail with
const Allocator=std.mem.Allocator;
/// an in-place sort, for ranking the lights
const pdq=std.sort.pdq;
/// trading two values' places
const swap=std.mem.swap;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, matrices, easing, tiles
const m=engine.core.math;
/// hashing a tile or index to a steady random value
const rng=engine.core.rng;
/// the chunk layer: tiles, coordinates
const ck=lib.ck;
/// every plant kind's definition
const species=lib.species;
/// the garden's plants: where a preview put down from the cursor stands
const Plants=lib.plants.Plants;
/// turning (R): how a turning thing is posed
const turn=lib.turn;
/// the garden's renderer: its scene, lights and limits
const renderer=lib.renderer;
/// plant meshes: variants, levels of detail, growth keys
const meshgen=lib.meshgen;
/// the vertex layouts: plant instances, lights, halos
const vertex=lib.vertex;
/// the structures registry: kinds, defs, their own extras
const st=lib.structures;
/// the halo structure, whose forming spiral draws blooms in
const haloMod=lib.haloStructure;
/// resource nodes: their meshes and glows
const resources=lib.resources;
/// the gardener's actions, for whether a preview fits
const actions=lib.actions;
/// plucking: a drawn plant's size, the plucked plant's bend
const pluck=lib.pluck;
/// the HUD, built into the scene each frame
const hud=lib.hud;
/// the playable layer: draw limit, what is known
const play=lib.play;
/// the game whose state is drawn
const Game=play.Game;
/// world generation, for how full a resource node starts
const gen=lib.gen;
/// shader time wraps this often (s) so f32 keeps its precision
const timeWrap:f64=3600;
/// no hovered tile: a position far off any tile
const noHover:f32=1e9;
/// no wolf: its paws' contact shadows far off any tile
const noFeet=[2]m.V3{m.splat3(noHover),m.splat3(noHover)};
/// fog thickens over this many chunks' eighths past the camera distance
const fogReach:f32=32*ck.sizeTiles/8;
/// fog starts to close in at this share of the drawn reach
const fogNear:f32=0.7;
/// a plant's bounding sphere: this much (tiles) plus its footprint
const plantBound:f32=1.2;
/// the share of the way up a plant its bounding sphere is centred
const plantBoundUp:f32=0.6;
/// how far out from a broad plant's centre (metres a tile past the first)
/// the paws find its yield, on the side facing the wolf
const pluckOut:f32=0.45;
/// floaters: how far they bob (metres), a slow rise and a quicker one
const bobAmount=[2]f32{0.07,0.025};
/// floaters: how fast each bob runs (radians a second)
const bobRate=[2]f32{0.5,1.13};
/// floaters: how far they drift about their point (metres)
const drift:f32=0.05;
/// floaters: how fast they drift, across and along (radians a second)
const driftRate=[2]f32{0.31,0.27};
/// a floater's shadow radius (metres), on the ground beneath it
const shadowR:f32=0.42;
/// how much the shadow shrinks for each metre the floater rises
const shadowShrink:f32=0.6;
/// how far (metres) the shadow sits above the ground
const shadowLift:f32=0.03;
/// how faint the shadow is, 0..1
const shadowFade:f32=0.6;
/// beams: how far they bow (metres)
const beamSag:f32=0.03;
/// beams: how fast they bow (radians a second)
const beamSagRate:f32=0.4;
/// beams: the share of a bloom's growth past which its beam reaches out
const beamFrom:f32=0.85;
/// how bright a beam of a dark network is, against a radiating one's 1
const beamDim:f32=0.1;
/// structures breathe at one tempo (radians a second)
const breathRate:f32=1.6;
/// how deep a resting structure breathes (a share of its size)
const breathAmount:f32=0.02;
/// how much deeper it breathes at full activity
const breathActive:f32=0.04;
/// how a resting structure glows
const glow:f32=0.25;
/// how much more it glows at full activity
const glowActive:f32=1.1;
/// how much a standing structure's leaves flutter
const flutterAmount:f32=0.6;
/// placement preview: the fixed plant seed, so it holds one shape
const ghostSeed:f32=0.37;
/// placement preview: how far (metres) a structure ghost floats over the ground
const ghostLift:f32=0.02;
/// placement preview: how much smaller a structure ghost is
const ghostScale:f32=0.96;
/// placement preview: the tint where it fits (red, green, blue, alpha)
const ghostFits=[4]f32{0.6,1.4,0.8,0.7};
/// placement preview: the tint where it cannot go
const ghostBlocked=[4]f32{1.6,0.4,0.4,0.8};
/// placement preview: how fast a structure ghost's glow pulses (radians a second)
const ghostPulseRate:f32=5;
/// a structure ghost's glow, pulsing about this
const ghostGlow:f32=0.6;
/// how far the ghost's glow pulses either way
const ghostPulse:f32=0.4;
/// resource nodes shrink to `nodeMin` of full size as they empty
const nodeMin:f32=0.55;
/// star motes: their size
const moteSize:f32=1.8;
/// how many echoes trail a falling mote
const echoes=3;
/// an echo's size, shrinking further for each one behind
const echoSize:f32=1.2;
/// points of light. A celestial bloom: how far its light reaches (metres)
const bloomReach:f32=9;
/// how strong a bloom's light is
const bloomLight:f32=3.5;
/// a dark network's bloom's light, as a share of a radiating one's
const bloomDark:f32=0.2;
/// how high (metres) over its float a bloom's core sheds its light
const bloomCore:f32=0.35;
/// how much of its pearl's film tints a bloom's light, 0..1
const bloomFilm:f32=0.35;
/// how far a bloom's light pulses either way (a share)
const bloomPulse:f32=0.15;
/// how fast it pulses (radians a second)
const bloomPulseRate:f32=1.1;
/// a bloom sheds light only once it has assembled this far
const bloomLitFrom:f32=0.6;
/// a star mote's light: its reach (metres)
const moteReach:f32=3.2;
/// a star mote's light: its strength
const moteLight:f32=0.9;
/// a star mote's light: its colour (linear)
const moteCol=m.V3{1.0,0.86,0.62};
/// a glowing resource node (ley shards): its light's reach (metres)
const nodeReach:f32=2.6;
/// a glowing node's light: its strength
const nodeLight:f32=0.45;
/// a glowing node's light: its colour (linear)
const nodeCol=m.V3{0.5,0.3,1.0};
/// how high (metres) over its tile a glowing node's light sits
const nodeLift:f32=0.3;
/// turning (R, sim/turn.zig): how high (metres) a rooted thing heaves
/// itself up on its roots
const heaveAmount:f32=0.16;
/// how much higher it heaves for each tile of its size
const heavePer:f32=0.12;
/// how many roots it turns on for each tile of its size
const rootsPer:f32=3;
/// the fewest roots it turns on
const rootsMin:f32=4;
/// where its roots leave its foot (a share of its size from its middle)
const rootFoot:f32=0.14;
/// how far out its roots dig in (a share of its size)
const rootReach:f32=0.5;
/// how deep (a share of its size) its roots' tips lie at rest
const rootDeep:f32=0.35;
/// how high (a share of its size) its roots arch while out
const rootArch:f32=0.22;
/// how high (a share of its size) the roots' tips step as it turns on them
const rootStep:f32=0.1;
/// how many steps the tips take over one turn
const rootSteps:f32=3;
/// how much the roots flutter
const rootFlutter:f32=0.35;
/// the scene for this frame on a screen `screen` pixels across: the plants,
/// threads, the wolf, nodes, structures, ghost and motes as parts, the best
/// lights, the HUD, and the push constants for sky, fog, sun and view.
pub fn scene(g:*Game,screen:[2]f32)Allocator.Error!renderer.Scene{
  // how far round the camera target things are drawn (tiles), and the shader clock
  const reach=g.cam.reach(play.drawLimit);
  const tf:f32=@floatCast(@mod(g.time,timeWrap));
  // parts first: plants add parts of their own (shadows under floaters).
  // Everything is culled to what the camera sees and drawn at the level of
  // detail its distance from the eye calls for.
  g.parts.clear();
  g.parts.look(g.cam.viewEye(),m.Frustum.of(g.cam.viewProj()),g.sky.lightDir());
  try plants(g,reach,tf);
  try threads(g,tf);
  // a specimen stands alone: no wolf, ghosts or motes, and a plant no
  // nodes or structures (their meshes were never built)
  const alone=g.specimen!=null;
  // where the wolf's paws are, for their contact shadows (none when alone)
  // (but for one the wolf plucks)
  const feet=if(alone and !g.specimen.?.wolf())noFeet else try g.player.rig(&g.parts,g.headless());
  if(!alone or g.specimen.?.what==.structure){
    try nodes(g,@intFromFloat(reach));
    try structures(g,reach,tf);
  }
  if(!alone){
    try ghost(g,tf);
    try motes(g);
  }
  rankLights(g);
  try hud.build(g,screen);
  // the veil of what is not yet understood, and the sky's colour under it
  const veil=g.prog.veil;
  const sky=g.sky.color(veil);
  // the eye, the hovered tile (far off when none), and the sun's heading
  const eye=g.cam.viewEye();
  const hv:[2]f32=if(g.hover)|h|.{m.f(h[0]),m.f(h[1])}else.{noHover,noHover};
  const ld=g.sky.lightDir();
  // the scene, its instance lists filled from the plants just gathered
  var out:renderer.Scene=.{
    .push=.{
      .vp=g.cam.viewProj(),
      .eyeTime=.{eye[0],eye[1],eye[2],tf},
      .fog=.{sky[0],sky[1],sky[2],1.0/(fogReach+g.cam.dist)},
      .misc=.{veil,if(g.prog.done.contains(.leySight))1 else 0,hv[0],hv[1]},
      .sun=.{ld[0],ld[1],ld[2],g.sky.daylight()},
      .view=.{g.cam.target[0],g.cam.target[2],reach*fogNear,reach},
      .feet=.{
        .{feet[0][0],feet[0][1],feet[0][2],g.player.facing},
        .{feet[1][0],feet[1][1],feet[1][2],g.player.facing},
      },
    },
    .clear=sky,
    .instances=undefined,
    .parts=g.parts.slices(),
    .bones=g.parts.bones.items,
    .lights=g.parts.lights.items,
    .ui=g.ui.v.items,
    .uiTime=@floatCast(@mod(g.uiTime,timeWrap)),
  };
  for(&out.instances,g.inst)|*o,l|o.*=l.items;
  return out;
}
/// plant instances near the camera, grouped by mesh: each plant's variant
/// comes from its tile, so it always regrows the same shape.
fn plants(g:*Game,reach:f32,tf:f32)Allocator.Error!void{
  for(&g.inst)|*l|l.clearRetainingCapacity();
  // the plants' columns, and which blooms radiate
  const s=g.plants.list.slice();
  const radiating=g.eco.radiance.radiating.items;
  for(0..g.plants.len())|i|{
    // where the plant's footprint centres, across the ground
    const ctr=g.plants.centre(i);
    if(@abs(ctr[0]-g.cam.target[0])>reach or @abs(ctr[1]-g.cam.target[2])>reach)continue;
    try plant(g,.{
      .sp=s.items(.sp)[i],.x=s.items(.x)[i],.y=s.items(.y)[i],.at=s.items(.at)[i],.ground=s.items(.chunk)[i].height[s.items(.tile)[i]],
      .growth=s.items(.growth)[i],.mana=s.items(.mana)[i],.seed=s.items(.seed)[i],
      .flow=s.items(.flow)[i],.health=s.items(.health)[i],
      .dir=s.items(.dir)[i],.turn=s.items(.turn)[i],
      .tug=g.tug.of(ck.PlantId.of(i),s.items(.at)[i]),
      // (worked out each tick: a plant sown since has none yet)
      .radiating=i<radiating.len and radiating[i],
    },tf);
  }
}
/// a thin film's hue as the shaders take it (common.glsl `filmHue`): one
/// turn of the rainbow per unit of `x`
fn filmHue(x:f32)m.V3{
  return.{
    0.5+0.5*@cos(m.tau*x),
    0.5+0.5*@cos(m.tau*(0.33+x)),
    0.5+0.5*@cos(m.tau*(0.67+x)),
  };
}
/// the most telling points of light first, the rest dropped: the renderer
/// takes `renderer.maxLights` (strong, far reaching lights near what the
/// camera looks at win)
fn rankLights(g:*Game)void{
  // the lights gathered this frame
  const ls=g.parts.lights.items;
  if(ls.len<=renderer.maxLights)return;
  // how a light is scored against what the camera looks at
  const Rank=struct{
    /// where the camera looks
    focus:m.V3,
    /// how telling light `l` is: strong, far reaching and near the focus scores high
    fn score(ctx:@This(),l:vertex.Light)f32{
      // how far the light is from the focus, and how strong it is
      const d=m.v3(l.pos[0],l.pos[1],l.pos[2])-ctx.focus;
      const strength=@max(l.col[0],@max(l.col[1],l.col[2]));
      return strength*l.pos[3]*l.pos[3]/(1+m.dot(d,d));
    }
    /// whether `a` is more telling than `b`, for the sort
    fn before(ctx:@This(),a:vertex.Light,b:vertex.Light)bool{return score(ctx,a)>score(ctx,b);}
  };
  pdq(vertex.Light,ls,Rank{.focus=g.cam.target},Rank.before);
  g.parts.lights.shrinkRetainingCapacity(renderer.maxLights);
}
/// where a floater hangs this frame: its hover height with a slow rise and
/// fall, and a lazy drift about its own point `c` (off the grid).
fn floatAt(def:*const species.Species,c:m.V3,ground:f32,seed:f32,tf:f32)m.V3{
  // how far it has risen with its two bobs
  const lift=bobAmount[0]*@sin(tf*bobRate[0]+seed*10)+bobAmount[1]*@sin(tf*bobRate[1]+seed*4);
  return m.v3(c[0]+drift*@sin(tf*driftRate[0]+seed*7),@max(ground,0)+def.hover+lift,c[2]+drift*@cos(tf*driftRate[1]+seed*5));
}
/// where the paws pluck plant `i`'s ripe yield this frame, the wolf at
/// `from`: its kind's pluck height over its foot (a floater's, over where
/// it hangs this moment), at the size it is drawn; a broad plant's from
/// the side of its footprint facing the wolf
pub fn pluckPoint(g:*const Game,i:usize,from:m.V3)m.V3{
  // the plants' columns, its kind, its seed, the ground under it, the time drawn
  const s=g.plants.list.slice();
  const def=species.get(s.items(.sp)[i]);
  const seed=s.items(.seed)[i];
  const ground=s.items(.chunk)[i].height[s.items(.tile)[i]];
  const tf:f32=@floatCast(@mod(g.time,timeWrap));
  // its foot, or where it hangs
  const c=s.items(.at)[i];
  const at=if(def.floating)floatAt(def,c,ground,seed,tf)else m.v3(c[0],ground,c[2]);
  // the way to the wolf across the ground, and how far out toward it the
  // paws find a broad one's yield
  const d=m.v3(from[0]-at[0],0,from[2]-at[2]);
  const out=@min(pluckOut*m.f(def.size-1),m.len(d));
  const toward=if(out>0)m.norm(d)*m.splat3(out)else m.v3(0,0,0);
  return at+toward+m.v3(0,def.pluck*pluck.size(seed),0);
}
/// the forming halo drawing in the bloom at a tile, as the shaders take it
/// (`vertex.noHalo` for none): they spiral it in (common.glsl `haloSpiral`).
fn haloOf(g:*const Game,def:*const species.Species,x:i32,y:i32)[4]f32{
  if(def.radiance<=0)return vertex.noHalo;
  // the halo structure holding the bloom at this tile, if any
  const hd=st.hold(&g.structs,x,y) orelse return vertex.noHalo;
  // the halo's seat over its centre, where the bloom is drawn to
  const to=structCentre(g,hd.s)+m.v3(0,hd.h.seat,0);
  return.{to[0],to[1],to[2],hd.h.k};
}
/// the threads of light between linked blooms (see ecology `Radiance`):
/// bent on the GPU from one bloom's core to the other's with a slight sag,
/// bright where their network radiates, faint where it is dark. A thread
/// reaches out from the more grown bloom as that bloom finishes assembling.
/// A forming halo draws its blooms in, and the GPU bends the threads from
/// them along (`Look.ends`).
fn threads(g:*Game,tf:f32)Allocator.Error!void{
  // the plants' columns
  const s=g.plants.list.slice();
  for(g.eco.radiance.links.items)|l|{
    // the two blooms, the more grown one first
    var ia=l.a.idx();
    var ib=l.b.idx();
    // links are worked out each tick; an uproot since then leaves a stale one
    if(ia>=g.plants.len() or ib>=g.plants.len())continue;
    if(species.get(s.items(.sp)[ia]).radiance<=0 or species.get(s.items(.sp)[ib]).radiance<=0)continue;
    if(s.items(.growth)[ib]>s.items(.growth)[ia])swap(usize,&ia,&ib);
    // the two cores, and the span from one to the other
    const pos=[2]m.V3{end(g,ia,tf),end(g,ib,tf)};
    const span=pos[1]-pos[0];
    // a beam runs true, bowing only a breath as the blooms drift
    const sag=m.v3(0,beamSag*@sin(tf*beamSagRate+m.f(ia)),0);
    // the beam's four control points
    const ctrl=[4]m.V3{pos[0],pos[0]+span*m.splat3(1.0/3.0)+sag,pos[0]+span*m.splat3(2.0/3.0)+sag,pos[1]};
    // which way is across the beam, level
    const side=m.norm(m.cross(span,m.v3(0,1,0)));
    // how far out the beam has reached, 0..1, as its bloom finishes
    const reach=m.smooth(m.clamp01((s.items(.growth)[ia]-beamFrom)/(1-beamFrom)));
    if(reach<=0)continue;
    // decision: one halo per beam; a beam between two halos' blooms (never
    // at once in practice) follows the first
    // the halos drawing in either bloom, if any
    const ha=haloOf(g,species.get(s.items(.sp)[ia]),s.items(.x)[ia],s.items(.y)[ia]);
    const hb=haloOf(g,species.get(s.items(.sp)[ib]),s.items(.x)[ib],s.items(.y)[ib]);
    // which ends a halo moves: 1 the first, 2 the second, 3 both
    const ends:f32=(if(ha[3]>=0)@as(f32,1)else 0)+(if(hb[3]>=0)@as(f32,2)else 0);
    try g.parts.emitCurve(.bloomThread,ctrl,side,1,reach,.{
      .glow=if(l.live)1 else beamDim,.phase=s.items(.seed)[ia],
      .halo=if(ha[3]>=0)ha else hb,.ends=ends,
    });
  }
}
/// a bloom's core this frame (over its tile; a forming halo moves it on the GPU)
fn end(g:*Game,i:usize,tf:f32)m.V3{
  // the plants' columns, and the bloom's kind
  const s=g.plants.list.slice();
  const def=species.get(s.items(.sp)[i]);
  return floatAt(def,s.items(.at)[i],s.items(.chunk)[i].height[s.items(.tile)[i]],s.items(.seed)[i],tf);
}
/// what drawing one plant needs to know about it.
const Drawn=struct{
  /// its kind
  sp:species.Id,
  /// its tile, across
  x:i32,
  /// its tile, along
  y:i32,
  /// where it stands across the ground (y 0): a floater's own point, a rooted one's footprint centre
  at:m.V3,
  /// the ground's height under it (metres)
  ground:f32,
  /// how far grown it is, 0..1
  growth:f32,
  /// the mana it holds, against its kind's cap
  mana:f32=0,
  /// its own seed, 0..1, for sway phase and shape
  seed:f32,
  /// how much mana moves through it, smoothed, for its motion and glow
  flow:f32=0,
  /// how healthy it is, 0..1
  health:f32=1,
  /// whether it is a placement preview
  ghost:bool=false,
  /// whether the preview fits where it is
  fits:bool=true,
  /// a celestial bloom: whether its network radiates (it shines in full)
  radiating:bool=false,
  /// the way it faces
  dir:m.Dir=0,
  /// how it is turning to that facing (R)
  turn:turn.Turn=.{},
  /// its bend after the paws plucking it (`pluck.Tug.of`)
  tug:[4]f32=@splat(0),
};
/// draws one plant (or its placement preview): culled to the view, posed
/// as it turns, floated over its shadow if it floats, its instance added to
/// its mesh's list, and a celestial bloom's light.
fn plant(g:*Game,d:Drawn,tf:f32)Allocator.Error!void{
  // its kind, its foot, and its bounding sphere's reach
  const def=species.get(d.sp);
  const foot=m.v3(d.at[0],d.ground,d.at[2]);
  const reach=plantBound+m.f(def.size);
  if(!g.parts.sees(foot+m.v3(0,reach*plantBoundUp,0),reach))return;
  // the level of detail its distance from the eye calls for
  const lod=meshgen.lodAt(m.len(foot-g.parts.eye));
  // where it stands, across and up
  var at=d.at;
  var y=d.ground;
  // the forming halo drawing it in, if any
  const halo=if(d.ghost)vertex.noHalo else haloOf(g,def,d.x,d.y);
  // turning, a rooted one heaves itself up on its roots; a floater only turns
  // how it is posed this moment of its turn
  const pose=turn.pose(d.turn,d.dir,g.time,!def.floating);
  if(!pose.still()and!def.floating){
    // its size (tiles)
    const size=m.f(def.size);
    y+=heave(size)*pose.lift;
    try roots(g,m.footprintCentre(d.x,d.y,def.size,d.ground),size,m.dirYaw(d.dir)+pose.spin,pose,d.seed,def.lineage.affinity()<-0.5);
  }
  if(def.floating){
    // floaters hang in the air: a slow rise and fall and a lazy drift,
    // never a bounce, over a soft shadow that shrinks as they rise (and
    // follows one a halo draws in, fading as it folds)
    // the ground under it (never below the water)
    const ground=@max(y,0);
    at=floatAt(def,d.at,d.ground,d.seed,tf);
    y=at[1];
    // its shadow's radius, shrinking as it rises
    const r=shadowR-shadowShrink*(at[1]-ground-def.hover);
    if(!d.ghost)try g.parts.emit(.shadow,m.chain(&.{m.translate(m.v3(at[0],ground+shadowLift,at[2])),m.scale3(m.v3(r,1,r))}),.{.fade=shadowFade,.halo=halo});
  }
  // a confluence grows through its keys, blending from one to the next;
  // other plants pick a shape by tile
  // the shape it grows into: its confluence key, or a variant by tile
  const key=meshgen.growthKey(d.sp,d.growth) orelse meshgen.Key{
    .v=@intCast(rng.hash2(0x7A11,d.x,d.y)%meshgen.variantCount),.f=0,
  };
  try g.inst[meshgen.plantSlot(d.sp,key.v,lod)].append(g.gpa,.{
    .pos=.{at[0],y,at[2]},
    .a=.{d.growth,d.mana/def.manaCap,d.seed,def.lineage.affinity()},
    .b=.{d.flow,d.health,def.sway,m.f(@intFromEnum(def.genome.form))},
    .c=.{key.f,if(d.ghost)1 else 0,if(d.fits)1 else 0,m.dirYaw(d.dir)+pose.spin},
    .h=halo,
    .tug=d.tug,
  });
  // a celestial bloom is the garden's light: its core sheds it round
  // about, pearl tinted by its film, pulsing slowly, brighter as it
  // assembles (a dark network's only faintly), following it as a forming
  // halo draws it in and dimming as it folds
  if(def.radiance>0 and !d.ghost){
    // how far it has assembled, where a forming halo draws its light, and its pulse
    const assembled=m.smooth(m.clamp01((d.growth-bloomLitFrom)/(1-bloomLitFrom)));
    const drawn=haloMod.spiral(m.v3(at[0],y+bloomCore,at[2]),halo);
    const pulse=1+bloomPulse*@sin(tf*bloomPulseRate+d.seed*m.tau);
    // how strong its light is now
    const strength=bloomLight*assembled*d.health*drawn.open*pulse*(if(d.radiating)@as(f32,1)else bloomDark);
    if(strength>0){
      // its light's tint, pearl blended toward its film's hue
      const tint=m.lerpV(m.v3(1,1,1),filmHue(d.seed*3+tf*0.03),bloomFilm);
      try g.parts.light(drawn.at,tint*m.splat3(strength),bloomReach);
    }
  }
}
/// a structure's centre on the ground (metres): its footprint's middle, or a floater's own point
fn structCentre(g:*const Game,s:*const st.Structure)m.V3{
  return s.at+m.v3(0,g.heightAt(s.x,s.y),0);
}
/// structures breathe and glow with their activity; each kind adds its own
/// extras through its `emit` hook.
fn structures(g:*Game,reach:f32,tf:f32)Allocator.Error!void{
  for(g.structs.list.items)|*s|{
    // its centre
    const ctr=structCentre(g,s);
    if(@abs(ctr[0]-g.cam.target[0])>reach or @abs(ctr[2]-g.cam.target[2])>reach){
      // what it sends far off is drawn wherever it is (each piece culled
      // to the view on its own)
      if(s.def().far)try st.emit(s,&g.parts,ctr,tf);
      continue;
    }
    // how active it is, 0..1
    const a=s.activity;
    // a fixed tempo: activity deepens the breath but never retimes it (a
    // tempo that followed activity jumped phase every time it changed)
    // its breath now: a scale a little over or under 1
    const breathe=if(s.def().still)1 else 1+(breathAmount+breathActive*a)*@sin(tf*breathRate+s.seed*9);
    // turning, all it draws is carried with its body: lifted on its roots,
    // rocking, turned the rest of the way
    // whether it stands on roots (not floating), and its pose this moment of its turn
    const rooted=!s.def().floating;
    const pose=turn.pose(s.turn,s.dir,g.time,rooted);
    if(!pose.still())g.parts.around=m.chain(&.{
      m.translate(ctr+m.v3(0,heave(m.f(s.def().size))*pose.lift,0)),
      m.rotY(pose.spin),m.rotX(pose.rock[0]),m.rotZ(pose.rock[1]),m.translate(-ctr),
    });
    defer g.parts.around=null;
    if(!s.def().bare)try g.parts.emit(s.def().mesh,m.mul(s.place(ctr),m.scale3(m.v3(breathe,2-breathe,breathe))),.{
      .glow=glow+glowActive*a,.flutter=flutterAmount,.phase=s.seed,.fade=s.def().sap,
      .sway=s.def().sway,.tall=s.def().tall,.grown=s.grown,
    });
    try st.emit(s,&g.parts,ctr,tf);
    g.parts.around=null;
    if(rooted and !pose.still())try roots(g,ctr,m.f(s.def().size),m.dirYaw(s.dir)+pose.spin,pose,s.seed,s.def().pale);
  }
}
/// how high a rooted thing `size` tiles across heaves itself as it turns
fn heave(size:f32)f32{return heaveAmount+heavePer*size;}
/// the roots a rooted thing turns on (R), round its foot at `ctr` (on the
/// ground), `size` tiles across, facing `yaw` this moment: at rest all in
/// the soil; pulled out, they arch from under its lifted body to tips
/// laid on the ground round it, which step as it turns round on them,
/// then dig back in where it now faces
fn roots(g:*Game,ctr:m.V3,size:f32,yaw:f32,p:turn.Pose,seed:f32,pale:bool)Allocator.Error!void{
  if(p.out<=0)return;
  // how many roots, and how high its foot is lifted
  const n=m.floorTo(u32,@max(rootsMin,rootsPer*size));
  const footY=heave(size)*p.lift;
  for(0..n)|i|{
    // a steady random for this root, its bearing, and the way out it points
    const h=rng.unit(rng.hash2(0x7007,@intCast(i),m.floorTo(i32,seed*1000)));
    const a=yaw+(m.f(i)+0.4*h)/m.f(n)*m.tau;
    const out=m.v3(@cos(a),0,@sin(a));
    // where it leaves the foot, how far it reaches, and where it lies sunk at rest
    const foot=ctr+out*m.splat3(rootFoot*size)+m.v3(0,footY+0.04,0);
    const reach=rootReach*size*(0.85+0.3*h);
    const sunk=ctr+out*m.splat3(reach)-m.v3(0,rootDeep*size,0);
    // a tip steps (lifts and comes down again) as the body turns on it,
    // neighbours out of step
    // how high its tip steps now
    const step=rootStep*size*p.lift*@max(@sin(p.k*rootSteps*m.tau+m.f(i)*2.4),0);
    // where its tip lies pulled out, and where it is now
    const laid=ctr+out*m.splat3(reach*1.1)+m.v3(0,0.03+step,0);
    const tip=m.lerpV(sunk,laid,p.out);
    // how high it arches, its four control points, and which way is across it
    const arch=m.v3(0,rootArch*size*p.out,0);
    const ctrl=[4]m.V3{foot,m.lerpV(foot,tip,0.33)+arch,m.lerpV(foot,tip,0.7)+arch*m.splat3(0.6),tip};
    const side=m.norm(m.cross(tip-foot,m.v3(0,1,0)));
    try g.parts.emitCurve(if(pale).turnRootPale else.turnRoot,ctrl,side,1,1,.{.flutter=rootFlutter,.phase=seed+m.f(i)*0.13});
  }
}
/// a tinted, pulsing preview of what is about to be sown or grown: the
/// plant as it will look grown (the same shape its tile will give it), or
/// the structure.
fn ghost(g:*Game,tf:f32)Allocator.Error!void{
  // the hovered tile, and the selected item
  const h=g.hover orelse return;
  if(g.mode!=.roam)return;
  const item=g.selected() orelse return;
  if(!play.known(g,item))return;
  // whether it fits there: free, in reach, and one in the belly
  const ok=actions.canPut(g,h) and g.player.inReach(h[0],h[1]) and g.player.inv.count(item)>0;
  if(item.plants())|sp|{
    // a fixed seed so the preview does not spin about as the cursor moves
    return plant(g,.{.sp=sp,.x=h[0],.y=h[1],.at=Plants.spot(sp,h,g.hoverAt),.ground=g.heightAt(h[0],h[1]),.growth=1,.seed=ghostSeed,.ghost=true,.fits=ok,.dir=g.placeDir},tf);
  }
  // the structure kind it grows, and its definition
  const k=st.kindOf(item) orelse return;
  const def=st.defs.get(k);
  // (a floating one where it will hang)
  const ctr=st.Structures.spot(k,h,g.hoverAt)+m.v3(0,g.heightAt(h[0],h[1])+ghostLift+def.hover,0);
  // its tint: fits or blocked
  const tint=if(ok)ghostFits else ghostBlocked;
  try g.parts.emit(def.preview orelse def.mesh,m.chain(&.{m.translate(ctr),m.rotY(m.dirYaw(g.placeDir)),m.scale3(m.splat3(ghostScale))}),.{.glow=ghostGlow+ghostPulse*@sin(tf*ghostPulseRate),.tint=tint,.ghost=true});
}
/// resource nodes within `nr` tiles of the camera focus.
fn nodes(g:*Game,nr:i32)Allocator.Error!void{
  // the camera focus's tile, and the chunks from one corner to the other
  const cx,const cz=m.tileAt(g.cam.target);
  const lo=ck.Coord.ofTile(cx-nr,cz-nr);
  const hi=ck.Coord.ofTile(cx+nr,cz+nr);
  // the chunk row being looked at
  var cy=lo.y;
  while(cy<=hi.y):(cy+=1){
    // the chunk column being looked at
    var cxx=lo.x;
    while(cxx<=hi.x):(cxx+=1){
      // the chunk, if it is streamed
      const c=g.world.get(.{.x=cxx,.y=cy}) orelse continue;
      for(0..ck.tileCount)|t|{
        if(c.res[t]==0)continue;
        // the node on this tile, if its kind is one
        const node=resources.of(c.kind[t]) orelse continue;
        // the tile's place, a steady random for it, and its size as it empties
        const wx,const wz=c.tileOf(t);
        const hsh=rng.unit(rng.hash2(0xD0D,wx,wz));
        const sc=nodeMin+(1-nodeMin)*m.f(c.res[t])/gen.resFull;
        try g.parts.emit(node.mesh,m.chain(&.{
          m.translate(m.tileCentre(wx,wz,c.height[t])),
          m.rotY(hsh*m.tau),m.scale3(m.splat3(sc)),
        }),.{.glow=node.glow,.phase=hsh,.sway=node.sway,.tall=node.tall*sc});
        // a glowing node (ley shards) lights the ground round it
        if(node.glow>0)try g.parts.light(m.tileCentre(wx,wz,c.height[t]+nodeLift),nodeCol*m.splat3(nodeLight*node.glow*sc),nodeReach);
      }
    }
  }
}
/// fallen starlight: each mote turns slowly and twinkles, hovering with a
/// slow breath over the ground; while it falls, fading echoes of it trail
/// above, a streak of light.
fn motes(g:*Game)Allocator.Error!void{
  for(g.stars.motes.items)|mo|{
    // how faded the mote is, 0..1
    const fade=m.clamp01(mo.life);
    try g.parts.emitMote(mo.pos,mo.phase,fade,if(mo.falling)0 else-1,moteSize*fade);
    // a mote is a spark of starlight: it lights what it falls past and the
    // ground it rests over
    try g.parts.light(mo.pos,moteCol*m.splat3(moteLight*fade),moteReach);
    if(!mo.falling)continue;
    for(1..echoes+1)|k|try g.parts.emitMote(mo.pos,mo.phase,fade,m.f(k),echoSize*fade/(1+m.f(k)));
  }
}
