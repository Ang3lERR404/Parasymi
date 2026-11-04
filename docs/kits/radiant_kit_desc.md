# radiant_kit

`src/gfx/meshes/radiant_kit.zig`. Imports: `meshgen` (`mg`),
`mineralKit` (`mineral`), `vertex`, `sim/species`, `core/math`,
`core/color`, `core/rng`. **Never** `growth` or the symbiotic/parasitic
kits.

## What it is

The **radiant (celestial) lineage's body**. It is shared by:
- its plants: `plant` (the celestial bloom, form `radiant`), `star`
  (the vesper, form `star`) and the light grid's four: `solcyriphon`
  (`lens`), `astrocyme` (`bouquet`), `heliocyra` (`heliotrope`),
  `halcyra` (`veil`);
- its structures: the diamond (`cut` + `shards`), and the halo crowns
  powered structures wear (`light_crown.zig`).

**A radiant thing is never grown, only gathered.** No stem, no growth
spline, nothing that swells or scales up. A grounded one (the vesper) is
held to its tile by a `root` of light, struck down out of its heart, never
grown up from the soil.

It is made of rigid fragments joined to nothing: petals, threads, motes,
facets. Think of iron filings flying to a magnet:
- each fragment comes in from afar on its own way, turning round the
  heart as it comes;
- each settles in its place in its turn: the heart first, the last to
  close last.

Once gathered, it hangs together by light alone (`thread`), turning
slowly, drifting a little apart and back. It never bends from a root.

## The fragment contract (what the shaders read)

Every vertex belongs to one fragment, marked by `fragment(b, start, f)`.
Each fragment tells the shader three things:

| Channel | Meaning |
|---|---|
| tu.x | assembly order, 0 first .. 1 last |
| tu.y | `Ring` as a number; a thread adds `(1 - along) * threadAmount` (0.9), so its heart end stays put |
| tu.z | `aux`: what its form says besides (an astrocyme flower's number from 1; a root's strike height; a heliocyra head's distance out) |
| colour alpha | bearing round the heart (`bearing / τ * 255`: the angle scaled into 0..255), the way it comes in from |

`Ring = enum(u8) { core, inner, middle, outer, motes, halo, leaves, yield, root, facets, trailing, veil, wound, net }`.
Each ring moves its own way (plant.vert `SPIN[14]` turn rates; `.root`
and `.wound` never turn).

A radiant structure's body is `.core`. `threadAmount` = common.glsl
`RADIANT_THREAD`.

## API

| Item | Purpose |
|---|---|
| `Fragment{order, ring, bearing = 0}` / `fragment(b, start, f)` | mark all vertices since `start` (asserts order in 0..1) |
| `thread(b, growth, r, col) V3` | a thread of light (`.bloom` tube, 14 pts) along a grown path, tapering to a point at both ends (`√sin`, clamped against f32 NaN); not a fragment by itself (belongs to what it holds); returns its far end |
| `Core{r, body, lite, stamens = 7, seed}` / `core(b, c, rng)` | the heart, order 0: luminous seed-shaped core + nucleus + crown of stamens (threads tipped with beads); plant.frag shades everything of ring `core` (but prisms and pods) in twinkling rainbow flecks over a pearl, never white (`CORE_FLECKS`, `CORE_TWINKLE*`, `CORE_OVER`) |
| `Whorl{n, ring, at, y, len, w, rise, flare, cup, order:[2], offset, col, tip}` / `whorl(b, R, wh, lite, seed, rng)` | petals (`mg.petal`, part `.leaf`) floating free a gap off the heart, each its own fragment (order spread over `order[0..1]`), each held by a private `tether` thread from the core's flank to its claw; `offset` turns it half a petal on |
| `Leaves{n, at, y, len, w, droop, order, col, tip}` / `leaves(...)` | leaves floating free under the heart, threaded up to its underside; ring `.leaves` — **the only fragments that cast shadows** |
| `Root{n, depth, spread, sink, order:[2], col, shard, tip}` / `root(b, R, r, seed, rng)` | a grounded one's root of light: a taproot from the core's underside and `n` strands fanning down into the soil (threads, heart end held), a small `mineral.crystal` shard where each digs in; ring `.root` |
| `motes(b, R, n, col, rng)` | motes of light, each its own fragment on its bearing, spiralling in and fading, over and over |
| `halo(b, r, thick, tilt, order, col)` | a thin tilted ring of light, ring `.halo`, the last to close |
| `cutSides` = 8, `Cut{rows:[]const m.Vice(f32,3) (height, radius, twist in half sides), deepRows, deep, lite, part = .prism}` | a cut crystal's profile; a row of radius 0 is a point |
| `cut(b, c, rng)` | flat facets between rows (`mineral.facet`), staggered by twist, slightly uneven; every facet its own fragment, gathered **foot up**, each row in turn round it, within `cutShare` (0.8) of the order |
| `shards(b, n, at, c, rng)` | small `mineral.crystal`s out of a cut's foot, leaning away, settling after its facets (order 0.8..1) |
| `Stamens{r, n, lite, seed, at, y, len, lean}` / `stamens(b, s, rng)` | a crown of stamens (threads tipped with beads), the core's and the heliocyra's |
| `Lens{n, inner, outer, thick, y, order, lite, deep}` / `lens(b, R, l, lite, seed)` | a flat ring of `n` crystal segments round the heart, each a flat gem cut to a ridge above and below (`.prism`), its own fragment on ring `.facets`, tethered |
| `Trail{n, at, y, len, r, beads, order, col}` / `trailing(b, R, t, seed, rng)` | threads of light trailing beneath like a jellyfish's, beads strung down them; ring `.trailing`, held at the top |
| `CrystalPetal{base, dir, face, len, w, thick, col, tip}` / `crystalPetal(b, c)` | a broad lozenge of crystal, eight flat facets (`.prism`) |
| `woundThread(b, heart, lite, order)` | a halcyra's thread from its leaning heart (`veilLean`) arcing to a plant `veilReach` off along +x and winding down round it; ring `.wound` |
| `net(b, heart, R, lite, order)` | the same thread opened into a net (8 spokes, 2 sagging rings, beads at the crossings) 2.2 m round; ring `.net` |
| `bouquetAt(k)`, `bouquetFlowers/High/Low/Turn/Out/Taper` | where an astrocyme's flower `k` hangs (plant.vert `bouquetAt`, the same numbers) |
| `plant(b, genome, seed, variant)` | the celestial bloom (see below) |
| `star(b, genome, seed, variant)` | the vesper (see below) |

### The celestial bloom (`plant`)
- Its origin is the core: `core`.
- Three whorls:
  - inner: 5, an upright cup;
  - middle: 6–7, offset;
  - outer: 8–9, open wide.
- Colours `bloomCol` / `stemCol`, paling to white tips.
- 9 motes.
- A halo at 1.55R, tilt 0.35.

### The vesper (`star`)
- `core` (5 stamens), and an inner cup of `petals`.
- A star of long narrow rays (len 2.3+, offset).
- `leaves` floating beneath (`leafCol`), and 7 motes.
- **No halo.**
- All of it lifted `stemH` over its tile, held to it by a `root` (5
  strands, order 0.03–0.09: just after the heart lands).

### The solcyriphon (`solcyriphon`, form `lens`)
A lens, a flower facing up and a touch of jellyfish, hung 7 m up. Its
origin is the heart: a gold `core`, a `lens` of 10 facets round it, two
whorls of 7 broad petals rising round the lens open to the sky, 9
`trailing` threads with beads, 16 motes. plant.vert folds it by how dark
it is (`FORMS_NIGHT_FOLD`, read off `DAYLIGHT`): by night its petals close
up tight, its threads coil up under the lens, its heart burns smaller and
brighter; by day its motes spread out and down round it.

### The astrocyme (`astrocyme`, form `bouquet`)
A spiral bouquet. A knot of light 0.12 m over its tile, held by a `root`;
a twisting thread of light rises from it, and six flowers fan up from the
knot on stalks of light, winding round the thread (`bouquetAt`), each a
small `core` and a whorl of 7 petals, every vertex marked with its flower
in tu.z. plant.vert (`FORMS_SHARED`) opens flower `k` as its store
(instance `yield.w`) fills past `k / 6`, bottom up: gathering, it closes
into a bud and opens; empty, its petals hang open and drift loose round
its heart, circling, its light dim. Emptying, they come apart top down.

### The heliocyra (`heliocyra`, form `heliotrope`)
A heliotrope: a neck of light from a knot over its tile (held by a
`root`) bows up to a head facing +x, lifted 0.45 rad: a `cut` crystal
heart, a crown of 9 `stamens`, a ring of 9 short gold petals and a wheel
of 14 rays. Drawn turned the way it casts (never its seed's yaw:
`FORMS_FACING`); its rays flutter (tu.z), its head swings a little, its
crystal burns with its strip's light (`FORMS_FLUTTER`, `yield.w`).

### The halcyra (`halcyra`, form `veil`)
A small flower (`core`, a cup of 5) 0.5 m over its tile on a `root`,
hooded by a veil of 9 broad gores curving down like a jellyfish's bell
(ring `.veil`, drawn sheer), 9 `crystalPetal`s hanging between them at
the veil's edge (ring `.facets`), sparkling motes flung off them. Its
thread is built both ways (`woundThread`, `net`); plant.vert
(`FORMS_GUARDING`, `yield.w` the reach to the plant it guards, 0 alone)
shows one: beside a plant it leans over it (`veilLean`, the view turning
it toward that plant) with the thread wound round it, carried on to
where the plant stands; alone the net spreads.

## Who uses it

| User | Uses |
|---|---|
| `meshgen.zig` form `.radiant` | `plant` — species `bloom` |
| `meshgen.zig` form `.star` | `star` — species `vesper` |
| `meshgen/shoots.zig` forms `.lens`, `.bouquet`, `.heliotrope`, `.veil` | `solcyriphon`, `astrocyme`, `heliocyra`, `halcyra` |
| `halo.zig` (the diamond, shared by `diamond.zig`, polyp event) | `Cut`, `cut`, `shards` |
| `light_crown.zig` (the halo crowns powered structures wear) | `fragment`, `halo`, `whorl`, `core`, `cut`; `mineralKit.crystal`; all re-marked part `.crown`, gathered in part.vert by the structure's shine (`CROWN_*`) |
| `tests.zig` | pulls in its test |

## GPU side

### Shared helpers (common.glsl)
- `fragmentOf(tu, a)` → `{order, ring, held, bearing}`.
- `gatherAway(order, pace, span, k)`: 1 setting out .. 0 settled.
- `gatherIn(p, from, away, shrink, turn)` / `gatherTurn(n, away, turn)`.
- `FORMS_FREE` = radiant | star (no wind bend from a root).

### plant.vert
- **Gathering**: by the plant's growth (`ARRIVE_PACE` 0.7, `spanScale`
  0.3, `reachDistance` 1.4, `turnRate` 1.4). It spirals each fragment in,
  folded as a bud, and opens it.
- **Grown**: whorls turn slowly, alternating (`spinTimes`), and drift
  apart and back; the whole bobs.
- **Rooting**: a `.root` fragment strikes straight down out of the heart
  (its soil end starts `ROOT_STRIKE` 0.55 up, under the heart); once in it
  never turns, never comes loose, and its soil end stays put when plucked.
- **Falling**, `FORMS_FALLING` (= star): falls in from the sky. The heart
  comes first, straight down, then each piece spirals down its thread
  (`FALL_FROM` 1.8, `FALL_TURN` 2.4).
- **Withering** out of radiance: `LOOSE_SINK/AWAY/HANG` (pieces sink,
  drift out, hang open), and the light dims with health.

### plant.frag
- Pearl with an iridescent film (`filmHue` by view angle), like a soap
  bubble.
- `FORMS_OWN_HUE` (= star) keeps more of its own hue.

### part.vert (the diamond)
- Gathered by its halo's pull (`PRISM_PACE` 0.4, `spanScale` 0.6,
  `reachDistance` 0.45, `turnRate` 3.0).
- part.frag does the `PRISM_*` shading.

### Shadows
Shadow variants leave out light itself; only `.leaves` fragments cast.

## Test

`"a celestial bloom, a vesper and a cut crystal are wholly gathered fragments"`
and `"the light grid's four are wholly gathered, grounded ones dig in, and
the bouquet is as the shaders know it"` (every variant and level of detail)
checks:
- every vertex has an order in 0..1, a valid ring, and no NaN;
- **nothing is on a growth spline** (`b.grow` untouched);
- only the vesper's root reaches the ground, and it digs in (below 0);
- a cut's facets gather foot up.

## Rules

- A new radiant thing is built from these pieces and gathered the same
  way; never with other kits (except `mineralKit` for crystals) or growth
  splines.
- Never scale it in; give every new piece a fragment with an order and a
  ring.
- Check: `--plant=bloom --state=grow`, `--plant=vesper --state=grow|wither`,
  `--plant=solcyriphon --tod=0|0.5`, `--plant=astrocyme --state=fill`,
  `--plant=heliocyra`, `--plant=halcyra` (alone: its net; `--demo` for a
  guarded plant, the beam and the strips),
  `--structure=diamond --state=grow`.
