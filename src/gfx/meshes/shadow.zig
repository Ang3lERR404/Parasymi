//! mesh: SHADOW. a flat unit disc on the ground (y = 0), part `.shadow`,
//! tu.x its radial fraction so the shader can soften its edge. Laid under
//! things that float, so they read as hanging in the air.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const engine=lib.engine;
const m=engine.core.math;
const mg=lib.meshgen;
const color=engine.core.color;
const rings=4;
const stepCount=16;
pub fn build(b:*mg.Builder)Allocator.Error!void{
  const r=rings+1;
  const c=stepCount+1;
  var pts:[r*c]m.V3=undefined;
  var ns:[r*c]m.V3=undefined;
  var cs:[r*c]color.Rgba8=undefined;
  var us:[r*c]f32=undefined;
  for(0..r)|i|for(0..c)|j|{
    const k=m.ratio(i,rings);
    const a=m.ratio(j,stepCount)*m.tau;
    pts[i*c+j]=m.v3(@cos(a)*k,0,@sin(a)*k);
    ns[i*c+j]=m.v3(0,1,0);
    cs[i*c+j]=color.black.toRgba8(255);
    us[i*c+j]=k;
  };
  // tu.x carries the radial fraction (patch writes `us` to tu.y): move it over
  const start=b.mark();
  try mg.patch(b,r,c,&pts,&ns,&cs,&us,0,.shadow);
  for(b.v.items[start..])|*v|v.tu=.{v.tu[1],0};
}
