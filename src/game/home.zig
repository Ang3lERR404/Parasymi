//! where the gardener's files live: `%LOCALAPPDATA%\Parasymi` (the strings,
//! the controls, the options and `saves/`), made on first start. Opened once
//! at startup by main (`open`); until then (headless tests) the working
//! directory stands in.
//!
//! The strings and controls ship inside the game (`stock` writes them out):
//! a copy the gardener never touched carries a stamp of its own contents
//! and is replaced when the game's version changes; an edited one is kept,
//! and whatever it leaves out falls back to the game's.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Dir = Io.Dir;
const Environ = std.process.Environ;
const Wyhash = std.hash.Wyhash;
const startsWith = std.mem.startsWith;
const eql = std.mem.eql;
const parseInt = std.fmt.parseInt;
const log = std.log;
const testing = std.testing;

// decision: a file path, not player-facing text, so not in the strings
// (which live inside this folder and are read after it is found).
pub const NAME = "Parasymi";
const ENV = "LOCALAPPDATA";
/// the folder (inside home) holding the saved gardens
pub const SAVES = "saves";
/// a stock file's first line: this, then the hash of everything after it
const STAMP = "# stock ";
/// cfg files are at most this large
const MAX_FILE:usize = 1 << 20;

/// the gardener's folder; the working directory until `open`.
// decision: one process-wide handle, set once at startup like `txt.s`.
var opened:?Dir = null;

pub fn dir() Dir { return opened orelse .cwd(); }

pub const Error = error{NoHome};

/// finds (making it if need be) the gardener's folder and its `saves/`.
/// Without `LOCALAPPDATA` (not Windows) the working directory serves.
pub fn open(io:Io, env:*const Environ.Map) Error!void {
  const base = env.get(ENV) orelse {
    log.warn("{s} is not set: keeping files in the working directory", .{ENV});
    return makeSaves(io);
  };
  var root = Dir.openDirAbsolute(io, base, .{}) catch |e| {
    log.err("{s}: {t}", .{base, e});
    return error.NoHome;
  };
  defer root.close(io);
  root.createDirPath(io, NAME) catch |e| {
    log.err("{s}\\{s}: {t}", .{base, NAME, e});
    return error.NoHome;
  };
  opened = root.openDir(io, NAME, .{}) catch |e| {
    log.err("{s}\\{s}: {t}", .{base, NAME, e});
    return error.NoHome;
  };
  log.info("files in {s}\\{s}", .{base, NAME});
  return makeSaves(io);
}

fn makeSaves(io:Io) Error!void {
  dir().createDirPath(io, SAVES) catch |e| {
    log.err("{s}: {t}", .{SAVES, e});
    return error.NoHome;
  };
}

pub fn close(io:Io) void {
  if (opened) |d| d.close(io);
  opened = null;
}

/// a file the game ships (`default`, as built): makes `path` from it when
/// missing, refreshes an untouched copy that is out of date, and returns
/// the file's text (owned), or a copy of `default` when it cannot be read.
pub fn stock(gpa:Allocator, io:Io, path:[]const u8, default:[]const u8) Allocator.Error![]u8 {
  const have = dir().readFileAlloc(io, path, gpa, .limited(MAX_FILE)) catch |e| switch (e) {
    error.OutOfMemory => return error.OutOfMemory,
    error.FileNotFound => {
      write(io, path, default);
      return gpa.dupe(u8, default);
    },
    else => {
      log.warn("{s}: {t}: using the game's own", .{path, e});
      return gpa.dupe(u8, default);
    },
  };
  if (untouched(have)) |body| if (!eql(u8, body, default)) {
    gpa.free(have);
    write(io, path, default);
    return gpa.dupe(u8, default);
  };
  return have;
}

/// the contents after the stamp, if `text` is still exactly as stamped.
fn untouched(text:[]const u8) ?[]const u8 {
  if (!startsWith(u8, text, STAMP)) return null;
  const nl = std.mem.indexOfScalar(u8, text, '\n') orelse return null;
  const hash = parseInt(u64, std.mem.trim(u8, text[STAMP.len..nl], " \r"), 16) catch return null;
  const body = text[nl + 1 ..];
  return if (Wyhash.hash(0, body) == hash) body else null;
}

/// writes `body` under a stamp of itself (a failure only costs the copy).
fn write(io:Io, path:[]const u8, body:[]const u8) void {
  var f = dir().createFile(io, path, .{}) catch |e| {
    log.warn("{s}: {t}", .{path, e});
    return;
  };
  defer f.close(io);
  var buf:[STAMP.len + 18]u8 = undefined;
  const head = std.fmt.bufPrint(&buf, STAMP ++ "{x:0>16}\n", .{Wyhash.hash(0, body)}) catch unreachable;
  f.writePositionalAll(io, head, 0) catch |e| return log.warn("{s}: {t}", .{path, e});
  f.writePositionalAll(io, body, head.len) catch |e| return log.warn("{s}: {t}", .{path, e});
}

/// copies `path` from the working directory into home when home has none
/// (files kept beside the game before it moved them here).
pub fn adopt(io:Io, path:[]const u8, to:[]const u8) void {
  const d = opened orelse return;
  d.access(io, to, .{}) catch |e| switch (e) {
    error.FileNotFound => Dir.copyFile(.cwd(), path, d, to, io, .{}) catch return,
    else => {},
  };
}

test "a stock file is refreshed only while untouched" {
  var buf:[64]u8 = undefined;
  const body = "a = 1\n";
  const stamped = try std.fmt.bufPrint(&buf, STAMP ++ "{x:0>16}\n" ++ body, .{Wyhash.hash(0, body)});
  try testing.expectEqualStrings(body, untouched(stamped).?);
  // edited after stamping: kept as the gardener left it
  stamped[stamped.len - 2] = '2';
  try testing.expect(untouched(stamped) == null);
  try testing.expect(untouched(body) == null);
}
