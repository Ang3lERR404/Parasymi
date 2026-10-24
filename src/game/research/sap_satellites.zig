//! SAP SATELLITES: a minor study along Arsthraxia. Every arsthraxia grows:
//! larger, an offshoot off its stalk, another satellite sap round its core.
const prog = @import("../progression.zig");
const txt = @import("../text.zig");

pub const def:prog.Research = .{
  .per_unit = &.{
    .{ .item = .essence, .n = 2 },
    .{ .item = .fibre, .n = 2 },
  },
  .units = 15,
  .unit_time = 6,
  .prereq = &.{ .arsthraxia },
};

pub fn study(s:*prog.Study) void { prog.flourish(s); }

pub fn completed(g:*prog.Progression) void { g.say(txt.s.msg.arsthraxia_grows, .{}); }
