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
- The **stars** that fall at night shatter as they hit the ground and stop
  falling altogether.
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
| 0 | Every starlight mote shatters (6 warm shards each, 1.4 s) and no star falls again. Every structure is sent `Msg.unform`: the arsthraxia evolves. |
| 0 – 6 | Radiant plants (bloom, vesper) begin to glitch, one after another. |
| +5 each | Each one glitches, shatters like glass and blinks out over 5 s. At 60% through, it sends 4 shards up. |
| 0 – 14 | Symbiotic and parasitic plants wither, and the lineages' structures grow back down to nothing, each over 6 s (starting within the first 8 s). What they held is lost. |
| 1 – 13 | The sky shatters from the zenith to the horizon, pane by pane, and the ley's violet glow floods in. |
| ~2.8 – 10 | The ley lines seal from their edges in, a bright seam closing, leaving scars of bare soil. |
| 10 | Sealed. Every ley shard node breaks into 7 violet shards that drift up weightless. |
| up to 13.4 | The shards fly up (2.4 s each, swirling) to a point 14 m over the middle of where the radiant plants stood. A star of gathered light swells there as they arrive. |
| 13.4 – 15.6 | The **strange seed** falls (2.2 s, faster as it goes), its star shrinking back into it. |
| 15.6 | It lands, with a burst of light (1.4 s): **OUT OF THE SHATTERED LIGHT, A SEED FALLS. IT DOES NOT TAKE ROOT** |
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
  light becomes the ley-tinted glow overhead.
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
- radiant plants glitching: `PlantInstance.glitch`, plant.vert `unformAt`,
  plant.frag `unform`;
- the sky and the closing ley lines: sky.frag, terrain.frag, common.glsl
  `SHIFT` (`SEAL_FROM`/`SEAL_SPAN` must match `sealFrom`/`sealSpan` in
  `unforming.zig`).

Each frame `unforming.draw` emits the flying shards (`unformShard`), the
seed and its star of light, the landing burst and the drifting ley
shards, each lighting the air round it.

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
