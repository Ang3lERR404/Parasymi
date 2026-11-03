//! physical items and inventories. There is no global stockpile: every item
//! lives in some inventory (the player, later structures) or in the world.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the engine package
const engine=lib.engine;
/// the species registry: which plant a seed grows
const species=lib.species;
/// all the maths: ratios, conversions
const m=engine.core.math;
/// a table with one entry per item kind
const EnumArray=std.enums.EnumArray;
/// the test expectations
const testing=std.testing;
/// every kind of thing that can be held, stored by value (new kinds go last)
pub const Item=enum(u8){
  /// mineral grit, dug from the ground's grit nodes
  grit,
  /// root fibre, from the fibre plant's clumps
  fibre,
  /// a ley shard, broken from the crystals over a ley line
  leyShard,
  /// fallen starlight, condensed from the night sky
  starlight,
  /// essence, condensed inside plants from their mana
  essence,
  /// condensed only where the lineages have merged: the next tier's study.
  convergenceEssence,
  /// the seed a lumenroot grows from
  seedLumenroot,
  /// the seed a thornleech grows from
  seedThornleech,
  /// the seed a vesper bloom grows from
  seedVesper,
  /// the spore a driftwisp grows from
  seedDriftwisp,
  /// the seed a hollowheart grows from
  seedHollowheart,
  // structure bulbs: woven, then planted to grow a structure
  /// the bulb of a root conduit
  conduit,
  /// the bulb of a sap cache
  sapCache,
  /// the bulb of a germinator
  germinator,
  /// the bulb of an arsthraxia
  arsthraxia,
  /// the bulb of a root-digger
  rootDigger,
  // later additions go last, so stored item ids never shift
  /// the seed a celestial bloom grows from
  seedBloom,
  /// the bulb of a polyp, a halo's heart
  polyp,
  /// the diamond a halo forms
  diamond,
  /// the bulb of a loomfern
  loomfern,
  /// the bulb of a lithophage
  lithophage,
  /// the bulb of a braided conduit
  braidedConduit,
  /// the bulb of a ganglion
  ganglion,
  /// the bulb of a gathering crown
  gatheringCrown,
  /// the bulb of a sporecaster
  sporecaster,
  /// the bulb of a weftstone
  weftstone,
  /// the bulb of a driftbraid
  driftbraid,
  /// formed by a weftstone's electrostatic ionization of what it drains
  leyCrystal,
  /// the bulb of a monfris
  monfris,
  /// the bulb of a vultrixi
  vultrixi,
  /// a stemless flower of both lineages a polyp lets drift, fed on the
  /// blooms' light; pulled from the air beside it
  driftFlower,
  /// the seed the shattered radiant light gathered into and let fall: of
  /// a lineage not yet known, it never plants itself
  strangeSeed,
  /// the bulb of a nebularbor, the mist tree
  nebularbor,
  /// the seed a mire lily grows from
  seedMireLily,
  /// the seed a moss creeper grows from
  seedMossCreeper,
  /// the bulb of a root well
  rootWell,
  /// the bulb of a tanglehold
  tanglehold,
  /// the bulb of a storm spire
  stormSpire,
  /// a loose constellate fragment, a small glass triangle of light a
  /// planted strange seed conjures; built into constellate parts
  fragment,
  /// a constellate core, a flower head of light built of fragments: put
  /// down, petals snap onto it
  constellateCore,
  /// a constellate petal of light built of fragments, to snap onto a core
  constellatePetal,
  /// a constellate leaf of light built of fragments
  constellateLeaf,
  /// a constellate bud of light built of fragments
  constellateBud,
  /// a constellate stem of light built of fragments, what other parts fasten to
  constellateStem,
  /// a constellate heart taken up whole (put down, it plays its story afresh)
  constellateHeart,
  /// the seed of a solcyriphon, the light grid's maker
  seedSolcyriphon,
  /// the seed of an astrocyme, the light grid's store
  seedAstrocyme,
  /// the seed of a heliocyra, the light grid's shaper
  seedHeliocyra,
  /// the seed of a halcyra, the light grid's guard
  seedHalcyra,
  /// clear crystal a driftwisp yields now and then under a night beam
  starglass,
  /// threads of light a vesper yields now and then under a night beam
  eveningSilk,
  /// essence a night beam has steeped: worth `sunlitWorth` essence wherever
  /// essence is asked
  sunlitEssence,
  /// convergence essence a night beam has steeped: worth `sunlitWorth` of it
  sunlitConvergenceEssence,
  /// how item `i` looks (its colour)
  pub fn info(i:Item)Info{return infos.get(i);}
  /// the sunlit kind of a yield, what one unit in ten becomes in overdrive
  /// (an item with none is its own)
  pub fn sunlit(i:Item)Item{
    return switch(i){
      .essence=>.sunlitEssence,
      .convergenceEssence=>.sunlitConvergenceEssence,
      else=>i,
    };
  }
  /// what item `i` stands in for, and how many of it (a sunlit essence for
  /// `sunlitWorth` essence), if anything
  pub fn standsFor(i:Item)?Ingredient{
    return switch(i){
      .sunlitEssence=>.{.item=.essence,.n=sunlitWorth},
      .sunlitConvergenceEssence=>.{.item=.convergenceEssence,.n=sunlitWorth},
      else=>null,
    };
  }
  /// the item that stands in for `sunlitWorth` of item `i`, if any
  pub fn steeped(i:Item)?Item{
    // its sunlit kind
    const s=i.sunlit();
    return if(s!=i)s else null;
  }
  /// the species item `i` plants, if it is a seed
  pub fn plants(i:Item)?species.Id{return species.fromSeed(i);}
};
/// names are player-facing text (`game/text.zig`).
pub const Info=struct{
  /// its colour: red, green, blue and alpha bytes
  col:m.Vice(u8,4),
};
/// every item stacks this high in a slot.
pub const stack:u16=100;
/// each item's look, by kind
const infos=EnumArray(Item,Info).init(.{
  .grit=.{.col=.{150,140,130,255}},
  .fibre=.{.col=.{120,170,90,255}},
  .leyShard=.{.col=.{170,120,255,255}},
  .starlight=.{.col=.{255,245,190,255}},
  .essence=.{.col=.{255,215,120,255}},
  .convergenceEssence=.{.col=.{220,150,255,255}},
  .seedLumenroot=.{.col=.{120,240,220,255}},
  .seedThornleech=.{.col=.{240,90,120,255}},
  .seedVesper=.{.col=.{200,170,255,255}},
  .seedDriftwisp=.{.col=.{190,210,255,255}},
  .seedHollowheart=.{.col=.{230,170,100,255}},
  .conduit=.{.col=.{150,120,80,255}},
  .sapCache=.{.col=.{210,160,70,255}},
  .germinator=.{.col=.{140,220,140,255}},
  .arsthraxia=.{.col=.{200,150,255,255}},
  .rootDigger=.{.col=.{190,140,90,255}},
  .seedBloom=.{.col=.{140,255,215,255}},
  .seedMireLily=.{.col=.{170,200,255,255}},
  .seedMossCreeper=.{.col=.{130,190,90,255}},
  .rootWell=.{.col=.{150,200,240,255}},
  .tanglehold=.{.col=.{190,160,240,255}},
  .stormSpire=.{.col=.{200,180,255,255}},
  .polyp=.{.col=.{235,205,230,255}},
  .diamond=.{.col=.{255,236,215,255}},
  .loomfern=.{.col=.{130,200,110,255}},
  .lithophage=.{.col=.{180,160,225,255}},
  .braidedConduit=.{.col=.{170,130,80,255}},
  .ganglion=.{.col=.{200,185,225,255}},
  .gatheringCrown=.{.col=.{235,180,95,255}},
  .sporecaster=.{.col=.{215,205,240,255}},
  .weftstone=.{.col=.{185,200,150,255}},
  .driftbraid=.{.col=.{175,190,235,255}},
  .leyCrystal=.{.col=.{200,160,255,255}},
  .monfris=.{.col=.{210,175,230,255}},
  .vultrixi=.{.col=.{230,200,215,255}},
  .driftFlower=.{.col=.{240,150,200,255}},
  .strangeSeed=.{.col=.{235,240,255,255}},
  .nebularbor=.{.col=.{180,215,235,255}},
  .fragment=.{.col=.{150,200,255,255}},
  .constellateCore=.{.col=.{120,170,255,255}},
  .constellatePetal=.{.col=.{170,220,255,255}},
  .constellateLeaf=.{.col=.{140,215,235,255}},
  .constellateBud=.{.col=.{180,190,255,255}},
  .constellateStem=.{.col=.{130,180,240,255}},
  .constellateHeart=.{.col=.{200,225,255,255}},
  .seedSolcyriphon=.{.col=.{255,225,150,255}},
  .seedAstrocyme=.{.col=.{230,200,255,255}},
  .seedHeliocyra=.{.col=.{255,200,120,255}},
  .seedHalcyra=.{.col=.{200,235,255,255}},
  .starglass=.{.col=.{225,245,255,255}},
  .eveningSilk=.{.col=.{255,200,170,255}},
  .sunlitEssence=.{.col=.{255,240,170,255}},
  .sunlitConvergenceEssence=.{.col=.{245,200,255,255}},
});
/// how many of the plain kind a sunlit one is worth
pub const sunlitWorth=3;
/// one slot's worth: an item and how many of it
pub const Stack=struct{
  /// what is held
  item:Item,
  /// how many (at most `stack`)
  n:u16,
};
/// an amount of an item consumed by a recipe or research unit.
pub const Ingredient=struct{
  /// what is needed
  item:Item,
  /// how many
  n:u16,
};
/// any inventory seen through its slots, whatever its size. Recipes and
/// research take a Bag so they work on the wolf's belly and structures alike.
pub const Bag=struct{
  /// the slots, each empty or holding one stack
  slot:[]?Stack,
  /// adds as many as fit; returns how many were added.
  pub fn add(b:Bag,item:Item,n:u16)u16{
    // how many are still to place, and how high a slot stacks
    var left=n;
    const max=stack;
    for(b.slot)|*s|if(s.*)|*st|if(st.item==item and st.n<max){
      // how many more this stack takes
      const k=@min(left,max-st.n);
      st.n+=k;
      left-=k;
      if(left==0)return n;
    };
    for(b.slot)|*s|if(s.*==null){
      // how many go into this empty slot
      const k=@min(left,max);
      s.*=.{.item=item,.n=k};
      left-=k;
      if(left==0)return n;
    };
    return n-left;
  }
  /// how many of `item` the bag holds
  pub fn count(b:Bag,item:Item)u32{return countIn(b.slot,item);}
  /// how many of `item` the bag holds, counting what stands in for it (a
  /// sunlit essence as `sunlitWorth` essence): what a recipe may spend
  pub fn worth(b:Bag,item:Item)u32{return worthIn(b.slot,item);}
  /// spends `n` of `item`, the plain ones first, then stand-ins, the change
  /// handed back as plain ones; spends exactly `n` or nothing
  pub fn spend(b:Bag,item:Item,n:u32)bool{
    if(b.worth(item)<n)return false;
    // how many plain ones it holds, and how many more it must make up
    const plain=@min(b.count(item),n);
    _=b.take(item,plain);
    const short=n-plain;
    if(short==0)return true;
    // the stand-ins spent, and what they leave over
    const k=(short+sunlitWorth-1)/sunlitWorth;
    _=b.take(item.steeped().?,k);
    _=b.add(item,@intCast(k*sunlitWorth-short));
    return true;
  }
  /// removes exactly `n` or nothing.
  pub fn take(b:Bag,item:Item,n:u32)bool{
    if(b.count(item)<n)return false;
    // how many are still to take, and the slot being emptied (from the last back)
    var left=n;
    var i=b.slot.len;
    while(i>0 and left>0){
      i-=1;
      if(b.slot[i])|*st|if(st.item==item){
        // how many this stack gives
        const k:u16=@intCast(@min(left,st.n));
        st.n-=k;
        left-=k;
        if(st.n==0)b.slot[i]=null;
      };
    }
    return true;
  }
};
/// how many of `item` the slots hold, over every stack of it
fn countIn(slot:[]const?Stack,item:Item)u32{
  // the running count
  var c:u32=0;
  for(slot)|s|if(s)|st|if(st.item==item){c+=st.n;};
  return c;
}
/// how many of `item` the slots hold, what stands in for it counted at its worth
fn worthIn(slot:[]const?Stack,item:Item)u32{
  // the stand-in for it, if any
  const st=item.steeped() orelse return countIn(slot,item);
  return countIn(slot,item)+countIn(slot,st)*sunlitWorth;
}
/// an inventory of `slots` slots, held by value (the wolf's belly, a structure's store)
pub fn Inventory(comptime slots:usize)type{
  return struct{
    /// this inventory type
    const Self=@This();
    /// its slots, each empty or holding one stack
    slot:[slots]?Stack=@splat(null),
    /// the inventory seen as a bag
    pub fn bag(inv:*Self)Bag{return.{.slot=&inv.slot};}
    /// adds as many as fit; returns how many were added
    pub fn add(inv:*Self,item:Item,n:u16)u16{return inv.bag().add(item,n);}
    /// removes exactly `n` or nothing; returns whether it did
    pub fn take(inv:*Self,item:Item,n:u32)bool{return inv.bag().take(item,n);}
    /// how many of `item` it holds
    pub fn count(inv:*const Self,item:Item)u32{return countIn(&inv.slot,item);}
    /// how many of `item` it may spend, stand-ins counted (`Bag.worth`)
    pub fn worth(inv:*const Self,item:Item)u32{return worthIn(&inv.slot,item);}
    /// spends `n` of `item`, stand-ins too (`Bag.spend`)
    pub fn spend(inv:*Self,item:Item,n:u32)bool{return inv.bag().spend(item,n);}
    /// slots holding anything.
    pub fn used(inv:*const Self)usize{
      // the running count
      var c:usize=0;
      for(inv.slot)|s|if(s!=null){c+=1;};
      return c;
    }
    /// every item held, whatever it is.
    pub fn total(inv:*const Self)u32{
      // the running count
      var c:u32=0;
      for(inv.slot)|s|if(s)|st|{c+=st.n;};
      return c;
    }
    /// 0..1, how full the inventory is (by stack fraction).
    pub fn fill(inv:*const Self)f32{
      // the running sum of each stack's fullness
      var f:f32=0;
      for(inv.slot)|s|if(s)|st|{f+=m.ratio(st.n,stack);};
      return f/m.f(slots);
    }
  };
}
test"inventory stacks and takes"{
  // a small inventory of four slots
  var inv:Inventory(4)=.{};
  try testing.expectEqual(@as(u16,140),inv.add(.grit,140));
  try testing.expectEqual(@as(u32,140),inv.count(.grit));
  try testing.expectEqual(@as(usize,2),inv.used());
  try testing.expect(inv.take(.grit,130));
  try testing.expectEqual(@as(u32,10),inv.count(.grit));
  try testing.expect(!inv.take(.grit,11));
  // 3 free slots of 100 starlight each
  try testing.expectEqual(@as(u16,300),inv.add(.starlight,500));
}
