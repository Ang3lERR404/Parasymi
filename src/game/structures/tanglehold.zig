//! TANGLEHOLD: plain storage of both lineages, taking the sap cache's place
//! once the unforming has taken it, and holding twice as much. Takes
//! anything, gives anything; what it holds hangs in its sac of both saps,
//! turning slowly in a tangle round its heart.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// what can be held: item kinds and stacks of them
const items=lib.items;
/// the structures registry: `Def`, `Structure`, the hooks' context
const st=lib.structures;
/// the tools a bulb icon is drawn with
const iconKit=lib.icon;
/// every player-facing string
const txt=lib.txt;
/// what the gardener has understood
const prog=lib.progression;
/// the HUD's shared sizes and colours
const style=lib.style;
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// all the maths: vectors, matrices, easing
const m=lib.engine.core.math;
/// the scene's list of moving parts it adds to each frame
const Parts=lib.parts.Parts;
/// the hold's mesh: where its sac's heart is, and how big
const mesh=lib.tangleholdMesh;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.bellyLump};
/// what a tanglehold is: of the convergent lineage, one tile across, a
/// store of 32 slots (twice a sap cache's), grown in six seconds, swaying
/// gently and standing about a tile tall
pub const def:st.Def=.{.item=.tanglehold,.lineage=.convergent,.size=1,.mesh=.tanglehold,.store=true,.room=32,.sap=0.3,.sway=0.4,.tall=1.0,.grow=6};
/// how fast the tangle of what it holds turns round its heart (turns a second)
const turnRate:f32=0.08;
/// how far out of its heart what it holds hangs, at most (a share of the sac)
const tangleOut:f32=0.62;
/// how far each thing bobs (m), and how fast (radians a second)
const bobAmount:f32=0.012;
/// (how fast)
const bobRate:f32=0.6;
/// the size of a lump holding one thing, and how much larger a full stack is
const lumpR:f32=0.045;
/// (how much larger, full)
const lumpGrow:f32=0.035;
/// the stack at which a lump is its largest
const lumpFull:f32=50;
/// how brightly what it holds glows in its sac
const glow:f32=0.25;
/// it wants anything, as much as it has room for (dispatch caps it at its slots)
pub fn wants(s:*const st.Structure,_:*const prog.Progression,item:items.Item)u32{
  // room left: what fits in its stacks of this item, and its empty slots
  var room:u32=0;
  for(s.inv.slot[0..def.room])|slot|{
    if(slot)|it|{
      if(it.item==item)room+=items.stack-it.n;
    }else room+=items.stack;
  }
  return room;
}
/// what it gives first: the newest stack, from its last slot back
pub fn output(s:*const st.Structure)?items.Item{
  // the slot being looked at, walking back from the last
  var k:usize=def.room;
  while(k>0){
    k-=1;
    if(s.inv.slot[k])|it|return it.item;
  }
  return null;
}
/// it gives anything it holds.
pub fn gives(s:*const st.Structure,item:items.Item)bool{return s.inv.count(item)>0;}
/// what it holds hangs in its sac, one glowing lump a stack (larger for a
/// larger stack), spread through it on a slow spiral (each its own place,
/// out from the heart and up and down), turning slowly, bobbing
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  if(s.grown<1)return;
  // its frame in the world, and how many stacks it holds
  const base=s.place(ctr);
  const n=s.inv.used();
  // which stack is being drawn
  var k:usize=0;
  for(s.inv.slot[0..def.room])|slot|{
    const it=slot orelse continue;
    // its place in the tangle: up the sac on a golden spiral, out from the heart
    const u=(m.f(k)+0.5)/m.f(@max(n,1));
    const y=(u*2-1)*0.7;
    const out_=@sqrt(@max(1-y*y,0))*tangleOut*(if(n==1)@as(f32,0)else 1);
    const a=m.f(k)*m.goldenAngle+tf*turnRate*m.tau+s.seed*6;
    const at=mesh.heart+m.v3(@cos(a)*mesh.sacR[0]*out_,y*mesh.sacR[1]*tangleOut+bobAmount*@sin(tf*bobRate+m.f(k)*2),@sin(a)*mesh.sacR[2]*out_);
    // its size: larger the fuller it is
    const r=lumpR+lumpGrow*m.clamp01(m.f(it.n)/lumpFull);
    try s.emitLump(out,base,at,r,it.item,glow);
    k+=1;
  }
}
/// its line in the panel: how many of its slots are taken
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  _=try d.print(x,y,style.textBody,style.dim,txt.s.describe.hold,.{s.inv.used(),def.room});
}
/// its bulb: a sac of both saps in a cage of staves, motes in it
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // the sac's middle
  const sac:iconKit.P=.{0,0.55};
  try ic.stem(.{.{0,iconKit.topAt},.{0.03,0.2},.{-0.02,0.3},.{sac[0],sac[1]-0.22}},0.07,iconKit.stemCol);
  try ic.glow(sac,0.36,iconGlow);
  try ic.bud(sac,0.22,iconSac,0.7);
  // what it holds, turning in it
  for(0..3)|i|{
    // this mote's place, turning
    const a=ic.t*0.6+m.f(i)*2.1+ic.phase*5;
    try ic.bud(.{sac[0]+0.1*@cos(a),sac[1]+0.08*@sin(a*1.3)},0.04,iconMote,0.8);
  }
  for(cage)|sx|try ic.stem(.{.{0,sac[1]-0.24},.{0.3*sx,sac[1]-0.1},.{0.3*sx,sac[1]+0.14},.{0,sac[1]+0.26}},0.03,iconStave);
  try ic.leaf(.{0,sac[1]+0.26},m.halfPi,0.14,0.05,iconLeaf,1);
  try ic.coat(col);
}
/// its cage's staves in the icon, either side
const cage=[_]f32{-1,-0.45,0.45,1};
/// the icon's sac: violet between the two saps
const iconSac:Color=.{170,130,230,220};
/// its glow
const iconGlow:Color=.{190,150,255,80};
/// what it holds: pale gold motes
const iconMote:Color=.{255,225,160,255};
/// its staves: pale lilac
const iconStave:Color=.{205,190,235,255};
/// its crown leaf: green
const iconLeaf:Color=.{110,170,80,255};
test"a tanglehold wants only what fits in its own slots"{
  // a blank hold
  var s=st.blank(.tanglehold);
  try std.testing.expectEqual(@as(u32,def.room)*items.stack,wants(&s,undefined,.grit));
  // every slot full of grit: no more grit, nor anything else
  for(s.inv.slot[0..def.room])|*slot|slot.*=.{.item=.grit,.n=items.stack};
  try std.testing.expectEqual(@as(u32,0),wants(&s,undefined,.grit));
  try std.testing.expectEqual(@as(u32,0),wants(&s,undefined,.fibre));
}
