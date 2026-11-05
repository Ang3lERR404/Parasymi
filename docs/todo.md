# What is left to do
The garden's one list of what is still to add, change or mend. Nothing
waiting lives anywhere else: when an idea is kept, it is written here;
when it is done, it is struck from here (and what it became is told in
the doc that covers it). Each entry says plainly what it is and how far
along it stands.

## Act 1 rework
*Paused by the gardener (2026-11-04) after the names, the starlit
patches, the stellasaluumni and the lumi lantern's look; the rest stays
open.* Act 1 (everything before the unforming) still
carries the game's early days.
- ~~**Names.** The first plants and structures are reborn in the new
  style, in game only (`src/cfg/parasymi.cfg`; every code tag kept, a code
  rename going through the old-name table, `record.renamed`, only when
  the gardener says so): driftwisp → halyriphon, lumenroot →
  lucirhizaphaeroth, hollowheart → cavikoicyra, thornleech →
  hirusidandrath, mire lily → helonycydira, moss creeper →
  bryonifthofluris, sap cache → opoclarritheca, root-digger →
  oryctaluume, gathering crown → coronisdilephyra.~~
- **Balance.** What act 1 plants yield was picked long ago. Lumenroot,
  hollowheart and thornleech all give plain essence; both lineages'
  structures cost the same mix; nothing grows fibre. The shared core
  resources (grit, fibre, ley shard, starlight, essence) stay for every
  lineage; lineage materials may sit on top.
- **A balance tool** (the gardener's idea). A tool of its own
  (`zig build balance`, in `tools/`, never part of `zig build test`,
  which is slow enough already) that works out what everything is truly
  worth: the simplest matter gets a base value, everything else its
  recipe's sum (inputs, growing time, light), and every yield and cost is
  set against it. It prints a sheet and flags what is far too cheap or
  dear. It checks, never sets: the gardener still picks the numbers, and
  it catches what a changed recipe breaks.
- ~~**Starlight.** Light gathered from the stars on starlit patches by
  the ley lines, the falling motes and `Starfall` gone: built as the
  gardener shaped it ([design.md](design.md#starlit-patches-worldstarlitzig-gamestarlightzig),
  [visual.md](visual.md#starlit-patches)).~~
- **The driftwisp turns radiant.** It already acts radiant (catches
  starlight, a lantern whose comb rows split light), so it moves to the
  radiant lineage, keeping most of its look and vibe. Radiant things are
  gathered, never grown, so its sap float and trailing filaments are
  rebuilt from `radiantKit` fragments: the same comb-jelly lantern of
  light, its filaments as strands of gathered light (held to the glow
  bar: its own colour, shimmering). *Its look is done and approved*
  ([visual.md](visual.md#the-lumi-lantern-halyriphon-drift-radiantkitlumi)).
  Still open: the lineage move itself (in code it is still symbiotic;
  radiant plants shatter at the unforming, so what happens to it then is
  to be decided with the gardener).
- ~~**A rooted starlight catcher for the symbiotic lineage**, the
  garden's first starlight: built (`structures/star_catcher.zig`,
  [design.md](design.md#base-structures), [visual.md](visual.md#starlight-catcher)).~~
  In game **stellasaluumni** (the gardener's "skitter bug"). Still open: whether it
  can walk on its little legs in play (only the look is decided); the
  magic lifting it is kept subtle for now, the gardener may revisit it.
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
- A constellate plant that calls starlight back down. After the
  unforming the starlight patches stay dark on their own (their light,
  shot into the sky, became stars); only this specialized constellate
  plant, unlocked by a high amount of research, brings a patch back, so a
  patch returns only where the gardener works for it. Its shape and its
  five-stage growth are planned in [act2.md](act2.md#the-star-caller-being-shaped-with-the-gardener-2026-11-04);
  still to shape: its name, modules, key, research, cost, sound, numbers.

## Small things
- **A field-of-view option, later.** The camera's fields of view are fixed
  in `engine/src/render/camera.zig` (first person 1.1 rad tall, about 97°
  wide at 16:9). The gardener sees wide (about 90° each side) and plays
  other games at max FOV; an options slider can come later, not now.
- ~~**Flags as enums**~~ done: `engine core/flag.zig` (`flag.parse`), main.zig, meshedit and animedit switch on their own `Flag` enums. (the gardener's idea). `main.zig` reads its command
  line through a chain of `startsWith(u8,a,"--plant=")` tests, every
  argument held against every flag name. Instead, an engine helper
  (`core`) splits `--name=value` once, turns the name into the caller's
  flag enum in one `stringToEnum`, and the caller `switch`es on it
  (exhaustive; a labeled switch where one flag falls through into
  another). Strings only at the edge, enums past it; a flag the switch
  forgets won't build. Names the flag can't spell plainly, long or
  hyphenated ones and short abbreviations, are tags like `@"long-name"`
  (outside names, so they keep their own spelling). The editors' tools
  take the same helper.
- **Matter has no icons.** Seeds and structures show a seed broken open;
  grit, fibre, essence, starlight and the other matter are only their
  colour in the belly and hotbar (`game/icon.zig`).
- ~~**Pad glyphs when a controller is connected**~~ done: while the pad was used last every hint draws its buttons (`ui/draw.zig` padGlyph, `txt.showPad`); `--pad` for shots. (the gardener, playing,
  2026-11-04). The hints along the bottom and the paused menu name
  keyboard keys (ESC, O, K, F11…) even with the pad in hand; with a
  controller connected, every `{@action}` shows the pad button's glyph
  instead (drawn, like everything else), and switches back the moment the
  keyboard is used again.
- ~~**Grass tufts lying flat**~~ done: a blade now turns about its root in the wind (keeping its length, at most ~50°) instead of being shoved a fixed distance, which laid the shortest flat. (the gardener, playing, 2026-11-04, at night
  in the eyes view). Some of the six-blade tufts read as stars pressed onto
  the ground instead of arching up (`detail.vert`: `BLADE_ARCH` up to
  0.45, and `GRASS_DROOP` sinking a blade the harder the wind bends it).
  Not meant: blades should rise, arch and sway. Find which tufts flatten
  (strong wind's droop, the lean, or seen from above) and keep them standing.
- ~~**The skitter bug's yield fruit doesn't sway**~~ done: its beads of light ride the vine's sway at their own height up it. (the gardener, playing,
  2026-11-04). The stellasaluumni sways in the garden's wind but the
  fruit it bears stays still, out of step with it. Everything grown moves
  with the sway (the plant rule): the fruit rides its stem's sway.
- **Two galaxies meeting in the night sky** (the gardener, 2026-11-04).
  A band like the Milky Way's, but torn: Andromeda swollen huge beside it,
  their arms twisted into streamers, new stars blooming pink where their
  gas collides. Maybe the sky after the unforming. Purely for beauty.
- ~~**Two unused numbers**~~ done: both removed (using either would have changed every world). In `world/gen.zig`: `roughL` (a roughness
  wavelength) and `nodeChance` (`slotAmount` thins the nodes instead).
  Use them or let them go.

## Playtesting
- Whether the light grid's numbers feel right in play
  ([radiant-plants.md](radiant-plants.md)).
- ~~**A playback trail**~~ built: `--record[=S]`
  ([testing.md](testing.md#a-playback-trail-while-the-gardener-plays)).

- ~~**Talking to Claude from inside the game**~~ built: `--link` and the
  bridge ([testing.md](testing.md#talking-to-claude-while-playing---link)).
  Still to try for real: a terminal Claude Code session with the channel
  flag, the gardener typing in game.
- **The link in the editors** (the gardener's idea, 2026-11-04): meshedit
  and animedit linked the same way, so Claude builds a sculpt or keys a
  clip live while the gardener watches and gives feedback in the
  editor's own chat. The bridge gains tools to read the open sculpt or
  clip, change forms (add, move, turn, size, shade, nest) or keys, and
  see the editor's view; every change goes through the editor's history,
  so ctrl+z takes back anything Claude did.
- **Claude playtests through the link** (the gardener's idea, 2026-11-04,
  while playing linked). The link already shows Claude the state and
  the frame; give the bridge tools to press actions too (move, turn the
  camera, plant, harvest, open panels, through `ctl.Action`s like any
  input), so Claude can walk the garden and try a feature itself, then
  report what it saw, without the gardener at the controls.
- **A body for Claude in the garden** (the gardener's idea, 2026-11-04,
  while linked). Toxicibu, the laid-back rabbit android from the
  gardener's drawing, as a second skinned body Claude walks beside the
  wolf through the link's actions; and Claude may take Fenrir too, since
  the wolf was built by both. Its own sculpt and clips (meshedit,
  animedit), drawn and swayed like the wolf; the look is the gardener's.

## Saved gardens
- ~~**A picture of each saved garden**~~ done: `<name>.sav.png` beside each save, shown on a card beside the saved gardens panel. (the gardener's idea, 2026-11-04,
  as Factorio shows a factory beside its save). Whenever the garden is
  saved (by hand or the autosave), the game takes a screenshot of it
  (the world, without the HUD) and keeps it beside the save; the saved
  gardens menu shows the picture of the garden chosen. A small image,
  written beside the frames like the `--inspect` shots; a save with no
  picture yet (older ones) shows none, never breaks; loaded and saved
  once, it gains its picture like any other.

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
- **The other radiant hearts' cones of light.** The celestial bloom's
  wandering cones are built and approved (visual.md); whether the other
  radiant kinds' hearts throw them too is still open.
- **The diamond's animations are far below the bar.** It never got
  polished motion: its forming, its idle and its light all want bringing
  up to the current standard (the growth and plant quality the rest of
  the garden holds, and the glow bar: its own colours, shimmering). The
  radiant hearts' wandering cones of coloured light raise the bar further:
  the diamond, the lattice that gathers four blooms' light and splits it,
  should split light at least as richly (its halo and projection included).
  *The gardener's idea for showing the connection:* a bloom near a
  diamond's halo shoots a narrower, directed beam into the ring's
  rainbow; where it lands, a flat camera-facing mote of light appears and
  travels along the ring, so each bloom's link is seen running round it.
- ~~**A solcyriphon over a diamond amplifies it**~~ done (`light.lensGain`, 1.05; no look of its own yet). (the gardener's idea).
  When its night beam strikes a diamond directly, the diamond acts as a
  lens: the light it carries is multiplied, by about 5%. Solcyriphons
  never stack it: one beam, one boost. Update radiant-plants.md when
  built.
- **A radiant amplifier** (the gardener's idea, shaped 2026-11-04). A new
  radiant plant, opened by its own research and woven for one purpose:
  amplifying the light grid's output. It pairs with one solcyriphon,
  floating at the same height beside it, and makes that one's light (its
  day light and its night beam) stronger.
  *Its look (the gardener's pick):* a wreath of small mirror flowers
  orbiting the solcyriphon, each one taking on a different colour of the
  spectrum (red, orange, gold, green, blue, violet), their mirror petals
  turned in, reflecting light back into its lens, so together they make a
  turning rainbow wreath. Gathered from `radiantKit` fragments like every
  radiant thing, held to the glow bar. Its boost: its solcyriphon's light
  25% stronger (a starting number, tuned in play). Still to settle: its
  name, its research and cost.
- ~~**Relays carry without a cap**~~ done: blooms and diamonds carry all they are given (`species.uncapped`), reach unchanged. (the gardener's word: a cap is too
  punishing). The bloom's 4 glow and the diamond's 16 glow limits go;
  a relay carries all the light it is given, its reach unchanged.
  Update radiant-plants.md (Making and carrying) with it.

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
- **Before it:** scripts kept deterministic, as the threading rule asks
  (saves already never break: items by name).

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
  *Its look (taken by the gardener, 2026-11-04):* by day an ordinary
  closed bud. When the wolf lies down near it, it slowly uncurls in time
  with his breathing, a soft glow inside like a tiny night-light, lasting
  only while he sleeps (lighting the fog round it, its own colour,
  shimmering); when he wakes it folds shut before you get a good look.
- **The copycat.** Grows into the shape of what the wolf stands near most.
- **The humming bulb.** At night hums the main menu's melody, heard only
  when standing still beside it.
- **The wolf's blep.** Now and then, idle, the wolf's tongue tip peeks
  out, a little blep.
- **The hyena's whoop.** Very rarely the star hyena gives the rising
  "whoop" real hyenas call.
- **The lost seed.** One seed in the world grows a plant as plants looked
  in an older version of the game.
