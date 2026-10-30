//! PNG encoding of 8-bit pixels (screenshots): RGB, every row Sub-filtered,
//! one zlib stream in one IDAT chunk.
const std=@import("std");
const Allocator=std.mem.Allocator;
const Writer=std.Io.Writer;
const Allocating=Writer.Allocating;
const flate=std.compress.flate;
const Compress=flate.Compress;
const Crc32=std.hash.Crc32;
const writeInt=std.mem.writeInt;
const testing=std.testing;
const assert=std.debug.assert;
const readInt=std.mem.readInt;
const Reader=std.Io.Reader;
const signature="\x89PNG\r\n\x1a\n";
/// IHDR: 8 bits a channel, colour type 2 (RGB), no interlace
const depth=8;
const rgb=2;
/// each row's filter byte: Sub (each byte less the one a pixel before)
const sub=1;
/// the order of a source pixel's four bytes (the fourth is dropped)
pub const Layout=enum{rgba,bgra};
pub const Error=Allocator.Error||Writer.Error;
/// `px`: `w`×`h` pixels of 4 bytes, row by row from the top. The caller
/// frees the result.
pub fn encode(gpa:Allocator,w:u32,h:u32,px:[]const u8,layout:Layout)Error![]u8{
  assert(px.len==@as(usize,w)*h*4);
  // filtered rows: a filter byte, then RGB
  const row=@as(usize,w)*3+1;
  const raw=try gpa.alloc(u8,row*h);
  defer gpa.free(raw);
  const order:[3]usize=switch(layout){.rgba=>.{0,1,2},.bgra=>.{2,1,0}};
  for(0..h)|y|{
    const out=raw[y*row..][0..row];
    const in=px[y*w*4..][0..w*4];
    out[0]=sub;
    var prev:[3]u8=.{0,0,0};
    for(0..w)|x|for(0..3)|k|{
      const v=in[x*4+order[k]];
      out[1+x*3+k]=v-%prev[k];
      prev[k]=v;
    };
  }
  var z:Allocating=try.initCapacity(gpa,raw.len/2+64);
  defer z.deinit();
  const window=try gpa.alloc(u8,flate.max_window_len);
  defer gpa.free(window);
  // decision: ~224K of match tables, so on the heap
  const c=try gpa.create(Compress);
  defer gpa.destroy(c);
  c.*=try.init(&z.writer,window,.zlib,.fastest);
  try c.writer.writeAll(raw);
  try c.finish();
  var file:Allocating=try.initCapacity(gpa,z.written().len+64);
  errdefer file.deinit();
  try file.writer.writeAll(signature);
  var head:[13]u8=undefined;
  writeInt(u32,head[0..4],w,.big);
  writeInt(u32,head[4..8],h,.big);
  head[8..].*=.{depth,rgb,0,0,0};
  try chunk(&file.writer,"IHDR",&head);
  try chunk(&file.writer,"IDAT",z.written());
  try chunk(&file.writer,"IEND","");
  return file.toOwnedSlice();
}
fn chunk(out:*Writer,kind:*const[4]u8,data:[]const u8)Writer.Error!void{
  try out.writeInt(u32,@intCast(data.len),.big);
  try out.writeAll(kind);
  try out.writeAll(data);
  var crc=Crc32.init();
  crc.update(kind);
  crc.update(data);
  try out.writeInt(u32,crc.final(),.big);
}
test"a PNG holds its pixels: header, then rows that decompress back"{
  const gpa=testing.allocator;
  // 2×2 BGRA: red, green / blue, white
  const px=[_]u8{0,0,255,255,0,255,0,255,255,0,0,255,255,255,255,255};
  const png=try encode(gpa,2,2,&px,.bgra);
  defer gpa.free(png);
  try testing.expectEqualStrings(signature,png[0..8]);
  try testing.expectEqualStrings("IHDR",png[12..16]);
  try testing.expectEqual(@as(u32,2),readInt(u32,png[16..20],.big));
  // IDAT follows IHDR (8 + 13 + 4 bytes on)
  const at=8+25;
  const n=readInt(u32,png[at..][0..4],.big);
  try testing.expectEqualStrings("IDAT",png[at+4..][0..4]);
  var in:Reader=.fixed(png[at+8..][0..n]);
  var buf:[flate.max_window_len]u8=undefined;
  var d:flate.Decompress=.init(&in,.zlib,&buf);
  var rows:[14]u8=undefined;
  try d.reader.readSliceAll(&rows);
  // Sub-filtered: red, then green less red; blue, then white less blue
  try testing.expectEqualSlices(u8,&.{sub,255,0,0,1,255,0,sub,0,0,255,255,255,0},&rows);
  try testing.expectEqualStrings("IEND",png[png.len-8..][0..4]);
}
