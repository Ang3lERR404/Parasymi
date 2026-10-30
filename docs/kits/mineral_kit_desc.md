# mineral_kit

`src/gfx/meshes/mineral_kit.zig` (89 lines). Imports: `meshgen` (`mg`),
`vertex`, `core/math`, `core/color`, `core/rng`.

## What it is

Shared pieces for the ground's minerals: crystals and faceted stones. Not
a mesh itself.

They are **flat-faced**: each triangle has its own normal, so they catch
the light as cut planes, like a gem. Not grown, not on splines.

## API

| Item | Purpose |
|---|---|
| `facet(b, p:[3]V3, inside, col:[3]Rgba8, t, part)` | one flat-shaded triangle, wound and facing away from `inside` (the core primitive; radiant_kit's `cut` uses it) |
| `Crystal{base, dir, len, r, sides = 6, point = 0.28, col, tip, part = .bloom}` | a crystal's shape; `point` = the share of length taken by the pyramidal tip |
| `crystal(b, c, rng)` | a faceted prism from its base (sunk a little, foot at −r) to a pyramidal point; faces slightly uneven (radius ×0.85–1.12, top ×0.85–1); colour `col` → `tip`; tu.x 0 at the foot, 0.3 on the sides, 1 at the tip |
| `stone(b, at, r, flat, col, lite, rng)` | a faceted stone, half sunk: a 7-point mid ring + an offset upper ring, a flat-ish crown, a buried bottom; part `.stem` |

## Who uses it

| User | Uses |
|---|---|
| `node_ley.zig` | `crystal` (violet cluster), `stone` |
| `node_grit.zig` | `stone` (faceted stones), `crystal` (quartz chips) |
| `lithophage.zig` | `crystal` (the crystal in its crop) |
| `mote.zig` | `facet` (star mote's faceted core) |
| `radiant_kit.zig` | `facet` (in `cut`), `crystal` (in `shards`) |

## GPU side

- Crystals default to part `.bloom`: see-through in the glass pass, hue
  from vertex colour.
- Radiant cuts/shards pass `.prism` instead (part.frag `PRISM_*`).
- Ley shards are points of light (`Parts.light`).
- Stones are `.stem`: solid, lit, shadowed.

## Rules

- Keep it flat-faced; no smoothed normals here.
- No growth: a node's minerals are just there. A structure that makes a
  crystal scales it by `growth.formed(form, grown)`, or by its own
  progress, in the mesh that emits it.
- Check: `--structure=lithophage --state=active` (crystal in its crop).
  Nodes appear around any `--structure` specimen.
