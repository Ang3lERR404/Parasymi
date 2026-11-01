//! handing items on from a structure to its neighbours.
const lib=@import("../../../lib.zig");
/// the maths: vectors (Vec), rows (Vice) and matrices (Mat)
const m=lib.engine.core.math;
/// the standard library, reached through the hub
const std=lib.std;
/// the chunks: the ground kinds a structure may stand on
const ck=lib.ck;
/// everything a structure's behaviour may touch
const Ctx=lib.structures.structure.Ctx;
/// a placed structure's slot in the list
const Id=lib.structures.Id;
/// which kind of structure
const Kind=lib.structures.Kind;
/// the default `ground`: any tile will do
const anyTile=lib.structures.structure.anyTile;
/// the structures registry: which kinds have which hooks
const reg=lib.structures.reg;
/// how far and how much `handOffWith` hands on
pub const HandOff=struct{
  /// steps out from its footprint (four ways) it reaches; 1 is the tiles
  /// beside it
  range:u8=1,
  /// at most how many it hands on, to one neighbour or several
  amount:u16=1,
};
/// the first ground kind (in the enum's order) kind `k` may stand on,
/// soil if none: what a test or a bench lays for it
pub fn firstGround(k:Kind)ck.Kind{
  return switch(k){
    inline else=>|t|{
      // the kind's `ground` hook, or any tile if it has none
      const gf=if(comptime reg.has(t,"ground"))reg.module(t).ground else anyTile;
      return blk:{
        for(std.enums.values(ck.Kind))|c|if(gf(c))break:blk c;
        break:blk.soil;
      };
    }
  };
}
/// hand one of what structure `i` lets go (`outputs`) to a neighbour beside
/// it that wants it; returns whether one went.
pub fn handOff(ctx:Ctx,i:Id)bool{return handOffWith(ctx,i,.{})>0;}
/// hand up to `h.amount` of what structure `i` lets go (`outputs`, asked
/// again for each neighbour) to those within `h.range` of its footprint
/// that want it, nearest first; returns how many went. Carriers are left
/// alone: one behind it pulls through `output` itself.
// decision: a footprint's every side hands on (a 2×2 monfris once handed
// only from its corner tile's neighbours)
pub fn handOffWith(ctx:Ctx,i:Id,h:HandOff)u16{
  // the giver, and how many tiles across its footprint is
  const self=ctx.ss.get(i);
  const n:i32=self.def().size;
  // how many it may still hand on
  var left=h.amount;
  for(1..@as(usize,h.range)+1)|d|{
    // the ring of tiles `d` steps out round its footprint
    var r:Ring=.{.x0=self.x,.y0=self.y,.x1=self.x+n-1,.y1=self.y+n-1,.d=@intCast(d)};
    while(r.next())|t|{
      // the structure on that tile, if any
      const j=ctx.ss.at(ctx.w,t[0],t[1]) orelse continue;
      if(j==i or ctx.ss.get(j).def().carrier)continue;
      // what the giver lets go, asked afresh for this neighbour
      var out=ctx.ss.outputs(i);
      while(out.next())|item|{
        // how many of it may go: what is left to give, at most what it holds
        const have:u16=@intCast(@min(left,self.inv.count(item)));
        // how many the neighbour took
        const k=ctx.ss.insert(ctx.g,j,item,have);
        if(k==0)continue;
        _=self.inv.take(item,k);
        left-=k;
        if(left==0)return h.amount;
      }
    }
  }
  return h.amount-left;
}
/// the tiles exactly `d` steps (four ways) out from a footprint
/// `x0..x1` × `y0..y1`, clockwise from its east side: each side, then the
/// corner after it (a 1×1's ring 1 is its neighbours in `m.dirs` order)
pub const Ring=struct{
  /// the footprint's west column
  x0:i32,
  /// the footprint's north row
  y0:i32,
  /// the footprint's east column
  x1:i32,
  /// the footprint's south row
  y1:i32,
  /// how many steps out the ring lies
  d:i32,
  /// which stretch is walked: east, south-east, south, south-west, west,
  /// north-west, north, north-east (8: done)
  seg:u4=0,
  /// how far along that stretch the walk is
  k:i32=0,
  /// how many tiles the current stretch holds: a side as long as the
  /// footprint, a corner diagonal `d`-1
  pub fn len(r:*const Ring)i32{
    return switch(r.seg){
      0,4=>r.y1-r.y0+1,
      2,6=>r.x1-r.x0+1,
      else=>r.d-1,
    };
  }
  /// the next tile round the ring, or null once it has closed
  pub fn next(r:*Ring)?m.Vice(i32,2){
    while(r.seg<8 and r.k>=r.len()){
      r.seg+=1;
      r.k=0;
    }
    if(r.seg==8)return null;
    // the step along this stretch, and the ring's reach
    const k=r.k;
    const d=r.d;
    r.k+=1;
    return switch(r.seg){
      0=>.{r.x1+d,r.y0+k},
      1=>.{r.x1+d-1-k,r.y1+1+k},
      2=>.{r.x1-k,r.y1+d},
      3=>.{r.x0-1-k,r.y1+d-1-k},
      4=>.{r.x0-d,r.y1-k},
      5=>.{r.x0-d+1+k,r.y0-1-k},
      6=>.{r.x0+k,r.y0-d},
      7=>.{r.x1+1+k,r.y0-d+1+k},
      else=>unreachable,
    };
  }
};
