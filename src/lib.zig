//! the game's modules, for the tools built beside it (tools/animedit.zig, tools/meshedit.zig):
//! they reach them as `@import("parasymi")`; the game itself starts from
//! main.zig.
pub const play = @import("game/play.zig");
pub const view = @import("game/view.zig");
pub const player = @import("game/player.zig");
pub const specimen = @import("game/specimen.zig");
pub const loading = @import("game/loading.zig");
pub const home = @import("game/home.zig");
pub const txt = @import("game/text.zig");
pub const controls = @import("game/controls.zig");
pub const options = @import("game/options.zig");
pub const structures = @import("game/structures.zig");
pub const species = @import("sim/species.zig");
pub const renderer = @import("render/renderer.zig");
pub const skeleton = @import("gfx/meshes/wolf_skeleton.zig");
pub const style = @import("game/style.zig");
pub const parts = @import("game/parts.zig");
pub const meshgen = @import("gfx/meshgen.zig");
pub const meshlib = @import("gfx/meshlib.zig");
pub const vertex = @import("gfx/vertex.zig");
