# Visual (current)

How everything looks and moves now. The user's art direction is final
(see CLAUDE.md, Rules). Each overhaul sets the bar for everything of its
kind. Kit-level detail: [kits/README.md](kits/README.md).

## Motion and wind
There is one wind for the whole garden (`gardenWind`/`bendIn`,
common.glsl): slow gusts rolling across it as a wave.

- Everything grown bends from its root in it. The bend grows with the
  square of the height (h²), so tips swing most and lag behind.
- Each thing has its own `sway`.
- Leaves breathe and lift a little.
- Only parasites writhe.

## Terrain (`render/terrain_mesh.zig`)
The ground is smooth, with no walls and no water (basins are level
lowland).

- **Shape:** each tile is a fan of four triangles, its centre at the
  tile's height. Corners are shared (height, colour and ley averaged), with
  smooth normals.
- **Terraces ease into each other** (`gen.eased`): a tile's height is the
  terraces within 2.5 tiles of it, the nearer counted more, so one terrace
  rolls into the next in a soft S over about four tiles (at most ~0.12 m a
  tile) instead of a one-tile ramp; the heart of a wide terrace stays level.
- **Kinds melt together** (`shaders/ground.glsl`, per pixel): each vertex
  carries how much soil, moss, stone and ley lies round it (every tile
  within 2 tiles, by a smooth falloff, `kindsAt`). The shader pushes each
  kind's border out where its own shape rises (moss in clumps, stone in
  slabs) and sharpens it, so borders wander in blobs and fray, never on
  the tile grid. Ley holds its ground firmer, so a line never breaks.
- **Surfaces:** soil in damp and dry patches with crumbly grain and pale
  pebbles; moss in heaped cushions, deep in the folds, gold on top, fuzzy;
  stone in warm and cool slabs split by dark cracks, flecked with lichen;
  ley ground grained in violet. Their bumps tip the normal; the finest
  grain fades out where a pixel spans too much.
- **Detail, grown on the GPU** (detail pass, `detail.vert`) from one
  `DetailTile` per tile, within `detailR` (28 tiles):
  - grass, as thick as the ground beneath is grassy (moss full, ley most,
    stone a little, soil none), its kinds melted exactly as the ground's
    are, so grass thins and frays across borders: up to 96 blades a tile
    in tufts of six fanning from their heart, each a curved, tapering
    blade of three bands arching along its lean, dark at the root and pale
    at the tip in the colour of the ground it rises from (moss green, ley
    violet, stone grey-green; a few straw tips), its normal leaned skyward
    so both faces catch light, wind-swayed; far off fewer and wider;
  - on soil, a clod and a pebble: rounded lumps of eight sides, heaped
    unevenly, smoothly shaded; a clod's crust paler on top.
- **Ley:** ley lines carry a faint drifting plexus (a web of thin lines);
  ley sight glows smoothly across tiles. At the unforming they seal: each
  closes from its edges in to its heart (each vertex's depth into its
  line, `terrain_mesh.lineDepth`, info.w), bare soil behind a bright
  violet seam; their nodes' shards drift off and blink out.
- `info.z = 255` marks the top surface.
- The world closes into the horizon's colour before its edge. Paws leave
  contact shadows.

## Fog (`passes/fog.zig`, `fog.frag`)
The garden stands in real air, marched on the GPU after the world at half
the screen's size and laid over it edge-aware (engine `render/volume.zig`).

- **Haze:** everywhere, thinning with height; thinner as the camera draws
  back (the old distance fog's density), so far views never drown. Far
  away it melts into the sky's colour.
- **Low air:** thin air among the plants, thickest on the ground.
- **Mist:** lies low on the ground and pools in the hollows (below the
  second terrace), torn into flat wisps drifting along the wind; denser by
  night.
- **Breathed moisture:** what the nebularbor breathes, kept on the GPU as
  a moisture field over the world (`passes/moisture.zig`, the engine's
  field): a mist lying low round its foot, torn into the same wisps, and a
  cloud gathering in a billowing band over its crown (4.5–6 over the
  ground), both drifting off on the wind, spreading and slowly drying.
  Cloud gathered heavy swells deeper, fills in between its billows and
  hangs grey, its belly darker the thicker it is (it swallows a share of
  the light it stops). Under raining cloud, grey sheets of rain haze fall
  to the ground.
- **Rain** (`passes/rain.zig`, rain.vert/.frag): drops grown on the GPU
  over a grid fixed to the world round the view, falling from the cloud's
  belly wherever the field rains, as many as the rain is heavy, leaning on
  the wind; thin pale streaks lit by the sky, each splashing a ring that
  spreads and fades where it lands. Ground the rain has soaked is darker
  and a little bluer, its grass too (terrain.frag), drying slowly.
- **Pools** (`passes/pools.zig`, pools.vert/.frag): the rain pooled in
  the dips, a surface grown on the GPU over every texel near the view at
  the water's level, sinking into the ground at a soft shore. Still and
  dark: clear in the shallows, murky where deep, mirroring the sky (more
  at a graze) and the key light's glint, stirred by the wind and ringed
  by the rain falling on it.
- **Light shafts:** the key light is looked up in its shadow map at every
  step, so what shades the ground shades the air: light falls through the
  gaps between plants and structures, and glows toward the sun (forward
  scattering, gone once the sky has shifted).
- **Glow:** the points of light (blooms, motes) light the air round them;
  the ley lines' glow rises off the ground into the mist, pulsing with
  them (read from the overhead map, the ground drawn from above).
- **Everything that glows lights the air** (a standing rule): beams,
  flashes, the halo, energy, the constellate's glowing edges and points
  each cast a soft haze into the fog round them, brighter in the mist,
  faint in clear air (`partsAir`, docs/architecture.md).
- **The constellate tendril:** a braid of fragments flowing along it like
  a stream; how the plexus web makes it, with every number, is in
  [tendril.md](tendril.md).

## Plants
### All plants
- 4 variants per species, picked by tile.
- **Leaves and petals** (`meshgen.lamina`) are finely built: 13 points
  across the face, 8 across the back, up to 13 rows, so their curves read
  smooth. Each vertex carries where across the sheet it lies (mesh
  `tu.z`, 1..3 edge to edge, 0 off a sheet), and the shaders draw their
  surface from it (surface.glsl `sheetColour`, on plants and structures
  alike):
  - a leaf: a pale midrib, lateral veins arching out toward the tip and
    fading before the edge, a fine net of veinlets between them, a
    yellower edge, a paler base; light through it is shaded by its veins;
  - a petal: fine streaks running out from its claw, a deeper throat, a
    paler edge;
  - stems and tendrils: fine ridges along them (a tube's sides carry
    how far round they lie, tu.z 4..5), darker in their grooves, fibres
    streaking lighter and darker (`stemGrain`), on all their light.
- **Material** (plant.frag) speaks the wolf's vocabulary:
  - muted skin, a sheen like fibre;
  - old growth densifies to root brown;
  - colour carried by sap through thin, young tissue (`v_young`);
  - no glow of its own (a rim light at night); see-through petals.
- Plants scale up as they grow. Parasites open their closed crowns.
- Holding a seed shows a ghost of the grown plant: green where it fits,
  red where it does not.
- **Forms** (`species.Form`): herb 0, coil 1, drift 2, confluence 3,
  radiant 4, star 5. In common.glsl, `FORMS_FREE` = the radiant ones.

### Symbiotes (`herb`, `structureKit.plant`)
These are the symbiotic structures' body.

- **Stem:** braided, 4 strands round a darker core (6 on a trunk thicker
  than `thick`). Strands wind at one `pitch` per radius, so thin and thick
  stems wind alike.
- **Roots:** the stem flares into a mat of 5 braided roots that arch down,
  hug the ground and sink in.
- **Leaves:** natural and uneven, never clones (`meshgen.leaf`): each
  on its own stalk, its own size, droop, twist and edge ripple, toothed,
  its tip curling. A low rosette of broad old leaves sprawls round the foot
  (genome `rosette`), yellower with age; many leaves climb the stem,
  biggest low down; young ones stand folded round the crown. Every
  structure's and convergent leaf is grown the same way (`meshgen.natural`).
  Leafy vines twine up the stem, tapering at both ends (`vines`). One vase
  leaf envelope rises up it (`leafFrom`, for tree crowns).
- **Offshoots:** braided (`meshgen.shootPath`; genome `shoots` = the
  per-variant count range), each ending in a closed bud or a small bloom.
  They are looks only. Colour alpha = 1 - how far out along one it is;
  plant.vert folds them in against the stem until growth passes them.
- **Blooms:** each opens out of a bead of the lineage's amber resin
  (`meshgen.Calyx.resin`, part `.resin`), held in a cup of five sepals:
  two whorls of real petals, with stamens on its crown.
  - The bead shades like the structures' resin (surface.glsl
    `resinSurface`; tu.y runs from dense base to thin crown), dimmed by
    health.
- **Greens:** their leaves and sepals are not muted. plant.frag shades
  them in their own green (`green`; light comes through them at
  `GREEN_THROUGH` of it), like the structures' leaves.
- **Lumenroot:** the palette's leaf green; a vine green richer than the
  palette's (the stem stays muted); a cyan bloom.

### Parasites (`coil`, `parasiteKit.plant`)
Alien, not hostile. Exactly symmetric and dead upright; variants differ in
proportion only.

- A lattice cage stalk on a bulbous foot, with sacs hanging on its core
  inside and a bulb at its neck.
- A candelabrum of 5 fronds, each ending in a pod crowned by 5 frondlets.
- plant.vert parts the cage from the foot up (tu.y) and opens the crown.

### Floaters (`drift`)
- **Lantern:** a comb-jelly lantern (`meshgen.lantern`): clear sap, 8
  twisting comb rows in split-light colours, a golden spore inside.
  plant.frag shades it apart by tu.x 0.5, with a bright iridescent film.
  Approved as is.
- A catcher dish.
- Hair-thin filaments waving in two lengths (plant.vert runs a wave down
  them).
- A slow bob over a ground shadow.

### Confluence
- 8 growth keys of one vertex layout, blended in plant.vert (binding 2).
  (A growth key is a snapshot of the shape at one stage; the shader blends
  between them.)
- Braid strands running on into red vines; translucent violet petals.
- Sway ×1.5.

### Vesper (`star`, `radiantKit.star`)
An evening star come down. It hangs `stemH` (0.62) over its tile, held to
it by a root of light: a taproot and 5 thin gold strands fanning down from
the core's underside into the soil, a small violet crystal shard standing
where each digs in. The root strikes down out of the heart just after it
lands, and never turns.

- **Parts:** a dusk-violet core (gold nucleus, 5 stamens); an upright cup
  of 5 pale-gold petals; a star of 5 long narrow violet rays lying open;
  5 dusky leaves floating beneath (`glow` 0.3: living tissue, little
  light, they cast shadows); motes. No halo.
- **Gathering:** it gathers as the bloom does, but falls in from the sky
  (plant.vert `FORMS_FALLING`, `FALL_*`). The heart comes first, straight
  down; then each piece spirals down on its thread.
- **Colour:** it keeps more of its own hue under the film (plant.frag
  `FORMS_OWN_HUE`).
- **Withering:** out of radiance, any radiant plant comes loose (`LOOSE_*`:
  pieces sink, drift out, hang open) and its light dims with health.

### Celestial bloom (`radiant`)
A flower whose petals float free, gathered by its core.

- **Parts:** a luminous core with a crown of stamens; three whorls of
  narrow cupped petals (inner upright .. outer open) floating apart from
  it, each held by a thread of light; motes spiralling in; a tilted halo.
- **Surface:** pearl with an iridescent film (plant.frag `filmHue`, by
  view angle).
- **What each fragment carries:** assembly order (tu.x), `radiantKit.Ring`
  (tu.y; a thread adds its distance from its petal) and bearing (colour
  alpha).
- **Growing:** plant.vert spirals each piece in, folded as a bud, and
  opens it as growth passes it.
- **Grown:** whorls turn slowly, alternating, and drift apart and back. It
  bobs and never bends.
- With the vesper, it is the garden's only true glow.

### Beams between linked blooms (`bloomThread`, part `.thread`)
- Soft rays: a camera-facing spindle bent in part.vert's curve mode.
- No core: a faint haze with five soft streaks swelling from sender to
  receiver.
- Iridescent: rainbow end to end, rolling along. Tiny motes drift inside,
  shifting hue (seeded by the instance phase).
- Dim when the network is dark.
- Sent from the more grown bloom as it finishes.

### Wild birds of paradise (`meshes/bird_of_paradise.zig`, `game/wild.zig`)
Real by day, magical by night. A clump of blue-green paddle leaves on
long stalks; flower stalks as tall end in a beak, a sideways sheath, green
at its heel flushing wine red to its point. Out of it rise crests of
flame-orange sepals (gold at their tips), one flower after another, each
with a blue tongue reaching forward over the beak and a white stigma at
its tip. Crest and tongue are `.bloom`: by night they glow and each grown
clump throws a warm orange light round its crest (into the fog too).
Three clumps: young (4 leaves, 1 flower), plain (6, 2), old (8, 3). Grown
on a skeleton: leaves rise and unfurl one after another, then the stalks
climb, the beak forms and the crests open in turn. They sway as low
structures do.

## Structures
`structureKit` structures speak the plants' language: woven root mats,
leafy vines, real petals, pods of resin sap (`Def.sap`, no light of their
own).

- **Sway:** standing structures sway (`Def.sway`). Conduits don't, so
  chains stay joined. Hung parts follow via `Look.drop`.
- **Breath:** they breathe at a fixed tempo.
- **Growing:** they grow in along their growth splines: trunk first,
  branches after, leaves unfolding as the front passes, emitted pieces
  last ([growth.md](growth.md)).

### Germinator
(`Def.still`: no breath, so its emitted pieces stay on it; `Def.preview`
whole.)

- **Shape:** a small tree, natural and uneven. A fine woven trunk
  buttressed into a wide root mat, ten foot leaves sprawling round it;
  five slender braided boughs, each straying its own way, rise round a
  core of thin resin sap held in a calyx (its sepals each their own
  length), and arch over it to hold flower cups (with stamens) above it.
  Each bough carries eleven leaves, three leafy twigs at uneven heights
  leaning their own ways, and a fan of five leaves behind its cup, so the
  crown is crowded. A sapwood spindle runs up through the core.
- **Weaving is shown by its progress alone:**
  - The cups hold what it stocks (pools of `.essence`, kept level).
  - They tip and pour it (curve-placed streams, colour in `q.yzw`).
  - The core spins it into a whirl round the spindle: one arm per essence,
    turned by the area under the spin stage, whole turns per weave.
  - Threads wind a seed of them on the spindle: a kernel in the output's
    colour, one winding per essence.

### Arsthraxia
(`Def.bare`, its own `emit`; never breathes or bobs.)

- **Shape:** three braided stems twine up from a root mat. They part into
  a cage round a resin pod threaded on a nerve, and gather in a calyx
  under a violet flower. The flower has two whorls, emitted, opening and
  counter-turning while it studies.
- **Nerves:** each stem's core is a nerve (part `.nerve`,
  `mg.braidAround`). While studying, violet thought climbs it (part.vert);
  each unit done sends a surge up (`flutter` = flare).
- **Research grows on it:** vines climb the stems (Arsthraxia,
  `Study.vines`), and each minor study adds a braided offshoot bough with
  a vine round it and its own flower.
- **Satellites are thought-buds:** small violet buds like its crown's,
  five petals furled round one another over a warm amber heart lit from
  within (`budHeart`, emitted with its own glow); a green calyx under each.
  At rest they cluster shut round the core, facing out; studying, they
  split, spin out and open like pinwheels, stamens drawn out of their
  hearts, wisps streaming from them into the core. Their hearts warm the
  air (a light round the core, one per offshoot's bud).
  - The opening is the GPU's: four keys of one vertex layout (`budKey`,
    closed to open), each blended into the next in part.vert (binding 4,
    the instance's `morph`). A part mesh declares the key it blends into
    as `next`; it must be built after it, vertex for vertex alike.
  - Seen up close: `--samples=arsthraxiaBudSpiral` (closed, half, open,
    three times its size).

### Sap cache
- A resin gourd cupped by a calyx on a woven bole.
- A wicker basket over it: green vines one way, pale roots the other, over
  and under.
- A collar at its neck, and a bud of sepals closing its mouth
  (`sapCacheLid`, emitted). The bud opens as an item drops in (sinking to
  its stack, which swells) or rises out.
- Contents hang inside.

### Root-digger
- Four braided roots break the ground (soil heaved round them) and twine
  up to grip a small resin gourd, with a leaf tuft on top.
- **Digging root** (`diggerRoot`): a conduit arch whose `.core` runs home
  (tu.x 0 is in the node). It reaches to the node it works, and withers
  from one that is gone.
- **Each item** is prised loose (`diggerClod`s flung up about the claw),
  then swells up the core in its colour to the gourd.

### Conduit
(`Def.bare`, its own `emit`.)

- **Path, per tile:** a root digs up out of the soil at each edge it is
  fed from (`link` hook: `feeds`; `conduit`/`conduitLeft`/`conduitRight`).
  It arches (rising long, diving short) and digs back in at its front. So
  chains join underground in any turn.
- **Body:** a sapwood core (part `.core`) in an over-under weave of
  strands; branchlets; leaves in twos and threes swept forward; soil
  heaped (a ridge pushed ahead where it dives) with rootlets.
- **Carrying:** carried essence swells and tints the core as it passes
  (part.vert, `Look.carry`/`carryCol`). Amber pulses run the way it
  carries.
- **Side roots** (`conduitTap`) are smaller woven arches.

### Others
- **Loomfern:** a fern: fronds, croziers (the curled-up fern tips), and a
  sheaf winding on its spindle from threads off the fronds.
- **Weftstone:** an ionizer, no leafy crown.
  - A clear chamber of both saps in a net of five green and five pale
    strands, knotted violet where they cross.
  - Five pale nodes reach in round its middle.
  - Five vanes fan out of its top knot: two pale ribs and a bar each,
    strung across with fine green threads, like a loom's warp.
  - Air motes spiral in through the vanes into the chamber, always.
  - Ionizing, lightning jumps between the nodes and the crystal
    (`weftstoneSpark`, part `spark`: white-hot core, violet edge, lights
    the fog). It starts as one tiny spark and grows to five long ones as
    the crystal forms.
- **The weave of both** (the convergence kit's stalk, chosen as a blend
  of two looks): two stems out of the soil, a green braided one and a
  pale smooth one swelling at its nodes, winding round each other and
  grown together in smooth calluses (green one side, pale the other, a
  violet seam between), fusing into one soft see-through body with green
  strands, amber lanes and a pale vein inside it and pale ribs on its
  skin. No root bulbs: the stems flare gently and the roots leave from
  under them.
- **Driftbraid:** the reference for convergent structures, on that weave.
- **Monfris:** four corners of grafted stems twining into one crowned
  body.

## Halo
This is what plays while a halo forms from four blooms
([design.md](design.md#halo-and-diamond-halozig-diamondzig)).

### The blooms come in
- The blooms spiral in to the ring's heart at bloom hover height, over
  1.25 turns, and fold to buds.
- How far along each one is follows `share ∝ e^(4k)`: an exponential
  curve, so the pull quickens toward the end.
- All of it runs on the GPU (common.glsl `haloSpiral`). The CPU sends only
  `[centre, k]` (instance `h` / `vertex.noHalo`; beams keep their held
  ends in `e.z`).

### The diamond projects the halo
- The diamond (1.6× its mesh) gathers at the heart from its shards.
- It projects needle rays of split light (`haloProjection`, part 12),
  running level out to a ring through the points.
- The ring (`haloRing`, part 11): a spectrum across its width with a red
  inner edge, like an ice halo, and beam-like swells and motes running
  round.
- As they meet, a flash spreads (`haloFlash`, part 9).

## Resource nodes (`mineralKit`)
- **Stones** are weathered boulders, smooth and lumpy, ground down to a
  few worn faces with rounded edges, a third buried; shaded as stone
  (part `.stone`, part.frag in mesh space): mottled grey, fine grain that
  tips the light, dark and pale flecks, darker hollows, lichen on the
  faces turned to the sky.
- **Crystals** stay flat-faced, cut planes catching the light.
- **Ley shards:** a violet crystal cluster.
- **Grit:** boulders with quartz chips.
- **Fibre:** a swaying clump of arching stalks.

## Sap
Sap everywhere is alive. Bubbles rise inside; beads slide down its surface
(`sapBubbles`/`sapDroplets`, in mesh space). Symbiotic and parasitic
plants are matte, stems and vines included, as are every plant's leaves
and petals: sap lights them from inside, but no bubbles, beads, glisten or
fibre sheen sit on them (plant.frag).

Sap glistens; it never glows softly (`sapGlisten`, common.glsl, on every
sap material):

- hard-edged mirrored lights (`hardSpot`: the key light with a white-hot
  core, points of light, a sky window);
- winking skin facets;
- a sharp caustic (focused light) through clear sap;
- a thin hard edge line;
- its colour gathers to a narrow band at the edge (`SAP_EDGE_POW`).

The bloom post-process makes the glow round the glints.

## Sky
- A gradient dome, sun and moon, stars.
- Star motes (faceted core, ring, needle rays) turn, twinkle, hover and
  trail echoes while falling. At the unforming each shatters into 6
  crystal shards of its warm light, flung out and fading (1.4 s).
- **Shifting** (the unforming, `SHIFT` in common.glsl, the paws' spare
  push slot): the old sky shatters like glass from the zenith down. A ring
  of bright cracks sweeps over the dome to the horizon (about 6 s), ragged
  where the sky tears unevenly, finer cracks splintering each pane; behind
  it each pane flares and falls away at its own moment, the ley's glow
  flooding in, a seam of light all along the front. The sun, moon and
  stars go with the panes they were on. The fog and horizon turn as the
  front nears the horizon (sky.zig `fogFrom`, `fogSpan`).
- **Shifted**: the ley's glow. No sun, moon or stars; veils of violet
  light flowing slowly round the dome, warped through one another, their
  hue wandering; a plexus drifting across it (points on a shell round the
  eye, threads bowed along the dome); both drawn on the dome itself, so
  they keep their size from the zenith to the horizon and the sky reads
  round. A glowing band along the horizon; all pulsing as the ley lines
  did. Rose violet by day, deep blue violet by night. The key light and
  the ambient sky turn ley violet with it.
- **The seed gathering** (`unforming.draw`): the shards fly up in their
  plant's film colour, each trailing a ribbon of it (`.trail`: a strip
  turned to the eye, a thread at its tail, full and pale-cored at its
  head). The star they gather in is a web of pale blue light, points on
  two shells joined to their nearest by threads (`unformStar`), round a
  heart of light; it swells as they arrive and flares with each, turning
  slowly, lighting the air round it (so it reads from anywhere in the
  garden), and shrinks back into the seed as it falls, a comet's tail
  running up behind. Where it lands a ring of light rolls out over the
  ground (the halo's flash, 2.4 s) and motes are flung up.
- **Shifted light**: the glow overhead keys the garden a pale lavender by
  day, near white, so plants keep their colours; the sky's fill is a
  softer violet below it, so shade reads; the air sheds half its haze.
- A low camera pitch widens the view toward the horizon.

## Lighting (engine `render/light.zig`)
### Shadows
- The key light (sun or moon) casts shadows through a cascaded shadow map:
  3 cascades, shadow pictures each covering a wider area out from the
  camera (2048² each). `fit` snaps them to texels so they hold still.
- **Soft shadows that harden at contact** (engine light.glsl
  `cascadeLit`): the light has a breadth (`LIGHT_SPREAD`), so a shadow's
  edge is sharp where it meets what casts it and softens as it falls
  away. The blockers' depth is searched round each point (8 taps of the
  raw depths, the map's second binding), their distance sets the soft
  edge's width (1..7 texels), and 16 compares over a Poisson disc that
  wide, turned by a hash of the place, filter it.
- **Shade hides the sky** (common.glsl `SKY_IN_SHADE`): where the key
  light is shaded, the sky's light is too, a share of it, so shade
  deepens under things and inside foliage.
- **Night sight** (`NIGHT_GREY`): by night, lit colours fade toward a
  cool grey as eyes see in the dark; what glows keeps its colour.
- They are drawn in one multiview pass per caster (all 3 at once:
  `gl_ViewIndex`, `project()`), with casters at their coarsest LOD
  (`renderer.caster`).
- Shader variants with SHADOW leave out what is light itself: blooms,
  motes, beams, halo, ghosts, lanterns.
- Terrain receives shadows but does not cast them.

### Points of light
- `Parts.light`: blooms, motes, ley shards, diamond and flash. At most
  `maxLights` (32), ranked in view.zig.
- They and the cascades travel in `Lighting`, reached by address
  (`WorldPush.light`).
- Shader side: engine light.glsl `keyShadow`, `pointLight`; common.glsl
  `shadeLit`.
- Culling keeps whatever may cast a shadow into view (`Parts.sees`).

## Post-processing (engine `render/post.zig`)
- World passes draw into an HDR image (one that can hold light brighter
  than white).
- **Bloom:** brighter-than-white light glows out. A 5-level 13-tap chain
  shrinks the image, with a soft-knee threshold (a gentle start rather
  than a hard cutoff) and anti-firefly weighting (so single bright pixels
  don't flicker); a tent filter scales it back up.
- **Composite:** adds the glow (0.7), rolls highlights off above 0.8, and
  adds a faint vignette.
- `Desc.screen` passes (the UI) draw on top.

## Anti-aliasing (`post.Antialias`: off, fxaa, msaa2/4/8; default msaa4)
Anti-aliasing smooths jagged edges.

- **MSAA** (several samples per pixel): draws the world into multisampled
  colour + depth, resolved (averaged) into the HDR image. Plant/part
  passes (`Desc.perSample`) shade per sample, since their solid/glass
  split is per fragment.
- **FXAA** (a blur along edges after drawing): `fxaa.frag`, FXAA 3.11
  quality, filters the composite (luma in alpha) before the UI.
- `Renderer.antialias`/`setVsync` switch at runtime (remaking pipelines /
  swapchain).

## Loading screen (`game/loading.zig`, wired in main)
A living night (`Draw.night`, ui.frag) with the name; a tendril growing as
far as what is made (leaves opening as it passes); the stage, percent,
made/left.

The stages:

1. Every mesh, grown on a thread of its own (`renderer.meshProgress`;
   `meshesReady` uploads once they are through).
2. The world woken.
3. Its ground meshed in 25 ms slices (`World.unmeshed`).

It shows after a load in play too. It fades off over play's first frames
(0.6 s).

## UI
Every interface is grown, never boxed. The shapes are SDFs (shapes drawn
from a distance-to-edge function, so they stay crisp at any size) in
`engine/shaders/ui.frag`.

### Panels (`Draw.trellis`)
- A dark bed of leaf litter behind a faint diagonal lattice of woven
  withies (over-under; `LATTICE_SHOW` kept low for the text).
- Framed by two vines braided round the rim.
- **Growing:** they root at the lower left corner and grow both ways round
  in `trellisGrow` s from the frame the panel is first drawn (`Draw.grown`,
  keyed by its seed; a frame's break regrows it). Tips taper.
- Leaves unfurl off the nodes behind the tips. Some nodes bear an amber
  sap bud or a curling tendril.
- Leaves sway; sap pulses climb out from the root.

### Slots (`Draw.husk`)
- Ribbed husks, fuller below, with a calyx of sepals.
- Each hangs by its stalk from its row's vine (`hudBelly.Vine`: belly,
  hotbar, a structure's store). The vine grows across, with leaf pairs
  between the husks.
- A husk swells as the vine reaches it and swings a little. Sap light
  fills it when lit.

### Bars (`Draw.tendril`; any angle: `Draw.stem`)
- A stem grows to the value, with alternating leaves unfurling behind a
  bud at its tip and a faint twine ahead.
- The belly's main stem rises up its left side, filling with sap.

### Small pieces
- Bullets: buds (`hud.bullet`) that open under the mouse.
- Ingredients and saved gardens: seeds (`Draw.grain`).
- Also: stems (`Draw.limb`), leaves/buds (`Draw.leaf`), gems (`Draw.gem`),
  soft glow.

## Item icons (`game/icon.zig`)
- **A structure's bulb** is a split seed with a sprout or two showing what
  it does. It comes from its `icon` hook, drawn with the `Icon` kit:
  `coat`, `stem` along a Bézier curve, `leaf`, `bud`, `glow`, `gem`,
  `kernel`. Sprouts sway.
- **A plant's seed** likewise, from its module in `game/seeds.zig`
  (`seeds/<species>.zig`: `item` + `icon`). The test fails on a sown
  species without one.
- **Any other item** is its colour fill with its short name, for now.

## Wolf (`game/player.zig` rig)
### Colour and build
- Three colours, as the gardener drew it: a hide of dark red-brown bark
  (`pal.wolfBark`, its muscles a shade warmer), leaves, vines and claws of
  bright living green, and amber sap. Amber only on belly, the panel down
  the front, eyes, inner ears, beans, pectorals and rear.
- **Torso:** the ribcage is broad but melts into a waist only a little
  narrower (`rib*`, `lat*` in `wolfBody`). No barrel rim over the waist,
  front or back.
- **Build, as the gardener drew it:** heavy and stylized: big rounded
  deltoids, the upper arm grown as two branches (one from the shoulder,
  one on the body's side) with an almond hole cut clean through between
  them, joining into the one forearm at the elbow; large pectorals with leaves of chest fur lying over their
  tops (in `wolfPec`), a slender neck, wide hips, great thighs swelling
  out past them, stout digitigrade legs on big paws, and mitten hands:
  thick, long fingers melted a little together, each digit still its own.
- **Head, shaped:** full cheekbones with tufts of leaves fanned back off
  them, whisker pads either side of the muzzle so it reads boxy at its
  end, and a plump lower lip of amber sap (a little pout): a sap bean on
  the jaw (`wolfBody.lowerLip`, emitted in posing), dense like the chest.
- **Muscle:** the limbs carry heavy, distinct muscle: three-headed
  deltoids, bicep/tricep, brachioradialis, quadriceps with an inner
  teardrop, two-headed calves, neck cords, obliques. They are melted only
  a little (`meatMelt`), so a groove reads between each mass.

### One skin
- **Sculpted:** `wolfBody` is sculpted with engine `gfx/sculpt.zig`. SDF
  forms (ellipsoids, round cones, round boxes) per bone, joined with
  smooth union or carved away, like clay; `ink` paints colour only.
- It is sculpted around the bind pose (the rest pose the mesh is built
  in) of `wolf_skeleton` (27 bones, `fk(Pose)`).
- **Meshed once** with surface nets (a way of turning the sculpt into
  triangles on a grid; `cell` 5 mm, doubled per LOD).
- **Weights:** each vertex is weighted to the bones of the forms nearest
  it (only across joints that are joined).
- **GPU skinning:** `vertex.Skin` sits beside the mesh buffer (binding 2).
  Bones come per frame via `Parts.pose`/`emitSkinned` (part.vert mode 3,
  buffer device address in `WorldPush.bones`).
- New wolf meshes are built in bind space and skinned; never rigid parts.

### Over the hide
- Vines cast onto it from bone axes (`wind`/`line`, so they never jump
  across).
- Fur leaves (`wolfKit.leaf`) as hair: over the crown with a forelock and
  nape mane, along the cheekbones, shoulder tufts, and the tail thatched
  root to tip into a great flame of leaves, broadest past its middle.
- What the gardener drew over it (`finery`): a lock falling over the -x
  eye (the left one seen from the front), a collar of leaves round the
  neck with a layered bib on the sternum, thick cuffs of leaves thatching
  each forearm up from a clean line at the wrist, a flame tuft on the -x
  thigh and a lotus of petals on the +x one, a tuft fanned down over
  each kneecap.
- A sash: a vine wound round the -x upper arm, run under one pectoral,
  swagging down over the belly with leaves along it (`wolfBelly`,
  swelling with it) and back up under the other.
- The claws are leaf tips: green (`pal.wolfClaw`).
- Digits and claws (`wolfKit.digit`).
- Eyes set in carved sockets under the brow.

### Head
A short muzzle rising to an upturned nose (bean); the lower jaw (its own
bone) tucked up under it; ears (`wolfEars`, skinned to ear bones).

### Resin sap
(`.resin`, sprung `give`.) Pectorals (`wolfPec`) on the chest; the rear
(`wolfRump`) on the pelvis, its lower edge partly following the thighs.
The sap panel down the front: the bark is inked amber from the sternum
between the pectorals, broad over the belly and out to the hips, drawn to
a point at the groin (ink forms in `wolfBody`), glazed by a thin resin
sheet laid over it (`wolfPanel`); the belly's sac swells over it.

### Gathering (`Player.pry`, `armsToWrists`, `solveArm`)
- **A deep squat** (`squat*`): hips drop, body leans in, feet step out,
  tail lifts.
- **Both paws on the node** by arm IK (inverse kinematics: place the paw,
  and the elbow and shoulder work out how to bend).
- **A pry each unit** (`pryPull`): pull back and up, wrench with a wrist
  twist, back to the grip; the body rocks back. Fingers shut on the node
  and open to regrip.
- **Stowing:** each unit that comes loose sends one paw, in turn, cupped
  to the front of the belly (`stowTime`).
- The generic work gesture gives way to it.

### Plucking (`game/pluck.zig`, `Player.hold` `.plant`)
Harvest on a ripe plant is taken by paw, never all at once:
- **Steps up** to `pluckAt` from the yield, clear of the leaves.
- **As high as the yield** (`Species.pluck`, per kind): the squat goes
  only as deep as it is low (`Player.low`); one over the chest is
  reached up to, the wolf stretching and leaning back (`Player.rise`).
- **Up to three plucks** (`pluck.most`), each `pluck.time`: both paws
  close either side of the yield and draw it back toward the wolf; the
  plant **bends after them** (`PlantInstance.tug`, bent on the GPU from
  the root, tip most; a radiant one is drawn along instead).
- **Comes loose** at the wrench's end: the plant springs back past
  upright and settles (`pluck.Tug`, an underdamped spring), and one
  paw, in turn, carries a **bead** of the yield's colour (`itemPod`)
  cupped at its knuckles to the belly (`pluckStow`, slower than a node's).
- **Bursts and shivers** there (`pluck.Tug.loosed`): motes of the yield
  drift up and drops of it arc down round the paws (`pluckBurst`,
  part.vert's burst placement), and the plant's leaves, petals and pods
  quiver, dying away (plant.vert `SHIVER*`).

### Ripening (`meshgen/pods.zig`, part `.pod`)
A plant's yield shows on it, where the paws pluck it:
- **Pods** (`Genome.pods`, `podR`): beads of sap, one per share of its
  cap. A symbiote hangs them on short stalks from its stem (`podAt`); a
  thornleech ripens in the sacs in its cage; a driftwisp gathers starlight
  in its dish's heart; a confluence hangs them from its weave over where
  the trunks fuse; a vesper holds beads of light round its core
  (radiant fragments, ring `.yield`).
- **Swelling** (`PlantInstance.ripe`): each fills in turn as the essence
  builds, from a dark nub to a bead of the yield's colour
  (`PlantInstance.yield`), shrunk about its own centre on the GPU (tu.y
  its radius). Ripe, it breathes and holds a soft light of its own.
- **The whole plant** takes on its yield as it ripens: its sap tints toward
  the yield's colour and shows more (a symbiote's leaves keep their green).
- **Taken**, a pod empties back to its nub, which weeps bright sap for a
  few seconds (`WOUND_FADE`) and swells again as the plant ripens anew.

### Belly stages (`Player.stage`, `gaits`)
- Stages: light (< 1/3 full), heavy, full (> 2/3), blended over
  `stageBlend`.
- Each fuller stage:
  - walks and sprints a little slower (full: 86% / 80%);
  - steps shorter and lower;
  - sways and rolls the pelvis more (full: a waddle);
  - sinks and bobs lower, and leans back under the weight.

### Belly-rest idle (`restArms`, `rest*`)
- **When:** standing still `restAfter` s with the belly past a third full
  (fully in the pose by `restFullIn`).
- **Pose:** the right paw lies palm down over the top of the sac; the left
  fist sits on the hip, elbow out (`solveArmTurned` swings the elbow round
  the shoulder-wrist line).
- Eased in on a slow spring; gone once he moves, works or gathers.

### Belly (`wolfBelly`)
- The wolf's own round amber belly, as the gardener drew it: a convex
  egg on the gut, bare (no vines over it), dense sap like the chest
  (`pecOpacity`), swelling out of the sap panel; what it holds no longer
  shows through.
- **Filling** scales and drops two bones: `gut` (lower half) and `gutTop`
  (upper half: as wide, its top kept where it hangs). So the swollen sac
  never folds (tested).
- tu.x = the gut's share of each vertex.
- A crease runs down its middle, there even empty, deeper as it fills; a
  second folds across it only as it fills.
- The belly button is the sac's own surface (part.vert `bellyCarve`, the
  grid gathered round it): a pit, a knot and a puckered rim, sunk in when
  empty; as the belly swells the creases part round it and it pops out.
- **Normals:** `vertex.Skin` carries each weight's slope (`gx/gy/gz`).
  part.vert bends skinned normals by the true Jacobian (how the surface
  actually stretches and turns there), not by the blended bones alone.

### Motion
- **Feet** are planted in the world and swung on arcs when the gait's
  phase says so (or, standing, when a foot is left behind).
- **Legs:** digitigrade (walking on the toes, as dogs do), every bone its
  own (`solveLeg`): the metatarsal stands back up from the ball at its
  rest angle, swung part way with the reach and folded mid-swing; thigh
  and shin reach the hock, the knee forward, the shin folding back. The
  hip is rolled out to the leg's plane before
  it swings in it (composed in that order and read back as one turn), so
  the foot lands exactly; near straight the reach is softened
  (`softReach`) so the knee eases straight instead of snapping.
- **Feet hug the ground:** each foot feels the slope under it
  (`Foot.nrm`, eased) and its sole is tipped and rolled flat along it
  (`Limb.roll`); the hips drop so a foot down a slope or off a step still
  reaches (`hipDrop`).
- **Arms:** the elbow is placed toward a pole (back and a little out;
  swung out on the hip in the belly rest), the shoulder's swing and twist
  read back from the upper arm's whole frame (`solveArmPole`). Gathering,
  each paw turns to grip: palm toward the other paw across what they
  hold, fingers cupped over it (`handTo`).
- **Body:** the pelvis bobs at footfalls, sways, turns and rolls; the
  chest counter-turns.
- **Springs** (`Swing`): lean, bank, arms, head, ears and the tail's sway.
- **Head:** neck and skull turn as one chain to face exactly where it
  looks (the neck a share, the skull the rest), whatever the body below
  does; an idle look-around; ear flicks.
- **Tail:** a trailing chain (engine `rig.trail`): each joint carries on
  with its own motion, is drawn back to the tail's swinging rest shape
  and held at its length, so it swings through, lags a turn and settles.
- Breath and panting quicken with effort.
