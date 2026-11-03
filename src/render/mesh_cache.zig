//! the grown meshes kept on disk between starts: once every mesh is grown
//! and welded, the whole is written to `cache/<game>.meshes` in the
//! gardener's folder; the next start reads it back instead of growing them
//! again, if nothing they are grown from has changed. That is told by a
//! key: a hash of the game itself (its program file, so any change to the
//! code that grows them) and of every sculpt on the shelf. A different key,
//! a file that will not read, or one cut short, and the meshes are grown as
//! ever (and the file written anew). Skin weights and growth records are
//! kept only for the vertices that have any (most have none). Written to a
//! side file first and renamed over, so a start cut short never leaves a
//! half-written cache that reads as whole.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// how this program was built, for its cache file's name
const builtin=@import("builtin");
/// the allocator the read meshes and the sparse lists come from
const Allocator=std.mem.Allocator;
/// the I/O every file call goes through
const Io=std.Io;
/// a directory handle
const Dir=Io.Dir;
/// a file handle
const File=Io.File;
/// the hash the key is made of
const Wyhash=std.hash.Wyhash;
/// a value's bytes
const asBytes=std.mem.asBytes;
/// a slice's bytes
const sliceAsBytes=std.mem.sliceAsBytes;
/// are two byte strings equal?
const eql=std.mem.eql;
/// the last part of a path, for the program's name
const basename=std.fs.path.basename;
/// the program's name without its ending
const stem=std.fs.path.stem;
/// formats into a fixed buffer, for the file's name
const bufPrint=std.fmt.bufPrint;
/// the log, for a cache that will not read or write
const log=std.log;
/// the test harness
const testing=std.testing;
/// the engine package
const engine=lib.engine;
/// all the maths: conversions for the test's vertices
const m=engine.core.math;
/// the welded meshes, as kept
const weld=engine.gfx.weld;
/// the GPU layouts: vertices, skin weights, growth records
const vertex=lib.vertex;
/// the gardener's folder, where the cache lives
const home=lib.home;
/// the gardener's sculpts: the key follows them
const sculpts=lib.sculpts;
/// the folder inside home the cache files go in
pub const folder="cache";
/// the file's first bytes: what it is, and its layout's version
const magic="PSYMSH02".*;
/// how much of a file is read at once while the program is hashed
const hashChunk=1<<22;
/// the file's head: what it is, the key it was written for, and how many
/// of each list follow
const Head=extern struct{
  /// what it is
  magic:[8]u8=magic,
  /// the key it was written for
  key:u64=0,
  /// how many vertices
  verts:u64=0,
  /// how many indices
  indices:u64=0,
  /// how many runs
  runs:u64=0,
  /// how many vertices have skin weights
  skinned:u64=0,
  /// how many vertices have growth records
  grown:u64=0,
  /// how many vertices the skin and growth lists run over (the leading
  /// meshes', which read them: `weld`'s `lead`)
  covered:u64=0,
  /// how many bytes of the tables kept beside them
  extra:u64=0,
};
/// the skin weights of a vertex nothing moves
const blankSkin=vertex.Skin{};
/// the growth record of a vertex not grown along a spline
const blankGrow=vertex.Grow{};
/// the key the meshes grown now would be kept under: the game's program
/// file hashed, then every sculpt on the shelf (null: the program will not
/// read, so nothing is kept)
pub fn key(gpa:Allocator,io:Io)?u64{
  // the program, open to be read
  const f=std.process.openExecutable(io,.{})catch|e|{
    log.warn("mesh cache: the program will not open: {t}",.{e});
    return null;
  };
  defer f.close(io);
  // the hash, fed the program a chunk at a time, then the shelf
  var h=Wyhash.init(0);
  const buf=gpa.alloc(u8,hashChunk) catch return null;
  defer gpa.free(buf);
  // where the next chunk begins
  var at:u64=0;
  while(true){
    // how much of this chunk was read
    const n=f.readPositionalAll(io,buf,at)catch|e|{
      log.warn("mesh cache: the program will not read: {t}",.{e});
      return null;
    };
    h.update(buf[0..n]);
    at+=n;
    if(n<buf.len)break;
  }
  h.update(asBytes(&sculpts.stamp()));
  return h.final();
}
/// the cache file's name for this program and the way it was built (each
/// its own: the game and the tools, debug and release, grow their meshes
/// alike but are not alike, and would write over each other's), in `buf`
pub fn fileName(io:Io,buf:[]u8)?[]const u8{
  // the program's path, and its name
  var path:[std.fs.max_path_bytes]u8=undefined;
  const n=std.process.executablePath(io,&path) catch return null;
  return bufPrint(buf,folder++"/{s}-{t}.meshes",.{stem(basename(path[0..n])),builtin.mode}) catch null;
}
/// the welded meshes kept in `name` under `dir` if it was written for
/// `key`, with the tables beside them read into `extras` (each exactly as
/// long as written); null if there is none, it is another key's, or it
/// will not read whole
pub fn read(gpa:Allocator,io:Io,dir:Dir,name:[]const u8,want:u64,extras:[]const []u8)?weld.Welded{
  // the file (none: nothing kept)
  const f=dir.openFile(io,name,.{}) catch return null;
  defer f.close(io);
  // its head, which must be this layout's and this key's
  var head:Head=undefined;
  if((f.readPositionalAll(io,asBytes(&head),0) catch return null)!=@sizeOf(Head))return null;
  if(!eql(u8,&head.magic,&magic) or head.key!=want)return null;
  // the tables kept beside the meshes must be as long as asked
  var extra:u64=0;
  for(extras)|x|extra+=x.len;
  if(head.extra!=extra)return null;
  return readBody(gpa,io,f,head,extras)catch|e|{
    log.warn("mesh cache {s}: {t}: growing them again",.{name,e});
    return null;
  };
}
/// what a cache file may fail with as its body is read
const ReadError=Allocator.Error||File.ReadPositionalError||error{CutShort};
/// reads a cache file's body after its head: the meshes, then the tables
fn readBody(gpa:Allocator,io:Io,f:File,head:Head,extras:[]const []u8)ReadError!weld.Welded{
  // what comes out, freed again if the file is not whole
  var w=weld.Welded{};
  errdefer w.deinit(gpa);
  w.runs=try gpa.alloc(weld.Run,head.runs);
  try w.v.resize(gpa,head.verts);
  try w.indices.resize(gpa,head.indices);
  if(head.covered>head.verts)return error.CutShort;
  try w.skin.resize(gpa,head.covered);
  @memset(w.skin.items,blankSkin);
  try w.grow.resize(gpa,head.covered);
  @memset(w.grow.items,blankGrow);
  // where the next section begins
  var at:u64=@sizeOf(Head);
  try section(io,f,&at,sliceAsBytes(w.runs));
  try section(io,f,&at,sliceAsBytes(w.v.items));
  try section(io,f,&at,sliceAsBytes(w.indices.items));
  try scatter(vertex.Skin,gpa,io,f,&at,head.skinned,w.skin.items);
  try scatter(vertex.Grow,gpa,io,f,&at,head.grown,w.grow.items);
  for(extras)|x|try section(io,f,&at,x);
  return w;
}
/// reads `out` whole from `at` on, moving `at` past it
fn section(io:Io,f:File,at:*u64,out:[]u8)ReadError!void{
  if((try f.readPositionalAll(io,out,at.*))!=out.len)return error.CutShort;
  at.*+=out.len;
}
/// reads `n` kept entries (their vertices, then their values) and puts
/// each back at its vertex in `all`
fn scatter(comptime T:type,gpa:Allocator,io:Io,f:File,at:*u64,n:u64,all:[]T)ReadError!void{
  // which vertices, and what each holds
  const idx=try gpa.alloc(u32,n);
  defer gpa.free(idx);
  const val=try gpa.alloc(T,n);
  defer gpa.free(val);
  try section(io,f,at,sliceAsBytes(idx));
  try section(io,f,at,sliceAsBytes(val));
  for(idx,val)|i,v|{
    if(i>=all.len)return error.CutShort;
    all[i]=v;
  }
}
/// keeps `w` and the tables beside it (`extras`) in `name` under `dir`,
/// written for `key`: to a side file, renamed over the old one once whole.
/// A failure only costs the next start its quickness.
pub fn write(gpa:Allocator,io:Io,dir:Dir,name:[]const u8,want:u64,w:*const weld.Welded,extras:[]const []const u8)void{
  // the side file's name
  var buf:[std.fs.max_path_bytes]u8=undefined;
  const side=bufPrint(&buf,"{s}.part",.{name}) catch return;
  if(std.fs.path.dirname(name))|d|dir.createDirPath(io,d)catch|e|return log.warn("mesh cache {s}: {t}",.{d,e});
  writeSide(gpa,io,dir,side,want,w,extras)catch|e|{
    log.warn("mesh cache {s}: {t}",.{side,e});
    dir.deleteFile(io,side)catch{};
    return;
  };
  Dir.rename(dir,side,dir,name,io)catch|e|{
    log.warn("mesh cache {s}: {t}",.{name,e});
    dir.deleteFile(io,side)catch{};
  };
}
/// what writing a cache file may fail with
const WriteError=Allocator.Error||File.OpenError||File.WritePositionalError;
/// writes the whole cache file `path`: head, meshes, the kept skin and
/// growth entries, the tables
fn writeSide(gpa:Allocator,io:Io,dir:Dir,path:[]const u8,want:u64,w:*const weld.Welded,extras:[]const []const u8)WriteError!void{
  // the file, made fresh
  const f=try dir.createFile(io,path,.{});
  defer f.close(io);
  // the vertices with skin weights, and with growth records
  var skinned=try keptOf(vertex.Skin,gpa,w.skin.items,blankSkin);
  defer skinned.deinit(gpa);
  var grown=try keptOf(vertex.Grow,gpa,w.grow.items,blankGrow);
  defer grown.deinit(gpa);
  // the head
  var head=Head{.key=want,.verts=w.v.items.len,.indices=w.indices.items.len,.runs=w.runs.len,.skinned=skinned.idx.len,.grown=grown.idx.len,.covered=w.skin.items.len};
  for(extras)|x|head.extra+=x.len;
  // where the next section goes
  var at:u64=0;
  for([_][]const u8{
    asBytes(&head),sliceAsBytes(w.runs),sliceAsBytes(w.v.items),sliceAsBytes(w.indices.items),
    sliceAsBytes(skinned.idx),sliceAsBytes(skinned.val),sliceAsBytes(grown.idx),sliceAsBytes(grown.val),
  })|s|{
    try f.writePositionalAll(io,s,at);
    at+=s.len;
  }
  for(extras)|x|{
    try f.writePositionalAll(io,x,at);
    at+=x.len;
  }
}
/// the entries of a list that are not blank: which, and what they hold
fn Kept(comptime T:type)type{
  return struct{
    /// the vertices that hold one
    idx:[]u32,
    /// what each holds
    val:[]T,
    /// lets both go
    fn deinit(k:*@This(),gpa:Allocator)void{
      gpa.free(k.idx);
      gpa.free(k.val);
    }
  };
}
/// the entries of `all` not bit for bit `blank`
fn keptOf(comptime T:type,gpa:Allocator,all:[]const T,blank:T)Allocator.Error!Kept(T){
  // how many there are
  var n:usize=0;
  for(all)|*x|{
    if(!eql(u8,asBytes(x),asBytes(&blank)))n+=1;
  }
  // the lists, filled in order
  const idx=try gpa.alloc(u32,n);
  errdefer gpa.free(idx);
  const val=try gpa.alloc(T,n);
  // how many are in so far
  var k:usize=0;
  for(all,0..)|*x,i|if(!eql(u8,asBytes(x),asBytes(&blank))){
    idx[k]=@intCast(i);
    val[k]=x.*;
    k+=1;
  };
  return.{.idx=idx,.val=val};
}
test"meshes kept come back exactly, only for their own key"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  const io=testing.io;
  // a folder of its own to keep them in
  var tmp=testing.tmpDir(.{});
  defer tmp.cleanup();
  // four vertices, one skinned, one grown, the lists over the first three
  // only; two runs; six indices
  var w=weld.Welded{};
  defer w.deinit(gpa);
  for(0..4)|i|try w.v.append(gpa,.{.pos=.{m.f(i),0,0},.nrm=.{0,1,0},.col=.{.r=1,.g=2,.b=3,.a=4},.tu=.{0,0,0},.part=@intCast(i)});
  try w.skin.appendNTimes(gpa,blankSkin,3);
  w.skin.items[2]=.{.bones=7,.weights=.{255,0,0,0}};
  try w.grow.appendNTimes(gpa,blankGrow,3);
  w.grow.items[1]=.{.at=.{0.5,0.25,0,1}};
  try w.indices.appendSlice(gpa,&.{0,1,2,2,1,3});
  w.runs=try gpa.dupe(weld.Run,&.{.{.count=3,.verts=3},.{.first=3,.count=3,.base=0,.verts=4,.early=3}});
  // a table beside them, and room for it to come back into
  const table=[_]u64{11,22,33};
  var back:[3]u64=@splat(0);
  write(gpa,io,tmp.dir,"cache/test.meshes",0xABC,&w,&.{asBytes(&table)});
  try testing.expect(read(gpa,io,tmp.dir,"cache/test.meshes",0xABD,&.{asBytes(&back)})==null);
  var got=read(gpa,io,tmp.dir,"cache/test.meshes",0xABC,&.{asBytes(&back)}) orelse return error.TestUnexpectedResult;
  defer got.deinit(gpa);
  try testing.expectEqualSlices(u8,sliceAsBytes(w.v.items),sliceAsBytes(got.v.items));
  try testing.expectEqualSlices(u8,sliceAsBytes(w.skin.items),sliceAsBytes(got.skin.items));
  try testing.expectEqualSlices(u8,sliceAsBytes(w.grow.items),sliceAsBytes(got.grow.items));
  try testing.expectEqualSlices(u32,w.indices.items,got.indices.items);
  try testing.expectEqualSlices(u8,sliceAsBytes(w.runs),sliceAsBytes(got.runs));
  try testing.expectEqualSlices(u64,&table,&back);
  // a table of another length is another layout: not read
  var short:[2]u64=undefined;
  try testing.expect(read(gpa,io,tmp.dir,"cache/test.meshes",0xABC,&.{asBytes(&short)})==null);
}
