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
  /// a plain filled quad in its colour, unpadded: one pixel of a picture
  swatch,
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
//// the keys, mouse buttons and pad buttons a binding names (pad glyphs)
const input=@import("../platform/input.zig");
/// the first byte standing for a pad button in a line of text (`padByte`):
/// past ASCII, never a character's own (the strings are ASCII)
const padFirst:u8=0x80;
/// how many pad buttons (then the two triggers) have a byte of their own
const padButtons=@typeInfo(input.PadButton).@"enum".fields.len;
/// how many cells a pad button takes in a line of text
pub const padCells:usize=3;
/// a pad glyph's radius, a share of a line's height
const padReach:f32=0.62;
/// how lit a pad glyph's pods are
/// how far a wooden pad glyph reaches either side of its middle, and how
/// thick it is, shares of the glyph's radius
const padSpan:f32=0.75;
/// (see `padSpan`)
const padThick:f32=0.95;
const padLit:f32=0.35;
/// the pad's wood: bumpers, triggers, sticks, Menu, View and the d-pad
const padWood:Color=.{62,44,28,255};
/// the dark of the letters on a face button
const padInk:Color=.{24,20,16,255};
/// the pale of the names and marks on the pad's wood
const padPale:Color=.{238,226,198,255};
/// a face button's own colour, as the pad's: A green, B red, X blue, Y yellow
fn faceColor(p:input.PadButton)Color{
  return switch(p){.a=>.{92,168,64,255},.b=>.{196,64,52,255},.x=>.{52,112,196,255},else=>.{224,184,52,255}};
}
/// the byte a pad button or trigger is written as in a line of text, for
/// `text` to draw as that button (null: a key or mouse button)
pub fn padByte(b:input.Bind)?u8{
  return switch(b){
    .pad=>|p|padFirst+@as(u8,@intCast(@intFromEnum(p))),
    .trigger=>|t|padFirst+@as(u8,@intCast(padButtons+@intFromEnum(t))),
    .key,.button=>null,
  };
}
/// the pad button or trigger byte `ch` stands for, if it stands for one
pub fn padOf(ch:u8)?input.Bind{
  if(ch<padFirst)return null;
  // which of them, counted from the first
  const i=ch-padFirst;
  if(i<padButtons)return.{.pad=@enumFromInt(i)};
  if(i<padButtons+2)return.{.trigger=@enumFromInt(i-padButtons)};
  return null;
}
// text shimmers along its length by this phase per pixel
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
  /// a small picture (`w`×`h` pixels of RGB, `rgb`) drawn from (x, y), each
  /// of its pixels a `k`×`k` swatch, at opacity `alpha` (0..255)
  pub fn picture(d:*Draw,x:f32,y:f32,k:f32,w:u32,h:u32,rgb:[]const u8,alpha:u8)Allocator.Error!void{
    for(0..h)|py|for(0..w)|px|{
      // this pixel's colour
      const i=(py*w+px)*3;
      try d.quad(x+m.f(px)*k,y+m.f(py)*k,k,k,k,k,.{rgb[i],rgb[i+1],rgb[i+2],alpha},.{shapeMark,@intFromEnum(Shape.swatch)},.{0,0});
    };
  }
  /// a line of text from (x, y) at scale `s`, each glyph a quad of its
  /// bitmap (spaces skipped), a pad button's byte (`padByte`) drawn as
  /// that button. Returns the x after the last glyph.
  pub fn text(d:*Draw,x:f32,y:f32,s:f32,col:Color,str:[]const u8)Allocator.Error!f32{
    // where the next glyph goes
    var cx=x;
    for(str)|ch|{
      if(padOf(ch))|b|{
        try d.padGlyph(cx,y,s,col,b);
        cx+=padCells*cellW*s;
        continue;
      }
      // a glyph's quad size, padding and all, before scaling
      const pw=cellW+2*glyphPad;
      const ph=cellH+2*glyphPad;
      if(ch!=' ')try d.quad(cx-glyphPad*s,y-glyphPad*s,pw*s,ph*s,pw,ph,col,font.bits(ch),.{0,cx*shimmer});
      cx+=cellW*s;
    }
    return cx;
  }
  /// how wide `str` is at scale `s` (pixels), a pad button `padCells` wide
  pub fn width(str:[]const u8,s:f32)f32{
    // the cells it takes
    var cells:usize=0;
    for(str)|ch|cells+=if(padOf(ch)!=null)padCells else 1;
    return m.f(cells)*cellW*s;
  }
  /// pad button `b` drawn in a line of text whose cell starts at (x, y),
  /// scale `s`: a face button a seed pod in its own colour, its letter on
  /// it; a bumper, trigger or stick a short limb of wood with its name; the
  /// d-pad a cross of twigs, the way pressed lit; Menu and View short
  /// limbs marked with their lines. `col` is the text's own colour (the marks')
  pub fn padGlyph(d:*Draw,x:f32,y:f32,s:f32,col:Color,b:input.Bind)Allocator.Error!void{
    // the glyph's middle, and its size: a line tall
    const cx=x+padCells*cellW*s/2-cellW*s/2;
    const cy=y+cellH*s/2-s/2;
    const r=cellH*s*padReach;
    switch(b){
      .pad=>|p|switch(p){
        .a,.b,.x,.y=>{
          try d.pod(cx,cy,r,faceColor(p),padLit,0);
          _=try d.text(cx-cellW*s/2+s/2,y,s,padInk,switch(p){.a=>"A",.b=>"B",.x=>"X",else=>"Y"});
        },
        .left_bumper=>try d.padNamed(cx,cy,r,y,s,"LB"),
        .right_bumper=>try d.padNamed(cx,cy,r,y,s,"RB"),
        .left_thumb=>try d.padNamed(cx,cy,r,y,s,"LS"),
        .right_thumb=>try d.padNamed(cx,cy,r,y,s,"RS"),
        .start,.back,.guide=>{
          try d.limb(.{cx-r*padSpan*0.6,cy},.{cx+r*padSpan*0.6,cy},r*padThick,r*padThick,padWood,0);
          // Menu's three lines, View's two offset panes, the guide a ring
          const w=r*0.55;
          if(p==.start)for(0..3)|k|{
            const ly=cy+(m.f(k)-1)*r*0.4;
            try d.limb(.{cx-w,ly},.{cx+w,ly},s*0.8,s*0.8,padPale,0);
          }else if(p==.back){
            try d.limb(.{cx-w,cy-r*0.25},.{cx+w*0.4,cy-r*0.25},s*0.9,s*0.9,padPale,0);
            try d.limb(.{cx-w*0.4,cy+r*0.25},.{cx+w,cy+r*0.25},s*0.9,s*0.9,padPale,0);
          }else try d.glow(cx,cy,r*0.5,padPale);
        },
        .dpad_up,.dpad_right,.dpad_down,.dpad_left=>{
          // the cross, and the arm pressed lit at its tip
          try d.limb(.{cx-r,cy},.{cx+r,cy},s*1.6,s*1.6,padWood,0);
          try d.limb(.{cx,cy-r},.{cx,cy+r},s*1.6,s*1.6,padWood,0.5);
          const tip:m.Vice(f32,2)=switch(p){.dpad_up=>.{0,-1},.dpad_right=>.{1,0},.dpad_down=>.{0,1},else=>.{-1,0}};
          try d.pod(cx+tip[0]*r*0.7,cy+tip[1]*r*0.7,r*0.38,col,padLit,0);
        },
      },
      .trigger=>|t|try d.padNamed(cx,cy,r,y,s,if(t==.left_trigger)"LT"else"RT"),
      .key,.button=>{},
    }
  }
  /// a short thick limb of the pad's wood with a two-letter name over it
  fn padNamed(d:*Draw,cx:f32,cy:f32,r:f32,y:f32,s:f32,name:[]const u8)Allocator.Error!void{
    try d.limb(.{cx-r*padSpan,cy},.{cx+r*padSpan,cy},r*padThick,r*padThick,padWood,0);
    _=try d.text(cx-cellW*s+s/2,y,s,padPale,name);
  }
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
test"a pad button rides a line of text as one byte, drawn as the button and a few cells wide"{
  // the test helpers, and a batch over the test allocator
  const t=std.testing;
  var d:Draw=.{.gpa=t.allocator};
  defer d.deinit();
  d.clear(0);
  // every pad button and trigger has its own byte, read back as itself
  for(std.enums.values(input.PadButton))|p|try t.expectEqual(input.Bind{.pad=p},padOf(padByte(.{.pad=p}).?).?);
  for(std.enums.values(input.Trigger))|k|try t.expectEqual(input.Bind{.trigger=k},padOf(padByte(.{.trigger=k}).?).?);
  try t.expect(padByte(.{.key=.w})==null);
  try t.expect(padOf('A')==null);
  // a line holding one: as wide as its letters and the button's cells
  const line=[_]u8{'G','O',' ',padByte(.{.pad=.a}).?};
  try t.expectEqual(m.f(3+padCells)*cellW*2,Draw.width(&line,2));
  try t.expectEqual(10+m.f(3+padCells)*cellW*2,try d.text(10,10,2,.{255,255,255,255},&line));
}
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
