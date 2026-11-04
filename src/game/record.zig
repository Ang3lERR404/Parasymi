//! a value as a record of named fields (every save, structures and all): each field is
//! written with its name's hash and its length, so a record read back into
//! a type that has since gained, lost or changed a field keeps what still
//! matches and the defaults for the rest. Stores numbers, bools, enums (by
//! tag name), optionals, arrays, vectors, structs, tagged unions (by tag
//! name), `ArrayList`s and `std.EnumSet`/`EnumArray`/`EnumMap` (by their
//! keys' tag names, so reordered or new tags never scramble them); anything
//! else (a pointer) is refused at compile time.
//!
//! A value's bytes: a number or packed struct raw; an enum its tag name's
//! hash (u32; a non-exhaustive one its integer); an optional a 0/1 byte and
//! the value; an array, vector or list its count (u32) and each element
//! framed; a struct its field count (u16) and per field its name's hash
//! (u32) and the field framed; a union its tag name's hash and the payload
//! framed; an enum set its count (u32) and each key framed; an enum array
//! or map its count and per entry its key framed and its value framed.
//! Framed: its length (u32), then its bytes.
const lib=@import("../lib.zig");
/// the maths: vectors (Vec), rows (Vice) and matrices (Mat)
const m=lib.engine.core.math;
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator lists and the output grow with
const Allocator=std.mem.Allocator;
/// a growable list: the output bytes, and stored lists
const ArrayList=std.ArrayList;
/// a value's raw bytes
const asBytes=std.mem.asBytes;
/// which tag a union holds
const activeTag=std.meta.activeTag;
/// the 32-bit FNV-1a hash names are stored as
const Fnv=std.hash.Fnv1a_32;
/// the test harness
const testing=std.testing;
/// which keys of an enum are in (the tests' stored sets)
const EnumSet=std.EnumSet;
/// a value for every key of an enum (the tests' stored rows)
const EnumArray=std.EnumArray;
/// a value for some keys of an enum (the tests' stored maps)
const EnumMap=std.EnumMap;
/// the record was cut short or does not frame (or memory ran out)
pub const Error=error{CorruptSave}||Allocator.Error;
/// what a name (a field's, a tag's) is stored as
pub fn nameHash(name:[]const u8)u32{return Fnv.hash(name);}
/// a name list of a struct, union or enum
const fieldNames=std.meta.fieldNames;
/// a name a code tag or field once had and the one it has now: a save
/// naming the old one reads as the new one
pub const Renamed=struct{
  /// the name saves may still hold
  was:[]const u8,
  /// the name it goes by now
  now:[]const u8,
};
/// the old-name table: every code tag (species, structure kind, item,
/// research, anything stored by name) or field renamed since saves became
/// named, so a renamed thing is carried over, never dropped. Add a line
/// when renaming; never remove one. A name renamed twice chains (a to b,
/// b to c). The player-facing names live in `src/cfg/parasymi.cfg` and
/// change freely; only code names need a line here.
pub const renamed=[_]Renamed{};
/// names only the tests rename (they stand for a renamed species, kind,
/// study and item, and the tests' own enums)
const testRenamed=[_]Renamed{
  .{.was="recordOldest",.now="recordOld"},
  .{.was="recordOld",.now="recordNew"},
  .{.was="recordOldField",.now="recordField"},
  .{.was="saveTestOldKind",.now="conduit"},
  .{.was="saveTestOldStudy",.now="driftSpores"},
  .{.was="saveTestOldItem",.now="grit"},
};
/// the table this build reads: `renamed`, and in a test build the tests' own
const formerly=renamed++(if(lib.builtin.is_test)testRenamed else [_]Renamed{});
/// the table as name hashes: each line's old name and new name
const formerHashes=blk:{
  @setEvalBranchQuota(100_000);
  // the pairs, filled line by line
  var p:[formerly.len]m.Vice(u32,2)=undefined;
  for(formerly,0..)|r,i|p[i]=.{nameHash(r.was),nameHash(r.now)};
  break:blk p;
};
/// the name stored as `h` is called now, followed through the table (null:
/// the table never renamed it)
fn current(h:u32)?u32{
  // the name as far as it has been followed
  var now=h;
  outer:for(0..formerHashes.len)|_|{
    now=for(formerHashes)|p|{
      if(p[0]==now)break p[1];
    }else break:outer;
  }
  return if(now==h)null else now;
}
/// whether one of `names` hashes to `h`
fn has(comptime names:[]const [:0]const u8,h:u32)bool{
  inline for(names)|n|if((comptime nameHash(n))==h)return true;
  return false;
}
/// the name hash among `T`'s fields or tags that the stored `h` stands for:
/// `h` itself, else what the old-name table renamed it to (null: gone)
fn known(comptime T:type,h:u32)?u32{
  // the names `T` has now
  const names=comptime fieldNames(T);
  if(has(names,h))return h;
  // what the table renamed it to
  const now=current(h) orelse return null;
  return if(has(names,now))now else null;
}
/// the tag of `E` stored as the name hash `h` (through the old-name
/// table), if `E` still has it
pub fn tagByHash(comptime E:type,h:u32)?E{
  // the hash of the name it has now
  const n=known(E,h) orelse return null;
  inline for(@typeInfo(E).@"enum".fields)|f|if((comptime nameHash(f.name))==n)return@enumFromInt(f.value);
  return null;
}
/// whether `T` is an `ArrayList` (it has `items`, `capacity` and a `Slice`)
fn isList(comptime T:type)bool{
  return@typeInfo(T)==.@"struct"and@hasField(T,"items")and@hasField(T,"capacity")and@hasDecl(T,"Slice");
}
/// the element type of the list `T`
fn ListItem(comptime T:type)type{return@typeInfo(@FieldType(T,"items")).pointer.child;}
/// which of the standard library's enum-keyed collections a type is
const Keyed=enum{
  /// not one of them
  none,
  /// an `EnumSet`: which keys are in
  set,
  /// an `EnumArray`: a value for every key
  array,
  /// an `EnumMap`: a value for some keys
  map,
};
/// which enum-keyed collection `T` is (an `Indexer` and a `Key`, and a
/// `bits` mask, a `values` row, or both)
fn keyed(comptime T:type)Keyed{
  if(@typeInfo(T)!=.@"struct" or !@hasDecl(T,"Indexer") or !@hasDecl(T,"Key"))return.none;
  // what it holds
  const bits=@hasField(T,"bits");
  const values=@hasField(T,"values");
  return if(bits and values).map else if(bits).set else if(values).array else.none;
}
/// the tag of `E` whose name hashes to what `b` holds, if `b` is a stored
/// tag and `E` still has it
fn tagOf(comptime E:type,b:[]const u8)?E{
  if(b.len!=4)return null;
  return tagByHash(E,@bitCast(b[0..4].*));
}
/// whether `T` is an exhaustive enum, stored by its tags' names
fn isTag(comptime T:type)bool{
  return switch(@typeInfo(T)){
    .@"enum"=>|e|e.is_exhaustive,
    else=>false,
  };
}
/// a fresh `T`: its fields' defaults, else zero, false, null or the first tag
pub fn fresh(comptime T:type)T{
  if(comptime isList(T))return.empty;
  switch(comptime keyed(T)){
    .none=>{},
    .set=>return.initEmpty(),
    .array=>return.initFill(fresh(T.Value)),
    .map=>return.{},
  }
  return switch(@typeInfo(T)){
    .void=>{},
    .bool=>false,
    .int,.float=>0,
    .@"enum"=>|e|if(e.fields.len>0)@enumFromInt(e.fields[0].value)else@enumFromInt(0),
    .optional=>null,
    .array=>|a|@splat(fresh(a.child)),
    .vector=>|v|@splat(fresh(v.child)),
    .@"struct"=>|s|blk:{
      // the struct being built, field by field
      var v:T=undefined;
      inline for(s.fields)|f|{
        if(f.is_comptime)continue;
        @field(v,f.name)=f.defaultValue() orelse fresh(f.type);
      }
      break:blk v;
    },
    .@"union"=>|u|@unionInit(T,u.fields[0].name,fresh(u.fields[0].type)),
    else=>@compileError("record: cannot store "++@typeName(T)),
  };
}
/// a value's raw bytes onto `out`
fn put(gpa:Allocator,out:*ArrayList(u8),comptime T:type,v:T)Allocator.Error!void{
  try out.appendSlice(gpa,asBytes(&v));
}
/// `v`, framed (its length, then its bytes), onto `out`
pub fn writeFramed(comptime T:type,gpa:Allocator,out:*ArrayList(u8),v:*const T)Allocator.Error!void{
  // where the length goes, filled in once the value is written
  const at=out.items.len;
  try put(gpa,out,u32,0);
  try write(T,gpa,out,v);
  // the value's length, now known
  const n:u32=@intCast(out.items.len-at-4);
  @memcpy(out.items[at..][0..4],asBytes(&n));
}
/// `v`'s bytes onto `out`
pub fn write(comptime T:type,gpa:Allocator,out:*ArrayList(u8),v:*const T)Allocator.Error!void{
  if(comptime isList(T)){
    try put(gpa,out,u32,@intCast(v.items.len));
    for(v.items)|*e|try writeFramed(ListItem(T),gpa,out,e);
    return;
  }
  // an enum-keyed collection: only what it holds, each by its key's name
  const kd=comptime keyed(T);
  if(kd!=.none){
    // how many keys it holds
    var n:u32=0;
    for(0..T.Indexer.count)|i|{
      if(kd==.array or v.contains(T.Indexer.keyForIndex(i)))n+=1;
    }
    try put(gpa,out,u32,n);
    for(0..T.Indexer.count)|i|{
      // the key at this place
      const k=T.Indexer.keyForIndex(i);
      if(kd!=.array and !v.contains(k))continue;
      try writeFramed(T.Key,gpa,out,&k);
      switch(kd){
        .array,.map=>try writeFramed(T.Value,gpa,out,&v.values[i]),
        .set,.none=>{},
      }
    }
    return;
  }
  switch(@typeInfo(T)){
    .void=>{},
    .bool,.int,.float=>try out.appendSlice(gpa,asBytes(v)),
    .@"enum"=>|e|if(e.is_exhaustive){
      try put(gpa,out,u32,nameHash(@tagName(v.*)));
    }else try put(gpa,out,e.tag_type,@intFromEnum(v.*)),
    .optional=>|o|if(v.*)|*c|{
      try put(gpa,out,u8,1);
      try write(o.child,gpa,out,c);
    }else try put(gpa,out,u8,0),
    .array=>|a|{
      try put(gpa,out,u32,a.len);
      for(v)|*e|try writeFramed(a.child,gpa,out,e);
    },
    .vector=>|vi|{
      // the vector as an array
      const arr:[vi.len]vi.child=v.*;
      try write([vi.len]vi.child,gpa,out,&arr);
    },
    .@"struct"=>|s|if(s.layout==.@"packed")try out.appendSlice(gpa,asBytes(v))else{
      comptime uniqueNames(T);
      // how many fields are stored (comptime ones are not)
      var n:u16=0;
      inline for(s.fields)|f|{
        if(!f.is_comptime)n+=1;
      }
      try put(gpa,out,u16,n);
      inline for(s.fields)|f|{
        if(f.is_comptime)continue;
        try put(gpa,out,u32,comptime nameHash(f.name));
        try writeFramed(f.type,gpa,out,&@field(v.*,f.name));
      }
    },
    .@"union"=>|u|{
      if(u.tag_type==null)@compileError("record: an untagged union cannot be stored: "++@typeName(T));
      comptime uniqueNames(T);
      switch(v.*){
        inline else=>|*p,tag|{
          try put(gpa,out,u32,comptime nameHash(@tagName(tag)));
          try writeFramed(@TypeOf(p.*),gpa,out,p);
        },
      }
    },
    else=>@compileError("record: cannot store "++@typeName(T)),
  }
}
/// refuses at compile time a type two of whose names hash alike (they
/// could not be told apart when read)
fn uniqueNames(comptime T:type)void{
  @setEvalBranchQuota(200_000);
  // the fields or tags to compare
  const fs=switch(@typeInfo(T)){
    inline.@"struct",.@"union"=>|i|i.fields,
    else=>unreachable,
  };
  for(fs,0..)|a,i|for(fs[0..i])|b|{
    if(nameHash(a.name)==nameHash(b.name))@compileError("record: "++a.name++" and "++b.name++" hash alike in "++@typeName(T));
  };
}
/// reading bytes in turn
/// a cursor over a record's bytes: reads numbers and frames in turn,
/// refusing any that would run past the end
pub const In=struct{
  /// the bytes being read
  b:[]const u8,
  /// how far into them the next read starts
  pos:usize=0,
  /// the next `T`, raw
  pub fn int(r:*In,comptime T:type)Error!T{
    if(@sizeOf(T)>r.b.len-r.pos)return error.CorruptSave;
    // the number being read
    var v:T=undefined;
    @memcpy(asBytes(&v),r.b[r.pos..][0..@sizeOf(T)]);
    r.pos+=@sizeOf(T);
    return v;
  }
  /// the next framed bytes
  pub fn frame(r:*In)Error![]const u8{
    // the frame's length
    const n=try r.int(u32);
    if(n>r.b.len-r.pos)return error.CorruptSave;
    defer r.pos+=n;
    return r.b[r.pos..][0..n];
  }
};
/// read `b` (one value's bytes) over `out`: what it holds that `T` still
/// has is set, the rest of `out` is left as it was
pub fn read(comptime T:type,gpa:Allocator,b:[]const u8,out:*T)Error!void{
  // the cursor over this value's bytes
  var r:In=.{.b=b};
  if(comptime isList(T)){
    // how many elements are stored
    const n=try r.int(u32);
    // each element takes at least its length
    if(n>(b.len-r.pos)/4)return error.CorruptSave;
    out.clearRetainingCapacity();
    try out.ensureTotalCapacity(gpa,n);
    for(0..n)|_|{
      // the element, from its defaults, then read over
      var e=fresh(ListItem(T));
      try read(ListItem(T),gpa,try r.frame(),&e);
      out.appendAssumeCapacity(e);
    }
    return;
  }
  // an enum-keyed collection, by its keys' names: a key gone is left out
  const kd=comptime keyed(T);
  if(kd!=.none){
    // how many keys are stored
    const n=try r.int(u32);
    if(n>(b.len-r.pos)/4)return error.CorruptSave;
    if(kd!=.array)out.*=fresh(T);
    for(0..n)|_|{
      // the key's bytes, and the key if it is still one
      const kb=try r.frame();
      const k=tagOf(T.Key,kb);
      switch(kd){
        .set=>if(k)|key|out.insert(key),
        .array=>{
          // the value's bytes
          const vb=try r.frame();
          if(k)|key|try read(T.Value,gpa,vb,out.getPtr(key));
        },
        .map=>{
          // the value's bytes, and the value read from its defaults
          const vb=try r.frame();
          if(k)|key|{
            var e=fresh(T.Value);
            try read(T.Value,gpa,vb,&e);
            out.put(key,e);
          }
        },
        .none=>unreachable,
      }
    }
    return;
  }
  switch(@typeInfo(T)){
    .void=>{},
    .bool=>if(b.len==1){
      out.*=b[0]!=0;
    },
    .int,.float=>if(b.len==@sizeOf(T))@memcpy(asBytes(out),b),
    .@"enum"=>|e|if(e.is_exhaustive){
      if(tagOf(T,b))|k|out.*=k;
    }else if(b.len==@sizeOf(e.tag_type)){
      out.*=@enumFromInt(try r.int(e.tag_type));
    },
    .optional=>|o|{
      if(b.len==0)return;
      if(b[0]==0){
        out.*=null;
        return;
      }
      // a tag no longer had is nothing at all (an item gone empties its slot)
      if(comptime isTag(o.child)){
        out.*=tagOf(o.child,b[1..]);
        return;
      }
      // the value read over: what was there, else a fresh one
      var c=out.* orelse fresh(o.child);
      try read(o.child,gpa,b[1..],&c);
      out.*=c;
    },
    .array=>|a|{
      // how many elements are stored
      const n=try r.int(u32);
      for(0..n)|i|{
        // this element's bytes
        const e=try r.frame();
        if(i<a.len)try read(a.child,gpa,e,&out[i]);
      }
    },
    .vector=>|vi|{
      // the vector as an array
      var arr:[vi.len]vi.child=out.*;
      try read([vi.len]vi.child,gpa,b,&arr);
      out.*=arr;
    },
    .@"struct"=>|s|if(s.layout==.@"packed"){
      if(b.len==@sizeOf(T))@memcpy(asBytes(out),b);
    }else{
      // how many fields are stored
      const n=try r.int(u16);
      for(0..n)|_|{
        // this field's stored name hash, and its bytes
        const stored=try r.int(u32);
        const e=try r.frame();
        // the field it is now, through the old-name table (none: gone)
        const h=known(T,stored) orelse continue;
        inline for(s.fields)|f|{
          if(f.is_comptime)continue;
          if((comptime nameHash(f.name))==h)try read(f.type,gpa,e,&@field(out.*,f.name));
        }
      }
    },
    .@"union"=>|u|{
      // the stored tag name's hash, and the payload's bytes
      const stored=try r.int(u32);
      const e=try r.frame();
      // the tag it is now, through the old-name table (none: gone, left as it was)
      const h=known(T,stored) orelse return;
      inline for(u.fields)|f|if((comptime nameHash(f.name))==h){
        if(@field(u.tag_type.?,f.name)!=activeTag(out.*))out.*=@unionInit(T,f.name,fresh(f.type));
        try read(f.type,gpa,e,&@field(out.*,f.name));
      };
    },
    else=>@compileError("record: cannot store "++@typeName(T)),
  }
}
/// `v` written and read back into `T` over `start`
fn again(comptime V:type,comptime T:type,v:V,start:T)!T{
  // the bytes `v` is written into
  var buf:ArrayList(u8)=.empty;
  defer buf.deinit(testing.allocator);
  try write(V,testing.allocator,&buf,&v);
  // `start`, read over
  var out=start;
  try read(T,testing.allocator,buf.items,&out);
  return out;
}
test"a record keeps what still matches and the defaults for the rest"{
  // the old enum, and the old record (each field with a default)
  const Kind=enum{moss,soil,sand};
  const Old=struct{a:u32=1,b:f32=2,k:Kind=.sand,gone:u8=9,opt:?u16=null,arr:m.Vice(u8,3)=.{1,2,3}};
  // `a` became a u8 (kept at its default), `gone` went, `c` came, the
  // array shrank, the enum's tags moved
  // the new enum, its tags moved, and the new record, changed as said
  const Kind2=enum{sand,moss};
  const New=struct{c:u16=7,b:f32=0,a:u8=5,k:Kind2=.moss,opt:?u16=3,arr:m.Vice(u8,2)=.{0,0}};
  // the old record written and read into the new one
  const got=try again(Old,New,.{.a=40,.b=2.5,.k=.sand,.opt=null},.{});
  try testing.expectEqual(New{.c=7,.b=2.5,.a=5,.k=.sand,.opt=null,.arr=.{1,2}},got);
}
test"enum sets, arrays and maps by their keys' names"{
  // the old keys, and the new ones: reordered, one gone, one new
  const Old=enum{moss,soil,sand};
  const New=enum{fern,sand,moss};
  // what is stored with the old keys
  var set=EnumSet(Old).initEmpty();
  set.insert(.moss);
  set.insert(.soil);
  var arr=EnumArray(Old,u32).initFill(0);
  arr.set(.sand,3);
  arr.set(.soil,9);
  var map:EnumMap(Old,f32)=.{};
  map.put(.moss,1.5);
  // read back with the new keys
  const s2=try again(EnumSet(Old),EnumSet(New),set,.initFull());
  try testing.expect(s2.contains(.moss) and !s2.contains(.sand) and !s2.contains(.fern));
  const a2=try again(EnumArray(Old,u32),EnumArray(New,u32),arr,.initFill(7));
  try testing.expectEqual(@as(u32,3),a2.get(.sand));
  try testing.expectEqual(@as(u32,0),a2.get(.moss));
  try testing.expectEqual(@as(u32,7),a2.get(.fern));
  const m2=try again(EnumMap(Old,f32),EnumMap(New,f32),map,.{});
  try testing.expectEqual(@as(?f32,1.5),m2.get(.moss));
  try testing.expectEqual(@as(?f32,null),m2.get(.sand));
  // an optional tag no longer had is nothing, one still had is kept
  try testing.expectEqual(@as(?New,null),try again(?Old,?New,.soil,.fern));
  try testing.expectEqual(@as(?New,.sand),try again(?Old,?New,.sand,null));
}
test"unions by tag name, lists grown back, nested records"{
  // the test allocator
  const gpa=testing.allocator;
  // a nested record: a count and a vector
  const Inner=struct{n:u16=0,v:m.Vec(f32,3)=@splat(0)};
  // a union with no payload, one record, or a list of them
  const U=union(enum){none,one:Inner,many:ArrayList(Inner)};
  // the list stored inside the union
  var list:ArrayList(Inner)=.empty;
  defer list.deinit(gpa);
  try list.append(gpa,.{.n=4,.v=.{1,2,3}});
  try list.append(gpa,.{.n=5});
  // the union written and read back
  var got=try again(U,U,.{.many=list},.none);
  defer got.many.deinit(gpa);
  try testing.expectEqual(@as(usize,2),got.many.items.len);
  try testing.expectEqual(@as(u16,5),got.many.items[1].n);
  try testing.expectEqual(@as(f32,3),got.many.items[0].v[2]);
  // a tag it no longer has: left as it was
  // a union that has lost those tags
  const V=union(enum){none,other:u8};
  try testing.expectEqual(V.none,try again(U,V,.{.one=.{}},.none));
}
test"a renamed tag or field is carried over through the old-name table"{
  // the old names, and the new: one renamed, one renamed twice, one kept
  const Old=enum{recordOldest,keep,recordOld};
  const New=enum{recordNew,keep};
  try testing.expectEqual(@as(?New,.recordNew),try again(?Old,?New,.recordOld,null));
  try testing.expectEqual(@as(?New,.recordNew),try again(?Old,?New,.recordOldest,null));
  try testing.expectEqual(@as(?New,.keep),try again(?Old,?New,.keep,null));
  // a set, and a field and a union tag renamed
  var set=EnumSet(Old).initEmpty();
  set.insert(.recordOld);
  try testing.expect((try again(EnumSet(Old),EnumSet(New),set,.initEmpty())).contains(.recordNew));
  const S1=struct{recordOldField:u8=0};
  const S2=struct{recordField:u8=0};
  try testing.expectEqual(@as(u8,9),(try again(S1,S2,.{.recordOldField=9},.{})).recordField);
  const U1=union(enum){none,recordOld:u8};
  const U2=union(enum){none,recordNew:u8};
  try testing.expectEqual(U2{.recordNew=4},try again(U1,U2,.{.recordOld=4},.none));
  // a name the table never renamed, and gone, stays gone
  try testing.expectEqual(@as(?u32,null),current(nameHash("neverRenamed")));
}
test"a cut-short record is corrupt, never misread"{
  // a record with a number and a list
  const S=struct{a:u32=0,l:ArrayList(u32)=.empty};
  // the bytes it is written into
  var buf:ArrayList(u8)=.empty;
  defer buf.deinit(testing.allocator);
  // the list stored in it
  var l:ArrayList(u32)=.empty;
  defer l.deinit(testing.allocator);
  try l.appendSlice(testing.allocator,&.{1,2,3});
  try write(S,testing.allocator,&buf,&.{.a=1,.l=l});
  for(0..buf.items.len)|n|{
    // what is read from the first `n` bytes
    var out:S=.{};
    defer out.l.deinit(testing.allocator);
    read(S,testing.allocator,buf.items[0..n],&out)catch|e|{
      try testing.expectEqual(error.CorruptSave,e);
      continue;
    };
  }
}
