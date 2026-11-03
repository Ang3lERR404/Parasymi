# The engine

`engine/` is a Zig package of its own (`engine/build.zig`,
`engine/build.zig.zon`). It holds everything that does not know it is a
garden. It never imports the game.

Parasymi depends on it by path: `.engine = .{ .path = "engine" }`.

Game code reaches it as `@import("engine")` (`engine/src/engine.zig`), for
example:
- `engine.core.math`, `engine.gfx.ctx`, `engine.render.renderer`,
  `engine.ui.draw`;
- the libraries underneath: `engine.vk`, `engine.glfw` and `engine.wasapi`
  (Windows audio, jcollie/zig-wsapi).

## What lives where

Each layer, split into what the engine has and what the game (`src/`)
adds on top.

### core
- Engine: math, color, rng, noise, registry, jobs, text, png, and `dsp`
  (audio building blocks, no device): `Osc`, `Noise`, `Crackle`,
  `OnePole`, `Biquad`, `Smooth`, `Adsr`, `Delay`, `Hall` (a large stone
  hall reverb, fixed rings, no allocation, its tail sent back wide), `Voice`.
  Sound is stereo: sources mix `Frame`s (left, right). `spot(p)` gives the
  speakers' gains for a sound at pan `p` (equal power, 1 each side in the
  middle, so a centred sound is as loud as a mono one was), `put` and
  `pan` place a sample with them, `mid` centres one. An `Ear` (where the
  listener is and which way is its right) turns a place in the world into
  a pan. `StereoPole` and `StereoBiquad` filter both sides at once, each
  its own, and `Pool` voices render into frames.
  Heard in space: `Ear.hear(at,muffle)` gives a `Heard` (side; loudness
  falling 6 dB a doubling past 2 m; the air darkening it with distance;
  the head's shade behind; `muffle`, how much of the way is hidden,
  darkening and quieting it; the ear's notch carved higher the higher it
  is, and the ground darkening what is under; how much reaches the
  place's echo). A `Spatial` plays a sound so (`mono`, or `tick` for one
  already placed), gliding as it moves (`follow`), and sends a share to
  the echo (`Pool.renderSent`). A `Space` is a place's echo (ring, wet,
  damping); `Hall.ring` retunes a hall without losing what it holds.
- Game: nothing.

### platform
- Engine: input, display, and `audio`.
- `audio` is `Output(S)`: the default WASAPI device. It pulls stereo blocks
  (left to the first channel, right to the second, both halved together on
  a mono device, any further channels silent)
  from a source that declares `Cmd`, `apply` and `render`, on
  zig-wsapi's render thread. The game `send`s commands through a
  lock-free `Mailbox` (a drop box both sides use without waiting on each
  other).
- Game: nothing.

### anim
- Engine `rig`: `Turn` (Y·X·Z, `blend`), `twoBone` (IK for a two-bone
  limb, solved with the law of cosines), `inverses`, `skin`.
- Engine `clip`: keyed channels eased between, their text form, and
  `Channels(T)` (every f32 of a struct as a named channel).
- Game: the wolf's skeleton (`wolf_skeleton`: bones, offsets, `fk`,
  breath swell) and limb solvers (`player.solveLeg`/`solveArm`, built on
  `twoBone`).

### gfx
- Engine: ctx, swapchain, buffer, pipeline, and `vertex` (`Mesh`, `Skin`,
  `Grow`, `MeshPose`, `Ui`, `Light`).
- Engine `meshgen`: `Mesher(Part, stem)` with `Builder`, tubes, cone,
  loft, patch, ellipsoid, vines, braids, bands; the LOD scheme;
  Growth/transport.
- Engine `sculpt`: SDF forms, surface nets, bone weights.
- Engine `growth`: `Grower(M, leaf)` with the growth-spline `Skeleton`,
  `tag`, `formed`.
- Game: meshgen (blades, laminae, petals, stamens, flowers, plants; it
  re-exports the engine's), meshlib, growth, kits, and `vertex`
  (instances; re-exports the rest).

### world
- Engine: `chunk` (the grid: `sizeTiles`, `Coord`, `MeshSlot`,
  `localIndex`) and `World(L)` (streaming).
- Game: `chunk` (the garden's tiles), `gen`, `world` (`World` over the
  garden's land).

### render
- Engine: `Renderer(G)`, post, light, camera, `volume` (the air: the
  overhead map, a half-size volume after the world, its edge-aware
  composite), `cube` (the points of light's shadow cubes: which lights
  hold one, kept from frame to frame and eased in and out; their faces;
  the depth images), `passes/ui`. `Renderer.pointShadows(count,size)` sets
  how many lights may hold one and how fine.
- Game: `renderer` (the garden's `G`), passes, terrain meshing.

### ui
- Engine: draw (with a clip rectangle every quad is cut to), font, box,
  and the components' behaviour: `button` (a box and the pointer give one
  of idle, hovering, pressed, held, released; `Press` makes a click a
  release over the button pressed), `textInput` (typing at a caret,
  selecting, erasing either way, cut and paste, enter; text kept to the
  left-hand side, the centre or the right-hand side of its box; `Edit`
  types into any input), `layout` (columns of rows, grids of cells),
  `scroll` (where a list is wanted, how far it has eased, what shows),
  `slider` (stops along a track) and `focus` (the nearest box each way,
  or the next).
- Platform input also reads the first gamepad's buttons and triggers
  (`pad_*` binds), its sticks (`stick`, deadzoned; `steer` moves the
  cursor by one), keys the system repeats while held, and the clipboard.
- Game: how they look (`hud/button.zig`, `hud/field.zig`, `hud/slot.zig`,
  `hud/panel.zig`, `hud/scroll.zig`, `hud/toggle.zig`, `hud/slider.zig`,
  `hud/picker.zig`).

### shaders
- Engine: post, bloom, composite, fxaa, ui, `shadow.frag`, `light.glsl`
  (`airLit`: the key light at a point in the air; `cubeLit`, a shadow
  cube looked up; `pointShadow`, a surface's), `growth.glsl`
  (`growOut`), `volume.glsl` (what a volume pass reads),
  `volume_compose.frag`.
- Game: everything else. `common.glsl` includes `light.glsl`; `part.vert`
  includes `growth.glsl`.

## How a game plugs in

The engine's generic pieces each take a small namespace from the game
that fills in the garden-specific parts, like a form the game fills out.

### Renderer
`engine.render.renderer.Renderer(G)`, where `G` is a namespace.
Parasymi's is `src/render/renderer.zig`, using `@This()`.

`G` declares:
- `name`;
- `passes`: the pass registry, in record order (list `er.ui` as `ui` for
  the HUD);
- `Push`, holding `vp`, `eyeTime`, `view`, `sun`, `light`;
- `Scene`, holding `push`, `clear`, `lights`, plus `ui` and `uiTime` for
  the UI pass;
- `Stats`, holding `draws`, `lights`, `gpuMs`;
- `Ext`: the game's own state (`r.ext`).

It may also declare the hooks `start(r)`, `release(r)` and `carry(prev)`.
Its comment block lists the full contract.

Pass descriptors carry SPIR-V bytes (`.vert = @embedFile("plant.vert")`),
so each module embeds its own shaders.

A pass's `.target` is where it draws, in this order each frame:
- `shadow`: the key light's cascades;
- `cube`: each face of each shadow cube held this frame in turn, the
  push's `light` pointing at that face's matrix (light.glsl `CubeFace`,
  a shader built with CUBE), `Renderer.cubeNow` saying which face (cube ×
  6 + face) and `cubeSpheres` where each light is and how far it reaches,
  so a pass draws only what may stand in it there (`cube.sees`);
- `overhead`: the overhead map, seen from straight above. It is fixed to
  the world and wraps (a texel a unit, `volume.overheadSize` across) and
  is kept from frame to frame, so a pass redraws only a few pieces a frame,
  each pushed `volume.overheadOf` as its `vp`;
- `field`: the game's own state kept over the world on the GPU, laid out
  as the overhead map (a texel a unit, wrapping), in 32-bit floats (so a
  slow change a frame is never lost to rounding). Every frame its passes
  write the next step whole from the last, which they read through set 1
  (`volume.glsl` `field_map`); two images take turns. Every later pass reads
  the new step. Skipped when no pass draws into it. A scene with a
  `probe` (world x, z) has the field's texel there copied back to the CPU:
  `Renderer.probed`, a frame or two old; a scene whose `readField` is set
  has the whole field copied back: `Renderer.field` (read a point of it
  with `Volume.texelIn`), its count `fieldReads` going up by one each time
  one comes back;
- `world`: the HDR image;
- `volume`: the air, at half size, reading the world's depth, the
  overhead map and the field (set 1, `volume.glsl`); rgb what the air sends to the eye, a
  how much shows through. The engine lays it over the HDR image before the
  glow;
- `screen`: the HUD.

### Meshes
`engine.gfx.meshgen.Mesher(Part, stem)`:
- `Part` is the game's `enum(u32)` of vertex roles;
- `stem` is the role plain woody surfaces take.

Parasymi's is `mg.gen` (`src/gfx/meshgen.zig`). Every mesh is built in its
`Builder`. A sculpt meshes into it with `s.mesh(mg.gen, b, h, t, part)`.

A builder makes a triangle soup (three vertices a triangle).
`engine.gfx.weld.weld` turns runs of it into indexed meshes: corners that
are the same vertex bit for bit are drawn from one, triangles keep their
order, and runs given one group (growth keys) share their indices and
line up vertex for vertex. The runs may lie in many soups (one builder
each, built apart on the pool), never copied into one; each group is
welded on a core of its own, the same result as on one. Draw a
`weld.Run` with `drawIndexed(count, …, first, base, …)`.
A builder's `io`, when set, lets a sculpt meshed into it spread its
field over the cores.

### Growth splines
`engine.gfx.growth.Grower(M, leaf)`:
- `M` is the mesher;
- `leaf` is how the game builds one leaf (`LeafFn`).

Parasymi's is `src/gfx/growth.zig`. Its shader carries `vertex.Grow` and
calls `growOut` (growth.glsl) with how far its thing has grown.

### World
`engine.world.World(L)`, where `L` declares:
- `Chunk`, holding `at`, `height`, `kind`, `occ`, `pins`, `gpuSlot`,
  `dirty`;
- `Kind`;
- `Occ` (with `.none`);
- `blank`, `generate` and `heightAt`.

Parasymi's is `Land` in `src/world/world.zig`.

### Shaders
A world shader declares its push block `pc` and `SUN`, then includes
`light.glsl` (`Lighting`, `project`, `keyShadow`, `pointLight`). The
header of `light.glsl` lists what it expects.

### Build
- The game's `build.zig` imports the engine's build
  (`const eb = @import("engine")`) for `eb.glslc`, `eb.registry` and
  `eb.compile`.
- It passes `target`, `optimize`, `glslc` and `vk-registry` to
  `b.dependency("engine", ...)`.
- It compiles its own shaders with `-I` set to both shader folders.
- `zig build test` runs the game's tests and the engine's.
  `cd engine && zig build test` runs the engine's tests alone.

## Starting another game on it
1. Copy or reference `engine/` (a path or git dependency).
2. Write a `G` and an `L` like Parasymi's: a `render/renderer.zig` with
   your passes, and a land if you want streamed chunks.
3. Wire a `main` the way `src/main.zig` does: window, `Input`,
   `Renderer.init`, then loop on `draw`.

The UI shapes in `ui.frag` (trellises, husks, pods, leafy tendrils) come
in Parasymi's style; restyle them there.
