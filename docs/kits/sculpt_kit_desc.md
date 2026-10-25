# sculpt_kit

`src/gfx/meshes/sculpt_kit.zig` (524 lines). Imports: `meshgen` (`mg`),
`vertex`, `core/math`, `core/color`.

## What it is

Sculpts **one seamless surface out of many forms** (the wolf's skin):

1. Each form (ellipsoid, rounded cone, rounded box) is a **signed distance
   field**, owned by a bone.
2. Forms melt together by **smooth union** (`smin`, per-form melt `k`) or are
   carved by smooth subtraction (`carve`); `ink` forms only colour.
3. The whole is meshed once at startup with **surface nets**: one vertex per
   surface cell, pulled onto the surface, normal = field gradient.
4. Each vertex is **weighted to the bones** of the forms it lies nearest
   (smoothly, only across joints that are actually joined: the nearest bone,
   its parent, its children), so the mesh bends as one skin (`vertex.Skin`,
   part.vert skinned mode 3).

Sampling is sparse: only 8³-cell blocks the surface can pass through are
evaluated, each with only the forms whose bounding sphere reaches it.

## API

| Item | Purpose |
|---|---|
| `Shape = union { ellipsoid{c, r}, cone{a, b, ra, rb}, box{c, half, round} }` | the SDF primitives (round cone rounded at both ends; box half extents include rounding) |
| `Form{shape, at = identity, stretch = 1, bone, col, k = 0.03, carve = false, ink = 0, soft = 0}` | `at` places shape space; `stretch` scales it first (a wide muzzle from a round cone, distance scaled back); `k` melt (m); `ink` > 0 = colour-only, fading over that many metres; `soft` = per-bone joint softness (small for a finger) |
| `Hit{p, n}` | a surface point and outward normal |
| `Sculpt{gpa, parents:[]const ?u8, soft = 0.02, blend = 0.012, only = all bones}` | the sculpt; `parents` per bone (weights spread only along joints); `blend` how softly colours meet; `only` bitmask keeps a subset of bones (a surface cast onto part of a body, e.g. ears) |
| `deinit()` / `add(form)` | add a form (skipped if its bone isn't in `only`); computes inverse (`m.inverseAffine`), bound centre and reach |
| `project(p) Hit` | nearest surface point (6 steps down the field) and normal |
| `cast(from, dir, max) ?Hit` | where a ray from inside comes out of the body (sphere-trace + 12 bisections); null if never within `max` or `from` is not inside |
| `castOut(from, dir, max) ?Hit` | where a ray from inside *last* comes out within `max` (marched back in from the far end), past any part it re-enters: what a sheet laid over the body lies on; null if `from` is not inside or `max` still is |
| `weigh(p) vertex.Skin` | skin weights at `p` (exp falloff over `soft`, only joined bones) |
| `pack(w)` | per-bone weights → the four heaviest, dropping < 3% of the top, unorm summing to 255 |
| `packWith(w, slope)` | `pack` plus each kept bone's weight gradient (`gx/gy/gz`), so normals bend by the true Jacobian |
| `mesh(b, h, t, part)` | mesh with cell size `h`; every vertex `part`, tu (`t`, 0), skin weights written via `b.skinOf` |

## Who uses it

| User | Uses |
|---|---|
| `wolf_body.zig` | `Sculpt`, `Form`, `Shape`: `sculptBody` adds forms per bone of `wolf_skeleton`'s bind pose; `mesh(b, CELL << lod, 0.5, .stem)` (`CELL` 5 mm, doubled per LOD); `cast` to lay vines onto the hide; `project` + `weigh` for fur leaves |
| `wolf_ears.zig` | `Sculpt.pack` (ear skins) |
| `wolf_belly.zig` | `Sculpt.packWith` (belly weights + slopes for the swelling sac) |
| `wolf_kit.zig` | `Sculpt` (`resinLobe` casts out onto it with `castOut`, `project`s strays, weighs) |

## GPU side

- `vertex.Skin` (binding 2) beside the mesh buffer; bones per frame via
  `Parts.pose`/`emitSkinned`, buffer device address in `WorldPush.bones`;
  part.vert placement mode 3 (`e.y` first bone), normals bent by slopes.

## Rules

- New wolf meshes are built **in bind space and skinned**; never rigid parts.
- Weights only cross joined bones, so a surface never jumps across a gap.
- Linear algebra only through `m` (`m.inverseAffine`); a singular form matrix is
  a bug.
- Sculpting is startup cost (once per LOD); keep forms bounded (`reach`) so the
  sparse sampling stays sparse.
