//! GPU vertex/instance layouts. Pipelines derive their attribute descriptions
//! from these (gfx/pipeline.zig), and the GLSL `layout(location=..)` must match
//! field order.
const lib=@import("../lib.zig");
/// the engine package, reached through the hub
const engine=lib.engine;
/// the maths: vectors (Vec), rows (Vice) and matrices (Mat)
const m=engine.core.math;
/// colour types: the four-byte vertex colour
const color=engine.core.color;
/// the engine's own vertex layouts, re-exported below
const ev=engine.gfx.vertex;
/// the engine's own layouts: a point of light
pub const Light=ev.Light;
/// and a UI quad
pub const Ui=ev.Ui;
/// one vertex of the baked ground mesh: where it is, which way it faces,
/// its colour and what kind of tile it belongs to
pub const Terrain=extern struct{
  /// its position in world space
  pos:m.Vice(f32,3),
  /// its normal, unit length
  nrm:m.Vice(f32,3),
  /// its colour, before the shader's lighting
  col:color.Rgba8,
  /// x: tile kind, y: ley intensity, z: is-top-face, w: depth into a ley line
  info:m.Vice(u8,4),
  /// how much of each kind of ground is here (soil, moss, stone, ley; the
  /// tiles meeting at it share it out), which terrain.frag melts together
  /// along wandering, noisy borders
  mat:m.Vice(u8,4),
};
/// shading role of a vertex; shaders key secondary motion and glow off it
/// (common.glsl's `PART_*` numbers match these tags in order)
pub const Part=enum(u32){
  /// a stalk, a stem, a woody trunk
  stem,
  /// a leaf, folded to its midrib
  leaf,
  /// a petal, sap, a glow
  bloom,
  /// a thorn, a claw
  thorn,
  /// a tendril, a frond, a root
  tendril,
  /// a leaf whose inner face (opposite its normal) is lined with sap
  ear,
  /// solidified sap, thick and dense at its base (tu.y 0) thinning toward
  /// its surface (tu.y 1); the instance's `give` moves the surface while
  /// the base holds
  resin,
  /// a soft dark patch on the ground under something floating (tu.x its
  /// radial fraction; instance fade its darkness)
  shadow,
  /// a beam between blooms
  thread,
  /// a disc of light thrown out where a halo's blooms met (tu.x its radius)
  flash,
  /// a cut iridescent crystal that only catches light
  prism,
  /// the ring of split light a diamond projects
  halo,
  /// the rays a diamond throws to make its halo
  projection,
  /// a conduit's living core
  core,
  /// liquid essence a germinator pours, spins and winds into a seed (its
  /// colour the instance's, tu.x the way it flows, < 0 still)
  essence,
  /// research energy an arsthraxia condenses, glowing white
  energy,
  /// an arsthraxia's nerve: thought rises through it
  nerve,
  /// a plant's yield ripening on it, a bead of sap in its colour (meshgen
  /// `pod`): col.a its place among the plant's pods, tu.y its radius; it
  /// swells from a pale nub as the plant ripens (plant.vert)
  pod,
  /// the constellate web: points, lines and panes of blue light (tu.y
  /// which), lightened by each beat as it runs out to them (tu.x how far
  /// it runs to reach them)
  plexus,
  /// weathered stone: grained, flecked, darker in its hollows, lichened
  /// where it faces the sky (part.frag, in its own mesh space)
  stone,
  /// a spark of lightning: light itself, white-hot along its core, violet
  /// at its edge, flickering (tu.x 0..1 along it)
  spark,
};
/// whether a library part of role `p` draws see-through (part.frag blends
/// it over what lies behind): true for light, sap and glass, false for solids
pub fn seeThrough(p:Part)bool{
  return switch(p){
    .bloom,.ear,.resin,.shadow,.thread,.flash,.halo,.projection,.energy,.pod,.plexus,.spark=>true,
    .stem,.leaf,.thorn,.tendril,.prism,.core,.essence,.nerve,.stone=>false,
  };
}
/// the engine's mesh layouts (gfx/meshgen.zig builds them): one plain vertex
pub const Mesh=ev.Mesh;
/// a vertex's bone weights, for skinned meshes like the wolf
pub const Skin=ev.Skin;
/// a vertex's growth timing: when along its spline it forms
pub const Grow=ev.Grow;
/// a vertex's place in its mesh's own pose space
pub const MeshPose=ev.MeshPose;
/// one plant as the plant pass draws it: where it stands and how far it
/// has grown, filled, flowered and leaned toward a lineage
pub const PlantInstance=extern struct{
  /// where it is rooted, in world space
  pos:m.Vice(f32,3),
  /// growth 0..1, mana fill 0..1, seed 0..1, lineage affinity -1..1
  a:m.Vice(f32,4),
  /// flow, health, sway amplitude, genome form (species.Form)
  b:m.Vice(f32,4),
  /// x: blend toward the next growth key (0..1); y: 1 for a placement
  /// preview (ghost); z: 1 when that preview fits; w the yaw it is turned
  /// to (R), on top of its own
  c:m.Vice(f32,4)=.{0,0,0,0},
  /// a forming halo drawing it in (see `noHalo`)
  h:m.Vice(f32,4)=noHalo,
  /// its bend after the gardener's paws plucking it: xy the way it bends
  /// on the ground (unit length), z how far (radians at its tip), w unused
  tug:m.Vice(f32,4)=.{0,0,0,0},
  /// its yield ripening on it: x how ripe, 0..1 (its essence over its
  /// cap), y how many pods it ripens in, z a radiant pod's radius (mesh
  /// space), w seconds since its yield last came loose in the paws
  ripe:m.Vice(f32,4)=.{0,0,0,noPluck},
  /// the colour of what it yields (sRGB 0..1), w unused
  yield:m.Vice(f32,4)=.{1,1,1,0},
  /// its unforming (game/unforming.zig): x how far it has shattered, 0
  /// its first glitch .. 1 gone (< 0 none); yzw unused
  glitch:m.Vice(f32,4)=noGlitch,
};
/// `PlantInstance.glitch` for a plant the unforming has not touched
pub const noGlitch=m.Vice(f32,4){-1,0,0,0};
/// `PlantInstance.ripe.w` for a plant never plucked (long since)
pub const noPluck:f32=1e4;
/// one tile's worth of ground detail, read per instance by detail.vert,
/// which grows the tile's grass blades (or its clods and stones on soil)
/// from it: the ground itself stays one baked mesh, the detail is the GPU's.
pub const DetailTile=extern struct{
  /// the tile's corner x, its centre height, its corner z
  at:m.Vice(f32,3),
  /// the heights of its corners: (x0,z0), (x0,z1), (x1,z1), (x1,z0)
  corners:m.Vice(f32,4),
  /// the tile's ground colour, which its blades take on
  col:color.Rgba8,
  /// tile kind, ley 0..255, unused, unused
  info:m.Vice(u8,4),
  /// how much of each kind of ground (soil, moss, stone, ley) lies at its
  /// corner (x0,z0), as the ground beneath shares it out: grass grows as
  /// thick as the ground it stands on is grassy, so it thins across borders
  k00:m.Vice(u8,4),
  /// (at its corner (x0,z1))
  k01:m.Vice(u8,4),
  /// (at its corner (x1,z1))
  k11:m.Vice(u8,4),
  /// (at its corner (x1,z0))
  k10:m.Vice(u8,4),
  /// (at its centre)
  kc:m.Vice(u8,4),
};
/// a rigid procedural part (creature limb, resource node, mote, structure piece).
pub const PartInstance=extern struct{
  /// model matrix columns: the first
  c0:m.Vice(f32,4),
  /// the second
  c1:m.Vice(f32,4),
  /// the third
  c2:m.Vice(f32,4),
  /// the fourth, its translation
  c3:m.Vice(f32,4),
  /// x glow, y flutter (leaf secondary motion), z phase 0..1, w alpha-ish fade
  p:m.Vice(f32,4),
  /// rgb colour multiply, w blend amount
  tint:m.Vice(f32,4),
  /// x how far along a conduit's core the essence it carries has come
  /// (0..1, < 0 none; its colour in `e.yzw` when placed by the matrix);
  /// yzw give: how far a resin part's surface is pushed (mesh space), its base held
  q:m.Vice(f32,4),
  /// x sway: how far it bends from its root in the garden's wind (0 rigid);
  /// y the height over which it bends; z how far below the origin it is
  /// rooted (a part hovering above its stalk bends with it); w how far a
  /// growing structure has come along (1 grown)
  w:m.Vice(f32,4),
  /// x how part.vert places it: 0 by the matrix; 1 along a curve (a bloom
  /// thread: c0..c3 xyz its control points, tint.xyz the side its x lies
  /// toward, y how far along it reaches (0: all of it), w its rest length;
  /// z which of its ends a forming halo draws in: 1 its first, 2 its last,
  /// 3 both); placed by the matrix, yzw the colour of the essence a
  /// conduit's core carries (`q.x`); 2 a star mote (c3 its centre; y phase, z life, w its trail
  /// echo, -1 when resting); along a curve, q.yzw its essence's colour
  /// (sRGB 0..1); 3 skinned (y the first of its bones in the
  /// frame's bone buffer; each vertex by its `Skin`); 4 a burst flung out
  /// from where a yield came loose (y how far through its life, 0..1)
  e:m.Vice(f32,4)=.{0,0,0,0},
  /// a forming halo it belongs to (see `noHalo`)
  h:m.Vice(f32,4)=noHalo,
  /// `partGhost`, ...: what it is beyond its mesh
  flags:u32=0,
  /// x how far it is blended into its mesh's next key (0..1, the library's
  /// `next`: a bud opening); yzw unused
  k:m.Vice(f32,4)=.{0,0,0,0},
};
/// `PartInstance.flags`: a placement preview (casts no shadow); part.vert
/// reads it as `PART_GHOST`
pub const partGhost:u32=1;
/// a halo forming around a polyp (game/structures/polyp.zig), as an
/// instance carries it to the shaders: xyz its centre (where the diamond
/// sits), w how far it has come (0 the blooms leave their corners .. 1 they
/// meet; past 1, `halo.form`s since). common.glsl `haloSpiral` draws the
/// blooms in along it. This, w < 0, is none.
pub const noHalo=m.Vice(f32,4){0,0,0,-1};
