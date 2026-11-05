//! the light grid: radiance as the garden's power. Only a solcyriphon makes
//! light: by day it spreads `glow[0]` round itself, by night it pours
//! `glow[1]` down in one beam onto what hangs or stands under it. Relays
//! (blooms, astrocymes, a diamond) carry it on along their links, each up
//! to its `carry`; a heliocyra casts what it takes as a strip, a tile wide,
//! and bends a strip that strikes it. What draws light (a vesper, the
//! structures) takes it from the one relay it stands best in: full within a
//! tile of it, fading to a quarter at its field's edge, and only its share
//! when that relay's users want more than reaches it. Light flows out from
//! where it is made, nearest first: each relay keeps what its own users
//! want and passes the rest on, evenly, to the relays it reached first. A
//! night beam that finds no relay overdrives the plant under it, or falls
//! on the bare ground. Worked out each tick from the relays and users
//! alone; plants are never scanned against relays.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the engine package
const engine=lib.engine;
/// all the maths: distances, ramps, facings
const m=engine.core.math;
/// the species registry: who makes, carries, casts, draws or guards light
const species=lib.species;
/// plant storage: the plants, their points and neighbour rings
const plantsMod=lib.plants;
/// the garden's streamed world, whose tiles plants stand on
const World=lib.world.World;
/// the allocator type the grid's lists grow with
const Allocator=std.mem.Allocator;
/// the test allocator and expectations
const testing=std.testing;
/// every living plant
const Plants=plantsMod.Plants;
/// a plant's slot
const Id=plantsMod.Id;
/// every plant's columns at once
const Slice=std.MultiArrayList(plantsMod.Plant).Slice;
/// within this many tiles of its relay a user has its light whole
pub const nearFull:f32=1;
/// at its relay's field's edge a user has this share of it
pub const edgeShare:f32=0.25;
/// what needs light stops below this share of it
pub const needAt:f32=0.25;
/// how near under a solcyriphon a floater must hang to catch its beam (m,
/// flat across the ground)
pub const beamCatch:f32=0.6;
/// how much a diamond a night beam strikes multiplies the light it carries
/// (the gardener: about 5%; beams never stack it)
pub const lensGain:f32=1.05;
/// the most a heliocyra takes from the field it stands in (glow)
pub const stripTake:f32=3;
/// the share of a strip's light a heliocyra keeps as it bends it on
pub const bendKeep:f32=0.9;
/// how fast a halcyra leans over a plant put down beside it, or draws
/// back to its net when the plant is gone (a share a second: about two
/// seconds either way)
pub const leanRate:f32=1.6;
/// a relay a structure holds (a diamond): where it hangs, how far its field
/// reaches, how much it carries and how far it links
pub const Relay=struct{
  /// where it hangs across the ground (y 0)
  at:m.V3,
  /// how far its field reaches (tiles)
  radius:f32,
  /// the most light it carries (glow)
  carry:f32,
  /// how far it links with other relays (tiles)
  link:f32,
  /// the tile it floats over: its column
  x:i32,
  /// and its row
  y:i32,
};
/// a structure that draws light: where it stands and how much it wants
pub const User=struct{
  /// its footprint's centre across the ground (y 0)
  at:m.V3,
  /// how much light it draws at full work (glow)
  draw:f32,
};
/// a node of the grid: a plant that makes, carries or casts light, or a
/// structure's relay (an index into the relays passed in)
pub const Ref=union(enum){
  /// a plant: a solcyriphon, a bloom, an astrocyme, a heliocyra
  plant:Id,
  /// a structure's relay, by its place in the list passed in
  relay:u32,
};
/// two relays linked: a thread of light between them, and how much light
/// went along it this tick (0: dark)
pub const Link=struct{
  /// one end
  a:Ref,
  /// the other
  b:Ref,
  /// how much light passed between them (glow)
  glow:f32,
};
/// a heliocyra's strip: who casts it, how many tiles it runs and how much
/// light it carries
pub const Strip=struct{
  /// the heliocyra casting it
  from:Id,
  /// how many tiles it runs before it ends or strikes another
  len:u8,
  /// how much light runs along it (glow)
  glow:f32,
};
/// what a night beam falls on
pub const Onto=enum(u8){
  /// a relay, which carries it on
  relay,
  /// a plant, overdriven by it
  plant,
  /// the bare ground
  ground,
};
/// a solcyriphon's night beam: who pours it, how strong, onto what
pub const Beam=struct{
  /// the solcyriphon
  from:Id,
  /// how much light it pours (glow)
  glow:f32,
  /// what it falls on
  onto:Onto,
  /// the tile it falls on: its column
  x:i32,
  /// and its row
  y:i32,
  /// its strength, 0 none .. 1 a whole night's beam
  k:f32,
  /// the relay that takes it, if it falls on one (where it ends)
  into:?Ref=null,
};
/// how a node was reached from its parent: along a link, out of the field
/// it stands in (a heliocyra), or by a strip striking it
const Way=enum(u8){link,field,bend};
/// a node's link across the grid, from one end
const Edge=struct{to:u32,way:Way};
/// no node
const none=std.math.maxInt(u32);
/// one node of the grid, as this tick works it out
const Node=struct{
  /// what it is
  ref:Ref,
  /// where it stands across the ground (y 0)
  at:m.V3,
  /// its tile: column and row
  x:i32,
  /// (row)
  y:i32,
  /// how far its field reaches (tiles; 0: none, as a heliocyra's)
  radius:f32,
  /// the most it carries
  cap:f32,
  /// how far it links (tiles; 0: never)
  link:f32,
  /// a heliocyra's strip length (tiles; 0: it casts none)
  strip:u8=0,
  /// the way a heliocyra faces
  dir:m.Dir=0,
  /// light made at it this tick (a solcyriphon's day, a beam it caught)
  supply:f32=0,
  /// light handed to it by its parent
  got:f32=0,
  /// light it carried
  carried:f32=0,
  /// what its users want of it
  demand:f32=0,
  /// what it kept for its users
  kept:f32=0,
  /// the node it was reached from (`none`: a source, or never reached)
  parent:u32=none,
  /// how it was reached
  way:Way=.link,
  /// a diamond a solcyriphon's night beam strikes: it acts as a lens, the
  /// light it carries multiplied by `lensGain` (one beam or many, once)
  lensed:bool=false,
};
/// the grid, worked out each tick: per plant, per relay and per user what
/// it carries or gets, the beams, the strips and the threads of light
pub const Light=struct{
  /// per plant: its share of the light it draws (1 when it draws none)
  lit:std.ArrayList(f32)=.empty,
  /// per plant: how hard a night beam overdrives it, 0 none .. 1 a whole night's
  beamed:std.ArrayList(f32)=.empty,
  /// per plant: whether a halcyra guards it from overdrive
  guarded:std.ArrayList(bool)=.empty,
  /// per plant: the one plant a halcyra guards beside it (`.none`: it
  /// guards all round it alone, or it is no halcyra)
  ward:std.ArrayList(Id)=.empty,
  /// per plant: the light it carried, if it is a node (glow)
  carried:std.ArrayList(f32)=.empty,
  /// per relay passed in: the light it carried (glow)
  relayCarried:std.ArrayList(f32)=.empty,
  /// per user passed in: its share of the light it draws, 0..1
  userLit:std.ArrayList(f32)=.empty,
  /// the threads of light between linked relays
  links:std.ArrayList(Link)=.empty,
  /// every heliocyra's strip
  strips:std.ArrayList(Strip)=.empty,
  /// every solcyriphon's night beam
  beams:std.ArrayList(Beam)=.empty,
  /// scratch: the nodes
  nodes:std.ArrayList(Node)=.empty,
  /// scratch: each node's edges, packed (`first` says where each begins)
  edges:std.ArrayList(Edge)=.empty,
  /// scratch: where each node's edges begin in `edges` (one past for the last)
  first:std.ArrayList(u32)=.empty,
  /// scratch: edges as found, before packing (from, to, way)
  found:std.ArrayList(Found)=.empty,
  /// scratch: the nodes in the order light reaches them
  order:std.ArrayList(u32)=.empty,
  /// scratch: per user, the node it draws from and how strongly (plants first, then structures)
  pick:std.ArrayList(Pick)=.empty,
  /// scratch: the plant per node (or none), to find a plant's node
  nodeOf:std.ArrayList(u32)=.empty,
  /// an edge as found: from a node, to a node, which way
  const Found=struct{from:u32,to:u32,way:Way};
  /// the node a user draws from, and how strongly it reaches it
  const Pick=struct{node:u32,strength:f32};
  /// frees every list
  pub fn deinit(l:*Light,gpa:Allocator)void{
    l.lit.deinit(gpa);l.beamed.deinit(gpa);l.guarded.deinit(gpa);l.ward.deinit(gpa);l.carried.deinit(gpa);l.relayCarried.deinit(gpa);l.userLit.deinit(gpa);
    l.links.deinit(gpa);l.strips.deinit(gpa);l.beams.deinit(gpa);l.nodes.deinit(gpa);l.edges.deinit(gpa);l.first.deinit(gpa);
    l.found.deinit(gpa);l.order.deinit(gpa);l.pick.deinit(gpa);l.nodeOf.deinit(gpa);
  }
  /// works out the grid for this tick: `night` 0 day .. 1 full night,
  /// `relays` and `users` the structures', `dt` the tick (an astrocyme
  /// fills and empties by it)
  pub fn update(l:*Light,gpa:Allocator,p:*Plants,w:*const World,relays:[]const Relay,users:[]const User,night:f32,dt:f32)Allocator.Error!void{
    // how many plants there are, and their columns
    const n=p.len();
    const s=p.list.slice();
    try resetTo(f32,gpa,&l.lit,n,1);
    try resetTo(f32,gpa,&l.beamed,n,0);
    try resetTo(bool,gpa,&l.guarded,n,false);
    try resetTo(Id,gpa,&l.ward,n,.none);
    try resetTo(f32,gpa,&l.carried,n,0);
    try resetTo(u32,gpa,&l.nodeOf,n,none);
    try resetTo(f32,gpa,&l.relayCarried,relays.len,0);
    try resetTo(f32,gpa,&l.userLit,users.len,0);
    l.links.clearRetainingCapacity();
    l.strips.clearRetainingCapacity();
    l.beams.clearRetainingCapacity();
    l.nodes.clearRetainingCapacity();
    try l.gather(gpa,s,relays);
    try l.guard(s,p,w,dt);
    if(l.nodes.items.len>0){
      try l.pour(gpa,s,p,w,night);
      try l.join(gpa);
      try l.want(gpa,s,users);
      try l.flow(gpa,s,dt);
      l.share(s,users);
      for(l.nodes.items)|nd|switch(nd.ref){
        .plant=>|id|l.carried.items[id.idx()]=nd.carried,
        .relay=>|r|l.relayCarried.items[r]=nd.carried,
      };
    }else{
      // no relay at all: whoever draws light has none
      for(s.items(.sp),0..)|sp,i|if(species.get(sp).draw>0){l.lit.items[i]=0;};
    }
  }
  /// a list made `n` long, every entry `v`
  fn resetTo(comptime t:type,gpa:Allocator,list:*std.ArrayList(t),n:usize,v:t)Allocator.Error!void{
    try list.resize(gpa,n);
    @memset(list.items,v);
  }
  /// the nodes: every grown plant that makes, carries or casts light, then
  /// every relay the structures hold
  fn gather(l:*Light,gpa:Allocator,s:Slice,relays:[]const Relay)Allocator.Error!void{
    for(s.items(.sp),0..)|sp,i|{
      // the species, and whether it is a node of the grid
      const d=species.get(sp);
      if(!d.lightNode() or s.items(.growth)[i]<1)continue;
      l.nodeOf.items[i]=@intCast(l.nodes.items.len);
      try l.nodes.append(gpa,.{
        .ref=.{.plant=.of(i)},.at=s.items(.at)[i],.x=s.items(.x)[i],.y=s.items(.y)[i],
        .radius=d.radiance,.cap=d.carry,.link=d.link,.strip=d.strip,.dir=s.items(.dir)[i],
      });
    }
    for(relays,0..)|r,k|try l.nodes.append(gpa,.{.ref=.{.relay=@intCast(k)},.at=r.at,.x=r.x,.y=r.y,.radius=r.radius,.cap=r.carry,.link=r.link});
  }
  /// what each solcyriphon makes: its day light at itself, its night beam
  /// onto what is under it (a relay takes it; else a plant is overdriven,
  /// else it falls on the ground)
  fn pour(l:*Light,gpa:Allocator,s:Slice,p:*const Plants,w:*const World,night:f32)Allocator.Error!void{
    for(l.nodes.items,0..)|*nd,k|{
      // the solcyriphon, if this node is one
      const id=switch(nd.ref){.plant=>|i|i,.relay=>continue};
      const d=species.get(s.items(.sp)[id.idx()]);
      if(d.glow[0]+d.glow[1]<=0)continue;
      nd.supply+=d.glow[0]*(1-night);
      // the beam: how much, and its strength
      const beam=d.glow[1]*night;
      if(beam<=0)continue;
      // the relay under it, if any
      if(l.under(k))|r|{
        // decision: the beam's light is the solcyriphon's to hand on, the
        // relay under it reached from it as any other: so light flows one
        // way from dawn to dusk to dawn, never turning round where the beam
        // outgrows the day's glow (it flickered there)
        nd.supply+=beam;
        // a diamond struck straight on is a lens (structures' relays are diamonds)
        if(l.nodes.items[r].ref==.relay)l.nodes.items[r].lensed=true;
        try l.beams.append(gpa,.{.from=id,.glow=beam,.onto=.relay,.x=nd.x,.y=nd.y,.k=night,.into=l.nodes.items[r].ref});
        continue;
      }
      // else the plant under it, if any: overdriven
      if(plantUnder(s,p,w,id,nd.at,nd.x,nd.y))|j|{
        l.beamed.items[j.idx()]=@max(l.beamed.items[j.idx()],night);
        try l.beams.append(gpa,.{.from=id,.glow=beam,.onto=.plant,.x=nd.x,.y=nd.y,.k=night});
        continue;
      }
      try l.beams.append(gpa,.{.from=id,.glow=beam,.onto=.ground,.x=nd.x,.y=nd.y,.k=night});
    }
  }
  /// the node right under node `k` (a solcyriphon), if any: a floating one
  /// within `beamCatch` of its point, else one on its tile
  fn under(l:*const Light,k:usize)?usize{
    // the solcyriphon
    const sol=l.nodes.items[k];
    for(l.nodes.items,0..)|nd,j|{
      if(j==k)continue;
      if(flat(nd.at,sol.at)<=beamCatch or (nd.x==sol.x and nd.y==sol.y))return j;
    }
    return null;
  }
  /// the plant under a solcyriphon at `at` over tile `x`,`y` (never itself
  /// or a node): a floater within `beamCatch`, else one rooted on the tile
  fn plantUnder(s:Slice,p:*const Plants,w:*const World,self:Id,at:m.V3,x:i32,y:i32)?Id{
    for(p.floaters.items)|f|{
      if(f==self or species.get(s.items(.sp)[f.idx()]).lightNode())continue;
      if(flat(s.items(.at)[f.idx()],at)<=beamCatch)return f;
    }
    // the plant rooted on the tile
    const j=p.at(w,x,y) orelse return null;
    if(j==self or species.get(s.items(.sp)[j.idx()]).lightNode())return null;
    return j;
  }
  /// the edges: links between relays in reach of each other, a relay to
  /// each heliocyra standing best in its field, and each strip to the
  /// heliocyra it strikes (its own length cut there)
  fn join(l:*Light,gpa:Allocator)Allocator.Error!void{
    l.found.clearRetainingCapacity();
    // the nodes
    const ns=l.nodes.items;
    for(ns,0..)|a,i|for(ns[i+1..],i+1..)|b,j|{
      if(a.link<=0 or b.link<=0)continue;
      if(flat(a.at,b.at)>@min(a.link,b.link))continue;
      try l.found.append(gpa,.{.from=@intCast(i),.to=@intCast(j),.way=.link});
      try l.found.append(gpa,.{.from=@intCast(j),.to=@intCast(i),.way=.link});
    };
    for(ns,0..)|h,j|{
      if(h.strip==0)continue;
      // the relay whose field it stands best in, if any
      if(best(ns,h.at,j))|r|try l.found.append(gpa,.{.from=@intCast(r.node),.to=@intCast(j),.way=.field});
      // the heliocyra its strip strikes, if any
      const step=m.dirVec(h.dir);
      for(1..@as(usize,h.strip)+1)|t|{
        // the tile this far along
        const tx=h.x+step.x*@as(i32,@intCast(t));
        const ty=h.y+step.z*@as(i32,@intCast(t));
        // the heliocyra standing there, if any
        const hit=for(ns,0..)|o,k|{if(k!=j and o.strip>0 and o.x==tx and o.y==ty)break k;}else null;
        if(hit)|k|{
          try l.found.append(gpa,.{.from=@intCast(j),.to=@intCast(k),.way=.bend});
          ns[j].strip=@intCast(t);
          break;
        }
      }
    }
    // packed per node, in the order found
    const nn=ns.len;
    try resetTo(u32,gpa,&l.first,nn+1,0);
    for(l.found.items)|e|l.first.items[e.from+1]+=1;
    for(1..nn+1)|k|l.first.items[k]+=l.first.items[k-1];
    try l.edges.resize(gpa,l.found.items.len);
    // where the next edge of each node goes
    try l.order.resize(gpa,nn);
    @memcpy(l.order.items,l.first.items[0..nn]);
    for(l.found.items)|e|{
      l.edges.items[l.order.items[e.from]]=.{.to=e.to,.way=e.way};
      l.order.items[e.from]+=1;
    }
  }
  /// the node whose field point `at` stands best in (never node `skip`),
  /// and how strongly: nearest its middle, the first on a tie
  fn best(ns:[]const Node,at:m.V3,skip:?usize)?Pick{
    // the best yet
    var out:?Pick=null;
    for(ns,0..)|nd,k|{
      if(k==skip or nd.radius<=0)continue;
      // how far it is from the node, and how strongly it is reached
      const d=flat(nd.at,at);
      if(d>nd.radius)continue;
      const st=strength(d,nd.radius);
      if(out==null or st>out.?.strength)out=.{.node=@intCast(k),.strength=st};
    }
    return out;
  }
  /// what every user wants: each draws from the node it stands best in (a
  /// strip it stands on reaches it whole)
  fn want(l:*Light,gpa:Allocator,s:Slice,users:[]const User)Allocator.Error!void{
    l.pick.clearRetainingCapacity();
    for(s.items(.sp),0..)|sp,i|{
      // how much this plant draws
      const dr=species.get(sp).draw;
      if(dr<=0)continue;
      try l.pick.append(gpa,l.pickFor(s.items(.at)[i],dr));
    }
    for(users)|u|try l.pick.append(gpa,l.pickFor(u.at,u.draw));
  }
  /// the node a user at `at` drawing `dr` takes from, its demand counted
  fn pickFor(l:*Light,at:m.V3,dr:f32)Pick{
    // the field it stands best in, if any
    var out=best(l.nodes.items,at,null) orelse Pick{.node=none,.strength=0};
    // a strip it stands on reaches it whole
    const t=m.tileAt(at);
    for(l.nodes.items,0..)|nd,k|if(nd.strip>0 and onStrip(nd,t[0],t[1])){
      if(out.node==none or out.strength<1)out=.{.node=@intCast(k),.strength=1};
      break;
    };
    if(out.node!=none)l.nodes.items[out.node].demand+=dr;
    return out;
  }
  /// light flows out from where it is made, nearest first: each node keeps
  /// what its users want (an astrocyme makes up a shortfall from its store)
  /// and hands what is left to those it reached first, evenly, each up to
  /// what it takes in; an astrocyme stores what none takes
  fn flow(l:*Light,gpa:Allocator,s:Slice,dt:f32)Allocator.Error!void{
    // the nodes
    const ns=l.nodes.items;
    l.order.clearRetainingCapacity();
    // the sources, strongest first, each spreading breadth first out along
    // the edges before the next is looked at: one a stronger source reached
    // is fed from it as well as making its own (a relay a dusk beam has
    // only begun to pour into stays fed by the solcyriphon above it, not
    // cut off with the beam's first trickle)
    var head:usize=0;
    while(true){
      // the strongest source no light has reached yet
      var top:?usize=null;
      for(ns,0..)|nd,k|if(nd.supply>0 and nd.parent==none and (top==null or nd.supply>ns[top.?].supply)){top=k;};
      const k=top orelse break;
      ns[k].parent=@intCast(k);
      try l.order.append(gpa,@intCast(k));
      try l.spread(gpa,&head);
    }
    // then the stores with light in them that none of it reached, each a
    // source of its own (never before what makes light: a store a tick
    // filled and the next emptied would turn the whole tree each tick, the
    // light flickering between two ways of flowing)
    const made=l.order.items.len;
    for(ns,0..)|nd,k|if(nd.parent==none and storeOf(s,nd)>0){
      ns[k].parent=@intCast(k);
      try l.order.append(gpa,@intCast(k));
    };
    if(l.order.items.len>made)try l.spread(gpa,&head);
    for(l.order.items)|u|{
      // the node, what reached it and what it carries
      const nd=&ns[u];
      nd.carried=@min((nd.supply+nd.got)*(if(nd.lensed)lensGain else 1),nd.cap);
      // an astrocyme makes up its users' shortfall from its store
      if(storeOf(s,nd.*)>0){
        // the plant, and how much its users go short
        const id=nd.ref.plant.idx();
        const short=@max(0,nd.demand-nd.carried);
        // what it gives a second: the shortfall, no more than it pours or holds
        const give=@min(@min(short,species.get(s.items(.sp)[id]).carry),s.items(.stored)[id]/@max(dt,1e-6));
        nd.carried+=give;
        s.items(.stored)[id]-=give*dt;
      }
      nd.kept=@min(nd.carried,nd.demand);
      // what is left once its users have theirs
      var spare=nd.carried-nd.kept;
      spare-=l.handOn(u,spare);
      // an astrocyme stores what none took
      if(nd.ref==.plant){
        // the plant, and its kind
        const id=nd.ref.plant.idx();
        const d=species.get(s.items(.sp)[id]);
        if(d.store>0){
          // how much it takes in this tick
          const fill=@min(@min(spare,d.carry)*dt,d.store-s.items(.stored)[id]);
          s.items(.stored)[id]+=@max(0,fill);
        }
      }
    }
    // the threads: every link both ends reached, lit by what passed along it
    for(ns,0..)|a,i|for(l.edges.items[l.first.items[i]..l.first.items[i+1]])|e|{
      if(e.way!=.link or e.to<i)continue;
      // the far end, and the light that went between them
      const b=ns[e.to];
      const glow=if(b.parent==i)b.got else if(a.parent==e.to)a.got else 0;
      try l.links.append(gpa,.{.a=a.ref,.b=b.ref,.glow=glow});
    };
    // the strips, as long as they run, lit by what their heliocyras carry
    for(ns)|nd|if(nd.strip>0)try l.strips.append(gpa,.{.from=nd.ref.plant,.len=nd.strip,.glow=nd.carried});
  }
  /// breadth first out along the edges from the nodes in `order` from
  /// `head.*` on, each node reached once, from the first to reach it
  fn spread(l:*Light,gpa:Allocator,head:*usize)Allocator.Error!void{
    // the nodes
    const ns=l.nodes.items;
    while(head.*<l.order.items.len):(head.*+=1){
      // the node being spread from
      const u=l.order.items[head.*];
      for(l.edges.items[l.first.items[u]..l.first.items[u+1]])|e|{
        if(ns[e.to].parent!=none)continue;
        ns[e.to].parent=u;
        ns[e.to].way=e.way;
        try l.order.append(gpa,e.to);
      }
    }
  }
  /// hands `spare` from node `u` on to the nodes it reached first, evenly,
  /// each up to what it takes in (light bent on loses a little on the
  /// way); returns how much went
  fn handOn(l:*Light,u:u32,spare:f32)f32{
    // the nodes, and what is still to hand out
    const ns=l.nodes.items;
    var left=spare;
    // the children still open, counted until none is filled
    while(left>1e-6){
      // how many still take more, and what each would be given evenly
      var open:usize=0;
      for(l.edges.items[l.first.items[u]..l.first.items[u+1]])|e|{
        if(isChild(ns,u,e) and room(ns,e)>1e-6)open+=1;
      }
      if(open==0)break;
      // an even share, and whether any filled up this round
      const each=left/m.f(open);
      for(l.edges.items[l.first.items[u]..l.first.items[u+1]])|e|{
        if(!isChild(ns,u,e))continue;
        // how much it still takes
        const r=room(ns,e);
        if(r<=1e-6)continue;
        const give=@min(each,r);
        ns[e.to].got+=give*(if(e.way==.bend)bendKeep else 1);
        left-=give;
      }
    }
    return spare-left;
  }
  /// whether `e` leads from `u` to a node `u` reached first
  fn isChild(ns:[]const Node,u:u32,e:Edge)bool{return ns[e.to].parent==u and ns[e.to].way==e.way;}
  /// how much more the node `e` leads to takes in, its way taken into
  /// account (a heliocyra takes `stripTake` from a field; light bent on
  /// counts before its loss; what it makes itself fills it too)
  fn room(ns:[]const Node,e:Edge)f32{
    // the node it leads to, and the most it takes in that way
    const to=ns[e.to];
    const most=if(e.way==.field)@min(stripTake,to.cap)else to.cap;
    const had=to.got/(if(e.way==.bend)bendKeep else 1)+to.supply;
    return@max(0,most-had);
  }
  /// every user's share: how strongly it is reached times its node's share
  /// to go round; a plant short of a quarter withers (the ecology's)
  fn share(l:*Light,s:Slice,users:[]const User)void{
    // the picks, plants first then structures, walked in turn
    var k:usize=0;
    for(s.items(.sp),0..)|sp,i|{
      if(species.get(sp).draw<=0)continue;
      l.lit.items[i]=l.got(l.pick.items[k]);
      k+=1;
    }
    for(0..users.len)|u|{
      l.userLit.items[u]=l.got(l.pick.items[k]);
      k+=1;
    }
  }
  /// the share pick `pk` gets: how strongly it is reached, times what its
  /// node kept over what its users wanted (where none of them draws, only
  /// looking lit, a lit node's light is theirs as far as it reaches them)
  fn got(l:*const Light,pk:Pick)f32{
    if(pk.node==none)return 0;
    // the node it draws from
    const nd=l.nodes.items[pk.node];
    if(nd.demand<=0)return if(nd.carried>0)pk.strength else 0;
    return pk.strength*nd.kept/nd.demand;
  }
  /// halcyras guard: one put down beside a plant guards that one alone,
  /// one with no plant beside it every plant within its reach; each eases
  /// its lean toward the one it guards, or back to its net alone, over
  /// `dt` (`leanRate`)
  fn guard(l:*Light,s:Slice,p:*const Plants,w:*const World,dt:f32)Allocator.Error!void{
    for(s.items(.sp),0..)|sp,i|{
      // the species, and how far it guards
      const d=species.get(sp);
      if(d.guards<=0)continue;
      // the first plant beside it, if any (none while it is still gathering)
      const beside=if(s.items(.growth)[i]<1)null else for(s.items(.n1)[i])|j|{
        if(j==.none)break null;
        if(!species.get(s.items(.sp)[j.idx()]).lightNode())break j;
      }else null;
      if(beside)|j|s.items(.leanTo)[i]=s.items(.at)[j.idx()];
      s.items(.lean)[i]=m.damp(s.items(.lean)[i],if(beside!=null)1 else 0,leanRate,dt);
      if(s.items(.growth)[i]<1)continue;
      if(beside)|j|{
        l.guarded.items[j.idx()]=true;
        l.ward.items[i]=j;
        continue;
      }
      // every plant within its reach, rooted or floating
      const reach=m.floorTo(i32,d.guards);
      var it=m.footprint(s.items(.x)[i]-reach,s.items(.y)[i]-reach,@intCast(2*reach+1));
      while(it.next())|t|{
        // the plant rooted there, if any
        const j=p.at(w,t[0],t[1]) orelse continue;
        if(flat(s.items(.at)[j.idx()],s.items(.at)[i])<=d.guards+0.5)l.guarded.items[j.idx()]=true;
      }
      for(p.floaters.items)|f|if(flat(s.items(.at)[f.idx()],s.items(.at)[i])<=d.guards){l.guarded.items[f.idx()]=true;};
    }
  }
};
/// how strongly a field reaches a user `d` tiles from its middle, its edge
/// at `radius`: whole within `nearFull`, fading evenly to `edgeShare`
pub fn strength(d:f32,radius:f32)f32{
  if(radius<=nearFull)return 1;
  return m.lerp(1,edgeShare,m.unlerp(nearFull,radius,d));
}
/// how far apart two points lie, flat across the ground
fn flat(a:m.V3,b:m.V3)f32{return m.dist(a*m.v3(1,0,1),b*m.v3(1,0,1));}
/// whether tile `x`,`y` lies on node `nd`'s strip
fn onStrip(nd:Node,x:i32,y:i32)bool{
  // the step along it, and how far along the tile lies
  const step=m.dirVec(nd.dir);
  const along=if(step.x!=0)@divFloor(x-nd.x,step.x)else@divFloor(y-nd.y,step.z);
  if(along<1 or along>nd.strip)return false;
  return nd.x+step.x*along==x and nd.y+step.z*along==y;
}
/// the light an astrocyme node holds in store (0 for any other node)
fn storeOf(s:Slice,nd:Node)f32{
  // the plant, if the node is one
  const id=switch(nd.ref){.plant=>|i|i,.relay=>return 0};
  if(species.get(s.items(.sp)[id.idx()]).store<=0)return 0;
  return s.items(.stored)[id.idx()];
}
/// the tests step at the 60 Hz tick: seconds a step
const testDt:f32=1.0/60.0;
/// a small garden for the tests: soil round the origin, plants on it
const Bench=struct{
  /// the world
  w:World,
  /// the plants
  p:Plants=.{},
  /// the grid
  l:Light=.{},
  /// a garden of soil and moss round the origin
  fn init(gpa:Allocator)!Bench{
    // the bench being built
    var b:Bench=.{.w=World.init(gpa,5)};
    try b.w.stream(.{.x=0,.y=0},1,100);
    // the chunk at the origin
    const c=b.w.chunkOfTile(0,0).?;
    for(0..16)|y|for(0..16)|x|{c.kind[y*lib.ck.sizeTiles+x]=.soil;};
    return b;
  }
  /// frees it all
  fn deinit(b:*Bench,gpa:Allocator)void{b.l.deinit(gpa);b.p.deinit(gpa);b.w.deinit();}
  /// puts down a grown plant of `sp` at tile `x`,`y` (a floater at its centre)
  fn put(b:*Bench,gpa:Allocator,x:i32,y:i32,sp:species.Id)!Id{
    try testing.expect(try b.p.placeEx(gpa,&b.w,x,y,.{.x=x,.y=y,.chunk=undefined,.tile=undefined,.sp=sp,.seed=0,.growth=1}));
    return.of(b.p.len()-1);
  }
  /// works the grid out once, at `night`
  fn run(b:*Bench,gpa:Allocator,night:f32)!void{try b.l.update(gpa,&b.p,&b.w,&.{},&.{},night,testDt);}
};
test"by day a solcyriphon lights its field; a bloom linked to it carries it on, nearest first"{
  // the test allocator, and a small garden
  const gpa=testing.allocator;
  var b=try Bench.init(gpa);
  defer b.deinit(gpa);
  // a solcyriphon, a vesper right under its field, a bloom 6 tiles on and a vesper by it
  _=try b.put(gpa,2,2,.solcyriphon);
  const near=try b.put(gpa,3,2,.vesper);
  const bloom=try b.put(gpa,8,2,.bloom);
  const far=try b.put(gpa,9,2,.vesper);
  const out=try b.put(gpa,14,14,.vesper);
  try b.run(gpa,0);
  // the near vesper has its light whole, the far one by the bloom too,
  // the bloom carries what reached it, and the one out of every field none
  try testing.expect(b.l.lit.items[near.idx()]>0.9);
  try testing.expect(b.l.lit.items[far.idx()]>0.9);
  try testing.expect(b.l.carried.items[bloom.idx()]>0);
  try testing.expectEqual(@as(f32,0),b.l.lit.items[out.idx()]);
  try testing.expectEqual(@as(usize,1),b.l.links.items.len);
  try testing.expect(b.l.links.items[0].glow>0);
}
test"a relay carries all it is given: six users round a bloom draw more than four glow"{
  // the test allocator, and a small garden
  const gpa=testing.allocator;
  var b=try Bench.init(gpa);
  defer b.deinit(gpa);
  // a solcyriphon off to one side, a bloom linked to it, and six vespers round the bloom (each draws 1)
  _=try b.put(gpa,3,3,.solcyriphon);
  _=try b.put(gpa,9,9,.bloom);
  // the vespers round the bloom
  var v:[6]Id=undefined;
  for(&v,0..)|*x,k|x.*=try b.put(gpa,8+@as(i32,@intCast(k%3)),8+2*@as(i32,@intCast(k/3)),.vesper);
  try b.run(gpa,0);
  // the bloom has no cap (it once carried 4 at most, two thirds each):
  // what the solcyriphon makes reaches all six, more than the old cap's share
  var all:f32=0;
  for(v)|x|all+=b.l.lit.items[x.idx()];
  try testing.expect(all>4+1e-3);
}
test"what only looks lit is lit where light reaches it, though it draws none"{
  // the test allocator, and a small garden
  const gpa=testing.allocator;
  var b=try Bench.init(gpa);
  defer b.deinit(gpa);
  // a solcyriphon, and two users drawing nothing: one in its field, one far out
  _=try b.put(gpa,2,2,.solcyriphon);
  try b.l.update(gpa,&b.p,&b.w,&.{},&.{.{.at=m.v3(3.5,0,2.5),.draw=0},.{.at=m.v3(14.5,0,14.5),.draw=0}},0,testDt);
  try testing.expect(b.l.userLit.items[0]>0.9);
  try testing.expectEqual(@as(f32,0),b.l.userLit.items[1]);
}
test"by night the beam pours into the relay under it, or overdrives the plant under it"{
  // the test allocator, and a small garden
  const gpa=testing.allocator;
  var b=try Bench.init(gpa);
  defer b.deinit(gpa);
  // a solcyriphon over a lumenroot: at full night the beam overdrives it
  _=try b.put(gpa,4,4,.solcyriphon);
  const root=try b.put(gpa,4,4,.lumenroot);
  try b.run(gpa,1);
  try testing.expectEqual(@as(f32,1),b.l.beamed.items[root.idx()]);
  try testing.expectEqual(Onto.plant,b.l.beams.items[0].onto);
  // by day, no beam
  try b.run(gpa,0);
  try testing.expectEqual(@as(f32,0),b.l.beamed.items[root.idx()]);
}
test"a diamond a night beam strikes is a lens: what it carries grows by lensGain, once"{
  // the test allocator, and a small garden
  const gpa=testing.allocator;
  var b=try Bench.init(gpa);
  defer b.deinit(gpa);
  // a solcyriphon, and a diamond (a structure's relay) right under it
  _=try b.put(gpa,4,4,.solcyriphon);
  const under=[_]Relay{.{.at=m.v3(4.5,0,4.5),.radius=7,.carry=species.uncapped,.link=14,.x=4,.y=4}};
  try b.l.update(gpa,&b.p,&b.w,&under,&.{},1,testDt);
  // the whole beam reaches it, and it carries a twentieth more
  const beam=species.get(.solcyriphon).glow[1];
  try testing.expectApproxEqAbs(beam*lensGain,b.l.relayCarried.items[0],1e-3);
  // a diamond the beam misses (linked, two tiles off) is no lens
  const beside=[_]Relay{.{.at=m.v3(6.5,0,4.5),.radius=7,.carry=species.uncapped,.link=14,.x=6,.y=4}};
  try b.l.update(gpa,&b.p,&b.w,&beside,&.{},1,testDt);
  try testing.expect(b.l.relayCarried.items[0]<=beam+1e-3);
}
test"a halcyra beside a plant guards it alone; alone, it guards all round it"{
  // the test allocator, and a small garden
  const gpa=testing.allocator;
  var b=try Bench.init(gpa);
  defer b.deinit(gpa);
  // a halcyra beside a lumenroot, another lumenroot two tiles off
  _=try b.put(gpa,4,4,.halcyra);
  const by=try b.put(gpa,5,4,.lumenroot);
  const off=try b.put(gpa,4,7,.lumenroot);
  b.p.rebuildLinks(&b.w);
  try b.run(gpa,0);
  try testing.expect(b.l.guarded.items[by.idx()]);
  try testing.expect(!b.l.guarded.items[off.idx()]);
  // (it says whom it guards, for its thread to wind round)
  try testing.expectEqual(by,b.l.ward.items[0]);
  // it leans in over the plant beside it by degrees, never at a blink
  try testing.expect(b.p.list.items(.lean)[0]<0.1);
  for(0..120)|_|try b.run(gpa,0);
  try testing.expect(b.p.list.items(.lean)[0]>0.9);
  // a lone halcyra guards both plants within its reach
  _=try b.put(gpa,10,10,.halcyra);
  const a=try b.put(gpa,10,12,.lumenroot);
  const c=try b.put(gpa,12,10,.lumenroot);
  b.p.rebuildLinks(&b.w);
  try b.run(gpa,0);
  try testing.expect(b.l.guarded.items[a.idx()] and b.l.guarded.items[c.idx()]);
}
test"a heliocyra casts its field's light as a strip, and another bends it on"{
  // the test allocator, and a small garden
  const gpa=testing.allocator;
  var b=try Bench.init(gpa);
  defer b.deinit(gpa);
  // a solcyriphon, a heliocyra in its field facing east, another 5 tiles
  // east of it facing south, and a vesper on the second's strip
  _=try b.put(gpa,2,2,.solcyriphon);
  _=try b.put(gpa,3,2,.heliocyra);
  const turn=try b.put(gpa,8,2,.heliocyra);
  b.p.list.items(.dir)[turn.idx()]=1;
  const v=try b.put(gpa,8,6,.vesper);
  try b.run(gpa,0);
  try testing.expectEqual(@as(usize,2),b.l.strips.items.len);
  // the first strip ends where it strikes the second
  try testing.expectEqual(@as(u8,5),b.l.strips.items[0].len);
  try testing.expect(b.l.lit.items[v.idx()]>0.9);
}
test"an astrocyme stores what none takes, and gives it back when its users go short"{
  // the test allocator, and a small garden
  const gpa=testing.allocator;
  var b=try Bench.init(gpa);
  defer b.deinit(gpa);
  // a solcyriphon, an astrocyme linked to it, and a vesper by the astrocyme
  _=try b.put(gpa,2,2,.solcyriphon);
  const store=try b.put(gpa,8,2,.astrocyme);
  for(0..600)|_|try b.run(gpa,0);
  try testing.expect(b.p.list.items(.stored)[store.idx()]>0);
  // the solcyriphon gone dark (a night with nothing under its beam): the store lights the vesper
  const v=try b.put(gpa,9,2,.vesper);
  try b.run(gpa,1);
  try testing.expect(b.l.lit.items[v.idx()]>0.9);
}
test"through a whole day and night the light never flickers: no share jumps from one tick to the next"{
  // the test allocator, and a small garden: a solcyriphon over a bloom, an
  // astrocyme and a far bloom linked on, a vesper by each, two structures
  const gpa=testing.allocator;
  var b=try Bench.init(gpa);
  defer b.deinit(gpa);
  _=try b.put(gpa,2,2,.solcyriphon);
  _=try b.put(gpa,2,2,.bloom);
  _=try b.put(gpa,6,2,.astrocyme);
  _=try b.put(gpa,10,2,.bloom);
  // the vespers, one by each relay
  const vs=[_]Id{try b.put(gpa,3,3,.vesper),try b.put(gpa,7,3,.vesper),try b.put(gpa,11,3,.vesper)};
  // the structures drawing light, by the near and the far bloom
  const users=[_]User{.{.at=m.v3(3.5,0,1.5),.draw=2},.{.at=m.v3(9.5,0,1.5),.draw=2}};
  // each share last tick
  var prev=[_]f32{0}**(vs.len+users.len);
  for(0..4000)|k|{
    // the day, then dusk, the night and dawn, a thousand ticks each
    const t=m.f(k);
    const night:f32=if(k<1000)0 else if(k<2000)(t-1000)/1000 else if(k<3000)1 else 1-(t-3000)/1000;
    try b.l.update(gpa,&b.p,&b.w,&.{},&users,night,testDt);
    // each share now
    var now:[vs.len+users.len]f32=undefined;
    for(vs,0..)|v,i|now[i]=b.l.lit.items[v.idx()];
    for(0..users.len)|i|now[vs.len+i]=b.l.userLit.items[i];
    if(k>0)for(now,prev)|a,p|try testing.expect(@abs(a-p)<0.05);
    prev=now;
  }
}
