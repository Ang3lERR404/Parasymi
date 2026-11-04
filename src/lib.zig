//! the import hub: every game file reaches std, the engine and every other
//! game module through here (`const lib = @import("../lib.zig")`), never by
//! path; only registry part lists import their own members. The tools reach
//! it as `@import("parasymi")`; the game itself starts from main.zig.
/// the standard library, for every game file
pub const std=@import("std");
/// what this build is (a test build reads the saves' test-only old names)
pub const builtin=@import("builtin");
/// the engine package: core, platform, anim, gfx, world, render and ui
pub const engine=@import("engine");
/// what can be held: the item table and stacks of items
pub const items=@import("sim/items.zig");
/// the garden's plants: footprints, floaters and the store of every plant
pub const plants=@import("sim/plants.zig");
/// turning what stands: roots pulled up, a quarter step, dug back in
pub const turn=@import("sim/turn.zig");
/// the garden's chunk: a block of tiles kept as struct-of-arrays
pub const ck=@import("world/chunk.zig");
/// world generation: the ground as a pure function of seed and tile
pub const gen=@import("world/gen.zig");
/// the garden's world: chunks streamed in round the gardener
pub const world=@import("world/world.zig");
/// play: the running game, its modes and its frame update
pub const play=@import("game/play.zig");
/// what gets drawn: the game state turned into the renderer's scene
pub const view=@import("game/view.zig");
/// the main menu's stage: the wolf asleep in a patch of flowers
pub const title=@import("game/title.zig");
/// the stage's meshes: its mound's height, what drifts down on it
pub const stageMeshes=@import("gfx/meshes/stage.zig");
/// the vine-wolf the gardener plays: movement, belly and steps
pub const player=@import("game/player.zig");
/// one plant or structure standing alone, for `--plant=` / `--structure=`
pub const specimen=@import("game/specimen.zig");
/// the first world event: the radiant plants shatter, the lineages die, a seed falls
pub const unforming=@import("game/unforming.zig");
/// the garden's two acts: the wolf's, then the star hyena's
pub const act=@import("game/act.zig");
/// what every constellate part put down shares: floating over its tile
pub const constellatePart=@import("game/structures/constellate_part.zig");
/// the flow: constellate tendrils the hyena draws, carrying between things
pub const tendril=@import("game/tendril.zig");
/// the weather: the rain the air rains soaking back into the ground
pub const weather=@import("game/weather.zig");
/// moss grown in the garden by its creepers, kept and laid on each chunk
pub const moss=@import("game/moss.zig");
/// where a night beam falls on bare ground: moss now and then turned to ley
pub const beamGround=@import("game/beam_ground.zig");
/// wild flowers sprung up by the pools, kept tile by tile
pub const wild=@import("game/wild.zig");
/// the loading screen: a night with a tendril growing across it
pub const loading=@import("game/loading.zig");
/// the gardener's folder, where every file of theirs lives
pub const home=@import("game/home.zig");
/// every player-facing string, read from parasymi.cfg
pub const txt=@import("game/text.zig");
/// the gardener's sculpts, read at startup, each looping its clip
pub const sculpts=@import("game/sculpts.zig");
/// the key and button bindings, read from controls.cfg
pub const controls=@import("game/controls.zig");
/// the gardener's settings: vsync, antialiasing, fullscreen and the rest
pub const options=@import("game/options.zig");
/// the structures registry: each kind's definition and hooks
pub const structures=@import("game/structures.zig");
/// the plant species registry: each genome that drives a grown mesh
pub const species=@import("sim/species.zig");
/// the garden's renderer: its passes, scene and mesh growing
pub const renderer=@import("render/renderer.zig");
/// the wolf's skeleton: its bones in bind pose
pub const skeleton=@import("gfx/meshes/wolf_skeleton.zig");
/// the HUD's shared colours, type sizes and bar sizes
pub const style=@import("game/style.zig");
/// the per-frame list of rigid parts, grouped by library mesh
pub const parts=@import("game/parts.zig");
/// a sculpt as the mesh editor keeps it: forms, bones, text, meshing
pub const sculptDoc=@import("gfx/sculpt_doc.zig");
/// a sculpt's bones: twins, posing
pub const sculptRig=@import("gfx/sculpt_rig.zig");
/// plant pieces: stems, leaves, petals, stamens
pub const meshgen=@import("gfx/meshgen.zig");
/// the mesh library: every built mesh, in draw order
pub const meshlib=@import("gfx/meshlib.zig");
/// the GPU vertex and instance layouts
pub const vertex=@import("gfx/vertex.zig");
/// what the wolf does to the world: gather, sow, weave, feed, harvest
pub const actions=@import("game/actions.zig");
/// plucking: a ripe plant's yield taken by paw, the plant bending after it
pub const pluck=@import("game/pluck.zig");
/// convergence: where a symbiote and a parasite meet, a confluence takes root
pub const convergence=@import("game/convergence.zig");
/// the weave recipes: what a germinator turns what into
pub const craft=@import("game/craft.zig");
/// the HUD panels registry: belly, research, menus
pub const hud=@import("game/hud.zig");
/// the belly panel: what the wolf carries
pub const hudBelly=@import("game/hud/belly.zig");
/// a HUD slot: a husk hanging in its box
pub const hudSlot=@import("game/hud/slot.zig");
/// a HUD button: a bud and its label, idle, hovered, pressed or held
pub const hudButton=@import("game/hud/button.zig");
/// a HUD text field: typed text on a stem, its caret a blinking bud
pub const hudField=@import("game/hud/field.zig");
/// a HUD panel: a trellis round its box, its title, a menu's veil
pub const hudPanel=@import("game/hud/panel.zig");
/// a HUD scrolled list: rows sliding by, cut to its box, its stem
pub const hudScroll=@import("game/hud/scroll.zig");
/// a HUD toggle: a bud that opens into a bloom when on
pub const hudToggle=@import("game/hud/toggle.zig");
/// a HUD slider: a seed riding a stem of stops
pub const hudSlider=@import("game/hud/slider.zig");
/// a HUD picker: a value between two leaves that turn it
pub const hudPicker=@import("game/hud/picker.zig");
/// item icons: a seed broken open, a pod, a mote
pub const icon=@import("game/icon.zig");
/// `--inspect`: the camera turning round one thing, taking shots
pub const orbit=@import("game/orbit.zig");
/// research: what the gardener has understood and what it opens
pub const progression=@import("game/progression.zig");
/// what each kind of ground offers when gathered, and how its nodes look
pub const resources=@import("game/resources.zig");
/// a value as a record of named fields, so saved structures outlive changes
pub const record=@import("game/record.zig");
/// saving, loading, listing and deleting gardens
pub const save=@import("game/save.zig");
/// the seed icons registry: each structure's bulb and plant's seed
pub const seeds=@import("game/seeds.zig");
/// the test gardens: `--demo` and `--stress`
pub const setups=@import("game/setups.zig");
/// the sky: time of day, sun, stars and daylight
pub const sky=@import("game/sky.zig");
/// the garden's sound: footsteps, twinkles, music and hums
pub const sound=@import("game/sound.zig");
/// the halo a diamond projects, which polyp and diamond both hold
pub const haloStructure=@import("game/structures/halo.zig");
/// the monfris structure: the tree that weaves what is of both lineages
pub const monfrisStructure=@import("game/structures/monfris.zig");
/// the sporecaster structure: sends what it is fed to its pair as spores
pub const sporecasterStructure=@import("game/structures/sporecaster.zig");
/// the garden's growth timing: how far each grown form has formed
pub const growth=@import("gfx/growth.zig");
/// mesh: the arsthraxia, a bloom that studies
pub const arsthraxia=@import("gfx/meshes/arsthraxia.zig");
/// mesh: the arsthraxia the unforming evolves, woven of both lineages
pub const arsthraxiaConvergent=@import("gfx/meshes/arsthraxia_convergent.zig");
/// mesh: the braided conduit, a woven channel between structures
pub const braidedConduit=@import("gfx/meshes/braided_conduit.zig");
/// mesh: the conduit, a vine that carries between structures
pub const conduit=@import("gfx/meshes/conduit.zig");
/// the convergence kit: the shared pieces of grown-together bodies
pub const convergenceKit=@import("gfx/meshes/convergence_kit.zig");
/// the constellate sketches: the star hyena's limbs, bones and pose among them
pub const constellate=@import("gfx/meshes/constellate.zig");
/// mesh: the driftbraid, a braided conduit and sporecaster grown into one
pub const driftbraid=@import("gfx/meshes/driftbraid.zig");
/// mesh: the ganglion, a parasite's nerve knot
pub const ganglion=@import("gfx/meshes/ganglion.zig");
/// mesh: the gathering crown, a symbiote that gathers for the garden
pub const gatheringCrown=@import("gfx/meshes/gathering_crown.zig");
/// mesh: the germinator, a small tree that weaves
pub const germinator=@import("gfx/meshes/germinator.zig");
/// mesh: the lithophage, a parasite that eats stone
pub const lithophage=@import("gfx/meshes/lithophage.zig");
/// mesh: the loomfern, a fern that weaves
pub const loomfern=@import("gfx/meshes/loomfern.zig");
/// the mineral kit: the stones and crystals of resource nodes
pub const mineralKit=@import("gfx/meshes/mineral_kit.zig");
/// mesh: the monfris, a weftstone and driftbraid grown into one tree
pub const monfris=@import("gfx/meshes/monfris.zig");
/// the meshes' shared palette and per-mesh random stream
pub const palette=@import("gfx/meshes/palette.zig");
/// the parasite kit: the shared pieces of the parasitic lineage
pub const parasiteKit=@import("gfx/meshes/parasite_kit.zig");
/// the radiant kit: gathered light fragments, never grown
pub const radiantKit=@import("gfx/meshes/radiant_kit.zig");
/// mesh: the halo crowns a powered structure wears, of radiant fragments
pub const lightCrownMesh=@import("gfx/meshes/light_crown.zig");
/// the sign a powered structure wears in light: its halo crown and ley-blue leaves
pub const lightCrown=@import("game/light_crown.zig");
/// the polyp's colony mesh: its shared mound and buds, for the mixed looks
pub const polypMesh=@import("gfx/meshes/polyp.zig");
/// the hydra look for the polyp: its hanging tentacles and bodies, for the mixed looks
pub const polypHydra=@import("gfx/meshes/polyp_hydra.zig");
/// mesh: the root digger, which draws from the ground's nodes
pub const rootDigger=@import("gfx/meshes/root_digger.zig");
/// mesh: the sap cache, a gourd of resin that stores anything
pub const sapCache=@import("gfx/meshes/sap_cache.zig");
/// the root well's mesh: where the water it holds lies
pub const rootWellMesh=@import("gfx/meshes/root_well.zig");
/// the tanglehold's mesh: where its sac's heart is
pub const tangleholdMesh=@import("gfx/meshes/tanglehold.zig");
/// the storm spire's mesh: where its crown, offshoot tips and lanterns are
pub const stormSpireMesh=@import("gfx/meshes/storm_spire.zig");
/// mesh: the sporecaster, a parasite that sends
pub const sporecaster=@import("gfx/meshes/sporecaster.zig");
/// the structure kit: the shared grown pieces of structures
pub const structureKit=@import("gfx/meshes/structure_kit.zig");
/// mesh: the vultrixi, a gathering crown and ganglion grown into one
pub const vultrixi=@import("gfx/meshes/vultrixi.zig");
/// mesh: the weftstone, a loomfern and lithophage grown into one
pub const weftstone=@import("gfx/meshes/weftstone.zig");
/// mesh: the wolf's belly, a sac of sap on its gut
pub const wolfBelly=@import("gfx/meshes/wolf_belly.zig");
/// mesh: the wolf's body, one skin sculpted round its skeleton
pub const wolfBody=@import("gfx/meshes/wolf_body.zig");
/// the wolf kit: the shared pieces of the wolf's meshes
pub const wolfKit=@import("gfx/meshes/wolf_kit.zig");
/// mesh: the wolf's pectoral, a lobe of solid sap on the chest
pub const wolfPec=@import("gfx/meshes/wolf_pec.zig");
/// mesh: the wolf's rump, a lobe of solid sap on each hip
pub const wolfRump=@import("gfx/meshes/wolf_rump.zig");
/// mesh: the wolf's sap panel, a sheet of sap down its front
pub const wolfPanel=@import("gfx/meshes/wolf_panel.zig");
/// the ground's mesh, built from each chunk's tiles
pub const terrainMesh=@import("render/terrain_mesh.zig");
/// the grown meshes kept on disk between starts
pub const meshCache=@import("render/mesh_cache.zig");
/// the fixed-tick ecology: mana, sharing, draining, growth and death
pub const ecology=@import("sim/ecology.zig");
/// the light grid: who makes, carries, casts, draws and guards light
pub const light=@import("sim/light.zig");
/// debugging helpers: why a structure can't be placed
pub const diagnostics=@import("diagnostics.zig");
