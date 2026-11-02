//! what structures tell each other (`Msg`, `Reply`) and how a kind pairs.
const lib=@import("../../../lib.zig");
/// what can be held: item kinds and stacks of them
const items=lib.items;
/// which kind of structure
const Kind=lib.structures.Kind;
/// the structures registry, for asking a kind's `pairs`
const reg=lib.structures.reg;
/// what one structure tells another (`Structures.send`): taken at once by
/// the other's `message` hook, nothing left pending (so nothing is saved).
/// One reads another through its hooks (`chosen`, `gives`, ...), never its
/// `state`.
// decision: synchronous, chosen by the user over a queued mailbox and
// one-off typed hooks
pub const Msg=union(enum){
  /// born whole: its light already full (a diamond a halo formed)
  lit,
  /// the unforming has begun (an arsthraxia evolves)
  unform,
  /// a drift flower taken in as a stemless branch (an evolved arsthraxia)
  graft,
  /// `n` of `item` came in from afar (spores landing); by default it is
  /// taken in as `insert` does
  arrived:struct{item:items.Item,n:u16},
  /// a constellate petal put down nearby asks to drift over (a yielder
  /// still short of petals answers `done`)
  petalComing,
  /// a constellate petal has drifted over and merges (a yielder short of
  /// petals takes it on: `done`)
  petalSnapped,
  /// a constellate part put down nearby asks to drift over to a stem's
  /// joint (a stem with that joint free answers `joint`)
  fastenComing:Fasten,
  /// a constellate part has drifted over and fastens at a joint (a stem
  /// with a joint free for it takes it: `joint`)
  fastened:Fasten,
};
/// what a structure makes of a `Msg`
pub const Reply=union(enum){
  /// nothing: it does not take that message
  ignored,
  /// heard and acted on, with nothing to hand back
  done,
  /// how many of what `arrived` it took in
  took:u16,
  /// the joint of a stem a part drifts to or fastened at (0 lowest, 1
  /// middle, 2 highest)
  joint:u8,
};
/// how a kind pairs (its `pairs`): with a structure of kind `with` (its
/// own if null), one way (its partner is where it sends) or both ways
/// (each is the other's), with up to `most` partners at once: paired with
/// one more, it lets go of its oldest (both ways, that one lets go of it)
pub const Pairs=struct{way:Way=.oneWay,with:?Kind=null,most:u8=1};
/// the most partners any structure keeps
pub const partnerSlots=4;
/// which way a pairing runs
pub const Way=enum{
  /// one sends, its partner receives
  oneWay,
  /// each is the other's partner
  bothWays
};
/// how kind `k` pairs, or null if it never does; checked at compile time
/// that its `most` lies in 1..`partnerSlots`
pub fn pairsOf(k:Kind)?Pairs{
  return switch(k){
    inline else=>|t|if(comptime reg.has(t,"pairs"))blk:{
      // the kind's pairing, as it declares it
      const p:Pairs=reg.module(t).pairs;
      if(comptime p.most<1 or p.most>partnerSlots)@compileError(@tagName(t)++": pairs.most must be 1..PARTNERS");
      break:blk p;
    }else null,
  };
}
/// where configuring a structure that pairs leaves it (`pairStep`)
pub const PairStep=enum{
  /// it waits for the next one configured
  waiting,
  /// configured twice over: it is cut loose
  cut,
  /// the one waiting is paired with it
  paired,
};
/// what fastens at a constellate stem's joint: a leaf (its lowest or
/// highest), or another stem as its branch (its middle)
pub const Fasten=enum{
  /// a leaf
  leaf,
  /// a stem, as a branch
  branch,
};
