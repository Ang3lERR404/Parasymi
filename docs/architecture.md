# Architecture and conventions in detail

CLAUDE.md holds the short rules; this file holds how each one works.

## Strings
Every player-facing string (messages, HUD labels, names/descriptions of
items, plants, research, structures, tiles, the window title) lives in
`parasymi.cfg` (`src/cfg/`), read once at startup by `game/text.zig`
(`txt.load` in main) and never again.
- Add a field to `txt.Strings` and a line to the cfg; show it via
  `txt.s.*`/`txt.item(i)`.
- Templates are runtime: `{0}`, `{1:.1}` (`core/text.zig`), passed to
  `Progression.say` / `Draw.print`; lists are `a | b` (`txt.nth`).
- The test build embeds the cfg and fails on a missing or unknown key.
- Not text: file paths/magic, shader names, CLI flags, log/panic messages,
  reflection.

## Inputs
No key or mouse button is named in code. Every binding lives in
`controls.cfg` (`[bind] action = name | name`, GLFW key names,
`mouse_left`…), read once at startup by `game/controls.zig`
(`controls.load` in main).
- Game code asks about an `ctl.Action` (`ctl.down`/`ctl.pressed(in,
  .harvest)`), never `glfw.Key`/`Button`; `platform/input.zig` only polls
  and answers for a `Bind`.
- New input = an `Action` tag + a cfg line (the test fails on an unbound
  action); modifiers are actions too (`alt`, `take`, `run`).
- Headless tests `ctl.fill` the embedded cfg and `ctl.hold` actions. The
  mouse wheel/cursor are axes, not bindings.
- Text never names a key either: write `{@action}` in `parasymi.cfg`
  (`FEED ({@harvest})`); `txt.load` (after `controls.load`) replaces it once
  with the bound key's `[key]`/`[mouse]` name (else its binding name in
  capitals), so labels follow rebinding.

## Parallel loops (`core/jobs.zig`)
`jobs.each(io, n, min, Ctx, ctx, Ctx.run)` runs `run(ctx, lo, hi)` over
[0, n) in ranges of at least `min` items (first range on the calling
thread, the rest on main's `Io` pool) and returns once all are done. Never
spawn threads or keep a pool of your own.
- The pool: `w.io` (`World.io`, set by main after `Game.init` and in
  `restore`); anything holding the world uses it. `null` (headless tests,
  `Game.init`'s first stream) runs it all in place.
- Only for work where each index writes only its own outputs and reads
  shared state that nothing writes meanwhile (the caller blocks, so the sim
  is still). Results must be identical to the serial loop: no shared
  accumulators, no order-dependent sums (the ecology tick scatters into
  neighbours, so it stays serial).
- The pattern: a small struct of the inputs (slices, `*const`) with
  `fn run(c:Ctx, lo:usize, hi:usize) void`; see `Plants.Relink`,
  `World.Generate`, `Renderer.Meshing`. Errors go in a per-item `[]?E`
  checked after `each` returns; scratch is one per item, never shared.
  Allocate with the gpa (thread-safe); no Vulkan, GLFW, txt or controls
  calls inside `run`.
- `min`: enough work a range to pay for a hand-off (~0.1 ms; e.g.
  `LINKS_MIN` 512 plants, 1 chunk).
- Every new use gets a test that it matches the serial result
  (`testing.io` vs `null`, as in plants/world).

## Math
All math via `core/math.zig` (`m`): scalars, `unorm8`, tiles (`footprint`
and `ring` iterators, `Chunk.tileOf` back from a local index),
`dirs`/`dirVec`/`dirYaw`, vectors/matrices, `spring`, `springDamper`,
`catmullRom`/`splineResample`, `alignY`, `Frustum`. Colours via
`core/color.zig`. Inverses: `m.inverseRigid`, `m.inverseAffine`, `m.inverse`
only as fallback; add missing methods with a test. A singular matrix is a
bug (`@panic` in debug).

## Meshes and materials
- meshgen primitives: `tubeR`/`tubeC`, `vine`, `braid`/`braidTurned`,
  `bundle`, `loft`, `patch`, `lamina`, `blade`/`bladeAlong`, `petal`,
  `stamens`, `leavesAlong`, `bands`, `ellipsoid`, `cone`.
- Shared kits: [kits/README.md](kits/README.md) (one file per kit; update
  it with the kit). Symbiotic structures use `structure_kit` and the
  conduit's `arch` (its weave, spine and side roots: `conduit.arch`,
  `spineCtrl`, `core = null` for a bare weave).
- Structures: [growth.md](growth.md).
- Stamens (`meshgen.stamens`): grown filaments, two-lobed pollen anthers,
  `.leaf` so they fold and open with the petals; icons `Icon.stamens`.
  Closed buds hide theirs.
- Leaves and petals (`meshgen.lamina`): a thin closed shell (`LAMINA_THICK`
  of the broadest half-width) rounded over at the edges, a small bevel;
  leaves (blades, fur leaves) fold toward a pale midrib vein raised in the
  fold, fading to the tip. Petals have no vein.
- Liquid essence (part `.essence`, a germinator's): solid, its colour the
  instance tint (sRGB), tu.x the way it flows (streaks), < 0 still.
- Translucent sap: part `.bloom` with instance `fade < 1` (fresnel, hue from
  vertex colour, `tint` shifts it); `.ear` inner face and `.resin` likewise.
- See-through is two passes: `plants`/`parts` keep only fragments with
  alpha ≥ 0.996 (writing depth); `plants_glass`/`parts_glass` (the same
  instances, shaders built with `-DGLASS`, build.zig `variants`) blend the
  rest over every solid surface, testing depth but writing none. A new
  see-through part role goes in `vertex.seeThrough`.
- part.vert placement by `PartInstance.e.x`: 0 matrix, 1 curve (beams;
  `e.y` reach), 2 star mote, 3 skinned (`e.y` first bone).
- `WorldPush` is 192 bytes (limit checked at pipeline creation).
- GPU buffers retired mid-frame wait in `Renderer.pending` until every
  frame in flight is done.
