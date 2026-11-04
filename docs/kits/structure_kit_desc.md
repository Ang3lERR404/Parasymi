# structure_kit

`src/gfx/meshes/structure_kit.zig` (338 lines). Imports: `meshgen` (`mg`),
`palette` (`pal`), `growth`, `sim/species`, `core/math`, `core/color`,
`core/rng`.

## What it is

The **symbiotic lineage's body**. Not a mesh itself.

It holds shared pieces for the lineage's structures, in the plants'
language:
- a woven root mat they rise from;
- grown vines with leaves along them;
- broad foot leaves;
- forking rootlets;
- pods of the wolf's resin sap: dense at the base, see-through at the
  crown, no light of its own.

It also builds the lineage's plants (`plant`, the `herb` form) out of the
same pieces.

Every piece works two ways:
- **Plain** (`on = null`): built with a fixed tu.x. This is the old style,
  still used by the fibre node and rootlets.
- **On a growth spline** (`on = On{k, id, u}`): the piece becomes a branch
  of the structure's `growth.Skeleton` and grows with it. This is the
  required way for any structure mesh ([../growth.md](../growth.md)).

## Colours (from `palette.zig`)

- `pal.core`: the braid core.
- `pal.vine`: strands, vines.
- `pal.leafDark` / `pal.leafLite`: leaves, base→tip.
- `pal.sap`: resin.
- `pal.rootBark`: rootlets.
- `pal.strandWobble` (0.03): how much a braided strand wanders.

## API

| Item | What it builds | On a spline |
|---|---|---|
| `On{ k:*Skeleton, id:Id, u:f32 = 0 }` | where a piece grows: spline `id` of skeleton `k`, `u` along it | — |
| `rootMat(b, n, reach, girth, seed, on)` | `n` braided roots radiating from the centre to `reach`, hugging the ground, sinking in at their ends (3-strand `mg.braid`, girth tapering to 0.35) | each root is `k.branch(id, u, ctrl, .{.after = .with})` + `k.braid` (grows with its parent) |
| `leafyVine(b, from, to, r0, curl, leaves, t0, t1, seed, on)` | a grown, tapering vine from `from` toward `to` (wobble 0.18, `curl`), `leaves` small leaves along it | `k.vine(id, u, growth, 7, .{})` + `k.tube` + `k.leaves`: grown once the parent is done, leaves open as the front passes |
| `resinPod(b, center, radii, rings, segs)` | an ellipsoid of part `.resin`, colour `pal.sap`; tu.y 0 at its dense base → 1 at its thin crown (the resin shader reads it) | not tagged: tag it yourself (`sk.on` / `growth.tag`) |
| `footLeaves(b, n, r, len, width, seed, on)` | `n` broad blades in a ring at the foot on one envelope | each blade `k.on(b, mark, id, u, .{.from = base, .delay = footStagger * i})`: they unfold from their bases one after another (`footStagger` 0.025 of the growth) |
| `rootlet(b, from, dir, len, r0, seed)` | a root heading down into the soil, tapering to a hair (tip 0.12), two forks off its far half; `pal.rootBark`, tu.x 0..0.3 | plain only (the caller tags it) |
| `plant(b, g, seed, variant, rooted)` | a symbiote from its genome (see below) | plants grow by tu.x in plant.vert (whole-plant scale, leaves and petals unfolding), not on a skeleton |

### What `plant` builds
A symbiote from its genome. Colours come from the genome (core = stem
shaded 0.55). From the ground up:
- **Stem**: braided, 4 strands (6 past `thick` 0.1). Its turn is `pitch`
  0.46 × length / radius.
- **Roots**: the stem flares into 5 braided roots (`roots`) hugging the
  ground, plus braided prop roots (`tendrils`).
- **Foot leaves**: genome `rosette` of them: broad old leaves sprawling
  low on short stalks, each its own size, toothed, twisted, rippled,
  yellower with age.
- **Vines**: `vines` leafy vines twining up it, pointed at both ends.
- **Leaves and thorns**: genome `leaves` of them up the stem on their own
  stalks (`mg.leaf`), a golden angle apart with strays, biggest and
  drooping most low down, each its own size, droop, twist and ripple,
  tips curling; toothed on a herb, smooth-edged past `toothedUpTo` (a
  tree's); `crownLeaves` young ones folded round the crown; thorns.
- **Offshoots**: braided (`mg.shootPath`, folded by
  `mg.shootFoldNearest`), ending in buds or blooms.
- **Bloom**: on a resin bead (`mg.flower`, `.{.resin = pal.sap}`).

## Leaves
Every leaf in the lineage's pieces (foot leaves, vines' leaves, the
grower's leaves) is a natural one (`mg.natural`: the plain blade's reach,
size and colours, its own twist, ripple, tip curl and teeth drawn from
where it grows, on a stalk of its own). The convergence kit's leaflets
and the loomfern's pinnae are natural too, sitting on their rachis
(`.sessile`).

## Who uses it

| Mesh | Uses |
|---|---|
| `meshgen.plant` (`herb` form: lumenroot, hollowheart) | `plant` |
| `germinator.zig` | `rootMat`, `footLeaves`, `leafyVine`, `resinPod` |
| `sap_cache.zig` | `rootMat`, `footLeaves`, `leafyVine`, `resinPod` |
| `arsthraxia.zig` | `rootMat`, `footLeaves`, `resinPod` |
| `gathering_crown.zig` | `rootMat`, `footLeaves`, `resinPod`, `rootlet` |
| `polyp_hydra.zig` (the polyp) | `rootMat`, `resinPod` |
| `polyp.zig` (its colony look) | `rootMat`, `resinPod` |
| `root_digger.zig` | `rootMat`, `resinPod`, `rootlet` |
| `loomfern.zig` | `rootMat` |
| `conduit.zig` | `rootlet` (the arch's rootlets; the arch itself is `conduit.arch`) |
| `node_fibre.zig` | `rootMat` (plain) |
| `starlight_catcher.zig` | `resinPod` (its legs braid on its own skeleton) |

Companion pieces not in this kit, but part of the same vocabulary:
- `conduit.arch` / `spineCtrl`: a woven arch with a sapwood `.core` and
  side roots (`core = null` for a bare weave);
- `mg.braid`, `mg.braidAround` (nerves);
- `mg.leavesAlong`, `mg.petal`, `mg.stamens`.

## Process: building a symbiotic structure mesh with it

```zig
var sk = growth.Skeleton.begin(b);
const trunk = sk.trunk(&ctrl, .{});
try kit.rootMat(b, 6, 0.4, 0.03, seed, .{.k = &sk, .id = trunk});      // roots grow with the trunk
try kit.footLeaves(b, 5, 0.12, 0.2, 0.07, seed, .{.k = &sk, .id = trunk});
try sk.braid(b, trunk, .{...});                                        // the trunk itself
const mk = b.mark();
try kit.resinPod(b, centre, radii, 10, 14);
try sk.on(b, mk, trunk, 0.8, .{.from = centre});                       // pod swells once the front reaches 0.8
try kit.leafyVine(b, from, to, 0.012, 0.4, 4, 0.5, 1, seed, .{.k = &sk, .id = trunk, .u = 0.6});
sk.finish(b);                                                           // required (debug assert in meshlib.build)
```

Timing is the skeleton's alone (`Branch.pace`, `Branch.front`,
`After.done/passing/with`, `.delay`); never hand-set times.

Emitted pieces (cups, lids) go in the tail kept free by `sk.tail = form`.

## GPU side

- **Growing**: vertices on a spline carry `vertex.Grow` (`from`, `at`;
  binding 3, locations 21–22). `part.vert` shrinks each into `from` until
  the structure's growth (`PartInstance.w.w`, `Look.grown`) reaches it,
  then grows it out. It stays thin (`SPROUT_THIN`) until its spline is
  done. Foliage tips lag behind (`LEAF_LAG`).
- **Resin pods** (`.resin`): translucent sap, tu.y base→crown,
  `sapGlisten`, `sapBubbles`/`sapDroplets` (common.glsl). Drawn in the
  glass pass (`vertex.seeThrough(.resin)`).
- **Resin beads on a plant's blooms** (`.resin`): plant.frag shades them
  as the structures' resin (surface.glsl `resinSurface`, shared with
  part.frag). tu.y (passed as `v_young`) runs base→crown, dimmed by
  health.
- **Leaves** (`.leaf` blades) fold toward a pale midrib
  (`meshgen.lamina`), and breathe and sway with `gardenWind`.

## Rules

- Always pass an `On` in new structure meshes; plain mode is legacy.
- Don't add parasitic or radiant pieces here; those have their own kits.
- Check with `zig build run -- --structure=<kind> --state=grow` (and
  `--state=active` for emitted pieces), with `--inspect=<kind>` for shots.
