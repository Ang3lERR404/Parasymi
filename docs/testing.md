# Testing one plant or structure

`--plant`, `--structure`, `game/specimen.zig`.

The way to check a species' or structure's growth, look and work: no demo
garden, no scratch edits. Use it whenever a species, its genome, a plant
kit (`parasite_kit`, `convergence_kit`, `radiant_kit`, meshgen herb/
drift), a structure, its mesh/growth skeleton/`emit`, or plant/part
shaders change.

- `--plant=<species>` (a `species.Id` tag) / `--structure=<kind>` (a
  `st.Kind` tag) puts it down on the free tile nearest spawn in a fresh
  world (a structure on one edge to edge with a resource node if any is
  within 8 tiles, for it may work it), the wolf (not drawn) and camera
  over it. Only the meshes it draws are built (`Specimen.only`), so loading
  is quick: a species' own (+ `shadow` for floaters); a structure's
  `st.meshes(kind)` (its `mesh`, `preview` and `meshes` hook) + the
  resource node meshes. The wolf, motes, ghosts and starfall are left out;
  a plant also has no nodes or structures. Saves, loads and autosave are
  ignored; `--demo`/`--stress`/`--load` are ignored with it.
- `--state=` (default `grow`); a state that does not suit the thing stops
  the game (`error.BadState`). Looping ones run `--period=` seconds
  (default 8; `active` 30), hold their end 1.5 s, start again:

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
  | `turn` | both | grown, turned a quarter (R) every `turn.TIME` + 1 s: a rooted one pulls its roots out, steps round, digs back in; a floater turns in the air |
  | `active` | structure | grown and working its real `tick`: every 0.4 s handed one of the next thing it `wants` (a carrier: into it from behind, let go 2 s later), what it made (an `output` it does not want) taken away; put down afresh each loop. Emitted pieces (cups, pours, roots to nodes, lids, crystals) as in play |

  Held states skip the world's tick: a plant gets growth, mana, flow,
  health, radiating written; a structure runs only its `link` hooks
  (`Structures.link`: a conduit's arches) with `grown` set and activity 0.
  Removed, it comes back. An `active` arsthraxia studies the first open
  research that takes ingredients.
- Not covered alone: what needs a partner or neighbours (sporecaster/
  driftbraid pairs, Vultrixi tethers to a monfris, a polyp's halo from
  blooms, conduit side roots and crown roots to plants); use `--demo` for
  those.
- Unattended, with screenshots: add `--inspect=<same species/kind>` and
  shape the orbit, e.g.
  `zig build run -- --plant=vesper --state=grow --period=5 --inspect=vesper --shots=6 --orbit=9 --dist=3.5 --pitch=25 --tod=0.5`
  `zig build run -- --structure=root_digger --state=active --period=20 --inspect=root_digger --shots=3 --orbit=12 --dist=3 --pitch=30 --tod=0.5`
  (shots land in `shots/<name>_<n>.png` after a 3 s settle; the loop runs
  from the start, so shot k of n over a turn of `--orbit` seconds shows
  growth about `((3 + k·orbit/n) mod (period+1.5)) / period`). Read the
  PNGs to verify. A stage held still from every side: `--state=0.5`.
- A structure that emits a library mesh lists it in its `meshes` hook
  (`pub const meshes = .{ .item_pod, ... };`), or `--structure` never
  builds it. The test "a structure alone draws only the meshes it
  declares" runs every kind through `grow` and `active` and fails naming
  the kind and the missing mesh.
- A new visual input to plants (a new `PlantInstance` field the shaders
  read) gets a state: a tag in `State` (+ `parse`, `suits`) and a line in
  `look`, plus its row here; the tests check parsing and loop timing.
