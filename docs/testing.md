# Testing one plant or structure

`--plant`, `--structure`, `game/specimen.zig`.

This is the way to check a species' or structure's growth, look and work:
one thing alone in a fresh world. No demo garden, no scratch edits.

Use it whenever any of these change:

- a species or its genome;
- a plant kit (`structureKit` plant, `parasiteKit`, `convergenceKit`,
  `radiantKit`, meshgen drift);
- a structure, its mesh, growth skeleton or `emit`;
- plant or part shaders.

## Putting it down
`--plant=<species>` (a `species.Id` tag) or `--structure=<kind>` (a
`st.Kind` tag).

- **Where:** on the free tile nearest spawn, in a fresh world. A structure
  goes on a tile edge to edge with a resource node if one is within 8
  tiles, since it may work it.
- The wolf (not drawn) and the camera stand over it.
- **Only the meshes it draws are built** (`Specimen.only`), so loading is
  quick:
  - a species: its own (+ `shadow` for floaters);
  - a structure: `st.meshes(kind)` (its `mesh`, `preview` and `meshes`
    hook) + the resource node meshes.
- **Left out:** the wolf, motes, ghosts and starfall. A plant also has no
  nodes or structures.
- **Ignored:** saves, loads and autosave; also `--demo`/`--stress`/`--load`
  when used with it.

## States
`--state=` picks what it shows (default `grow`). A state that does not
suit the thing stops the game (`error.BadState`).

Looping states run `--period=` seconds (default 8; `active` 30), hold
their end 1.5 s, then start again.

| state | for | shows |
|---|---|---|
| `grow` | both | growth (a structure: `grown`) 0 → 1, looped: the growing animation, emitted pieces forming in their tail |
| `0.2..0.8` | both | growth between two shares, looped |
| `0.4` / `mature` (`idle`) | both | held at that growth / grown |
| `wither` | plant | grown, health 1 → 0, looped (wilt; radiant ones come loose, dim) |
| `flow` | plant | grown, sap flow rising and ebbing (sine, one period) |
| `drain` | plant | grown, mana 1 → 0, looped (sap fill) |
| `dark` | plant | grown, a bloom's network dark |
| `live` | plant | real ecology from seed; resown 4 s after grown or dead |
| `turn` | both | grown, turned a quarter (R) every `turn.time` + 1 s: a rooted one pulls its roots out, steps round, digs back in; a floater turns in the air |
| `active` | structure | grown and working its real `tick`: every 0.4 s handed one of the next thing it `wants` (a carrier: into it from behind, let go 2 s later), what it made (an `output` it does not want) taken away; put down afresh each loop. Emitted pieces (cups, pours, roots to nodes, lids, crystals) as in play |

### Held states
Held states skip the world's tick.

- A plant gets growth, mana, flow, health and radiating written.
- A structure runs only its `link` hooks (`Structures.link`: a conduit's
  arches), with `grown` set and activity 0.
- Removed, it comes back.

An `active` arsthraxia studies the first open research that takes
ingredients.

### Not covered alone
Anything that needs a partner or neighbours; use `--demo` for those:

- sporecaster/driftbraid pairs;
- Vultrixi tethers to a monfris;
- a polyp's halo from blooms;
- conduit side roots, and crown roots to plants.

## Screenshots, unattended
Add `--inspect=<same species/kind>` and shape the orbit, e.g.

```
zig build run -- --plant=vesper --state=grow --period=5 --inspect=vesper --shots=6 --orbit=9 --dist=3.5 --pitch=25 --tod=0.5
zig build run -- --structure=rootDigger --state=active --period=20 --inspect=rootDigger --shots=3 --orbit=12 --dist=3 --pitch=30 --tod=0.5
```

- Shots land in `shots/<name>_<n>.png` after a 3 s settle.
- Read the PNGs to verify.
- A stage held still from every side: `--state=0.5`.

**Which growth each shot shows.** The loop runs from the start, and the
shots are spread over one turn of `--orbit` seconds. So shot `k` of `n`
shows growth about:

```
time   = 3 + k * orbit / n          // 3 s settle, then evenly spaced
growth = (time mod (period + 1.5)) / period   // the loop is period + 1.5 s hold
```

## First person
`--inspect=eyes` looks out of the wolf's eyes, turning round where it
stands, `--pitch=` degrees down (65 shows its chest and belly), e.g.

```
zig build run -- --demo --inspect=eyes --shots=4 --orbit=8 --pitch=30
```

## A HUD panel
`--panel=<belly|research|paused|options|gardens|naming>` holds it open and
keeps the HUD in `--inspect` shots, e.g.

```
zig build run -- --demo --panel=belly --inspect=player --shots=1 --orbit=2
```

Panels grow under the loading screen's fade, so shots show them grown.

## Rules for new things
- **Library meshes:** a structure that emits a library mesh lists it in
  its `meshes` hook (`pub const meshes = .{ .itemPod, ... };`), or
  `--structure` never builds it. The test "a structure alone draws only
  the meshes it declares" runs every kind through `grow` and `active`, and
  fails naming the kind and the missing mesh.
- **New plant inputs:** a new visual input to plants (a new
  `PlantInstance` field the shaders read) gets a state: a tag in `State`
  (+ `parse`, `suits`) and a line in `look`, plus its row here. The tests
  check parsing and loop timing.
