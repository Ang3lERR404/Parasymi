# Mesh kits

A kit is a shared library of mesh pieces in `src/gfx/meshes/*_kit.zig`
(sculpt_kit lives in the engine, `engine/src/gfx/sculpt.zig`). It is
not a mesh itself (it has no `build` and no slot in `meshlib`); meshes, plant
forms and structures call into it so a lineage keeps one look. Each kit has one
file here with everything about it: its look, API, who uses it, what the shaders
read from it, its rules and tests.

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
growth.zig (Skeleton) is used by structure_kit, parasite_kit, convergence_kit;
never by radiant_kit (enforced by its test).
```

## Which kit to reach for

- A new **symbiotic structure**: `structure_kit` + the conduit's `arch`
  (`conduit.arch`, `spineCtrl`). Build on a `growth.Skeleton`.
- A new **symbiotic plant**: a `herb` genome (`structure_kit.plant`).
- A new **parasitic plant or structure**: `parasite_kit`.
- A new **convergent structure** (3rd tier): `convergence_kit` (it already
  mixes the two lineages; never layer `structure_kit` over `parasite_kit`).
- A new **radiant thing**: `radiant_kit` only. No skeleton, no splines,
  no other kits except `mineral_kit` for crystals.
- **Rocks, crystals, facets**: `mineral_kit`.
- **Wolf**: sculpt in `sculpt_kit`, dress with `wolf_kit`; everything skinned.

Rules that apply to every kit (from CLAUDE.md): Catmull-Rom grown vines tapering
at both ends, watertight geometry (shared rings, capped tubes), leaves/petals
with a body (`meshgen.lamina`), every flower has stamens, LOD comes free from the
`Builder` primitives, and visual changes are checked with
`zig build run -- --plant=<species>` / `--structure=<kind>` (see
[../testing.md](../testing.md)).

When a kit changes, update its file here in the same commit.
