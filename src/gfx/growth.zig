//! the garden's growth splines: the engine's (engine gfx/growth.zig: the
//! hidden skeleton a grown structure is built on and grows along) for the
//! garden's builder, its leaves the garden's (`meshgen.leafAt`).
const lib=@import("../lib.zig");
const engine=lib.engine;
const eg=engine.gfx.growth;
const mg=lib.meshgen;
const gr=eg.Grower(mg.gen,mg.leafAt);
pub const Skeleton=gr.Skeleton;
pub const tag=gr.tag;
pub const Id=eg.Id;
pub const After=eg.After;
pub const Branch=eg.Branch;
pub const Spline=eg.Spline;
pub const max=eg.max;
pub const res=eg.res;
pub const front=eg.front;
pub const tailWindow=eg.tailWindow;
pub const formed=eg.formed;
