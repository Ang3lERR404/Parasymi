//! DRIFT FLOWER: a flower of both lineages with no stem, pulled from the
//! air beside a polyp and put down by the wolf as a floating light. It
//! drifts in place, glowing softly, wherever it is put. Once the unforming
//! has passed, one put down within `graftTiles` of an evolved arsthraxia
//! is taken into it instead: it grows on it as a stemless branch, and the
//! arsthraxia studies `arsthraxia.branchBoost` faster for each it bears.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the drawing calls may fail with
const Allocator=std.mem.Allocator;
/// all the maths: vectors, matrices
const m=lib.engine.core.math;
/// the structures registry: `Def`, `Structure`, the hooks' context
const st=lib.structures;
/// the tools a bulb icon is drawn with
const iconKit=lib.icon;
/// the scene's list of moving parts it is drawn into
const Parts=lib.parts.Parts;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// what it is: floating at a flower's height over its tile, there at
/// once, drawing itself (it drifts in place)
pub const def:st.Def=.{.item=.driftFlower,.lineage=.convergent,.size=1,.mesh=.driftFlower,.floating=true,.hover=hover,.bare=true};
/// how high it floats
const hover:f32=1.1;
/// how far (tiles, between footprints) from an evolved arsthraxia it is
/// taken into it as a branch
pub const graftTiles:i32=2;
/// how far it drifts off its point, and how fast
const drift:f32=0.12;
/// (radians a second its drift turns)
const driftRate:f32=0.35;
/// its light: warm rose
const lightCol=m.V3{1.0,0.62,0.82};
/// how far its light reaches, tiles
const lightReach:f32=4;
/// how bright its light is
const lightStrength:f32=1.6;
/// once the unforming has passed, an evolved arsthraxia near enough takes
/// it in as a branch (it is gone from here); else it only drifts. Never busy.
pub fn tick(ctx:st.Ctx,i:st.Id,_:f32)bool{
  if(!ctx.g.done.contains(.unforming))return false;
  // the flower, and where it floats
  const self=ctx.ss.get(i);
  const here=m.Vice(i32,2){self.x,self.y};
  for(ctx.ss.list.items,0..)|*o,k|{
    if(o.kind()!=.arsthraxia or o.grown<1)continue;
    // how far off the arsthraxia is (between footprints)
    const n:i32=o.def().size;
    const gx=@max(o.x-here[0]-1,here[0]-(o.x+n),0);
    const gy=@max(o.y-here[1]-1,here[1]-(o.y+n),0);
    if(@max(gx,gy)>graftTiles)continue;
    // (only an evolved one takes it: it answers `done`)
    if(ctx.ss.send(ctx,.of(k),.graft)!=.done)continue;
    // taken in: gone from here at the end of the tick
    ctx.ss.get(i).fade=1;
    return false;
  }
  return false;
}
/// it, drifting in place over its point, slowly turning, and its light
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // its drift now
  const a=tf*driftRate+s.seed*m.tau;
  const at=ctr+m.v3(drift*@cos(a),hover+drift*0.8*@sin(a*1.7),drift*@sin(a*1.3));
  try out.emit(.driftFlower,m.chain(&.{m.translate(at),m.rotY(tf*0.2+s.seed*m.tau),m.rotX(0.2*@sin(tf*0.5+s.seed*7))}),.{.phase=s.seed,.glow=0.5});
  try out.light(at,lightCol*m.splat3(lightStrength),lightReach);
}
/// its bulb: a flower of both, glowing, drifting
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // where it drifts now
  const at:iconKit.P=.{0.05*@sin(ic.t*0.7),0.55+0.05*@sin(ic.t*1.1)};
  try ic.glow(at,0.38,iconGlow);
  for(0..6)|i|try ic.leaf(at,m.halfPi+m.ratio(i,6)*m.tau,0.24,0.12,iconPetal,1);
  try ic.bud(at,0.09,iconHeart,0.8);
  try ic.coat(col);
}
/// the warm rose of its petals
const iconPetal:Color=.{245,150,200,255};
/// the amber bead at its heart
const iconHeart:Color=.{255,200,110,255};
/// its soft glow
const iconGlow:Color=.{255,190,225,80};
test"after the unforming, a drift flower put by an evolved arsthraxia becomes its branch; one put elsewhere stays a light"{
  // the test harness, its allocator, the world and its ground
  const testing=std.testing;
  const gpa=testing.allocator;
  var w=lib.world.World.init(gpa,5);
  defer w.deinit();
  _=try st.bench.ground(&w,.{.width=16,.depth=16});
  // no plants, the structures, and what the gardener understands
  var plants:lib.plants.Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:lib.progression.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,2,2,.arsthraxia,0,0));
  try testing.expect(try ss.place(gpa,&w,5,3,.driftFlower,0,0));
  try testing.expect(try ss.place(gpa,&w,13,13,.driftFlower,0,0));
  // before the unforming: both only drift
  try st.bench.run(&ss,&w,&plants,&g,0.5);
  try testing.expectEqual(@as(usize,3),ss.list.items.len);
  // the unforming passes, and the arsthraxia evolves
  g.done.insert(.unforming);
  _=ss.send(.{.gpa=gpa,.w=&w,.plants=&plants,.g=&g,.ss=&ss},ss.at(&w,2,2).?,.unform);
  try st.bench.run(&ss,&w,&plants,&g,0.5);
  // the near one is its branch now; the far one still drifts
  try testing.expectEqual(@as(usize,2),ss.list.items.len);
  try testing.expectEqual(@as(u16,1),ss.get(ss.at(&w,2,2).?).state.arsthraxia.branches);
  try testing.expect(ss.floaterAt(13,13)!=null);
}
