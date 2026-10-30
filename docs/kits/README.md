# Mesh kits

A kit is a shared library of mesh pieces, like a box of parts a lineage
builds everything from, so it keeps one look.
- Kits live in `src/gfx/meshes/*_kit.zig` (sculpt_kit lives in the engine,
  `engine/src/gfx/sculpt.zig`).
- A kit is not a mesh itself: it has no `build` and no slot in `meshlib`.
- Meshes, plant forms and structures call into it.

Each kit has one file here with everything about it: its look, API, who
uses it, what the shaders read from it, its rules and tests.

| Kit | File | Lineage / domain | Grows how | Used by |
|---|---|---|---|---|
| structure_kit | [structure_kit_desc.md](structure_kit_desc.md) | symbiotic (structures and plants) | growth splines (`On`), or plain; plants by tu.x | `herb` plants (lumenroot, hollowheart), germinator, sap cache, arsthraxia, root-digger, gathering crown, loomfern, polyp, conduit, fibre node |
| parasite_kit | [parasite_kit_desc.md](parasite_kit_desc.md) | parasitic (pale, exact fives) | growth splines; plants by tu.x | `coil` plants (thornleech), lithophage, ganglion, sporecaster; convergence_kit and convergent structures |
| convergence_kit | [convergence_kit_desc.md](convergence_kit_desc.md) | both lineages mixed | growth splines (`*On`); confluence by keys | confluence, weftstone, driftbraid, monfris, vultrixi |
| radiant_kit | [radiant_kit_desc.md](radiant_kit_desc.md) | radiant / celestial | **gathered, never grown** | celestial bloom, vesper, diamond (halo) |
| mineral_kit | [mineral_kit_desc.md](mineral_kit_desc.md) | ground minerals | not grown | grit and ley nodes, lithophage crystal, star mote, radiant_kit cuts/shards |
| sculpt_kit | [sculpt_kit_desc.md](sculpt_kit_desc.md) | the wolf's skin (SDF) | skinned, not grown | wolf body, belly, ears, wolf_kit |
| wolf_kit | [wolf_kit_desc.md](wolf_kit_desc.md) | the wolf's details | skinned, not grown | wolf body, belly, pecs, rump |

## How they depend on each other

```
engine meshgen (Builder, tubes, lofts, vines, braids, ellipsoids, patches)
   └─ meshgen (the garden's: blades, laminae, petals, stamens, flowers)
meshgen ──────────────┬─ structure_kit ── palette
                      ├─ mineral_kit ──────────────┐
                      ├─ parasite_kit ─┐           │
                      │                └─ convergence_kit (+ palette)
                      ├─ radiant_kit ──────────────┘ (uses mineral_kit)
                      └─ sculpt_kit (engine) ── wolf_kit
```

`growth.zig` (the `Skeleton`; the engine's, for the garden's builder) is
used by structure_kit, parasite_kit and convergence_kit. It is never used
by radiant_kit (enforced by its test).

## Which kit to reach for

- A new **symbiotic structure**: `structureKit` + the conduit's `arch`
  (`conduit.arch`, `spineCtrl`). Build on a `growth.Skeleton`.
- A new **symbiotic plant**: a `herb` genome (`structureKit.plant`).
- A new **parasitic plant or structure**: `parasiteKit`.
- A new **convergent structure** (3rd tier): `convergenceKit`. It already
  mixes the two lineages; never layer `structureKit` over `parasiteKit`.
- A new **radiant thing**: `radiantKit` only. No skeleton, no splines, no
  other kits except `mineralKit` for crystals.
- **Rocks, crystals, facets**: `mineralKit`.
- **Wolf**: sculpt in `sculpt_kit`, dress with `wolfKit`; everything
  skinned.

## Rules for every kit

From CLAUDE.md:
- Grown vines are Catmull-Rom splines, tapering at both ends.
- Geometry is watertight (shared rings, capped tubes).
- Leaves and petals have a body (`meshgen.lamina`).
- Every flower has stamens.
- LOD comes free from the `Builder` primitives.

Check visual changes with `zig build run -- --plant=<species>` /
`--structure=<kind>` (see [../testing.md](../testing.md)).

When a kit changes, update its file here in the same commit.
