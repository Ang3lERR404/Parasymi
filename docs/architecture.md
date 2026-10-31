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

### The pool
- It is `w.io` (`World.io`). Main sets it after `Game.init` and in
  `restore`. Anything holding the world uses it.
- `null` runs everything in place. That is what headless tests and
  `Game.init`'s first stream use.

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
- vectors and matrices, `alignY`, `Frustum`;
- motion and curves: `spring`, `springDamper`, `catmullRom`,
  `splineResample`.

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

A new see-through part role goes in `vertex.seeThrough`.

### What glows lights the air
Every part that is light itself (`PARTS_LIGHT`: beams, flashes, the halo,
energy, the constellate's lines and points) also lights the fog round it.
`partsAir` draws the see-through runs once more into the fog's volume,
after its march, with shaders built with `-DAIR`: each glow spread wider
(part.vert), its light added on (`additive`) as much as the air there is
dense (`airDensity`, shaders/air.glsl, the same air the fog marches), and
hidden behind what stands in front of it. A new glowing role only needs to
be in `PARTS_LIGHT` and `vertex.seeThrough`.

### Other rules
- part.vert picks how to place a part by `PartInstance.e.x`:
  - 0 matrix;
  - 1 curve (beams; `e.y` is the reach);
  - 2 star mote;
  - 3 skinned (`e.y` is the first bone).
- `WorldPush` is 192 bytes (the limit is checked at pipeline creation).
- GPU buffers retired mid-frame wait in `Renderer.pending` until every
  frame in flight is done.
