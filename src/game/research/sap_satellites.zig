//! SAP SATELLITES: a minor study along Arsthraxia. Every arsthraxia grows:
//! an offshoot out of its stems, another satellite sap round its core.
const lib = @import("../../lib.zig");
const prog = lib.progression;
const txt = lib.txt;

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
