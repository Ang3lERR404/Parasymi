//! laying boxes out, so a panel says what goes where instead of working out
//! each pixel: a column hands out rows down a box one after another, a grid
//! hands out cells in rows of so many. Each returns a `Box`, which a
//! component is then drawn in and hit-tested by.
/// the standard library
const std=@import("std");
/// the engine's maths: conversions
const m=@import("../core/math.zig");
/// a box in screen pixels
const Box=@import("box.zig").Box;
/// rows handed out down a column, each as tall as asked, `gap` between them
pub const Column=struct{
  /// the column's left edge (pixels)
  x:f32,
  /// how wide every row is (pixels)
  w:f32,
  /// where the next row's top goes (pixels)
  y:f32,
  /// the room between one row and the next (pixels)
  gap:f32=0,
  /// a column filling `b` across, its first row at `b`'s top
  pub fn in(b:Box,gap:f32)Column{return.{.x=b.x,.w=b.w,.y=b.y,.gap=gap};}
  /// the next row, `h` tall; the one after starts below it and the gap
  pub fn next(c:*Column,h:f32)Box{
    // the row handed out
    const b:Box=.{.x=c.x,.y=c.y,.w=c.w,.h=h};
    c.y+=h+c.gap;
    return b;
  }
  /// leaves `h` of room before the next row (no gap added)
  pub fn skip(c:*Column,h:f32)void{c.y+=h;}
};
/// cells handed out in rows of `cols`, left to right then down, each `cell`
/// big with `gap` between them
pub const Grid=struct{
  /// the first cell's top left corner (pixels)
  at:m.Vice(f32,2),
  /// one cell's width and height (pixels)
  cell:m.Vice(f32,2),
  /// the room between cells across and down (pixels)
  gap:m.Vice(f32,2)=.{0,0},
  /// how many cells a row holds
  cols:usize,
  /// cell `i` (0 the top left)
  pub fn box(g:Grid,i:usize)Box{
    // the cell's column and row
    const c=i%g.cols;
    const r=i/g.cols;
    return.{.x=g.at[0]+m.f(c)*(g.cell[0]+g.gap[0]),.y=g.at[1]+m.f(r)*(g.cell[1]+g.gap[1]),.w=g.cell[0],.h=g.cell[1]};
  }
  /// how much room `n` cells take, as .{w, h} (no gap after the last)
  pub fn size(g:Grid,n:usize)m.Vice(f32,2){
    // how many columns and rows they fill
    const c=@min(n,g.cols);
    const r=(n+g.cols-1)/g.cols;
    return.{m.f(c)*g.cell[0]+m.f(c-|1)*g.gap[0],m.f(r)*g.cell[1]+m.f(r-|1)*g.gap[1]};
  }
};
/// a `w` by `h` box in the middle of a screen `screen` pixels wide and high
pub fn centred(screen:m.Vice(f32,2),w:f32,h:f32)Box{
  return.{.x=(screen[0]-w)/2,.y=(screen[1]-h)/2,.w=w,.h=h};
}
/// `b` drawn in by `dx` at its left and right and `dy` at its top and bottom
pub fn inset(b:Box,dx:f32,dy:f32)Box{return.{.x=b.x+dx,.y=b.y+dy,.w=b.w-2*dx,.h=b.h-2*dy};}
/// the test helpers
const testing=std.testing;
test"a column hands out rows one under another, a gap between them"{
  // a column down a 200 wide box from (10, 20), 4 between rows
  var c=Column.in(.{.x=10,.y=20,.w=200,.h=300},4);
  try testing.expectEqual(Box{.x=10,.y=20,.w=200,.h=30},c.next(30));
  c.skip(6);
  try testing.expectEqual(Box{.x=10,.y=60,.w=200,.h=50},c.next(50));
  try testing.expectEqual(@as(f32,114),c.y);
}
test"a grid fills its rows left to right, and knows how much room cells take"{
  // three cells a row, each 40 by 30, 10 between
  const g:Grid=.{.at=.{100,50},.cell=.{40,30},.gap=.{10,10},.cols=3};
  try testing.expectEqual(Box{.x=100,.y=50,.w=40,.h=30},g.box(0));
  try testing.expectEqual(Box{.x=200,.y=50,.w=40,.h=30},g.box(2));
  try testing.expectEqual(Box{.x=150,.y=90,.w=40,.h=30},g.box(4));
  try testing.expectEqual(m.Vice(f32,2){140,70},g.size(5));
  try testing.expectEqual(m.Vice(f32,2){90,30},g.size(2));
  try testing.expectEqual(m.Vice(f32,2){0,0},g.size(0));
}
test"a box sits in the middle of the screen, and draws in by its insets"{
  try testing.expectEqual(Box{.x=350,.y=250,.w=100,.h=100},centred(.{800,600},100,100));
  try testing.expectEqual(Box{.x=15,.y=12,.w=70,.h=36},inset(.{.x=5,.y=10,.w=90,.h=40},10,2));
}
