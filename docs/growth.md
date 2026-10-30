# Structures grow along growth splines

Engine `gfx/growth.zig` (`Grower(M, leaf)`), made for the garden in
`src/gfx/growth.zig` (its leaves `meshgen.leafAt`). Every structure mesh (and any piece of one that grows) is
built this way, never grown by scaling the whole. That is: sap cache,
germinator, arsthraxia (and its research vines and offshoots), root-digger
(and its roots, the digging root to its node grown by how far it reaches),
polyp, conduit (each arch its own spline; side roots grown by how far they
reach), loomfern, lithophage (and its roots), braided conduit (weave and
each lane its own mesh on the same spline), ganglion (and its nerves),
gathering crown (and its roots, `Root(n)` per distance), sporecaster, and
the convergent structures. The diamond is the radiant lineage's: gathered,
not grown (`radiantKit`, [kits/radiant_kit_desc.md](kits/radiant_kit_desc.md)).

## Building
- A mesh's `build` lays out a hidden `Skeleton`: `var sk =
  growth.Skeleton.begin(b)`, `sk.trunk(ctrl, .{})`, then `sk.branch(parent,
  u, ctrl, .{})` / `sk.vine(parent, u, mg.Growth, n, .{})` off it (a
  branch's first point is moved onto its parent at `u`). Splines are
  Catmull-Rom, resampled to `growth.RES` points (`sk.get(id).pts`).
- Build along it: `sk.tube`, `sk.braid`, `sk.leaves` do it in one call; for
  anything else build with the usual primitives, then tag what was built
  since a `b.mark()`: `sk.along(b, mark, id)` (each vertex grows out of its
  nearest point on the spline as the front passes: tubes, braids, lofts,
  pods, bundles) or `sk.on(b, mark, id, u, .{.from, .delay, .span})` (one
  piece grown out of one point once the front reaches `u`: a leaf, petal,
  cup, stamens; stagger a whorl with `.delay`).
- End with `sk.finish(b)` (it turns times into shares of the growth; a
  debug assert in `meshlib.build` catches a skeleton left unfinished).

## Timing
- The skeleton's alone, never hand-set: a spline takes time ∝ its length
  (`Branch.pace`), its front tapers over `Branch.front`; a branch starts
  once its parent is done (`After.done`, default), or as the parent's front
  passes it (`.passing`), or with it (`.with`, e.g. roots); `.delay` waits
  longer.
- `grownScale` is a structure's research size only; nothing shoots up or
  fills out (the old whole-structure scale is gone).
- Pieces a structure emits on its own (cups, cores, satellites) form in a
  last share kept free by `sk.tail = form` (a `pub const` in the mesh
  file): a mesh of its own carries that window (`growth.tag(b, mark, from,
  growth.tailWindow(FORM))`, emitted with `.grown = s.grown`); one the game
  places and sizes itself scales by `growth.formed(mesh.FORM, s.grown)`,
  the same curve. Never a separate hand-tuned threshold. A piece grown by
  something else (an offshoot by research progress) gets its own skeleton
  and that progress as `.grown`.

## On the GPU
Each vertex carries `vertex.Grow` (`from`, `at`: start, span, spline start,
spline done; binding 3, locations 21–22, zero = not on a spline). part.vert
(engine growth.glsl `growOut`) shrinks it into `from` until the structure's growth (`PartInstance.w.w`,
`Look.grown`) reaches it, grows it out, thin (`SPROUT_THIN`) until its
spline is done; foliage tips lag (`LEAF_LAG`). `b.xform` carries `from`
along.

## Watching
`--structure=<kind> --state=grow` (with `--inspect=<kind>` for shots); its
emitted pieces at work: `--state=active` ([testing.md](testing.md)). No
scratch edits.
