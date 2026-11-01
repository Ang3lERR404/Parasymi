//! saving and restoring the garden. The world itself is never stored: it is
//! regenerated from the seed, and only what the gardener changed is kept:
//! the wolf and its belly, research, the weave queue, every plant and
//! structure, and resource nodes that were gathered.
//!
//! Each garden is a file of its own in `home.saves` (`<name>.sav`), named
//! by the gardener (`Name.typed`); the timer saves into `auto`.
//!
//! Format: a small header (magic, version, layout fingerprint) followed by
//! plain-old-data records. The fingerprint changes whenever a stored type's
//! size changes, so an incompatible save is refused instead of misread.
//! Structures are the exception: each is its kind's name hash and a
//! `record` of named fields, so a structure or its state gaining, losing or
//! changing a field (or holding a list) keeps older saves loading; one of a
//! kind that is gone is left out.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the bytes and the rebuilt garden come from
const Allocator=std.mem.Allocator;
/// the I/O interface every file call goes through
const Io=std.Io;
/// a value's raw bytes
const asBytes=std.mem.asBytes;
/// are two strings equal?
const eql=std.mem.eql;
/// are two names equal, ignoring case (as Windows does)?
const eqlIgnoreCase=std.ascii.eqlIgnoreCase;
/// may a typed character stand in a name?
const isAlphanumeric=std.ascii.isAlphanumeric;
/// finds a byte, for the marks a name may hold
const indexOfScalar=std.mem.indexOfScalar;
/// does a file name end in `.sav`?
const endsWith=std.mem.endsWith;
/// the path separator, between the saves folder and a file
const sepStr=std.fs.path.sep_str;
/// nanoseconds in a second, for a save's age
const nsPerS=std.time.ns_per_s;
/// the test harness
const testing=std.testing;
/// an enum's tags, for counting the items
const fields=std.meta.fields;
/// a check that holds at compile time
const assert=std.debug.assert;
/// sorts the listed gardens, newest first
const sort=std.mem.sort;
/// formats a save's path into a fixed buffer
const bufPrint=std.fmt.bufPrint;
/// the gardener's folder, where `saves/` lives
const home=lib.home;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, directions, tiles
const m=engine.core.math;
/// the game's random stream, stored so the garden carries on as it would
const Rng=engine.core.rng.Rng;
/// the chunk grid: chunks, their nodes and coordinates
const ck=lib.ck;
/// the world generator, to tell gathered nodes from untouched ones
const gen=lib.gen;
/// the species registry: counts and footprints
const species=lib.species;
/// what can be held: item ids for the hotbar
const items=lib.items;
/// the research tree, stored whole
const prog=lib.progression;
/// the weaving queue, stored whole
const craft=lib.craft;
/// the structures registry: kinds by name, blank structures
const st=lib.structures;
/// named-field records, how structures are stored
const record=lib.record;
/// the player module, for its belly's type
const playerMod=lib.player;
/// the game's state
const play=lib.play;
/// every player-facing string
const txt=lib.txt;
/// the whole running game saved and rebuilt
const Game=play.Game;
/// the wolf's belly, as stored
const Belly=@FieldType(playerMod.Player,"inv");
/// a hotbar slot is stored as its item's id, or this when empty
const noItem:u8=0xff;
/// how many kinds of item there are
const itemCount=fields(items.Item).len;
// every item id must fit below the empty-slot mark
comptime{assert(itemCount<noItem);}
/// where saves were kept before they moved into `home.saves`
pub const legacy="parasymi.sav";
/// a saved garden's file extension, and its scratch copy's while written
pub const ext=".sav";
/// the scratch copy's extension, while it is written
const tmpExt=".tmp";
/// the garden the timer saves into
pub const auto="autosave";
/// the longest name a garden may have, in bytes
pub const maxName=32;
/// what a typed name may hold besides letters and digits (nothing a
/// Windows file name refuses, all in the UI font)
const nameMarks=" -'()!+,.=[]%";
/// the byte `c` stands for in a name, if a name may hold it: a letter, a
/// digit or one of `nameMarks`
pub fn nameChar(c:u21)?u8{
  if(c>0x7e)return null;
  // the character, as a byte
  const b:u8=@intCast(c);
  return if(isAlphanumeric(b) or indexOfScalar(u8,nameMarks,b)!=null)b else null;
}
/// the name prompt's text input: what a name may hold, as long as one may be
pub const Typed=lib.engine.ui.textInput.TextInput(maxName,nameChar);
/// what was typed into `t` as a garden's name, if it can be one (`Name.typed`)
pub fn named(t:*const Typed)?Name{
  // the text, as a name
  const n=Name.of(t.slice()) orelse return null;
  return n.typed();
}
/// the longest path a save's file can have, scratch extension and all
const maxPath=home.saves.len+1+maxName+ext.len+tmpExt.len;
/// the first four bytes of every save
const magic="PRSY".*;
/// the stored layout's version: bumped whenever one changes
const version:u32=27;
/// max save file size (64 MB): a garden with millions of plants will never
/// approach this; anything larger is almost certainly a corrupt or malicious file.
const maxSave:usize=64<<20;
/// everything saving and loading can fail with; file-system errors are
/// folded into these at the boundary.
pub const Error=error{
  /// there is no save file yet
  NoSave,
  /// the file is there but cannot be read
  SaveUnreadable,
  /// the file cannot be written (or deleted)
  SaveUnwritable,
  /// the file is not a save at all (no magic)
  NotASave,
  /// written by a build whose stored layout differs
  IncompatibleSave,
  /// the file is cut short or holds what cannot be
  CorruptSave,
}||Allocator.Error;
/// one plant, without its runtime links (rebuilt on load).
const PlantRec=extern struct{
  /// its tile column
  x:i32,
  /// its tile row
  y:i32,
  /// where it stands across (a floater's own free point, m)
  ax:f32,
  /// and along
  az:f32,
  /// its species id
  sp:u32,
  /// how grown it is, 0..1
  growth:f32,
  /// its own growing time (s; 0: its species')
  span:f32,
  /// the mana it holds
  mana:f32,
  /// its health, 0..1
  health:f32,
  /// its seed, the per-plant variation
  seed:f32,
  /// the flow through it
  flow:f32,
  /// the essence it has ripened
  essence:f32,
  /// the way it faces, 0..3
  dir:u32,
};
/// one chunk whose resource nodes differ from what the generator made.
const NodesRec=struct{
  /// which chunk
  at:ck.Coord,
  /// what is left in each of its tiles' nodes
  res:[ck.tileCount]ck.Res,
};
/// what opens every save: the magic, the version, the layout fingerprint
/// and the seed the world regrows from
const Header=extern struct{
  /// always `magic`
  magic:m.Vice(u8,4),
  /// the build's `version`
  version:u32,
  /// the build's `layoutFingerprint`
  layout:u64,
  /// the world's seed
  seed:u64,
};
/// changes whenever any stored record's layout changes.
const layoutFingerprint=blk:{
  // the hash so far, folded with each stored size
  var h:u64=0xA5;
  for([_]usize{
    @sizeOf(PlantRec),@sizeOf(NodesRec),
    @sizeOf(prog.Progression),@sizeOf(craft.Crafter),@sizeOf(Belly),
    @sizeOf(Rng),species.count,
  })|n|h=h*%0x100000001B3^n;
  break:blk h;
};
/// the bytes being written, value by value
const Writer=struct{
  /// the allocator they grow with
  gpa:Allocator,
  /// the bytes so far
  buf:std.ArrayList(u8)=.empty,
  /// a value's raw bytes onto the end
  fn put(w:*Writer,comptime T:type,v:T)Allocator.Error!void{
    try w.buf.appendSlice(w.gpa,asBytes(&v));
  }
};
/// a cursor over a save's bytes
const Reader=struct{
  /// the bytes being read
  data:[]const u8,
  /// how far into them the next read starts
  pos:usize=0,
  /// the next `T`, raw; corrupt if it would run past the end
  fn get(r:*Reader,comptime T:type)Error!T{
    if(r.pos+@sizeOf(T)>r.data.len)return error.CorruptSave;
    // the value being read
    var v:T=undefined;
    @memcpy(asBytes(&v),r.data[r.pos..][0..@sizeOf(T)]);
    r.pos+=@sizeOf(T);
    return v;
  }
};
/// the garden as bytes (owned): the header, the gardener and what it
/// knows, every plant and structure, and the gathered chunks' nodes
pub fn encode(gpa:Allocator,g:*const Game)Allocator.Error![]u8{
  // the bytes being written
  var w:Writer=.{.gpa=gpa};
  errdefer w.buf.deinit(gpa);
  try w.put(Header,.{.magic=magic,.version=version,.layout=layoutFingerprint,.seed=g.world.seed});
  // the gardener and what it knows
  try w.put(Rng,g.rng);
  try w.put(f32,g.sky.tod);
  try w.put(f64,g.time);
  try w.put(u32,@intCast(g.hot));
  // the hotbar, each slot an item id or `noItem`
  var bar:[play.barSlots]u8=undefined;
  for(g.bar,&bar)|b,*o|o.*=if(b)|it|@intFromEnum(it)else noItem;
  try w.put([play.barSlots]u8,bar);
  try w.put(m.Dir,g.placeDir);
  try w.put(m.V3,g.player.pos);
  try w.put(f32,g.player.facing);
  try w.put(Belly,g.player.inv);
  try w.put(craft.Crafter,g.weave);
  try w.put(prog.Progression,g.prog);
  try w.put(lib.unforming.Unforming,g.unforming);
  // everything it grew
  // the plant list's columns
  const s=g.plants.list.slice();
  try w.put(u32,@intCast(g.plants.len()));
  for(0..g.plants.len())|i|try w.put(PlantRec,.{
    .x=s.items(.x)[i],.y=s.items(.y)[i],.ax=s.items(.at)[i][0],.az=s.items(.at)[i][2],.sp=@intFromEnum(s.items(.sp)[i]),
    .growth=s.items(.growth)[i],.span=s.items(.span)[i],.mana=s.items(.mana)[i],.health=s.items(.health)[i],
    .seed=s.items(.seed)[i],.flow=s.items(.flow)[i],.essence=s.items(.essence)[i],
    .dir=s.items(.dir)[i],
  });
  try w.put(u32,@intCast(g.structs.list.items.len));
  for(g.structs.list.items)|*it|{
    try w.put(u32,record.nameHash(@tagName(it.kind())));
    try record.writeFramed(st.Structure,gpa,&w.buf,it);
  }
  // gathered resource nodes (only chunks that differ from generation)
  // the chunks whose nodes were gathered from
  var touched:std.ArrayList(*const ck.Chunk)=.empty;
  defer touched.deinit(gpa);
  // the walk over every chunk in the world
  var it=g.world.map.valueIterator();
  while(it.next())|c|if(gathered(g.world.seed,c.*))try touched.append(gpa,c.*);
  try w.put(u32,@intCast(touched.items.len));
  for(touched.items)|c|try w.put(NodesRec,.{.at=c.at,.res=c.res});
  return w.buf.toOwnedSlice(gpa);
}
/// whether any of a chunk's nodes differ from what the generator made
fn gathered(seed:u64,c:*const ck.Chunk)bool{
  for(0..ck.tileCount)|t|{
    // the tile's place in the world
    const wx,const wy=c.tileOf(t);
    // what the generator made there
    const s=gen.sample(seed,wx,wy);
    if(s.res!=c.res[t])return true;
  }
  return false;
}
/// rebuild a game from bytes produced by `encode`.
pub fn decode(gpa:Allocator,data:[]const u8)Error!Game{
  // the cursor over the bytes
  var r:Reader=.{.data=data};
  // the header
  const h=try r.get(Header);
  if(!eql(u8,&h.magic,&magic))return error.NotASave;
  if(h.version!=version or h.layout!=layoutFingerprint)return error.IncompatibleSave;
  // a fresh garden from the saved seed, filled in below
  var g=try Game.init(gpa,h.seed);
  errdefer g.deinit();
  g.rng=try r.get(Rng);
  g.sky.tod=try r.get(f32);
  g.time=try r.get(f64);
  g.hot=try r.get(u32);
  if(g.hot>=play.barSlots)return error.CorruptSave;
  for(try r.get([play.barSlots]u8),&g.bar)|b,*o|o.*=if(b==noItem)null
    else if(b<itemCount)@enumFromInt(b)
    else return error.CorruptSave;
  g.placeDir=try r.get(m.Dir);
  g.player.pos=try r.get(m.V3);
  g.player.facing=try r.get(f32);
  g.player.inv=try r.get(Belly);
  g.weave=try r.get(craft.Crafter);
  g.prog=try r.get(prog.Progression);
  g.unforming=try r.get(lib.unforming.Unforming);
  g.cam.target=g.player.pos;
  // how many plants are stored
  const plants=try r.get(u32);
  for(0..plants)|_|{
    // the stored plant
    const p=try r.get(PlantRec);
    if(p.sp>=species.count or p.dir>=m.dirs.len)return error.CorruptSave;
    // its species
    const sp:species.Id=@enumFromInt(p.sp);
    try ensureFootprint(&g,p.x,p.y,species.get(sp).size);
    _=try g.plants.placeNear(gpa,&g.world,m.v3(p.ax,0,p.az),.{
      .x=p.x,.y=p.y,.chunk=undefined,.tile=undefined,.sp=sp,
      .growth=p.growth,.span=p.span,.mana=p.mana,.health=p.health,.seed=p.seed,
      .flow=p.flow,.essence=p.essence,.dir=@intCast(p.dir),
    });
  }
  // how many structures are stored
  const structs=try r.get(u32);
  for(0..structs)|_|{
    // its kind's name hash
    const kh=try r.get(u32);
    // a cursor at the structure's frame, and its bytes
    var in:record.In=.{.b=r.data,.pos=r.pos};
    const body=try in.frame();
    r.pos=in.pos;
    // a kind no longer grown is left out
    // its kind; one no longer grown is left out
    const k=st.kindByName(kh) orelse continue;
    // a blank structure of that kind, read over
    var s=st.blank(k);
    errdefer s.deinit(gpa);
    try record.read(st.Structure,gpa,body,&s);
    try ensureFootprint(&g,s.x,s.y,s.def().size);
    // restored as saved (inventory, per-kind data). If it does not fit the
    // save is corrupt (the world is regenerated from the same seed, so the
    // tile was valid when saved).
    if(!try g.structs.restore(gpa,&g.world,s))return error.CorruptSave;
  }
  g.structs.relink();
  // how many gathered chunks are stored
  const nodes=try r.get(u32);
  for(0..nodes)|_|{
    // the stored chunk's nodes
    const n=try r.get(NodesRec);
    // the chunk, made if it is not streamed in yet
    const c=try g.world.ensure(n.at);
    c.res=n.res;
  }
  g.prog.say(txt.s.msg.remembers,.{});
  return g;
}
/// streams in every chunk a footprint `size` tiles across at `x, y` touches
fn ensureFootprint(g:*Game,x:i32,y:i32,size:u8)Allocator.Error!void{
  // how far the footprint's far corner is
  const far=@as(i32,size)-1;
  for([_]m.Vice(i32,2){.{x,y},.{x+far,y},.{x,y+far},.{x+far,y+far}})|t|{
    _=try g.world.ensure(ck.Coord.ofTile(t[0],t[1]));
  }
}
/// a saved garden's file name, without its folder or `ext`
pub const Name=struct{
  /// the name's bytes; only the first `len` are real
  buf:[maxName]u8=undefined,
  /// how many bytes the name holds
  len:u8=0,
  /// a name of `s`, if it is not blank and fits
  pub fn of(s:[]const u8)?Name{
    if(s.len==0 or s.len>maxName)return null;
    // the name being made
    var n:Name=.{.len=@intCast(s.len)};
    @memcpy(n.buf[0..s.len],s);
    return n;
  }
  /// the name's bytes, as a slice
  pub fn slice(n:*const Name)[]const u8{return n.buf[0..n.len];}
  /// whether the name is exactly `s`
  pub fn is(n:*const Name,s:[]const u8)bool{return eql(u8,n.slice(),s);}
  /// names the same file (Windows ignores case)
  pub fn same(n:*const Name,o:Name)bool{return eqlIgnoreCase(n.slice(),o.slice());}
  /// `c` typed at the end, if a name may hold it and there is room
  pub fn put(n:*Name,c:u21)void{
    if(n.len==maxName)return;
    n.buf[n.len]=nameChar(c) orelse return;
    n.len+=1;
  }
  /// the last character taken back
  pub fn erase(n:*Name)void{n.len-|=1;}
  /// what was typed as a garden's name: not blank, never the autosave's,
  /// and nothing Windows would strip from a file name's ends
  pub fn typed(n:*const Name)?Name{
    // the typed name
    const s=n.slice();
    if(s.len==0 or s[0]==' ' or s[s.len-1]==' ' or s[s.len-1]=='.')return null;
    if(eqlIgnoreCase(s,auto))return null;
    return n.*;
  }
};
/// a garden in `home.saves`, as listed: its name and how long ago (s) it
/// was saved, when the list was made.
pub const Entry=struct{
  /// the garden's name
  name:Name,
  /// how long ago it was saved (s)
  age:i64
};
/// lists the saved gardens into `out`, the most recent first.
pub fn list(gpa:Allocator,io:Io,out:*std.ArrayList(Entry))Error!void{
  out.clearRetainingCapacity();
  // the saves folder, open to be walked
  var d=home.dir().openDir(io,home.saves,.{.iterate=true}) catch return error.SaveUnreadable;
  defer d.close(io);
  // the time now, and the walk over the folder
  const now=Io.Clock.real.now(io).nanoseconds;
  var it=d.iterate();
  while(it.next(io) catch return error.SaveUnreadable)|e|{
    if(e.kind!=.file or !endsWith(u8,e.name,ext))continue;
    // the garden's name, the file's details, and how old it is
    const name=Name.of(e.name[0..e.name.len-ext.len]) orelse continue;
    const stat=d.statFile(io,e.name,.{}) catch continue;
    const age:i64=@intCast(@divFloor(now-stat.mtime.nanoseconds,nsPerS));
    try out.append(gpa,.{.name=name,.age=@max(age,0)});
  }
  // newest first
  sort(Entry,out.items,{},struct{
    /// whether `a` was saved more recently than `b`
    fn newer(_:void,a:Entry,b:Entry)bool{return a.age<b.age;}
  }.newer);
}
/// `home.saves`/`name``ext`, plus `extra`
fn pathOf(buf:*[maxPath]u8,name:Name,extra:[]const u8)[]const u8{
  return bufPrint(buf,"{s}{s}{s}{s}{s}",.{home.saves,sepStr,name.slice(),ext,extra}) catch unreachable;
}
/// writes the garden as `name` (whole or not at all: into a scratch file
/// first, then over the old one).
pub fn save(g:*Game,gpa:Allocator,io:Io,name:Name)Error!void{
  // the garden as bytes
  const bytes=try encode(gpa,g);
  defer gpa.free(bytes);
  // room for the scratch path and the final one, and the scratch path
  var tmpBuf:[maxPath]u8=undefined;
  var toBuf:[maxPath]u8=undefined;
  const tmp=pathOf(&tmpBuf,name,tmpExt);
  home.dir().writeFile(io,.{.sub_path=tmp,.data=bytes}) catch return error.SaveUnwritable;
  Io.Dir.rename(home.dir(),tmp,home.dir(),pathOf(&toBuf,name,""),io) catch return error.SaveUnwritable;
}
/// lets the garden `name` go (its file is deleted).
pub fn remove(io:Io,name:Name)Error!void{
  // room for the path
  var buf:[maxPath]u8=undefined;
  home.dir().deleteFile(io,pathOf(&buf,name,""))catch|e|return switch(e){
    error.FileNotFound=>error.NoSave,
    else=>error.SaveUnwritable,
  };
}
/// reads and rebuilds the garden saved as `name`
pub fn load(gpa:Allocator,io:Io,name:Name)Error!Game{
  // room for the path, and the file's bytes
  var buf:[maxPath]u8=undefined;
  const bytes=home.dir().readFileAlloc(io,pathOf(&buf,name,""),gpa,.limited(maxSave))catch|e|return switch(e){
    error.FileNotFound=>error.NoSave,
    error.OutOfMemory=>error.OutOfMemory,
    else=>error.SaveUnreadable,
  };
  defer gpa.free(bytes);
  return decode(gpa,bytes);
}
test"a typed name holds only what a file name may, and never the autosave's"{
  // a name typed character by character
  var n:Name=.{};
  for("my: Garden?/2")|c|n.put(c);
  try testing.expectEqualStrings("my Garden2",n.slice());
  try testing.expect(n.typed()!=null);
  n.put(' ');
  try testing.expect(n.typed()==null);
  n.erase();
  try testing.expect(n.same(Name.of("MY GARDEN2").?));
  // a name that is the autosave's
  var a:Name=.{};
  for("AutoSave")|c|a.put(c);
  try testing.expect(a.typed()==null);
  try testing.expect((Name{}).typed()==null);
  for(0..maxName+4)|_|a.put('x');
  try testing.expectEqual(@as(u8,maxName),a.len);
}
test"a garden survives a save round trip"{
  // the test allocator, and a demo garden grown on for three seconds
  const gpa=testing.allocator;
  var g=try Game.init(gpa,play.defaultSeed);
  defer g.deinit();
  try lib.setups.demo(&g,3);
  // gather from some node so a depleted chunk is stored too
  // the chunk the wolf stands in
  const c=g.world.chunkOfTile(m.tileOf(g.player.pos[0]),m.tileOf(g.player.pos[2])).?;
  for(&c.res)|*r|if(r.*>0){r.*-=1;break;};
  // the garden as bytes, and rebuilt from them
  const bytes=try encode(gpa,&g);
  defer gpa.free(bytes);
  var back=try decode(gpa,bytes);
  defer back.deinit();
  try testing.expectEqual(g.plants.len(),back.plants.len());
  try testing.expectEqual(g.structs.list.items.len,back.structs.list.items.len);
  try testing.expectEqual(g.player.inv.count(.grit),back.player.inv.count(.grit));
  try testing.expect(back.prog.done.contains(.rootCommunion));
  try testing.expectEqual(g.player.pos,back.player.pos);
  // the rebuilt garden's chunk under the wolf
  const c2=back.world.chunkOfTile(m.tileOf(g.player.pos[0]),m.tileOf(g.player.pos[2])).?;
  try testing.expectEqualSlices(ck.Res,&c.res,&c2.res);
  // a structure's per-kind state comes back intact
  for(g.structs.list.items,0..)|s,i|try testing.expectEqual(s.kind(),back.structs.list.items[i].kind());
}
