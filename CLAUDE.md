# CLAUDE.md

## What this is
Player-centric Factorio-like automation game: magically infused plants
(parasitic + symbiotic lineages that converge). Zig 0.16, zglfw + vulkan-zig
(Vulkan 1.3), Windows, no asset files (every mesh, the font and all UI shapes
are procedural) except `parasymi.cfg`, the player-facing strings, and
`controls.cfg`, the key/button bindings (both built into the game and written
out to the gardener's folder, below). 2.5D top-down 3D: pitch 30°–85° (default 55°), yaw Q/E, no
free rotation in play; free inspection camera on Ctrl+F.

## Build
```
zig build run                     # debug (validation on)
zig build run -Drelease=true      # ReleaseFast (-Doptimize is not accepted)
zig build run -- --demo           # test garden + structures, fast-forwarded
zig build run -- --stress         # 120×120 plant field
zig build run -- --tod=0.9        # time of day (0=midnight, 0.5=noon)
zig build run -- --novsync --seed=0x1234
zig build run -- --load           # load the newest saved garden
zig build run -- --demo --inspect # orbit the wolf, screenshots to shots/, then quit
zig build run -- --inspect=bloom --shots=12 --orbit=30 --dist=6 --pitch=25
                                  # focus: player | <species> | <structure> | x,z
zig build test                    # headless logic tests (no window/GPU)
```
Needs `VULKAN_SDK` (`vk.xml` + `glslc`). Pinned: vulkan-zig `zig-0.16-compat`,
zglfw `f04fdbf` (upstream heads need 0.17). A stray `CPATH` breaks GLFW's C
build. New shaders go in `build.zig`'s list.

## Controls
Defaults in `controls.cfg` (rebindable there): WASD move, Shift run, Q/E yaw, Ctrl+W/S pitch, wheel zoom. LMB gather/place,
RMB uproot, F harvest/feed, Shift+F take, C configure, R rotate. 1–9/0/-/=/Backspace pick
hotbar slots only; research nodes and weave recipes are clicked in their
panels. Hotbar slots start empty: in the belly a click lifts a stack onto
the cursor, the next puts it down (empty slot, merge, or swap: sorting by
hand); dropped on a hotbar slot it assigns that item (any item); a lifted
hotbar item swaps or, dropped elsewhere, comes off; RMB clears a hotbar
slot. Every item stacks to 100 (`items.STACK`). Delete (`discard`) throws
away the belly stack under the cursor (or carried), never a structure's.
Hovering a slot shows the item's full name. LMB on a structure that
keeps items (`Def.store`: sap cache, germinator, arsthraxia, digger)
opens its panel (`Mode.structure`, `hud/structure.zig`): its slots beside
the belly's, lifted/put down between them the same way (into it only what
it `wants`), Shift+LMB moves a stack across; a germinator's panel also
picks what it weaves, any weave (`recipes`/`chosen`/`choose` hooks). Closes out of reach.
Tab belly (weave), T research, F3 debug, Esc closes a panel else
pauses (pause rows are clicked or keyed: Q = save and quit, O = options,
G = saved gardens), F5 save (the garden being played), F9 load (its last
save), F11 fullscreen. Options panel: LMB turns a setting, RMB turns it
back, Esc/BACK returns to the pause menu. Saved gardens panel (pause menu
only, `hud/gardens.zig`, `Mode.gardens`): A FRESH GARDEN then every save,
newest first; wheel or drag its stem to scroll (`GARDENS_SHOWN` rows), LMB
chooses, SAVE (twice to save over one), LOAD, BACK/Esc.
Free cam: click to look, WASD fly (Shift fast), Space/Ctrl+Space rise/sink,
Q/E roll, wheel dolly; eases back in 0.3 s.

## Performance
- Target 8 ms (120 FPS), RTX 3060-class, validation on; 30 Hz fixed sim
  tick (currently 60 Hz, `play.TICK`); chunks 64×64 (currently 32×32),
  < 2 ms gen+upload; < 200 draw calls at stress.
- Measured release (4060 Ti, 1600×900, no vsync): demo ~3.0 ms, stress
  ~2.5 ms. Streaming meshes at most `MESH_MS` (3 ms) of chunks a frame.
- **Computation-heavy work goes on the GPU**: dense or per-element visual
  work (grass, scatter, particles, procedural detail, deformation, animation
  fields) is generated in shaders (instancing, vertex/fragment fields,
  compute), never built on the CPU per frame or per chunk. The CPU keeps
  state and sim and sends small records (a tile's corners, a mote's state,
  four control points).
- Level of detail: every plant and library mesh is built at `meshgen.LODS`
  (3) levels by `Builder.lod` inside the primitives (each level keeps every
  other ring/row and half the sides), so new meshes get it free. Picked by
  eye distance (`lodAt`, `LOD_AT` 36/70). Plant slots (species, variant,
  lod); part slots `meshlib.slot(id, lod)`.
- Culling: chunks (`CHUNK_RADIUS`), plants and parts are culled to the view
  frustum (`m.Frustum`; `Parts.look` sets the frame's eye and view).

## Layers (import only downward)
```
core      math, color, rng, noise, registry
platform  input, display (fullscreen)
gfx       Vulkan ctx, swapchain, buffers, pipelines, meshgen, meshlib
world     chunks (tile SoA + occupancy), generation, streaming
sim       items, species, plants (footprints, floaters), ecology tick
game      player, actions, structures, research, craft, sky, hud, view, play, save
render    renderer + passes, post (bloom), terrain meshing, camera
ui        SDF draw batch, font
main      wiring, frame loop, save/load/fullscreen requests
```

## Registries
One module per thing; enum via `std.meta.DeclEnum`, dispatch via
`switch (id) { inline else => |k| reg.module(k).hook(...) }`, hooks optional
(`reg.has`). Adding a thing = one file + one line. Never `switch` over
registry kinds outside the registry file; add a hook.

| Domain | Entry | Hooks |
|---|---|---|
| species | `sim/species.zig` | `def` (genome drives the grown mesh) |
| meshes | `gfx/meshlib.zig` | `build(b)` (order = draw order: translucent after what they cover) |
| structures | `game/structures.zig` | `def`, `State`, `tick`, `link`, `wants`, `output`, `release`, `configure`, `recipes`, `chosen`, `choose`, `emit`, `describe`, `ground`, `field`, `hold`, `icon` |
| research | `game/progression.zig` | `def` (`.branch` for big steps), `apply`, `unlocks`, `completed`, `veil`, `reveals` |
| seed icons | `game/seeds.zig` | `item`, `icon` |
| hud panels | `game/hud.zig` | `draw`, `visible` (draw order = declaration order) |
| render passes | `render/renderer.zig` | `desc` (`.target`: shadow/world/screen), `Frame`, `initFrame`/`deinitFrame`, `prepare`, `record` (plants_shadow, parts_shadow, sky, terrain, detail, plants, parts, plants_glass, parts_glass, ui) |

Items (`sim/items.zig`, ids stored by value: new items go last) and weave
recipes (`game/craft.zig`) are plain data tables.

## Conventions
- 2-space indent, `name:Type`, terse `//!`/`///` docs, LF.
- All math via `core/math.zig` (`m`): scalars, `unorm8`, tiles (`footprint`
  and `ring` iterators, `Chunk.tileOf` back from a local index), `dirs`/`dirVec`/`dirYaw`,
  vectors/matrices, `spring`, `springDamper`, `catmullRom`/`splineResample`,
  `alignY`, `Frustum`. Colours via `core/color.zig`. Never reach into
  `std.math` or hand-roll casts. No inline `std.ns.Name`: alias at file top.
- **Never hand-roll linear algebra**: `m.inverseRigid`, `m.inverseAffine`,
  `m.inverse` only as fallback; add missing methods with a test. A singular
  matrix is a bug (`@panic` in debug).
- **Every flower has stamens** (`meshgen.stamens`: grown filaments, two-lobed
  pollen anthers, `.leaf` so they fold and open with the petals; icons
  `Icon.stamens`). Closed buds hide theirs.
- **Geometry watertight and seamless**: shared rings (parallel transport),
  capped cones/lofts, shared-vertex sheets; deform only with smooth position
  fields so shared vertices move alike.
- **Grown vines are Catmull-Rom splines** via `growthPath()`/`grow()` (the
  root never moves), never a straight line or simple arc, and taper to a
  point at both ends (no hard cuts).
- meshgen primitives: `tubeR`/`tubeC`, `vine`, `braid`/`braidTurned`, `bundle`,
  `loft`, `patch`, `lamina`, `blade`/`bladeAlong`, `petal`, `stamens`, `leavesAlong`, `bands`,
  `ellipsoid`, `cone`. Shared kits: `structure_kit`, `wolf_kit` (`leaf`,
  `digit`, `claw`), `sculpt_kit` (SDF forms meshed and skinned), `mineral_kit`.
- **Leaves and petals have a body** (`meshgen.lamina`): a thin closed shell
  (`LAMINA_THICK` of the broadest half-width) rounded over at the edges, a
  small bevel; leaves (blades, fur leaves) fold toward a pale midrib vein
  raised in the fold, fading to the tip. Petals have no vein.
- Liquid essence (part `.essence`, a germinator's): solid, its colour the
  instance tint (sRGB), tu.x the way it flows (streaks), < 0 still.
- Translucent sap: part `.bloom` with instance `fade < 1` (fresnel, hue from
  vertex colour, `tint` shifts it); `.ear` inner face and `.resin` likewise.
- See-through is two passes: `plants`/`parts` keep only fragments with
  alpha ≥ 0.996 (writing depth); `plants_glass`/`parts_glass` (the same
  instances, shaders built with `-DGLASS`, build.zig `variants`) blend the
  rest over every solid surface, testing depth but writing none. A new
  see-through part role goes in `vertex.seeThrough`.
- `WorldPush` is 192 bytes (limit checked at pipeline creation).
- UI: organic, animated, no boxes; SDFs in `shaders/ui.frag`.
- **Never hard-code strings**: every player-facing string (messages, HUD
  labels, names/descriptions of items, plants, research, structures, tiles,
  the window title) lives in `parasymi.cfg`, read once at startup by
  `game/text.zig` (`txt.load` in main) and never again. Add a field to
  `txt.Strings` and a line to the cfg; show it via `txt.s.*`/`txt.item(i)`.
  Templates are runtime: `{0}`, `{1:.1}` (`core/text.zig`), passed to
  `Progression.say` / `Draw.print`; lists are `a | b` (`txt.nth`). The test
  build embeds the cfg and fails on a missing or unknown key. Not text:
  file paths/magic, shader names, CLI flags, log/panic messages, reflection.
- **Never hard-code inputs**: no key or mouse button is named in code. Every
  binding lives in `controls.cfg` (`[bind] action = name | name`, GLFW key
  names, `mouse_left`…), read once at startup by `game/controls.zig`
  (`controls.load` in main). Game code asks about an `ctl.Action`
  (`ctl.down`/`ctl.pressed(in, .harvest)`), never `glfw.Key`/`Button`;
  `platform/input.zig` only polls and answers for a `Bind`. New input = an
  `Action` tag + a cfg line (the test fails on an unbound action); modifiers
  are actions too (`alt`, `take`, `run`). Headless tests `ctl.fill` the
  embedded cfg and `ctl.hold` actions. The mouse wheel/cursor are axes, not
  bindings. Text never names a key either: write `{@action}` in
  `parasymi.cfg` (`FEED ({@harvest})`); `txt.load` (after `controls.load`)
  replaces it once with the bound key's `[key]`/`[mouse]` name (else its
  binding name in capitals), so labels follow rebinding.
- Edits: write to files, pass files to scripts; no inline heredocs.

## Zig 0.16 notes
`std.Io` replaces old I/O (pass an `Io` like an allocator). "Juicy Main":
injected params, no global env/args. `@Type` removed (`@Pointer`,
`@ErrorUnion`, explicit `error{...}`). `ArrayList{}` → `.empty`;
`ArenaAllocator` is lock-free. Build: `root_module` + `Module`; deps in `zig-pkg/`.

## Code design
- Tagged unions for exclusive states (`Game.mode`, `Camera.view`,
  `Display.mode`, `Occ.get()`); explicit error sets in public APIs (folded
  via `ctx.fold`); distinct ID types (`PlantId`, `StructId`, `MeshSlot`, `Occ`).
- `comptime T: type` over `anytype`; exhaustive `switch`; explicit
  allocators; `defer deinit()` at once, `errdefer` on init paths; arenas
  for batch work; `std.testing.allocator` in tests; SoA for hot loops;
  `try` by default, translate errors at module boundaries.
- GPU buffers retired mid-frame wait in `Renderer.pending` until every frame
  in flight is done.

## Design
- No global resources: items live in the belly, structures or plants.
  Every plant is player-seeded and grows before use. Research is the
  Factorio-lab model (structures consume ingredients unit by unit).
  Plants never set seed: only a germinator weaves seeds (hand-weaving
  makes bulbs only, `craft.by_hand`). The germinator is the bootstrap,
  woven from fibre, grit and starlight, and the hub of automation: it
  weaves every recipe, seeds and bulbs (`craft.all`), and lets only what
  it wove go (`craft.woven`); always open: lumenroot/thornleech
  seeds, conduits, sap caches, germinator; other species research-gated
  (vesper by Seed Splicing: essence + convergence essence + fibre).
  Uprooting a sown plant always gives its seed back (it stays put while
  the belly is full); a confluence gives nothing.
  Plants and structures share occupancy; footprints 1×1, 2×2 or floating.
- Structures: conduit (pulls from behind, pushes forward; grows a side root
  to a plant beside/behind it and harvests it once the root arrives), sap
  cache, germinator, arsthraxia, root-digger (1×1 on soil/moss, digs an
  adjacent node 1 item/4 s into an 8-item buffer, feeds neighbours, idles
  with no node; 3 fibre + 2 grit + 1 ley shard; "Deep Rooting"). Put down,
  they grow (`Def.grow`: germinator 6 s, arsthraxia 8, sap cache and
  digger 4, conduit 1.5) and do no work until grown. `Def.carrier` marks
  item carriers (conduit): they face a way, chain, and are pulled through.
- Confluence (`game/convergence.zig`): a mature symbiote and parasite within
  2 tiles (or joined by a conduit chain) root a 2×2 confluence beside them
  unless one already holds them. Never sown; grows 1.5× the slower parent
  (`span`) in 4 stages; yields convergence essence;
  mature, halves parasite drain within 3 tiles. "Convergence Theory" only
  reveals its yield.
- Celestial bloom (`species/bloom.zig`, `ecology.Radiance`): sown, floating
  (hover 3.2), yields nothing; radiates a 3.5-tile field. Blooms within 10
  tiles link into networks; a network radiates when it holds a mature bloom
  (then all its blooms do), so uprooting a linking bloom cuts off those
  beyond it. Plants with `needs_radiance` (vesper, for now) halt and
  wither (0.06 HP/s) outside every field. Worked out per tick from blooms
  only (pairwise links, then each radiating bloom's tiles). Hover panel
  shows RADIATING/DARK + links, DRAWING RADIANCE/WITHERING. Seed: 3
  starlight + 1 ley shard + 2 essence.
- Halo (`structures/polyp.zig`, `halo.zig` shared, `diamond.zig`): a
  polyp (1×1, grows 6 s; 4 fibre + 3 essence + 2 starlight + 2 ley shard)
  checks each tick for grown blooms (HP > 0.5) on the four
  points 5 tiles out E/S/W/N. Then, once ever, over 5 s: the blooms spiral
  in to where their cross of beams meets, the ring's heart at bloom hover
  (share ∝ e^(4k), 1.25 turns) and fold to buds, all on the GPU
  (common.glsl `haloSpiral`; the CPU sends only `[centre, k]`, instance `h`
  / `vertex.NO_HALO`, beams their held ends in `e.z`), while the diamond
  (1.6× its mesh) gathers there from its shards and projects the halo:
  needle rays of split light (`halo_projection`, part 12) running level
  out to a ring through the points (`halo_ring`, part 11: spectrum across
  its width, red inner edge as an ice halo, beam-like swells and motes
  running round). As they meet they are consumed, a flash spreads
  (`halo_flash`, part 9) and a DIAMOND structure (floating there,
  `Def.floating`/`hover`/`bare`) is put down; the polyp stays as it is. Ring field: radius 5 while
  forming; diamond field: radius 7. Points without a grown bloom dim their
  arcs to 0.3. A diamond discovers `.diamond`, opening CELESTIAL
  DEFRAGMENTATION, which lets diamonds be woven and put over
  any dry tile (they gather as they grow, then flash). The diamond is the
  world event's future launch point. Demo: west of the garden, the fourth
  bloom finishes ~20 s in.
- The gardener's folder (`game/home.zig`): `%LOCALAPPDATA%\Parasymi`
  holds `parasymi.cfg`, `controls.cfg`, `options.cfg` and `saves/`, all
  made on startup when missing (`home.open` first in main; `home.dir()`
  for every file); no cfg ever lives beside the game. The two stock cfgs
  are tracked in `src/cfg/`, embedded (`@embedFile`) and written
  with a `# stock <hash>` first line: an untouched copy is replaced when
  the repo's changes, an edited one is kept and read over the built-in
  (what it lacks falls back). So `src/cfg/` edits reach the game unless the
  AppData copy was hand-edited. Old `options.cfg`/`parasymi.sav` beside
  the game are copied in once.
- Save (`game/save.zig`, `saves/<name>.sav`): the world regenerates from the
  seed; only the gardener's changes are stored. Written to a `.tmp` then
  renamed over. `Game.slot` is the garden being played (F5/quit save into
  it, a fresh `garden N` if none); `Request` carries saves/loads/listing to
  main. Autosave (`autosave.sav`) every `Options.autosave` minutes of play
  (default 5, options panel: never..60). Bump `VERSION` when a stored
  layout changes (the fingerprint checks sizes only).

## Visual (current)
- Motion and wind: one garden-wide wind (`gardenWind`/`bendIn`,
  common.glsl), slow gusts rolling across as a wave. Everything grown bends
  from its root in it (h², tips lagging), per-thing `sway`; leaves breathe
  and lift a little; only parasites writhe.
- Terrain (`render/terrain_mesh.zig`): smooth, no walls; each tile a fan of
  four triangles, centre at the tile's height, corners shared (height,
  colour, ley averaged), smooth normals; land dips under water at the shore.
  Detail grown on the GPU (detail pass, `detail.vert`) from one `DetailTile`
  per tile: grass blades on all but water/soil (tile-coloured, wind-swayed),
  clods and stones on soil; within `DETAIL_R` (28 tiles). Ley lines carry a
  faint drifting plexus; ley sight glows smoothly across tiles. info.z = 255
  marks the top surface. Fog closes in before the edge; paw contact shadows.
- Plants: 4 variants per species (by tile). Material (plant.frag) is the
  wolf's vocabulary: muted skin, fibre sheen, old growth densifying to root
  brown, colour carried by sap through thin/young tissue (`v_young`), no
  self-glow (rim at night), see-through petals. Plants scale up as they
  grow; parasites open their closed crowns. Holding a seed shows a ghost of
  the grown plant (green fits, red not). Forms (`species.Form`: herb 0,
  coil 1, drift 2, confluence 3, radiant 4): symbiotes (`herb`) flare into
  roots, one vase leaf envelope (`leaf_from` for tree crowns), calyx and two
  whorls of real petals; vines grow leaves along them. Offshoots
  (`meshgen.offshoot`, genome `shoots` = per-variant count range): side
  stems off the main stem ending in a closed bud or a small bloom (looks
  only); colour alpha = 1 - how far out along one, and plant.vert folds
  them in against the stem until growth passes them. Parasites (`coil`):
  alien not hostile, pale pearl/lilac with thin-film sap: twisted 3-strand
  stalk on a bulbous foot, bladders, fronds curling around a bulb.
  Floaters (`drift`): a comb-jelly lantern (`meshgen.lantern`: clear sap,
  8 twisting comb rows in split-light colours, a golden spore inside;
  plant.frag shades it apart by tu.x 0.5, bright iridescent film, approved
  as is), catcher dish, hair-thin filaments waving in two lengths (a wave
  runs down them in plant.vert), slow bob over a ground shadow. Confluence: 8 growth keys of one vertex layout
  blended in plant.vert (binding 2), braid strands running on into red
  vines, translucent violet petals, sway ×1.5.
- Celestial bloom (`radiant`): a flower whose petals float free, gathered
  by its core: a luminous core with a crown of stamens, three whorls of
  narrow cupped petals (inner upright .. outer open) floating apart from it,
  each held by a thread of light, motes spiralling in, tilted halo. Pearl
  with an iridescent film (plant.frag `filmHue` by view angle). Fragments
  carry assembly order (tu.x), `meshgen.Ring` (tu.y; a thread adds its
  distance from its petal) and bearing (colour alpha): plant.vert spirals
  each in folded as a bud and opens it as growth passes it; grown, whorls
  turn slowly, alternating, and drift apart and back; it bobs and never
  bends. The garden's only true glow. Beams
  between linked blooms (`bloom_thread`, part `.thread`): soft rays, a
  camera-facing spindle bent in part.vert curve mode; no core, a faint haze
  with five soft streaks swelling from sender to receiver, iridescent
  (rainbow end to end, rolling along), tiny motes drifting inside shifting
  hue (seeded by the instance phase); dim when the network is dark; sent
  from the more grown bloom as it finishes. Demo: a chain of five blooms
  arced around the garden, clear of parasites (they drain floaters).
- Structures (`structure_kit`) speak the plants' language: woven root mats,
  leafy vines, real petals, pods of resin sap (`Def.sap`, no own light).
  Germinator (`Def.still`: no breath, so its emitted pieces stay on it;
  `Def.preview` whole): a small tree, woven trunk on a root mat, five
  braided boughs rising round a core of thin resin sap held in a calyx and
  arching over it to hold flower cups (stamens) above it; a sapwood
  spindle runs up through the core. A weave is seen through by its
  progress alone: the cups hold what it stocks (pools of `.essence`, kept
  level), tip and pour it (curve-placed streams, colour in `q.yzw`); the
  core spins it into a whirl round the spindle (one arm per essence,
  turned by the area under the spin stage, whole turns per weave) and
  threads wind a seed of them on the spindle (kernel in the output's
  colour, a winding per essence). Research bloom: woven
  stalk, violet flower, banded resin orb (forms last). Sap cache: clear pod
  in a vine basket, contents hanging inside. Conduit (`Def.bare`, its own
  `emit`): per tile a root digs up out of the soil at each edge it is fed
  from (`link` hook: `feeds`; `conduit`/`conduit_left`/`conduit_right`),
  arches (rising long, diving short) and digs back in at its front, so
  chains join underground in any turn; a sapwood core (part `.core`) in an
  over-under weave of strands, branchlets, leaves in twos/threes swept
  forward, soil heaped (a ridge pushed ahead where it dives) with rootlets.
  Carried essence swells and tints the core as it passes (part.vert,
  `Look.carry`/`carry_col`), amber pulses run the way it carries; side
  roots (`conduit_tap`) are smaller woven arches. Standing structures sway (`Def.sway`; conduits don't, so
  chains stay joined; hung parts follow via `Look.drop`), breathe at a fixed
  tempo, and grow in (shoot up, fill out, leaves unfold).
- Resource nodes (`mineral_kit`, flat facets): ley shards a violet crystal
  cluster; grit faceted stones with quartz chips; fibre a swaying clump of
  arching stalks.
- Sap everywhere is alive: bubbles rise inside, beads slide down its surface
  (`sapBubbles`/`sapDroplets`, mesh space).
- Sky: gradient dome, sun/moon, stars; star motes (faceted core, ring,
  needle rays) turn, twinkle, hover and trail echoes while falling. Low
  pitch widens the view toward the horizon.
- part.vert placement by `PartInstance.e.x`: 0 matrix, 1 curve (beams;
  `e.y` reach), 2 star mote, 3 skinned (`e.y` first bone).
- Lighting (`render/light.zig`): the key light (sun/moon) casts shadows
  through a cascaded shadow map (3 cascades, 1536², `fit` snaps them to
  texels so they hold still), drawn in one multiview pass per caster
  (`gl_ViewIndex`, `project()`), casters at their coarsest LOD
  (`light.caster`); shader variants with SHADOW leave out what is light
  itself (blooms, motes, beams, halo, ghosts, lanterns). Terrain receives
  but does not cast. Points of light (`Parts.light`: blooms, motes, ley
  shards, diamond and flash; at most `MAX_LIGHTS` 32, ranked in
  view.zig) and the cascades travel in `Lighting`, reached by address
  (`WorldPush.light`); common.glsl `keyShadow`, `pointLight`, `shadeLit`.
  Culling keeps what may cast into view (`Parts.sees`). Cost ~+3 ms on
  this machine's 35 ms demo frame.
- Post-processing (`render/post.zig`): world passes draw into an HDR image;
  brighter-than-white light blooms (5-level 13-tap down chain with soft-knee
  threshold and anti-firefly weighting, tent filter back up); composite
  adds the glow (0.7), rolls highlights off above 0.8 and a faint vignette;
  `Desc.screen` passes (UI) draw on top. ~0.1 ms.
- Anti-aliasing (`post.Antialias`: off, fxaa, msaa2/4/8; default msaa4):
  MSAA draws the world into multisampled colour + depth resolved (average)
  into the HDR image; plant/part passes (`Desc.per_sample`) shade per
  sample, since their solid/glass split is per fragment. FXAA (`fxaa.frag`,
  FXAA 3.11 quality) filters the composite (luma in alpha) before the UI.
  `Renderer.antialias`/`setVsync` switch at runtime (remake pipelines /
  swapchain). Release: off 4.1, fxaa 3.9, msaa4 4.35, msaa8 4.9 ms (demo).
- Options (`game/options.zig`, `hud/options.zig`): AA, vsync, fullscreen,
  autosave, stored in `options.cfg` (in the gardener's folder, written when one
  changes, kept across save loads); main applies `Game.opts` when it
  differs from what is in effect.
- UI: wobbling membranes, seed-pod slots, tendril bars, soft glow, stems
  (`Draw.limb`) and leaves/buds (`Draw.leaf`), seeds (`Draw.grain`) and
  gems (`Draw.gem`); 150 ms anim.
- Item icons (`game/icon.zig`): a structure's bulb is a split seed with a
  sprout or two showing what it does (its `icon` hook, drawn with the
  `Icon` kit: `coat`, `stem` along a Bézier, `leaf`, `bud`, `glow`, `gem`,
  `kernel`; sprouts sway). A plant's seed likewise, from its module in
  `game/seeds.zig` (`seeds/<species>.zig`: `item` + `icon`; the test fails
  on a sown species without one). Any other item is its colour fill with
  its short name, for now.
- Research panel (T, `hud/research.zig`) is a sapling in soil, laid out
  from the prerequisites alone, so it never needs placing or adjusting:
  - Adding research: one file in `research/` + one line in `techs`. Set
    `.branch = true` on a big step (new structures, species, an event);
    anything else is a leaf. Nothing else to do: no coordinates, no sizes.
  - Host: a node grows on the nearest branch up its *first* prerequisite
    chain, else on the trunk (so list the prerequisite it belongs to first).
  - Along a host, children sit one slot apart by depth (longest prereq
    chain; a `needs` discovery counts 1), then declaration order; leaves and
    branches each alternate sides. Stems are one slot longer than their
    children (branches ≥ `BRANCH_MIN`) and bend toward the light.
  - The fully grown, still tree is fitted to the panel (`fit`, slot ≤
    `max_slot` px), so nothing moves: the sapling starts small at the soil
    and fills the panel as research is done.
  - Known: grown leaf / branch with a violet bloom at its tip. Open: gold
    bud (glows; while studied a leaf unfurls and a branch shoot extends with
    progress). Locked: dim dormant bud where its host has grown, else
    hidden. The trunk reaches `TRUNK_LEAD` past its highest open/known
    node (eased, `play.Game.sapling`) and thickens with √(known).
  - Wind sways stems from the base (children follow), leaves flutter.
    Hovering a node (`Game.pointed`) shows its card (cost, progress, or
    what it is DORMANT on); else the studied one. Click selects.
  - The test asserts hosts come before what grows on them and no two nodes
    crowd (> 0.5 slot); if it fails after adding research, fix the layout
    rules there, never hand-place a node.
- Wolf (`game/player.zig` rig; muted greens/browns, amber only on belly,
  eyes, inner ears, beans, pectorals and rear):
  - One skin: `wolf_body` is sculpted (`sculpt_kit`: SDF ellipsoids, round
    cones, round boxes per bone, smooth union/carve, `ink` paints colour
    only) around the bind pose of `wolf_skeleton` (27 bones, `fk(Pose)`),
    meshed once with surface nets (`CELL` 5 mm, doubled per LOD), each
    vertex weighted to the bones of the forms nearest it (only across
    joints that are joined). GPU skinning: `vertex.Skin` beside the mesh
    buffer (binding 2), bones per frame via `Parts.pose`/`emitSkinned`
    (part.vert mode 3, buffer device address in `WorldPush.bones`).
    New wolf meshes are built in bind space and skinned; never rigid parts.
  - Over the hide: vines cast onto it from bone axes (`wind`/`line`, so
    they never jump across), fur leaves (`wolf_kit.leaf`) as hair over the
    crown with a forelock and nape mane, along the cheekbones, shoulder
    tufts, tail rings and tip; digits/claws (`wolf_kit.digit`); eyes set in
    carved sockets under the brow.
  - Head: short muzzle rising to an upturned nose (bean), lower jaw (own
    bone) tucked up under it, ears (`wolf_ears`, skinned to ear bones).
  - Resin sap (`.resin`, sprung `give`): pectorals (`wolf_pec`) on the
    chest, the rear (`wolf_rump`) on the pelvis, its lower edge partly
    following the thighs.
  - Belly (`wolf_belly`): convex egg sac on the gut; filling scales and
    drops the `gut` bone (lower half) and `gut_top` (upper half: as wide,
    its top kept where it hangs), so the swollen sac never folds (tested);
    tu.x = gut share of each vertex; the belly button pops out; up to 5
    lumps inside (in the gut bone's frame). `vertex.Skin` carries each
    weight's slope (`gx/gy/gz`): part.vert bends skinned normals by the
    true Jacobian, not the blended bones alone.
  - Motion: feet planted in the world, swung on arcs when the gait's phase
    (or, standing, a foot left behind) says; digitigrade leg IK
    (`solveLeg`: thigh+metatarsal as one link); pelvis bobs at footfalls,
    sways, turns and rolls, chest counter-turns; lean, bank, arms, head,
    ears and tail on springs (`Swing`); head steadied against the bob,
    idle look-around, ear flicks; breath and panting quicken with effort.
- "Celestial / beyond comprehension" is the next phase target.

## Rules
- **Scope guard**: no audio, multiplayer, PBR/IBL, further post-processing
  (bloom was asked for) or Linux/macOS without explicit direction; flag and
  stop if a task drifts there.
- **Decision authority**: a layer boundary or build/run interface change →
  stop and ask; otherwise decide and note with `// decision:`.
- **Plant rule**: everything grown has a proper growing animation, is moved
  by the garden's sway and matches the current plant quality, unless the
  user says otherwise.
- **Cohesion rule**: each visual overhaul sets the bar for everything of its
  kind; the whole wolf and all plants/structures are kept up with it; new
  grown things follow the current look, motion and growth via the shared
  kits, never older primitives.
- **Visual authority**: the user calls the shots on art direction, with NO
  compromises, period. Their word on look, motion, proportions,
  silhouette, material, technique (e.g. "on the GPU") and "does this read
  as X" is final. Build exactly what they describe: never substitute a
  cheaper, simpler or "equivalent" approach, never water it down, never
  ship a stand-in and call it done. If it can't be done as described,
  research another way (techniques, papers, docs, prior art) that delivers
  exactly what they described, and build that; never give up on it or
  fall back to less. If it's ambiguous, ask. "Off", "weak", "generic", "too X" is
  the acceptance criterion: implement their fix.
- **Finish line**: work until the phase's criteria are met; take the next
  step instead of "next I would…"; stop only for a blocking decision or
  phase completion.
- **Working**: commit and push `devel` after every verified change (builds,
  tests pass) without asking; never commit `parasymi.sav`; report broken
  work, don't commit it. Reports: a short list of changes, a real deviation
  or blocker as one bullet. Verify visual work in the running game (scratch
  copies may move the camera) and say what was not checked.

## Current state
Done: engine, terrain, streaming, plants + 7 species, ecology, structures,
footprints/floaters, research (10 nodes), hand weaving, save/load, pause,
fullscreen, root-digger, adjustable/free camera, sky, wolf anatomy and
planes/fur passes, confluence, celestial bloom + radiance, GPU detail,
LOD + culling, bloom post-processing, research sapling panel, halo + diamond structure + Celestial Defragmentation,
anti-aliasing (MSAA/FXAA) + options panel, the wolf as one sculpted skinned
mesh with procedural locomotion (planted feet, leg IK, springs), saved gardens
menu + autosave, files in `%LOCALAPPDATA%\Parasymi`.
**Next (vertical slice):**
1. 2–3 more species per lineage
2. Research tree to ~12 nodes
3. First world event (something that *happens*, not just a research unlock)
4. One "wow" visual moment (sky shift at convergence)
Target: a stranger plays 2 hours and says "I want to see what happens next."
