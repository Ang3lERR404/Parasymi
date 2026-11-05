//! PNG encoding of 8-bit pixels (screenshots): RGB, every row Sub-filtered,
//! one zlib stream in one IDAT chunk; and reading those back (`decode`).
const std=@import("std");
/// the maths: vectors (Vec), rows (Vice) and matrices (Mat)
const m=@import("math.zig");
/// the allocator type the encoder takes
const Allocator=std.mem.Allocator;
/// the stream writer chunks are written through
const Writer=std.Io.Writer;
/// a writer that grows into memory, for the compressed data and the file
const Allocating=Writer.Allocating;
/// deflate, for the pixel stream
const flate=std.compress.flate;
/// the deflate compressor
const Compress=flate.Compress;
/// the checksum ending every chunk
const Crc32=std.hash.Crc32;
/// writes a whole number in a set byte order
const writeInt=std.mem.writeInt;
/// the test helpers
const testing=std.testing;
/// whether two byte runs are the same (a file read back)
const eql=std.mem.eql;
/// stops on what must never happen
const assert=std.debug.assert;
/// reads a whole number in a set byte order (the header, read back)
const readInt=std.mem.readInt;
/// the stream reader (the compressed pixels, read back)
const Reader=std.Io.Reader;
/// the eight bytes every PNG file opens with
const signature="\x89PNG\r\n\x1a\n";
/// IHDR: 8 bits a channel
const depth=8;
/// IHDR: colour type 2 (RGB), with no interlace
const rgb=2;
/// each row's filter byte: Sub (each byte less the one a pixel before)
const sub=1;
/// the order of a source pixel's four bytes (the fourth is dropped):
/// red first, or blue first as swapchains often store them
pub const Layout=enum{
  /// red, green, blue, then the dropped byte
  rgba,
  /// blue, green, red, then the dropped byte
  bgra
};
/// what encoding can fail with: out of memory, or the writer failing
pub const Error=Allocator.Error||Writer.Error;
/// `px`: `w`×`h` pixels of 4 bytes, row by row from the top, laid out as
/// `layout` says. Returns the whole PNG file's bytes; the caller frees them.
pub fn encode(gpa:Allocator,w:u32,h:u32,px:[]const u8,layout:Layout)Error![]u8{
  assert(px.len==@as(usize,w)*h*4);
  // filtered rows: a filter byte, then RGB
  const row=@as(usize,w)*3+1;
  // the filtered rows
  const raw=try gpa.alloc(u8,row*h);
  defer gpa.free(raw);
  // where red, green and blue sit within a source pixel
  const order:m.Vice(usize,3)=switch(layout){.rgba=>.{0,1,2},.bgra=>.{2,1,0}};
  for(0..h)|y|{
    // this row's filtered bytes, and its source pixels
    const out=raw[y*row..][0..row];
    const in=px[y*w*4..][0..w*4];
    out[0]=sub;
    // the pixel before's bytes, which each byte is stored less
    var prev:m.Vice(u8,3)=.{0,0,0};
    for(0..w)|x|for(0..3)|k|{
      // this channel's byte
      const v=in[x*4+order[k]];
      out[1+x*3+k]=v-%prev[k];
      prev[k]=v;
    };
  }
  // the compressed stream, grown in memory
  var z:Allocating=try.initCapacity(gpa,raw.len/2+64);
  defer z.deinit();
  // the compressor's sliding window
  const window=try gpa.alloc(u8,flate.max_window_len);
  defer gpa.free(window);
  // decision: ~224K of match tables, so on the heap
  const c=try gpa.create(Compress);
  defer gpa.destroy(c);
  c.*=try.init(&z.writer,window,.zlib,.fastest);
  try c.writer.writeAll(raw);
  try c.finish();
  // the finished file, grown in memory
  var file:Allocating=try.initCapacity(gpa,z.written().len+64);
  errdefer file.deinit();
  try file.writer.writeAll(signature);
  // IHDR's body: width, height, depth, colour type, then three zeros
  var head:[13]u8=undefined;
  writeInt(u32,head[0..4],w,.big);
  writeInt(u32,head[4..8],h,.big);
  head[8..].*=.{depth,rgb,0,0,0};
  try chunk(&file.writer,"IHDR",&head);
  try chunk(&file.writer,"IDAT",z.written());
  try chunk(&file.writer,"IEND","");
  return file.toOwnedSlice();
}
/// writes one chunk to `out`: its length, its four-letter `kind`, its
/// `data`, then the checksum of kind and data
fn chunk(out:*Writer,kind:*const m.Vice(u8,4),data:[]const u8)Writer.Error!void{
  try out.writeInt(u32,@intCast(data.len),.big);
  try out.writeAll(kind);
  try out.writeAll(data);
  // the checksum, over the kind and the data
  var crc=Crc32.init();
  crc.update(kind);
  crc.update(data);
  try out.writeInt(u32,crc.final(),.big);
}
/// a picture read back: `w`×`h` pixels of RGB, row by row from the top
pub const Image=struct{
  /// its width, in pixels
  w:u32,
  /// its height, in pixels
  h:u32,
  /// its pixels, 3 bytes each (the caller frees them)
  rgb:[]u8,
  /// frees its pixels
  pub fn deinit(im:Image,gpa:Allocator)void{gpa.free(im.rgb);}
};
/// `px` (`w`×`h`, 4 bytes a pixel) at 1/`k` its size each side, each
/// pixel the mean of the `k`×`k` it stands for (owned): a frame made small
pub fn shrink(gpa:Allocator,px:[]const u8,w:u32,h:u32,k:u32)Allocator.Error![]u8{
  // the shrunk size, and its pixels
  const sw:usize=w/k;
  const sh:usize=h/k;
  const out=try gpa.alloc(u8,sw*sh*4);
  for(0..sh)|y|for(0..sw)|x|for(0..4)|c|{
    // the pixels' channel summed
    var sum:u32=0;
    for(0..k)|dy|for(0..k)|dx|{
      sum+=px[((k*y+dy)*w+(k*x+dx))*4+c];
    };
    out[(y*sw+x)*4+c]=@intCast(sum/(k*k));
  };
  return out;
}
/// what reading a PNG back can fail with: out of memory, or a file not as
/// `encode` writes them (8-bit RGB, no interlace, one IDAT, Sub-filtered)
pub const DecodeError=Allocator.Error||error{NotOurs};
/// the largest side a picture read back may have (pixels), so a broken
/// header never asks for the world
const maxSide=4096;
/// reads back a PNG `encode` wrote: its pixels as RGB. Any other kind of
/// PNG, or a damaged one, is `NotOurs` (a picture shown is never trusted)
pub fn decode(gpa:Allocator,bytes:[]const u8)DecodeError!Image{
  if(bytes.len<8+25 or !eql(u8,bytes[0..8],signature))return error.NotOurs;
  if(!eql(u8,bytes[12..16],"IHDR"))return error.NotOurs;
  // the header: its size, and that it is ours
  const w=readInt(u32,bytes[16..20],.big);
  const h=readInt(u32,bytes[20..24],.big);
  if(w==0 or h==0 or w>maxSide or h>maxSide)return error.NotOurs;
  if(bytes[24]!=depth or bytes[25]!=rgb or bytes[26]!=0 or bytes[27]!=0 or bytes[28]!=0)return error.NotOurs;
  // the IDAT chunk, right after IHDR
  const at=8+25;
  if(bytes.len<at+8)return error.NotOurs;
  const n=readInt(u32,bytes[at..][0..4],.big);
  if(!eql(u8,bytes[at+4..][0..4],"IDAT") or bytes.len<at+8+n)return error.NotOurs;
  // the filtered rows, decompressed
  const row=@as(usize,w)*3+1;
  const raw=try gpa.alloc(u8,row*h);
  defer gpa.free(raw);
  var in:Reader=.fixed(bytes[at+8..][0..n]);
  // the decompressor's window, on the heap (64K)
  const window=try gpa.alloc(u8,flate.max_window_len);
  defer gpa.free(window);
  var d:flate.Decompress=.init(&in,.zlib,window);
  d.reader.readSliceAll(raw)catch{return error.NotOurs;};
  // each row unfiltered: Sub, each byte plus the one a pixel before
  const out=try gpa.alloc(u8,@as(usize,w)*h*3);
  errdefer gpa.free(out);
  for(0..h)|y|{
    // this row's filtered bytes, and its pixels
    const f=raw[y*row..][0..row];
    const o=out[y*w*3..][0..w*3];
    if(f[0]!=sub)return error.NotOurs;
    for(0..w*3)|k|o[k]=f[1+k]+%(if(k>=3)o[k-3]else 0);
  }
  return.{.w=w,.h=h,.rgb=out};
}
test"a PNG written is read back pixel for pixel; one not ours is refused"{
  // the allocator, which finds leaks
  const gpa=testing.allocator;
  // 3×2 RGBA: a few colours
  const px=[_]u8{10,20,30,0,200,100,50,0,255,255,255,0,0,0,0,0,1,2,3,0,250,128,7,0};
  const file=try encode(gpa,3,2,&px,.rgba);
  defer gpa.free(file);
  const im=try decode(gpa,file);
  defer im.deinit(gpa);
  try testing.expectEqual(@as(u32,3),im.w);
  try testing.expectEqual(@as(u32,2),im.h);
  try testing.expectEqualSlices(u8,&.{10,20,30,200,100,50,255,255,255,0,0,0,1,2,3,250,128,7},im.rgb);
  try testing.expectError(error.NotOurs,decode(gpa,"not a png at all, not even close to one"));
  // cut short: refused, never a crash
  try testing.expectError(error.NotOurs,decode(gpa,file[0..file.len/2]));
}
test"a PNG holds its pixels: header, then rows that decompress back"{
  // the allocator, which finds leaks
  const gpa=testing.allocator;
  // 2×2 BGRA: red, green / blue, white
  const px=[_]u8{0,0,255,255,0,255,0,255,255,0,0,255,255,255,255,255};
  // the encoded file
  const png=try encode(gpa,2,2,&px,.bgra);
  defer gpa.free(png);
  try testing.expectEqualStrings(signature,png[0..8]);
  try testing.expectEqualStrings("IHDR",png[12..16]);
  try testing.expectEqual(@as(u32,2),readInt(u32,png[16..20],.big));
  // IDAT follows IHDR (8 + 13 + 4 bytes on)
  const at=8+25;
  // IDAT's length
  const n=readInt(u32,png[at..][0..4],.big);
  try testing.expectEqualStrings("IDAT",png[at+4..][0..4]);
  // a reader over IDAT's compressed body
  var in:Reader=.fixed(png[at+8..][0..n]);
  // the decompressor's window
  var buf:[flate.max_window_len]u8=undefined;
  // the decompressor
  var d:flate.Decompress=.init(&in,.zlib,&buf);
  // the two rows, filter bytes and all
  var rows:[14]u8=undefined;
  try d.reader.readSliceAll(&rows);
  // Sub-filtered: red, then green less red; blue, then white less blue
  try testing.expectEqualSlices(u8,&.{sub,255,0,0,1,255,0,sub,0,0,255,255,255,0},&rows);
  try testing.expectEqualStrings("IEND",png[png.len-8..][0..4]);
}
