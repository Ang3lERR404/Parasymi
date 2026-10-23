//! mesh: WOLF PECTORAL, LEFT lobe (see wolf_pec.zig)
const std = @import("std");
const Allocator = std.mem.Allocator;
const mg = @import("../meshgen.zig");
const pec = @import("wolf_pec.zig");

pub fn build(b:*mg.Builder) Allocator.Error!void { try pec.lobe(b, -1); }
