//! every player-facing string, loaded once at startup from `PATH`
//! (`parasymi.cfg`) and never read again. Templates take positional
//! arguments (`{0}`, `{1:.1}`; see `core/text.zig`); lists are `a | b`.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const EnumArray = std.enums.EnumArray;
const log = std.log;
const ctext = @import("../core/text.zig");
const ck = @import("../world/chunk.zig");
const items = @import("../sim/items.zig");
const species = @import("../sim/species.zig");
const prog = @import("progression.zig");
const st = @import("structures.zig");

pub const PATH = "parasymi.cfg";
/// the cfg is a few kilobytes; anything near this is not one.
const MAX_CFG:usize = 1 << 20;

pub const nth = ctext.nth;
pub const count = ctext.count;
pub const bufRender = ctext.bufRender;

const S = []const u8;

pub const Named = struct { name:S = "" };
pub const ItemText = struct { name:S = "", short:S = "" };
/// `stages`: a list, one name per growth stage (staged species only).
pub const PlantText = struct { name:S = "", stages:?S = null };
pub const ResearchText = struct { name:S = "", desc:S = "" };

pub const Strings = struct {
  window:struct { title:S = "" } = .{},
  /// said into the message log
  msg:struct {
    wake:S = "", night_hint:S = "",
    belly_full:S = "", no_item:S = "", not_understood:S = "", cannot_weave:S = "", wove:S = "",
    wants_nothing:S = "", spilled:S = "", still_growing:S = "", not_ripe:S = "", gives_up:S = "",
    lineages_strain:S = "", confluence_roots:S = "",
    researching:S = "", already_known:S = "", locked:S = "", researched:S = "",
    entwine:S = "", hybrid_stirs:S = "", withered:S = "",
    essence_converges:S = "", veil_thins:S = "",
    germinator_weaves:S = "",
    saved:S = "", save_failed:S = "", remembers:S = "", no_save:S = "", no_fullscreen:S = "",
  } = .{},
  hud:struct {
    controls:S = "", ingredient:S = "", unknown:S = "",
    belly_title:S = "", belly_fill:S = "", weave:S = "", weave_hint:S = "", queued:S = "",
    recipe:S = "", recipe_many:S = "", recipe_needs:S = "",
    research_title:S = "", research_hint:S = "", research_cost:S = "",
    hotbar_keys:S = "", facing:S = "", facing_label:S = "", not_understood:S = "",
    too_far:S = "", empty:S = "", node:S = "", tile:S = "", stage:S = "", growth:S = "",
    bloom:S = "", radiating:S = "", dark:S = "", no_mature:S = "",
    plant:S = "", unknown_yield:S = "", drawing_radiance:S = "", withering:S = "",
    sap:S = "", paused:S = "", pause_keys:S = "", pause_labels:S = "",
    free_cam:S = "", free_cam_hint:S = "",
    fps:S = "", sim:S = "", counts:S = "", draws:S = "", pos:S = "", motes:S = "",
  } = .{},
  /// one-line hover descriptions of structures
  describe:struct {
    carries:S = "", nothing:S = "", weaves:S = "", choose_study:S = "", studies:S = "",
    no_node:S = "", digger_full:S = "", digs:S = "", cache:S = "",
  } = .{},
  sky:struct { dawn:S = "", dusk:S = "", day:S = "", night:S = "" } = .{},
  tile:EnumArray(ck.Kind, Named) = .initFill(.{}),
  item:EnumArray(items.Item, ItemText) = .initFill(.{}),
  plant:EnumArray(species.Id, PlantText) = .initFill(.{}),
  research:EnumArray(prog.Id, ResearchText) = .initFill(.{}),
  structure:EnumArray(st.Kind, Named) = .initFill(.{}),
};

/// the loaded strings; empty until `load` (headless tests run without them).
// decision: one process-wide table, set once at startup and read-only
// after, instead of threading a pointer through every HUD and message site.
pub var s:Strings = .{};
var src:[]u8 = &.{};

pub const Error = error{ NoStrings, BadStrings } || Allocator.Error;

/// reads and parses `PATH`. Called once, at startup, before anything is shown.
pub fn load(gpa:Allocator, io:Io) Error!void {
  std.debug.assert(src.len == 0);
  src = Io.Dir.cwd().readFileAlloc(io, PATH, gpa, .limited(MAX_CFG)) catch |e| return switch (e) {
    error.OutOfMemory => error.OutOfMemory,
    else => { log.err("{s}: {t}", .{PATH, e}); return error.NoStrings; },
  };
  errdefer unload(gpa);
  try fill(src);
}

/// parses cfg source `text` (which must outlive the strings) into `s`.
pub fn fill(text:[]const u8) Error!void {
  var bad_buf:[256]u8 = undefined;
  var bad:Io.Writer = .fixed(&bad_buf);
  ctext.parse(Strings, &s, text, &bad) catch |e| {
    log.err("{s}: {t}: {s}", .{PATH, e, bad.buffered()});
    return error.BadStrings;
  };
}

pub fn unload(gpa:Allocator) void {
  gpa.free(src);
  src = &.{};
  s = .{};
}

pub fn item(i:items.Item) ItemText { return s.item.get(i); }
pub fn plant(id:species.Id) PlantText { return s.plant.get(id); }
pub fn research(id:prog.Id) ResearchText { return s.research.get(id); }
pub fn structure(k:st.Kind) []const u8 { return s.structure.get(k).name; }
pub fn tile(k:ck.Kind) []const u8 { return s.tile.get(k).name; }

test "the strings file fills every key" {
  defer s = .{};
  try fill(@embedFile("parasymi.cfg"));
  try std.testing.expectEqual(count(s.hud.pause_keys), count(s.hud.pause_labels));
  try std.testing.expectEqual(4, count(s.hud.facing));
}
