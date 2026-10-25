# Visual (current)

How everything looks and moves now. The user's art direction is final (see
CLAUDE.md, Rules); each overhaul sets the bar for everything of its kind.
Kit-level detail: [kits/README.md](kits/README.md).

## Motion and wind
One garden-wide wind (`gardenWind`/`bendIn`, common.glsl), slow gusts
rolling across as a wave. Everything grown bends from its root in it (h²,
tips lagging), per-thing `sway`; leaves breathe and lift a little; only
parasites writhe.

## Terrain (`render/terrain_mesh.zig`)
Smooth, no walls; each tile a fan of four triangles, centre at the tile's
height, corners shared (height, colour, ley averaged), smooth normals; no
water (basins are level lowland). Detail grown on the GPU (detail pass,
`detail.vert`) from one `DetailTile` per tile: grass blades on all but soil
(tile-coloured, wind-swayed), clods and stones on soil; within `DETAIL_R`
(28 tiles). Ley lines carry a faint drifting plexus; ley sight glows
smoothly across tiles. info.z = 255 marks the top surface. Fog closes in
before the edge; paw contact shadows.

## Plants
- 4 variants per species (by tile). Material (plant.frag) is the wolf's
  vocabulary: muted skin, fibre sheen, old growth densifying to root brown,
  colour carried by sap through thin/young tissue (`v_young`), no self-glow
  (rim at night), see-through petals. Plants scale up as they grow;
  parasites open their closed crowns. Holding a seed shows a ghost of the
  grown plant (green fits, red not).
- Forms (`species.Form`: herb 0, coil 1, drift 2, confluence 3, radiant 4,
  star 5; common.glsl `FORMS_FREE` = the radiant ones).
- Symbiotes (`herb`, `structure_kit.plant`): the symbiotic structures'
  body. A braided stem (4 strands round a darker core, 6 on a trunk
  thicker than `THICK`, wound at one `PITCH` per radius so thin and thick
  wind alike) flaring into a mat of 5 braided roots that arch down to hug
  the ground and sink in; a rosette of broad leaves round the foot
  (genome `rosette`), leafy vines twining up the stem, tapering at both
  ends (`vines`), one vase leaf envelope up it (`leaf_from` for tree
  crowns), braided offshoots (`meshgen.shootPath`, genome `shoots` =
  per-variant count range) ending in a closed bud or a small bloom (looks
  only; colour alpha = 1 - how far out along one, plant.vert folds them
  in against the stem until growth passes them). Each bloom opens out of
  a bead of the lineage's amber resin (`meshgen.Calyx.resin`, part
  `.resin`) held in a cup of five sepals: two whorls of real petals and
  stamens on its crown. The bead shades as the structures' resin
  (surface.glsl `resinSurface`, tu.y dense base → thin crown), dimmed by
  health. Their leaves and sepals are not muted: plant.frag shades them
  in their own green (`green`, light through them `GREEN_THROUGH` of it),
  as the structures' leaves. Lumenroot: the palette's leaf green, a vine
  green richer than the palette's (the stem is still muted), cyan bloom.
- Parasites (`coil`, `parasite_kit.plant`): alien not hostile, exactly
  symmetric and dead upright (variants differ in proportion only): a
  lattice cage stalk on a bulbous foot, sacs hanging on its core inside, a
  bulb at its neck, a candelabrum of 5 fronds each ending in a pod crowned
  by 5 frondlets; plant.vert parts the cage from the foot up (tu.y) and
  opens the crown.
- Floaters (`drift`): a comb-jelly lantern (`meshgen.lantern`: clear sap, 8
  twisting comb rows in split-light colours, a golden spore inside;
  plant.frag shades it apart by tu.x 0.5, bright iridescent film, approved
  as is), catcher dish, hair-thin filaments waving in two lengths (a wave
  runs down them in plant.vert), slow bob over a ground shadow.
- Confluence: 8 growth keys of one vertex layout blended in plant.vert
  (binding 2), braid strands running on into red vines, translucent violet
  petals, sway ×1.5.
- Vesper (`star`, `radiant_kit.star`): an evening star come down, hanging
  `stem_h` (0.62) over its tile, nothing under it: a dusk-violet core (gold
  nucleus, 5 stamens), an upright cup of 5 pale-gold petals, a star of 5
  long narrow violet rays lying open, 5 dusky leaves floating beneath
  (`GLOW` 0.3: living tissue, little light, they cast shadows), motes; no
  halo. It gathers as the bloom does but falls in from the sky (plant.vert
  `FORMS_FALLING`, `FALL_*`): the heart first, straight down, then each
  piece spiralling down on its thread. Keeps more of its own hue under the
  film (plant.frag `FORMS_OWN_HUE`). Withering out of radiance any radiant
  plant comes loose (`LOOSE_*`: pieces sink, drift out, hang open) and its
  light dims with health.
- Celestial bloom (`radiant`): a flower whose petals float free, gathered
  by its core: a luminous core with a crown of stamens, three whorls of
  narrow cupped petals (inner upright .. outer open) floating apart from
  it, each held by a thread of light, motes spiralling in, tilted halo.
  Pearl with an iridescent film (plant.frag `filmHue` by view angle).
  Fragments carry assembly order (tu.x), `radiant_kit.Ring` (tu.y; a thread
  adds its distance from its petal) and bearing (colour alpha): plant.vert
  spirals each in folded as a bud and opens it as growth passes it; grown,
  whorls turn slowly, alternating, and drift apart and back; it bobs and
  never bends. With the vesper, the garden's only true glow.
- Beams between linked blooms (`bloom_thread`, part `.thread`): soft rays,
  a camera-facing spindle bent in part.vert curve mode; no core, a faint
  haze with five soft streaks swelling from sender to receiver, iridescent
  (rainbow end to end, rolling along), tiny motes drifting inside shifting
  hue (seeded by the instance phase); dim when the network is dark; sent
  from the more grown bloom as it finishes.

## Structures
`structure_kit` structures speak the plants' language: woven root mats,
leafy vines, real petals, pods of resin sap (`Def.sap`, no own light).
Standing structures sway (`Def.sway`; conduits don't, so chains stay
joined; hung parts follow via `Look.drop`), breathe at a fixed tempo, and
grow in along their growth splines (trunk first, branches after, leaves
unfolding as the front passes, emitted pieces last; [growth.md](growth.md)).
- Germinator (`Def.still`: no breath, so its emitted pieces stay on it;
  `Def.preview` whole): a small tree, woven trunk on a root mat, five
  braided boughs rising round a core of thin resin sap held in a calyx and
  arching over it to hold flower cups (stamens) above it; a sapwood spindle
  runs up through the core. A weave is seen through by its progress alone:
  the cups hold what it stocks (pools of `.essence`, kept level), tip and
  pour it (curve-placed streams, colour in `q.yzw`); the core spins it into
  a whirl round the spindle (one arm per essence, turned by the area under
  the spin stage, whole turns per weave) and threads wind a seed of them on
  the spindle (kernel in the output's colour, a winding per essence).
- Arsthraxia (`Def.bare`, its own `emit`; never breathes or bobs): three
  braided stems twine up from a root mat, part into a cage round a resin
  pod threaded on a nerve and gather in a calyx under a violet flower (two
  whorls, emitted, opening and counter-turning while it studies). Each
  stem's core is a nerve (part `.nerve`, `mg.braidAround`): studying,
  violet thought climbs it (part.vert), a unit done sends a surge up
  (`flutter` = flare). Research grows on it: vines climbing the stems
  (Arsthraxia, `Study.vines`), a braided offshoot bough with a vine round
  it and its own flower per minor study.
- Sap cache: a resin gourd cupped by a calyx on a woven bole, a wicker
  basket over it (green vines one way, pale roots the other, over and
  under), a collar at its neck and a bud of sepals closing its mouth
  (`sap_cache_lid`, emitted): it opens as an item drops in (sinking to its
  stack, which swells) or rises out; contents hang inside.
- Root-digger: four braided roots break the ground (soil heaved round them)
  and twine up to grip a small resin gourd, a leaf tuft on top; its digging
  root (`digger_root`, a conduit arch whose `.core` runs home, tu.x 0 in
  the node) reaches to the node it works and withers from one gone; each
  item is prised loose (`digger_clod`s flung up about the claw), then
  swells up the core in its colour to the gourd.
- Conduit (`Def.bare`, its own `emit`): per tile a root digs up out of the
  soil at each edge it is fed from (`link` hook: `feeds`;
  `conduit`/`conduit_left`/`conduit_right`), arches (rising long, diving
  short) and digs back in at its front, so chains join underground in any
  turn; a sapwood core (part `.core`) in an over-under weave of strands,
  branchlets, leaves in twos/threes swept forward, soil heaped (a ridge
  pushed ahead where it dives) with rootlets. Carried essence swells and
  tints the core as it passes (part.vert, `Look.carry`/`carry_col`), amber
  pulses run the way it carries; side roots (`conduit_tap`) are smaller
  woven arches.
- Loomfern: a fern: fronds, croziers, a sheaf winding on its spindle from
  threads off the fronds.
- Weftstone: crystal + sparks in its bulb as it ionizes.
- Driftbraid: its look is the approved reference for convergent structures.
- Monfris: four corner weaves twining into one crowned trunk.

## Halo
While a polyp's halo forms ([design.md](design.md#halo-and-diamond-structurespolypzig-halozig-diamondzig)):
the blooms spiral in to the ring's heart at bloom hover (share ∝ e^(4k),
1.25 turns) and fold to buds, all on the GPU (common.glsl `haloSpiral`; the
CPU sends only `[centre, k]`, instance `h` / `vertex.NO_HALO`, beams their
held ends in `e.z`), while the diamond (1.6× its mesh) gathers there from
its shards and projects the halo: needle rays of split light
(`halo_projection`, part 12) running level out to a ring through the points
(`halo_ring`, part 11: spectrum across its width, red inner edge as an ice
halo, beam-like swells and motes running round). As they meet a flash
spreads (`halo_flash`, part 9).

## Resource nodes (`mineral_kit`, flat facets)
Ley shards a violet crystal cluster; grit faceted stones with quartz chips;
fibre a swaying clump of arching stalks.

## Sap
Sap everywhere is alive: bubbles rise inside, beads slide down its surface
(`sapBubbles`/`sapDroplets`, mesh space). Sap glistens, never glows softly
(`sapGlisten`, common.glsl, on every sap material): hard-edged mirrored
lights (`hardSpot`: key light with a white-hot core, points of light, a sky
window), winking skin facets, a sharp caustic through clear sap, a thin
hard edge line; its colour gathers to a narrow edge band (`SAP_EDGE_POW`).
The bloom post makes the glow round the glints.

## Sky
Gradient dome, sun/moon, stars; star motes (faceted core, ring, needle
rays) turn, twinkle, hover and trail echoes while falling. Low pitch widens
the view toward the horizon.

## Lighting (`render/light.zig`)
The key light (sun/moon) casts shadows through a cascaded shadow map (3
cascades, 1536², `fit` snaps them to texels so they hold still), drawn in
one multiview pass per caster (`gl_ViewIndex`, `project()`), casters at
their coarsest LOD (`light.caster`); shader variants with SHADOW leave out
what is light itself (blooms, motes, beams, halo, ghosts, lanterns).
Terrain receives but does not cast. Points of light (`Parts.light`: blooms,
motes, ley shards, diamond and flash; at most `MAX_LIGHTS` 32, ranked in
view.zig) and the cascades travel in `Lighting`, reached by address
(`WorldPush.light`); common.glsl `keyShadow`, `pointLight`, `shadeLit`.
Culling keeps what may cast into view (`Parts.sees`).

## Post-processing (`render/post.zig`)
World passes draw into an HDR image; brighter-than-white light blooms
(5-level 13-tap down chain with soft-knee threshold and anti-firefly
weighting, tent filter back up); composite adds the glow (0.7), rolls
highlights off above 0.8 and a faint vignette; `Desc.screen` passes (UI)
draw on top.

## Anti-aliasing (`post.Antialias`: off, fxaa, msaa2/4/8; default msaa4)
MSAA draws the world into multisampled colour + depth resolved (average)
into the HDR image; plant/part passes (`Desc.per_sample`) shade per sample,
since their solid/glass split is per fragment. FXAA (`fxaa.frag`, FXAA 3.11
quality) filters the composite (luma in alpha) before the UI.
`Renderer.antialias`/`setVsync` switch at runtime (remake pipelines /
swapchain).

## Loading screen (`game/loading.zig`, wired in main)
A living night (`Draw.night`, ui.frag) with the name, a tendril growing as
far as what is made (leaves opening as it passes), the stage, percent,
made/left. Stages: every mesh grown on a thread of its own
(`Renderer.meshProgress` / `meshesReady` uploads once through), the world
woken, its ground meshed in 25 ms slices (`World.unmeshed`); also after a
load in play. It fades off play's first frames (0.6 s).

## UI
Organic, animated, no boxes; SDFs in `shaders/ui.frag`. Wobbling membranes,
seed-pod slots, tendril bars, soft glow, stems (`Draw.limb`) and
leaves/buds (`Draw.leaf`), seeds (`Draw.grain`) and gems (`Draw.gem`);
150 ms anim.

## Item icons (`game/icon.zig`)
A structure's bulb is a split seed with a sprout or two showing what it
does (its `icon` hook, drawn with the `Icon` kit: `coat`, `stem` along a
Bézier, `leaf`, `bud`, `glow`, `gem`, `kernel`; sprouts sway). A plant's
seed likewise, from its module in `game/seeds.zig` (`seeds/<species>.zig`:
`item` + `icon`; the test fails on a sown species without one). Any other
item is its colour fill with its short name, for now.

## Wolf (`game/player.zig` rig)
Muted greens/browns, amber only on belly, eyes, inner ears, beans,
pectorals and rear. The ribcage is broad but melts into a waist only a
little narrower (`RIB_*`, `LAT_*` in `wolf_body`): no barrel rim over the
waist, front or back.
- One skin: `wolf_body` is sculpted (`sculpt_kit`: SDF ellipsoids, round
  cones, round boxes per bone, smooth union/carve, `ink` paints colour
  only) around the bind pose of `wolf_skeleton` (27 bones, `fk(Pose)`),
  meshed once with surface nets (`CELL` 5 mm, doubled per LOD), each vertex
  weighted to the bones of the forms nearest it (only across joints that
  are joined). GPU skinning: `vertex.Skin` beside the mesh buffer (binding
  2), bones per frame via `Parts.pose`/`emitSkinned` (part.vert mode 3,
  buffer device address in `WorldPush.bones`). New wolf meshes are built in
  bind space and skinned; never rigid parts.
- Over the hide: vines cast onto it from bone axes (`wind`/`line`, so they
  never jump across), fur leaves (`wolf_kit.leaf`) as hair over the crown
  with a forelock and nape mane, along the cheekbones, shoulder tufts, tail
  rings and tip; digits/claws (`wolf_kit.digit`); eyes set in carved
  sockets under the brow.
- Head: short muzzle rising to an upturned nose (bean), lower jaw (own
  bone) tucked up under it, ears (`wolf_ears`, skinned to ear bones).
- Resin sap (`.resin`, sprung `give`): pectorals (`wolf_pec`) on the chest,
  the rear (`wolf_rump`) on the pelvis, its lower edge partly following the
  thighs.
- Belly (`wolf_belly`): convex egg sac on the gut; filling scales and drops
  the `gut` bone (lower half) and `gut_top` (upper half: as wide, its top
  kept where it hangs), so the swollen sac never folds (tested); tu.x = gut
  share of each vertex; the belly button pops out; up to 5 lumps inside (in
  the gut bone's frame). `vertex.Skin` carries each weight's slope
  (`gx/gy/gz`): part.vert bends skinned normals by the true Jacobian, not
  the blended bones alone.
- Motion: feet planted in the world, swung on arcs when the gait's phase
  (or, standing, a foot left behind) says; digitigrade leg IK (`solveLeg`:
  thigh+metatarsal as one link); pelvis bobs at footfalls, sways, turns and
  rolls, chest counter-turns; lean, bank, arms, head, ears and tail on
  springs (`Swing`); head steadied against the bob, idle look-around, ear
  flicks; breath and panting quicken with effort.
