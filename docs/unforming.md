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
| 0 | Every starlight mote shatters (6 warm shards each, 1.4 s) and no star falls again. Every structure is sent `Msg.unform`: the arsthraxia evolves. The garden's music cuts dead and a second of silence falls. |
| 1 – 5 | The theme's lament: a lone cello sings the garden's Lydian line over a choir's hum, its raised fourth (G#) on top. |
| 5 – 7.5 | The cello returns to the G# and it bends down to G; the choir follows into D minor and a heartbeat of timpani begins. |
| 6 – 13.4 | Far off, mostly heard through the hall, the world screams: a voice comes in every 0.7 s, harmonic but straining, cracking. |
| 7.5 – 10 | The loss: the choir's line falls, the strings sigh, a timpani roll swells. |
| 10 – 13.4 | The peak: the whole orchestra with low brass and the great taiko on every heartbeat. |
| 0 – 6 | Radiant plants (bloom, vesper) begin to glitch, one after another. |
| +5 each | Each one glitches over 5 s: bands of it slip sideways and it blinks, cracks of its own light run over it cell by cell, and past halfway it breaks along them into large shards of its own film's colour that drift out and up, turning, and shrink away. At 60% through it sends 4 shards up, each trailing a ribbon of that colour; a glass snap and scatter of glints is heard. |
| 0 – 14 | Symbiotic and parasitic plants wither, each over 6 s (starting within the first 8 s): they dry out grey, bow over and curl, then crumble from the top down into flakes of ash, an ember along each edge as it breaks, lifting off downwind; dry crumbling is heard. The lineages' structures grow back down to nothing. What they held is lost. |
| 1 – 13 | The sky shatters from the zenith to the horizon, pane by pane, and the ley's violet glow floods in. |
| ~2.8 – 10 | The ley lines seal from their edges in, a bright seam closing, leaving scars of bare soil; a seam is heard humming shut, sinking an octave. |
| 10 | Sealed. Every ley shard node breaks (glass heard) into 7 violet crystals that drift up weightless; each at its own moment cracks and melts into a burst of violet motes. |
| up to 13.4 | The shards fly up (2.4 s each, swirling, ribbons behind them) to a point 14 m over the middle of where the radiant plants stood. A star of gathered light swells there as they arrive: a web of pale blue points and threads (as the sky's plexus) round a heart of light, turning slowly, flaring as each shard lands, each landing ringing a Lydian step higher. |
| 13.4 – 15.6 | The **strange seed** falls (2.2 s, faster as it goes), its star shrinking back into it, a comet's tail of light behind it. The whole theme and the world's screaming stop dead; only its whistle is heard. |
| 15.6 | It lands: a ring of light rolls out over the ground from it (2.4 s, the halo's flash), motes flung up, and a deep soft bell blooms with a thump and the great taiko under it and a glass chord ringing up over it, the choir, strings and horns blooming into D major with the G# back: **OUT OF THE SHATTERED LIGHT, A SEED FALLS. IT DOES NOT TAKE ROOT**. The theme rings away; from 8 s after, the garden's music returns over 10 s. |
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

**The theme** is the garden's music breaking: its D Lydian loses its raised
fourth (the sound of wonder) and the landing gives it back. The mixer
(`Sounds.musics`) cuts the day's and night's music to nothing within
0.25 s and plays the theme in their place, in the same stone hall:
- a cello (three saws a hair apart, a wood body, vibrato growing into each
  note) sings D3 A3 G#3 F#3 over the choir's quiet hum (G#4 C#4 A3 D2) and
  low strings;
- at 5 s the cello's G#3 bends to G3 over 0.7 s, the choir moves to Gm/D,
  then D minor; the heartbeat (timpani D2, two strokes 0.26 s apart, every
  0.9 s) grows from soft to hard until the drop;
- at 7.5 s the choir falls through Bb and A, the strings bow harder, a
  timpani roll (14 strokes a second) swells into the peak;
- at 10 s the peak: timpani and the great taiko strike, low brass (saws
  held dark, opening as they swell) on D, Bb and A, the choir past its
  night's full voice, the strings bowing three times as hard, the taiko on
  every beat;
- the world screams from 6 s: eight voices (D5 A5 F5 D6 C5 G5 C6 F6), each
  a throat's buzz shaped into an "ahh" that opens into a cry as it strains,
  scooping in from 3 semitones under, climbing 1.5, its vibrato widening to
  70 cents, cracking once up 4 to 7 semitones, darkened by distance and sent
  mostly into the hall (`farDry` of it heard straight). Until the starlit
  patches fire their beams up, the screaming stands for the light torn out;
- at the drop (13.4 s) a gate shuts it all in 50 ms and the hall's tail is
  taken down to a tenth, so the seed's whistle falls in near silence;
- at the landing every voice is made afresh: timpani and great taiko, the
  choir on C#5 G#4 F#3 D2, strings, horns and the cello's D3, ringing away
  over 9 s; the garden's music comes back from 8 s after, over 10 s.

**Over it**, all soft and in D Lydian: glass glints rain while the sky
shatters, thickest midway; the seam glides D3 to D2 as the ley seals;
crackle in a high band as ash crumbles; each crack a noise snap and 4 to 7
glints; each arrival a glint a Lydian step above the last; the fall a band
of air swept down 3.2 kHz to 280 Hz with a tone gliding under it; the
landing a D2 bell (five partials), a sinking thump and the D5 F#5 A5 C#6
G#6 chord ringing up.

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
