//! saving and restoring the garden. The world itself is never stored: it is
//! regenerated from the seed, and only what the gardener changed is kept:
//! the wolf and its belly, research, the weave queue, every plant and
//! structure, and resource nodes that were gathered.
//!
//! Each garden is a file of its own in `home.saves` (`<name>.sav`), named
//! by the gardener (`Name.typed`); the timer saves into `auto`.
//!
//! Format: a small header (magic, version, seed) that never changes, the
//! whole garden as one `record` of named fields, then every structure as its
//! kind's name hash and a record of its own. Items, species, research and
//! every other tag are stored by name, never by number, so saves never
//! break: a field gained keeps the fresh garden's value, a field gone is
//! passed over, a reordered tag still reads as itself, and a thing that is
//! gone (an item, a species, a structure's kind) is left out.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// pictures: one kept beside each save, read back
const png=lib.engine.core.png;
/// the allocator the bytes and the rebuilt garden come from
const Allocator=std.mem.Allocator;
/// the I/O interface every file call goes through
const Io=std.Io;
/// a growable list: the bytes written, and the record's lists
const ArrayList=std.ArrayList;
/// which keys of an enum are in: what is known, what was witnessed
const EnumSet=std.EnumSet;
/// a value for every key of an enum: each study's progress
const EnumArray=std.EnumArray;
/// the tag an integer names, for the moss's stored ground
const fromInt=std.enums.fromInt;
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
/// the game's state
const play=lib.play;
/// every player-facing string
const txt=lib.txt;
/// the whole running game saved and rebuilt
const Game=play.Game;
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
pub const maxPath=home.saves.len+1+maxName+ext.len+@max(tmpExt.len,pictureExt.len);
/// the first four bytes of every save
const magic="PRSY".*;
/// the save format's version: 35 and on, every save is named records
const version:u32=35;
/// the oldest version still read: before it saves were raw bytes
const firstNamed:u32=35;
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
  /// written before saves were named records
  IncompatibleSave,
  /// the file is cut short or holds what cannot be
  CorruptSave,
}||Allocator.Error;
// a weave is stored as what it makes, so no two hand weaves may make the same
comptime{
  for(craft.hand,0..)|a,i|for(craft.hand[0..i])|b|{
    if(a.out==b.out)@compileError("save: two hand weaves make "++@tagName(a.out));
  };
}
/// one plant, without its runtime links (rebuilt on load)
const PlantRec=struct{
  /// its tile column
  x:i32=0,
  /// its tile row
  y:i32=0,
  /// where it stands across (a floater's own free point, m)
  ax:f32=0,
  /// and along
  az:f32=0,
  /// its species, by name (none: a species no longer grown, left out)
  sp:?species.Id=null,
  /// how grown it is, 0..1
  growth:f32=0,
  /// its own growing time (s; 0: its species')
  span:f32=0,
  /// the mana it holds
  mana:f32=0,
  /// its health, 0..1
  health:f32=1,
  /// its seed, the per-plant variation
  seed:f32=0,
  /// the flow through it
  flow:f32=0,
  /// the essence it has ripened
  essence:f32=0,
  /// how much of that is rare, steeped by a night beam
  rare:f32=0,
  /// the light it holds in store (an astrocyme's)
  stored:f32=0,
  /// the way it faces
  dir:m.Dir=0,
};
/// one chunk whose resource nodes differ from what the generator made
const NodesRec=struct{
  /// which chunk
  at:ck.Coord,
  /// what is left in each of its tiles' nodes
  res:[ck.tileCount]ck.Res,
};
/// one tile the garden changed (moss, beam-born ley)
const MossRec=struct{
  /// its column
  x:i32=0,
  /// its row
  y:i32=0,
  /// what it became, by name (none: a ground no longer grown, left out)
  grown:?lib.moss.Grown=null,
};
/// one wild flower and the tile it grows on
const WildRec=struct{
  /// its tile
  at:m.Vice(i32,2),
  /// the flower
  flower:lib.wild.Flower,
};
/// one slot of the wolf's belly
const Held=struct{
  /// what it holds, by name (none: empty, or an item that is gone)
  item:?items.Item=null,
  /// how many
  n:u16=0,
};
/// the weave queue: what each queued weave makes, and how far the first is
const Weave=struct{
  /// each queued weave, by the item it makes (none: a weave that is gone)
  queue:ArrayList(?items.Item)=.empty,
  /// seconds the first weave has been worked
  t:f32=0,
};
/// what the gardener knows: every study and discovery by name, and how far
/// each study has come
const Known=struct{
  /// every technology known
  done:EnumSet(prog.Id)=.initEmpty(),
  /// every discovery witnessed
  found:EnumSet(prog.Discovery)=.initEmpty(),
  /// the world event's blend 0..1
  veil:f32=0,
  /// the technology the labs work on
  current:?prog.Id=null,
  /// units finished so far, per technology
  progress:EnumArray(prog.Id,u32)=.initFill(0),
};
/// the whole garden as one record of named fields: a field this build no
/// longer has is passed over, one the save lacks keeps the fresh garden's
const Saved=struct{
  /// the game's random stream
  rng:Rng=.{.s=0},
  /// the time of day, 0..1
  tod:f32=0,
  /// the game's clock (s)
  time:f64=0,
  /// the hotbar slot in hand
  hot:u32=0,
  /// the hotbar, each slot an item by name or empty
  bar:[play.barSlots]?items.Item=@splat(null),
  /// the way the next thing placed faces
  placeDir:m.Dir=0,
  /// where the wolf stands
  pos:m.V3=@splat(0),
  /// the way the wolf faces (rad)
  facing:f32=0,
  /// the wolf's belly, slot by slot
  belly:ArrayList(Held)=.empty,
  /// the weave queue
  weave:Weave=.{},
  /// what the gardener knows
  known:Known=.{},
  /// the world event
  unforming:lib.unforming.Unforming=.{},
  /// the act the garden is in
  act:lib.act.Act=.wolf,
  /// the tendrils drawn
  tendrils:ArrayList(lib.tendril.Tendril)=.empty,
  /// everything it grew
  plants:ArrayList(PlantRec)=.empty,
  /// the chunks whose nodes were gathered from
  nodes:ArrayList(NodesRec)=.empty,
  /// the ground the garden changed
  moss:ArrayList(MossRec)=.empty,
  /// the wild flowers
  wild:ArrayList(WildRec)=.empty,
  /// frees its lists
  fn deinit(s:*Saved,gpa:Allocator)void{
    s.belly.deinit(gpa);
    s.weave.queue.deinit(gpa);
    s.tendrils.deinit(gpa);
    s.plants.deinit(gpa);
    s.nodes.deinit(gpa);
    s.moss.deinit(gpa);
    s.wild.deinit(gpa);
  }
};
/// what opens every save, the same in every version: the magic, the
/// version and the seed the world regrows from
const Header=extern struct{
  /// always `magic`
  magic:m.Vice(u8,4),
  /// the build's `version`
  version:u32,
  /// the world's seed
  seed:u64,
};
/// the garden `g` as one record (its lists owned)
fn snapshot(gpa:Allocator,g:*const Game)Allocator.Error!Saved{
  // the record being filled
  var sv=Saved{.rng=g.rng,.tod=g.sky.tod,.time=g.time,.hot=@intCast(g.hot),.bar=g.bar,.placeDir=g.placeDir,
    .pos=g.player.pos,.facing=g.player.facing,.weave=.{.t=g.weave.t},.unforming=g.unforming,.act=g.act,
    .known=.{.done=g.prog.done,.found=g.prog.found,.veil=g.prog.veil,.current=g.prog.current,.progress=g.prog.progress}};
  errdefer sv.deinit(gpa);
  for(g.player.inv.slot)|o|try sv.belly.append(gpa,if(o)|s|.{.item=s.item,.n=s.n}else.{});
  for(g.weave.queue[0..g.weave.len])|q|try sv.weave.queue.append(gpa,craft.hand[q].out);
  try sv.tendrils.appendSlice(gpa,g.tendrils.list.items);
  // the plant list's columns
  const s=g.plants.list.slice();
  try sv.plants.ensureTotalCapacity(gpa,g.plants.len());
  for(0..g.plants.len())|i|sv.plants.appendAssumeCapacity(.{
    .x=s.items(.x)[i],.y=s.items(.y)[i],.ax=s.items(.at)[i][0],.az=s.items(.at)[i][2],.sp=s.items(.sp)[i],
    .growth=s.items(.growth)[i],.span=s.items(.span)[i],.mana=s.items(.mana)[i],.health=s.items(.health)[i],
    .seed=s.items(.seed)[i],.flow=s.items(.flow)[i],.essence=s.items(.essence)[i],
    .rare=s.items(.rare)[i],.stored=s.items(.stored)[i],.dir=@intCast(s.items(.dir)[i]),
  });
  // gathered resource nodes (only chunks that differ from generation)
  // the walk over every chunk in the world
  var it=g.world.map.valueIterator();
  while(it.next())|c|if(gathered(g.world.seed,c.*))try sv.nodes.append(gpa,.{.at=c.*.at,.res=c.*.res});
  // the moss the creepers grew, tile by tile
  var mossed:ArrayList(lib.moss.Kept)=.empty;
  defer mossed.deinit(gpa);
  try g.moss.list(gpa,&mossed);
  for(mossed.items)|t|try sv.moss.append(gpa,.{.x=t.x,.y=t.y,.grown=fromInt(lib.moss.Grown,t.grown)});
  // the wild flowers, tile by tile
  var wi=g.wild.flowers.iterator();
  while(wi.next())|e|try sv.wild.append(gpa,.{.at=lib.wild.unkey(e.key_ptr.*),.flower=e.value_ptr.*});
  return sv;
}
/// the garden as bytes (owned): the header, the garden as one record, and
/// every structure, each its kind's name hash and a record of its own
pub fn encode(gpa:Allocator,g:*const Game)Allocator.Error![]u8{
  // the bytes being written
  var out:ArrayList(u8)=.empty;
  errdefer out.deinit(gpa);
  // the header
  const h=Header{.magic=magic,.version=version,.seed=g.world.seed};
  try out.appendSlice(gpa,asBytes(&h));
  // the garden as one record
  var sv=try snapshot(gpa,g);
  defer sv.deinit(gpa);
  try record.writeFramed(Saved,gpa,&out,&sv);
  // the structures
  const n:u32=@intCast(g.structs.list.items.len);
  try out.appendSlice(gpa,asBytes(&n));
  for(g.structs.list.items)|*it|{
    // its kind's name hash
    const kh=record.nameHash(@tagName(it.kind()));
    try out.appendSlice(gpa,asBytes(&kh));
    try record.writeFramed(st.Structure,gpa,&out,it);
  }
  return out.toOwnedSlice(gpa);
}
/// whether any of a chunk's nodes differ from what the generator made
fn gathered(seed:u64,c:*const ck.Chunk)bool{
  for(0..ck.tileCount)|t|{
    // the tile's place in the world
    const wx,const wy=c.tileOf(t);
    // what the generator made there
    const s=gen.plain(seed,wx,wy);
    if(s.res!=c.res[t])return true;
  }
  return false;
}
/// rebuild a game from bytes produced by `encode` (this build's or any
/// other since saves became named records)
pub fn decode(gpa:Allocator,data:[]const u8)Error!Game{
  if(data.len<magic.len or !eql(u8,data[0..magic.len],&magic))return error.NotASave;
  // the cursor over the bytes, and the header
  var in:record.In=.{.b=data};
  const h=try in.int(Header);
  if(h.version<firstNamed)return error.IncompatibleSave;
  // a fresh garden from the saved seed, filled in below
  var g=try Game.init(gpa,null,h.seed);
  errdefer g.deinit();
  // the fresh garden as a record, read over with what was saved
  var sv=try snapshot(gpa,&g);
  defer sv.deinit(gpa);
  try record.read(Saved,gpa,try in.frame(),&sv);
  g.rng=sv.rng;
  g.sky.tod=sv.tod;
  g.time=sv.time;
  g.hot=if(sv.hot<play.barSlots)sv.hot else 0;
  g.bar=sv.bar;
  g.placeDir=sv.placeDir;
  g.player.pos=sv.pos;
  g.player.facing=sv.facing;
  g.cam.target=g.player.pos;
  // the belly, slot by slot: an item gone leaves its slot empty
  g.player.inv=.{};
  for(sv.belly.items,0..)|b,i|{
    if(i==g.player.inv.slot.len)break;
    if(b.item)|it|if(b.n>0){g.player.inv.slot[i]=.{.item=it,.n=b.n};};
  }
  // the weave queue, each found again by what it makes
  g.weave=.{.t=sv.weave.t};
  for(sv.weave.queue.items)|q|{
    // what the weave makes, and the hand weave that makes it
    const it=q orelse continue;
    const idx=handOf(it) orelse continue;
    if(g.weave.len==g.weave.queue.len)break;
    g.weave.queue[g.weave.len]=idx;
    g.weave.len+=1;
  }
  if(g.weave.len==0)g.weave.t=0;
  g.prog.done=sv.known.done;
  g.prog.found=sv.known.found;
  g.prog.veil=sv.known.veil;
  g.prog.current=sv.known.current;
  g.prog.progress=sv.known.progress;
  g.unforming=sv.unforming;
  g.act=sv.act;
  // the tendrils drawn
  g.tendrils.list.clearRetainingCapacity();
  for(sv.tendrils.items)|t|{
    // the tendril, its tile count kept within its path
    var c=t;
    c.n=@min(c.n,lib.tendril.most);
    try g.tendrils.list.append(g.gpa,c);
  }
  // everything it grew; a species no longer grown is left out
  for(sv.plants.items)|p|{
    // its species
    const sp=p.sp orelse continue;
    try ensureFootprint(&g,p.x,p.y,species.get(sp).size);
    _=try g.plants.placeNear(gpa,&g.world,m.v3(p.ax,0,p.az),.{
      .x=p.x,.y=p.y,.chunk=undefined,.tile=undefined,.sp=sp,
      .growth=p.growth,.span=p.span,.mana=p.mana,.health=p.health,.seed=p.seed,
      .flow=p.flow,.essence=p.essence,.rare=p.rare,.stored=p.stored,.dir=p.dir,
    });
  }
  // how many structures are stored
  const structs=try in.int(u32);
  for(0..structs)|_|{
    // its kind's name hash, and its record's bytes
    const kh=try in.int(u32);
    const body=try in.frame();
    // its kind; one no longer grown is left out
    const k=st.kindByName(kh) orelse continue;
    // a blank structure of that kind, read over
    var s=st.blank(k);
    errdefer s.deinit(gpa);
    try record.read(st.Structure,gpa,body,&s);
    try ensureFootprint(&g,s.x,s.y,s.def().size);
    // restored as saved (inventory, per-kind data); one that no longer
    // fits (its footprint grew, the land moved) is let go
    if(!try g.structs.restore(gpa,&g.world,s))s.deinit(gpa);
  }
  g.structs.relink();
  // the gathered chunks' nodes
  for(sv.nodes.items)|n|{
    // the chunk, made if it is not streamed in yet
    const c=try g.world.ensure(n.at);
    c.res=n.res;
  }
  // the ground the garden changed (moss, beam-born ley), laid on its chunks as they stream in
  for(sv.moss.items)|t|if(t.grown)|to|try g.moss.become(gpa,&g.world,t.x,t.y,to);
  // the wild flowers
  for(sv.wild.items)|f|try g.wild.put(gpa,f.at[0],f.at[1],f.flower);
  g.prog.say(txt.s.msg.remembers,.{});
  return g;
}
/// the hand weave that makes `it`, as its index in `craft.hand`
fn handOf(it:items.Item)?u8{
  for(craft.hand,0..)|r,i|if(r.out==it)return @intCast(i);
  return null;
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
/// lets the garden `name` go (its file is deleted, and its picture)
pub fn remove(io:Io,name:Name)Error!void{
  // room for the path
  var buf:[maxPath]u8=undefined;
  home.dir().deleteFile(io,pathOf(&buf,name,""))catch|e|return switch(e){
    error.FileNotFound=>error.NoSave,
    else=>error.SaveUnwritable,
  };
  home.dir().deleteFile(io,pathOf(&buf,name,pictureExt))catch{};
}
/// what a save's picture is named after it: `<name>.sav.png`, beside it
pub const pictureExt=".png";
/// the most a save's picture may weigh, read back (bytes)
const maxPicture:usize=1<<20;
/// where garden `name`'s picture is kept, in the home folder
pub fn picturePath(buf:*[maxPath]u8,name:Name)[]const u8{return pathOf(buf,name,pictureExt);}
/// garden `name`'s picture, read back (null: it has none yet, as older
/// saves, or it will not read: shown as none, never an error)
pub fn picture(gpa:Allocator,io:Io,name:Name)?png.Image{
  // room for the path, and the file's bytes
  var buf:[maxPath]u8=undefined;
  const bytes=home.dir().readFileAlloc(io,picturePath(&buf,name),gpa,.limited(maxPicture))catch{return null;};
  defer gpa.free(bytes);
  return png.decode(gpa,bytes)catch{return null;};
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
  var g=try Game.init(gpa,testing.io,play.defaultSeed);
  defer g.deinit();
  try lib.setups.demo(&g,3);
  // a weave queued, a study half done, a hotbar slot filled
  g.weave.queue[0]=2;
  g.weave.len=1;
  g.weave.t=0.5;
  g.prog.progress.set(.driftSpores,3);
  g.prog.current=.driftSpores;
  g.bar[1]=.fibre;
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
  try testing.expectEqual(g.player.inv.slot,back.player.inv.slot);
  try testing.expectEqual(@as(usize,1),back.weave.len);
  try testing.expectEqual(@as(u8,2),back.weave.queue[0]);
  try testing.expectEqual(@as(f32,0.5),back.weave.t);
  try testing.expectEqual(@as(u32,3),back.prog.progress.get(.driftSpores));
  try testing.expectEqual(@as(?prog.Id,.driftSpores),back.prog.current);
  try testing.expectEqual(g.bar,back.bar);
  try testing.expectEqual(g.wild.count(),back.wild.count());
  // the rebuilt garden's chunk under the wolf
  const c2=back.world.chunkOfTile(m.tileOf(g.player.pos[0]),m.tileOf(g.player.pos[2])).?;
  try testing.expectEqualSlices(ck.Res,&c.res,&c2.res);
  // a structure's per-kind state comes back intact
  for(g.structs.list.items,0..)|s,i|try testing.expectEqual(s.kind(),back.structs.list.items[i].kind());
}
test"a save from another build loads: fields it lacks stay fresh, fields unknown are passed over"{
  // the test allocator, and the bytes of a save from a build whose garden
  // has a field this one never had and lacks every other
  const gpa=testing.allocator;
  var out:ArrayList(u8)=.empty;
  defer out.deinit(gpa);
  const h=Header{.magic=magic,.version=version+9,.seed=play.defaultSeed};
  try out.appendSlice(gpa,asBytes(&h));
  // that build's garden: the act it is in, and a comet this one knows nothing of
  const Later=struct{act:lib.act.Act=.hyena,comet:m.Vice(f32,3)=.{1,2,3}};
  try record.writeFramed(Later,gpa,&out,&.{});
  // and a structure of a kind long gone
  const n:u32=1;
  try out.appendSlice(gpa,asBytes(&n));
  const kh=record.nameHash("aKindNeverGrown");
  try out.appendSlice(gpa,asBytes(&kh));
  try record.writeFramed(u32,gpa,&out,&n);
  var back=try decode(gpa,out.items);
  defer back.deinit();
  // the fresh garden from the same seed, to compare against
  var fresh=try Game.init(gpa,null,play.defaultSeed);
  defer fresh.deinit();
  try testing.expectEqual(lib.act.Act.hyena,back.act);
  try testing.expectEqual(fresh.player.pos,back.player.pos);
  try testing.expectEqual(@as(usize,0),back.structs.list.items.len);
}
test"an old save naming a renamed study, item or kind loads it under its new name"{
  // the test allocator, and the bytes of a save from before the renames
  const gpa=testing.allocator;
  var out:ArrayList(u8)=.empty;
  defer out.deinit(gpa);
  const h=Header{.magic=magic,.version=version,.seed=play.defaultSeed};
  try out.appendSlice(gpa,asBytes(&h));
  // the old build's names: a study and an item since renamed
  const OldStudy=enum{saveTestOldStudy};
  const OldItem=enum{saveTestOldItem};
  // that build's garden: the study under way and a hotbar slot, by old names
  const Before=struct{
    known:struct{current:?OldStudy=.saveTestOldStudy}=.{},
    bar:m.Vice(?OldItem,1)=.{.saveTestOldItem},
  };
  try record.writeFramed(Before,gpa,&out,&.{});
  const n:u32=0;
  try out.appendSlice(gpa,asBytes(&n));
  var back=try decode(gpa,out.items);
  defer back.deinit();
  try testing.expectEqual(@as(?prog.Id,.driftSpores),back.prog.current);
  try testing.expectEqual(@as(?items.Item,.grit),back.bar[0]);
  // a structure stored under its kind's old name
  try testing.expectEqual(@as(?st.Kind,.conduit),st.kindByName(record.nameHash("saveTestOldKind")));
}
test"an old raw save is refused, never misread, and a cut-short one is corrupt"{
  // the test allocator, and a raw save's header from before named records
  const gpa=testing.allocator;
  const old=Header{.magic=magic,.version=firstNamed-1,.seed=1};
  try testing.expectError(error.IncompatibleSave,decode(gpa,asBytes(&old)));
  try testing.expectError(error.NotASave,decode(gpa,"PR"));
  // a whole save, cut short
  var g=try Game.init(gpa,null,play.defaultSeed);
  defer g.deinit();
  const bytes=try encode(gpa,&g);
  defer gpa.free(bytes);
  try testing.expectError(error.CorruptSave,decode(gpa,bytes[0..bytes.len/2]));
}
