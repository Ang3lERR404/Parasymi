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
- **Monfris** (weftstone + driftbraid, INTERWEAVING): 2×2. It weaves only
  the advanced tier (`Recipe.advanced`, `craft.advanced`; the germinator's
  `craft.all` leaves it out). For now that is the diamond, from ley
  crystals. Fed by at most 6 Vultrixi (`monfris.tethers`, because an
  advanced weave has at most 6 kinds), by hand, or by conduits.
- **Vultrixi** (gathering crown + ganglion, SHARED NERVES): floating.
  Configure it, then a monfris, to tether it (it becomes the monfris's
  child).
  - It takes the ingredient matching its place among the tethered.
  - It reaches a tendril into the nearest structure within 6 tiles that
    `gives` it (never a monfris or Vultrixi).
  - It pulls 1/s and sends it along its tether.

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

## Halo and diamond (`structures/polyp.zig`, `halo.zig`, `diamond.zig`)
- **The polyp:** 1×1, grows in 6 s; costs 4 fibre + 3 essence + 2
  starlight + 2 ley shard. Each tick it checks for grown blooms (HP > 0.5)
  on the four points 5 tiles out east, south, west and north.
- **The event, once ever, over 5 s:** the blooms spiral in to where their
  cross of beams meets and fold to buds. Meanwhile a diamond gathers there
  and projects the halo (see [visual.md](visual.md#halo)).
- **As they meet:** the blooms are consumed, a flash spreads, and a
  DIAMOND structure is put down, floating there (`Def.floating`/`hover`/
  `bare`). The polyp stays as it is.
- **Fields:** the ring's field has radius 5 while forming; the diamond's,
  radius 7. Points without a grown bloom dim their arcs to 0.3.
- **What it opens:** a diamond discovers `.diamond`, opening CELESTIAL
  DEFRAGMENTATION. That lets diamonds be woven and put over any dry tile
  (they gather as they grow, then flash). The diamond is the world event's
  future launch point.
- **Demo:** west of the garden, the fourth bloom finishes ~20 s in.

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
  `branchMin`) and bend toward the light.
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
3. First world event (something that *happens*, not just a research unlock)
4. One "wow" visual moment (sky shift at convergence)

Target: a stranger plays 2 hours and says "I want to see what happens
next." "Celestial / beyond comprehension" is the next phase's look.
