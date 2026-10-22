//! species registry. Everything about a plant derives from its entry here:
//! simulation stats, which lineage it belongs to, how its mesh is grown
//! (the genome) and which parents it was spliced from.
const std = @import("std");

pub const Id = enum(u8) { lumenroot, thornleech, vesper };
pub const count = @typeInfo(Id).@"enum".fields.len;

pub const Lineage = enum(u8) {
  symbiotic, parasitic,
  /// both at once: the first step toward the eventual merge of the two paths.
  convergent,

  /// shader-side scalar: +1 symbiotic, -1 parasitic, 0 convergent.
  pub fn affinity(l:Lineage) f32 {
    return switch (l) { .symbiotic => 1, .parasitic => -1, .convergent => 0 };
  }
};

/// procedural mesh parameters (see gfx/meshgen.zig).
pub const Genome = struct {
  stem_h:f32, stem_r:f32, segments:u8, curl:f32,
  leaves:u8, leaf_len:f32, leaf_w:f32, leaf_droop:f32,
  petals:u8, bloom_r:f32,
  thorns:u8, tendrils:u8,
  stem_col:[3]f32, leaf_col:[3]f32, bloom_col:[3]f32,
};

pub const Species = struct {
  name:[]const u8,
  lineage:Lineage,
  /// seconds to maturity at full mana.
  mature_time:f32,
  mana_cap:f32,
  /// mana drawn from the ley field under the plant per second.
  ley_draw:f32,
  /// mana shared to (symbiotic) or stolen from (parasitic) neighbours per second.
  share:f32,
  drain:f32,
  /// essence produced per second from stored mana once mature.
  yield:f32,
  genome:Genome,
  parents:?[2]Id = null,
};

pub const table = std.enums.EnumArray(Id, Species).init(.{
  .lumenroot = .{
    .name = "LUMENROOT", .lineage = .symbiotic,
    .mature_time = 12, .mana_cap = 10, .ley_draw = 0.6, .share = 0.8, .drain = 0, .yield = 0.12,
    .genome = .{
      .stem_h = 0.75, .stem_r = 0.035, .segments = 7, .curl = 0.25,
      .leaves = 7, .leaf_len = 0.32, .leaf_w = 0.11, .leaf_droop = 0.35,
      .petals = 6, .bloom_r = 0.14, .thorns = 0, .tendrils = 0,
      .stem_col = .{0.25, 0.55, 0.35}, .leaf_col = .{0.30, 0.85, 0.55}, .bloom_col = .{0.55, 0.95, 1.0},
    },
  },
  .thornleech = .{
    .name = "THORNLEECH", .lineage = .parasitic,
    .mature_time = 8, .mana_cap = 14, .ley_draw = 1.0, .share = 0, .drain = 1.2, .yield = 0.22,
    .genome = .{
      .stem_h = 0.55, .stem_r = 0.05, .segments = 6, .curl = 0.9,
      .leaves = 3, .leaf_len = 0.22, .leaf_w = 0.06, .leaf_droop = 0.8,
      .petals = 4, .bloom_r = 0.09, .thorns = 10, .tendrils = 4,
      .stem_col = .{0.35, 0.12, 0.22}, .leaf_col = .{0.55, 0.15, 0.35}, .bloom_col = .{1.0, 0.25, 0.45},
    },
  },
  .vesper = .{
    .name = "VESPER BLOOM", .lineage = .convergent,
    .mature_time = 16, .mana_cap = 24, .ley_draw = 0.8, .share = 0.6, .drain = 0.8, .yield = 0.4,
    .genome = .{
      .stem_h = 0.95, .stem_r = 0.04, .segments = 9, .curl = 0.55,
      .leaves = 9, .leaf_len = 0.30, .leaf_w = 0.09, .leaf_droop = 0.55,
      .petals = 9, .bloom_r = 0.2, .thorns = 4, .tendrils = 2,
      .stem_col = .{0.25, 0.2, 0.45}, .leaf_col = .{0.45, 0.4, 0.95}, .bloom_col = .{0.95, 0.75, 1.0},
    },
    .parents = .{.lumenroot, .thornleech},
  },
});

pub inline fn get(id:Id) *const Species { return table.getPtrConst(id); }
