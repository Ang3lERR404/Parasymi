# The Unforming

The garden's first world event. Everything the wolf grew in act 1 ends
here: the radiant light breaks, the two old lineages die, the sky shatters
like glass, and out of what is left a strange seed falls. What survives is
what was already both lineages at once: the convergent.

Code: `src/game/unforming.zig` (the event), `src/game/research/unforming.zig`
(the study that starts it). Summary in [design.md](design.md#the-unforming-gameunformingzig-the-first-world-event);
looks in [visual.md](visual.md#sky); watching it in [testing.md](testing.md#the-unforming).

## The story (the gardener's account)
- A study unlocks once the **polyp** is planted. The polyp is convergent,
  woven by a **monfris** (or a germinator; never by hand).
- Learning it kills every **symbiotic** and **parasitic** plant.
- Every **radiant** plant glitches in and out of reality, then is gone.
- At the middle point of where they stood, a **seed** forms. It leads to
  the new lineage: the **constellate**.
- **Look up during it:** the sky shatters, the plexus spreading across the
  whole of it. The sun and moon disappear, and the world takes on an
  otherworldly glow.
- The **ley lines** seal up. The **ley shards** shatter into fine pieces,
  then disappear from reality too.
- The **stars** that fall at night shatter, all at once as it begins, and
  stop falling altogether.
- Afterwards only the **convergent** lineage is left. With it alone the
  wolf has to make the world **rain** and **storm**; only then does he
  root himself into the garden's tree, and act 2 begins.

## How it is reached
1. **Four blooms** round an empty tile form a halo, and a **diamond** is
   born over it. That opens CELESTIAL DEFRAGMENTATION.
2. A **polyp** (convergent) feeds on grown blooms and lets its first
   **drift flower** float free. That discovers `.driftFlower`.
3. THE UNFORMING can now be studied: after Celestial Defragmentation,
   30 units of 10 s, each costing 3 convergence essence + 3 starlight +
   1 ley crystal. It is a branch (a big step).
4. When it is learned, the log says **THE GARDEN HOLDS ITS BREATH**, and on
   the next tick the event begins with **THE RADIANT LIGHT BREAKS.
   EVERYTHING THE LINEAGES GREW IS UNFORMING**.

## What happens, second by second
Time is seconds since it began (`Unforming.t`). Each plant and structure
draws its own moment from its seed, so they go one after another rather
than all at once.

| t (s) | What happens |
|---|---|
| 0 | Every starlit patch shoots its light up into the sky (its searchlights turned upward, flaring and fading over 4 s), where it becomes stars, and stays dark. Every structure is sent `Msg.unform`: the arsthraxia evolves. The garden's music cuts dead; the world creaks and swells, as if about to break under its own weight. |
| 1.6 | One great deep horn: the beginning of the end. Under everything a rumble begins, masses fall and hit the ground all round, and a wall of choirs and strings rises. |
| 1.6 – 12.5 | The wall: bright, heavenly, suspended chords over a held D, never resolving, climbing chord by chord, dipping once, climbing again. |
| 8 – 12.5 | Fireworks rise whistling into the sky (the shards flying up) and never burst; the burning begins; trumpets ring out from 8.85 s. |
| 11.4 | One woman screams far off, in agony, almost joining the choir, never quite; the land echoes her. |
| 12.5 – 15.6 | It all falls slowly away while she sobs, into silence and a few rumbles of earth. |
| 0 – 6 | Radiant plants (bloom, vesper) begin to glitch, one after another. |
| +5 each | Each one glitches over 5 s: bands of it slip sideways and it blinks, cracks of its own light run over it cell by cell, and past halfway it breaks along them into large shards of its own film's colour that drift out and up, turning, and shrink away. At 60% through it sends 4 shards up, each trailing a ribbon of that colour; a glass snap and scatter of glints is heard. |
| 0 – 14 | Symbiotic and parasitic plants wither, each over 6 s (starting within the first 8 s): they dry out grey, bow over and curl, then crumble from the top down into flakes of ash, an ember along each edge as it breaks, lifting off downwind; dry crumbling is heard. The lineages' structures grow back down to nothing. What they held is lost. |
| 1 – 13 | The sky shatters from the zenith to the horizon, pane by pane, and the ley's violet glow floods in. |
| ~2.8 – 10 | The ley lines seal from their edges in, a bright seam closing, leaving scars of bare soil; a seam is heard humming shut, sinking an octave. |
| 10 | Sealed. Every ley shard node breaks (glass heard) into 7 violet crystals that drift up weightless; each at its own moment cracks and melts into a burst of violet motes. |
| up to 13.4 | The shards fly up (2.4 s each, swirling, ribbons behind them) to a point 14 m over the middle of where the radiant plants stood. A star of gathered light swells there as they arrive: a web of pale blue points and threads (as the sky's plexus) round a heart of light, turning slowly, flaring as each shard lands, each landing ringing a Lydian step higher. |
| 13.4 – 15.6 | The **strange seed** falls (2.2 s, faster as it goes), its star shrinking back into it, a comet's tail of light behind it; it whistles down through the falling music. |
| 15.6 | It lands: a ring of light rolls out over the ground from it (2.4 s, the halo's flash), motes flung up, and a great church bell tolls with a deep boom and the great taiko under it, soft glass over it, then the strings and choirs rise slowly into Dmaj7 with the G# and the garden's theme comes home on the bells: **OUT OF THE SHATTERED LIGHT, A SEED FALLS. IT DOES NOT TAKE ROOT**. The theme rings away; from 8 s after, the garden's music returns over 10 s. |
| 40 | The last drifting ley shard blinks out. The event's clock stops. |

The phases (`Phase`) are `waiting` → `shattering` → `falling` → `landed`.

## What dies, what stays, what changes
- **Gone:** every radiant plant (shattered); every symbiotic and parasitic
  plant (withered); every structure whose `Def.unforms()` is true. That
  means any lineage but convergent unless it `evolves`: the base
  structures, conduit, sap cache, germinator, root-digger, the lineage
  structures, and the diamond (its shards come loose, back the way they
  gathered).
- **Stays:** convergent plants and structures: the confluence, polyp,
  weftstone, driftbraid, monfris, Vultrixi.
- **Evolves:** the **arsthraxia** (`evolves=.convergent`). It is redrawn
  woven of both lineages (`arsthraxia_convergent.zig`), its flower two
  nested blooms floating over its calyx on thin tethers.
- **The sky, for good:** no sun, moon or stars. Violet veils and a
  drifting plexus on the dome, rose by day and deep blue by night. The key
  light becomes the glow overhead, a pale lavender by day so the garden
  keeps its colours under it, its shade violet; the air sheds half its
  haze (view.zig `shiftClear`), so it stays clear rather than purple.
- **The ley, for good:** sealed to soil (`gen.sealOf`); chunks streamed in
  later are sealed as they arrive (`Chunk.sealed`), their nodes simply gone.
- **No longer to be had:** starlight and ley shards.

## The strange seed
- It lands on the tile under where it fell, or the nearest free tile
  within 6 rings.
- It is a structure (`strangeSeed`), a crystal husk with a small web
  turning inside. Put down by the wolf it only lies there; it never
  plants itself.
- It is the first thing of the **constellate** lineage, and it only grows
  in act 2, planted by the star hyena (see
  [design.md](design.md#act-2-the-star-hyena)).

## What opens afterwards
- **Tanglehold** weaving (it takes the sap cache's place, twice the room).
- The **monfris** may weave what the unforming made convergent (the
  arsthraxia among them, `craft.loomEvolved`).
- **Drift flowers** put within 2 tiles of an evolved arsthraxia graft onto
  it as stemless branches, each making it study 0.6% faster.
- With the blooms gone, a **polyp** grows a drift flower on its own every
  90 s.
- Weather research (root wells, moss creeping, mire blooming) needs the
  unforming and the first rain.
- **Act 2**: once the wolf, with the convergent lineage alone, has made
  the world rain (`firstRain`) and storm (`firstStorm`, the storm spire),
  he roots himself into the garden's tree and the star hyena takes over.
  The rooting is not yet in the game.

## Where it is drawn
All dense work is on the GPU:
- radiant plants glitching and breaking: `PlantInstance.glitch.x`,
  plant.vert `unformAt`, plant.frag `unform`. The shards are cells of a 3D
  Voronoi (common.glsl `shardCell`) laid in the mesh as built (`v_rest`);
  a triangle whose corners lie in two cells is cut away (`split`), so
  shards never smear across the gap;
- the old lineages withering to ash: `PlantInstance.glitch.y`
  (`Unforming.witherOf`), plant.vert `crumbleAt` (finer cells, lifted
  downwind; drawn as points in the shadow pass, so a flake casts none),
  plant.frag `wither`;
- the sky and the closing ley lines: sky.frag, terrain.frag, common.glsl
  `SHIFT` (`SEAL_FROM`/`SEAL_SPAN` must match `sealFrom`/`sealSpan` in
  `unforming.zig`).

Each frame `unforming.draw` emits the flying shards (`unformShard`, in
their plant's film colour) with their ribbons (`unformTrail`, a `.trail`
part laid along each shard's own path by `emitCurve`), the seed, its star
(`unformStar`, a web of `.trail` light) and heart, the comet tail, the
landing ring (`haloFlash`) and motes, and the drifting ley crystals and
their melting, each lighting the air round it.

## How it sounds
`sound/unforming.zig` (`Unformed`) and its theme,
`sound/unforming_theme.zig` (`Theme`). The game sends `unforming.heard`
each frame while it runs (main.zig): its clock, how much is withering, and
the cracks and arrivals since last heard; the sound keeps its own clock
between frames.

**The theme** is scored from the gardener's own hearing of Little Inferno's
"Incident on the Other Side of the Wall": beautiful and chaotic at once, a
huge wall of sound, bright and consonant but sorrowful, never resolving,
building and building until a scream, then falling. The mixer
(`Sounds.musics`) cuts the day's and night's music to nothing within
0.25 s and plays the theme in their place, in the same stone hall, loud:
- **the creak** (0 to 1.6 s): grains of strain ringing in timbers and stone
  (130, 215, 480 Hz, sinking as they strain) over the strings' low D swelling;
- **the horn** (1.6 s): two low horns on D1 and D2, the timpani and the
  great taiko, dying away over 1.2 s;
- **the wall** (1.6 to 12.5 s): eight chords 1.45 s apart, all over a held
  D, two choirs (each its own voices) and the strings with a contrabass D1,
  violins soaring an octave over the sopranos, the great taiko under each:
  Dmaj9, E/D, A/D, Bm9/D, E/D (the dip), F#m7/D, E/D high, Dmaj7#11, the
  choirs from under a night's voice to twice it;
- **the trumpets** ring out on the wall's top notes from its sixth chord,
  the low horns holding the D;
- **the world breaking** (past the music's gate, so it goes on as the music
  falls): a deep rumble growing from the horn to the fall; masses falling
  (a deep body bent sharp by the blow, a crunch, gravel trickling), from
  0.8 to 3.5 a second, all round; burning from 8.5 s (crackle and a low
  roar); fireworks from 8 s, 1.8 a second, whistling up from about 450 Hz to
  2.5 kHz and never bursting; all of it kept under the music, and giving
  way to 40% while she screams, so she is heard over it;
- **the scream** (11.4 s): one woman, a Rosenberg glottal pulse shaking from
  cycle to cycle, through an open "ah": a breath in, a cry rising from A5 to
  30 cents over D6 (almost the choir's high D), holding 1.2 s, her voice
  breaking (rasp, every other cycle weak) partway through, then sinking to A4
  in a trembling sob, closing to "uh". Far off (darkened above 3.2 kHz, most
  of her heard through the hall), the land echoing her four times
  (0.42 to 2.4 s later, quieter and darker each, either side);
- **the fall** (12.5 s): the music gate falls away over 0.7 s and the hall's
  tail is taken to a quarter, so by the drop only her sob, the rumble's last
  and the seed's whistle are left; two last rumbles of earth sound in the
  silence;
- **the landing**: every voice made afresh; timpani and the great taiko,
  the strings (0.3 s) and choirs on C#5 G#4 F#3 D2 (0.7 s) rising slowly out
  of the bell, no brass (brass on a major chord read as a fanfare); 1.6 s
  after, the garden's theme (`score.theme`) comes home upright on the
  bells and softly on the piano; the garden's music returns from 8 s after,
  over 10 s.
**Over it**, in D Lydian: glass glints rain while the sky
shatters, thickest midway; the seam glides D3 to D2 as the ley seals;
crackle in a high band as ash crumbles; each crack a noise snap and 4 to 7
glints; each arrival a glint a Lydian step above the last; the fall a band
of air swept down 3.2 kHz to 280 Hz with a tone gliding under it; the
landing a great church bell on D2 (its hum an octave under, its minor
tierce, quint and nominal, ringing up to 7 s), a deep boom hardly sinking
(36 to 31 Hz, ringing over a second) and the D5 F#5 A5 C#6 G#6 glass struck
together, soft, a shimmer over the bell. (Rung up note by note, the glass
read as a wand's sparkle, and a thump sinking fast as a cartoon's bwomp:
the gardener called that landing comical.)

## Saves
`Unforming` (phase, time, where the seed gathers, whether the ley has
sealed) is saved with the garden. The shards in flight (`unformSources`)
and the drifting ley shards (`leyDrifts`) are not: a garden loaded
mid-event sends none up and has none drifting.

## Trying it
```
zig build run -- --demo --unforming --inspect=eyes --pitch=-25 --shots=14 --orbit=14
zig build run -- --plant=bloom --state=unform
zig build run -- --act2
```
`--unforming` begins it at once (its study learned). `--act2` runs it
all the way through first (at most 600 s of ticks, `act.zig`).

## Tests
In `unforming.zig`:
- the ley lines seal: ley tiles close to soil and their nodes drift;
- a radiant plant's moment falls within the spread;
- learned, it shatters the radiant plants, kills the lineages, evolves the
  arsthraxia and lets one seed fall.
