# Optimizing: how to make a frame cheaper without changing it

A working method, learned on 2026-11-01 taking the demo from 38 ms to
18 ms and the stress field from 53 ms to 16 ms (GPU, msaa8, RTX 4060 Ti),
with the picture unchanged. The research behind the shader rules is in
[shader-optimization.md](shader-optimization.md); the targets and where
things stand are in [performance.md](performance.md).

**The rule over all of it:** an optimization changes cost, never the
picture. Looks come before frame cost (the user's standing call). If the
only way to save time is to change how something looks (fewer shadow
taps, coarser LODs, shading per pixel instead of per sample), stop and
show the user the options side by side (`--samples=`); never take it.

## 1. Measure, per pass, on the GPU

The CPU frame hides behind the GPU, so read GPU time. Every pass is timed
with timestamp queries, and the game logs each pass's eased time as it
closes (`gpu <pass> <ms>`, engine `Renderer.logTimes`).

```bash
zig build -Drelease=true
sh tools/perf/bench.sh demo msaa8 --demo --inspect=player --shots=2 --orbit=8
sh tools/perf/bench.sh stress msaa8 --stress --inspect=player --shots=2 --orbit=8
```

- `bench.sh` switches `antialias` in the gardener's options.cfg for the
  run and puts it back; it prints every pass over 0.1 ms and the total.
- Noise is about ±0.5 ms on the demo. Run twice; trust only a change
  bigger than that, or one that shows in both demo and stress.
- Bench the antialias settings too (`off` vs `msaa8`): a pass that grows
  a lot with samples is fragment-bound (plant and part passes shade every
  sample).

## 2. Find what costs: knock-outs

Swap one piece for something trivial, bench, put it back. The difference
is what that piece costs.

```bash
sh tools/perf/knock.sh noShadow shaders/plant.frag "float sh = keyShadow(v_pos, n);" "float sh = 1.0;"
```

`knock.sh` swaps the one place the text appears, builds, benches (demo,
msaa8) and restores the file whatever happens. Check `git status` after.

The first knock-out to make on any slow pass: replace its fragment
shader's `main` with a flat colour. What is left is the vertex stage and
rasterizing. That one test told us stress was vertex-bound.

What the pieces cost on 2026-11-01 (demo, msaa8, plant pass 11.1 ms):

| piece | ms |
|---|---|
| key shadow (`keyShadow`) | 4.5: blocker search 1.8, soft filter 1.5, cascade blend 0.2 |
| points of light (`pointLights`) | 1.4 |
| a leaf's veins (`sheetColour`) | 1.2, its fine net 0.8 |

## 3. Prove the picture held

- **Shots before and after.** Build the old version beside the new one
  without touching the gardener's uncommitted work: copy aside only the
  files you changed, `git checkout HEAD -- <those files>`, build with
  `zig build -Drelease=true -p <scratch>/before`, copy yours back. Then
  take the same `--inspect` shots from both.
- **Two runs never match pixel for pixel** (wind, motes and clouds move
  with the clock). So diff a box round what you changed and a box of bare
  ground in the same pair:
  ```bash
  python -I tools/perf/shotdiff.py before.png after.png 740 390 870 540
  ```
  Safe when the thing differs no more than the ground does. Then look at
  both shots yourself.
- **One debug run** (`zig build`, validation on) with no validation
  errors.
- **Prove exactness in a test** where you can: the weld's tests check
  every corner of every run comes out bit for bit.

## 4. The methods that worked, and how to keep using them

### Indexed meshes (`engine.gfx.weld`)
Builders make triangle soups (three vertices a triangle). Each mesh at
each level of detail is a piece built in a builder of its own, the
pieces taken by the pool's threads one after another as each comes
free (they differ widely in size). Each piece builds in an arena of its
own, freed the moment it is built, keeping only its soup copied out at
its size (skin and growth lists only where any vertex has them); the
weld's scratch is freed as it goes, and the soups once welded. One
shared arena for all of it held every piece's scratch to the end: 70 GB
at its peak, now about 11. The welded whole is kept on disk
(render/mesh_cache.zig, `cache/<program>-<mode>.meshes` in the
gardener's folder, ~1.9 GB), keyed by a hash of the program file and every
sculpt: a start with the same key reads it (meshes in at ~3 s, release)
instead of growing; any other grows and writes it anew beside the upload,
let go once written while the garden is played. Once every piece is grown,
`Growing.weldAll` (render/renderer.zig) welds each run straight from its
piece, each group on a core of its own:
corners that are the same vertex bit for bit (vertex, skin, growth
record) become one, so the GPU shades a shared vertex once. Passes draw
a `Run` with `drawIndexed(count, …, first, base, …)`.
- Growth-key chains (a plant's variants with keys, `meshlib.next`) weld
  as one group: they share indices and line up vertex for vertex, so the
  morph offset (`plantMorph`, `partMorph`) still works.
- Triangle order and corner order are kept (blending and `flat` values
  stay as they were); never reorder triangles for the cache.
- The tools' meshes (`setParts`) are drawn through indices that count
  up from 0, unwelded.
- New mesh kinds get it free as long as they are built in a `Builder`
  and land in a slot's range. Smooth meshes share ~5x; faceted ones
  (the constellate's fragments) ~2x.

### Skin and growth only where they are read (`weld`'s `lead`)
Only the parts' shaders read skin weights and growth records; the plants'
read neither. The library meshes' pieces are laid first, and the weld
keeps skin and growth only as far as their vertices run: the plants' 33
million vertices no longer carry 84 unread bytes each (~2.8 GB of video
memory). On an 8 GB card that was the difference between fitting and the
driver paging: `--stress` with rays went from 125 ms a frame to 54 (rays
98 → 29), and with buffers doubled it ran out of memory outright.
- A new mesh whose shader reads skin or growth must be a library mesh
  (or its pieces laid among the leading ones).

### Ray levels per patch, refitted (`renderer.patchTiles`, engine `Rays`)
The plants caught for the rays were one bottom level of the plants seen,
so every camera move changed what it held and it was built anew each
frame (stress: rays 29 ms of a 52 ms frame, 28.8 of it the build). Now
each 4×4-tile patch with any plant seen is caught whole, seen or not,
into a level of its own, kept from frame to frame and refitted while it
holds the same meshes: stress rays 6.6 ms, the frame 29 ms; demo 60 to 56.
- Patches, not chunks: a whole 32-tile chunk in view, or a patch culled by
  a sphere round it, caught three or four times the triangles and ran an
  8 GB card out of memory. "Any plant seen" keeps the excess to a patch's
  edge (stress: 3120 caught for 2595 seen).
- Video memory is the wall here: past about 7.5 GB the driver pages and
  every pass slows (sky 0.3 ms became 11). So levels are sized exactly
  (one outgrown is freed a few frames later, never a wait), a level
  uncaught a few frames is let go, and builds go in batches sharing a
  64 MB scratch (all at once they wanted 575 MB).
- The top level is made once with room for `maxLevels`: the shaders'
  descriptor binds it, so making it anew would leave them tracing a freed
  one (device lost).

### Only the see-through tail in the glass passes (`Run.early`)
The weld puts each run's late triangles (see-through ones) last; the
glass and air passes draw only `first+early ..`, the solid passes the
rest.
- Plants: `renderer.plantGlassy` marks them (all of a radiant or star
  plant; else pods, petals, resin). Parts: `vertex.seeThrough`.
- A mesh with a placement preview among its instances is drawn whole in
  the glass pass (`plants.Frame.ghosts`).
- **When a shader gains a new see-through look, add it to `plantGlassy`
  or `vertex.seeThrough`**, or it disappears.

### Lighter shader builds for the always-solid triangles (HEAD)
`plantsHead`/`partsHead` draw each run's head with plant.frag/part.frag
built with `-DHEAD` (build.zig `variants`), where the materials only
see-through roles take are left out (`#ifndef HEAD`). Fewer registers
mean more fragments in flight: plants 11.1 to ~9.7 ms, parts 4.5 to 2.45.
- A new material branch for a see-through role goes inside the
  `#ifndef HEAD` blocks; one for a solid role must stay outside them.
- The same trick fits any big shader whose rare branches are keyed off
  something the CPU knows per triangle or per mesh: split the triangles,
  build a variant without those branches.

### Skip work whose weight is zero
If `x * f()` has `x == 0` over a region, test `x` first. Exact, and it
pays when `f` is heavy: a leaf's vein net (`sheetNet`, nine worley
cells) is no longer searched where it has faded out (`leafSheet`).
Take derivatives (`fwidth`, `dFdx`) before the branch.

## 5. Tried, and not worth it here (don't repeat without a new reason)

- **Depth pre-pass** of the always-solid plant triangles: plants hardly
  hide each other from the garden's camera; it saved 0.6 ms of shading
  and cost 0.9 (4 in stress).
- **Explicit level-0 shadow taps**: `textureLod` on the depth reads gave
  nothing; `textureGrad` on the compare sampler doubled the plant pass
  (a slow path on this GPU).
- **Hand-rewriting the skinned normal** (round one): no gain.
- **Lower `min_sample_shading`, shading per pixel, alpha-to-coverage**:
  changes the edges; the user decided per-sample shading stays.

## 6. Pitfalls met on the way

- **The gardener's uncommitted work**: never `git stash` or reset it.
  Commit only your own paths (`git commit -- <paths>`).
- **Tools write into the repo**: running meshedit re-created
  `src/mesh/sculpt.mesh` (the gardener had deleted it). Check
  `git status` after running a tool and put back what it changed.
- **Git Bash rewrites arguments that start with `/`** into Windows
  paths (`/// doc` became `//// doc`). Edit such lines with the editor,
  or pass them from a file.
- **No heredocs**: write a script file and run it.
- **Keep options.cfg**: bench.sh backs it up; if a run is killed, put
  `options.cfg.benchbak` back by hand.

## 7. What is left, ranked

1. **The key shadow's soft filter** (~4.5 ms of plant shading: 33
   texture reads a sample, 8 samples a pixel). Cheaper means a different
   look: the user's call (offered 2026-11-01, not taken).
2. **Points of light** (~1.4 ms): clustered or tiled light lists, so a
   fragment loops only over lights that reach it. Exact.
3. **Shadow casters per cascade** (stress `plantsShadow` ~2.3 ms):
   every caster is drawn into all three cascades; cull per cascade.
   Exact.
4. **Video memory** (stress peaks near 7.7 GB of 8): the mesh upload's
   staging (~1.7 GB at once) and two caught sets of equal room (the
   points-only set holds far fewer). Less held means no paging on
   smaller cards. Exact.
5. **Compute pre-transform, meshlets**: only if the vertex stage leads
   again (see shader-optimization.md, round two).
