//! CONDENSING WHORL: a minor study along Arsthraxia. Every arsthraxia grows:
//! an offshoot out of its stems, another satellite sap round its core.
const prog = @import("../progression.zig");
const txt = @import("../text.zig");

pub const def:prog.Research = .{
  .per_unit = &.{
    .{ .item = .essence, .n = 3 },
    .{ .item = .starlight, .n = 2 },
  },
  .units = 20,
  .unit_time = 8,
  .prereq = &.{ .sap_satellites },
};

pub fn study(s:*prog.Study) void { prog.flourish(s); }

pub fn completed(g:*prog.Progression) void { g.say(txt.s.msg.arsthraxia_grows, .{}); }
