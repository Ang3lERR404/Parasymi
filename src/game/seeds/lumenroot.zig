//! LUMENROOT seed: a leafy sprout opening a cyan flower, motes of mana
//! running from it to the little sprouts beside it (it shares with kin).
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const m=lib.engine.core.math;
const items=lib.items;
const iconKit=lib.icon;
const Color=lib.engine.ui.draw.Color;
pub const item:items.Item=.seedLumenroot;
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  const top:iconKit.P=.{0,0.66};
  try ic.stem(.{.{0,iconKit.topAt},.{-0.06,0.3},.{0.06,0.48},top},0.1,stem);
  try ic.leaf(.{0,0.3},0.5,0.32,0.16,iconKit.sprout,0.9);
  try ic.leaf(.{0,0.38},m.pi-0.5,0.3,0.15,iconKit.sprout,0.9);
  // the neighbours it feeds, and the mana running out to them
  for([_]f32{-1,1},0..)|sx,i|{
    const kin:iconKit.P=.{0.72*sx,-0.32};
    try ic.stem(.{.{kin[0],kin[1]-0.18},.{kin[0],kin[1]-0.08},.{kin[0]+0.02*sx,kin[1]},kin},0.06,stem);
    try ic.leaf(kin,if(sx<0)m.pi-0.7 else 0.7,0.18,0.11,iconKit.sprout,0.9);
    const run=[4]iconKit.P{top,.{0.3*sx,0.85},.{0.7*sx,0.3},kin};
    const k=@mod(ic.t*runAmount+ic.phase+m.f(i)*0.5,1);
    try ic.bud(iconKit.curve(run,k),0.06,mote,@sin(k*m.pi));
  }
  try ic.glow(top,0.3,glow);
  for(0..petals)|i|{
    try ic.leaf(top,m.halfPi+m.tau*m.ratio(i,petals),0.2,0.13,petal,1);
  }
  try ic.stamens(top,m.halfPi,0.75,5,0.17,filament);
  try ic.bud(top,0.06,core,1);
  try ic.coat(col);
}
const petals=6;
/// motes out to the neighbours a second
const runAmount:f32=0.4;
const stem:Color=.{70,140,95,255};
const petal:Color=.{140,240,255,255};
const core:Color=.{230,255,250,255};
const filament:Color=.{220,250,245,255};
const mote:Color=.{160,250,240,255};
const glow:Color=.{140,240,255,80};
