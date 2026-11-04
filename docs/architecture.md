# Architecture and conventions in detail

CLAUDE.md holds the short rules. This file holds how each one works.

## Strings
Every word the player reads lives in one file: `parasymi.cfg` (in
`src/cfg/`). That covers messages, HUD labels, the names and descriptions
of items, plants, research, structures and tiles, and the window title.

`game/text.zig` reads it once at startup (`txt.load` in main) and never
again.

How to use it:
- Add a field to `txt.Strings` and a line to the cfg. Show it with
  `txt.s.*` or `txt.item(i)`.
- Templates fill in at runtime: `{0}`, `{1:.1}` (engine `core/text.zig`).
  Pass them to `Progression.say` or `Draw.print`.
- A list is written `a | b` and read with `txt.nth`.
- The test build embeds the cfg and fails on a missing or unknown key.

What does *not* count as text: file paths and magic numbers, shader
names, CLI flags, log and panic messages, reflection.

## Inputs
No key or mouse button is named in code. Every binding lives in
`controls.cfg`, written as `[bind] action = name | name` (GLFW key names,
`mouse_left`…). `game/controls.zig` reads it once at startup
(`controls.load` in main).

How game code asks about input:
- It asks about an `ctl.Action`, e.g. `ctl.down` or
  `ctl.pressed(in, .harvest)`. Never `glfw.Key`/`Button`.
- Engine `platform/input.zig` only polls the devices and answers for a
  `Bind`.
- Modifiers are actions too (`alt`, `take`, `run`).
- The mouse wheel and cursor are axes, not bindings.

Adding one: a new input = an `Action` tag + a cfg line + its name in
`[action]` of `parasymi.cfg` (the keybinds menu lists it). The tests fail
on an unbound or unnamed action.

Rebinding in game (pause menu, KEYBINDS): `ctl.rebind`/`reset` change
`ctl.map` between frames; main (`.bindings` request) writes what differs
from `ctl.stock` with `ctl.write`, then reads the strings again so every
`{@action}` follows.

Headless tests `ctl.fill` the embedded cfg and `ctl.hold` actions.

Text never names a key either. Write `{@action}` in `parasymi.cfg`, e.g.
`feedRate ({@harvest})`. `txt.load` runs after `controls.load` and swaps
it once for the bound key's name, as `[key]` or `[mouse]` (if it has
none, the binding name in capitals). So labels follow rebinding.

## Parallel loops (engine `core/jobs.zig`)
`jobs.each` splits a loop over the CPU cores, like handing out pages of a
book to several readers. Never spawn threads or keep a pool of your own.
Work beside the frames that touches no game state (growing the meshes,
writing `--inspect` shots) is an `io.concurrent` task on the I/O, with
its own copy of what it needs, awaited before that is freed.

```zig
jobs.each(io, n, min, Ctx, ctx, Ctx.run);
// runs run(ctx, lo, hi) over 0..n, in ranges of at least `min` items,
// and returns once every range is done
```

The first range runs on the calling thread, the rest on main's `Io` pool.
A task of its own may call it too: the meshes growing call it to build
their pieces and weld them while the loading screen draws. When items
differ widely in cost, ask for one range a core and let each take the
next item from a shared atomic counter (`Growing.Build`, the weld's
`Shared`), so no core waits on a heavy split; the result is the same.

### The pool
- It is `w.io` (`World.io`). `Game.init(gpa,io,seed)` sets it before its
  first stream (main passes its own, tests `testing.io`); main sets it
  again in `restore`. Anything holding the world uses it.
- `null` runs everything in place. That is what a loaded save's first
  stream and the editors' quiet world use.
- Tests whose heavy pieces stand alone (the long sound listens, the
  structure-mesh watch) run them side by side through `jobs.each` on
  `testing.io`, every check kept, so `zig build test` stays quick.

### When it is allowed
Only for work where each index writes only its own outputs, and reads
shared state that nothing writes meanwhile. (The caller blocks, so the
sim is still.)

Results must be identical to the serial loop:
- no shared accumulators;
- no sums whose result depends on order.

The ecology tick scatters into neighbours, so it stays serial.

### The pattern
- A small struct of the inputs (slices, `*const`) with
  `fn run(c:Ctx, lo:usize, hi:usize) void`. See `Plants.Relink`,
  `World.Generate`, `Renderer.Meshing`.
- Errors go in a per-item `[]?E`, checked after `each` returns.
- Scratch memory is one per item, never shared.
- Allocate with the gpa (it is thread-safe).
- No Vulkan, GLFW, txt or controls calls inside `run`.

### Picking `min`
Give each range enough work to pay for the hand-off (~0.1 ms). For
example `linksMin` is 512 plants; for chunks it is 1 chunk.

### Test
Every new use gets a test that it matches the serial result (`testing.io`
vs `null`, as in plants/world).

## Math
All math goes through engine `core/math.zig` (`m`). It has:
- scalars and `unorm8`;
- tiles: the `footprint` and `ring` iterators, and `Chunk.tileOf` to get
  back from a local index;
- directions: `dirs`, `dirVec`, `dirYaw`;
- types: `Vec(t,s)` (a SIMD vector, for lanes summed together), `Vice(t,s)`
  (a plain row `[s]t`: GPU and save layouts, tables, runtime-indexed lanes),
  `Mat(t,s,a)` (`a` columns of `Vec(t,s)`); `V3`, `V4`, `M4` are built on
  them;
- vectors of any width: `sumOf`, `meanOf` (the middle of many points),
  `lenOf`, `splatOf`; for points `dist`, `len`, `dot`, `norm`, `lerpV`;
- ramps: `lerp` and `unlerp` (lerp undone, held in 0..1);
- vectors and matrices, `alignY`, `Frustum`;
- motion and curves: `damp`, `dampV`, `dampBy` (easing toward a target,
  the same at any frame rate), `spring`, `springDamper`, `catmullRom`,
  `splineResample`;
- constants: `pi`, `tau`, `halfPi`, `sqrt2`, `goldenAngle` (leaves,
  petals and shards stepped round so none line up), `goldenShare`
  (`@mod(i*goldenShare,1)` scatters steps evenly over 0..1).

Use these, never the same thing written out by hand:

| Instead of | Write |
|---|---|
| `@Vector(n,t)`, small `[n]t` | `m.Vec(t,n)`, `m.Vice(t,n)` |
| `m.len(a-b)` | `m.dist(a,b)` |
| `m.clamp01((x-a)/(b-a))` | `m.unlerp(a,b,x)` |
| `x+=(t-x)*@min(1,dt*k)` | `x=m.damp(x,t,k,dt)` (`dampV` for points) |
| `@as(m.Vec(t,n),@splat(x))` | `m.splatOf(t,n,x)` |
| `@sqrt(m.sumOf(t,n,v*v))` | `m.lenOf(t,n,v)` |
| `2.39996`, `0.618` | `m.goldenAngle`, `m.goldenShare` |
| `a[0]-b[0],a[1]-b[1]` by lanes | `a-b` on `Vec`s |
| a ray's closest pass to a segment, worked out by hand | `m.rayNearSegment(o,d,a,b)` (`.t` along it, `.gapSq` off it) |

When a new pattern repeats, add a helper here (with a test) rather than
writing it out again.

The same holds outside the maths:

| Instead of | Write |
|---|---|
| `[n]?Voice` with a free-slot search, a turn counter and a render-and-drop loop | `dsp.Pool(Voice,n)`: `add` (free, else the oldest), `cycle` (always the next in turn), `addFree`, `render`, `clear` |
| `@exp(-1/(seconds*rate))` | `dsp.fall(seconds,rate)` |
| a sound's pan worked out per sample, or `.{x,x}` | `dsp.spot(p)` once, then `dsp.put(gains,x)`; `dsp.mid(x)` for the middle |
| a sound's pan from where it is in the world | `ear.hear(at,muffle)` into a `dsp.Spatial` (the mixer's `dsp.Ear`, told each frame from the camera; `muffle` from `game.muffle(at)`) |
| `r=if(there)@min(1,r+grow)else@max(0,r-wither)` | `r=st.reaching(r,there,grow,wither)` |
| a spore flight, launch, homecoming, count or drawing of its own | the sporecaster's `drift`, `launchSpore`, `bringHome`, `aloft`, `emitSpores` over a `caster.Air` |

Colours go through engine `core/color.zig`.

Inverting a matrix: use `m.inverseRigid` or `m.inverseAffine`; `m.inverse`
only as a fallback. Add missing methods with a test.

A singular matrix (one that can't be undone, like squashing a shape flat)
is a bug (`@panic` in debug).

## Meshes and materials

### Where pieces come from
- meshgen primitives: `tubeR`/`tubeC`, `vine`, `braid`/`braidTurned`,
  `bundle`, `loft`, `patch`, `lamina`, `blade`/`bladeAlong`, `petal`,
  `stamens`, `leavesAlong`, `bands`, `ellipsoid`, `cone`.
- Shared kits: [kits/README.md](kits/README.md), one file per kit (update
  it with the kit).
- Symbiotic structures use `structureKit` and the conduit's `arch`: its
  weave, spine and side roots (`conduit.arch`, `spineCtrl`; `core = null`
  for a bare weave).
- Structures: [growth.md](growth.md).

### Stamens, leaves and petals
- Stamens (`meshgen.stamens`): grown filaments with two-lobed pollen
  anthers. They are `.leaf`, so they fold and open with the petals. Icons
  use `Icon.stamens`. Closed buds hide theirs.
- Leaves and petals (`meshgen.lamina`) are a thin closed shell, rounded
  over at the edges with a small bevel. Its thickness is `laminaThick` of
  the broadest half-width.
- Leaves (blades, fur leaves) fold toward a pale midrib vein, raised in
  the fold and fading to the tip. Petals have no vein.

### Liquids and see-through materials
- Liquid essence (part `.essence`, a germinator's) is solid. Its colour is
  the instance tint (sRGB). tu.x is the way it flows (streaks); below 0 it
  is still.
- Translucent sap: part `.bloom` with instance `fade < 1`. It has a
  fresnel glow (brighter at grazing edges), its hue comes from the vertex
  colour, and `tint` shifts it. The `.ear` inner face and `.resin` work
  the same way.

### See-through is two passes
Think of it as painting the solid things first, then laying the glass
over them.
1. `plants`/`parts` keep only fragments with alpha ≥ 0.996, and write
   depth.
2. `plantsGlass`/`partsGlass` draw the same instances with shaders built
   with `-DGLASS` (build.zig `variants`). They blend the rest over every
   solid surface, testing depth but writing none.

Each grown mesh keeps its see-through triangles last (the weld's
`Run.early`). `plantsHead`/`partsHead` draw the always-solid head with
shaders built with `-DHEAD` (only the materials those triangles take);
`plants`/`parts` draw the tail with the whole shader; the glass and air
passes draw only the tail.

A new see-through part role goes in `vertex.seeThrough` (a plant's in
`renderer.plantGlassy`), or it is drawn with the HEAD shader and never
in the glass pass.

### What glows lights the air
Every part that is light itself (`PARTS_LIGHT`: beams, flashes, the halo,
energy, the constellate's lines and points) also lights the fog round it.
`partsAir` draws the see-through runs once more into the fog's volume,
after its march, with shaders built with `-DAIR`: each glow spread wider
(part.vert), its light added on (`additive`) as much as the air there is
dense (`airDensity`, shaders/air.glsl, the same air the fog marches), and
hidden behind what stands in front of it. A new glowing role only needs to
be in `PARTS_LIGHT` and `vertex.seeThrough`.

### As many points of light as the garden throws
No point of light is ever dropped: the frame's lighting record (engine
`light.Head`, then every `vertex.Light` the scene makes) grows to hold
them, and the view is cut into cells (engine `render/cells.zig`): the
screen into 32 by 18 tiles, each tile along the eye's depth into 32
slices (the nearest from the eye to 1 unit, each further one a constant
share deeper, the last running on), and one more cell a tile for its
whole depth. Each frame a compute pass (`cells.comp`) tests every light's
sphere of reach against every cell's planes and writes a bit for each
light that touches it, a 32-bit word for every 32 lights, so however many
crowd one cell none is left out. A surface finds its cell from where it
lands in the eye's clip space (lighting.glsl `cellAt`) and walks only its
bits, in the order the frame holds the lights, so its sum is the sum over
all of them (`pointLight`, the game's `pointLights`); a ray through the
air walks its tile's whole-depth cell (`columnAt`, fog.frag). A point
outside every cell (behind the eye, off screen: the overhead map) walks
every light. The shadow cubes and traced shadows are unchanged: a light
still says which cube it holds in its `col[3]`. A new shader reading the
lights includes `light.glsl` (the record is in `lighting.glsl`) and
walks `lightsIn(L, cellAt(L, wpos), w, count)` the same way.

### Points of light thrown in a cone
A point of light (engine `vertex.Light`, as many as the garden throws) may be
thrown in a cone, a spotlight: its `dir` holds the way the cone's middle
points and the cosine of its half-width (`Light.round`, w below -1, lights
all round). light.glsl `coneOf` fades it softly to the cone's rim; every
surface (`pointLight`, the game's `pointLights`) and the fog (fog.frag, the
cone's glow summed across each ray in `CONE_STEPS`) take it. The game
throws one with `Parts.spot`.

### Points of light with shadows
The few most telling points of light near the camera hold shadow cubes
(engine `render/cube.zig`), drawn before the world by the `cube` passes
(`plantsCube`, `partsCube`: plant.vert and part.vert built with `-DCUBE`,
which brings `SHADOW`), a face at a time, each pass drawing from its own
list of what may stand in that face (`Frame.cubeInst`, filled in
`prepare` from `Renderer.cubeSpheres`, culled by each mesh's reach,
`Ext.plantReach`/`partReach`). The fog marches each shadowed light's
chord and lets through only what its cube does; every lit surface looks
it up in `pointShadow`. A new caster needs nothing: whatever casts into
the key light's map casts here (and a radiant plant's petals, leaves and
veil, plant.vert under CUBE). A light says which cube it holds in its
`col.w` (the renderer sets it).

### Ray-traced shadows
Where the GPU can trace rays (`Ctx.rayTracing`) and RAY TRACING is on
(`Renderer.setRays`, `tracing`), the engine draws no shadow map or cube
(they are cleared, never read) and traces instead (engine
`render/rays.zig`):
1. `prepare`: each capture pass (`plantsCapture`, `partsCapture`, target
   `.capture`) reserves room for its instances' vertices
   (`Rays.reserve`) and writes its table: each instance's first slot less
   its mesh's first vertex, by its place among the instances
   (`renderer.caught`). The plants' capture draws its own instances
   (`Scene.caught`): every plant of each patch (`renderer.patchTiles`,
   4×4 tiles) with any plant seen, at its caster mesh, each named for its
   patch (`Scene.caughtIn`, `renderer.patchCatch`; a placement preview
   and the title's stage plants `looseCatch`).
2. The capture passes draw those instances with plant.vert/part.vert
   built with CAPTURE (which brings SHADOW without its views), nothing
   rasterized (`pipeline.Desc.discard`), the push's `light` pointing at
   the table. Each vertex is written where it is placed (light.glsl
   `capture`), as NaN where it casts nothing; each instance is handed to
   a bottom level by name (`renderer.handed`, `Into`: `plantLevel` and
   `pointLevel` of its patch, the latter for a radiant plant's
   point-only petals; `partLevel`). Each geometry added folds its indices,
   vertex count and triangles into its level's key.
3. `Rays.build` refits each level whose key matches its last full build
   (rebuilt every `refits` frames, staggered), builds the rest, in
   batches sharing a capped scratch (`scratchBatch`), then the top level
   (at most `maxLevels`), which set 0 binding 3 holds (`casters`);
   `Lighting.info.z` says rays are on. A level uncaught a few frames is
   let go, one outgrown is freed once no frame in flight traces it.
4. The lit fragment shaders are the RAY builds (`Desc.rayFrag`:
   plant/part head, solid and glass, terrain and detail, pools, fog),
   taken where the GPU can trace rays; light.glsl's `keyShadow`,
   `airLit`, `cubeLit` and `pointShadow` trace while `info.z` is set,
   else read the maps. plant.frag and part.frag define SAMPLED (shaded per
   sample), so a pixel's rays are shared among its samples
   (`info.w` the world's samples).
A new caster needs nothing: what its shadow pass casts is caught. A new
lit shader takes a RAY build in build.zig's variants and its pass's
`rayFrag`.

### Other rules
- part.vert picks how to place a part by `PartInstance.e.x`:
  - 0 matrix;
  - 1 curve (beams; `e.y` is the reach);
  - 2 star mote;
  - 3 skinned (`e.y` is the first bone);
  - 4 a burst; 5 falling over the menu's stage; 6 a starlit patch's spark
    (`e.y` its seed, `e.z` how far it rises, below 0 falls, `e.w` its spread).
- `WorldPush` is 192 bytes (the limit is checked at pipeline creation).
- GPU buffers retired mid-frame wait in `Renderer.pending` until every
  frame in flight is done.
