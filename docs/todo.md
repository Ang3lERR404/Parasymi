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
  monfris). The old names are to be reborn in the new style. A candidate:
  **halyriphon** for the repurposed driftwisp (not settled).
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
- **Fibre after the unforming.** The loomfern (symbiotic) weaves fibre
  out of essence, but no convergent plant makes it, so once the
  symbiotic lineage is gone only the fibre plant's nodes, gathered by
  hand, are left. *The answer being shaped:* a new convergent plant of
  the rain pools, one joined structure of two parts: reeds or flax rooted
  in the pool bed, growing fibre stalks, and at their feet the convergent
  lineage's pink flowers on lily pads, harvesting the fibre. Never a
  loomfern that lives through the unforming: that is the arsthraxia's
  alone.
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

### The gardener's first playthrough (2026-11-03)
*The rest is mended (the floater looked at, the sky's shaking, the light's
flicker and the lenses, what the wolf and the germinator weave); the sky's
hues are being chosen from samples.*
- **The sky wants a darker hue** by day; the iridescent beams don't show
  well against it.
- **The night sky wants darker hues** too: deepened and saturated, like a
  real night sky, so vibrant hues come through instead of a milky
  lavender-white. The fog takes its colour from the sky (`SKY_AIR`), so it
  deepens with it.
- **The radiant cores read white.** The glowing heart of each radiant
  plant with a core (the celestial bloom and the others of the radiant
  kit) clips to a burnt-out white; it should glow in the radiant lineage's
  rainbow (as its threads and halo already do, `filmHue`), and so should
  the glow it puts in the fog and the light it casts. Its exact rainbow is
  the gardener's to pick from samples.

## Act 3, far off
*A seed, nothing decided.* Evolved plants in space: the garden at last
reaching up into the sky it has looked at all along (starlight gathered,
living constellations, a hyena made of stars). Kept open on purpose.

## Mods
*An idea being shaped, far off.* Players make their own plants and
structures, simple or complex in what they do, as Factorio's Lua mods do.
- **Data** (items, weave recipes, costs, yields, timings) could live in
  `.zon` files read at start (`std.zon`); names become entries in a list,
  not types, since a running game makes no new types.
- **Behaviour** through an embedded language rather than one of our own:
  Lua (small, C, known from Factorio) or WebAssembly; simple plants maybe
  from building blocks ("takes essence, waits 5 s, gives fibre") with no
  code. One registry member, "modded", whose hooks call the mod's script.
- **A behaviour editor** beside meshedit and animedit, so most mods need
  no code: what a plant does built by hand and saved as `.zon`. Safe and
  deterministic by design (a mod does only what its blocks can). All three
  feels blended: rules snap on in order like Scratch, wired to each other
  like a node graph, and drawn as a growing stem, each rule a leaf or bud
  ("when it holds 3 essence" sprouting "weave 1 fibre"). Lua stays the
  far-off expert road for what the blocks cannot do. The game's own
  structures' behaviours offered as ready-made blocks too, to mix and
  match (a loomfern's weaving with a gathering crown's gathering).
- **Looks** from sculpts (`.mesh`) and clips (`.anim`), which the game
  already reads at start; modded plants still keep the plant rules
  (growing, sway, stamens).
- **Safety:** a mod reaches only other mods and its own `mod-data` folder
  in the game's AppData folder (`%LOCALAPPDATA%\Parasymi\mod-data`); no
  other files, no network. Lua's own `io`/`os` left out, a file call of our
  own that refuses any path outside `mod-data`.
- **Before it:** saves that never break (items by name), and scripts kept
  deterministic, as the threading rule asks.

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
- **Symbiotic and parasitic** (the same tier): they work the same; only
  their look differs, yin and yang. The early game stays gentle, so
  neither costs or punishes more than the other. The symbiotic one, a
  curling tendril, cups the item like a leaf holding dew and lays it in
  softly; the parasitic one, a quick pale feeler, snaps it up and flicks
  it in, lively, never cruel.
- **Convergent:** the two braided together, a tendril and a feeler taking
  turns, one cupping, one flicking; so faster than either alone.
- **Constellate:** picks the kind and the lane and reaches farthest. No
  arm: a small web unravels the item into fragments that drift into the
  stream and reform inside the lane.
- Still to shape: how the base one looks.

## The radiant lineage's forming sound
*Direction approved, not built.* Fantasy mixed with sci-fi: real glass,
bells and choir (never small synth tones, which read comical), shaped in
strange ways. Soft, in D Lydian, kept apart from the arsthraxia's glass
whorls and bell bloom.
- **Each fragment arriving:** a glass tink, heard swelling up *reversed*
  before it lands, light arriving ahead of the thing; the tinks climb a
  D Lydian chord, so a forming plays a small arpeggio. A quiet echo of the
  unforming's climbing bell per shard, so that moment plays back something
  heard all game.
- **The threads of light:** a bowed-glass hum, a finger round a wine
  glass, slowly phasing like light through a prism, growing as threads
  join.
- **Whole:** a soap-bubble shimmer and one breath of far choir ("ooh"),
  breaking into a fizz of crystal grains that scatter and fade.

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
- **The wolf's blep.** Now and then, idle, the wolf's tongue tip peeks
  out, a little blep.
- **The hyena's whoop.** Very rarely the star hyena gives the rising
  "whoop" real hyenas call.
- **The lost seed.** One seed in the world grows a plant as plants looked
  in an older version of the game.
