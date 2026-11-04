//! the flow: constellate tendrils (act 2). Holding `tendril`, the star
//! hyena sweeps the cursor from one structure across the garden to another
//! (or back to himself); the tiles it passes are the tendril's path. Loose
//! fragments flow in from his keeping (one for every two tiles) and braid
//! it from its start to its end, three strands winding round each other,
//! always flowing on along it like a stream; the wheel, while he draws,
//! sets how high the tile under the cursor floats (on the ground up to
//! `highest`), each tile swept after it starting there, so the path can
//! rise and fall tile by tile, the whole curve running smoothly through
//! every tile's height. Braided, it
//! carries: whatever its start hands over (a seed's fragment, a yielder's,
//! the part a heart has made) rides along it, one at a time, to its end,
//! which takes it in (a heart its fragments; the gardener anything). It is
//! one flow along its whole path: the path's points go to the GPU as this
//! frame's bones and every light of it is placed there by how far along
//! the whole of it it has flowed (`constellateTendrilFlow`, part.vert
//! `plexusTendrilGarden`).
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the lists grow with
const Allocator=std.mem.Allocator;
/// a growable list
const ArrayList=std.ArrayList;
/// the test harness: expectations
const testing=std.testing;
/// all the maths: vectors, splines, tiles
const m=lib.engine.core.math;
/// the structures registry: references, hand-overs, taking in
const st=lib.structures;
/// what can be carried
const items=lib.items;
/// every player-facing string
const txt=lib.txt;
/// the game: its garden, its gardener
const Game=lib.play.Game;
/// the scene's list of moving parts a tendril draws into
const Parts=lib.parts.Parts;
/// the most tiles a tendril's path runs over
pub const most=32;
/// how long braiding one tile of it takes (s)
pub const braidPerTile:f32=0.6;
/// how fast what it carries rides along it (tiles a second)
pub const speed:f32=1.5;
/// how high over the ground a tendril's tiles float unless the wheel says
/// otherwise (m; the tendril sketch's)
pub const lift:f32=1.0;
/// the highest it can be set to float (m)
pub const highest:f32=3.0;
/// how much higher or lower a notch of the wheel sets it (m)
pub const notch:f32=0.25;
/// how far it sags at its middle floating a metre up, less lower down (m)
pub const sag:f32=0.2;
/// how high over the ground it lies set on the ground (m; the sketch's)
pub const low:f32=0.06;
/// how many lights a chunk of it holds (part.vert `PLEXUS_FLOW_LIGHTS`)
const flowLights=90;
/// how many slices of three lights a metre of it holds (`PLEXUS_FLOW_PER`)
const flowPer:f32=10;
/// how big what rides it is drawn, beside its own size (the sketch's)
const rideScale:f32=0.3;
/// how far over it what rides it floats (m)
const rideOver:f32=0.12;
/// how fast what rides it turns as it goes (rad/s)
const rideTurn:f32=0.5;
/// over how much of its ride it fades in at the start and out at the end
const rideEnds:f32=0.08;
/// a tile of the garden
pub const Tile=m.Vice(i32,2);
/// one tendril: where it runs from and to, its path, how far braided, and
/// what rides it now
pub const Tendril=struct{
  /// the structure it runs from
  from:st.Ref,
  /// the structure it runs to (none: the gardener)
  to:?st.Ref,
  /// the tiles it runs over, start to end
  path:[most]Tile=undefined,
  /// how many of them
  n:u8,
  /// how high over the ground each of its tiles floats (m; 0 on the ground)
  highs:[most]f32=@splat(lift),
  /// how far braided, start to end (0..1)
  fill:f32=0,
  /// what rides it now
  cargo:?items.Item=null,
  /// how far along it that has come (0..1)
  s:f32=0,
  /// its path's tiles
  pub fn tiles(t:*const Tendril)[]const Tile{return t.path[0..t.n];}
};
/// a tendril being drawn: the tiles swept so far
pub const Draft=struct{
  /// the tiles swept, start first
  path:[most]Tile=undefined,
  /// how many
  n:u8=0,
  /// how high over the ground each floats (m)
  highs:[most]f32=@splat(lift),
};
/// every tendril in the garden, and the one being drawn
pub const Tendrils=struct{
  /// the tendrils
  list:ArrayList(Tendril)=.empty,
  /// the one the gardener draws now, if any
  draft:?Draft=null,
  /// how high the next tile swept floats (m), set by the wheel while
  /// drawing
  high:f32=lift,
  /// free the list
  pub fn deinit(ts:*Tendrils,gpa:Allocator)void{ts.list.deinit(gpa);}
};
/// whether tiles `a` and `b` are the same tile
fn same(a:Tile,b:Tile)bool{return a[0]==b[0] and a[1]==b[1];}
/// how many fragments braiding a path of `n` tiles takes: one for every two
pub fn cost(n:u8)u16{return @intCast((n+1)/2);}
/// the wheel turned `notches` while drawing: the tile under the cursor (and
/// every one swept after it) floats higher (+) or lower, down to the ground
pub fn raise(g:*Game,notches:f32)void{
  const ts=&g.tendrils;
  ts.high=@min(@max(ts.high+notches*notch,0),highest);
  if(ts.draft)|*d|d.highs[d.n-1]=ts.high;
}
/// one frame of drawing: while `held`, the cursor's tile `hover` (begun on
/// a structure) is swept into the draft; let go, the draft becomes a
/// tendril to what stands at its end (or the gardener, on his own tile),
/// paid for in fragments from his keeping
pub fn drag(g:*Game,held:bool,hover:?Tile)Allocator.Error!void{
  const ts=&g.tendrils;
  if(held){
    const h=hover orelse return;
    if(ts.draft)|*d|{
      // a new tile, swept in
      if(same(d.path[d.n-1],h) or d.n==most)return;
      d.path[d.n]=h;
      d.highs[d.n]=ts.high;
      d.n+=1;
      return;
    }
    if(g.structs.at(&g.world,h[0],h[1])==null)return;
    var d=Draft{};
    d.path[0]=h;
    d.highs[0]=ts.high;
    d.n=1;
    ts.draft=d;
    return;
  }
  const d=ts.draft orelse return;
  ts.draft=null;
  if(d.n<2)return;
  // where it runs from and to
  const fromId=g.structs.at(&g.world,d.path[0][0],d.path[0][1]) orelse return;
  const end=d.path[d.n-1];
  const toId=g.structs.at(&g.world,end[0],end[1]);
  const mine=m.tileAt(g.player.pos);
  if(toId==null and !same(end,mine))return g.prog.say(txt.s.msg.tendrilNowhere,.{});
  if(toId)|j|if(j==fromId)return;
  if(!g.player.inv.take(.fragment,cost(d.n)))return g.prog.say(txt.s.msg.tendrilFragments,.{cost(d.n)});
  var t=Tendril{.from=g.structs.get(fromId).ref(),.to=if(toId)|j|g.structs.get(j).ref()else null,.n=d.n,.highs=d.highs};
  t.path=d.path;
  try ts.list.append(g.gpa,t);
}
/// one tick of every tendril: braiding, then carrying from its start to
/// its end; one whose start (or end) is gone is gone too
pub fn tick(g:*Game,dt:f32)void{
  const ts=&g.tendrils;
  var i:usize=0;
  while(i<ts.list.items.len){
    const t=&ts.list.items[i];
    const from=g.structs.where.get(t.from);
    const to=if(t.to)|r|g.structs.where.get(r)else null;
    if(from==null or (t.to!=null and to==null)){
      _=ts.list.orderedRemove(i);
      continue;
    }
    i+=1;
    if(t.fill<1){
      t.fill=@min(1,t.fill+dt/(braidPerTile*m.f(t.n)));
      continue;
    }
    if(t.cargo==null){
      t.cargo=take(g,from.?) orelse continue;
      t.s=0;
    }
    t.s=@min(1,t.s+dt*speed/m.f(t.n-1));
    if(t.s<1)continue;
    // there: taken in (else it waits at the end)
    const took=if(to)|j|g.structs.insert(&g.prog,j,t.cargo.?,1)==1 else g.player.inv.add(t.cargo.?,1)==1;
    if(took)t.cargo=null;
  }
}
/// what the structure `j` a tendril runs from lets ride it: what a click
/// would hand over, else the first thing it holds
fn take(g:*Game,j:st.Id)?items.Item{
  // the structure
  const s=g.structs.get(j);
  if(st.handOver(s))|it|return it;
  for(&s.inv.slot)|*slot|if(slot.*)|*stack|{
    const it=stack.item;
    stack.n-=1;
    if(stack.n==0)slot.*=null;
    return it;
  };
  return null;
}
/// a path laid out in the world: each tile's point over the ground and how
/// far along the path it lies (m)
const Laid=struct{
  /// the points, start to end
  at:[most]m.V3=undefined,
  /// how far along the path each lies (m)
  along:[most]f32=undefined,
  /// how many
  n:usize=0,
  /// how long the whole path is (m)
  fn len(l:*const Laid)f32{return l.along[l.n-1];}
  /// point `k`, the path's ends held past them
  fn point(l:*const Laid,k:isize)m.V3{return l.at[@intCast(@min(@max(k,0),@as(isize,@intCast(l.n-1))))];}
  /// where the path runs `s` metres along it: the Catmull-Rom curve through
  /// its points, as part.vert `plexFlowAt` lays it
  fn on(l:*const Laid,s:f32)m.V3{
    // the span it lies in
    var i:usize=0;
    for(1..l.n-1)|k|if(l.along[k]<=s){i=k;};
    // how far through that span
    const f=m.clamp01((s-l.along[i])/@max(l.along[i+1]-l.along[i],1e-4));
    const k:isize=@intCast(i);
    return m.catmullRom(l.point(k-1),l.point(k),l.point(k+1),l.point(k+2),f);
  }
};
/// the tiles `p` of a path, each floating its own of `highs` over the
/// ground, laid out in the world: each tile's centre that high (on the
/// ground, just over it), sagging toward the path's middle the higher it
/// floats (the tendril sketch's)
fn lay(g:*const Game,p:[]const Tile,highs:[]const f32)Laid{
  var l=Laid{.n=p.len};
  for(p,highs,0..)|c,high,k|{
    // how far along the path it lies (0 start .. 1 end)
    const along=m.f(k)/m.f(@max(p.len-1,1));
    const y=if(high<=0)low else high-sag*@min(high,1)*@sin(m.pi*along);
    l.at[k]=m.tileCentre(c[0],c[1],@max(g.heightAt(c[0],c[1]),0)+y);
    l.along[k]=if(k==0)0 else l.along[k-1]+m.dist(l.at[k-1],l.at[k]);
  }
  return l;
}
/// every tendril, one flow along the whole of its path as far as it is
/// braided, what rides it, and the one being drawn, faint
pub fn draw(g:*Game,out:*Parts)Allocator.Error!void{
  for(g.tendrils.list.items)|*t|{
    // its path, laid out
    const l=lay(g,t.tiles(),t.highs[0..t.n]);
    try flow(out,&l,t.highs[0..t.n],t.fill,false);
    const it=t.cargo orelse continue;
    // where along its path it rides, just over it, turning slowly as it
    // goes and fading in and out at either end (the sketch's rider)
    const at=l.on(t.s*l.len());
    const show=m.smooth(m.clamp01(t.s/rideEnds))*m.smooth(m.clamp01((1-t.s)/rideEnds));
    try out.emit(rideMesh(it),m.chain(&.{m.translate(at+m.v3(0,rideOver,0)),m.rotY(@as(f32,@floatCast(g.time))*rideTurn),m.scale3(m.splat3(rideScale)),m.translate(m.v3(0,-1,0))}),.{.phase=t.s,.glow=0.6,.fade=show});
  }
  const ts=&g.tendrils;
  if(ts.draft)|d|if(d.n>1){
    // the path swept so far, at the height it will float
    const l=lay(g,d.path[0..d.n],d.highs[0..d.n]);
    try flow(out,&l,d.highs[0..d.n],1,true);
  };
}
/// one tendril along `l`, its tiles floating `highs`, braided as far as `fill`, a
/// ghost if `ghost`: its path put as this frame's bones, then as many
/// chunks of its braid as its length needs, each flowing along the whole
fn flow(out:*Parts,l:*const Laid,highs:[]const f32,fill:f32,ghost:bool)Allocator.Error!void{
  // how high its highest tile floats (on the ground all along, it sways
  // less)
  var high:f32=0;
  for(highs)|h|high=@max(high,h);
  // its points as bones: each a point and how far along it lies
  var bones:[most]m.M4=undefined;
  for(0..l.n)|k|{
    bones[k]=m.identity;
    bones[k][0]=.{l.at[k][0],l.at[k][1],l.at[k][2],l.along[k]};
  }
  const base=try out.pose(bones[0..l.n]);
  // what bounds it: round its middle, out to its farthest point
  var mid=m.splat3(0);
  for(l.at[0..l.n])|a|mid+=a;
  mid/=m.splat3(m.f(l.n));
  var r:f32=0;
  for(l.at[0..l.n])|a|r=@max(r,m.dist(a,mid));
  // how many chunks its lights need
  const lights=3*@max(@ceil(l.len()*flowPer),1);
  const chunks:usize=@intFromFloat(@ceil(lights/flowLights));
  for(0..chunks)|c|try out.emitPath(.constellateTendrilFlow,base,@intCast(l.n),l.len(),mid,r+0.3,.{.grown=fill,.flutter=m.f(c),.tall=high,.ghost=ghost,.fade=if(ghost)0.4 else 1});
}
/// how what rides a tendril is drawn: a part as its own web, a fragment or
/// anything else as a glowing pod
fn rideMesh(it:items.Item)lib.meshlib.Id{
  return switch(it){
    .constellatePetal=>.constellatePetal,
    .constellateLeaf=>.constellateLeaf,
    .constellateBud=>.constellateBud,
    .constellateCore=>.constellateYieldCore,
    .constellateStem=>.constellateStem,
    else=>.itemPod,
  };
}
test"a tendril costs a fragment for every two tiles of it"{
  try testing.expectEqual(@as(u16,1),cost(2));
  try testing.expectEqual(@as(u16,2),cost(3));
  try testing.expectEqual(@as(u16,16),cost(most));
}
test"a tendril braids, then carries what its start holds to its end, one at a time"{
  // a fresh game, its world streamed in round the gardener
  const gpa=testing.allocator;
  var g=try Game.init(gpa,testing.io,lib.play.defaultSeed);
  defer g.deinit();
  try g.world.stream(g.focus(),2,1000);
  // a yielder holding three fragments, a heart five tiles on that takes them
  const c=m.tileAt(g.player.pos);
  try testing.expect(try g.structs.place(gpa,&g.world,c[0]+3,c[1],.yielder,0,0.1));
  try testing.expect(try g.structs.place(gpa,&g.world,c[0]+8,c[1],.heart,0,0.2));
  _=g.structs.list.items[0].inv.add(.fragment,3);
  // a tendril between them, along the row
  var t=Tendril{.from=g.structs.list.items[0].ref(),.to=g.structs.list.items[1].ref(),.n=6};
  for(0..6)|k|t.path[k]=.{c[0]+3+@as(i32,@intCast(k)),c[1]};
  try g.tendrils.list.append(gpa,t);
  // the seconds run: braided, then all three carried over
  var s:f32=0;
  while(s<30):(s+=lib.play.tickTime)try g.step();
  try testing.expectEqual(@as(u32,0),g.structs.list.items[0].inv.count(.fragment));
  try testing.expectEqual(@as(u32,3),g.structs.list.items[1].inv.count(.fragment));
  // its start gone, it is gone too
  var gone=g.structs.remove(&g.world,.of(0));
  gone.deinit(gpa);
  try g.step();
  try testing.expectEqual(@as(usize,0),g.tendrils.list.items.len);
}
