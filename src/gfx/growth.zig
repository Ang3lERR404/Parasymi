//! the garden's growth splines: the engine's (engine gfx/growth.zig: the
//! hidden skeleton a grown structure is built on and grows along) for the
//! garden's builder, its leaves the garden's (`meshgen.leafAt`).
const lib=@import("../lib.zig");
/// the engine package, reached through the hub
const engine=lib.engine;
/// the engine's growth splines, which this file fits to the garden
const eg=engine.gfx.growth;
/// the garden's mesh builder, whose leaves the splines grow
const mg=lib.meshgen;
/// the engine's grower made for the garden: its builder `meshgen.gen`, its leaves `meshgen.leafAt`
const gr=eg.Grower(mg.gen,mg.leafAt);
/// the hidden skeleton a grown structure is built on: splines that grow one off another
pub const Skeleton=gr.Skeleton;
/// marks a piece of mesh to form over a window of its structure's growth
pub const tag=gr.tag;
/// which spline of a skeleton: an index, distinct from any other number
pub const Id=eg.Id;
/// when a branch starts growing: when its parent is done, as its front passes, or with it
pub const After=eg.After;
/// how a branch grows: its pace, when it starts, its delay and its front
pub const Branch=eg.Branch;
/// one spline of a skeleton: its resampled points, length, parent and timing
pub const Spline=eg.Spline;
/// the most splines a skeleton may hold
pub const max=eg.max;
/// how many points each spline is resampled into, evenly by length
pub const res=eg.res;
/// how long a spline's tapering growth front is, as a share of its growing time
pub const front=eg.front;
/// the window (start, length, as shares of the whole growth) of a structure's last `tail`
pub const tailWindow=eg.tailWindow;
/// how far a piece formed over the last `tail` of the growth has come at growth `g` (0..1, eased)
pub const formed=eg.formed;
