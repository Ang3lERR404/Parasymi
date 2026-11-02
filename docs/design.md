# Game design

What the game is and how its pieces play. Code names in backticks point at
where each rule lives. How things look is in [visual.md](visual.md).

## Premise
Parasymi is a player-centric automation game, like Factorio, about
magically infused plants. Two lineages, parasitic and symbiotic, grow
side by side and converge; a third, radiant (celestial), stands apart.

The player is a vine-wolf, the gardener. They start from nothing and grow
a grand garden. The view is 2.5D: a 3D world seen from above.

## Core rules
- **No global resources.** Every item lives somewhere real: in the belly,
  in a structure or in a plant.
- **Every plant is sown by the player** and must grow before it is any
  use.
- **Research works like Factorio's labs:** structures eat the ingredients
  one unit at a time.
- **Plants never set seed.** Only a germinator weaves seeds. Weaving by
  hand makes bulbs only (`craft.byHand`).
- **The germinator is the bootstrap** and the hub of automation. It is
  woven from fibre, grit and starlight. It weaves every recipe, seeds and
  bulbs alike (`craft.all`), and lets go only of what it wove itself
  (`craft.woven`).
- **Always open from the start:** lumenroot and thornleech seeds, conduits,
  sap caches, the germinator. Every other species is gated by research
  (vesper by Seed Splicing: essence + convergence essence + fibre).
- **Uprooting a sown plant always gives its seed back.** If the belly is
  full, the plant stays put. A confluence gives nothing.
- **Plants and structures share the ground** (occupancy: one thing per
  tile). Footprints are 1×1, 2×2 or floating.
- **Floaters are off the grid.** A driftwisp, bloom, Vultrixi or
  weftstone hangs right where the cursor puts it, at any point. Floating
  plants keep 0.8 m from each other; floating structures keep 1 m and
  never two over one tile (they are found and held by the tile under
  them). Pointing at one reaches it before the ground; it draws from the
  tile under it.
- **Floaters** hang in the air. You reach one (panel, feed, configure,
  unbuild) where nothing stands under it. Nothing is ever sown or put
  under one.

## Base structures
- **Conduit:** pulls from behind and pushes forward. It grows a side root
  to a plant beside or behind it, and harvests the plant once the root
  arrives.
- **Sap cache, germinator, arsthraxia** (research).
- **Root-digger:** 1×1, on soil or moss. Research "Deep Rooting"; costs
  3 fibre + 2 grit + 1 ley shard. It digs an adjacent node at 1 item every
  4 s into an 8-item buffer and feeds its neighbours. With no node, it
  idles.

### Growing in
A structure grows after it is put down, and does no work until it is
grown (`Def.grow`):

| structure | grows in |
|---|---|
| germinator | 6 s |
| arsthraxia | 8 s |
| sap cache, root-digger | 4 s |
| conduit | 1.5 s |

### Carriers and handing items on
- **Carriers** carry items along (`Def.carrier`: conduit, braided conduit).
  They face one way, chain together, and hand items on to each other
  through `receive` (`Structures.handIn`, at the edge the item comes in
  by).
- Carriers are never pulled from.
- `gives` says what a structure lets go. A braid pulls a different kind
  per lane.
- `Structures.outputs` walks everything that may leave a structure: its
  `output` first, then each other kind it holds and `gives`.
- `st.handOff` feeds a producer's `outputs` to a non-carrier neighbour
  touching any side of its footprint. Each neighbour gets the first item
  it wants.
- `st.handOffWith` reaches further: `.range` steps out, handing up to
  `.amount`, nearest first.

## Lineage structures (2nd tier, each its own research)
### Symbiotic (woven, green, amber sap)
- **Loomfern** (1×1, soil/moss, "Living Looms"): weaves fibre. Unfed it
  makes 1 every 12 s. Fed, each essence makes 4, at 3 s each. Holds 12.
- **Gathering crown** ("Living Looms"): roots out to every plant within 2
  tiles (one root per plant's own tile). It gathers whatever is ripe, one
  unit every 1.5 s, taking the plants in turn. Holds 12.
- **Braided conduit** ("Braided Roots", woven from 4 conduits): 4 lanes,
  one kind of item each, moving 3.5 tiles/s. Joins and turns with ordinary
  conduits.

### Parasitic (pale, alien, `parasiteKit`)
- **Lithophage** ("Lithophagy"): drains grit and ley nodes on the 8 tiles
  around it, one every 3 s, into a crystal in its crop (6 grit, ley
  shard = 3). The crystal is sapped back out as 6 grit into its
  cup. It is fed ley shards only, so any grit it holds is grit it sapped
  (the gardener's call: grit).
- **Ganglion** ("Lithophagy"): holds 8. Every 0.35 s it hands one item
  out, going round its sides in turn, to whatever wants it, and to
  carriers not facing into it. Use it to split lines, or to feed several
  germinators each what it needs.
- **Sporecaster** ("Spore Casting"): paired one way. Configure one, then
  its partner (`pairs`; `Structures.pairStep` in its `configure` hook).
  - It sends spore carriers: free, 0.25 s apart, 5 of a kind.
  - They drift at 2.5 tiles/s, with unlimited range, into the partner.
  - If the partner is gone, they go home. If it is full, they hang over it.
  - `Def.far`: its spores are drawn however far away it stands.

## Parents and children
Any structure may depend on another, its parent (`Structure.parent`). The
link is held by tile and floating, so it survives ids shifting.

- `Structures.spawnChild` puts one down already a child (the polyp's
  diamond).
- `dependOn` adopts one, if the parent's `adopts(s, kind, have)` hook takes
  it. The default takes none. Never a loop.
- `detach` cuts a child loose.
- `getParent`, `getChildren`, `getChild`, `childCount` walk them.
- Uprooting a parent cuts its children loose.

### Partners
Partners are peers, not parent and child (`Structure.partners`, up to
`partnerSlots`, oldest first, held the same way as parents).

- A kind that declares `pairs:Pairs` pairs with its own kind (or with
  `.with`).
- One way: it sends to its partner (the sporecaster).
- Both ways: each is the other's (the driftbraid).
- Up to `.most` partners at once (default 1). One more lets go of the
  oldest; with both-ways pairing, that one lets go too.
- Uprooting cuts its pairings.

The calls: `pairWith`, `unpair`, `getPartner` (the first), `getPartners`,
`pairedTo` (who names it). `pairStep` is the shared configure handshake
(`Structures.pairing`): the first one configured waits, the next is paired
to it, and configuring the same one twice cuts it.

## Messages
A structure never reads or writes another kind's `state`. A test fails the
build if one does.

Instead it reads another through that one's hooks (`chosen`, `gives`,
`wants`, ...), and tells it something with `Structures.send(ctx, to, msg)`:

- The message is an `st.Msg`: `lit` (a diamond born whole) or `arrived`
  (items come in from afar).
- The target takes it at once in its `message(ctx, id, msg) Reply` hook.
  Without that hook, the message's default applies (`arrived` is taken in
  as `insert`).
- Nothing is ever left pending, so nothing is saved.
- A new kind of interaction is one more `Msg` tag.

## Convergent structures (3rd tier)
When two lineage structures of a pair grow within `structures.meetCount`
(3) tiles of each other, that is a discovery (`meets` hook +
`Structures.meetings`). It opens their research.

They are woven by a germinator only (`Recipe.germinator`), from the pair's
bulbs + 2 convergence essence. The confluence stays the only convergent
plant.

- **Weftstone** (loomfern + lithophage, WOVEN STONE): floating (its mesh
  carries `hover`, `Def.hover` 0).
  - It latches tendrils (emitted curves, `weftstoneTendril`) onto the
    nearest 6 grit/ley nodes within 2 tiles.
  - It draws one unit every 2 s from them in turn into its bulb (12 grit,
    4 ley).
  - It ionizes 4 grit + 1 ley into a ley crystal in 6 s; holds 8 and hands
    them on.
- **Driftbraid** (braided conduit + sporecaster, BRAIDED DRIFT): paired
  both ways by configuring one, then the other. It sends what it is fed by
  spore and takes in what comes back. It lets go only what came by spore
  (`kept` counts per kind).
- **Monfris** (weftstone + driftbraid, INTERWEAVING): 2×2. It weaves
  everything convergent (by `Def.lineage`: the polyp, weftstone,
  driftbraid, monfris, Vultrixi; the germinator weaves these too, so the
  first monfris can be made, never the hands), the arsthraxia once the
  unforming has evolved it into a convergent structure (`Def.evolves`), and the
  advanced tier only it weaves
  (`Recipe.advanced`, none yet); together `craft.loomFor`. Never the
  diamond or the vesper seed (radiant, with the celestial bloom), which are the
  germinator's. It never lets go of what its weave eats (a
  weftstone while it weaves a monfris). Fed by at most 6 Vultrixi
  (`monfris.tethers`, because a weave of its has at most 6 kinds), by
  hand, or by conduits.
- **Vultrixi** (gathering crown + ganglion, SHARED NERVES): floating.
  Configure it, then a monfris, to tether it (it becomes the monfris's
  child).
  - It takes the ingredient matching its place among the tethered.
  - It reaches a tendril into the nearest structure within 6 tiles that
    `gives` it (never a monfris or Vultrixi).
  - It pulls 1/s and sends it along its tether.
  - **Untethered, it relays** (its second job): it links to every other
    untethered Vultrixi within 6 tiles. One pulls from a structure in its
    reach whatever something along the links wants; the item hops link
    to link (nearest first) to the Vultrixi nearest a structure that
    wants it, which hands it over. Never back to where it came from.
- **Nebularbor** (the mist tree, `structures/nebularbor.zig`): roots 3×3 (its trunk nudged off the grid by the world seed, `nudgeOf`), crown 5×5 and taller than everything round it; moss
  only, woven by a monfris from 4 convergence essence, 2 ley crystals, a
  drift flower and 3 grit (so only after the unforming). It never stops
  growing: its life (`grow` 24000 s, 80 days) is drawn along a curve
  that slows forever (`drawn`), a sapling putting out young leaves, a real
  tree at 8 days, then old age: its last young leaves fall one by one and
  an offshoot grows where each was, and woven strands harden its foot.
  - **Ground water** (`Chunk.water`/`waterCap`, from the generator's
    wetness: moss holds well over a third, stone little; not saved, like
    the ley). Hovering a tile shows it (`WATER x%`).
  - **Its roots drink** (all through its life, `Def.worksGrowing`) from its
    3×3 and the ring round it, an even share from each, more the further
    along its life; never below 40% of a tile's water (`floor`), and every
    tile drunk from refills toward it (1/600 of what is missing a second).
  - **It breathes** (`breath` hook) a trickle of its own (8%) and what it
    drinks, a mist round its foot and a cloud over its crown; in its old
    age it makes up to 1.6× the mist of each drop. Dry ground: the
    trickle alone.
  - The moisture is a field on the GPU (`passes/moisture.zig`) that drifts
    on the wind, spreads and dries; the fog draws it. Hovering any tile
    reads the air over it (`AIR MIST x CLOUD y RAIN z%`, read back from
    the GPU: the engine's `probe`). The weather begins here.

## Weather (`game/weather.zig`, `passes/moisture.zig`)
A water loop the gardener builds up in stages: ground water, drunk and
breathed by the nebularbor, gathers into cloud, which rains it back.
1. **Clouds gather, slowly, from a grove's leaves.** A nebularbor's
   crown spreads over 5×5 tiles though it roots in 3×3; crowns may
   overlap and anything may stand under one. A grove is trees whose
   crowns overlap: each tree's leaves breathe 4× more cloud for every
   real tree whose crown wholly overlaps its own (`groveCloud`), so a
   lone tree only ever makes a light haze. Cloud lingers (it barely
   drifts or spreads, drying over 40 minutes); past 0.6 it holds
   together, wholly at 1.0, a tipping point only a grove passes: held, it
   drifts and spreads far less and lasts 10× longer, piling up heavy.
2. **Rain falls on its own** where cloud grows past 1.4 (a grove of four
   young trees first rains after about three minutes, then in showers
   every few minutes; the demo's grove of nine, east of the garden, after
   two, then near steadily). It rains until the cloud is rained out to 0.7,
   harder the thicker it is, each shower building and easing and drawing
   the cloud down; a shower spreads through its cloud, raining wherever a
   neighbour rains and the cloud is thick enough to keep on; the rain
   feeds the grove's own roots.
3. **Rain refills the ground:** where it rains the ground grows wet
   (one shower soaks it through, a downpour in 2.5 s; drying to a third
   in 5 minutes). Once a second the game reads the whole field back (the
   engine's `field`) and soaks every loaded tile's water back up toward
   all it holds, as fast as the ground over it is wet (a third of what is
   missing left after a minute wet through; never past its cap).
   **It pools:** rain on ground already wet through stands on it as water
   (the field's alpha past 1) and runs downhill, levelling out in the
   dips and valleys (moisture.frag, on the GPU, no water made or lost on
   the way); pooled, it dries away over 10 minutes, keeping the ground
   under it wet through. The pools pass draws it (`passes/pools.zig`).
4. **The first rain** over the loaded garden is a discovery (`firstRain`).
   The breeds it opens (the gardener's picks, to be built on the pools):
   a moss creeper (spreads moss onto wet soil, so groves can grow), a
   mire lily, a root well (stores rainwater above ground) and a cache
   taking the sap cache's place after the unforming, with more slots.
   - **Mire lily** (`species/mire_lily.zig`, built): MIRE BLOOMING (after
     the unforming, needs `firstRain`; 20 units of 2 convergence essence
     + 1 ley crystal) lets germinators weave its seed (2 convergence
     essence + 2 grit). Convergent, 1×1. It never draws the ley: it
     drinks its tile's ground water (`waterDraw` 0.006/s, each unit 30
     mana, `ecology.waterMana`) and yields convergence essence. It needs
     soaked ground (`needsSoak`): where the rain has left its tile wetter
     than half (`Chunk.wet`, read back with the field each second,
     `ecology.soakedAt`) it grows; drier, it halts and withers over about
     eight minutes, waiting out the dry spells between showers. Hovering it
     says which. A water lily (the `lily` form, meshgen/lilies.zig): its
     crown roots under the water, long stems rising to round notched pads
     lying on it and one bloom resting on it; drawn at the water's level
     (`Species.onWater`, `Chunk.pool`), its pads drifting and bobbing there
     (plant.vert `FORMS_AFLOAT`). Four grow along the demo grove's edge.
   - **Moss creeper** (`species/moss_creeper.zig`, built): MOSS CREEPING
     (after the unforming, needs `firstRain`; 20 units of 2 convergence
     essence + 2 grit) lets germinators weave its seed (2 convergence
     essence + 1 grit). Convergent, 1×1, drawing a little ley and ground
     water, yielding convergence essence. Grown and healthy, about once
     every 30 s (`Species.creeps`, on the garden's random stream) it turns
     a soil tile within 2 tiles (`creepReach`) to moss, if the rain has
     soaked it past half (`game/moss.zig` `creep`); the tile then holds
     at least a moss's water (0.4) and a nebularbor may root there. Grown
     moss is kept tile by tile (`Moss`, saved) and laid back onto every
     chunk as it streams in (`Chunk.mossed`), since the world regrows
     its ground from the seed. A groundcover (the `creeper` form,
     meshgen/creepers.zig): a cushion of moss, runners creeping out over
     the ground, a rosette of leaves and a tuft of moss rooting at each
     node; it never bends from a root (`FORMS_LOW`). In the demo, one
     grows on a patch of bare soil past the lilies.
   - **Root well** (`structures/root_well.zig`, built): ROOT WELLS (after
     the unforming, needs `firstRain`; 20 units of 2 convergence essence
     + 1 ley crystal) lets a germinator or monfris weave its bulb (3
     convergence essence, 3 grit, a ley crystal). Convergent, 1×1. It
     stores the rain above the ground: while it rains over it
     (`Chunk.rain`, read back with the field) it fills, 2 a second in a
     downpour, up to 60 (the field's water: a unit is a tile soaked
     through); once the ground under it dries past soaked it pours 0.8 a
     second round its foot, 2 units across (`Breath.water`, a spring into
     the field's ground water), until the ground is soaked again or it is
     empty. So the ground round it stays soaked through the dry spells,
     for the lilies and creepers. A woven basket of both lineages on a
     rooted foot, a see-through lining inside its staves, leaves round its
     braided rim; the water it holds a surface risen as high as it is
     full (`rootWellWater`, `surface`). Hovering it says how full, and
     whether it is holding or pouring.
   - **Tanglehold** (`structures/tanglehold.zig`, built): the sap cache's
     place once the unforming has taken it, and twice its room: plain
     storage of both lineages, 32 slots (`Def.room`; every structure's
     inventory holds up to `structures.slots`, 32, each kind keeping
     items in its `room`, 16 by default; conduits and the panel fill
     only that, `Structure.bag`). Its panel shows its slots in four rows,
     as many across as it needs. Woven by a monfris from the unforming on
     (2 convergence essence + 4 grit), so the garden is never without a
     store. A sac of both saps caged in braided staves on a rooted foot,
     a crown of young leaves where the staves meet; what it holds hangs
     in the sac on a slow spiral, one glowing lump a stack.
5. **The storm** (`structures/storm_spire.zig`): the storm spire, a
   weftstone kin of both lineages, woven by a monfris after STORM CALLING
   (after the root wells, needs `firstRain`; 30 units of 3 convergence
   essence + 2 ley crystals) from a weftstone, 4 convergence essence and 2
   ley crystals. It holds up to 5 ley crystals. While rain falls on it
   (the heaviest within 3 tiles, where its lanterns fly, past 0.15) and
   it holds one, it charges over 30 s of rain, building over a grove's
   showers (dry, it fades over about 8 minutes); its five lanterns, flown
   free on threads up into the cloud (each its own piece, wandering on the
   air its own way, `stormLantern`, `stormThread`), beat brighter and
   faster. Full, it strikes: a bolt up the
   spire and every thread into the cloud, the lanterns flashing, the
   crystal spent; it never charges in its own storm. The storm lasts two
   minutes: it feeds the cloud over it
   (1.5 a second over 3 units round: past the rain line in about ten
   seconds), so the rain stays heavy, and bolts
   strike the ground within 7 units of it, 18 a minute, each flash
   lighting the fog. The first storm is a discovery (`firstStorm`); the
   weather is fully formed. In the demo one stands between the lilies,
   holding five crystals.

## Confluence (`game/convergence.zig`)
When a mature symbiote and a mature parasite are within 2 tiles (or joined
by a conduit chain), they root a 2×2 confluence beside them, unless one
already holds them.

- Never sown.
- Grows in 4 stages, taking 1.5× as long as the slower parent (`span`).
- Yields convergence essence.
- Once mature, it halves parasite drain within 3 tiles.
- "Convergence Theory" only reveals its yield.

## Radiance (`species/bloom.zig`, `ecology.Radiance`)
Radiance is a field of light that some plants need to live.

- **Celestial bloom:** sown, floating (hover 3.2), yields nothing. It
  radiates a 3.5-tile field. Seed: 3 starlight + 1 ley shard + 2 essence.
- **Networks:** blooms within 10 tiles of each other link into a network.
  A network radiates when it holds a mature bloom, and then all its blooms
  do. So uprooting a linking bloom cuts off those beyond it.
- **Needing it:** plants with `needsRadiance` (vesper, for now) halt and
  wither (0.06 HP/s) outside every field.
- **Worked out per tick from blooms only:** first the pairwise links, then
  each radiating bloom's tiles.
- **Hover panel:** RADIATING/DARK + links for a bloom; DRAWING
  RADIANCE/WITHERING for a plant that needs it.

## Halo and diamond (`halo.zig`, `diamond.zig`)
- **Four blooms are enough:** grown blooms (HP > 0.5) on the four points
  5 tiles east, south, west and north of a tile with no diamond over it
  form a halo there (`halo.seek`, every tick). No polyp is needed.
- **The event, once per ring, over 5 s:** a DIAMOND is put down floating
  over the heart (`Diamond.born = .halo`). The blooms spiral in to it and
  fold to buds while it gathers and projects the halo (see
  [visual.md](visual.md#halo)).
- **As they meet:** the blooms are consumed and a flash spreads.
- **Fields:** the ring's field has radius 5 while forming; the diamond's,
  radius 7. Points without a grown bloom dim their arcs to 0.3.
- **What it opens:** a diamond discovers `.diamond`, opening CELESTIAL
  DEFRAGMENTATION. That lets diamonds be woven and put over any dry tile
  (they gather as they grow, then flash).
- **Demo:** west of the garden, the fourth bloom finishes ~20 s in.

## Polyp (`structures/polyp.zig`)
- **Convergent:** woven of both lineages (`polyp_convergent.zig` WOVEN,
  the gardener's pick). 1×1, grows in 6 s; costs 4 fibre + 3 essence + 2
  starlight + 2 ley shard.
- **Feeds** on every grown bloom within 4 tiles: 20 s of one bloom's light
  grows a DRIFT FLOWER (the confluence's flower, no stem). It rises off
  the crown and drifts round it, never far and never fading, up to 5.
- **Pulled from the air:** a click hands one to the belly (`handOver`
  hook).
- **Drift flowers** (`structures/drift_flower.zig`) are put down anywhere
  as floating lights, drifting in place. After the unforming, one put
  within 2 tiles of an evolved arsthraxia is taken into it as a stemless
  branch (`Msg.graft`): each makes it study 0.6% faster (linear,
  `arsthraxia.branchBoost`). With the blooms gone, a polyp then grows a
  flower on its own every 90 s.
- **Its first flower** discovers `.driftFlower`, opening THE UNFORMING.

## The unforming (`game/unforming.zig`): the first world event
Begun the moment THE UNFORMING (after Celestial Defragmentation; 30 units
of 3 convergence essence + 3 starlight + 1 ley crystal) is learned.
- **Radiant plants** (`Lineage.radiant`: bloom, vesper) glitch, shatter like glass and blink
  out, one after another over 6 s, each in 5 s (GPU: `PlantInstance.glitch`,
  plant.vert `unformAt`, plant.frag `unform`; `--plant=bloom --state=unform`).
- **Their shards** fly up to one point 14 m over their middle and gather
  into a STRANGE SEED in a star of their light, which falls (2.2 s), a
  burst of light where it lands, and lies on the ground, never
  planting itself: a structure the wolf may pick up. It is the constellate
  lineage's first, planted only in act 2 (below).
- **Everything else dies:** symbiotic and parasitic plants wither, and
  every structure of another lineage (`Def.unforms()`, from `Def.lineage`:
  the base ones, conduit, sap cache, germinator, root-digger, all
  symbiotic; the lineage ones; and the radiant diamond, its shards coming
  loose) grows back down to nothing and is
  gone (`Structure.fade`), over 8 s, each in 6 s. Only the convergent
  plants and structures (the confluence, the polyp, weftstone,
  driftbraid, monfris, Vultrixi) and the strange seed remain.
- **The arsthraxia evolves** instead (`Msg.unform`: `evolved`): drawn
  woven of both lineages (`arsthraxia_convergent.zig`, the gardener's
  pick). Its flower is the kit's own, two blooms nested, floating a
  little over its calyx, tethered to it by thin strands of both lineages.
- **The stars shatter:** every starlight mote shatters at once as it
  begins (`Starfall.shatterAll`), and no star falls again: starlight is
  no longer to be had.
- **The sky shifts for good** (1 s in, over 12 s; `Sky.shift`): the old
  sky shatters like glass from the zenith down to the horizon, falling
  away pane by pane to the ley's violet, glowing, its sun and moon (and
  stars) gone with it (sky.frag). The glow
  turning rose by day and deep by night is the only tell of the time.
  The key light becomes the glow overhead, ley-tinted.
- **The ley lines seal up** (over the middle of the shift; done 10 s in):
  each closes from its edges in to its heart, a bright seam at the
  closing edge, to a scar of bare soil (`gen.sealOf`: soil, only the ley
  a tile off the lines holds). Every chunk streamed in later is sealed as
  it comes (`Chunk.sealed`).
- **The ley shard nodes shatter** as the lines close: each breaks into 7
  violet shards that drift off weightless, rising and tumbling apart, and
  blink out of reality over 30 s (`Drift`, not saved). Ley shards are no
  longer to be had.

## Act 2: the star hyena
A garden has two acts (`game/act.zig`, `Game.act`, saved). The second
comes only after the unforming: once the wolf roots himself into the
garden's tree (not yet in the game; `--act2` begins there, the unforming
run through and its seed in his keeping), the gardener is the star hyena,
a living constellation (constellate webs on 28 bones, `--samples=constellateHyena`)
who never walks but hovers, leaning into his motion, his steps silent, the
camera in his eyes. He works with the convergent lineage and the
constellate one alone.
- **The strange seed, planted:** a crystal husk (a see-through `husk`
  part, clear glass with glowing cracks) with a small web turning inside
  it. Put down by his hand (the `sown` hook) it is planted; put down by
  the wolf's it only lies there. Planted, it conjures 50 fragments, one
  every 15 s, enough for a core and four petals: each a small glass
  triangle of three points that slips out through a crack and spirals up
  to drift loose round and over it (`strangeSeedWeb`, part.vert
  `plexusSeedWeb`; how many drift in the instance's growth). A click
  (`handOver`) takes one into his keeping. Hover says how many drift and
  how many are still to come.
- **Building:** his own hands (recipes `by=.hyena`, `craft.byHyena`, the
  belly panel showing each gardener's own) build a constellate core or a
  constellate petal from ten fragments each.
- **The yielder:** a core put down stands alone; each petal fed to it
  (`wants` petals) snaps on round its rim, bonded to it, until four stand
  there (part.vert `plexYieldOn` from its growth: only the petals on
  show). Whole, its petals turn round the core and every 6 s spring shut,
  their tips gathering one point of light over it, let go as a mote and a
  new fragment; it keeps up to 20 fragments, a click takes one.
- **Next:** what the yielder's fragments and light feed: the heart, the
  heart making parts, tendrils carrying them (one loop).
## Research panel (T, `hud/research.zig`)
The research tree is drawn as a sapling growing in soil. It is laid out
from the prerequisites alone, so it never needs placing or adjusting.

### Adding research
One file in `research/` + one line in `techs`. Set `.branch = true` on a
big step (new structures, species, an event); anything else is a leaf. No
coordinates, no sizes.

### Layout rules
- **Host:** a node grows on the nearest branch up its *first*
  prerequisite chain, else on the trunk. So list the prerequisite it
  belongs to first.
- **Order along a host:** children sit one slot apart, by depth (the
  longest prereq chain; a `needs` discovery counts 1), then by declaration
  order. Leaves and branches each alternate sides.
- **Stems** are one slot longer than their children (branches ≥
  `branchMin`) and bend toward the light. A branch whose tip would land
  on a node already grown grows half a slot longer at a time until it is
  clear (`crowds`, worked out on the still tree so it never jumps as the
  sapling sways).
- **Fitting:** the fully grown, still tree is fitted to the panel (`fit`,
  slot ≤ `maxSlot` px), so nothing moves. The sapling starts small at the
  soil and fills the panel as research is done.

### How nodes look
- **Known:** a grown leaf or branch with a violet bloom at its tip.
- **Open:** a gold bud that glows. While it is being studied, a leaf
  unfurls, or a branch shoot extends, with progress.
- **Locked:** a dim dormant bud where its host has grown; else hidden.
- **Trunk:** reaches `trunkLead` past its highest open/known node (eased,
  `play.Game.sapling`), and thickens with the square root of how many are
  known.

### Motion and pointing
Wind sways stems from the base (children follow); leaves flutter.
Hovering a node (`Game.pointed`) shows its card: cost, progress, or what
it is DORMANT on. With nothing hovered, the studied one's card shows.
Click selects.

### The layout test
The test asserts hosts come before what grows on them, and no two nodes
crowd (> 0.5 slot). If it fails after adding research, fix the layout
rules there. Never hand-place a node.

## Saves, options and the gardener's folder
### The gardener's folder (`game/home.zig`)
- `%LOCALAPPDATA%\Parasymi` holds `parasymi.cfg`, `controls.cfg`,
  `options.cfg` and `saves/`. All are made on startup when missing
  (`home.open` comes first in main; `home.dir()` for every file).
- No cfg ever lives beside the game.
- The two stock cfgs are tracked in `src/cfg/`, embedded (`@embedFile`),
  and written out with a `# stock <hash>` first line.
  - An untouched copy is replaced when the repo's copy changes.
  - An edited one is kept and read over the built-in (whatever it lacks
    falls back to the built-in).
  - So edits to `src/cfg/` reach the game, unless the AppData copy was
    hand-edited.
- An old `options.cfg`/`parasymi.sav` beside the game is copied in once.

### Saves (`game/save.zig`, `saves/<name>.sav`)
- The world regenerates from the seed; only the gardener's changes are
  stored.
- A save is written to a `.tmp`, then renamed over the old one.
- `Game.slot` is the garden being played. F6 saves into it, else asks its
  name. Quitting saves into it, else into the autosave.
- Names are only ever typed by the gardener (`save.Name.typed`). A save
  can be deleted from the menu.
- `Request` carries saves, loads, listing and deletes to main.
- Autosave (always `autosave.sav`) runs every `Options.autosave` minutes
  of play (default 5; options panel: never..60).

### Save versions
Bump `version` when a stored layout changes. (The fingerprint checks
sizes only.)

Structures are the exception. They are stored as `record`s
(`game/record.zig`: named, framed fields; enums and kinds stored by name).
So a structure's state may gain, lose or change fields, or hold lists (its
`State.deinit` frees them), without a bump. Older saves keep what matches,
take the defaults for the rest, and drop structures of a kind that is
gone.

### Seeds
Each start grows a fresh world (the seed is logged and kept in its saves).
`--seed=` repeats one; test gardens use `play.defaultSeed`.

### Options (`game/options.zig`, `hud/options.zig`)
AA, vsync, fullscreen and autosave, stored in `options.cfg`. It is written
when one changes and kept across save loads. Main applies `Game.opts` when
it differs from what is in effect.

## Roadmap
**Done:**
- Foundations: engine, terrain, streaming, LOD + culling, GPU detail,
  loading screen, files in `%LOCALAPPDATA%\Parasymi`.
- Plants: plants + 7 species, ecology, confluence, celestial bloom +
  radiance.
- Structures: structures, footprints/floaters, root-digger, growth splines
  (every structure but the diamond), lineage structures (3 per lineage),
  halo + diamond structure + Celestial Defragmentation.
- Systems: research (18 nodes), research sapling panel, hand weaving,
  save/load, saved gardens menu + autosave, pause, fullscreen,
  anti-aliasing (MSAA/FXAA) + options panel.
- Look and feel: adjustable/free camera, sky, wolf anatomy and planes/fur
  passes, bloom post-processing, the wolf as one sculpted skinned mesh
  with procedural locomotion (planted feet, leg IK, springs).

**Next (vertical slice):**
1. ~~2–3 more per lineage~~ done as structures (the gardener's call)
2. ~~Research tree to ~12 nodes~~
3. ~~First world event (something that *happens*, not just a research unlock)~~
4. ~~One "wow" visual moment (sky shift at convergence)~~

Target: a stranger plays 2 hours and says "I want to see what happens
next."
