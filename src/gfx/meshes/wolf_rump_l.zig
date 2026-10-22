//! mesh: WOLF RUMP, LEFT lobe (see wolf_rump.zig)
const std = @import("std");
const Allocator = std.mem.Allocator;
const mg = @import("../meshgen.zig");
const rump = @import("wolf_rump.zig");

pub fn build(b:*mg.Builder) Allocator.Error!void { try rump.lobe(b, -1); }
