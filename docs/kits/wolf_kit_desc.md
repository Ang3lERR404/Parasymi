# wolf_kit

`src/gfx/meshes/wolf_kit.zig` (391 lines). Imports: `meshgen` (`mg`),
`vertex`, `sculpt_kit` (engine `gfx/sculpt.zig`, `Sculpt`), `core/math`, `core/color`.

## What it is

Shared pieces for **the wolf's body** (the player, a vine-wolf): the leaves that
lie over it like fur, resin lobes grown over the hide (pectorals, rear), and the
digits and claws of hands and feet ("forms of planes": superellipsoids, flat
faces, rounded edges, curved claws). Not a mesh itself. The skin they sit on is
`sculpt_kit`'s.

## API

| Item | Purpose |
|---|---|
| `Form{center, radii, ns = 0.7, ew = 0.7, col, part = .stem, t = 0.5, rings = 10, segs = 14}` / `form(b, f)` | a superellipsoid closed at its poles: `ns` squareness down its height, `ew` around it (1 round → 0 flat faces, sharp edges); rings/segs reduced per LOD (`b.around`) |
| `Leaf{base, along, out, len, width, lift = 0.35, curl = 0.25, cup = 0.25, col, tip, t = 1}` / `leaf(b, l)` | a fur leaf: base flush with the surface, lifting off (`lift`), curling back at the tip (`curl`), cupped toward the body; lanceolate (narrow claw, broadest a third along, long point); a `mg.lamina` with a vein in the cup; tu.y base→tip (the shader moves tips, never the base); part `.leaf` |
| `resinLobe(b, s:*const Sculpt, at, Shape, rings, steps, col, t)` | a lobe of resin laid over the hide: every outline point cast from one point deep behind the lobe (always inside) to where its ray last leaves the body (`s.castOut`); a hit far from where the previous ring predicts it (> 12 mm: out through the thigh) is replaced by `s.project` of the prediction. A smooth sheet draped over the hide (60 smoothing passes, never sinking in), settling onto the hide from 0.55 of the radius; raised by `Shape.height` along the sheet's facing, turning to the hide's own only from 0.85 out (offset along the hide's normal over a crease tighter than the lobe's height folds it). The face stands 1.5 mm clear of the hide (the hide's facets lie outside its true surface in creases) and dives under it over the outer 8% to meet the base (4 mm under); one watertight sheet. Every vertex part `.resin`, tu.y 0 on the body → 1 at the crown, **skinned to the hide where it lies** (`s.weigh`) |
| — `Shape` (comptime) must provide | `outline(a) [2]f32` (x, y at unit radius for angle `a`), `height(k, a, x, y)` (k 0 crown .. 1 rim, falling to 0 with no slope at the rim), `CROWN` |
| `claw(b, base, dir, down, len, r, col)` | a curved tapering hook bending toward `down`, closed to a point; part `.thorn` |
| `Digit{base, dir, down = -y, len, r, col, claw}` / `digit(b, d)` | a knuckle and two segments (`form`s, each lower and narrower) arching from `base` along `dir` to the ground, then its `claw` |

## Who uses it

| User | Uses |
|---|---|
| `wolf_body.zig` | `leaf` (fur over crown, forelock, nape mane, cheekbones, shoulder tufts, tail rings and tip; placed with `Sculpt.project` + skinned by `weigh`), `digit`, `claw` |
| `wolf_belly.zig` | `leaf` |
| `wolf_pec.zig` | `resinLobe` (pectorals on the chest) |
| `wolf_rump.zig` | `resinLobe` (the rear on the pelvis, lower edge following the thighs) |

## GPU side

- Skinned through `vertex.Skin` (see sculpt_kit). `.resin` lobes have a sprung
  `give` in part.vert; tu.y gives their height for resin shading (`sapGlisten`,
  bubbles/droplets), drawn in the glass pass.
- `.leaf` fur lifts and breathes; tips move, bases stay.

## Palette

The wolf's colours live in `palette.zig`: `wolf_core`, `wolf_vine`,
`wolf_leaf_dark`, `wolf_leaf_lite`, `wolf_claw` (muted greens/browns; amber only
on belly, eyes, inner ears, beans, pectorals, rear).

## Test

`"a fur leaf's base stays on the surface it grows from"`: every tu.y = 0 vertex
sits on the surface. `"a resin lobe never folds over itself"` (wolf_rump.zig):
every quad of the rear's and the pectorals' raised face faces away from the
base under it.

## Rules

- Build in bind space, skin everything to the sculpt; no rigid parts.
- Fur leaves are laminae (body, bevel, vein), per the leaf convention.
- Wolf overhauls set the bar for the whole wolf (cohesion rule).
