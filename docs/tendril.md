# The constellate tendril, exactly

How the tendril looks the way it does: a braid of loose fragments that
flows along its length like a stream. The gardener approved this look
(2026-10-31). Rebuild it from these numbers and it will match.

- The sketch: `--samples=constellateTendril,constellateTendrilGround,constellateTendrilArc`
  (`src/gfx/meshes/constellate.zig` `tendrilAt`, `shaders/part.vert`
  `plexusTendril`, `plexusTendrilPath`, `plexusTendrilRide`).
- The garden's version, one flow along a whole drawn path:
  `tendrilFlowMesh` and `plexusTendrilGarden` (the same braid on any
  path).

Nothing about it is stored as a shape. The mesh only holds *which* lights
and lines could exist. The GPU places every light each frame and decides
which lines and panes show.

## 1. What it is made of (the plexus web)

Everything constellate is a **plexus web**: part role `plexus`
(`vertex.Part.plexus`, `PART_PLEXUS` in part.vert / part.frag). A web is
built by `cluster(b, Web)` in constellate.zig and has three kinds of piece:

- **Points.** Each point is a *pair* of lights: a small ball (ellipsoid,
  6 rings × 8 segments) built twice, `pos.y` = 1 (the first light) and
  -1 (its companion). The companion is 0.7 the size (`PLEXUS_COMPANION`).
  The two circle each other 0.04 apart (`PLEXUS_PAIR`), each pair on its own
  axis at its own pace (0.6–1.4 rad/s), the first light keeping to the far
  side (`PLEXUS_PAIR_LEAN` 0.4). Light radius 0.009 (`PLEXUS_POINT_R`).
- **Lines.** A line is built for *every pair* of points in the web: a
  ribbon of 8 pieces, turned to face the eye on the GPU, pinched to a
  point at both ends, 0.022 half-width (`PLEXUS_LINE_W`). It shows only
  while its two lights are within the web's **reach**, fading from 0.8 of
  the reach (`PLEXUS_SOFT`) to nothing at the reach.
- **Panes.** A pane is built for *every triple* of points: two faces,
  0.005 apart (`PLEXUS_PANE`). It shows while all three of its lines show,
  and draws in toward its middle as any of them breaks.
- **Two layers.** Every line and pane is built twice. Layer 0 joins the
  first lights (blue). Layer 1 joins only the companions (thinner, cyan).

Each vertex carries only what it belongs to, packed in its colour:
r, g, b the ids of its points (a point repeats its id, a line repeats its
second); alpha = kind + 4 × shape (kind 0 point, 1 line, 2 pane, 3 bond;
shape is the `Shape` enum, so up to 63 shapes). `pos.x` is the reach,
`pos.z` the layer, and for a pane `pos.y` which face.

## 2. The tendril's web

`tendrilAt(b, height)`:

```zig
try cluster(b,.{.shape=@enumFromInt(@intFromEnum(Shape.tendril)+height),.reach=0.14,.n=72});
try cluster(b,.{.shape=@enumFromInt(@intFromEnum(Shape.tendrilRide)+height),.reach=0.17*0.3});
```

- **72 points** = 3 strands × 24 fragments (`PLEXUS_TENDRIL_STRANDS`,
  `PLEXUS_TENDRIL_EACH`). Point `id` is strand `id / 24`, fragment
  `id % 24`.
- **Reach 0.14**, with no grouping, so any two lights may join. This
  number makes the look. Fragments along a strand sit about 0.1 apart
  (2.4 m / 24), and the strands about 0.087 apart across the braid. Both
  are inside the reach, so each fragment joins its neighbours along *and*
  across. That gives the braid its woven lattice of lines, and the glassy
  panes between strands. A fragment two along is 0.2 away, outside the
  reach, so it never joins.
- The shape ids: `tendril` 52, `tendrilGround` 53, `tendrilArc` 54; the
  riding part 55–57 (`PLEXUS_TENDRIL`, `PLEXUS_TENDRIL_RIDE`).

## 3. Where each fragment is (part.vert)

### The path (`plexusTendrilPath(u, height, t)`)

`u` runs 0 → 1 from one end to the other; the segment is 2.4 long
(`PLEXUS_TENDRIL_LEN`), along z:

| height | y |
|---|---|
| 0 floating | `1.0 - 0.2 * sin(π u)` (sags 0.2 in the middle) |
| 1 ground | `0.06` |
| 2 arc | `0.3 + 1.4 * sin(π u)` |

Side sway (x): `amp * sin(u*3 + t*0.4) * sin(π u)`, amp 0.08 (0.02 on the
ground). The `sin(π u)` keeps both ends still.

### The braid (`plexusTendril(id, height, t)`)

```glsl
float k = floor(id / 24.0);                 // strand 0..2
float j = id - k * 24.0;                    // fragment along it
float u = fract(j / 24.0 + t * 0.06 + k * 0.013);   // flowing
vec3 c = plexusTendrilPath(u, height, t);
vec3 dir = normalize(path(u + 0.01) - path(u - 0.01));
vec3 e1 = normalize(cross(dir, vec3(0, 1, 0)));
vec3 e2 = cross(e1, dir);
float ang = k / 3.0 * TAU + u * 2.2 * TAU - t * 0.8;
float r = 0.05 * (0.75 + 0.25 * sin(u * 20.0 - t * 2.0));
float env = smoothstep(0.0, 0.06, u) * (1.0 - smoothstep(0.94, 1.0, u));
pos = c + (cos(ang) * e1 + sin(ang) * e2) * r;
```

What each line does to the look:
- **Flow:** `u` moves on at 0.06 lengths a second (`PLEXUS_TENDRIL_FLOW`),
  wrapping at the end. Every fragment travels the whole length, so it
  reads as a stream, not a rope that turns.
- **Strand offset `k * 0.013`:** the three strands are not in lock-step,
  so the fragments never line up into rungs.
- **Braid:** the strands are 120° apart round the middle and wind 2.2 full
  turns along the length (`PLEXUS_TENDRIL_TURNS`). `- t * 0.8` twists the
  whole braid slowly as it flows.
- **Breathing:** radius 0.05 (`PLEXUS_TENDRIL_R`) swells and narrows by
  a quarter. The swell moves along at `u*20 - t*2`, so a pulse seems to
  travel down the braid.
- **Ends:** `env` thins the fragments to nothing over the first and last
  6% (lights shrink, lines and panes fade), where it meets what it joins.
  It also hides the jump when a fragment wraps from the far end back to
  the start. That jump never draws a line: wrapped neighbours are 2.4 m
  apart, far outside the reach.
- **Lines and panes fade with their faintest point:** the `yield` for a
  tendril vertex is the `min` of `env` over its three ids.

The tendril skips the general drift every other web gets (`plexusAt`
returns early for it). The flow is its motion.

### The riding part (`plexusTendrilRide`)

A petal web (`plexusForm(id, PLEXUS_PETAL)`, 30 points) scaled to 0.3
(`PLEXUS_TENDRIL_PART`), its form centred by subtracting (0, 1, 0). It
rides 0.12 above the path, end to end every 8 s (`PLEXUS_TENDRIL_RIDING`),
turning about y at 0.5 rad/s. It fades in and out over the first and last
8% of the ride. Its reach is `0.17 * 0.3`: the petal's own reach, scaled
the same as its shape.

## 4. How it shines (part.frag, plus the crowd dimming)

- **Colours** (part.frag): first layer `PLEXUS_BLUE` (0.04, 0.16, 0.85) →
  `PLEXUS_PALE` (0.62, 0.86, 1.0); companions `PLEXUS_CYAN`
  (0.02, 0.5, 0.6) → `PLEXUS_CYAN_PALE` (0.6, 1.0, 0.95).
- **Heartbeat:** each web beats lub-dub from its heart, point id 0 for a
  tendril (`plexusHeart`). Period 1.6 s, lub at 0.06, dub at 0.2 of it,
  each a gaussian 0.035 wide, the dub 0.6 as strong. The beat runs out at
  0.9 m/s (`PLEXUS_SPEED`), the distance being straight-line from the
  heart (`v_t`), fading by `1 / (1 + 0.35 * v_t)`. It mixes the blue
  toward pale.
- **Point:** `mix(col, pale, 0.35 * ndv²) * (1.6 + 4 * beat)`, solid.
- **Line:** a soft glow, `core = exp(-x² * 40)`, `halo = exp(-x² * 4)`
  across its width:
  `c = col * (0.8 + 3 * beat) * halo + pale * core * (0.6 + 1.5 * beat)`.
- **Pane:** blue glass brighter at grazing angles:
  `col * (0.32 + 0.6 * rim + 1.8 * beat)`, rim = `(1 - ndv)³`,
  alpha `0.4 + 0.35 * rim + 0.4 * beat`.
- **Crowd dimming:** a tendril's points and lines are multiplied by 0.55
  (`plexCrowd`); its panes are not. Without it, the lights crowding where
  the strands cross ran together into a white glare, mostly at the beat.
  Panes stay whole so the braid still reads as glass.
- **It lights the fog:** like every glow, it is drawn again in the
  `partsAir` pass (part.vert/frag built with `-DAIR`), lines and points
  spread 5× wider (`AIR_SPREAD`), adding light as dense as the air is.

## 5. What was tried and why it is like this

- The gardener's words: a braided tendril **that moves like a flowing
  stream**. That is why the fragments travel along (`u` flows) instead
  of the braid only turning in place.
- Up close it reads as a glassy lattice more than a twisted rope. That
  comes from reach 0.14 joining across the strands. The gardener saw this
  and approved it as is.
- The ends flash white on each beat, because the heart (id 0) flows
  through the whole tendril. 0.55 dimming tamed it. It was not removed.
- The heart's own hanging tendrils are a different thing (`heartFilament`).
  Bundling them to carry parts looked unnatural and was dropped.

## 6. Making another one

1. Add its `Shape` tags in constellate.zig (keep the numbers after the
   last; alpha must stay ≤ 255, so shape ≤ 63) and the matching
   `const int` in part.vert.
2. Build it with `cluster` at reach 0.14 and 72 points (3 × 24), or keep
   the same spacing if you change the length: about 0.1 between fragments
   along a strand, and radius 0.05.
3. Place it in `plexusAt` with the braid formula above along your own
   path, return early so no drift is added, and set `yield` to the `min`
   of `env` over the vertex's ids.
4. Dim its points and lines with `plexCrowd = 0.55`, never its panes.
5. Check it at night, close and far:
   `zig build run -Drelease=true -- --samples=<yours> --inspect=player --shots=4 --orbit=16 --dist=5 --pitch=18 --tod=0.85`,
   then read the PNGs in `shots/`.

## 7. The garden's tendril (one flow along a drawn path)

`plexusTendrilGarden` is the same braid with everything measured in
metres along the *whole* drawn path, so it is one stream from start to
end, never tile by tile:

- **The path on the GPU.** game/tendril.zig lays the path's tiles out
  (each tile's centre floating `high` over the ground, sagging
  `0.2 * min(high, 1) * sin(π along)` over the whole length; on the ground
  0.06) and puts the points as this frame's bones (`Parts.pose`): each a
  point in its first column, how far along the path it lies in its w.
  The instance (`Parts.emitPath`) carries where they start, how many and
  the path's length in `ie.yzw`. `plexFlowAt(s)` finds the span and runs
  the Catmull-Rom curve through the points.
- **The lights.** A slice of 3 lights every 0.1 m (10 a metre, the
  sketch's spacing), `ceil(len * 10)` slices. Slice `j` sits at
  `mod(j + (t * 0.06 + k * 0.013) * 2.4 * 10, slices) / slices * len`:
  the sketch's flow speed, strand offset, twist (2.2 turns per 2.4 m),
  breathing and sway, all per metre. The ends thin over 0.144 m (6% of
  the sketch's 2.4).
- **Chunks.** Ids are a byte, so the mesh holds one chunk of 90 lights
  plus the next 9 (band 9: each light joins only lights 9 on in the
  list, plenty for reach 0.14). A tendril is drawn as many chunk
  instances as its lights need (`flutter` = which chunk); each light,
  line and pane is drawn only by the chunk owning its first id
  (`plexFlowOwns`), so chunks join seamlessly. Ids past the last slice
  wrap to the first, so the stream also joins round its wrap.
- **One heart.** Every chunk beats from the tendril's first light.
- **Riding.** What it carries is drawn at 0.3, 0.12 over the path,
  turning 0.5 rad/s, fading over the first and last 8% of its ride.
