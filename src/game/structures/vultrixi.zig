//! VULTRIXI: a gathering crown and a ganglion grown into one floating body
//! that feeds a monfris. Configured, then the monfris configured, it is
//! tethered there: the monfris's child (`dependOn`, at most
//! `monfris.tethers` to one). It takes on one
//! kind of what the monfris's weave needs, by its place among the
//! Vultrixi tethered there (the first the weave's first ingredient, and so
//! on), reaches a tendril into the nearest structure within `reachTiles`
//! tiles that would let that kind go, pulls it out a unit at a time and
//! sends each along its tether into the monfris, while the monfris wants it.
//! Untethered, it relays instead (its second job): it links to every other
//! untethered Vultrixi within `linkTiles`, and together they carry what
//! one pulls from a structure in its reach, hop by hop along their links,
//! to the one nearest a structure that wants it, which hands it over.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the test harness: allocator and expectations
const testing=std.testing;
/// all the maths: vectors, matrices, curves
const m=lib.engine.core.math;
/// colour conversions, for tinting a mote by its item's colour
const color=lib.engine.core.color;
/// chunk layout and tiles
const ck=lib.ck;
/// the garden's tile world
const World=lib.world.World;
/// what can be held: item kinds and stacks of them
const items=lib.items;
/// the garden's plants (the tests' bench needs a list of them)
const Plants=lib.plants.Plants;
/// the structures registry: `Def`, `Structure`, the hooks' context
const st=lib.structures;
/// the shared structure test bench: ground, running ticks
const bench=st.bench;
/// the tools a bulb icon is drawn with
const iconKit=lib.icon;
/// every player-facing string
const txt=lib.txt;
/// what the gardener has understood
const prog=lib.progression;
/// the weave recipes, to learn what its monfris needs
const craft=lib.craft;
/// the HUD's shared sizes and colours
const style=lib.style;
/// the scene's list of moving parts it adds to each frame
const Parts=lib.parts.Parts;
/// how one part looks: its glow, tint, sway and growth
const Look=lib.parts.Look;
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the Vultrixi's mesh: its crown and the point under it
const mesh=lib.vultrixi;
/// the monfris's mesh, for where its sac hangs (the tether's end)
const loomMesh=lib.monfris;
/// the sporecaster's module, for its `groundAt`
const caster=lib.sporecasterStructure;
/// the monfris's module, for how many it may tether
const monfris=lib.monfrisStructure;
/// a three-float vector
const V3=m.V3;
/// builds a three-float vector
const v3=m.v3;
// decision: its hover is carried by its mesh (`mesh.hover`), as a weftstone's
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.itemPod,.monfrisTether,.weftstoneTendril};
/// what a Vultrixi is: grown from its seed, one tile across, floating,
/// tall, swaying a little, and drawn from afar
pub const def:st.Def=.{.item=.vultrixi,.size=1,.mesh=.vultrixi,.grow=6,.sway=0.3,.tall=1.3,.sap=0.3,.floating=true,.far=true};
/// how far its tendril reaches (tiles between it and a structure's edge)
pub const reachTiles=6;
/// seconds its tendril takes to reach a structure
const reachDistance:f32=0.8;
/// seconds it takes to pull a unit out
pub const pull:f32=1;
/// tiles a second what it pulls runs along its tether
const runAmount:f32=3;
/// how much its tether and tendril flutter in the breeze
const tendrilFlutter:f32=0.25;
/// how deep its tether sags between it and the monfris
const tetherSag:f32=0.25;
/// the size of the mote running along its tether
const moteSize:f32=0.32;
/// how brightly that mote glows
const moteGlow:f32=0.7;
/// how brightly its tether and tendril glow
const glow:f32=0.18;
/// a unit running along its tether: what it is, and how far along (0..1)
pub const Carry=struct{item:items.Item,t:f32=0};
/// what a Vultrixi remembers: where its monfris stands, the kind it brings,
/// the structure it pulls from, and what runs along its tether
pub const State=struct{
  /// the ground under the monfris it feeds (its parent)
  destH:f32=0,
  /// the kind it brings (from its place among the tethered)
  kind:?items.Item=null,
  /// the tile of the structure its tendril reaches (null: none)
  src:?[2]i32=null,
  /// that structure's size, tiles
  srcSize:u8=1,
  /// the ground height under it
  srcH:f32=0,
  /// how far the tendril has reached it (0..1)
  reach:f32=0,
  /// how far along the unit it pulls is (0..1)
  pull:f32=0,
  /// what runs along its tether now
  carry:?Carry=null,
  /// what it relays along its links now (untethered), if anything
  relay:?Relay=null,
};
/// the monfris it is tethered to
fn loomOf(ss:*st.Structures,i:st.Id)?st.Id{
  // its parent, if it has one
  const j=ss.getParent(i) orelse return null;
  return if(ss.get(j).kind()==.monfris)j else null;
}
/// configured, it waits to be tethered by configuring a monfris next
/// (`monfris.configure`); configured twice over, it is cut loose.
pub fn configure(ss:*st.Structures,id:st.Id,g:*prog.Progression)void{
  // a lasting reference to it, to wait in `ss.pairing`
  const here=ss.get(id).ref();
  if(ss.pairing)|p|if(p.eql(here)){
    ss.pairing=null;
    ss.detach(id);
    return g.say(txt.s.msg.tetherCut,.{});
  };
  ss.pairing=here;
  g.say(txt.s.msg.tetherChoose,.{});
}
/// the kind the Vultrixi `i` brings its monfris `j`: the ingredient of
/// its weave at its place among those tethered there
fn assigned(ss:*st.Structures,i:st.Id,j:st.Id)?items.Item{
  // its place among the Vultrixi tethered there, and the monfris's children
  var rank:usize=0;
  var kin=ss.getChildren(j);
  while(kin.next())|o|{
    if(o==i)break;
    if(ss.get(o).kind()==.vultrixi)rank+=1;
  }
  // the weave the monfris is set to
  const r=craft.hand[st.chosen(ss.get(j)) orelse return null];
  return if(rank<r.in.len)r.in[rank].item else null;
}
/// empty tiles between tile `p` and structure `s`'s footprint
fn gap(p:[2]i32,s:*const st.Structure)i32{
  // its size, and the gaps across and along (-1 inside it)
  const n:i32=s.def().size;
  const dx=@max(s.x-p[0]-1,p[0]-(s.x+n),-1);
  const dy=@max(s.y-p[1]-1,p[1]-(s.y+n),-1);
  return@max(dx,dy,0);
}
/// the nearest structure within reach that would let `kind` go
fn source(ss:*st.Structures,i:st.Id,kind:items.Item)?st.Id{
  // the Vultrixi itself, and its tile
  const self=ss.get(i);
  const here=[2]i32{self.x,self.y};
  // the nearest found so far, and how near (start: just past reach)
  var best:?st.Id=null;
  var near:i32=reachTiles+1;
  for(ss.list.items,0..)|*o,k|{
    if(k==i.idx() or o.def().carrier or o.grown<1)continue;
    // never from a monfris (what it weaves is the gardener's) or another
    // Vultrixi
    if(o.kind()==.monfris or o.kind()==.vultrixi)continue;
    // how far off it is
    const d=gap(here,o);
    if(d>=near)continue;
    // its id
    const id=st.Id.of(k);
    if(!ss.gives(id,kind))continue;
    best=id;
    near=d;
  }
  return best;
}
/// learns the kind it brings, runs what is on its tether into the monfris,
/// and otherwise reaches its tendril into the nearest source and pulls a
/// unit out each `pull` seconds while the monfris wants it (the tendril
/// withdrawing when it does not). Returns true while working.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // its remembered state
  const vs=&ctx.ss.get(i).state.vultrixi;
  // the monfris it feeds
  const j=loomOf(ctx.ss,i)orelse{
    vs.kind=null;
    return relayTick(ctx,i,dt);
  };
  // the monfris's tile
  const to=ctx.ss.get(i).parent.?.tile();
  vs.destH=caster.groundAt(ctx.w,to);
  vs.kind=assigned(ctx.ss,i,j);
  // what runs along the tether goes into the monfris at its end
  if(vs.carry)|*c|{
    // the Vultrixi itself, and how far its tether runs (tiles, at least one)
    const self=ctx.ss.get(i);
    const far=@max(m.len(v3(m.f(to[0]+1-self.x),0,m.f(to[1]+1-self.y))),1);
    c.t=@min(1,c.t+dt*runAmount/far);
    if(c.t>=1 and ctx.ss.insert(ctx.g,j,c.item,1)==1)vs.carry=null;
    return true;
  }
  // the kind it brings
  const kind=vs.kind orelse {
    vs.reach=@max(0,vs.reach-dt/reachDistance);
    return false;
  };
  if(ctx.ss.wants(ctx.g,j,kind)==0){
    vs.reach=@max(0,vs.reach-dt/reachDistance);
    return false;
  }
  // the structure it pulls from
  const src=source(ctx.ss,i,kind)orelse{
    vs.reach=@max(0,vs.reach-dt/reachDistance);
    return false;
  };
  const s=ctx.ss.get(src);
  // a new source: the tendril reaches out to it afresh
  if(vs.src==null or vs.src.?[0]!=s.x or vs.src.?[1]!=s.y){
    vs.src=.{s.x,s.y};
    vs.srcSize=s.def().size;
    vs.srcH=caster.groundAt(ctx.w,.{s.x,s.y});
    vs.reach=0;
    vs.pull=0;
  }
  if(vs.reach<1){
    vs.reach=@min(1,vs.reach+dt/reachDistance);
    return true;
  }
  vs.pull+=dt/pull;
  if(vs.pull<1)return true;
  vs.pull=0;
  if(s.inv.take(kind,1))vs.carry=.{.item=kind};
  return true;
}
/// how far (tiles) an untethered Vultrixi links to another
pub const linkTiles:f32=6;
/// the most Vultrixi a relay's search walks through
const maxKin=64;
/// one item relayed along the Vultrixi's links: what it is, how far along
/// the hop it has run (0..1), and where it is going: the next Vultrixi's
/// tile (null: it is handed over here) and the structure that wants it
pub const Relay=struct{
  /// what is relayed
  item:items.Item,
  /// how far along this hop (0..1)
  t:f32=0,
  /// the next Vultrixi's tile, or null to hand it over here
  next:?[2]i32=null,
  /// the tile of the structure it is bound for
  dest:[2]i32,
  /// the tile of the structure it was pulled from (never handed back there)
  from:[2]i32,
};
/// whether `o` is an untethered, grown Vultrixi within `linkTiles` of `s`
fn linked(s:*const st.Structure,o:*const st.Structure)bool{
  if(o.kind()!=.vultrixi or o==s or o.grown<1 or o.fade>0 or o.parent!=null)return false;
  // the way between them, level
  const d=o.at-s.at;
  return d[0]*d[0]+d[2]*d[2]<=linkTiles*linkTiles;
}
/// the nearest structure in `i`'s reach (no Vultrixi, monfris or the one
/// it came from) that wants `item`
fn wanting(ctx:st.Ctx,i:st.Id,item:items.Item,except:?st.Id)?st.Id{
  // the Vultrixi, its tile, and the nearest found so far
  const self=ctx.ss.get(i);
  const here=[2]i32{self.x,self.y};
  var best:?st.Id=null;
  var near:i32=reachTiles+1;
  for(ctx.ss.list.items,0..)|*o,k|{
    // its id, and how far off it is
    const id=st.Id.of(k);
    if(k==i.idx() or (except!=null and except.?==id) or o.grown<1 or o.fade>0)continue;
    if(o.kind()==.vultrixi or o.kind()==.monfris)continue;
    const d=gap(here,o);
    if(d>=near or ctx.ss.wants(ctx.g,id,item)==0)continue;
    best=id;
    near=d;
  }
  return best;
}
/// a way to hand `item` on from Vultrixi `from`: the first hop (itself if
/// it hands it over there) and the structure that wants it, found by a
/// walk outward along the links, nearest first
const Way=struct{first:st.Id,dest:st.Id};
/// (`Way` found as above, or null if no Vultrixi in reach of `from` along
/// its links has a structure wanting it)
fn route(ctx:st.Ctx,from:st.Id,item:items.Item,except:?st.Id)?Way{
  // the walk's queue, each one's first hop, and how many are in it
  var queue:[maxKin]st.Id=undefined;
  var first:[maxKin]st.Id=undefined;
  var n:usize=1;
  queue[0]=from;
  first[0]=from;
  // how far through the queue the walk has come
  var at:usize=0;
  while(at<n):(at+=1){
    // the Vultrixi this step reaches
    const v=queue[at];
    if(wanting(ctx,v,item,except))|dest|return.{.first=first[at],.dest=dest};
    for(ctx.ss.list.items,0..)|*o,k|{
      if(n==maxKin)break;
      if(!linked(ctx.ss.get(v),o))continue;
      // its id, unless the walk has been there already
      const id=st.Id.of(k);
      var seen=false;
      for(queue[0..n])|q|seen=seen or q==id;
      if(seen)continue;
      queue[n]=id;
      first[n]=if(at==0)id else first[at];
      n+=1;
    }
  }
  return null;
}
/// untethered: relays along its links. Carrying, the item runs along the
/// hop to the next Vultrixi, which takes it on (once it carries nothing)
/// or, bound here, hands it to the structure that wants it; carrying
/// nothing, it pulls a unit from a structure in its reach that something
/// along its links wants. Returns whether it is busy.
fn relayTick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // the Vultrixi and its remembered state
  const self=ctx.ss.get(i);
  const vs=&self.state.vultrixi;
  if(vs.relay)|*r|{
    vs.reach=@max(0,vs.reach-dt/reachDistance);
    const next=r.next orelse {
      // bound here: handed over, if the structure is still there and wants it
      const dest=ctx.ss.at(ctx.w,r.dest[0],r.dest[1])orelse{
        vs.relay=null;
        return false;
      };
      if(ctx.ss.insert(ctx.g,dest,r.item,1)==1)vs.relay=null;
      return true;
    };
    // how far this hop runs (tiles, at least one)
    const far=@max(m.len(v3(m.f(next[0]-self.x),0,m.f(next[1]-self.y))),1);
    r.t=@min(1,r.t+dt*runAmount/far);
    if(r.t<1)return true;
    // arrived: the next Vultrixi takes it on, if it carries nothing
    const nid=ctx.ss.floaterAt(next[0],next[1])orelse{
      vs.relay=null;
      return false;
    };
    // (it may be gone, or no longer a Vultrixi)
    if(ctx.ss.get(nid).kind()!=.vultrixi){
      vs.relay=null;
      return false;
    }
    const ns=&ctx.ss.get(nid).state.vultrixi;
    if(ns.relay!=null)return true;
    // its way on from there, never back where it came from
    const way=route(ctx,nid,r.item,ctx.ss.at(ctx.w,r.from[0],r.from[1])) orelse return true;
    // the Vultrixi it hops to after that, if any
    const after=if(way.first==nid)null else [2]i32{ctx.ss.get(way.first).x,ctx.ss.get(way.first).y};
    // the structure's tile
    const dt2=ctx.ss.get(way.dest);
    ns.relay=.{.item=r.item,.next=after,.dest=.{dt2.x,dt2.y},.from=r.from};
    vs.relay=null;
    return true;
  }
  // carrying nothing: the nearest structure in reach with something
  // wanted along its links
  const here=[2]i32{self.x,self.y};
  // the best source so far, how near, and the way its item goes
  var best:?st.Id=null;
  var near:i32=reachTiles+1;
  var way:?Way=null;
  var item:items.Item=.grit;
  for(ctx.ss.list.items,0..)|*o,k|{
    if(k==i.idx() or o.def().carrier or o.grown<1 or o.fade>0)continue;
    if(o.kind()==.monfris or o.kind()==.vultrixi)continue;
    // how far off it is, its id, and what it lets go first
    const d=gap(here,o);
    if(d>=near)continue;
    const id=st.Id.of(k);
    const it=ctx.ss.output(id) orelse continue;
    const w=route(ctx,i,it,id) orelse continue;
    best=id;
    near=d;
    way=w;
    item=it;
  }
  const src=best orelse {
    vs.reach=@max(0,vs.reach-dt/reachDistance);
    return false;
  };
  // the source
  const s=ctx.ss.get(src);
  if(vs.src==null or vs.src.?[0]!=s.x or vs.src.?[1]!=s.y){
    vs.src=.{s.x,s.y};
    vs.srcSize=s.def().size;
    vs.srcH=caster.groundAt(ctx.w,.{s.x,s.y});
    vs.reach=0;
    vs.pull=0;
  }
  if(vs.reach<1){
    vs.reach=@min(1,vs.reach+dt/reachDistance);
    return true;
  }
  vs.pull+=dt/pull;
  if(vs.pull<1)return true;
  vs.pull=0;
  if(!s.inv.take(item,1))return true;
  // where it goes: the first hop's tile (none: handed over here), and the structure's
  const w=way.?;
  const after=if(w.first==i)null else [2]i32{ctx.ss.get(w.first).x,ctx.ss.get(w.first).y};
  const d=ctx.ss.get(w.dest);
  vs.relay=.{.item=item,.next=after,.dest=.{d.x,d.y},.from=.{s.x,s.y}};
  return true;
}
/// cut loose when uprooted: what runs along its tether is lost back to it.
pub fn release(s:*st.Structure)?items.Item{
  // its remembered state
  const vs=&s.state.vultrixi;
  defer vs.carry=null;
  defer vs.relay=null;
  if(vs.relay)|r|return r.item;
  return if(vs.carry)|c|c.item else null;
}
/// a point `t` along the curve through `c` (as the GPU bends it, closely enough)
fn along(c:[4]V3,t:f32)V3{
  // what is left of the way
  const u=1-t;
  return c[0]*m.splat3(u*u*u)+c[1]*m.splat3(3*u*u*t)+c[2]*m.splat3(3*u*t*t)+c[3]*m.splat3(t*t*t);
}
/// the curve its tether hangs along, from its crown down to its monfris's
/// sac, sagging between (null while untethered)
fn tetherCtrl(s:*const st.Structure,base:m.M4)?[4]V3{
  // its remembered state, and its monfris's tile
  const vs=&s.state.vultrixi;
  const to=(s.parent orelse return null).tile();
  // its crown, the monfris's sac, and the way between
  const from=m.mulPoint(base,mesh.crown);
  const end=m.footprintCentre(to[0],to[1],2,vs.destH)+loomMesh.sacAt;
  const d=end-from;
  // how far the tether sags (deeper for a longer one, to a point)
  const sag=v3(0,-tetherSag*@min(m.len(d),4)*0.25,0);
  return.{from,from+d*m.splat3(1.0/3.0)+sag,from+d*m.splat3(2.0/3.0)+sag,end};
}
/// the level sideways across a curve's run, for its flat side
fn sideOf(c:[4]V3)V3{
  // the curve's run laid level
  const flat=v3(c[3][0]-c[0][0],0,c[3][2]-c[0][2]);
  return if(m.len(flat)>m.eps)m.norm(m.cross(flat,v3(0,1,0)))else v3(1,0,0);
}
/// its tether to its monfris (or, untethered, the hop it relays along),
/// what runs along it, and its tendril into
/// the structure it pulls from.
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // its remembered state, and its frame in the world
  const vs=&s.state.vultrixi;
  const base=s.place(ctr);
  if(tetherCtrl(s,base))|c|{
    try out.emitCurve(.monfrisTether,c,sideOf(c),1,s.grown,.{.flutter=tendrilFlutter,.phase=s.seed,.glow=glow});
    if(vs.carry)|cr|{
      // the mote's look: glowing, its item's colour
      const look:Look=.{.glow=moteGlow,.phase=s.seed,.tint=color.Rgba8.of(cr.item.info().col).toF4()};
      try out.emit(.itemPod,m.chain(&.{m.translate(along(c,m.smooth(cr.t))),m.scale3(m.splat3(moteSize))}),look);
    }
  }
  // untethered: a thread to every Vultrixi it links to (each pair drawn
  // once, by the one further west), the item it relays running along one
  if(s.parent==null)try links(s,out,base,tf);
  if(vs.reach>0)if(vs.src)|src|{
    // the point under it, the top of the source, and the way between
    const under=m.mulPoint(base,mesh.underAt);
    const end=m.footprintCentre(src[0],src[1],vs.srcSize,vs.srcH)+v3(0,0.25,0);
    const d=end-under;
    // the tendril's curve: dipping out from under it, arching down into the source
    const c=[4]V3{under,under+v3(d[0]*0.25,-0.2,d[2]*0.25),end+v3(-d[0]*0.15,0.35,-d[2]*0.15),end};
    try out.emitCurve(.weftstoneTendril,c,sideOf(c),1,vs.reach*s.grown,.{.flutter=tendrilFlutter,.phase=s.seed+0.3,.glow=glow});
  };
}
/// its line in the panel: loose (untethered), pulling a kind, or idle.
/// the threads from an untethered Vultrixi `s` to those it links to (from
/// the one further west, so each is drawn once), and the item it relays
/// running along the hop it takes
fn links(s:*const st.Structure,out:*Parts,base:m.M4,_:f32)Allocator.Error!void{
  // its remembered state, and its crown
  const vs=&s.state.vultrixi;
  const from=m.mulPoint(base,mesh.crown);
  if(vs.relay)|r|{
    // the hop it relays along, or the structure it hands to
    const to:V3=if(r.next)|n|m.v3(m.f(n[0])+0.5,from[1],m.f(n[1])+0.5)else m.v3(m.f(r.dest[0])+0.5,from[1]-0.6,m.f(r.dest[1])+0.5);
    // the way between, sagging
    const d=to-from;
    const sag=v3(0,-tetherSag*@min(m.len(d),4)*0.25,0);
    const c=[4]V3{from,from+d*m.splat3(1.0/3.0)+sag,from+d*m.splat3(2.0/3.0)+sag,to};
    try out.emitCurve(.monfrisTether,c,sideOf(c),1,s.grown,.{.flutter=tendrilFlutter,.phase=s.seed,.glow=glow});
    // the mote's look: glowing, its item's colour
    const look:Look=.{.glow=moteGlow,.phase=s.seed,.tint=color.Rgba8.of(r.item.info().col).toF4()};
    try out.emit(.itemPod,m.chain(&.{m.translate(along(c,m.smooth(r.t))),m.scale3(m.splat3(moteSize))}),look);
  }
}


pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // its remembered state
  const vs=&s.state.vultrixi;
  if(s.parent==null){
    if(vs.relay)|r|_=try d.print(x,y,style.textBody,style.white,txt.s.describe.vultRelays,.{txt.item(r.item).name})
    else _=try d.print(x,y,style.textBody,style.dim,txt.s.describe.vultLoose,.{});
  }else if(vs.kind!=null and (vs.reach>0 or vs.carry!=null)){
    _=try d.print(x,y,style.textBody,style.white,txt.s.describe.vultPulls,.{txt.item(vs.kind.?).name});
  }else{
    _=try d.print(x,y,style.textBody,style.dim,txt.s.describe.vultIdle,.{});
  }
}
/// its bulb: a pale knot over the seed, petals cupping it, a tendril down
/// into a pod on one side and a tether off to the other with a mote on it.
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // where its body floats, and the tether's curve off to the side
  const body:iconKit.P=.{0,0.7};
  const line=[4]iconKit.P{body,.{0.35,0.95},.{0.65,0.95},.{0.85,0.75}};
  try ic.stem(line,0.02,iconTether);
  // how far along the tether its mote has run (0..1)
  const k=@mod(ic.t*0.6+ic.phase,1);
  try ic.bud(iconKit.curve(line,k),0.045,iconMote,@sin(k*m.pi));
  try ic.stem(.{body,.{-0.25,0.5},.{-0.6,0.3},.{-0.7,-0.1}},0.03,iconTendril);
  try ic.bud(.{-0.7,-0.2},0.1,iconPod,0.4);
  for(0..5)|i|{
    // this petal's angle round the body
    const a=m.halfPi+m.ratio(i,5)*m.tau;
    try ic.leaf(body,a,0.18,0.09,iconPetal,1);
  }
  try ic.bud(body,0.12,iconSac,0.6);
  for(0..5)|i|{
    // this pearl's angle round the body
    const a=m.ratio(i,5)*m.tau;
    try ic.bud(.{body[0]+0.13*@cos(a),body[1]+0.11*@sin(a)},0.04,iconPearl,0.8);
  }
  try ic.coat(col);
}
/// the pale thread of its tether in its bulb
const iconTether:Color=.{200,195,220,255};
/// the warm gold of the mote along the tether
const iconMote:Color=.{245,210,150,255};
/// the violet of its tendril
const iconTendril:Color=.{175,160,210,255};
/// the amber of the pod its tendril reaches into
const iconPod:Color=.{210,160,70,255};
/// the orange of the petals cupping its body
const iconPetal:Color=.{235,160,100,255};
/// the violet, half-clear sac of its body
const iconSac:Color=.{180,140,230,220};
/// the pearly lilac of the beads round it
const iconPearl:Color=.{220,212,238,255};
// ---- tests ----
/// tethers the Vultrixi floating at `v` to the monfris at `loom`, as the
/// gardener would: configuring one, then the other
fn tether(ss:*st.Structures,w:*World,g:*prog.Progression,v:[2]i32,loom:[2]i32)void{
  st.configure(ss,ss.floaterAt(v[0],v[1]).?,g);
  st.configure(ss,ss.at(w,loom[0],loom[1]).?,g);
}
test"Vultrixi tether to a monfris, six at most, each bringing one kind of its weave"{
  // the allocator, the world and its ground
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  _=try bench.ground(&w,.{.width=16,.depth=16});
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  g.done.insert(craft.hand[craft.loom[0]].needs.?);
  try testing.expect(try ss.place(gpa,&w,6,6,.monfris,0,0));
  for(0..7)|k|try testing.expect(try ss.place(gpa,&w,@intCast(k+1),2,.vultrixi,0,0));
  for(0..7)|k|tether(&ss,&w,&g,.{@intCast(k+1),2},.{6,6});
  try testing.expectEqual(@as(u32,monfris.tethers),ss.childCount(ss.at(&w,6,6).?));
  try testing.expect(ss.get(ss.floaterAt(7,2).?).parent==null);
  try bench.run(&ss,&w,&plants,&g,0.1);
  // its weave's kinds go to the first, in order; the rest idle
  const r=craft.hand[ss.get(ss.at(&w,6,6).?).state.monfris.recipe];
  for(0..6)|k|{
    // the kind this Vultrixi brings
    const kind=ss.get(ss.floaterAt(@intCast(k+1),2).?).state.vultrixi.kind;
    if(k<r.in.len)try testing.expectEqual(r.in[k].item,kind.?)else try testing.expect(kind==null);
  }
}
test"a Vultrixi pulls what a structure lets go into its monfris, which weaves it"{
  // the allocator, the world and its ground
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  _=try bench.ground(&w,.{.width=16,.depth=16});
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  g.done.insert(craft.hand[craft.loom[0]].needs.?);
  try testing.expect(try ss.place(gpa,&w,8,8,.monfris,0,0));
  // the monfris, and the weave it is set to
  const loom=ss.at(&w,8,8).?;
  const r=craft.hand[ss.get(loom).state.monfris.recipe];
  // a cache of each kind beside a Vultrixi of its own, all tethered
  for(r.in,0..)|ing,k|{
    // the column this pair stands in
    const x:i32=@intCast(1+3*k);
    try testing.expect(try ss.place(gpa,&w,x,1,.vultrixi,0,0));
    try testing.expect(try ss.place(gpa,&w,x,3,.sapCache,0,0));
    _=ss.insert(&g,ss.at(&w,x,3).?,ing.item,30);
    tether(&ss,&w,&g,.{x,1},.{8,8});
  }
  // a germinator's unwoven ingredients are never pulled
  try testing.expect(try ss.place(gpa,&w,13,1,.germinator,0,0));
  _=ss.insert(&g,ss.at(&w,13,1).?,.fibre,6);
  try bench.run(&ss,&w,&plants,&g,40);
  try testing.expect(ss.get(loom).inv.count(r.out)>=1);
  try testing.expectEqual(@as(u32,6),ss.get(ss.at(&w,13,1).?).inv.count(.fibre));
}
test"untethered Vultrixi relay what one pulls along their links to a structure that wants it"{
  // the allocator, the world and its ground
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  _=try bench.ground(&w,.{.width=16,.depth=16});
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  // three Vultrixi in a line, each within reach of the next, a cache of
  // grit by the first and an empty one by the last, beyond the first's reach
  for([_]i32{1,6,11})|x|try testing.expect(try ss.place(gpa,&w,x,1,.vultrixi,0,0));
  try testing.expect(try ss.place(gpa,&w,1,3,.sapCache,0,0));
  try testing.expect(try ss.place(gpa,&w,14,3,.sapCache,0,0));
  // the full cache and the empty one
  const from=ss.at(&w,1,3).?;
  const to=ss.at(&w,14,3).?;
  _=ss.get(from).inv.add(.grit,5);
  try bench.run(&ss,&w,&plants,&g,40);
  try testing.expect(ss.get(to).inv.count(.grit)>0);
  try testing.expectEqual(@as(u32,5),ss.get(from).inv.count(.grit)+ss.get(to).inv.count(.grit)+inFlight(&ss));
}
/// how many items the Vultrixi have in flight between them (a test's count)
fn inFlight(ss:*st.Structures)u32{
  // the count so far
  var n:u32=0;
  for(ss.list.items)|*s|if(s.kind()==.vultrixi and s.state.vultrixi.relay!=null){n+=1;};
  return n;
}
