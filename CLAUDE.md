# CLAUDE.md

## What this is
Player-centric Factorio-like automation game. Magically infused plants (parasitic +
symbiotic lineages that converge). Zig 0.16, zglfw + vulkan-zig (Vulkan 1.3),
Windows, no asset files (every mesh, the font and all UI shapes are procedural).
2.5D top-down 3D. Adjustable pitch (30°–85°, default 55°), yaw via Q/E. No free
rotation in play; a free inspection camera is always available (Ctrl+F).

## Build
```
zig build run                     # debug (validation on)
zig build run -Drelease=true      # ReleaseFast (-Doptimize is not accepted)
zig build run -- --demo           # test garden + structures, fast-forwarded
zig build run -- --stress         # 120×120 plant field
zig build run -- --tod=0.9        # time of day (0=midnight, 0.5=noon)
zig build run -- --novsync --seed=0x1234
zig build run -- --load           # load save
zig build test                    # headless logic tests (no window/GPU)
```

Needs `VULKAN_SDK` (`vk.xml` + `glslc`). Pinned: vulkan-zig `zig-0.16-compat`,
zglfw `f04fdbf`. Upstream heads need 0.17. A stray `CPATH` breaks GLFW's C build.

## Controls
WASD move, Shift run, Q/E yaw, Ctrl+W/S pitch, wheel zoom. LMB gather/place,
RMB uproot, F harvest/feed, Shift+F take, C configure, R rotate, 1–9/0/- hotbar
(only), click a research node or weave recipe in its panel,
Tab belly (weave), T research, F3 debug. Esc closes a panel, else pauses (Q in
pause = save and quit). F5 save, F9 load, F11 fullscreen.
Free cam (Ctrl+F): click to look, WASD fly (Shift fast), Space/Ctrl+Space
rise/sink, Q/E roll, wheel dolly, unclamped; eases back in 0.3 s.

## Performance targets
- 8 ms frame (120 FPS), RTX 3060-class, validation ON.
- 30 Hz fixed sim tick, decoupled from render (currently 60 Hz, `play.TICK`).
- Chunk: 64×64 tiles, < 2 ms gen+upload, queue-based (currently 32×32).
- < 200 draw calls at stress. Instancing expected.
- Level of detail: every plant and library mesh is built at `meshgen.LODS`
  (3) levels; each level keeps every other ring/row along a surface and
  half its sides (`Builder.lod`, applied inside the primitives, so new
  meshes get it for free). Plants and parts pick their level by eye
  distance (`meshgen.lodAt`, `LOD_AT` 36 / 70). Plant slots are
  (species, variant, lod); part slots `meshlib.slot(id, lod)`.
- Culling: only what the camera sees is drawn: chunks (terrain and detail
  passes, `CHUNK_RADIUS`), plants and parts (`m.Frustum` from the
  view-projection; `Parts.look` sets the frame's eye and view).
- Release (RTX 4060 Ti, 1600x900, no vsync): demo ~2.9 ms, stress ~2.5 ms.
- **Computation-heavy work goes on the GPU.** Dense or per-element visual
  work (grass, scatter, particles, procedural detail, deformation,
  animation fields) is generated or evaluated in shaders (instancing,
  vertex/fragment fields, compute), not built on the CPU per frame or per
  chunk. The CPU keeps game state and sim logic (it sends small records:
  a tile's corners, a mote's state, the tail's four control points).

## Layers (import only downward)

```
core      math, color, rng, noise, registry
platform  input, display (fullscreen)
gfx       Vulkan ctx, swapchain, buffers, pipelines, meshgen, meshlib
world     chunks (tile SoA + occupancy), generation, streaming
sim       items, species, plants (footprints, floaters), ecology tick
game      player, actions, structures, research, craft, sky, hud, view, play, save
render    renderer + passes, terrain meshing, camera
ui        SDF draw batch, font
main      wiring, frame loop, save/load/fullscreen requests
```

## Registries
One module per thing. Enum via `std.meta.DeclEnum`, dispatch via
`switch (id) { inline else => |k| reg.module(k).hook(...) }`; hooks optional
(`reg.has`). Adding a thing = one file + one line in the namespace. Never add a
`switch` over registry kinds outside the registry file; add a hook.

| Domain | Entry | Hooks |
|---|---|---|
| species | `sim/species.zig` | `def` (genome drives the grown mesh) |
| meshes | `gfx/meshlib.zig` | `build(b)` (order = draw order: translucent after what they cover) |
| structures | `game/structures.zig` | `def`, `State`, `tick`, `wants`, `output`, `release`, `configure`, `emit`, `describe`, `ground` |
| research | `game/progression.zig` | `def`, `apply`, `unlocks`, `completed`, `veil` |
| hud panels | `game/hud.zig` | `draw`, `visible` (draw order = declaration order) |
| render passes | `render/renderer.zig` | `desc`, `Frame`, `initFrame`/`deinitFrame`, `record` (sky, terrain, plants, parts, ui) |

Items (`sim/items.zig`) and weave recipes (`game/craft.zig`) are plain data tables.

## Conventions
- 2-space indent, `name:Type` (no space after colon), terse `//!`/`///` docs, LF.
- All math via `core/math.zig` (alias `m`): scalars, tiles, `m.dirVec`/`dirYaw`,
  vectors/matrices, `m.spring` (exact critically damped), `m.springDamper`
  (substepped spring-mass), `m.catmullRom`/`splineResample`, `m.alignY`.
  Colours via `core/color.zig`. Never reach into `std.math` or hand-roll casts.
- No inline `std.ns.Name` — alias at file top.
- **Never hand-roll linear algebra.** Use `m.inverseRigid` (rotation +
  translation), `m.inverseAffine` (scaled), `m.inverse` only as fallback. If a
  method is missing, add it + a test. A singular matrix is a bug: `@panic` in
  debug, don't silently return zero.
- **All geometry watertight and seamless:** tubes share rings (parallel
  transport), bundles continuous, cones/lofts capped, sheets shared-vertex.
  Deform meshes only with smooth position fields so shared vertices move alike.
- **Grown vines use Catmull-Rom splines** with `growthPath()`/`grow()`
  (wobble, curl, taper, seed; the root never moves). Never a straight line or
  simple arc.
- meshgen primitives: `tubeR`, `vine`, `braid`/`braidTurned`, `bundle`, `loft`
  (any cross-section), `patch` (grid sheet), `blade`/`bladeAlong`, `bands`
  (vines over an ellipsoid), `ellipsoid`, `cone`.
- Translucent sap: part `.bloom` with instance `fade < 1` → fresnel (amber at
  grazing angles, see-through centre); hue follows vertex colour, so instance
  `tint` shifts it. Part `.ear` inner face does the same.
- Push constants: `WorldPush` is 176 bytes (limit checked at pipeline creation).
- UI: organic, animated, no boxes. SDFs in `shaders/ui.frag`.
- Edits: write to files, pass files to scripts. No inline heredocs.

## Zig 0.16 API notes
- `std.Io` replaces all old I/O. Pass an `Io` instance like an allocator.
- "Juicy Main": `main` accepts injected params. No global env/args.
- `@Type` removed. Use `@Pointer`, `@ErrorUnion`, explicit `error{...}` sets.
- `ArrayList{}` → `.empty`. `ArenaAllocator` is lock-free.
- Build: `root_module` + `Module`. Deps in `zig-pkg/`.

## Code design
- Tagged unions for exclusive states (`Game.mode`, `Camera.view`,
  `Display.mode`, `Occ.get()`). Explicit error sets in public APIs
  (`Allocator.Error`, `save.Error`, `gfx.Error` folded via `ctx.fold`).
- `comptime T: type` over `anytype`. Distinct types for domain IDs
  (`PlantId`, `StructId`, `MeshSlot`, `Occ`).
- Exhaustive `switch`. Pass allocators explicitly. `defer deinit()` immediately;
  `errdefer` on init paths (half-built renderer frees cleanly).
- Arena allocators for batch work. `std.testing.allocator` in tests.
- Vtable pattern for many-method interfaces. SoA for hot loops.
- `try` by default. Translate errors at module boundaries.
- GPU buffers retired mid-frame wait in `Renderer.pending` until every frame
  in flight is done.

## Design
- No global resources. Items live in the player's belly, in structures, or
  in plants until harvested.
- Every plant is player-seeded and must grow before use.
- Research: Factorio-lab model. A structure consumes ingredients unit by unit.
- Hand-weaving is the bootstrap (wolf weaves seeds from gathered matter + starlight).
- Plants and structures share occupancy. Footprints: 1×1, 2×2, or floating.
- Player-centric, builds toward full automation.
- Structures: conduit (pulls from behind, pushes forward; grows a side root
  to any plant beside or behind it and harvests it once the root arrives),
  sap cache, germinator, research bloom, root-digger.
- Root-digger: 1×1 on soil/moss, digs an adjacent node 1 item/4s into an
  8-item buffer, feeds adjacent structures (conduits pull from it), idles when
  no node. Recipe: 3 fibre + 2 grit + 1 ley shard. Gated by "Deep Rooting".
- Confluence (convergence hybrid, `game/convergence.zig`): a mature symbiote
  and mature parasite within 2 tiles (or joined by a conduit chain) root a
  2×2 confluence beside them unless one already holds them. Never sown
  (`seed = null`); grows 1.5× the slower parent (per-plant `span`) in 4
  stages; yields convergence essence + its parents' seeds; mature, it halves
  parasite drain within 3 tiles. Discovery-gated; "Convergence Theory" only
  reveals its yield in the HUD.
- Celestial bloom (`species/bloom.zig`, `ecology.Radiance`): a sown,
  floating symbiote (hover 3.2, above the motes) that yields nothing and
  radiates a field of celestial energy (3.5 tiles). Blooms within 10 tiles
  link into networks; a network radiates when it holds a mature bloom, and
  then all its blooms (growing ones too) hold their fields, so uprooting a
  linking bloom cuts off the blooms beyond it. Plants with
  `needs_radiance` (the vesper bloom, for now) halt and wither (0.06 HP/s)
  outside every field. Worked out each tick from the blooms only (pairwise
  links, then each radiating bloom's tiles), like containment. The hover
  panel shows RADIATING/DARK and links, DRAWING RADIANCE/WITHERING. Seed:
  3 starlight + 1 ley shard + 2 essence (hotbar `-`).
  Visual (form `.radiant`, `meshgen.radiant`): a structure of light, not a
  flower: a faceted luminous core with a brighter nucleus, spires above
  and below, a ring of lens plates and a looser ring of crystal shards
  orbiting at their own paces (counter to each other), a tilted halo.
  Each fragment carries its assembly order (tu.x), ring (tu.y) and bearing
  (colour alpha): plant.vert drifts it in from its bearing and locks it in
  as growth passes its order (it assembles, never scales up), and the
  bloom drifts and bobs instead of bending. plant.frag: the only true
  glow, light carried in thin tissue (fresnel, core, pulse, bubbles),
  translucent, fragments fading in as they lock. Beams (meshlib
  `bloom_thread`, part `.thread`): a flat ribbon carried on the GPU through
  the parts pass (curve mode, `e.y` how far it reaches) from bloom core to
  core, running true, its width turned to face the eye; a bright near-white
  core falling off to a warm faintly iridescent halo, pulses of light
  running along it, fading into each core; bright (it blooms) when its
  network radiates, a faint trace when dark; it reaches out from the more
  grown bloom as that bloom finishes assembling.
- Item ids are stored by value: new items go at the end of `items.Item`.
- Save (`game/save.zig`, `parasymi.sav`): the world regenerates from the seed;
  only the gardener's changes are stored. Bump `VERSION` when a stored layout
  changes (the fingerprint checks sizes only).

## Visual (current)
- Terrain (`render/terrain_mesh.zig`): smooth ground, no walls or ramps.
  Each tile is a fan of four triangles: its centre at the tile's height
  (everything on it stands there), corners shared with its neighbours
  (average height, colour and ley, from a per-chunk grid worked out once),
  smooth normals; land dips under the water at the
  shore. Detail is grown on the GPU (detail pass, `shaders/detail.vert`):
  each tile with any gets one `DetailTile` record (corner heights, colour,
  kind, blade count) and runs 60 vertices: thin grass blades on every tile
  but water and soil (tile-coloured, swayed by the garden wind), or a clod
  and a stone (faceted lumps) on soil, all hashed from the tile; drawn on
  chunks within `DETAIL_R` (28 tiles) of the view's focus. Ley lines carry a faint plexus of drifting
  points joined by threads (terrain.frag); ley sight glows smoothly across
  tile borders. info.z = 255 marks the ground's top surface. Streaming
  meshes at most `MESH_MS` (3 ms) of chunks a frame. Fog closes in
  before the drawn edge; contact shadows under the wolf's feet.
- Plants: grown spline stems/tendrils, 4 mesh variants per species (picked by
  tile). Motion (plant.vert) is rooted and heavy: points bend about the root
  in the wind's plane (h², tips lagging), one garden-wide wind with slow
  gusts rolling across as a wave, per-species `sway` (heavy trees 0.6,
  floaters 1.8); leaves lift a little; parasite fronds curl slowly; hanging
  filaments trail downwind. Material (plant.frag) is the wolf's vocabulary:
  muted skin with a fibre sheen, old growth near the ground densifying to
  root brown, colour carried by sap seen through thin/young tissue (back
  light, grazing angles), no self-glow (rim only at night). Growth read:
  plants scale up as they grow; parasites come up with their fronds closed
  and open as they mature. `v_young` (newest growth and tips thinner, more translucent). Petals see-
  through face-on. Holding a seed shows its grown plant as a ghost on the
  hovered tile (green fits, red not). Parasitic: alien, not hostile: pale pearl/lilac with a
  thin-film iridescent sap. Symbiotic: greens/teals.
- Plant silhouettes: symbiotes (`herb`) flare into short roots, carry their
  leaves on one vase envelope (`leaf_from` lifts it into a crown for trees),
  and bloom from a calyx with sepals: two cupped whorls of real petals
  (`meshgen.petal`: narrow claw, broad, rounded tip). Parasites (`coil`):
  twisted 3-strand stalk on a bulbous foot, small bladders up it, a crown
  of fronds curling into spirals around a bulb; no leaves or spikes.
  Symbiote vines (tendrils, the confluence's green vine length) grow small
  leaves along them (`leavesAlong`); plant.vert holds every leaf's base
  (breathing/unfurling weighted by tu.y), and only parasites writhe.
- Grown structures speak the plants' language (`meshes/structure_kit.zig`):
  woven root mats, grown vines with leaves along them, real petals, and
  pods of the wolf's resin sap (part `.resin`, instance fade `Def.sap`;
  no light of their own). Germinator: resin pod with a seed inside, cradled
  by vines. Research bloom: woven stalk, broad violet flower, banded resin orb.
  Sap cache: clear resin pod in a woven vine basket, what it holds hanging
  inside. Conduit: a gnarled root surfacing over its tile and sinking at its
  far edge into the next (`conduit.rise`), rootlets forking into the soil,
  side roots (`conduit_tap`) creeping out to plants. Structures breathe at a
  fixed tempo (activity deepens it, never retimes it).
  Standing structures (germinator, research bloom, sap cache, root-digger;
  `Def.sway`; conduits hug the ground and do not sway, so chains stay joined)
  move like plants in part.vert: they bend from the root in the same
  garden wind (`gardenWind`/`bendIn` in common.glsl), leaves and petals
  breathe and lift; what hangs on them (orb, stored items) sways with them
  (`Look.drop`).
  Put down by the gardener they grow (`Def.grow` s; germinator 6, research
  bloom 8, sap cache and digger 4, conduit 1.5) and do no work until grown: they shoot
  up first and fill out after (`Structure.grownScale`), leaves and petals
  unfold bottom-up (part.vert), the research orb forms last.
- Floaters (`drift`): a translucent sap float, a wide catcher dish above,
  filaments trailing beneath (tips sway most); they rise and fall slowly
  and drift over a soft ground shadow (part `.shadow`, meshlib `shadow`).
- Confluence: 8 growth keys with one vertex layout, blended per vertex in
  plant.vert (binding 2 reads the next key), so it grows without stepping;
  each braid strand gathers at the crown and runs on as its red vine in one
  tube (vertex-colour gradient, ±10° hue drift in the zone); leader crowned by translucent violet petals with amber
  fresnel (plants pass blends; only these petals have alpha < 1). Sway ×1.5.
- Post-processing (`render/post.zig`, the one post effect so far): world
  passes draw into an HDR image (`post.HDR_FORMAT`); what is brighter than
  white blooms: a 13-tap filtered chain of 5 half-size levels down (the
  first with a soft-knee threshold and a brightness-weighted average
  against fireflies) and a tent filter additively back up; the composite
  lays the glow over the scene (intensity 0.7), rolls highlights off above
  0.8 (below it the look is untouched) and adds a faint vignette, onto the
  swapchain; passes with `Desc.screen` (the UI) draw on top. ~0.1 ms.
  What glows is what is drawn brighter than 1: celestial blooms and their
  beams, motes, sap glow, ley crystals, highlights.
- Sky: gradient dome pass (fog colour at the horizon), sun/moon, stars,
  starlight motes (a faceted bipyramid of light, a tilted ring and four
  needle rays; they turn slowly, twinkle, hover breathing, and trail fading
  echoes while falling, all in part.vert's mote mode: the CPU sends each
  mote's centre, phase, life and echo).
- part.vert places an instance by `PartInstance.e.x`: 0 its matrix, 1 a
  curve (the tail), 2 a star mote.
- Resource nodes (`meshes/mineral_kit.zig`: flat-faceted crystals and
  stones): ley shards a violet crystal cluster on a dark stone root; grit
  faceted stones half sunk with quartz chips; fibre a clump of arching
  stalks (green to straw) on a root tuft that sways (`resources.Node.sway`).
- Sap (all sap materials: sacs, resin, inner ears, plant sap) is alive:
  bubbles drift up inside it and beads of it slide down its surface
  (`sapBubbles`/`sapDroplets` in common.glsl, in mesh space so they ride
  with the body). Low pitch widens the view and lifts it toward the horizon.
- UI: wobbling membranes, seed-pod slots, tendril bars, soft glow. 150 ms anim.
- Wolf (rigid joint skeleton, organic surface; `game/player.zig` rig):
  - Muted greens/browns; amber only on belly, eyes, inner ears (and beans).
  - Head: one closed surface of planes (`wolf_head.point`): broad cranium
    with sloping temples, brow ridges hooding the eyes, a stop down to a
    long wedge muzzle (narrow flat bridge, sides falling away) tapering to
    the nose bean, cheekbones flaring below the eyes, jaw line chamfered
    back from the chin over a separate lower jaw. Ears: thick (sap inner
    face 50% over a vine back shell, joined by a rolled rim), cupped with an
    inner fold, base flaring wide and sunk into the skull (`ear_root`),
    leaning 12 degrees forward and out, no flutter. Fur: leaves lie back
    over the skull behind the ears in staggered rows, lengthening into a
    ruff over the nape (`wolf_kit.leaf`: base flush, lifting off, tip
    curling back); small leaves emerge along each cheekbone. Leaf tufts
    (shoulders, tail tip) are whorls of the same fur leaves.
  - Forms of planes (`wolf_kit.form`, superellipsoids): joints are squared
    knuckles with a condyle at each end of the hinge and tendon straps over
    front and back; the deltoid is a squared cap with front and rear heads
    draping into a tendon down the upper arm.
  - Hands and feet (`wolf_kit.digit`/`claw`): a squared back of the hand /
    long squared foot with a raised arch, vine tendons over the top to four
    knuckled digits arching down to curved claws (a dewclaw high on each
    hand); sap beans under both (palm/central pad and four digit pads).
  - Limbs (`wolf_kit.limbCore`/`muscle`/`tendon`): squared cores (lofted
    rounded-square sections) with distinct muscle forms (bicep/tricep,
    brachioradialis, quadriceps/hamstring, gastrocnemius) and vine tendons
    (Achilles, down the forearm and metatarsal); thighs and calves keep
    grown vine wraps. Torso weave over trapezius and lat forms; rump lobes
    are squared forms; fur leaves ring the tail, lying back toward its tip.
    Every vine on the body is a grown vine: it tapers to a point at both
    ends (torso weave strands staggered and tucking into the core, belly
    net, collarbone, leg wraps, `mg.bands`), never a hard cut, and the
    torso weave and belly net carry small fur leaves along their length.
  - Torso: three sections (broad loose-woven chest, tight vine-corset waist,
    hips); pectorals are broad dishes of resin sap (wider top edge, areola +
    nipple below the crown), base held on the chest, surface sprung; chest
    vines tucked behind.
  - Belly (`wolf_belly.zig`, torso units): a teardrop sac, a full gut
    drawing in along a concave flank into a tongue that runs up between the
    pectorals; translucent sap (72%). Filling swells only the gut (tu.x),
    most low and forward (part.vert, `Look.sag`), the tongue stays on the
    chest; a belly button sunk in the sap surfaces and pops out as it fills
    (tu.y 2, fill in `give[0]`). Up to 5 dark lumps inside on
    spring-dampers driven by acceleration.
  - Arms: deltoid caps, bicep/tricep forms, forearm tapering 1.1→0.7.
  - Rear: two squared vine lobes pressed together at the cleft, sap nodes (40%), firm springs;
    tailbone knot above them; tail (`wolf_tail`, braid + fur leaves, built
    once straight over 0..1) is bent on the GPU along the Catmull-Rom curve
    through the rig's spring-steered joints (part.vert curve mode).
  - Legs: anthro digitigrade (vertical thigh, calf back to a high hock with a
    +25% swell, forward metatarsal), long feet, sap beans (80%, browner),
    central pad flattens 10% when planted.
  - Breathing 2% torso / 1% limbs (CPU instance scale); body strands wobble
    0.03; anisotropic sheen along vine tangents.
- "Celestial / beyond comprehension" is the next phase target.

## Scope guard
Do NOT build without explicit direction: audio, multiplayer, PBR/IBL, further
post-processing (bloom was asked for), Linux/macOS. Flag and stop if a task drifts toward these.

## Decision authority
Changes a layer boundary or build/run interface → stop and ask.
Otherwise decide and note with `// decision:` comment.

## Current state
Done: engine, terrain, streaming, plants + 7 species, ecology, structures,
footprints/floaters, research (9 nodes), hand weaving, save/load, pause,
fullscreen, root-digger, spline vines, adjustable/free camera, sky dome, wolf
anatomy + "alive" passes, convergence hybrid (confluence).
**Next (post-prototype / vertical slice):**
1. 2–3 more species per lineage
2. Research tree to ~12 nodes
3. First world event (something that *happens*, not just a research unlock)
4. Bloom + one "wow" visual moment (sky shift at convergence)
Target: a stranger plays 2 hours and says "I want to see what happens next."

## Finish line
Work until the current phase's acceptance criteria are met. Don't end with
"next I would…" — take the next step. Stop only for a blocking decision or
phase completion.

## Plant rule
Everything grown (plants, grown structures, anything plant-like) must have a
proper growing animation, be moved by the garden's sway, and match the
current quality of the rest of the plants in game, unless the user specifies
otherwise. A new or changed grown thing is not done without all three.

## Cohesion rule
Every major visual overhaul sets the bar for everything of its kind: the
rest of the wolf's body is brought up to match each upgrade (forms of planes,
fur leaves, sap material), and the plants and grown structures stay
consistent with each other. New plants (and anything new that is grown)
follow the current look, motion and growth by default, built from the shared
kits (`meshgen` plant forms, `structure_kit`, `wolf_kit`), never from older,
cruder primitives.

## Visual authority
The user is the artist. On all visual/aesthetic decisions (proportions,
silhouette, material feel, "does this read as X"), their word is final.
If they say something looks "off," "weak," "generic," or "too X," that
is the acceptance criterion — implement the fix they describe, don't
propose alternatives or ask for justification.

## Working rules
- Commit and push `devel` after every verified change (builds, tests pass),
  without asking. Never commit `parasymi.sav`. Broken work is reported, not
  committed.
- Reports: no commentary. End a task with a short list of changes only;
  a real deviation or blocker is one bullet.
- Verify visual work in the running game (a scratch copy may move the camera);
  say what was not checked.
