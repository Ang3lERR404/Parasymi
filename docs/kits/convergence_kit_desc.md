# convergence_kit

`src/gfx/meshes/convergence_kit.zig` (629 lines). Imports: `meshgen` (`mg`),
`parasiteKit` (`pk`), `palette` (`pal`), `growth`, `vertex`, `sim/species`,
`core/math`, `core/color`, `core/rng`.

## What it is

The **lineages mixed**: what grows where symbiote and parasite have become
one body. Not a mesh itself.

It is shared by:
- the confluence (a plant, grown through keys);
- the convergent structures (on growth splines, the `*On` pieces).

It is not one laid over the other (a braid below, a cage above). The two
are **woven through each other at every scale**, so neither is ever seen
alone:

- **Stalk** (`weave`): the parasites' lattice, with every other strand a
  symbiote's. Green strands run one way, each wandering a little; pale
  strands run the other way, exact. Where it parts into a cage they cross
  and **fuse into a violet knot**, neither one's colour. The shared core
  is banded with both saps.
- **Sap** (`sac`): amber and pale blue swirling round each other in arms,
  violet where they mingle; never stirred smooth.
- **Counts**: the parasites' exact fives (`fold`), turned evenly and grown
  alike. But what each of the five carries is a symbiote's, each a little
  different:
  - a lilac **frond** bearing green leaflets, ending in a fern crozier (a
    tightly rolled tip);
  - a **bloom** of a pale frondlet calyx holding warm living petals with
    stamens.
- **Foot**: rooted both ways. A pale bulb with five exact pale roots, and
  a green braided symbiote root between each two.

Cage strands carry how far they've parted in tu.y, as the parasites' do.

The driftbraid's look is the approved reference for this kit.

## Colours

| Name | Source | Use |
|---|---|---|
| `green`, `leafDark`, `leafLite`, `amber` | `pal.vine`, `pal.leafDark`/`pal.leafLite`, `pal.sap` | the symbiotes' half |
| `pale`, `pearl`, `lilac`, `blue` | `pk.skin`, `pk.pearl`, `pk.lilac`, `pk.sac` | the parasites' half |
| `violet` | rgb(0.58, 0.36, 0.9) | where they meet |
| `knot` | rgb(0.8, 0.68, 0.98) | fused crossings |
| `petalBase` → `petalTip` | warm orange → violet | living petals |
| (private) `coreSym` / `corePar` | `pal.sapwoodDark` / `pk.core` | banded core |
| `fold` | `pk.fold` (5) | counts |

## API

### Weave

| Item | Purpose |
|---|---|
| `Weave{n = fold, twist = pk.twist, sides = 4, wobble = 0.08, knot = 1.55, knotFrom = 0.3, bands = 5, seed, part = .stem}` | options: green strands wander by `wobble` (`mg.strandTurn`/`strandSwell`), pale never; `knot` size × strand radius where parted ≥ `knotFrom`; `bands` of sap up the core |
| `weave(b, spine, ts, sec, w)` | core (banded `coreSym`↔`corePar`) + `n` green strands one way, `n` pale the other, paling where parted (green→`leafLite`, pale→`pearl`); strand tu.y = `pk.parting`; knots where pale strand j meets green j−k. **Knots dropped at coarsest LOD.** |
| `sections(stalk, out)` | fill `out` with `pk.section` along it |
| `weaveOn(b, k, id, stalk, w, t0, t1, sp, sec)` | a weave along spline `id`, `k.along`-tagged; writes back the path and sections so callers can place what rides inside (sacs) |

### Sap

| Item | Purpose |
|---|---|
| `Sac{center, radii, t, arms = 2, swirl = 0.9, phase = 0, rings = 10, segs = 14}` | arms of each sap, turns from foot to crown, phase so no two swirl alike |
| `sac(b, s)` | ellipsoid part `.bloom` (see-through), coloured by `marbled`: a smooth position field amber ↔ violet ↔ blue, so shared vertices agree |

### Fronds

| Item | Purpose |
|---|---|
| `Frond{from, out, len, r, rise = 1.1, curl = 3.0, pairs, leafLen, leafW, coil = 1.2, t0, t1, seed, leafSeed}` | `seed` shared by a crown (exact); `leafSeed` per frond (symbiotic leaflets) |
| `frond(b, f)` | plain: lilac `.tendril` stem (`pk.frondPath` arc, 8 pts) rolling into a crozier (6 pts, `coil` turns), greening toward the tip; leaflet pairs longest near the foot; furled nubs on the coil (**nubs at LOD 0 only**) |
| `frondOn(b, k, parent, u, f, branch)` | the same on its own spline; stem `k.along`, each leaflet pair and nub `k.on` at its nearest point, unfolding as the front passes; returns its id |

### Flowers

| Item | Purpose |
|---|---|
| `Bloom{heart, len, t = 1, open = 1, spin = 0, petals = fold, base, tip, seed}` | `open` 0 bud .. 1 open |
| `bloom(b, f)` | a sac bead of both saps, a calyx of `fold` lilac frondlets tipped with pearls (exact), `petals` living `mg.petal`s each its own size and lean, and `mg.stamens` (pearl filaments, gold pollen). **Every size follows `open`, counts never do** — one vertex layout for every key. |

### Rooting and helpers

| Item | Purpose |
|---|---|
| `Foot{at, r, reach, rootR, t = 0, seed}` | bulb radius, root reach, root radius |
| `foot(b, f)` | plain: `pk.nodule` bulb, `fold` pale exact roots + `fold` green braided roots between (each its own) |
| `footOn(b, k, id, f)` | the same on spline `id`: bulb swells out of its start (30% of its time), every root a branch `.after = .with` |
| `rootPath(at, a, from, reach, wobble, seed, c)` | a root from the bulb toward bearing `a`, low over the ground then down |
| `taper(b, p, r, tip, t0, t1, col, part, sides)` | a tapering tube along `p`, never thinner than 2e-4 (keeps caps) |

### The confluence

`confluence(b, genome, seed, growth)` builds the `confluence` plant form
at `growth` 0..1. Meshgen builds `keys` = 8 keys, at `variant/(keys-1)`.

It tells the meeting from the ground up:
1. Out of opposite corners rise a symbiote's braided leafy trunk on green
   roots, and a parasite's lattice stalk with sacs on a pale bulb.
2. They wind round each other (1.15π) and close in.
3. They **fuse** at `fuseT` (0.42) into one `weave`.
4. The weave gives onto the canopy at `canopyT` (0.78): a great `sac`,
   five lilac boughs with leaves each ending in a `bloom`, and a crowning
   `bloom` lifting clear as it opens.

Stages via `Grown.at`: `rise` (trunks), `reach` (boughs), `bloom`
(flowers).

**Nothing appears or vanishes with growth**: what isn't grown yet is just
small. So every key keeps one vertex layout, which plant.vert's key
blending requires.

## Who uses it

| User | Uses |
|---|---|
| `meshgen.zig` (form `.confluence`) | `confluence` — species `confluence` |
| `weftstone.zig` | `weaveOn`, `frondOn`, `sac`, `taper`, palette, `fold` |
| `driftbraid.zig` (approved reference look) | `weaveOn`, `footOn`, `bloom`, `sac`, palette, `fold` |
| `monfris.zig` | `weave`, `weaveOn`, `sections`, `bloom`, `sac`, `rootPath`, palette |
| `vultrixi.zig` | `sac`, palette (`petalBase`/`petalTip`, `pale`, `pearl`), `fold` |

## GPU side

- **Confluence**: 8 growth keys of one vertex layout, blended in plant.vert
  (binding 2, `FORMS_KEYED`); sway ×1.5; translucent violet petals.
- **Cage strands**: tu.y = parting (as the parasites').
- **Sacs**: part `.bloom`, `fade < 1`: see-through in the glass pass;
  `sapGlisten`.
- **Structure pieces**: `vertex.Grow` from `k.along`/`k.on`, grown in
  part.vert.

## Rules

- Mix at every scale; never a symbiotic piece stacked on a parasitic one.
- Exact fives for counts and layout. Symbiotic variation only in what each
  of the five carries (leaflets, petal sizes, green strand wander, green
  root lengths).
- For the confluence: pass sizes, never counts, through `open`/`Grown`.
- Check: `--plant=confluence --state=grow`,
  `--structure=weftstone|driftbraid|monfris|vultrixi --state=grow` (pairs
  and tethers need `--demo`).
