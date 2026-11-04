//! where the gardener's files live: `%LOCALAPPDATA%\Parasymi` (the strings,
//! the controls, the options and `saves/`), made on first start. Opened once
//! at startup by main (`open`); until then (headless tests) the working
//! directory stands in.
//!
//! The strings and controls ship inside the game (`stock` writes them out):
//! a copy the gardener never touched carries a stamp of its own contents
//! and is replaced when the game's version changes; an edited one is kept,
//! and whatever it leaves out falls back to the game's.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator a read file's text comes from
const Allocator=std.mem.Allocator;
/// the I/O interface every file call goes through
const Io=std.Io;
/// a directory handle
const Dir=Io.Dir;
/// the process's environment, where `LOCALAPPDATA` is found
const Environ=std.process.Environ;
/// the hash a stock file's stamp is made of
const Wyhash=std.hash.Wyhash;
/// does text begin with a prefix?
const startsWith=std.mem.startsWith;
/// are two strings equal?
const eql=std.mem.eql;
/// reads a number, for the stamp's hash
const parseInt=std.fmt.parseInt;
/// the log, for warnings about files
const log=std.log;
/// the test harness
const testing=std.testing;
/// finds a byte, for the stamp line's end
const indexOfScalar=std.mem.indexOfScalar;
/// strips characters from both ends
const trim=std.mem.trim;
/// formats into a fixed buffer, for the stamp line
const bufPrint=std.fmt.bufPrint;
// decision: a file path, not player-facing text, so not in the strings
// (which live inside this folder and are read after it is found).
/// the folder's name inside `%LOCALAPPDATA%`
pub const name="Parasymi";
/// the environment variable naming where the folder goes
const envName="LOCALAPPDATA";
/// the folder (inside home) holding the saved gardens
pub const saves="saves";
/// a stock file's first line: this, then the hash of everything after it
const stamp="# stock ";
/// cfg files are at most this large
const maxFile:usize=1<<20;
/// the gardener's folder; the working directory until `open`.
// decision: one process-wide handle, set once at startup like `txt.s`.
var opened:?Dir=null;
/// the gardener's folder's full path, for telling where files went
var pathBuf:[maxPath]u8=undefined;
/// how much of `pathBuf` is real (0: the working directory)
var pathLen:usize=0;
/// the longest folder path kept for telling (bytes)
const maxPath=512;
/// the gardener's folder's full path, as found by `open` ("." before it,
/// or when the working directory serves)
pub fn where()[]const u8{return if(pathLen==0)"." else pathBuf[0..pathLen];}
/// the gardener's folder, or the working directory before `open`
pub fn dir()Dir{return opened orelse .cwd();}
/// the gardener's folder could not be found or made
pub const Error=error{NoHome};
/// finds (making it if need be) the gardener's folder and its `saves/`.
/// Without `LOCALAPPDATA` (not Windows) the working directory serves.
pub fn open(io:Io,env:*const Environ.Map)Error!void{
  // where the folder goes; unset, and the working directory serves
  const base=env.get(envName)orelse{
    log.warn("{s} is not set: keeping files in the working directory",.{envName});
    return makeSaves(io);
  };
  // the parent folder, open while the game's folder is made in it
  var root=Dir.openDirAbsolute(io,base,.{})catch|e|{
    log.err("{s}: {t}",.{base,e});
    return error.NoHome;
  };
  defer root.close(io);
  root.createDirPath(io,name)catch|e|{
    log.err("{s}\\{s}: {t}",.{base,name,e});
    return error.NoHome;
  };
  opened=root.openDir(io,name,.{})catch|e|{
    log.err("{s}\\{s}: {t}",.{base,name,e});
    return error.NoHome;
  };
  log.info("files in {s}\\{s}",.{base,name});
  pathLen=if(bufPrint(&pathBuf,"{s}\\{s}",.{base,name}))|p|p.len else|_|0;
  return makeSaves(io);
}
/// makes the `saves/` folder inside home if it is missing
fn makeSaves(io:Io)Error!void{
  dir().createDirPath(io,saves)catch|e|{
    log.err("{s}: {t}",.{saves,e});
    return error.NoHome;
  };
}
/// lets go of the gardener's folder; the working directory serves again
pub fn close(io:Io)void{
  if(opened)|d|d.close(io);
  opened=null;
}
/// a file the game ships (`default`, as built): makes `path` from it when
/// missing, refreshes an untouched copy that is out of date, and returns
/// the file's text (owned), or a copy of `default` when it cannot be read.
pub fn stock(gpa:Allocator,io:Io,path:[]const u8,default:[]const u8)Allocator.Error![]u8{
  // what is on disk now, owned; missing or unreadable, the game's own
  const have=dir().readFileAlloc(io,path,gpa,.limited(maxFile))catch|e|switch(e){
    error.OutOfMemory=>return error.OutOfMemory,
    error.FileNotFound=>{
      write(io,path,default);
      return gpa.dupe(u8,default);
    },
    else=>{
      log.warn("{s}: {t}: using the game's own",.{path,e});
      return gpa.dupe(u8,default);
    },
  };
  if(untouched(have))|body|if(!eql(u8,body,default)){
    gpa.free(have);
    write(io,path,default);
    return gpa.dupe(u8,default);
  };
  return have;
}
/// the contents after the stamp, if `text` is still exactly as stamped.
fn untouched(text:[]const u8)?[]const u8{
  if(!startsWith(u8,text,stamp))return null;
  // where the stamp line ends, the hash it names, and what follows it
  const nl=indexOfScalar(u8,text,'\n') orelse return null;
  const hash=parseInt(u64,trim(u8,text[stamp.len..nl]," \r"),16) catch return null;
  const body=text[nl+1..];
  return if(Wyhash.hash(0,body)==hash)body else null;
}
/// puts the game's own `default` back as `path`, stamped, so it is
/// refreshed with the game again (an edited copy given up)
pub fn restock(io:Io,path:[]const u8,default:[]const u8)void{write(io,path,default);}
/// writes `body` under a stamp of itself (a failure only costs the copy).
fn write(io:Io,path:[]const u8,body:[]const u8)void{
  // the file being written, made fresh
  var f=dir().createFile(io,path,.{})catch|e|{
    log.warn("{s}: {t}",.{path,e});
    return;
  };
  defer f.close(io);
  // room for the stamp line, and the stamp itself
  var buf:[stamp.len+18]u8=undefined;
  const head=bufPrint(&buf,stamp++"{x:0>16}\n",.{Wyhash.hash(0,body)}) catch unreachable;
  f.writePositionalAll(io,head,0)catch|e|return log.warn("{s}: {t}",.{path,e});
  f.writePositionalAll(io,body,head.len)catch|e|return log.warn("{s}: {t}",.{path,e});
}
/// copies `path` from the working directory into home when home has none
/// (files kept beside the game before it moved them here).
pub fn adopt(io:Io,path:[]const u8,to:[]const u8)void{
  // home; not opened, and there is nowhere to copy to
  const d=opened orelse return;
  d.access(io,to,.{})catch|e|switch(e){
    error.FileNotFound=>Dir.copyFile(.cwd(),path,d,to,io,.{}) catch return,
    else=>{},
  };
}
test"a stock file is refreshed only while untouched"{
  // room for a stamped file, its body, and the stamped text
  var buf:[64]u8=undefined;
  const body="a = 1\n";
  const stamped=try bufPrint(&buf,stamp++"{x:0>16}\n"++body,.{Wyhash.hash(0,body)});
  try testing.expectEqualStrings(body,untouched(stamped).?);
  // edited after stamping: kept as the gardener left it
  stamped[stamped.len-2]='2';
  try testing.expect(untouched(stamped)==null);
  try testing.expect(untouched(body)==null);
}
