//! flowers, buds and leaves set along a path.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const engine=lib.engine;
const m=engine.core.math;
const Rng=engine.core.rng.Rng;
const species=lib.species;
const color=engine.core.color;
const V3=m.V3;
const Builder=lib.meshgen.Builder;
const blade=lib.meshgen.blades.blade;
const ellipsoid=lib.meshgen.ellipsoid;
const petal=lib.meshgen.petals.petal;
const stamens=lib.meshgen.petals.stamens;
/// what a bloom sits on: a calyx of skin with its sepals folded back, or a
/// bead of resin sap (this colour) held up in a cup of sepals
pub const Calyx=union(enum){skin,resin:color.Rgba8};
/// how many sepals cup a bloom's bead of resin
const beadSepals=5;
/// a bloom at `top` heading along `axis`, `sc` the size of the species'
/// own: a calyx at the tip (`cx`), and two overlapping whorls of petals
/// rising from its crown into a cup.
pub fn flower(b:*Builder,g:species.Genome,top:V3,axis:V3,sc:f32,spin:f32,t:f32,cx:Calyx)Allocator.Error!void{
  const calyx=(g.bloomR*0.12+g.stemR*0.6)*sc;
  var heart=top+axis*m.splat3(calyx*0.5);
  switch(cx){
    .skin=>{
      try ellipsoid(b,.{
        .center=top+axis*m.splat3(calyx*0.4),.radii=m.v3(calyx,calyx*0.85,calyx),
        .col=g.stemCol.toRgba8(255),.part=.stem,.rings=6,.segs=8,.t=t,
      });
      for(0..4)|i|{
        const a=(m.f(i)+0.5)/4*m.tau+spin;
        try blade(b,top,m.norm(m.v3(@cos(a),-0.1,@sin(a))),g.bloomR*0.55*sc,g.bloomR*0.22*sc,0.5,color.shade(g.leafCol,0.55),g.leafCol.toRgba8(255),t-0.03,.leaf);
      }
    },
    .resin=>|sap|{
      // the bead: dense at its base, thin at its crown (tu.y, the resin
      // shading reads it), the sepals cupped up round its lower half
      const r=calyx*1.15;
      const c=top+axis*m.splat3(r*0.8);
      const s=b.mark();
      try ellipsoid(b,.{.center=c,.radii=m.v3(r,r*1.12,r),.col=sap,.part=.resin,.rings=8,.segs=10,.t=t});
      for(b.v.items[s..])|*v|v.tu[1]=m.clamp01(m.dot(v.pos-c,axis)/(2*r*1.12)+0.5);
      for(0..beadSepals)|i|{
        const a=(m.f(i)+0.5)/beadSepals*m.tau+spin;
        const out=m.v3(@cos(a),0,@sin(a));
        try petal(b,.{
          .base=top+out*m.splat3(r*0.3),.out=out,.len=r*1.9,.width=r*0.85,
          .rise=0.95,.flare=0.35,.cup=0.55,
          .col=color.shade(g.leafCol,0.55),.tip=g.leafCol.toRgba8(255),.t=t-0.03,.part=.leaf,
        });
      }
      heart=c+axis*m.splat3(r*0.9);
    },
  }
  // broad outer petals opening out, a smaller inner ring standing more
  // upright between them
  const inner=@max(g.petals/2,3);
  for(0..g.petals+inner)|i|{
    const outer=i<g.petals;
    const ang=if(outer)m.ratio(i,g.petals)*m.tau else(m.f(i-g.petals)+0.5)/m.f(inner)*m.tau;
    try petal(b,.{
      .base=heart,.out=m.v3(@cos(ang+spin*0.37),0,@sin(ang+spin*0.37)),
      .len=g.bloomR*sc*(if(outer)@as(f32,1)else 0.72),
      .width=g.bloomR*sc*(if(outer)@as(f32,0.62)else 0.5),
      .rise=if(outer)0.8 else 1.2,.flare=if(outer)0.95 else 0.55,.cup=if(outer)0.35 else 0.5,
      .col=color.shade(g.bloomCol,0.8),.tip=g.bloomCol.toRgba8(255),.t=t,
    });
  }
  // stamens standing up out of the cup
  try stamens(b,.{
    .heart=heart,.axis=axis,.n=@max(g.petals,5),
    .len=g.bloomR*sc*0.55,.r=g.bloomR*sc*0.035,.anther=g.bloomR*sc*0.2,
    .lean=0.3,.arch=0.6,.col=filament(g),.spin=spin,.t=t,.seed=@as(u32,@bitCast(spin)),
  });
}
/// a flower's filaments: its bloom's colour paled almost to white
pub fn filament(g:species.Genome)color.Rgba8{
  return color.mix(g.bloomCol.toRgba8(255),color.rgb(1,0.97,0.9).toRgba8(255),0.6);
}
/// a closed bud at `top`: a calyx, sepals clasping up around it, and the
/// petals folded over one another into a teardrop round a coloured heart.
pub fn bud(b:*Builder,g:species.Genome,top:V3,axis:V3,sc:f32,spin:f32,t:f32)Allocator.Error!void{
  const calyx=(g.bloomR*0.12+g.stemR*0.6)*sc;
  const len=g.bloomR*0.6*sc;
  try ellipsoid(b,.{
    .center=top+axis*m.splat3(calyx*0.4),.radii=m.v3(calyx,calyx*0.85,calyx),
    .col=g.stemCol.toRgba8(255),.part=.stem,.rings=6,.segs=8,.t=t,
  });
  const heart=top+axis*m.splat3(calyx*0.5);
  try ellipsoid(b,.{
    .center=heart+axis*m.splat3(len*0.42),.radii=m.v3(len*0.22,len*0.45,len*0.22),
    .col=color.shade(g.bloomCol,0.75),.part=.bloom,.rings=6,.segs=8,.t=t,
  });
  const n=@max(g.petals/2+2,4);
  for(0..n)|i|{
    const a=m.ratio(i,n)*m.tau+spin;
    try petal(b,.{
      .base=heart,.out=m.v3(@cos(a),0,@sin(a)),
      .len=len,.width=len*0.5,
      // past upright by the tip: the petals close over the heart
      .rise=1.3,.flare=-0.55,.cup=0.7,
      .col=color.shade(g.bloomCol,0.7),.tip=g.bloomCol.toRgba8(255),.t=t,
    });
  }
  for(0..3)|i|{
    const a=(m.f(i)+0.5)/3*m.tau+spin;
    try blade(b,top,m.norm(m.v3(@cos(a),1.5,@sin(a))),len*0.7,len*0.22,0.05,color.shade(g.leafCol,0.55),g.leafCol.toRgba8(255),t-0.03,.leaf);
  }
}
/// `n` small leaves grown along a vine between fractions `k0`..`k1` of
/// `path`: turning around it leaf by leaf, lifting toward the light, smaller
/// toward the tip. `t0`..`t1` is the vine's tu.x over its length.
pub fn leavesAlong(b:*Builder,path:[]const V3,n:u32,len:f32,width:f32,k0:f32,k1:f32,t0:f32,t1:f32,col:color.Rgba8,tip:color.Rgba8,seed:u64)Allocator.Error!void{
  var rng=Rng.init(seed);
  for(0..n)|i|{
    const k=m.lerp(k0,k1,(m.f(i)+0.5)/m.f(n));
    try leafAt(b,path,k,i,len,width,t0,t1,col,tip,seed,&rng);
  }
}
/// the `i`th of `leavesAlong`'s leaves, `k` along `path` (`rng` its draws,
/// in order): one at a time, for a piece grown on its own (gfx/growth.zig).
pub fn leafAt(b:*Builder,path:[]const V3,k:f32,i:usize,len:f32,width:f32,t0:f32,t1:f32,col:color.Rgba8,tip:color.Rgba8,seed:u64,rng:*Rng)Allocator.Error!void{
  const at=m.alongPath(path,k);
  const tan=m.norm(m.alongPath(path,@min(k+0.03,1))-m.alongPath(path,@max(k-0.03,0)));
  const ref=if(@abs(tan[1])>0.9)m.v3(1,0,0)else m.v3(0,1,0);
  const s1=m.norm(m.cross(tan,ref));
  const s2=m.cross(tan,s1);
  const a=m.f(i)*2.4+rng.range(-0.3,0.3)+m.f(seed%7);
  var out=s1*m.splat3(@cos(a))+s2*m.splat3(@sin(a))+m.v3(0,0.5,0)+tan*m.splat3(0.3);
  // a blade needs some sideways lean to find its width
  out[1]=m.clamp(out[1],-0.6,0.7);
  out=m.norm(out);
  const l=len*m.lerp(1,0.6,k)*rng.range(0.85,1.15);
  try blade(b,at,out,l,width*m.lerp(1,0.7,k),0.35,col,tip,m.lerp(t0,t1,k),.leaf);
}
