# mineral_kit

`src/gfx/meshes/mineral_kit.zig` (89 lines). Imports: `meshgen` (`mg`),
`vertex`, `core/math`, `core/color`, `core/rng`.

## What it is

Shared pieces for the ground's minerals: crystals and weathered stones.
Not a mesh itself.

Crystals are **flat-faced**: each triangle has its own normal, so they
catch the light as cut planes, like a gem. Stones are smooth boulders
ground down to worn faces. Not grown, not on splines.

## API

| Item | Purpose |
|---|---|
| `facet(b, p:[3]V3, inside, col:[3]Rgba8, t, part)` | one flat-shaded triangle, wound and facing away from `inside` (the core primitive; radiant_kit's `cut` uses it) |
| `Crystal{base, dir, len, r, sides = 6, point = 0.28, col, tip, part = .bloom}` | a crystal's shape; `point` = the share of length taken by the pyramidal tip |
| `crystal(b, c, rng)` | a faceted prism from its base (sunk a little, foot at −r) to a pyramidal point; faces slightly uneven (radius ×0.85–1.12, top ×0.85–1); colour `col` → `tip`; tu.x 0 at the foot, 0.3 on the sides, 1 at the tip |
| `stone(b, at, r, flat, col, lite, rng)` | a weathered boulder, a third sunk: a lat-long sphere (12 rings x 18 sides at full detail) swelled by 4 lumps and ground down to 7 worn faces, each rounded into the body (`smin`), smooth normals; `col` paling to `lite` up its sky-turned faces; part `.stone` |

## Who uses it

| User | Uses |
|---|---|
| `node_ley.zig` | `crystal` (violet cluster), `stone` |
| `node_grit.zig` | `stone` (faceted stones), `crystal` (quartz chips) |
| `lithophage.zig` | `crystal` (the crystal budding on its coral, crystals on its limbs and runners), `stone` (crust heaved where a tendril surfaces) |
| `mote.zig` | `facet` (star mote's faceted core) |
| `radiant_kit.zig` | `facet` (in `cut`), `crystal` (in `shards`) |

## GPU side

- Crystals default to part `.bloom`: see-through in the glass pass, hue
  from vertex colour.
- Radiant cuts/shards pass `.prism` instead (part.frag `PRISM_*`).
- Ley shards are points of light (`Parts.light`).
- Stones are `.stone`: solid, lit, shadowed; part.frag gives them grain,
  flecks, hollows and lichen in mesh space.

## Rules

- Crystals stay flat-faced; stones are smooth.
- No growth: a node's minerals are just there. A structure that makes a
  crystal scales it by `growth.formed(form, grown)`, or by its own
  progress, in the mesh that emits it.
- Check: `--structure=lithophage --state=active` (crystals on its coral
  and runners).
  Nodes appear around any `--structure` specimen.
