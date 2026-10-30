//! what structures tell each other (`Msg`, `Reply`) and how a kind pairs.
const lib = @import("../../../lib.zig");
const items = lib.items;
const Kind = lib.structures.Kind;
const reg = lib.structures.reg;

/// what one structure tells another (`Structures.send`): taken at once by
/// the other's `message` hook, nothing left pending (so nothing is saved).
/// One reads another through its hooks (`chosen`, `gives`, ...), never its
/// `state`.
// decision: synchronous, chosen by the user over a queued mailbox and
// one-off typed hooks
pub const Msg = union(enum) {
  /// born whole: its light already full (a diamond a halo formed)
  lit,
  /// `n` of `item` came in from afar (spores landing); by default it is
  /// taken in as `insert` does
  arrived: struct { item:items.Item, n:u16 },
};

/// what a structure makes of a `Msg`
pub const Reply = union(enum) {
  /// nothing: it does not take that message
  ignored,
  done,
  /// how many of what `arrived` it took in
  took:u16,
};

/// how a kind pairs (its `pairs`): with a structure of kind `with` (its
/// own if null), one way (its partner is where it sends) or both ways
/// (each is the other's), with up to `most` partners at once: paired with
/// one more, it lets go of its oldest (both ways, that one lets go of it)
pub const Pairs = struct { way:Way = .one_way, with:?Kind = null, most:u8 = 1 };
/// the most partners any structure keeps
pub const PARTNERS = 4;
pub const Way = enum { one_way, both_ways };

pub fn pairsOf(k:Kind) ?Pairs {
  return switch (k) {
    inline else => |t| if (comptime reg.has(t, "pairs")) blk: {
      const p:Pairs = reg.module(t).pairs;
      if (comptime p.most < 1 or p.most > PARTNERS) @compileError(@tagName(t) ++ ": pairs.most must be 1..PARTNERS");
      break :blk p;
    } else null,
  };
}

/// where configuring a structure that pairs leaves it (`pairStep`)
pub const PairStep = enum {
  /// it waits for the next one configured
  waiting,
  /// configured twice over: it is cut loose
  cut,
  /// the one waiting is paired with it
  paired,
};
