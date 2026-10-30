//! laminae: leaves with a body, folding to a midrib.
const lib=@import("../../lib.zig");
const std=lib.std;
const assert=std.debug.assert;
const Allocator=std.mem.Allocator;
const engine=lib.engine;
const m=engine.core.math;
const vertex=lib.vertex;
const color=engine.core.color;
const V3=m.V3;
const Builder=lib.meshgen.Builder;
const stride=lib.meshgen.stride;
/// half a leaf's or petal's thickness, as a share of its broadest half-width
pub const laminaThick:f32=0.055;
/// most rows a lamina may have
const maxLamina=12;
/// a lamina's cross-section, once round: the face (its cupped side) edge to
/// edge with the vein's crest at its middle, round the right edge, the
/// back, round the left edge
const faceU=[_]f32{-1,-0.5,-0.07,0,0.07,0.5,1};
const backU=[_]f32{1,0.5,0,-0.5,-1};
/// the edge's bevel: the angles (off the midplane) it is rounded over at
const bevel=[_]f32{0.9,-0.9};
const laminaRing=faceU.len+backU.len+2*bevel.len;
/// how much thinner a lamina is at its edge than along its midrib
const edgeThin:f32=0.35;
/// the vein's colour: paler than the blade it runs through
const veinPale=color.rgb(0.9,0.92,0.72);
/// a leaf or petal with a body to it: its mid-surface (row i at `spine[i]`,
/// `width[i]` out each way along `side[i]`, its edges rising `dish[i]`
/// toward `face[i]`, the side it cups to; `bow` 1 folds it along the
/// midrib, 2 cups it smoothly) given a thin thickness that rounds over at
/// the edges, a small bevel catching the light. `vein` raises a midrib along
/// the face, in the fold. Rows run base to tip (tu.y); where a row closes to
/// a point the shell closes with it, so it is watertight.
pub const Lamina=struct{
  spine:[]const V3,
  side:[]const V3,
  face:[]const V3,
  width:[]const f32,
  dish:[]const f32,
  bow:f32=2,
  /// its broadest half-width (the thickness follows it)
  broad:f32,
  /// how far the vein rises off the face, per row
  vein:?[]const f32=null,
  col:[]const color.Rgba8,
  t:f32,
  part:vertex.Part,
};
pub fn lamina(b:*Builder,l:Lamina)Allocator.Error!void{
  const rows=l.spine.len;
  const columns=laminaRing;
  assert(rows>=2 and rows<=maxLamina);
  var pts:[maxLamina][columns]V3=undefined;
  // each point's normal as the cross-section alone would have it: it orients
  // the sheet's own, and stands in where a row closes to a point
  var tpl:[maxLamina][columns]V3=undefined;
  var cs:[maxLamina][columns]color.Rgba8=undefined;
  const pale=veinPale.toRgba8(255);
  for(0..rows)|i|{
    const w=l.width[i];
    const fc=l.face[i];
    const sd=l.side[i];
    // thin everywhere, closing to nothing where the row narrows to a point
    const half=@min(laminaThick*l.broad,0.4*w);
    const mid=struct{
      fn at(lm:Lamina,index:usize,u:f32)V3{
        return lm.spine[index]+lm.side[index]*m.splat3(lm.width[index]*u)+lm.face[index]*m.splat3(lm.dish[index]*m.pow(f32,@abs(u),lm.bow));
      }
    }.at;
    var j:usize=0;
    for(faceU)|u|{
      const rise:f32=if(u!=0)0 else if(l.vein)|v|@min(v[i],0.3*w)else 0;
      pts[i][j]=mid(l,i,u)+fc*m.splat3(half*(1-edgeThin*u*u)+rise);
      tpl[i][j]=fc;
      cs[i][j]=if(rise>0)color.mix(l.col[i],pale,0.35)else l.col[i];
      j+=1;
    }
    const rim=half*(1-edgeThin);
    for([_]f32{1,-1},0..)|e,ei|{
      // round the right edge face to back, then the left edge back to face
      for(0..bevel.len)|q|{
        const a=if(ei==0)bevel[q]else bevel[bevel.len-1-q];
        const out=sd*m.splat3(e*@cos(a))+fc*m.splat3(@sin(a));
        pts[i][j]=mid(l,i,e)+out*m.splat3(rim);
        tpl[i][j]=out;
        cs[i][j]=l.col[i];
        j+=1;
      }
      if(ei==1)break;
      for(backU)|u|{
        pts[i][j]=mid(l,i,u)-fc*m.splat3(half*(1-edgeThin*u*u));
        tpl[i][j]=-fc;
        cs[i][j]=l.col[i];
        j+=1;
      }
    }
    assert(j==columns);
  }
  // normals from the shell itself, across its rows and round its section
  var ns:[maxLamina][columns]V3=undefined;
  for(0..rows)|i|for(0..columns)|j|{
    const dk=pts[@min(i+1,rows-1)][j]-pts[if(i==0)0 else i-1][j];
    const du=pts[i][(j+1)%columns]-pts[i][(j+columns-1)%columns];
    var n=m.cross(du,dk);
    if(m.len(n)<1e-12)n=tpl[i][j];
    if(m.dot(n,tpl[i][j])<0)n=-n;
    ns[i][j]=m.norm(n);
  };
  // rows and points round the section kept at this level of detail (the
  // section closes on itself: its last kept point joins back to the first)
  var kr:[maxLamina]usize=undefined;
  var kc:[columns+1]usize=undefined;
  const nr=stride(rows,b.step(),&kr);
  const nc=stride(columns+1,b.step(),&kc);
  for(0..nr-1)|ri|for(0..nc-1)|ci|{
    const r=[4]usize{kr[ri],kr[ri],kr[ri+1],kr[ri+1]};
    const c=[4]usize{kc[ci]%columns,kc[ci+1]%columns,kc[ci+1]%columns,kc[ci]%columns};
    for([2][3]usize{.{0,1,2},.{0,2,3}})|tri|{
      var p:[3]V3=undefined;
      var n=m.v3(0,0,0);
      for(tri,0..)|v,q|{
        p[q]=pts[r[v]][c[v]];
        n+=ns[r[v]][c[v]];
      }
      // front faces wind counter-clockwise seen from outside
      const order=if(m.dot(m.cross(p[1]-p[0],p[2]-p[0]),n)<0)[3]usize{tri[0],tri[2],tri[1]}else tri;
      for(order)|v|try b.put(pts[r[v]][c[v]],ns[r[v]][c[v]],cs[r[v]][c[v]],l.t,m.ratio(r[v],rows-1),l.part);
    }
  };
}
