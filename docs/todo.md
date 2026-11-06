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
  ~~The lineage move~~ done: radiant in code (`species/driftwisp.zig`,
  its symbiotes' sap look kept), and it shatters at the unforming (the
  gardener: "it shatters too").
- ~~**A rooted starlight catcher for the symbiotic lineage**, the
  garden's first starlight: built (`structures/star_catcher.zig`,
  [design.md](design.md#base-structures), [visual.md](visual.md#starlight-catcher)).~~
  In game **stellasaluumni** (the gardener's "skitter bug"). ~~Whether it
  walks~~ decided (the gardener, 2026-11-05): it stays rooted, "easier to
  debug until we have decently established dev tools"; its legs only
  twitch and fidget now and then (`Def.fidget`, part.vert `PART_FIDGET`).
  Walking may come back once the dev tools are better. The
  magic lifting it is kept subtle for now, the gardener may revisit it.
- **Fibre after the unforming.** The loomfern (symbiotic) weaves fibre
  out of essence, but no convergent plant makes it, so once the
  symbiotic lineage is gone only the fibre plant's nodes, gathered by
  hand, are left. *The answer being shaped:* a new convergent plant of
  the rain pools, one joined structure of two parts: reeds or flax rooted
  in the pool bed, growing fibre stalks, and at their feet the convergent
  lineage's pink flowers on lily pads, harvesting the fibre. Never a
  loomfern that lives through the unforming: that is the arsthraxia's
  alone. *Its name* (the gardener, 2026-11-05): **Lincalamnenypherohiem**
  (lin- flax, calam- reed, nem- thread, nymph- water lily, hiem- winter).
- **The parasitic side.** It has one species and three structures; it needs
  more. *Decided* (the gardener, 2026-11-05: "yes, pulse"): **the Pulse**,
  a mimosa-like heart, is the parasitic structure that lives through the
  unforming by becoming convergent, mirroring the arsthraxia. *Its role:*
  it quickens (plants within its beat's reach grow faster, a pace-setter)
  and it flinches like a mimosa (when something harms the garden nearby it
  snaps shut and guards it). It pumps no items: the injectors do that.
  ~~Still to shape: what counts as harm~~ *shaped* (the gardener chose
  both): **drought**, when the ground near it dries it snaps shut and
  holds its moisture, slowing the withering round it until rain returns
  (as a real mimosa folds to save water); and **the wolf's touch**,
  brushing past it folds it for a moment, pure charm with no game effect
  ("it's nice for a game to have personality behind it, all the little
  things count"). More may follow.
  *Its look, shaped as a chin wag* (the gardener, 2026-11-06; a first
  draft sculpt in `src/mesh/thepulse.mesh`: parasite cage, sap heart,
  mimosa fronds, pink pom-poms). The feeling: a beating heart, uncannily
  like a real one, alive and alien. The heart close to a real heart, so
  it reminds the player of their own, but never directly: something
  familiar they can't quite place: a real heart's lean and fullness, its
  great vessels becoming the fronds' stems arching from its top. The five
  strands hug it like its veins, beating with it, but latched round it
  too, claiming it as their own (the parasite holding the heart). The
  heart is a symbiote's, taken: that is what gives it its plant look, and
  the two beat together (already one before the unforming makes them
  convergent). It looks withered, wrinkled, almost dry, but not: still
  alive under it, shown both ways (the gardener: "quite brilliant"):
  *the flush*, at rest a dried fig, dusty grey-green and creased; each
  beat it swells, the creases pull nearly flat and a living green
  spreads from its middle, then it sinks back dry (what you see from
  across the garden); *the sap in the folds*, its skin matte throughout
  but thin threads of sap deep in the creases catch the light, glinting
  as the beat opens and closes them (the secret you find up close).
  *Its roots and stem* (the gardener's picture, no bulb): pale vein-like
  vines push out of the ground and spread over it in a small patch, then
  gather into an uncanny spiral stem, curling and weaving up and up; at
  the top, held between the roots' clutches, sits the heart (the same
  pale strands that rise as the stem latch round it). *The clutch*
  (chosen, a takeover still happening): five thick strands from the stem
  grip the heart from below like fingers; from between them five thin
  tendrils creep on over it as a closing net, gathering at its top and
  rising as the vessels that arch into the parasite's lilac fronds; a
  few of the heart's own old leaves still poke out between, withered,
  curled, brown-green, what is left of the symbiote. At the unforming
  the net closes whole and they become one (convergent).
- **The loss should sting.** The more act 1's plants helped, the harder
  their death at the unforming should hit. *The shaped answer* (the
  gardener, 2026-11-05): after the unforming, faint ghost outlines of the
  gardener's old plants linger where they stood and fade over a day (the
  more a plant helped, the longer or clearer it lingers); and what leaned
  on act 1's plants falters until it is rebuilt. Not built yet.

## Act 2
*Underway.* See [act2.md](act2.md).
- The wolf becoming the tree: already made of wood and vines, he takes
  root and becomes a tree himself, the garden's tree (never merging into
  another), step by step as
  [act2.md](act2.md#when-it-happens) has it. ~~How it is set off~~
  decided there: after the storm, the player chooses when, never told
  what follows, offered as one innocent prompt during a storm (its words
  still the gardener's to pick); today only `--act2` begins act 2.
- Animation as the constellate parts drift together and merge.
- The constellate lineage is in the game behind its own flag; it still
  has to join the garden proper.
- Act 2 keeping the hyena to the convergent and constellate lineages
  alone. By hand he weaves only the five constellate parts today
  (`craft.byHyena`). ~~How the convergent lineage serves him~~ decided
  ([act2.md](act2.md#the-convergent-lineage-his-hands)): his hands, its
  weavers weaving for him; constellate things never feed on it. Not
  built yet, nor the dish ([act2.md](act2.md#the-dish-gathering-the-scattered-starlight))
  or convergent flowers turning to face him.
- The constellate lineage has no studies yet, so no look for its nodes
  on the research tree ([research-tree.md](research-tree.md)).
- A constellate plant that calls starlight back down. After the
  unforming the starlight patches stay dark on their own (their light,
  shot into the sky, became stars); only this specialized constellate
  plant, unlocked by a high amount of research, brings a patch back, so a
  patch returns only where the gardener works for it. Its shape and its
  five-stage growth are planned in [act2.md](act2.md#the-star-caller-being-shaped-with-the-gardener-2026-11-04);
  still to shape: its name, modules, key, research, cost, sound, numbers.
- **Veils of light for the heart's rose** (the gardener, 2026-11-06, from
  Grey Goo's Shroud, `shots/capture/1794004494`). Off the rose's petals
  hang see-through veils of pale blue light trailing down to the ground:
  sheer curtains made of many fine glowing threads, a few brighter strands
  running through them, rippling and drifting slowly like a jellyfish's
  trailing arms or an aurora, never still. Its kin seen on the same
  structure (`1794003654`): fine wisps rising and curling out of its
  glowing heart, and light pulsing through the veins of its petals.

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
- ~~**Matter has no icons.**~~ done: `game/matter.zig` draws each as what it is; a test holds every item to an icon of its own. Seeds and structures show a seed broken open;
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
- **Lights read against the glow bar's reasons** (the gardener and Claude,
  2026-11-06). White has no colour of its own and punches a hole in the
  saturated night; the brightest spot is where the eye lands; movement
  catches it most; yellow against the night is a lit window, warmth the
  eye walks toward. Held to that, the shaders were read through and these
  read wrong, in order:
  1. ~~The final tone curve~~ done: `composite.frag` `shoulder` rolls off by
     the brightest channel and scales the rest with it, so a glow dims
     keeping its hue (the gardener, side by side: "oh my God it does").
  2. ~~A light trail's head~~ done: `PART_TRAIL` keeps its own colour to the
     head (it was mixed half to white where it moves).
  3. ~~Still lights~~ done: the solcyriphon beam's lights and a crown's shed
     light breathe (`m.shimmer`, engine core/math, now shared with the
     plants' crown glows).
  4. ~~Lightning's white-hot core~~ done: `PART_SPARK`'s core is pale
     violet, seen sparking in a burst (`--burst`, docs/testing.md). The
     sun keeps its white, the one source every colour comes from.
  5. The halo's outer band washes half to white: looked at again once the
     curve keeps colour.

## Playtesting
- Whether the light grid's numbers feel right in play
  ([radiant-plants.md](radiant-plants.md)).
- ~~**A playback trail**~~ built: `--record[=S]`
  ([testing.md](testing.md#a-playback-trail-while-the-gardener-plays)).

- ~~**Talking to Claude from inside the game**~~ built: `--link` and the
  bridge ([testing.md](testing.md#talking-to-claude-while-playing---link)).
  Still to try for real: a terminal Claude Code session with the channel
  flag, the gardener typing in game.
- ~~**The link in the editors**~~ done: `--link` in both, `tools/editlink.zig`, the bridge's `editor_document` and `editor_edit` ([testing.md](testing.md)). (the gardener's idea, 2026-11-04): meshedit
  and animedit linked the same way, so Claude builds a sculpt or keys a
  clip live while the gardener watches and gives feedback in the
  editor's own chat. The bridge gains tools to read the open sculpt or
  clip, change forms (add, move, turn, size, shade, nest) or keys, and
  see the editor's view; every change goes through the editor's history,
  so ctrl+z takes back anything Claude did.
- ~~**Claude turns the editors' camera**~~ done: the bridge's
  `editor_view` (home, focus a form, at, dist, yaw, pitch, zoom, pan),
  answered with the frame ([testing.md](testing.md)). (the gardener's
  idea, 2026-11-05, while their mouse was out of batteries.)
- **The pad in the editors** (the gardener's find, 2026-11-05: the mouse
  out of batteries, the pad did nothing). meshedit and animedit answer
  only the mouse and keyboard; give them the pad as the game has it
  (orbit and zoom on the sticks, select and the toolbar's buttons by
  `ctl.Action`s), never the Xbox or Share buttons.
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
- **A lensed diamond's shimmer** (kept for later, the gardener 2026-11-05:
  "interesting idea, save for later"). While a solcyriphon's beam makes a
  diamond a lens (`light.lensGain`), a faint extra shimmer runs through its
  facets, its own colour, never white, so the 5% shows.
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
  25% stronger (a starting number, tuned in play). *Its name* (the
  gardener, 2026-11-05): **Iridauxlariphon** (irid- rainbow, aux-
  strengthen, -iphon the radiant ending). Still to settle: ~~its name~~,
  its research and cost.
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
- ~~Still to shape: how the base one looks.~~ *Its look* (the gardener,
  2026-11-05: "a mix of all 3"): a root knuckle pushes up out of the soil
  and bends toward the lane; at its tip a single-leaf sprout whose leaf is
  a seed pod. The pod splits open to catch the item and closes round it.
  The pod's tip is a hollow thorn, like a nettle's stinging hair: it
  pierces the conduit's bark, the pod squeezes the item through as a new
  swelling on that lane's strand, the thorn draws out and the bark seals.
  Plain and humble, from before either lineage. *A conduit's two lanes*
  are two strands of its weave (left and right): items swell along their
  own strand inside the root, never sitting on top (the gardener: "that's
  perfect").

## The radiant lineage's forming sound
*Built (sound/forming.zig), waiting for the gardener's ear. With several gathering at once only the nearest is heard (the gardener: "only the nearest one really").* Fantasy mixed with sci-fi: real glass,
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

## Modular sound
*The gardener, 2026-11-05. Kept, not to build yet.* Sound is built the
way the garden is: every part has its own note, and when parts join their
notes join into a chord, so a whole thing sings as one. The constellate
dish, stem and core each hum a note and, snapped together, sing as one
flower; the radiant forming sound's climbing tinks already do this. The
unforming theme's held D is the root under it all, the world's own note
as its light becomes stars.

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
