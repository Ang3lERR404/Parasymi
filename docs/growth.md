# Structures grow along growth splines

Every structure grows like a plant: along hidden curves (growth splines),
trunk first, never by scaling the whole thing up. Think of a vine
creeping along a wire: the mesh appears where the growing front has
passed.

The code: engine `gfx/growth.zig` (`Grower(M, leaf)`), made for the garden
in `src/gfx/growth.zig` (its leaves are `meshgen.leafAt`).

## What grows this way
Every structure mesh, and any piece of one that grows, is built this way,
never grown by scaling the whole:

- **Sap cache, germinator, polyp, loomfern, sporecaster.**
- **Arsthraxia**, and its research vines and offshoots.
- **Root-digger**, and its roots; the digging root to its node is grown by
  how far it reaches.
- **Conduit:** each arch is its own spline; side roots are grown by how
  far they reach.
- **Lithophage**, and its roots. **Ganglion**, and its nerves.
- **Braided conduit:** the weave and each lane are their own meshes on the
  same spline.
- **Gathering crown**, and its roots (`Root(n)` per distance).
- **The convergent structures.**

The diamond is the exception. It belongs to the radiant lineage: gathered,
not grown (`radiantKit`,
[kits/radiant_kit_desc.md](kits/radiant_kit_desc.md)).

## Building
### 1. Lay out the skeleton
A mesh's `build` lays out a hidden `Skeleton`:

```zig
var sk = growth.Skeleton.begin(b);
sk.trunk(ctrl, .{});
sk.branch(parent, u, ctrl, .{});          // off the trunk or another branch
sk.vine(parent, u, mg.Growth, n, .{});
```

A branch's first point is moved onto its parent at `u` (how far along the
parent, 0 to 1). Splines are Catmull-Rom (smooth curves that pass through
every control point), resampled to `growth.res` points
(`sk.get(id).pts`).

### 2. Build along it
- **One call:** `sk.tube`, `sk.braid`, `sk.leaves` do it all.
- **Anything else:** build with the usual primitives, then tag what was
  built since a `b.mark()`, in one of two ways:
  - `sk.along(b, mark, id)`: each vertex grows out of its nearest point on
    the spline as the front passes. For tubes, braids, lofts, pods,
    bundles.
  - `sk.on(b, mark, id, u, .{.from, .delay, .span})`: one piece grown out
    of one point once the front reaches `u`. For a leaf, petal, cup,
    stamens. Stagger a whorl with `.delay`.

### 3. Finish
End with `sk.finish(b)`. It turns times into shares of the growth. A debug
assert in `meshlib.build` catches a skeleton left unfinished.

## Timing
Timing comes from the skeleton alone, never hand-set.

- **Length:** a spline takes time in proportion to its length
  (`Branch.pace`). Its front tapers over `Branch.front`.
- **When a branch starts:**
  - once its parent is done (`After.done`, the default);
  - as the parent's front passes it (`.passing`);
  - with it (`.with`, e.g. roots);
  - `.delay` waits longer.
- `grownScale` is a structure's research size only. Nothing shoots up or
  fills out (the old whole-structure scale is gone).

### Emitted pieces
Pieces a structure emits on its own (cups, cores, satellites) form in a
last share of the growth, kept free by `sk.tail = form` (`form` is a
`pub const` in the mesh file).

- **A mesh of its own** carries that window:
  `growth.tag(b, mark, from, growth.tailWindow(form))`, emitted with
  `.grown = s.grown`.
- **One the game places and sizes itself** scales by
  `growth.formed(mesh.form, s.grown)`: the same curve.
- Never a separate hand-tuned threshold.
- **A piece grown by something else** (an offshoot by research progress)
  gets its own skeleton, and that progress as `.grown`.

## On the GPU
Each vertex carries `vertex.Grow`: `from` and `at` (start, span, spline
start, spline done). Binding 3, locations 21–22; zero = not on a spline.

part.vert (engine growth.glsl `growOut`) does the growing:

- It shrinks the vertex into `from` until the structure's growth
  (`PartInstance.w.w`, `Look.grown`) reaches it, then grows it out.
- It stays thin (`SPROUT_THIN`) until its spline is done.
- Foliage tips lag (`LEAF_LAG`).

`b.xform` carries `from` along.

## Watching
- Growing: `--structure=<kind> --state=grow` (with `--inspect=<kind>` for
  shots).
- Its emitted pieces at work: `--state=active` ([testing.md](testing.md)).
- No scratch edits.
