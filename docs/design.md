# Game design

What the game is and how its pieces play. Code names in backticks point at
where each rule lives. Looks are in [visual.md](visual.md).

## Premise
Player-centric Factorio-like automation game: magically infused plants
(parasitic + symbiotic lineages that converge, and a radiant/celestial
one). The player is a vine-wolf (the gardener) who starts from nothing and
grows a grand garden. 2.5D top-down 3D.

## Core rules
- No global resources: items live in the belly, structures or plants.
  Every plant is player-seeded and grows before use. Research is the
  Factorio-lab model (structures consume ingredients unit by unit).
- Plants never set seed: only a germinator weaves seeds (hand-weaving
  makes bulbs only, `craft.by_hand`). The germinator is the bootstrap,
  woven from fibre, grit and starlight, and the hub of automation: it
  weaves every recipe, seeds and bulbs (`craft.all`), and lets only what
  it wove go (`craft.woven`).
- Always open: lumenroot/thornleech seeds, conduits, sap caches,
  germinator; other species research-gated (vesper by Seed Splicing:
  essence + convergence essence + fibre).
- Uprooting a sown plant always gives its seed back (it stays put while
  the belly is full); a confluence gives nothing.
- Plants and structures share occupancy; footprints 1×1, 2×2 or floating.
  Floaters are reached (panel, feed, configure, unbuild) where nothing
  stands under them; nothing is sown or put under one.

## Base structures
- Conduit: pulls from behind, pushes forward; grows a side root to a plant
  beside/behind it and harvests it once the root arrives.
- Sap cache, germinator, arsthraxia (research).
- Root-digger (1×1 on soil/moss, "Deep Rooting"; 3 fibre + 2 grit + 1 ley
  shard): digs an adjacent node 1 item/4 s into an 8-item buffer, feeds
  neighbours, idles with no node.
- Put down, structures grow (`Def.grow`: germinator 6 s, arsthraxia 8, sap
  cache and digger 4, conduit 1.5) and do no work until grown.
- `Def.carrier` marks item carriers (conduit, braided conduit): they face a
  way, chain, and hand on to each other through `receive`
  (`Structures.handIn`, at the edge an item comes in by); carriers are
  never pulled from. `gives` says what a structure lets go (a braid pulls a
  different kind per lane); `Structures.outputs` walks everything that may
  leave one (its `output` first, then each other kind it holds and
  `gives`). `st.handOff` feeds a producer's `outputs` to a non-carrier
  neighbour beside any side of its footprint (each the first it wants);
  `st.handOffWith` reaches `.range` steps out and hands up to `.amount`,
  nearest first.

## Lineage structures (2nd tier, each its own research)
### Symbiotic (woven, green, amber sap)
- Loomfern (1×1 soil/moss, "Living Looms"): weaves fibre, 1/12 s unfed, 4
  per essence fed at 3 s each; holds 12.
- Gathering crown ("Living Looms"): roots out to every plant within 2 tiles
  (one root per plant's own tile) and gathers what is ripe, one unit/1.5 s
  in turn; holds 12.
- Braided conduit ("Braided Roots", woven from 4 conduits): 4 lanes, one
  kind each, 3.5 tiles/s; joins and turns with conduits.

### Parasitic (pale, alien, `parasite_kit`)
- Lithophage ("Lithophagy"): drains grit/ley nodes on the 8 tiles round it
  (one per 3 s) into a crystal in its crop (6 grit, ley shard = 3), sapped
  back out as 6 grit into its cup; fed ley shards only, so the grit it
  holds is what it sapped (the gardener's call: grit).
- Ganglion ("Lithophagy"): holds 8, hands one each 0.35 s round its sides
  in turn to whatever wants it, and to carriers not facing in: splits
  lines, feeds several germinators each what it needs.
- Sporecaster ("Spore Casting"): paired one way by configuring one then its
  partner (`pairs`, `Structures.pairStep` in its `configure` hook); spore carriers
  (free, 0.25 s apart, 5 of a kind) drift at 2.5 tiles/s, unlimited range,
  into the partner; home again if it is gone, hang over it while it is
  full. `Def.far`: its spores are drawn however far it stands.

## Parents and children
Any structure may depend on another (`Structure.parent`, held by tile and
floating, so it survives ids shifting): `Structures.spawnChild` puts one
down already a child (the polyp's diamond), `dependOn` adopts one if the
parent's `adopts(s, kind, have)` hook takes it (default: none; never a
loop), `detach` cuts it loose, `getParent`/`getChildren`/`getChild`/
`childCount` walk them. Uprooting a parent cuts its children loose.

Partners are peers (`Structure.partners`, up to `PARTNERS`, oldest first,
held the same way): a kind that declares `pairs:Pairs` pairs with its own
kind (or `.with`), one way (it sends there: the sporecaster) or both ways
(each is the other's: the driftbraid), with up to `.most` (default 1) at
once; one more lets go of its oldest, both ways that one lets go too.
`pairWith`, `unpair`, `getPartner` (the first), `getPartners`, `pairedTo`
(who names it); `pairStep` is the shared
configure handshake (`Structures.pairing`: the first configured waits, the
next is paired, the same one twice cuts it). Uprooting cuts its pairings.

## Convergent structures (3rd tier)
Each pair of lineage structures grown within `structures.MEET` (3) tiles is
a discovery (`meets` hook + `Structures.meetings`), opening its research.
Woven by a germinator only (`Recipe.germinator`) from the pair's bulbs + 2
convergence essence. The confluence stays the only convergent plant.
- Weftstone (loomfern + lithophage, WOVEN STONE): floating (its mesh
  carries `HOVER`, `Def.hover` 0), latches tendrils (emitted curves,
  `weftstone_tendril`) onto the nearest 6 grit/ley nodes within 2 tiles,
  draws one unit/2 s in turn into its bulb (12 grit, 4 ley), ionizes 4 grit
  + 1 ley into a ley crystal in 6 s, holds 8, hands them on.
- Driftbraid (braided conduit + sporecaster, BRAIDED DRIFT): paired both
  ways by configuring one then the other; sends what it is fed by spore,
  takes in what comes back, lets go only what came by spore (`kept` counts
  per kind).
- Monfris (weftstone + driftbraid, INTERWEAVING): 2×2; weaves only the
  advanced tier (`Recipe.advanced`, `craft.advanced`; the germinator's
  `craft.all` leaves it out): for now the diamond (from ley crystals). Fed
  by at most 6 Vultrixi (`monfris.TETHERS`, an advanced weave has at most 6
  kinds), by hand, or by conduits.
- Vultrixi (gathering crown + ganglion, SHARED NERVES): floating; configure
  it, then a monfris, to tether it (it becomes the monfris's child). It takes the ingredient of the weave at
  its place among the tethered, reaches a tendril into the nearest
  structure within 6 tiles that `gives` it (never a monfris or Vultrixi),
  pulls 1/s and sends it along its tether.

## Confluence (`game/convergence.zig`)
A mature symbiote and parasite within 2 tiles (or joined by a conduit
chain) root a 2×2 confluence beside them unless one already holds them.
Never sown; grows 1.5× the slower parent (`span`) in 4 stages; yields
convergence essence; mature, halves parasite drain within 3 tiles.
"Convergence Theory" only reveals its yield.

## Radiance (`species/bloom.zig`, `ecology.Radiance`)
- Celestial bloom: sown, floating (hover 3.2), yields nothing; radiates a
  3.5-tile field. Seed: 3 starlight + 1 ley shard + 2 essence.
- Blooms within 10 tiles link into networks; a network radiates when it
  holds a mature bloom (then all its blooms do), so uprooting a linking
  bloom cuts off those beyond it.
- Plants with `needs_radiance` (vesper, for now) halt and wither
  (0.06 HP/s) outside every field.
- Worked out per tick from blooms only (pairwise links, then each radiating
  bloom's tiles). Hover panel shows RADIATING/DARK + links, DRAWING
  RADIANCE/WITHERING.

## Halo and diamond (`structures/polyp.zig`, `halo.zig`, `diamond.zig`)
- A polyp (1×1, grows 6 s; 4 fibre + 3 essence + 2 starlight + 2 ley
  shard) checks each tick for grown blooms (HP > 0.5) on the four points 5
  tiles out E/S/W/N.
- Then, once ever, over 5 s: the blooms spiral in to where their cross of
  beams meets and fold to buds, while a diamond gathers there and projects
  the halo (see [visual.md](visual.md#halo)). As they meet they are
  consumed, a flash spreads and a DIAMOND structure (floating there,
  `Def.floating`/`hover`/`bare`) is put down; the polyp stays as it is.
- Ring field: radius 5 while forming; diamond field: radius 7. Points
  without a grown bloom dim their arcs to 0.3.
- A diamond discovers `.diamond`, opening CELESTIAL DEFRAGMENTATION, which
  lets diamonds be woven and put over any dry tile (they gather as they
  grow, then flash). The diamond is the world event's future launch point.
- Demo: west of the garden, the fourth bloom finishes ~20 s in.

## Research panel (T, `hud/research.zig`)
A sapling in soil, laid out from the prerequisites alone, so it never needs
placing or adjusting.
- Adding research: one file in `research/` + one line in `techs`. Set
  `.branch = true` on a big step (new structures, species, an event);
  anything else is a leaf. No coordinates, no sizes.
- Host: a node grows on the nearest branch up its *first* prerequisite
  chain, else on the trunk (so list the prerequisite it belongs to first).
- Along a host, children sit one slot apart by depth (longest prereq chain;
  a `needs` discovery counts 1), then declaration order; leaves and
  branches each alternate sides. Stems are one slot longer than their
  children (branches ≥ `BRANCH_MIN`) and bend toward the light.
- The fully grown, still tree is fitted to the panel (`fit`, slot ≤
  `max_slot` px), so nothing moves: the sapling starts small at the soil
  and fills the panel as research is done.
- Known: grown leaf / branch with a violet bloom at its tip. Open: gold bud
  (glows; while studied a leaf unfurls and a branch shoot extends with
  progress). Locked: dim dormant bud where its host has grown, else
  hidden. The trunk reaches `TRUNK_LEAD` past its highest open/known node
  (eased, `play.Game.sapling`) and thickens with √(known).
- Wind sways stems from the base (children follow), leaves flutter.
  Hovering a node (`Game.pointed`) shows its card (cost, progress, or what
  it is DORMANT on); else the studied one. Click selects.
- The test asserts hosts come before what grows on them and no two nodes
  crowd (> 0.5 slot); if it fails after adding research, fix the layout
  rules there, never hand-place a node.

## Saves, options and the gardener's folder
- The gardener's folder (`game/home.zig`): `%LOCALAPPDATA%\Parasymi` holds
  `parasymi.cfg`, `controls.cfg`, `options.cfg` and `saves/`, all made on
  startup when missing (`home.open` first in main; `home.dir()` for every
  file); no cfg ever lives beside the game. The two stock cfgs are tracked
  in `src/cfg/`, embedded (`@embedFile`) and written with a
  `# stock <hash>` first line: an untouched copy is replaced when the
  repo's changes, an edited one is kept and read over the built-in (what it
  lacks falls back). So `src/cfg/` edits reach the game unless the AppData
  copy was hand-edited. Old `options.cfg`/`parasymi.sav` beside the game
  are copied in once.
- Save (`game/save.zig`, `saves/<name>.sav`): the world regenerates from
  the seed; only the gardener's changes are stored. Written to a `.tmp`
  then renamed over. `Game.slot` is the garden being played (F6 saves into
  it, else asks its name; quit saves into it, else into the autosave);
  names are only ever typed by the gardener (`save.Name.typed`), and a
  save can be deleted from the menu; `Request` carries
  saves/loads/listing/deletes to main. Autosave (always `autosave.sav`) every
  `Options.autosave` minutes of play (default 5, options panel:
  never..60). Bump `VERSION` when a stored layout changes (the fingerprint
  checks sizes only).
- Each start grows a fresh world (seed logged, kept in its saves);
  `--seed=` repeats one; test gardens use `play.DEFAULT_SEED`.
- Options (`game/options.zig`, `hud/options.zig`): AA, vsync, fullscreen,
  autosave, stored in `options.cfg` (written when one changes, kept across
  save loads); main applies `Game.opts` when it differs from what is in
  effect.

## Roadmap
Done: engine, terrain, streaming, plants + 7 species, ecology, structures,
footprints/floaters, research (18 nodes), hand weaving, save/load, pause,
fullscreen, root-digger, adjustable/free camera, sky, wolf anatomy and
planes/fur passes, confluence, celestial bloom + radiance, GPU detail,
LOD + culling, bloom post-processing, research sapling panel, halo +
diamond structure + Celestial Defragmentation, anti-aliasing (MSAA/FXAA) +
options panel, the wolf as one sculpted skinned mesh with procedural
locomotion (planted feet, leg IK, springs), saved gardens menu + autosave,
files in `%LOCALAPPDATA%\Parasymi`, loading screen, growth splines (every
structure but the diamond), lineage structures (3 per lineage).

**Next (vertical slice):**
1. ~~2–3 more per lineage~~ done as structures (the gardener's call)
2. ~~Research tree to ~12 nodes~~
3. First world event (something that *happens*, not just a research unlock)
4. One "wow" visual moment (sky shift at convergence)

Target: a stranger plays 2 hours and says "I want to see what happens
next." "Celestial / beyond comprehension" is the next phase's look.
