# convergence_kit

`src/gfx/meshes/convergence_kit.zig` (955 lines). Imports: `meshgen` (`mg`),
`parasiteKit` (`pk`), `palette` (`pal`), `growth`, `vertex`, `sim/species`,
`core/math`, `core/color`, `core/rng`.

## What it is

The **lineages mixed**: what grows where symbiote and parasite have become
one body. Not a mesh itself.

It is shared by:
- the confluence (a plant, grown through keys);
- the convergent structures (on growth splines, the `*On` pieces).

It is not one laid over the other. The two are **grown into each other**,
so neither is ever seen alone:

- **Stalk** (`weave`), a blend the gardener chose of two looks (grafted
  stems, a soft body):
  - out of the soil rise **two stems**: a symbiote's green braided one,
    wandering, carrying leaves on their own stalks; and a parasite's pale
    smooth one, swelling at its exact nodes (its own skin thickening and
    paling to pearl, lilac at the middle, never a ring stuck on);
  - they wind round each other, apart between their grafts and touching
    at each; wherever they touch they are **grown together in one smooth
    callus** (green on the green side, pale on the pale, a violet seam
    wandering between, lit lilac along its middle);
  - at `fuse` they become **one soft see-through body** as wide as the
    stalk's cage: two skins (pale flushed violet, warmed amber at the
    foot), green strands and amber lanes winding up inside, a pale vein
    up the middle, five pale ribs exact on the skin.
- **Sap** (`sac`): amber and pale blue swirling round each other in arms,
  violet where they mingle; never stirred smooth.
- **Counts**: the parasites' exact fives (`fold`), turned evenly and grown
  alike. But what each of the five carries is a symbiote's, each a little
  different:
  - a lilac **frond** bearing green leaflets, ending in a fern crozier (a
    tightly rolled tip);
  - a **bloom** of a pale frondlet calyx holding warm living petals with
    stamens.
- **Foot**: rooted both ways, **no bulb**. The stems flare gently into
  the soil; from under them leave five exact pale roots, and a green
  braided symbiote root between each two.

The driftbraid's look is the reference for this kit.

## Colours

| Name | Source | Use |
|---|---|---|
| `green`, `leafDark`, `leafLite`, `amber` | `pal.vine`, `pal.leafDark`/`pal.leafLite`, `pal.sap` | the symbiotes' half |
| `pale`, `pearl`, `lilac`, `blue` | `pk.skin`, `pk.pearl`, `pk.lilac`, `pk.sac` | the parasites' half |
| `violet` | rgb(0.58, 0.36, 0.9) | where they meet: a callus's seam |
| `knot` | rgb(0.8, 0.68, 0.98) | the lilac light along a seam |
| `tissueLow` → `tissue` | warm amber → violet | the body's skin, foot to crown (`Weave.skin` overrides) |
| `petalBase` → `petalTip` | warm orange → violet | living petals |
| `fold` | `pk.fold` (5) | counts |

## API

### Weave

| Item | Purpose |
|---|---|
| `Form` | `rooted` (out of the soil: stems, then the body), `limb` (off another weave: the body alone), `stems` (the stems the whole way, fused at the end into what they meet) |
| `Weave{form = .rooted, fuse = 0.38, leaves = 5, seed, skin = {tissueLow, tissue}}` | what it grows as, how far along the stems fuse into the body, leaves on the green stem, the body's skin colours (the confluence passes paler: a plant's glass draws them stronger) |
| `weave(b, spine, ts, sec, w)` | the stems and/or body along `spine`. Stems: as thick as half the stalk woven shut (its foot flare capped at 1.4× so it never reads as a bulb), grafts at 0.25, 0.75 and fused at 0.97 of their climb, each callus no longer than a share of the climb. Body: as wide as the stalk's cage (`open + strand`), rising thin out of the fusing callus |
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
| `Foot{at, r, reach, rootR, t = 0, seed}` | root crown width (roots leave `crownOut` = 0.3 of it out), root reach, root radius |
| `foot(b, f)` | plain: no bulb; `fold` pale exact roots + `fold` green braided roots between (each its own) |
| `footOn(b, k, id, f)` | the same on spline `id`, every root a branch `.after = .with` |
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
| `weftstone.zig` | `sac`, `taper`, palette (`knot`, `pale`, `green`), `fold` |
| `driftbraid.zig` (approved reference look) | `weaveOn`, `footOn`, `bloom`, `sac`, palette, `fold` |
| `monfris.zig` | `weave` (`.limb`), `weaveOn` (corners `.stems`), `sections`, `bloom`, `sac`, `rootPath`, palette |
| `vultrixi.zig` | `sac`, palette (`petalBase`/`petalTip`, `pale`, `pearl`), `fold` |
| `nebularbor.zig` | `weaveOn` (trunk rooted, limbs `.limb`), `footOn`, `bloom`, `sac` |
| `polyp_convergent.zig` | `weaveOn`, `footOn`, `frondOn`, `bloom`, `sac` |
| `arsthraxia_convergent.zig` | `weaveOn` (`.stems`), `footOn`, `frondOn`, `bloom`, `sac` |
| `root_well.zig`, `tanglehold.zig` | `weaveOn` (`.stems`: a short foot under a basket), `footOn`, `sac` |
| `storm_spire.zig` (samples) | `weaveOn`, `footOn`, `sac`, `taper` |

## GPU side

- **Confluence**: 8 growth keys of one vertex layout, blended in plant.vert
  (binding 2, `FORMS_KEYED`); sway ×1.5; translucent violet petals.
- **Body and sacs**: part `.bloom`, `fade < 1` (the structure's `sap`):
  see-through in the glass pass; `sapGlisten`. A plant's glass (the
  confluence) draws the body's skin stronger, so it passes paler colours.
- **Structure pieces**: `vertex.Grow` from `k.along`/`k.on`, grown in
  part.vert.

## Rules

- Mix at every scale; never a symbiotic piece stacked on a parasitic one.
- Exact fives for counts and layout. Symbiotic variation only in what each
  of the five carries (leaflets, petal sizes, green strand wander, green
  root lengths).
- No root bulbs (`pk.nodule` at a foot): the gardener found them ugly.
  Stems flare gently and roots leave from under them.
- Stems out of the soil (`.rooted`, `.stems`); off another weave, the
  body alone (`.limb`). A short stub under a basket is `.stems`, never a
  squat body.
- For the confluence: pass sizes, never counts, through `open`/`Grown`.
- Check: `--plant=confluence --state=grow`,
  `--structure=weftstone|driftbraid|monfris|vultrixi --state=grow` (pairs
  and tethers need `--demo`).
