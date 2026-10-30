//! chunk -> smooth ground mesh. Each tile is a fan of four triangles: its
//! centre at the tile's own height (where everything on it stands), its
//! corners shared with its neighbours (the average of the tiles that meet
//! there), so the ground rolls from one terrace to the next with no walls
//! or hard ramps, and its colour blends across tile borders. The detail on
//! top (grass on every tile but soil, clods and stones on soil) is not meshed here: each such
//! tile gets one `DetailTile` record and the GPU grows the detail from it.
//! Border neighbours come from the generator directly, so a chunk can be
//! meshed without its neighbours being loaded.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// all the maths: vectors, normals, conversions
const m=lib.engine.core.math;
/// the allocator type every meshing call may fail with
const Allocator=std.mem.Allocator;
/// one chunk: its tiles' heights, kinds and ley
const ck=lib.ck;
/// the world generator, for tiles beyond the chunk and the ley's ceiling
const gen=lib.gen;
/// hashes for each tile's colour jitter
const rng=lib.engine.core.rng;
/// colour types and conversions
const color=lib.engine.core.color;
/// the garden's vertex layouts
const vertex=lib.vertex;
/// one ground vertex
const TV=vertex.Terrain;
/// one tile's detail record, which the GPU grows grass or stones from
const DetailTile=vertex.DetailTile;
/// a point or direction in 3D
const V3=m.V3;
/// makes a point from three numbers
const v3=m.v3;
/// the colour of ground of each kind: soil brown, moss green, stone grey, ley violet
fn baseColor(k:ck.Kind)color.Rgb{
  return switch(k){
    .soil=>color.rgb(0.36,0.27,0.19),
    .moss=>color.rgb(0.20,0.36,0.20),
    .stone=>color.rgb(0.42,0.42,0.46),
    .ley=>color.rgb(0.30,0.24,0.45),
  };
}
/// how many grass blades grow on a tile of each kind (detail.vert grows them)
fn blades(k:ck.Kind)u32{
  return switch(k){
    .soil=>0,
    .moss=>8,
    .ley=>6,
    .stone=>2,
  };
}
/// each tile's colour varies by `jitterAmount` about `jitterMin` of its kind's
const jitterMin:f32=0.9;
/// how widely a tile's colour wanders (a share of its kind's colour)
const jitterAmount:f32=0.2;
/// a tile is a fan of four triangles
const vertsPerTile=4*3;
/// info.z of the ground's top surface (terrain.vert/frag read it as 1.0)
const topSurface:u8=255;
/// the tiles around a chunk, one ring beyond it, read once
const Ring=struct{
  /// how many tiles across the ring is: the chunk and one each side
  const w=ck.sizeTiles+2;
  /// each tile's height
  h:[w*w]f32=undefined,
  /// each tile's kind
  kind:[w*w]ck.Kind=undefined,
  /// each tile's colour, jittered
  col:[w*w]color.Rgb=undefined,
  /// ley intensity 0..1
  ley:[w*w]f32=undefined,
  /// where tile (lx, ly) sits in the ring (-1 .. sizeTiles each way)
  fn at(_:*const Ring,lx:i32,ly:i32)usize{return@intCast((ly+1)*w+(lx+1));}
};
/// reads every tile of the ring around chunk `c`: inside from the chunk,
/// beyond from the generator; each tile's colour jittered by its place
fn fill(r:*Ring,seed:u64,c:*const ck.Chunk)void{
  // the chunk's corner in world tiles
  const ox=c.originX();
  const oy=c.originY();
  // the ring's row being read
  var ly:i32=-1;
  while(ly<=ck.sizeTiles):(ly+=1){
    // the ring's column being read
    var lx:i32=-1;
    while(lx<=ck.sizeTiles):(lx+=1){
      // this tile in world tiles
      const wx=ox+lx;
      const wy=oy+ly;
      // whether it lies inside the chunk, and where it sits in the ring
      const inside=lx>=0 and lx<ck.sizeTiles and ly>=0 and ly<ck.sizeTiles;
      const i=r.at(lx,ly);
      if(inside){
        // its index in the chunk
        const t:usize=@intCast(ly*ck.sizeTiles+lx);
        r.h[i]=c.height[t];
        r.kind[i]=c.kind[t];
        r.ley[i]=m.clamp01(c.leyCap[t]/gen.leyMax);
      }else{
        // the generator's sample of the tile beyond
        const s=gen.sample(seed,wx,wy);
        r.h[i]=s.height;
        r.kind[i]=s.kind;
        r.ley[i]=m.clamp01(s.ley/gen.leyMax);
      }
      // how far this tile's colour is jittered, and its kind's colour
      const jitter=jitterMin+jitterAmount*rng.unit(rng.hash2(seed^0xC0101,wx,wy));
      const b=baseColor(r.kind[i]);
      r.col[i]=color.rgb(b.r*jitter,b.g*jitter,b.b*jitter);
    }
  }
}
/// a point of the half-tile grid (chunk-local, tile lx spans 2lx..2lx+2,
/// its centre at 2lx+1): shared by the tiles that meet there
fn point(r:*const Ring,px:i32,py:i32)Shared{
  // the tiles meeting at this point, and how many
  var ts:[4]usize=undefined;
  var n:usize=0;
  // the tiles either side of this point, across and down
  const xs=[2]i32{@divFloor(px-1,2),@divFloor(px,2)};
  const ys=[2]i32{@divFloor(py-1,2),@divFloor(py,2)};
  // an odd coordinate is inside one tile, an even one between two
  // how many tiles meet across, and down
  const nx:usize=if(@mod(px,2)==1)1 else 2;
  const ny:usize=if(@mod(py,2)==1)1 else 2;
  for(0..ny)|j|for(0..nx)|i|{
    // the tile this one is, across and down
    const tx=if(nx==1)@divFloor(px,2)else xs[i];
    const ty=if(ny==1)@divFloor(py,2)else ys[j];
    ts[n]=r.at(@max(-1,@min(ck.sizeTiles,tx)),@max(-1,@min(ck.sizeTiles,ty)));
    n+=1;
  };
  return shared(r,ts[0..n]);
}
/// one point the tiles meeting there share: its height, colour and ley
const Shared=struct{
  /// the meeting tiles' average height
  h:f32,
  /// their average colour
  col:color.Rgb,
  /// their average ley intensity, 0..1
  ley:f32,
};
/// a shared point among the tiles `ts`: their average height, colour and ley
fn shared(r:*const Ring,ts:[]const usize)Shared{
  // running sums: height, red, green, blue and ley
  var h:f32=0;
  var cr:f32=0;
  var cg:f32=0;
  var cb:f32=0;
  var ley:f32=0;
  // how many tiles share it
  const n=m.f(ts.len);
  for(ts)|t|{
    h+=r.h[t];
    cr+=r.col[t].r;
    cg+=r.col[t].g;
    cb+=r.col[t].b;
    ley+=r.ley[t];
  }
  return.{.h=h/n,.col=color.rgb(cr/n,cg/n,cb/n),.ley=ley/n};
}
/// appends one ground vertex: where it is, its normal, colour and info
fn put(out:*std.ArrayList(TV),gpa:Allocator,p:V3,n:V3,c:color.Rgba8,info:[4]u8)Allocator.Error!void{
  try out.append(gpa,.{.pos=.{p[0],p[1],p[2]},.nrm=.{n[0],n[1],n[2]},.col=c,.info=info});
}
/// every shared point of a chunk's half-tile grid (one point beyond it on
/// each side, for slopes at its border), worked out once
const Grid=struct{
  /// how many points across the grid is: the chunk's half-tiles and two beyond each side
  const w=2*ck.sizeTiles+5;
  /// each point, row by row
  p:[w*w]Shared=undefined,
  /// works out every point from the ring
  fn fill(g:*Grid,r:*const Ring)void{
    for(0..w)|y|for(0..w)|x|{
      g.p[y*w+x]=point(r,@as(i32,@intCast(x))-2,@as(i32,@intCast(y))-2);
    };
  }
  /// the point at half-tile (px, py), from -2 out
  fn at(g:*const Grid,px:i32,py:i32)Shared{return g.p[@intCast((py+2)*w+(px+2))];}
};
/// mesh a chunk's ground into `out`, and into `detail` one record per tile
/// that carries grass, clods or stones (the GPU grows those from it).
pub fn build(gpa:Allocator,seed:u64,c:*const ck.Chunk,out:*std.ArrayList(TV),detail:*std.ArrayList(DetailTile))Allocator.Error!void{
  out.clearRetainingCapacity();
  detail.clearRetainingCapacity();
  // room for the whole chunk up front: no regrowing mid-build
  try out.ensureTotalCapacity(gpa,ck.tileCount*vertsPerTile);
  try detail.ensureTotalCapacity(gpa,ck.tileCount);
  // the ring of tiles around the chunk, read once
  var r:Ring=.{};
  fill(&r,seed,c);
  // the shared points, too big for the stack, made once and freed at the end
  const grid=try gpa.create(Grid);
  defer gpa.destroy(grid);
  grid.fill(&r);
  // the chunk's corner in world tiles
  const ox=c.originX();
  const oy=c.originY();
  for(0..ck.sizeTiles)|uy|for(0..ck.sizeTiles)|ux|{
    // this tile within the chunk
    const lx:i32=@intCast(ux);
    const ly:i32=@intCast(uy);
    // its place in the ring and in the chunk
    const i=r.at(lx,ly);
    const t=uy*ck.sizeTiles+ux;
    // its kind
    const k=r.kind[i];
    // its place in world tiles
    const wx=ox+lx;
    const wy=oy+ly;
    // its ley as a byte, and the info every vertex of it carries
    const ley=m.unorm8(c.leyCap[t]/gen.leyMax);
    const info:[4]u8=.{@intFromEnum(k),ley,topSurface,0};
    // the tile: a fan of four triangles from its centre (at the tile's own
    // height) to its corners (shared with its neighbours), lit by the
    // ground's smooth slope.
    // the tile's corner and centre points: heights, colours, normals and ley
    var gh:[3][3]f32=undefined;
    var gc:[3][3]color.Rgba8=undefined;
    var gn:[3][3]V3=undefined;
    var gl:[3][3]u8=undefined;
    for([_][2]usize{.{0,0},.{2,0},.{0,2},.{2,2},.{1,1}})|g|{
      // which corner or centre this is, across and down
      const gx=g[0];
      const gy=g[1];
      // its place on the half-tile grid
      const px=2*lx+@as(i32,@intCast(gx));
      const py=2*ly+@as(i32,@intCast(gy));
      // the shared point there
      const s=grid.at(px,py);
      // ley fades across tile borders like the colour does
      gl[gy][gx]=m.unorm8(s.ley);
      gh[gy][gx]=s.h;
      gc[gy][gx]=s.col.toRgba8(255);
      // central differences over half-tile steps
      // the ground's slope across and down there
      const dx=grid.at(px+1,py).h-grid.at(px-1,py).h;
      const dz=grid.at(px,py+1).h-grid.at(px,py-1).h;
      gn[gy][gx]=m.norm(v3(-dx,1,-dz));
    }
    // the tile's corner in world space
    const x0=m.f(wx);
    const z0=m.f(wy);
    // its corners, round the fan
    const corners=[_][2]usize{.{0,0},.{0,2},.{2,2},.{2,0}};
    for(0..4)|j|{
      for([_][2]usize{.{1,1},corners[j],corners[(j+1)%4]})|cn|{
        // this vertex: the centre or a corner, at its height
        const at=v3(x0+0.5*m.f(cn[0]),gh[cn[1]][cn[0]],z0+0.5*m.f(cn[1]));
        try put(out,gpa,at,gn[cn[1]][cn[0]],gc[cn[1]][cn[0]],.{info[0],gl[cn[1]][cn[0]],info[2],info[3]});
      }
    }
    // the detail on it (grass, or clods and stones on soil) is grown on the
    // GPU from this one record (shaders/detail.vert)
    // how many blades it grows
    const n=blades(k);
    if(n==0 and k!=.soil)continue;
    try detail.append(gpa,.{
      .at=.{x0,gh[1][1],z0},
      .corners=.{gh[0][0],gh[2][0],gh[2][2],gh[0][2]},
      .col=r.col[i].toRgba8(255),
      .info=.{@intFromEnum(k),ley,@intCast(n),0},
    });
  };
}
