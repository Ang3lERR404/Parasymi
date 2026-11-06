//! what gets drawn: turns the game state into a render Scene (plant
//! instances, rigid parts, HUD, sky/fog/light push constants). Read-only with
//! respect to the simulation.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type drawing may fail with
const Allocator=std.mem.Allocator;
/// trading two values' places
const swap=std.mem.swap;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, matrices, easing, tiles
const m=engine.core.math;
/// the engine's noise: the sine hash a heart's cones draw from
const noise=engine.core.noise;
/// colour types: what a plant yields, as its pods colour it
const color=engine.core.color;
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
/// the sign a powered structure wears: its crown and ley-blue
const lightCrown=lib.lightCrown;
/// resource nodes: their meshes and glows
const resources=lib.resources;
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
/// the push's `misc.y` flags (common.glsl `LEY_SIGHT`, `DEBUG_GRID`): ley
/// sight understood, and the debug grid drawn on the ground while F3 is on
const flagLeySight:f32=1;
/// (see `flagLeySight`)
const flagDebugGrid:f32=2;
/// no wolf: its paws' contact shadows far off any tile
const noFeet=[2]m.V3{m.splat3(noHover),m.splat3(noHover)};
/// fog thickens over this many chunks' eighths past the camera distance
const fogReach:f32=32*ck.sizeTiles/8;
/// fog starts to close in at this share of the drawn reach
const fogNear:f32=0.7;
/// how much of the haze the air sheds once the sky has shifted (the
/// unforming): the ley's light shines through clear air, so the garden
/// keeps its colours under it rather than drowning in violet
const shiftClear:f32=0.55;
/// a plant's bounding sphere: this much (tiles) plus its footprint
const plantBound:f32=1.2;
/// the share of the way up a plant its bounding sphere is centred
const plantBoundUp:f32=0.6;
/// how far out from a broad plant's centre (metres a tile past the first)
/// the paws find its yield, on the side facing the wolf
const pluckOut:f32=0.45;
/// the burst where a plucked yield comes loose: how long it lasts (s), how
/// far it flings (m), and how brightly its beads glow
const burstLife:f32=0.9;
/// (how far it flings, m)
const burstReach:f32=0.32;
/// (how brightly its beads glow at first)
const burstGlow:f32=1.6;
/// floaters: how far they bob (metres), a slow rise and a quicker one
const bobAmount=m.Vice(f32,2){0.07,0.025};
/// floaters: how fast each bob runs (radians a second)
const bobRate=m.Vice(f32,2){0.5,1.13};
/// floaters: how far they drift about their point (metres)
const drift:f32=0.05;
/// floaters: how fast they drift, across and along (radians a second)
const driftRate=m.Vice(f32,2){0.31,0.27};
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
const ghostFits=m.Vice(f32,4){0.6,1.4,0.8,0.7};
/// placement preview: the tint where it cannot go
const ghostBlocked=m.Vice(f32,4){1.6,0.4,0.4,0.8};
/// placement preview: how fast a structure ghost's glow pulses (radians a second)
const ghostPulseRate:f32=5;
/// a structure ghost's glow, pulsing about this
const ghostGlow:f32=0.6;
/// how far the ghost's glow pulses either way
const ghostPulse:f32=0.4;
/// resource nodes shrink to `nodeMin` of full size as they empty
const nodeMin:f32=0.55;
/// points of light. A celestial bloom: how far its light reaches (metres)
const bloomReach:f32=9;
/// how strong a bloom's light is
const bloomLight:f32=3.5;
/// a dark network's bloom's light, as a share of a radiating one's
const bloomDark:f32=0.2;
/// how high (metres) over its float a bloom's core sheds its light
const bloomCore:f32=0.35;
/// how far a plant's crown glow shimmers either way (a share), and its pace (radians a second)
const crownShimmer:f32=0.2;
/// (its pace)
const crownShimmerRate:f32=1.7;
/// how much of its pearl's film tints a bloom's own round light, 0..1
const bloomFilm:f32=0.25;
/// how strong its round light is, a share of its light: low, so its cones
/// of colour (`heartCones`) carry the light, not a haze round it
const bloomRound:f32=0.3;
/// how far a bloom's light pulses either way (a share)
const bloomPulse:f32=0.15;
/// how fast it pulses (radians a second)
const bloomPulseRate:f32=1.1;
/// a relay standing on the ground (an astrocyme, a heliocyra) sheds this
/// share of a floating bloom's light, from its heart (low in the mist, a
/// whole bloom's would drown the ground round it in light)
const groundedLight:f32=0.2;
/// an empty astrocyme sheds this share of what it does full
const groundedEmpty:f32=0.3;
/// by full day a relay's light, and a strip's, sheds this share of what it
/// does by night: in the day's mist a night's light would wash the garden
/// white round it
const lightByDay:f32=0.3;
/// a bloom sheds light only once it has assembled this far
const bloomLitFrom:f32=0.6;
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
/// threads, the wolf, nodes, structures, ghost and starlit patches as parts, the best
/// lights, the HUD, and the push constants for sky, fog, sun and view.
pub fn scene(g:*Game,screen:m.Vice(f32,2))Allocator.Error!renderer.Scene{
  // at the main menu the wolf sleeps on its stage instead
  if(g.atTitle())return lib.title.scene(g,screen);
  // how far round the camera target things are drawn (tiles), and the shader clock
  const reach=g.cam.reach(play.drawLimitOf(g.opts.rings()));
  const tf:f32=@floatCast(@mod(g.time,timeWrap));
  // parts first: plants add parts of their own (shadows under floaters).
  // Everything is culled to what the camera sees and drawn at the level of
  // detail its distance from the eye calls for.
  g.parts.clear();
  g.parts.look(g.cam.viewEye(),m.Frustum.of(g.cam.viewProj()),g.sky.lightDir());
  try plants(g,reach,tf);
  try burst(g);
  try threads(g,tf);
  try shafts(g,tf);
  // a specimen stands alone: no wolf, ghosts or starlit patches, and a plant no
  // nodes or structures (their meshes were never built)
  const alone=g.specimen!=null;
  // where the wolf's paws are, for their contact shadows (none when alone)
  // (but for one the wolf plucks)
  // (in the hyena's act the gardener hovers: no paws touch down)
  const feet=if(alone and !g.specimen.?.wolf())noFeet else switch(g.act){
    .wolf=>try g.player.rig(&g.parts,g.headless()),
    .hyena=>blk:{
      try lib.act.draw(&g.player,&g.parts,@floatCast(g.time),g.headless());
      break:blk noFeet;
    },
  };
  if(!alone or g.specimen.?.what==.structure){
    try nodes(g,@intFromFloat(reach));
    try structures(g,reach,tf);
  }
  try wild(g,reach);
  if(alone)try g.specimen.?.drawSamples(g);
  try lib.unforming.draw(g,tf);
  if(!alone)try lib.tendril.draw(g,&g.parts);
  if(!alone){
    try ghost(g,tf);
    try g.starlight.draw(g,reach,tf);
  }
  try hud.build(g,screen);
  // the veil of what is not yet understood, and the sky's colour under it
  const veil=g.prog.veil;
  const sky=g.sky.color(veil);
  // the eye, the hovered tile (far off when none), and the sun's heading
  const eye=g.cam.viewEye();
  const hv:m.Vice(f32,2)=if(g.hover)|h|.{m.f(h[0]),m.f(h[1])}else.{noHover,noHover};
  const ld=g.sky.lightDir();
  // the scene, its instance lists filled from the plants just gathered
  var out:renderer.Scene=.{
    .push=.{
      .vp=g.cam.viewProj(),
      .eyeTime=.{eye[0],eye[1],eye[2],tf},
      .fog=.{sky[0],sky[1],sky[2],(1-shiftClear*g.sky.shift)/(fogReach+g.cam.dist)},
      .misc=.{veil,(if(g.prog.done.contains(.leySight))flagLeySight else 0)+(if(g.debug)flagDebugGrid else 0),hv[0],hv[1]},
      .sun=.{ld[0],ld[1],ld[2],g.sky.daylight()},
      .view=.{g.cam.target[0],g.cam.target[2],reach*fogNear,reach},
      .feet=.{
        .{feet[0][0],feet[0][1],feet[0][2],g.player.facing},
        .{feet[1][0],feet[1][1],feet[1][2],g.sky.shift},
      },
    },
    .clear=sky,
    .instances=undefined,
    .parts=g.parts.slices(),
    .bones=g.parts.bones.items,
    .lights=g.parts.lights.items,
    .moisture=g.parts.moisture.items,
    .step=g.moved,
    .probe=if(g.hover)|h|.{m.f(h[0])+0.5,m.f(h[1])+0.5}else null,
    .readField=g.weather.want,
    .ui=g.ui.v.items,
    .uiTime=@floatCast(@mod(g.uiTime,timeWrap)),
  };
  handPlants(g,&out);
  return out;
}
/// this frame's plant lists emptied, drawn and caught
pub fn clearPlants(g:*Game)void{
  for(&g.inst)|*l|l.clearRetainingCapacity();
  for(&g.caught)|*l|l.clearRetainingCapacity();
  for(&g.caughtIn)|*l|l.clearRetainingCapacity();
}
/// `out`'s plant instances, drawn and caught for the rays, this frame's lists
pub fn handPlants(g:*const Game,out:*renderer.Scene)void{
  for(&out.instances,g.inst)|*o,l|o.*=l.items;
  for(&out.caught,g.caught)|*o,l|o.*=l.items;
  for(&out.caughtIn,g.caughtIn)|*o,l|o.*=l.items;
}
/// whether plant `i`'s footprint centres within `reach` of the camera's
/// target, across the ground: near enough to be drawn
fn nearOf(g:*const Game,i:usize,reach:f32)bool{
  // where its footprint centres
  const ctr=g.plants.centre(i);
  return @abs(ctr[0]-g.cam.target[0])<=reach and @abs(ctr[1]-g.cam.target[2])<=reach;
}
/// the name the plant on tile (`x`, `y`) is caught under for the rays: its
/// patch's (`renderer.patchTiles` across)
fn patchOf(x:i32,y:i32)u64{return renderer.patchCatch(@divFloor(x,renderer.patchTiles),@divFloor(y,renderer.patchTiles));}
/// whether a plant of kind `def` standing at `at` on ground `ground` is
/// seen: its bounding sphere in view (a floater's centred where it hangs:
/// one hung high, the solcyriphon, would be culled seen level with it)
fn seenAt(g:*const Game,def:*const species.Species,at:m.V3,ground:f32)bool{
  // its foot, and its bounding sphere's reach
  const foot=m.v3(at[0],ground,at[2]);
  const reach=plantBound+m.f(def.size);
  return g.parts.sees(foot+m.v3(0,if(def.floating)def.hover else reach*plantBoundUp,0),reach);
}
/// plant instances near the camera, grouped by mesh: each plant's variant
/// comes from its tile, so it always regrows the same shape; and every
/// plant of each patch in view caught for the rays.
/// where a plant of species `sp` on tile `t` of chunk `c` is drawn from:
/// the ground's height, or the water's over it for one that floats on it
fn groundOf(sp:species.Id,c:*const ck.Chunk,t:u16)f32{
  return c.height[t]+if(species.get(sp).onWater)c.pool[t]else 0;
}
fn plants(g:*Game,reach:f32,tf:f32)Allocator.Error!void{
  clearPlants(g);
  // the plants' columns, and the light each relay carries
  const s=g.plants.list.slice();
  const carried=g.eco.light.carried.items;
  // the patches with a plant seen in them: every plant of each is caught
  // for the rays, seen or not, so a patch's level holds the same meshes
  // from frame to frame and is only refitted as the camera turns
  g.seenPatches.clearRetainingCapacity();
  for(0..g.plants.len())|i|{
    // its kind
    const sp=s.items(.sp)[i];
    if(!nearOf(g,i,reach)or!seenAt(g,species.get(sp),s.items(.at)[i],groundOf(sp,s.items(.chunk)[i],s.items(.tile)[i])))continue;
    try g.seenPatches.put(g.gpa,patchOf(s.items(.x)[i],s.items(.y)[i]),{});
  }
  for(0..g.plants.len())|i|{
    // whether it is near enough to draw, and the patch it is caught under
    // for the rays if any plant of it is seen
    const near=nearOf(g,i,reach);
    const patch=patchOf(s.items(.x)[i],s.items(.y)[i]);
    const caught:?u64=if(g.seenPatches.contains(patch))patch else null;
    if(!near and caught==null)continue;
    // what its form shows of its own state, and the way a guard leans
    const own=ownOf(g,i);
    try plant(g,.{
      .near=near,.caught=caught,
      .own=own.k,.face=own.face,
      .sp=s.items(.sp)[i],.x=s.items(.x)[i],.y=s.items(.y)[i],.at=s.items(.at)[i],.ground=groundOf(s.items(.sp)[i],s.items(.chunk)[i],s.items(.tile)[i]),
      .growth=s.items(.growth)[i],.mana=s.items(.mana)[i],.seed=s.items(.seed)[i],
      .flow=s.items(.flow)[i],.health=s.items(.health)[i],
      .dir=s.items(.dir)[i],.turn=s.items(.turn)[i],
      .tug=g.tug.of(ck.PlantId.of(i),s.items(.at)[i]),
      .essence=s.items(.essence)[i],
      .since=g.tug.sinceOf(ck.PlantId.of(i),s.items(.at)[i]),
      // (worked out each tick: a plant sown since has none yet)
      .radiating=i<carried.len and carried[i]>0,
    },tf);
  }
}
/// what a light grid plant's form shows of its own state (plant.vert, the
/// instance's `yield[3]`), and the way it is drawn facing if not its own
const Own=struct{
  /// an astrocyme's fill 0..1, a heliocyra's strip's light 0..1 (of what
  /// it takes from a field, more for a beam's), a halcyra's reach to the
  /// plant it leans toward and how far it leans, packed (`leanPacked`)
  k:f32=0,
  /// a halcyra beside a plant: the yaw that turns it toward it
  face:?f32=null,
};
/// what plant `i`'s form shows of its own state, from the light grid
fn ownOf(g:*const Game,i:usize)Own{
  // the plants' columns, its kind and the grid
  const s=g.plants.list.slice();
  const def=species.get(s.items(.sp)[i]);
  const l=&g.eco.light;
  if(def.store>0)return.{.k=m.clamp01(s.items(.stored)[i]/def.store)};
  if(def.strip>0){
    for(l.strips.items)|st0|if(st0.from.idx()==i)return.{.k=st0.glow/lib.light.stripTake};
    return.{};
  }
  if(def.guards>0){
    // how far it leans, and the way to where the plant it leans toward last stood
    const lean=s.items(.lean)[i];
    if(lean<=leanGone)return.{};
    const d=s.items(.leanTo)[i]-s.items(.at)[i];
    return.{.k=leanPacked(m.len(m.v3(d[0],0,d[2])),lean),.face=m.atan2(-d[2],d[0])};
  }
  return.{};
}
/// a halcyra leaning less than this is drawn wholly alone, its net spread
const leanGone:f32=0.002;
/// a halcyra's reach (m) and lean (0..1) packed in one float for the GPU
/// (plant.vert `GUARD_STEPS`, must match): the reach in whole steps of
/// 1/`leanSteps` m, the lean in the fraction
pub fn leanPacked(reach:f32,lean:f32)f32{return@floor(reach*leanSteps)+m.clamp(lean,0,0.99);}
/// how finely a halcyra's reach is packed (steps a metre)
const leanSteps:f32=64;
/// the burst where a plucked plant's yield came loose, while it lasts:
/// motes and drops of what it yields flung out round the paws, glowing
/// and shrinking away
fn burst(g:*Game)Allocator.Error!void{
  // the plucked plant, if any, and how far through its life the burst is
  const id=g.tug.id orelse return;
  if(g.tug.since>=burstLife or id.idx()>=g.plants.len())return;
  const age=g.tug.since/burstLife;
  // what the plant yields, its colour
  const def=species.get(g.plants.list.items(.sp)[id.idx()]);
  const col=color.Rgba8.of(def.yields.info().col).toF4();
  try g.parts.emitBurst(.pluckBurst,g.tug.burst,burstReach,age,.{.glow=burstGlow*(1-age),.tint=.{col[0],col[1],col[2],1}});
}
/// a thin film's hue as the shaders take it (common.glsl `filmHue`): one
/// turn of the rainbow per unit of `x`
pub fn filmHue(x:f32)m.V3{
  return.{
    0.5+0.5*@cos(m.tau*x),
    0.5+0.5*@cos(m.tau*(0.33+x)),
    0.5+0.5*@cos(m.tau*(0.67+x)),
  };
}
/// a saturated hue of the rainbow (one turn per unit of `x`): the film's
/// hue sharpened, its brightest channel at one
pub fn rainbow(x:f32)m.V3{
  // the film's soft hue, cubed so its weakest channels fall away
  const h=filmHue(x);
  const s=h*h*h;
  return s/m.splat3(@max(s[0],@max(s[1],s[2])));
}
/// the cones of light a radiant heart throws at `at`, `strength` its
/// light: between `coneFew` and `coneMost` wide soft cones (how many
/// drifting slowly over time, `howMany`, each one past the first few
/// fading in and out rather than popping), each its own colour, wandering
/// on its own (its own way round and down, swinging at its own two paces),
/// breathing in brightness at its own pace; together they overlap, part
/// and drift, filling the fog round it with colour and splashing it on
/// the ground and plants they sweep over (light.glsl `coneOf`)
fn heartCones(g:*Game,at:m.V3,strength:f32,seed:f32,tf:f32)Allocator.Error!void{
  // how many cones it throws just now, a share past a whole one fading
  const n=howMany(seed,tf);
  for(0..coneMost)|k|{
    // how far this cone has faded in: whole for the first `n`, the next part way
    const here=m.clamp01(n-m.f(k));
    if(here<=0)continue;
    // this cone's own random draws, from the plant's seed and its place
    const h=[_]f32{hashOf(seed,k,1),hashOf(seed,k,2),hashOf(seed,k,3),hashOf(seed,k,4),hashOf(seed,k,5),hashOf(seed,k,6)};
    // its way round: spread from its neighbours, swinging at two paces of its own
    const yaw=m.ratio(k,coneMost)*m.tau+h[0]*coneSpread+coneSwing*@sin(tf*m.lerp(coneSlow[0],coneSlow[1],h[1])+h[2]*m.tau)+coneSwing*0.55*@sin(tf*m.lerp(coneFast[0],coneFast[1],h[3])+h[4]*m.tau);
    // how far below level it leans, rising and dipping on its own
    const dip=m.lerp(coneDip[0],coneDip[1],0.5+0.5*@sin(tf*m.lerp(coneSlow[0],coneSlow[1],h[5])*1.3+h[1]*m.tau));
    const way=m.v3(@cos(dip)*@sin(yaw),-@sin(dip),@cos(dip)*@cos(yaw));
    // its colour, drifting slowly through the rainbow, and its breath
    const col=m.lerpV(rainbow(m.ratio(k,coneMost)+h[2]*0.15+tf*coneHueRate*(0.6+h[3])),m.v3(1,1,1),conePearl);
    const breath=1+coneBreath*@sin(tf*m.lerp(coneBreathRate[0],coneBreathRate[1],h[4])+h[5]*m.tau);
    try g.parts.spot(at,way,@cos(coneHalf),col*m.splat3(strength*coneLight*breath*m.smooth(here)),coneReach);
  }
}
/// a radiant heart's cones: the fewest it ever throws, and the most (the
/// gardener's 6 to 9)
const coneFew:f32=6;
/// (the most)
const coneMost=9;
/// how fast the count drifts between them (radians a second): over a
/// couple of minutes, each heart at its own place in the drift
const coneCountRate:f32=0.05;
/// how many cones a heart of `seed` throws at time `tf`: between `coneFew`
/// and `coneMost`, drifting slowly, the share past a whole one the next
/// cone's fade
fn howMany(seed:f32,tf:f32)f32{
  return m.lerp(coneFew,m.f(coneMost),0.5+0.5*@sin(tf*coneCountRate+seed*m.tau));
}
test"a heart throws between six and nine cones, drifting"{
  // the fewest and most seen over a long while
  var lo:f32=99;
  var hi:f32=0;
  for(0..2000)|i|{
    const n=howMany(0.37,m.f(i)*0.5);
    lo=@min(lo,n);
    hi=@max(hi,n);
  }
  try lib.std.testing.expect(lo>=coneFew-1e-4 and lo<coneFew+0.05 and hi<=m.f(coneMost)+1e-4 and hi>m.f(coneMost)-0.05);
}
/// how far a cone's resting way round strays from an even spread (radians)
const coneSpread:f32=0.8;
/// how far a cone swings round from its resting way (radians)
const coneSwing:f32=0.9;
/// a cone's slow and fast swings: the range each one's pace is drawn from (radians a second)
const coneSlow=m.Vice(f32,2){0.09,0.18};
/// (its faster swing)
const coneFast=m.Vice(f32,2){0.21,0.37};
/// how far below level a cone leans: between these (radians)
const coneDip=m.Vice(f32,2){0.35,1.05};
/// a cone's half-width (radians): wide, to fill the air
const coneHalf:f32=0.42;
/// how far a cone reaches (metres)
const coneReach:f32=10;
/// a cone's brightness, a share of its heart's light
const coneLight:f32=1.2;
/// how much of a pearl's white softens a cone's colour (never white itself)
const conePearl:f32=0.06;
/// how fast a cone's colour drifts through the rainbow (turns a second)
const coneHueRate:f32=0.02;
/// how far a cone breathes either way (a share), and the range of its pace (radians a second)
const coneBreath:f32=0.25;
/// (the range its breath's pace is drawn from)
const coneBreathRate=m.Vice(f32,2){0.4,0.9};
/// a draw 0..1 for cone `k` of a plant of `seed`, the `which`th
fn hashOf(seed:f32,k:usize,which:u32)f32{
  return noise.sineHash(3,.{seed,m.f(k),m.f(which)},coneHashWeights);
}
/// the weights a cone's draws are hashed with (the seed, the cone, which draw)
const coneHashWeights=m.Vice(f32,3){127.1,311.7,74.7};
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
fn haloOf(g:*const Game,def:*const species.Species,x:i32,y:i32)m.Vice(f32,4){
  if(!def.halo)return vertex.noHalo;
  // the halo structure holding the bloom at this tile, if any
  const hd=st.hold(&g.structs,x,y) orelse return vertex.noHalo;
  // the halo's seat over its centre, where the bloom is drawn to
  const to=structCentre(g,hd.s)+m.v3(0,hd.h.seat,0);
  return.{to[0],to[1],to[2],hd.h.k};
}
/// the threads of light between linked relays (sim/light.zig): bent on
/// the GPU from one relay's core to the other's with a slight sag, bright
/// where light passed between them, faint where none did. A forming halo
/// draws its blooms in, and the GPU bends the threads from them along
/// (`Look.ends`). A structure's relay (a diamond) holds its end still at
/// its heart.
fn threads(g:*Game,tf:f32)Allocator.Error!void{
  // the plants' columns
  const s=g.plants.list.slice();
  for(g.eco.light.links.items)|l|{
    // the two ends' points, and a plant end's slot (the first a plant, if either is)
    const pa=nodeEnd(g,l.a,tf) orelse continue;
    const pb=nodeEnd(g,l.b,tf) orelse continue;
    var ia:usize=if(l.a==.plant)l.a.plant.idx()else if(l.b==.plant)l.b.plant.idx()else continue;
    var ib:usize=if(l.b==.plant)l.b.plant.idx()else ia;
    if(l.a!=.plant)swap(usize,&ia,&ib);
    // the two cores, and the span from one to the other
    const pos=[2]m.V3{pa,pb};
    const span=pos[1]-pos[0];
    // a beam runs true, bowing only a breath as the blooms drift
    const sag=m.v3(0,beamSag*@sin(tf*beamSagRate+m.f(ia)),0);
    // the beam's four control points
    const ctrl=m.straightCubic(pos[0],pos[1],sag);
    // which way is across the beam, level
    const side=m.norm(m.cross(span,m.v3(0,1,0)));
    // how far out the beam has reached, 0..1, as its relay finishes
    const reach=m.smooth(m.unlerp(beamFrom,1,s.items(.growth)[if(l.a==.plant)l.a.plant.idx()else l.b.plant.idx()]));
    if(reach<=0)continue;
    // decision: one halo per beam; a beam between two halos' blooms (never
    // at once in practice) follows the first
    // the halos drawing in either bloom, if any
    const ha=haloOf(g,species.get(s.items(.sp)[ia]),s.items(.x)[ia],s.items(.y)[ia]);
    const hb=haloOf(g,species.get(s.items(.sp)[ib]),s.items(.x)[ib],s.items(.y)[ib]);
    // which ends a halo moves: 1 the first, 2 the second, 3 both
    const ends:f32=(if(ha[3]>=0)@as(f32,1)else 0)+(if(hb[3]>=0)@as(f32,2)else 0);
    try g.parts.emitCurve(.bloomThread,ctrl,side,1,reach,.{
      .glow=if(l.glow>0)1 else beamDim,.phase=s.items(.seed)[ia],
      .halo=if(ha[3]>=0)ha else hb,.ends=ends,
    });
  }
}
/// a night beam: how wide it is either side of its middle where it lands
/// (m), how bright at full night, and the light it throws where it lands
/// (strength, reach) and halfway down it (strength, reach)
const beamHalf:f32=0.17;
/// (how bright at full night)
const beamGlow:f32=1.0;
/// (the light where it lands: its strength)
const beamLand:f32=2.2;
/// (and its reach, m)
const beamLandReach:f32=4.5;
/// (the light halfway down it: its strength)
const beamMid:f32=1.2;
/// (and its reach, m)
const beamMidReach:f32=3.5;
/// how far the beam's light breathes either way (a share), and its pace
/// (radians a second): a light is never still (the glow bar)
const beamShimmer:f32=0.15;
/// (its pace)
const beamShimmerRate:f32=2.3;
/// the beam's gold, the light it throws (linear)
const beamCol=m.V3{1.0,0.78,0.45};
/// how far below a solcyriphon's heart its beam leaves (m: under its lens)
const beamFromBelow:f32=0.08;
/// a strip: how high it lies over the ground (m), how bright for each glow
/// it carries (a dark one a faint trace), the most it shines, and its light
/// along it (strength for each unit of brightness, reach, one every so many tiles)
const stripLift:f32=0.07;
/// (how bright for each glow it carries, of what it takes from a field)
const stripGlow:f32=1.0;
/// (a dark strip's faint trace)
const stripDark:f32=0.08;
/// (the most it shines, fed a whole beam)
const stripMost:f32=2.2;
/// (its light: strength for each unit of brightness)
const stripLight:f32=0.8;
/// (its light's reach, m)
const stripReach:f32=2.4;
/// (one light every so many tiles along it)
const stripEvery=3;
/// how far out from its tile's middle a heliocyra's crystal hangs (m) and
/// how high (a share over its kind's stemH): where its strip leaves
const stripFromOut:f32=0.12;
/// the light grid's shafts of light, lighting the air round them (part
/// `.shaft`): every solcyriphon's night beam, falling straight down from
/// under its lens onto the relay that takes it or the ground under it,
/// as strong as the night is deep, a light where it lands; every
/// heliocyra's strip, leaving its crystal and laid a tile wide over the
/// ground the way it faces, tile by tile over the ground's rise and fall,
/// as bright as the light it carries
fn shafts(g:*Game,tf:f32)Allocator.Error!void{
  // the plants' columns, and the grid
  const s=g.plants.list.slice();
  const l=&g.eco.light;
  for(l.beams.items)|bm|{
    // the solcyriphon, where its beam leaves and where it ends
    const i=bm.from.idx();
    if(i>=g.plants.len() or bm.k<=0)continue;
    const top=end(g,i,tf)-m.v3(0,beamFromBelow,0);
    const ground=g.heightAt(bm.x,bm.y);
    const to=if(bm.into)|r|(nodeEnd(g,r,tf) orelse m.v3(top[0],ground,top[2]))else m.v3(top[0],ground,top[2]);
    // the four control points, straight down
    const ctrl=m.straightCubic(top,to,m.splat3(0));
    try g.parts.emitCurve(.lightBeam,ctrl,m.v3(1,0,0),1,1,.{.glow=beamGlow*bm.k,.flutter=beamHalf,.phase=s.items(.seed)[i],.fade=0});
    // its light breathes as the beam flutters, where it lands a beat apart
    // from halfway down
    const seed=s.items(.seed)[i];
    try g.parts.light(to+m.v3(0,0.3,0),beamCol*m.splat3(beamLand*bm.k*m.shimmer(tf,seed,beamShimmer,beamShimmerRate)),beamLandReach);
    try g.parts.light(m.lerpV(top,to,0.5),beamCol*m.splat3(beamMid*bm.k*m.shimmer(tf,seed+0.5,beamShimmer,beamShimmerRate)),beamMidReach);
  }
  for(l.strips.items)|sp|{
    // the heliocyra, its kind, the way it faces and the step along it
    const i=sp.from.idx();
    if(i>=g.plants.len() or sp.len==0)continue;
    const def=species.get(s.items(.sp)[i]);
    const step=m.dirVec(s.items(.dir)[i]);
    const way=m.v3(m.f(step.x),0,m.f(step.z));
    const side=m.v3(-way[2],0,way[0]);
    // its tile, its middle, how brightly it shines, and its seed
    const x=s.items(.x)[i];
    const y=s.items(.y)[i];
    const mid=m.tileCentre(x,y,g.heightAt(x,y));
    const bright=if(sp.glow>0)@min(stripMost,stripGlow*sp.glow/lib.light.stripTake)else stripDark;
    const seed=s.items(.seed)[i];
    // the ground's height `t` tiles along it (its own tile 0)
    const H=struct{
      /// the ground's height at tile `t` along from `xx`,`yy` stepping `dv`
      fn at(gg:*const Game,xx:i32,yy:i32,dv:m.DirVec,t:i32)f32{return gg.heightAt(xx+dv.x*t,yy+dv.z*t);}
    };
    // the length it runs (m, from half a tile out)
    const len=m.f(sp.len);
    // it leaves its crystal and comes down to the ground at its own tile's edge
    const from=mid+way*m.splat3(stripFromOut)+m.v3(0,def.genome.stemH,0);
    const land=mid+way*m.splat3(0.5)+m.v3(0,(H.at(g,x,y,step,0)+H.at(g,x,y,step,1))*0.5-mid[1]+stripLift,0);
    try g.parts.emitCurve(.lightBeam,.{from,m.lerpV(from,land,0.33)+way*m.splat3(0.1),m.lerpV(from,land,0.75)-m.v3(0,0.05,0),land},side,1,1,.{.glow=bright*0.8,.flutter=0.05,.phase=seed});
    for(0..sp.len)|j|{
      // this tile along it, its edges' and middle's heights
      const t:i32=@intCast(j+1);
      const h=H.at(g,x,y,step,t);
      const e0=(H.at(g,x,y,step,t-1)+h)*0.5;
      const e1=(H.at(g,x,y,step,t+1)+h)*0.5;
      // how far along its start lies, and the four control points over it
      const a=0.5+m.f(j);
      const Along=struct{
        /// the point `d` tiles along from `c` the way `w` heads, `hh` high
        fn p(c:m.V3,w:m.V3,d:f32,hh:f32)m.V3{return m.v3(c[0]+w[0]*d,hh+stripLift,c[2]+w[2]*d);}
      };
      const ctrl=[4]m.V3{Along.p(mid,way,a,e0),Along.p(mid,way,a+1.0/3.0,h),Along.p(mid,way,a+2.0/3.0,h),Along.p(mid,way,a+1,e1)};
      try g.parts.emitCurve(.lightStrip,ctrl,side,1,1,.{.glow=bright,.flutter=len,.phase=seed,.fade=a});
      if(j%stripEvery==1)try g.parts.light(ctrl[1]+m.v3(0,0.25,0),beamCol*m.splat3(stripLight*bright*m.lerp(1,lightByDay,g.sky.daylight())),stripReach);
    }
  }
}
/// a node's core this frame: a relay plant's over its tile (a forming halo
/// moves it on the GPU), a structure's relay where it hangs; null for a
/// link worked out before the plant or structure it names was taken away
fn nodeEnd(g:*Game,r:lib.light.Ref,tf:f32)?m.V3{
  switch(r){
    .plant=>|id|{
      if(id.idx()>=g.plants.len())return null;
      return end(g,id.idx(),tf);
    },
    .relay=>|k|{
      if(k>=g.relays.items.len)return null;
      // the relay, and the ground under it
      const rl=g.relays.items[k];
      return rl.at+m.v3(0,g.heightAt(rl.x,rl.y)+lib.haloStructure.hover,0);
    },
  }
}
/// a relay plant's core this frame (over its tile; a forming halo moves it on the GPU)
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
  /// a relay of the light grid: whether light reaches it (it shines in full)
  radiating:bool=false,
  /// the way it faces
  dir:m.Dir=0,
  /// how it is turning to that facing (R)
  turn:turn.Turn=.{},
  /// its bend after the paws plucking it (`pluck.Tug.of`)
  tug:m.Vice(f32,4)=@splat(0),
  /// the yield it has ripened (units)
  essence:f32=0,
  /// seconds since its yield last came loose in the paws (`pluck.Tug.sinceOf`)
  since:f32=vertex.noPluck,
  /// what its form shows of its own state (`Own.k`)
  own:f32=0,
  /// the yaw it is drawn facing instead of its own (`Own.face`)
  face:?f32=null,
  /// whether it is near enough the camera to be drawn (if seen)
  near:bool=true,
  /// the name it is caught under for the rays (`catchOf`; null: not caught)
  caught:?u64=null,
};
/// a plant of kind `sp` drawn standing at `at` (its ground `at`'s height)
/// with no plant in the garden behind it, `growth` grown, `seed` its own:
/// the main menu's patch round the sleeping wolf
pub fn stagePlant(g:*Game,sp:species.Id,at:m.V3,growth:f32,seed:f32,tf:f32)Allocator.Error!void{
  try plant(g,.{.sp=sp,.x=@intFromFloat(@floor(at[0])),.y=@intFromFloat(@floor(at[2])),.at=m.v3(at[0],0,at[2]),.ground=at[1],.growth=growth,.seed=seed,.health=1,.caught=renderer.looseCatch},tf);
}
/// draws one plant (or its placement preview): culled to the view, posed
/// as it turns, floated over its shadow if it floats, its instance added to
/// its mesh's list, and a celestial bloom's light.
fn plant(g:*Game,d:Drawn,tf:f32)Allocator.Error!void{
  // its kind, and its foot
  const def=species.get(d.sp);
  const foot=m.v3(d.at[0],d.ground,d.at[2]);
  // whether it is drawn: near enough, and seen; else it is only caught for the rays
  const seen=d.near and seenAt(g,def,d.at,d.ground);
  if(!seen and d.caught==null)return;
  // the level of detail its distance from the eye calls for
  const lod=meshgen.lodAt(m.dist(foot,g.parts.eye));
  // where it stands, across and up
  var at=d.at;
  var y=d.ground;
  // the forming halo drawing it in, if any
  const halo=if(d.ghost)vertex.noHalo else haloOf(g,def,d.x,d.y);
  // turning, a rooted one heaves itself up on its roots; a floater only turns
  // how it is posed this moment of its turn
  const pose=turn.pose(d.turn,d.dir,g.time,!def.floating);
  if(!pose.still()and!def.floating and seen){
    // its size (tiles)
    const size=m.f(def.size);
    y+=heave(size)*pose.lift;
    try roots(g,m.footprintCentre(d.x,d.y,def.size,d.ground),size,m.dirYaw(d.dir)+pose.spin,pose,d.seed,def.drawnAs()==.parasitic);
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
    if(!d.ghost and seen)try g.parts.emit(.shadow,m.chain(&.{m.translate(m.v3(at[0],ground+shadowLift,at[2])),m.scale3(m.v3(r,1,r))}),.{.fade=shadowFade,.halo=halo});
  }
  // a confluence grows through its keys, blending from one to the next;
  // other plants pick a shape by tile
  // the shape it grows into: its confluence key, or a variant by tile
  const key=meshgen.growthKey(d.sp,d.growth) orelse meshgen.Key{
    .v=@intCast(rng.hash2(0x7A11,d.x,d.y)%meshgen.variantCount),.f=0,
  };
  // the colour of what it yields, its form's own state beside it
  var yield=color.Rgba8.of(def.yields.info().col).toF4();
  yield[3]=d.own;
  // its instance: drawn if seen, caught for the rays under its chunk's name
  const inst=vertex.PlantInstance{
    .pos=.{at[0],y,at[2]},
    .a=.{d.growth,d.mana/def.manaCap,d.seed,def.affinity()},
    .b=.{d.flow,d.health,def.sway,m.f(@intFromEnum(def.genome.form))},
    .c=.{key.f,if(d.ghost)1 else 0,if(d.fits)1 else 0,d.face orelse m.dirYaw(d.dir)+pose.spin},
    .h=halo,
    .tug=d.tug,
    // its yield ripening on it, in its pods, and what it is
    .ripe=.{if(d.growth>=1)m.clamp01(d.essence/def.manaCap)else 0,m.f(def.genome.pods),def.genome.podR,d.since},
    .yield=yield,
    .glitch=if(d.ghost)vertex.noGlitch else if(lib.unforming.radiant(d.sp)).{g.unforming.glitchOf(d.seed),0,0,0}else if(lib.unforming.dies(d.sp)).{-1,g.unforming.witherOf(d.seed),0,0}else vertex.noGlitch,
  };
  if(seen)try g.inst[meshgen.plantSlot(d.sp,key.v,lod)].append(g.gpa,inst);
  if(d.caught)|name|{
    // the mesh it casts with, at every level of detail the same
    const mesh=renderer.caster(meshgen.plantSlot(d.sp,key.v,0));
    try g.caught[mesh].append(g.gpa,inst);
    try g.caughtIn[mesh].append(g.gpa,name);
  }
  if(!seen)return;
  // a light of its own over it by night (the lumi lantern's lilac crown),
  // shimmering, lighting the fog round it, as grown and well as it is
  if(def.crownGlow)|cg|if(!d.ghost){
    // how deep the night is, and its shimmer
    const night=1-g.sky.daylight();
    const shimmer=m.shimmer(tf,d.seed,crownShimmer,crownShimmerRate);
    if(night>0)try g.parts.light(at+m.v3(0,cg.high,0),m.Vice(f32,3){cg.col[0],cg.col[1],cg.col[2]}*m.splat3(night*shimmer*d.growth*d.health),cg.reach);
  };
  // a celestial bloom is the garden's light: its core sheds it round
  // about, pearl tinted by its film, pulsing slowly, brighter as it
  // assembles (a dark network's only faintly), following it as a forming
  // halo draws it in and dimming as it folds
  if(def.lightNode() and !d.ghost){
    // how far it has assembled, where a forming halo draws its light, and its pulse
    const assembled=m.smooth(m.unlerp(bloomLitFrom,1,d.growth));
    const drawn=haloMod.spiral(m.v3(at[0],y+(if(def.floating)bloomCore else def.genome.stemH),at[2]),halo);
    const pulse=1+bloomPulse*@sin(tf*bloomPulseRate+d.seed*m.tau);
    // how far the unforming has shattered it (its light goes out with it)
    const shattered=m.clamp01(g.unforming.glitchOf(d.seed));
    // how strong its light is now
    const strength=bloomLight*assembled*d.health*drawn.open*pulse*(1-shattered)*(if(d.radiating)@as(f32,1)else bloomDark)*(if(def.floating)@as(f32,1)else groundedLight)*(if(def.store>0)m.lerp(groundedEmpty,1,d.own)else 1)*m.lerp(1,lightByDay,g.sky.daylight());
    if(strength>0){
      // a soft pearl light round it (its tint a breath of its film), and
      // its cones of coloured light wandering out into the night
      const tint=m.lerpV(m.v3(1,1,1),filmHue(d.seed*3+tf*0.03),bloomFilm);
      try g.parts.light(drawn.at,tint*m.splat3(strength*bloomRound),bloomReach);
      try heartCones(g,drawn.at,strength,d.seed,tf);
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
    if(st.breath(s))|b|{
      try g.parts.breathe(.{ctr[0]+b.off[0],ctr[2]+b.off[1]},b.reach,b.low,b.high);
      // what it pours onto the ground (a root well)
      if(b.water>0)try g.parts.spring(.{ctr[0]+b.off[0],ctr[2]+b.off[1]},b.reach,b.water);
    }
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
    // in light, all it draws carries its shine: its leaves turn ley-blue
    // and its crown gathers over it (game/light_crown.zig)
    g.parts.ley=lightCrown.ley(s,ctr);
    defer g.parts.ley=null;
    try lightCrown.wear(s,&g.parts,ctr,tf);
    // unforming, it is drawn grown back down as far as it has gone
    // (lifted by a hint of magic, it bobs softly)
    const bob=m.translate(m.v3(0,st.bobAt(s.def(),s.seed,tf),0));
    if(!s.def().bare)try g.parts.emit(s.def().mesh,m.chain(&.{bob,s.place(ctr),m.scale3(m.v3(breathe,2-breathe,breathe))}),.{
      .glow=glow+glowActive*a,.flutter=flutterAmount,.phase=s.seed,.fade=s.def().sap,
      .sway=s.def().sway,.tall=s.def().tall,.grown=s.grown,.fidget=s.def().fidget,
    });
    try st.emit(s,&g.parts,ctr,tf);
    g.parts.around=null;
    if(rooted and !pose.still())try roots(g,ctr,m.f(s.def().size),m.dirYaw(s.dir)+pose.spin,pose,s.seed,s.def().pale());
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
  const ok=g.canPut(h) and g.player.inReach(h[0],h[1]) and g.player.inv.count(item)>0;
  if(item.plants())|sp|{
    // a fixed seed so the preview does not spin about as the cursor moves
    return plant(g,.{.sp=sp,.x=h[0],.y=h[1],.at=Plants.spot(sp,h,g.hoverAt),.ground=g.heightAt(h[0],h[1]),.growth=1,.seed=ghostSeed,.ghost=true,.fits=ok,.dir=g.placeDir,.caught=renderer.looseCatch},tf);
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
/// how far the wild flowers bend in the wind, and the height they bend over
const wildSway:f32=0.6;
/// (the height they bend over)
const wildTall:f32=0.7;
/// how brightly their crests and tongues glow at the deepest night
const wildGlow:f32=0.9;
/// the warm light a grown one throws round its crest by night (linear), how
/// high over its foot it shines from and how far it reaches
const wildLight=m.v3(1,0.45,0.12)*m.splat3(0.35);
/// (how high over its foot)
const wildLightAt:f32=0.68;
/// (how far it reaches)
const wildReach:f32=1.6;
/// the wild flowers within `reach` of the camera focus (game/wild.zig):
/// each its clump, grown as far as it has come, swaying, turned its own
/// way; by night their crests and tongues glow and throw a warm light
fn wild(g:*Game,reach:f32)Allocator.Error!void{
  // how dark it is: the glow grows with it
  const night=1-g.sky.daylight();
  var it=g.wild.flowers.iterator();
  while(it.next())|e|{
    // its tile, and its middle on the ground
    const t=lib.wild.unkey(e.key_ptr.*);
    const f=e.value_ptr.*;
    const c=g.world.chunkOfTile(t[0],t[1]) orelse continue;
    const at=m.tileCentre(t[0],t[1],c.height[ck.localIndex(t[0],t[1])]);
    if(@abs(at[0]-g.cam.target[0])>reach or @abs(at[2]-g.cam.target[2])>reach)continue;
    // how far grown, how brightly it glows, and its mesh
    const grown=lib.wild.Wild.grown(f,g.time);
    const lit=wildGlow*night*grown;
    const mesh:lib.meshlib.Id=switch(f.kind){.young=>.birdOfParadiseYoung,.plain=>.birdOfParadise,.old=>.birdOfParadiseOld};
    try g.parts.emit(mesh,m.chain(&.{m.translate(at),m.rotY(f.turn*m.tau)}),.{.glow=lit,.phase=f.turn,.sway=wildSway,.tall=wildTall,.grown=grown});
    if(lit>0.05)try g.parts.light(at+m.v3(0,wildLightAt,0),wildLight*m.splat3(lit),wildReach);
  }
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
