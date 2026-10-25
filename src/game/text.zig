//! every player-facing string, loaded once at startup from `PATH`
//! (`parasymi.cfg`) and never read again. Templates take positional
//! arguments (`{0}`, `{1:.1}`; see `core/text.zig`); lists are `a | b`.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const EnumArray = std.enums.EnumArray;
const log = std.log;
const ArenaAllocator = std.heap.ArenaAllocator;
const stringToEnum = std.meta.stringToEnum;
const toUpper = std.ascii.toUpper;
const assert = std.debug.assert;
const testing = std.testing;
const indexOf = std.mem.indexOf;
const fields = std.meta.fields;
const input = @import("../platform/input.zig");
const ctl = @import("controls.zig");
const ctext = @import("../core/text.zig");
const ck = @import("../world/chunk.zig");
const items = @import("../sim/items.zig");
const species = @import("../sim/species.zig");
const prog = @import("progression.zig");
const st = @import("structures.zig");
const home = @import("home.zig");

pub const PATH = "parasymi.cfg";
/// the strings as built: what an edited file leaves out falls back to these
const DEFAULT = @embedFile("parasymi.cfg");
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
    belly_full:S = "", no_item:S = "", not_understood:S = "", cannot_weave:S = "", wove:S = "", discarded:S = "",
    wants_nothing:S = "", spilled:S = "", still_growing:S = "", not_ripe:S = "", gives_up:S = "",
    lineages_strain:S = "", confluence_roots:S = "",
    researching:S = "", already_known:S = "", locked:S = "", researched:S = "",
    entwine:S = "", hybrid_stirs:S = "", withered:S = "",
    essence_converges:S = "", veil_thins:S = "", arsthraxia_grows:S = "",
    germinator_weaves:S = "", halo_forms:S = "", diamond_forms:S = "", lattice_stirs:S = "",
    loom_meets_stone:S = "", braid_meets_spore:S = "", crown_meets_nerve:S = "", weft_meets_drift:S = "", research_named:S = "",
    tether_choose:S = "", tethered:S = "", tether_full:S = "", tether_cut:S = "", monfris_weaves:S = "",
    braid_choose:S = "", braid_paired:S = "", braid_still:S = "",
    spores_choose:S = "", spores_paired:S = "", spores_still:S = "",
    saved:S = "", autosaved:S = "", save_failed:S = "", remembers:S = "", no_save:S = "", no_gardens:S = "",
    no_fullscreen:S = "", options_unsaved:S = "",
  } = .{},
  hud:struct {
    controls:S = "", ingredient:S = "", unknown:S = "", stock:S = "",
    belly_title:S = "", belly_fill:S = "", belly_hint:S = "", weave:S = "", weave_hint:S = "", queued:S = "",
    recipe:S = "", recipe_many:S = "", recipe_needs:S = "",
    research_title:S = "", research_hint:S = "", research_cost:S = "",
    research_dormant:S = "", research_unwitnessed:S = "",
    hotbar_keys:S = "", facing:S = "", facing_label:S = "", not_understood:S = "",
    too_far:S = "", empty:S = "", open_hint:S = "", holds:S = "", store_hint:S = "", weave_choose:S = "", node:S = "", tile:S = "", stage:S = "", growth:S = "",
    bloom:S = "", radiating:S = "", dark:S = "", no_mature:S = "",
    plant:S = "", unknown_yield:S = "", drawing_radiance:S = "", withering:S = "",
    sap:S = "", paused:S = "", pause_keys:S = "", pause_labels:S = "",
    options_title:S = "", options_hint:S = "", option_labels:S = "",
    antialias:S = "", toggle:S = "", autosave:S = "", options_back:S = "",
    gardens_title:S = "", gardens_fresh:S = "", gardens_auto:S = "", gardens_playing:S = "", gardens_age:S = "",
    gardens_save:S = "", gardens_overwrite:S = "", gardens_load:S = "", gardens_hint:S = "",
    free_cam:S = "", free_cam_hint:S = "",
    fps:S = "", sim:S = "", counts:S = "", draws:S = "", pos:S = "", motes:S = "",
  } = .{},
  /// one-line hover descriptions of structures
  describe:struct {
    carries:S = "", nothing:S = "", weaves:S = "", choose_study:S = "", studies:S = "",
    no_node:S = "", digger_full:S = "", digs:S = "", cache:S = "",
    loom:S = "", loom_fed:S = "", loom_full:S = "",
    lith_draws:S = "", lith_saps:S = "", lith_starved:S = "",
    lanes:S = "", lane_empty:S = "",
    shares:S = "", gathers:S = "", crown_full:S = "",
    sends:S = "", unpaired:S = "",
    trades:S = "", untraded:S = "", loom_weaves:S = "", loom_waits:S = "", vult_pulls:S = "", vult_idle:S = "", vult_loose:S = "", weft_draws:S = "", weft_ionizes:S = "", weft_starved:S = "",
    halo_open:S = "", halo_forming:S = "", halo_formed:S = "", diamond:S = "",
  } = .{},
  sky:struct { dawn:S = "", dusk:S = "", day:S = "", night:S = "" } = .{},
  tile:EnumArray(ck.Kind, Named) = .initFill(.{}),
  item:EnumArray(items.Item, ItemText) = .initFill(.{}),
  plant:EnumArray(species.Id, PlantText) = .initFill(.{}),
  research:EnumArray(prog.Id, ResearchText) = .initFill(.{}),
  structure:EnumArray(st.Kind, Named) = .initFill(.{}),
  /// shown names of keys and mouse buttons (for `{@action}`); optional
  key:EnumArray(input.Key, ?S) = .initFill(null),
  mouse:EnumArray(input.Button, ?S) = .initFill(null),
};

/// the loaded strings; empty until `load` (headless tests run without them).
// decision: one process-wide table, set once at startup and read-only
// after, instead of threading a pointer through every HUD and message site.
pub var s:Strings = .{};
var src:[]u8 = &.{};
/// holds the strings `{@action}` tokens were written into
var arena:?ArenaAllocator = null;

pub const Error = error{ NoStrings, BadStrings } || Allocator.Error;

/// reads and parses `PATH` (in `home`, made from the game's own when
/// missing) over the game's own strings. Called once, at startup, before
/// anything is shown.
pub fn load(gpa:Allocator, io:Io) Error!void {
  assert(src.len == 0);
  src = try home.stock(gpa, io, PATH, DEFAULT);
  errdefer unload(gpa);
  fill(gpa, &.{DEFAULT, src}) catch |e| switch (e) {
    error.OutOfMemory => return error.OutOfMemory,
    else => {
      // the gardener's file is broken: the game's own still read
      log.warn("{s}: ignoring the edited strings", .{PATH});
      unload(gpa);
      try fill(gpa, &.{DEFAULT});
    },
  };
}

/// parses each cfg source of `texts` (which must outlive the strings) into
/// `s` in turn, later ones over earlier; then writes each `{@action}` as
/// the key or button bound to it, so what is shown follows `controls.cfg`
/// (loaded first).
pub fn fill(gpa:Allocator, texts:[]const []const u8) Error!void {
  var bad_buf:[256]u8 = undefined;
  var bad:Io.Writer = .fixed(&bad_buf);
  for (texts) |text| ctext.parse(Strings, &s, text, &bad) catch |e| {
    log.err("{s}: {t}: {s}", .{PATH, e, bad.buffered()});
    return error.BadStrings;
  };
  assert(arena == null);
  arena = .init(gpa);
  ctext.expand(Strings, &s, arena.?.allocator(), action, &bad) catch |e| return switch (e) {
    error.OutOfMemory => error.OutOfMemory,
    else => { log.err("{s}: {t}: {s}", .{PATH, e, bad.buffered()}); return error.BadStrings; },
  };
}

pub fn unload(gpa:Allocator) void {
  if (src.len > 0) gpa.free(src);
  src = &.{};
  if (arena) |*a| a.deinit();
  arena = null;
  s = .{};
}

/// `{@name}`: the first key or button bound to action `name`.
fn action(w:*Io.Writer, name:[]const u8) Io.Writer.Error!bool {
  const a = stringToEnum(ctl.Action, name) orelse return false;
  const binds = ctl.map.getPtrConst(a).items();
  if (binds.len > 0) try bindName(w, binds[0]);
  return true;
}

/// how a key or button is shown: its `[key]`/`[mouse]` name in the cfg,
/// else its binding name in capitals.
// decision: only keys whose binding name reads badly (left_shift, one,
// mouse_left) get a cfg name; F5, TAB, W show as they are bound.
pub fn bindName(w:*Io.Writer, b:input.Bind) Io.Writer.Error!void {
  const named, const tag = switch (b) {
    .key => |k| .{ s.key.get(k), @tagName(k) },
    .button => |k| .{ s.mouse.get(k), @tagName(k) },
  };
  if (named) |n| return w.writeAll(n);
  for (tag) |c| try w.writeByte(toUpper(c));
}

pub fn item(i:items.Item) ItemText { return s.item.get(i); }
pub fn plant(id:species.Id) PlantText { return s.plant.get(id); }
pub fn research(id:prog.Id) ResearchText { return s.research.get(id); }
pub fn structure(k:st.Kind) []const u8 { return s.structure.get(k).name; }
pub fn tile(k:ck.Kind) []const u8 { return s.tile.get(k).name; }

test "the strings file fills every key, shown with the bound keys" {
  const gpa = testing.allocator;
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  defer unload(gpa);
  try fill(gpa, &.{DEFAULT});
  try testing.expect(indexOf(u8, s.hud.controls, ctext.TOKEN) == null);
  // rebinding changes what is shown
  unload(gpa);
  try ctl.fill(&.{@embedFile("controls.cfg") ++ "\n[bind]\nbelly = mouse_middle | b\n"});
  try fill(gpa, &.{DEFAULT});
  try testing.expect(indexOf(u8, s.msg.night_hint, s.mouse.get(.middle).?) != null);
  try testing.expectEqual(count(s.hud.pause_keys), count(s.hud.pause_labels));
  try testing.expectEqual(fields(@import("play.zig").PauseRow).len, count(s.hud.pause_labels));
  const opt = @import("options.zig");
  try testing.expectEqual(fields(opt.Setting).len, count(s.hud.option_labels));
  try testing.expectEqual(fields(@FieldType(opt.Options, "aa")).len, count(s.hud.antialias));
  try testing.expectEqual(2, count(s.hud.toggle));
  try testing.expectEqual(opt.AUTOSAVE.len, count(s.hud.autosave));
  try testing.expectEqual(4, count(s.hud.gardens_age));
  try testing.expectEqual(4, count(s.hud.facing));
}
