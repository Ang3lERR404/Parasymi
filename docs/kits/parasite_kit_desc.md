# parasite_kit

`src/gfx/meshes/parasite_kit.zig` (471 lines). Imports: `meshgen` (`mg`),
`growth`, `vertex`, `sim/species` (Genome), `core/math`, `core/color`,
`core/rng`. Imported by `convergenceKit` as `pk`.

## What it is

The **parasitic lineage's body**, shared by its plants (`plant`, the
`coil` form) and its structures. Not a mesh itself.

It is alien, not hostile: plainly a deviation from the symbiotes.

**It opens up.** A symbiote winds its strands tight round its core, each a
little different. A parasite's strands come up woven the same way (both
ways at once), and then:
- **part from the core into an open lattice cage** (`lattice`), with
  pearl beads where they cross;
- the core thins to a filament inside;
- **sacs of thin-film sap hang on it in plain view** (`organs`);
- then the strands gather to the core again.

**It is too exact.** Everything comes in fives (`fold`), turned evenly,
grown alike (one seed for every frond of a crown), never a golden angle.

**It repeats itself.** Each frond ends in a small cage of its own (`pod`),
crowned in turn by five frondlets.

**Its look**: pale pearl skin, lilac fronds, a bulbous foot half sunk in
the soil, pale exact roots.

On a structure, every piece grows on growth splines. A plant grows by
tu.x, and its cage parts as it matures (plant.vert reads tu.y = how far
each strand has parted).

## Constants

| Name | Value | Meaning |
|---|---|---|
| `skin` | rgb(0.56, 0.54, 0.62) | its skin / strands |
| `core` | rgb(0.39, 0.37, 0.45) | the core showing between strands |
| `pearl` | rgb(0.78, 0.74, 0.84) | youngest growth, beads, roots |
| `lilac` | rgb(0.68, 0.62, 0.82) | fronds |
| `sac` | rgb(0.46, 0.62, 0.86) | thin pale-blue sap |
| `fold` | 5 | how many of everything |
| `twist` | 1.6π | turn of the strands along a stalk, each way |
| `wobble` | 0.05 | a plain weave (nerve) is tighter than a symbiote's |

## API

### The lattice (the body)

| Item | Purpose |
|---|---|
| `Section{core, tight, open, strand}` | cross-section at one point: core radius, radius strands lie at woven tight, radius they've parted to (≥ tight), strand radius |
| `parting(s) f32` | how far a section has parted, from 0 (woven) toward 1: `1 - tight/open` |
| `Lattice{n = fold, twist = twist, sides = 4, node = 1.9, nodeFrom = 0.3, part = .stem, core, strand, bead}` | lattice options; `node` = bead size × strand radius (0 none), only where parted ≥ `nodeFrom` |
| `lattice(b, spine, ts, sec, l)` | core tube + `n` strands each way at exactly even turns (parallel-transported frames), lifting into a cage where parted and paling toward pearl; beads where strands cross (every π/(n·twist) along it). Strand tu.y = `parting`. **Beads dropped at the coarsest LOD.** |
| `Stalk{girth, part = 2.6, from = 0.15, to = 0.85, foot = 0.9, twist, sides = 4, node = 1.9}` | a stalk's shape: woven at its foot, a cage over `from..to`, gathering above; `part` = how far strands part at widest (× woven radius); `foot` = swell into the foot |
| `parted(s, u)` | cage opening at `u` (0..1), shaped `1 - cos⁴`: eased both ways so strands leave and rejoin with no kink |
| `section(s, u)` | the `Section` at `u`: braid-proportioned (`mg.braidCore`/`braidOff`/`braidStrand`), core thinning 65% where open |
| `stalk(b, k, id, s)` | the stalk along spline `id`, `k.along`-tagged (tu.x 0..0.85) |

### Organs, foot, roots

| Item | Purpose |
|---|---|
| `organs(b, k, id, s, n, fill)` | `n` sacs threaded on the core inside the cage, evenly over the parted stretch, each `fill` of the cage, never touching; each swells as the front reaches it (`bladder`) |
| `foot(b, k, id, at, radii)` | bulbous foot (`nodule`) swelling out of the stalk's root over 30% of its time |
| `nodule(b, at, radii, t, skin, dark, light)` | a bulb shaded pearl toward the light, dark core underneath (colour by normal: a smooth field, so shared vertices agree) |
| `roots(b, k, id, n, reach, r, seed)` | `n` pale roots, out low then down, exactly alike; each a branch `.after = .with`, part `.tendril` |
| `bladder(b, k, id, u, center, radii, t, on)` | translucent sac (part `.bloom`, colour `sac`): the instance `fade` makes it see-through; swells at `u` |

### Fronds, crowns, pods

| Item | Purpose |
|---|---|
| `frondPath(from, out, len, rise, curl, seed, pts)` | control points: heading starts at `rise`, turns ever faster (`curl` at tip; negative turns up), steps shrinking; one seed for a crown → fronds alike |
| `Frond{out, len, r, rise = 1.25, curl = 5.2, tip = 0.12, t0 = 0.6, seed, grow}` / `frond(b, k, parent, u, f)` | a lilac `.tendril` tube on its own branch; returns its spline id |
| `Crown{spin, len, r, rise = 0.4, curl = -1.1, t0, seed, grow, pod = 0}` / `crown(b, k, parent, u, c)` | `fold` fronds alike, turned evenly from `spin`, all at once; with `pod > 0` each ends in a `pod` (frond tip sized to `podFoot`) |
| `Pod{len, girth, t, part = .tendril, skin, core, pearl, frond, sac, seed}` | a pod's look |
| `podGirth(len)` = len·0.085, `podFoot(girth)` | a pod's girth for its length; its width at the foot (where its frond meets it) |
| `podAt(b, at, axis, p)` | the body again, small: a 3-sided lattice parting round a sac, gathering into a pearl bead, `fold` frondlets springing from it. **Frondlets only at LOD 0.** No skeleton (used by plants directly) |
| `pod(b, k, id, p)` | `podAt` at the tip of frond `id`, on its own branch grown once the frond is done; returns that id |

### The plant

`plant(b, genome, seed)` builds the `coil` form: upright and exactly
symmetric. Variants differ in proportion only.

What it reads from the genome:
- colours: `stemCol` (skin; dark = shade 0.7, light = mixed toward white),
  `leafCol` (fronds), `bloomCol` (sap);
- sizes: `stemH`, `stemR`, `bloomR` (neck bulb);
- counts: `thorns` (number of sacs), `tendrils` (number of crown fronds).

What it builds:
- a 25-point, dead-upright lattice stalk (cage from 0.12 to ~0.78);
- a bulbous foot and `fold` pale roots;
- sacs on the core, and a sap bulb at the neck;
- a candelabrum of fronds, each ending in `podAt`.

tu.x is height (the crown is 0.85..1).

## Who uses it

| User | Uses |
|---|---|
| `meshgen.zig` (plant form `.coil`) | `plant` — species `thornleech` |
| `lithophage.zig` | `stalk`, `foot`, `roots`, `organs`, `bladder`, palette, `fold` |
| `ganglion.zig` | `stalk`, `foot`, `roots`, `organs`, `bladder`, `nodule`, `wobble`, palette |
| `sporecaster.zig` | `stalk`, `foot`, `roots`, `organs`, `bladder`, `frondPath`, `pod`, `podGirth`, `podFoot`, palette |
| `convergence_kit.zig` | `Section`, `Stalk`, `section`, `parting`, `lattice`, `frondPath`, `nodule`, `fold`, `twist`, palette |
| `driftbraid`, `monfris`, `vultrixi` | `Stalk`/`Section`, `nodule`, `frondPath`, `core` (via convergent meshes) |
| `weftstone` | `nodule` (knots, nodes, vane pearls) |

## GPU side

- **plant.vert**, `FORMS_PARTING` (= coil): parts the cage from the foot
  up as the plant matures, using strand tu.y (how far that strand has
  parted at full growth).
- **plant.vert**, `FORMS_CROWNED` (= coil): the crown starts closed and
  opens with growth.
- Parasites are the only things that **writhe** in the wind. Everything
  else bends from its root.
- Sacs/bladders are part `.bloom` with instance `fade < 1`: fresnel
  see-through (brighter at grazing edges), hue from vertex colour, drawn
  in the glass pass.
- Structure pieces carry `vertex.Grow` from `k.along` / `k.on` (see
  structure_kit's GPU notes).

## Rules

- Counts are `fold`, turned evenly; one seed per crown. No golden angles,
  no per-frond randomness (that's the symbiotes').
- Plants are exactly symmetric and dead upright.
- Don't mix with `structureKit` pieces for a convergent look; use
  `convergenceKit`.
- Check: `zig build run -- --plant=thornleech --state=grow`,
  `--structure=lithophage|ganglion|sporecaster --state=grow|active`.
