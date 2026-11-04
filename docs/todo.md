# What is left to do
The garden's one list of what is still to add, change or mend. Nothing
waiting lives anywhere else: when an idea is kept, it is written here;
when it is done, it is struck from here (and what it became is told in
the doc that covers it). Each entry says plainly what it is and how far
along it stands.

## Act 1 rework
*Brainstormed, not started.* Act 1 (everything before the unforming) still
carries the game's early days.
- **Names.** The first plants and structures have plain-English names
  (lumenroot, driftwisp, hollowheart, thornleech, mire lily, moss creeper,
  sap cache, root-digger, gathering crown) beside the newer coined ones
  (astrocyme, heliocyra, halcyra, arsthraxia, vultrixi, nebularbor,
  monfris). The old names are to be reborn in the new style.
- **Balance.** What act 1 plants yield was picked long ago. Lumenroot,
  hollowheart and thornleech all give plain essence; both lineages'
  structures cost the same mix; nothing grows fibre. The shared core
  resources (grit, fibre, ley shard, starlight, essence) stay for every
  lineage; lineage materials may sit on top.
- **Starlight.** Light gathered *from* the stars, not stars falling (the
  falling motes and `Starfall` go). Starlit patches spawn where it is
  strongest, beside the ley lines (which gain patches too). By day a patch
  is a hint: a dark-blue field, little stars floating up. By night a light
  beams onto it in shifting rainbow and star motes drift down and vanish.
  The driftwisp is its catcher, floating over a patch, its dish catching
  the light at night. A patch never runs dry, but each has its own
  richness, like Factorio's oil fields. At the unforming each patch goes
  dark by shooting its light up into the sky.
- **Fibre.** It comes only from the fibre plant's nodes, gathered by
  hand; no plant grows it.
- **The parasitic side.** It has one species and three structures; it needs
  more. One parasitic structure could live through the unforming by
  becoming convergent, mirroring the arsthraxia (the Pulse, a mimosa-like
  heart, was proposed).
- **The loss should sting.** The more act 1's plants helped, the harder
  their death at the unforming should hit.

## Act 2
*Underway.* See [act2.md](act2.md).
- The wolf rooting into the tree: how act 2 begins in play (today only
  `--act2` begins there).
- Animation as the constellate parts drift together and merge.
- The constellate lineage is in the game behind its own flag; it still
  has to join the garden proper.
- Act 2 keeping the hyena to the convergent and constellate lineages
  alone. By hand he weaves only the five constellate parts today
  (`craft.byHyena`); how the convergent lineage serves him is not worked
  out.
- The constellate lineage has no studies yet, so no look for its nodes
  on the research tree ([research-tree.md](research-tree.md)).

## Small things
- **Matter has no icons.** Seeds and structures show a seed broken open;
  grit, fibre, essence, starlight and the other matter are only their
  colour in the belly and hotbar (`game/icon.zig`).
- **Two unused numbers** in `world/gen.zig`: `roughL` (a roughness
  wavelength) and `nodeChance` (`slotAmount` thins the nodes instead).
  Use them or let them go.

## Playtesting
- Whether the light grid's numbers feel right in play
  ([radiant-plants.md](radiant-plants.md)).

## Lanes and injectors
*Being designed.* Today a conduit carries one item at a time. Every
belt-like carrier (conduit, braided conduit, vultrixi tether, the
constellate tendril; not the sporecasters) is to have **two sides, like
Factorio's belts, each side a short row of items**.
- Items are put into a lane by **injector plants**, one per tier, each
  better than the last.
- **Base tier:** slow, one item at a time, into the lane it faces, and
  fixed to that lane.
- **Every tier above** can switch lanes and reach farther (what mods give
  Factorio's inserters, here in the game itself).
- Still to shape: what the symbiotic and parasitic ones do differently at
  the same tier, what convergent and constellate add, how each looks.

## Saves that never break
*Planned, not started.* Today plants, the belly, research, the weave queue
and wild flowers are saved as raw bytes, so a change to their shape refuses
old saves, and reordering items, species or research scrambles them
quietly. Structures already survive change (named-field `record`s). The
plan, one commit per step:
1. Save items, species and research nodes by name hash, not by number.
2. The belly and the weave queue as `record`s.
3. Research as `record`s: only what is known and its progress, by name.
4. Plants and wild flowers as `record`s, checking save time and size.
5. One last `version` bump, and a test that saves, changes a field and
   loads again.

Renames still need a small old-name → new-name table. Changing world
generation still moves the land under a save; only storing the land would
mend that.

## Hidden plants
*Ideas, kept to be talked over one at a time.*
- **The homage corner.** A nod to Magic Farm 2: Fairy Lands (Meridian93,
  2011), in Parasymi's own style, never its art. Three plants grow
  together in one secret corner of each world, each only rarely: a lotus
  whose later stem bears golden lotuses with pink ribbons and whose seed
  pod turns crystalline (radiant), a flytrap that grows an extra head and
  little closed mouths (parasitic), and a spindly plant of woven threads,
  a small flower where they meet, its aura hardening the flowers round it
  (symbiotic). Harvesting one rarely drops its seed; a seed found is kept
  for good, outside any one garden's save, and can be woven into any later
  garden.
- **The sleepy flower.** Opens only while the wolf sleeps beside it.
- **The copycat.** Grows into the shape of what the wolf stands near most.
- **The humming bulb.** At night hums the main menu's melody, heard only
  when standing still beside it.
- **The lost seed.** One seed in the world grows a plant as plants looked
  in an older version of the game.
