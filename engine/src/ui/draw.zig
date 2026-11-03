//! immediate-mode 2D batch in pixel coordinates, rebuilt every frame.
//! Nothing here is a box: every shape is an animated distance field evaluated
//! in shaders/ui.frag (vine trellis panels, hanging husk slots, leafy stem
//! bars, seed pods, glows), and glyph bitmaps travel in the vertex stream, so
//! no textures are needed. What grows (a trellis) grows from the frame it is
//! first drawn in: `grown` keeps when each was first seen.
/// the standard library
const std=@import("std");
/// the engine's maths: clamp, rounding, casts
const m=@import("../core/math.zig");
/// formats into a fixed buffer
const bufPrint=std.fmt.bufPrint;
/// the allocator type the batch grows through
const Allocator=std.mem.Allocator;
/// the glyph bitmaps text is drawn with
const font=@import("font.zig");
/// runtime templates, filled for `print`
const ctext=@import("../core/text.zig");
/// one UI vertex: where it sits, its shape, colour and parameters
const UiVertex=@import("../gfx/vertex.zig").Ui;
/// a box in screen pixels, which drawing can be cut to
const Box=@import("box.zig").Box;
/// a clip rectangle (left, top, right, bottom pixels), as the shader reads it
pub const Clip=m.Vice(f32,4);
/// no clip: everything shows, wherever it is drawn
pub const noClip=Clip{-1e9,-1e9,1e9,1e9};
/// a UI colour: four bytes, red, green, blue and alpha
pub const Color=m.Vice(u8,4);
/// which distance field a quad is shaded with; must match the shape switch
/// in shaders/ui.frag
pub const Shape=enum(u32){
  /// a panel: a lattice of withies framed by two braided vines that grow
  /// round its rim; param.x = how far grown (0..1), param.y = seed
  trellis,
  /// round seed pod (a bead, a bud, a bullet); param.x = how lit
  pod,
  /// a leafy stem that grows along local x to param.x of its length
  tendril,
  /// soft radial halo
  glow,
  /// tapered stem segment (bark, sap rising); param.x = end/start radius,
  /// param.y = arc length at its start, so texture runs on across segments
  limb,
  /// leaf blade from its base along the quad; param.x = how open (0 is a
  /// closed bud), param.y = seed
  leaf,
  /// a seed on its round end, pointed top up; param.x = how far its seam
  /// has split open, param.y = seed
  grain,
  /// a cut gem, table up; param.x = how much fire, param.y = seed
  gem,
  /// a living night filling the quad: soil-dark, sap veins drifting through
  /// it, spores rising, darker toward its edges; param.y = seed
  night,
  /// a slot: a ribbed husk hanging by its stalk under a calyx; param.x =
  /// how much sap light fills it, param.y = seed
  husk,
  /// a painted backdrop over the whole screen: the dark, the moon low
  /// behind, the earth under a soil line at param.x (pixels down the
  /// screen), petals, flowers, seeds, leaves and pollen drifting down;
  /// param.y = seed
  dusk,
  /// a flower of the sharers: a bud in sepals opening into five petals
  /// round its stamens; param.x = how open, param.y = seed
  blossom,
  /// a gall of the takers: a thorned bladder whose mouth parts; param.x =
  /// how open, param.y = seed
  gall,
  /// light gathered: crystal fragments settling round a core; param.x =
  /// how gathered, param.y = seed
  shard,
  /// where the lineages meet: two strands braiding a ring round a bloom;
  /// param.x = how far braided, param.y = seed
  knot,
};
/// the first of a quad's two bit words when it holds a shape, not a glyph
const shapeMark:u32=0xffff_ffff;
/// a glyph's cell width: the font's bitmap plus one pixel of spacing
const cellW=font.glyphW+1;
/// a glyph's cell height: the font's bitmap plus one pixel of spacing
const cellH=font.glyphH+1;
/// a glyph's quad reaches this many cells past its cell each way, room for
/// the leaves its stems put out (must match GLYPH_PAD in shaders/ui.frag)
const glyphPad=1;
/// text shimmers along its length by this phase per pixel
const shimmer:f32=0.01;
/// how many growing things `grown` keeps track of at once
const maxSprouts=48;
/// seconds a trellis takes to grow round its panel
pub const trellisGrow:f32=0.6;
/// a growing thing: its key, when it was first drawn, whether it was drawn
/// this frame
const Sprout=struct{
  /// what the growing thing is keyed by (its key's bits)
  key:u32,
  /// when it was first drawn (seconds, as the shader's)
  born:f32,
  /// whether it was drawn this frame
  seen:bool
};
/// the frame's batch of UI quads, and the clocks of what is growing in it
pub const Draw=struct{
  /// the allocator the vertices grow through
  gpa:Allocator,
  /// the frame's vertices, six to a quad
  v:std.ArrayList(UiVertex)=.empty,
  /// the frame's time (seconds, as the shader's), set by `clear`
  now:f32=0,
  /// what is growing, and since when (the first `nSprouts` hold)
  sprouts:[maxSprouts]Sprout=undefined,
  /// how many sprouts are kept
  nSprouts:usize=0,
  /// what is drawn now is cut to this rectangle (`clipTo` narrows it)
  clip:Clip=noClip,
  /// frees the vertices
  pub fn deinit(d:*Draw)void{d.v.deinit(d.gpa);}
  /// cuts what is drawn from now on to `b` (within the clip already in
  /// force), as a list's rows are to the list; returns the clip that was,
  /// to put back with `unclip` once the cut drawing is done
  pub fn clipTo(d:*Draw,b:Box)Clip{
    // the clip in force, kept to be put back
    const was=d.clip;
    d.clip=.{@max(was[0],b.x),@max(was[1],b.y),@min(was[2],b.x+b.w),@min(was[3],b.y+b.h)};
    return was;
  }
  /// puts back the clip `was` (as `clipTo` returned it)
  pub fn unclip(d:*Draw,was:Clip)void{d.clip=was;}
  /// starts a frame at time `now`: what was not drawn last frame is
  /// forgotten, so it grows afresh when drawn again.
  pub fn clear(d:*Draw,now:f32)void{
    d.v.clearRetainingCapacity();
    d.now=now;
    d.clip=noClip;
    // how many sprouts are kept so far
    var n:usize=0;
    for(d.sprouts[0..d.nSprouts])|sp|{
      if(!sp.seen)continue;
      d.sprouts[n]=.{.key=sp.key,.born=sp.born,.seen=false};
      n+=1;
    }
    d.nSprouts=n;
  }
  /// how far (0..1, over `secs`) the thing keyed `key` has grown since it
  /// was first drawn without a frame's break; fully grown if too many grow.
  pub fn grown(d:*Draw,key:f32,secs:f32)f32{
    // the key's bits, to match it exactly
    const k:u32=@bitCast(key);
    for(d.sprouts[0..d.nSprouts])|*sp|if(sp.key==k){
      sp.seen=true;
      return m.clamp01((d.now-sp.born)/secs);
    };
    if(d.nSprouts==maxSprouts)return 1;
    d.sprouts[d.nSprouts]=.{.key=k,.born=d.now,.seen=true};
    d.nSprouts+=1;
    return 0;
  }
  /// a `w` x `h` quad at (x0, y0), snapped to whole pixels, its uv running
  /// 0..uw by 0..uh, with the bits and parameters the shader reads
  fn quad(d:*Draw,x0:f32,y0:f32,w:f32,h:f32,uw:f32,uh:f32,col:Color,bits:m.Vice(u32,2),param:m.Vice(f32,2))Allocator.Error!void{
    // snapped to whole pixels so edges never land between texels and crawl
    const x=@round(x0);
    const y=@round(y0);
    // the corners, clockwise from the top left, and their uvs
    const p=[4]m.Vice(f32,2){.{x,y},.{x+w,y},.{x+w,y+h},.{x,y+h}};
    const uv=[4]m.Vice(f32,2){.{0,0},.{uw,0},.{uw,uh},.{0,uh}};
    for([_]usize{0,1,2,0,2,3})|i|{
      try d.v.append(d.gpa,.{.pos=p[i],.uv=uv[i],.size=.{w,h},.col=col,.bits=bits,.param=param,.clip=d.clip});
    }
  }
  /// a quad laid along unit direction `u` from `a`: local x runs along it
  /// (len), y across (thick), both padded like `shape`.
  fn along(d:*Draw,kind:Shape,a:m.Vice(f32,2),u:m.Vice(f32,2),len:f32,thick:f32,col:Color,param:m.Vice(f32,2))Allocator.Error!void{
    // the margin round the shape, for wobble and glow
    const pad:f32=28;
    // the quad's size, margins and all
    const w=len+2*pad;
    const h=thick+2*pad;
    // the corners in the quad's own space, and where they land on screen
    const uv=[4]m.Vice(f32,2){.{0,0},.{w,0},.{w,h},.{0,h}};
    var p:[4]m.Vice(f32,2)=undefined;
    for(uv,&p)|q,*o|{
      // the corner's place along the direction, and across it
      const x=q[0]-pad;
      const y=q[1]-h/2;
      o.*=.{a[0]+u[0]*x-u[1]*y,a[1]+u[1]*x+u[0]*y};
    }
    for([_]usize{0,1,2,0,2,3})|i|{
      try d.v.append(d.gpa,.{.pos=p[i],.uv=uv[i],.size=.{w,h},.col=col,.bits=.{shapeMark,@intFromEnum(kind)},.param=param,.clip=d.clip});
    }
  }
  /// shapes get a margin so wobble/glow can spill past the nominal bounds.
  fn shape(d:*Draw,kind:Shape,x:f32,y:f32,w:f32,h:f32,col:Color,param:m.Vice(f32,2))Allocator.Error!void{
    // the margin round the shape
    const pad:f32=28;
    try d.quad(x-pad,y-pad,w+2*pad,h+2*pad,w+2*pad,h+2*pad,col,.{shapeMark,@intFromEnum(kind)},param);
  }
  /// a panel `w` x `h` (its bed `col`); `seed` sets its vines and keys its
  /// growth (`grown`), so panels drawn at once take different seeds.
  pub fn trellis(d:*Draw,x:f32,y:f32,w:f32,h:f32,col:Color,seed:f32)Allocator.Error!void{
    try d.shape(.trellis,x,y,w,h,col,.{d.grown(seed,trellisGrow),seed});
  }
  /// a slot of radius `r` hanging at (cx, cy), its stalk rising above it.
  pub fn husk(d:*Draw,cx:f32,cy:f32,r:f32,col:Color,lit:f32,seed:f32)Allocator.Error!void{
    try d.shape(.husk,cx-r,cy-r,2*r,2*r,col,.{lit,seed});
  }
  /// a seed pod of radius `r` at (cx, cy), lit by `lit` (0..1)
  pub fn pod(d:*Draw,cx:f32,cy:f32,r:f32,col:Color,lit:f32,seed:f32)Allocator.Error!void{
    try d.shape(.pod,cx-r,cy-r,2*r,2*r,col,.{lit,seed});
  }
  /// a leafy stem `w` x `h`, grown to `value` (0..1) of its length along x
  pub fn tendril(d:*Draw,x:f32,y:f32,w:f32,h:f32,col:Color,value:f32,seed:f32)Allocator.Error!void{
    try d.shape(.tendril,x,y,w,h,col,.{m.clamp(value,0,1),seed});
  }
  /// a tendril from `a` along screen angle `ang` (0 right, y down), `len`
  /// long and `h` thick, grown to `value` of its length.
  pub fn stem(d:*Draw,a:m.Vice(f32,2),ang:f32,len:f32,h:f32,col:Color,value:f32,seed:f32)Allocator.Error!void{
    try d.along(.tendril,a,.{@cos(ang),@sin(ang)},len,h,col,.{m.clamp01(value),seed});
  }
  /// a soft halo of radius `r` round (cx, cy)
  pub fn glow(d:*Draw,cx:f32,cy:f32,r:f32,col:Color)Allocator.Error!void{
    try d.shape(.glow,cx-r,cy-r,2*r,2*r,col,.{0,0});
  }
  /// a stem from `a` (radius r0) to `b` (radius r1 <= r0), round at both
  /// ends so consecutive segments join; `s0` is the arc length at `a`.
  pub fn limb(d:*Draw,a:m.Vice(f32,2),b:m.Vice(f32,2),r0:f32,r1:f32,col:Color,s0:f32)Allocator.Error!void{
    // the run from `a` to `b`, its length and its direction
    const dx=b[0]-a[0];
    const dy=b[1]-a[1];
    const l=@sqrt(dx*dx+dy*dy);
    const u:m.Vice(f32,2)=if(l>m.eps).{dx/l,dy/l}else.{1,0};
    try d.along(.limb,a,u,l,2*r0,col,.{if(r0>m.eps)r1/r0 else 1,s0});
  }
  /// a leaf (or, closed, a bud) growing from `base` at screen angle `ang`.
  pub fn leaf(d:*Draw,base:m.Vice(f32,2),ang:f32,len:f32,wid:f32,col:Color,open:f32,seed:f32)Allocator.Error!void{
    try d.along(.leaf,base,.{@cos(ang),@sin(ang)},len,wid,col,.{m.clamp01(open),seed});
  }
  /// a seed `w` x `h` centred on (cx, cy), split open by `crack`.
  pub fn grain(d:*Draw,cx:f32,cy:f32,w:f32,h:f32,col:Color,crack:f32,phase:f32)Allocator.Error!void{
    try d.shape(.grain,cx-w/2,cy-h/2,w,h,col,.{m.clamp01(crack),phase});
  }
  /// the night over the whole `w` x `h` screen (opaque at full alpha)
  pub fn night(d:*Draw,w:f32,h:f32,col:Color,seed:f32)Allocator.Error!void{
    try d.shape(.night,0,0,w,h,col,.{0,seed});
  }
  /// the painted backdrop over the whole `w` x `h` screen, its soil line
  /// `soil` pixels down it (opaque at full alpha)
  pub fn dusk(d:*Draw,w:f32,h:f32,soil:f32,col:Color,seed:f32)Allocator.Error!void{
    try d.shape(.dusk,0,0,w,h,col,.{soil,seed});
  }
  /// a flower of radius `r` at (cx, cy), petals `col`, opened by `open` (0..1)
  pub fn blossom(d:*Draw,cx:f32,cy:f32,r:f32,col:Color,open:f32,seed:f32)Allocator.Error!void{
    try d.shape(.blossom,cx-r,cy-r,2*r,2*r,col,.{m.clamp01(open),seed});
  }
  /// a gall of radius `r` at (cx, cy), its bladder `col`, its mouth opened by `open`
  pub fn gall(d:*Draw,cx:f32,cy:f32,r:f32,col:Color,open:f32,seed:f32)Allocator.Error!void{
    try d.shape(.gall,cx-r,cy-r,2*r,2*r,col,.{m.clamp01(open),seed});
  }
  /// crystal of radius `r` at (cx, cy), its light `col`, gathered by `open`
  pub fn shard(d:*Draw,cx:f32,cy:f32,r:f32,col:Color,open:f32,seed:f32)Allocator.Error!void{
    try d.shape(.shard,cx-r,cy-r,2*r,2*r,col,.{m.clamp01(open),seed});
  }
  /// a braided ring of radius `r` at (cx, cy), its bloom `col`, braided by `open`
  pub fn knot(d:*Draw,cx:f32,cy:f32,r:f32,col:Color,open:f32,seed:f32)Allocator.Error!void{
    try d.shape(.knot,cx-r,cy-r,2*r,2*r,col,.{m.clamp01(open),seed});
  }
  /// a cut gem of radius `r` at (cx, cy), its fire `fire` (0..1)
  pub fn gem(d:*Draw,cx:f32,cy:f32,r:f32,col:Color,fire:f32,phase:f32)Allocator.Error!void{
    try d.shape(.gem,cx-r,cy-r,2*r,2*r,col,.{fire,phase});
  }
  /// a line of text from (x, y) at scale `s`, each glyph a quad of its
  /// bitmap (spaces skipped). Returns the x after the last glyph.
  pub fn text(d:*Draw,x:f32,y:f32,s:f32,col:Color,str:[]const u8)Allocator.Error!f32{
    // where the next glyph goes
    var cx=x;
    for(str)|ch|{
      // a glyph's quad size, padding and all, before scaling
      const pw=cellW+2*glyphPad;
      const ph=cellH+2*glyphPad;
      if(ch!=' ')try d.quad(cx-glyphPad*s,y-glyphPad*s,pw*s,ph*s,pw,ph,col,font.bits(ch),.{0,cx*shimmer});
      cx+=cellW*s;
    }
    return cx;
  }
  /// how wide `str` is at scale `s` (pixels)
  pub fn width(str:[]const u8,s:f32)f32{return m.f(str.len)*cellW*s;}
  /// `tpl` is a runtime template (`core/text.zig`), truncated to 256 bytes.
  pub fn print(d:*Draw,x:f32,y:f32,s:f32,col:Color,tpl:[]const u8,args:anytype)Allocator.Error!f32{
    // the filled template, before it is drawn
    var buf:[256]u8=undefined;
    return d.text(x,y,s,col,ctext.bufRender(&buf,tpl,args));
  }
  /// a bare count.
  pub fn number(d:*Draw,x:f32,y:f32,s:f32,col:Color,n:u32)Allocator.Error!f32{
    // the number's digits
    var buf:[24]u8=undefined;
    return d.text(x,y,s,col,bufPrint(&buf,"{d}",.{n})catch&buf);
  }
};
test"a trellis grows from the frame it is first drawn, afresh after a break"{
  // a batch over the test allocator
  var d:Draw=.{.gpa=std.testing.allocator};
  defer d.deinit();
  d.clear(10);
  try std.testing.expectEqual(@as(f32,0),d.grown(0.5,1));
  d.clear(10.5);
  try std.testing.expectApproxEqAbs(@as(f32,0.5),d.grown(0.5,1),1e-6);
  // another key keeps its own clock
  try std.testing.expectEqual(@as(f32,0),d.grown(0.7,1));
  d.clear(12);
  try std.testing.expectEqual(@as(f32,1),d.grown(0.5,1));
  // a frame without it: it is forgotten, and grows again
  d.clear(13);
  d.clear(14);
  try std.testing.expectEqual(@as(f32,0),d.grown(0.5,1));
}
test"a clip narrows within the one in force, is put back, and every quad carries it"{
  // a batch over the test allocator
  var d:Draw=.{.gpa=std.testing.allocator};
  defer d.deinit();
  d.clear(0);
  // cut to a list, then within it to a row poking out of its right side
  const outer=d.clipTo(.{.x=10,.y=10,.w=100,.h=50});
  const inner=d.clipTo(.{.x=50,.y=0,.w=100,.h=30});
  try std.testing.expectEqual(Clip{50,10,110,30},d.clip);
  try d.glow(60,20,4,.{255,255,255,255});
  try std.testing.expectEqual(Clip{50,10,110,30},d.v.items[0].clip);
  d.unclip(inner);
  try std.testing.expectEqual(Clip{10,10,110,60},d.clip);
  d.unclip(outer);
  try std.testing.expectEqual(noClip,d.clip);
}
