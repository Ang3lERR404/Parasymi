//! a value as a record of named fields (structures in saves): each field is
//! written with its name's hash and its length, so a record read back into
//! a type that has since gained, lost or changed a field keeps what still
//! matches and the defaults for the rest. Stores numbers, bools, enums (by
//! tag name), optionals, arrays, vectors, structs, tagged unions (by tag
//! name) and `ArrayList`s; anything else (a pointer) is refused at compile
//! time.
//!
//! A value's bytes: a number or packed struct raw; an enum its tag name's
//! hash (u32; a non-exhaustive one its integer); an optional a 0/1 byte and
//! the value; an array, vector or list its count (u32) and each element
//! framed; a struct its field count (u16) and per field its name's hash
//! (u32) and the field framed; a union its tag name's hash and the payload
//! framed. Framed: its length (u32), then its bytes.
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
/// the record was cut short or does not frame (or memory ran out)
pub const Error=error{CorruptSave}||Allocator.Error;
/// what a name (a field's, a tag's) is stored as
pub fn nameHash(name:[]const u8)u32{return Fnv.hash(name);}
/// whether `T` is an `ArrayList` (it has `items`, `capacity` and a `Slice`)
fn isList(comptime T:type)bool{
  return@typeInfo(T)==.@"struct"and@hasField(T,"items")and@hasField(T,"capacity")and@hasDecl(T,"Slice");
}
/// the element type of the list `T`
fn ListItem(comptime T:type)type{return@typeInfo(@FieldType(T,"items")).pointer.child;}
/// a fresh `T`: its fields' defaults, else zero, false, null or the first tag
pub fn fresh(comptime T:type)T{
  if(comptime isList(T))return.empty;
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
  switch(@typeInfo(T)){
    .void=>{},
    .bool=>if(b.len==1){
      out.*=b[0]!=0;
    },
    .int,.float=>if(b.len==@sizeOf(T))@memcpy(asBytes(out),b),
    .@"enum"=>|e|if(e.is_exhaustive){
      if(b.len!=4)return;
      // the stored tag name's hash
      const h=try r.int(u32);
      inline for(e.fields)|f|if((comptime nameHash(f.name))==h){
        out.*=@enumFromInt(f.value);
      };
    }else if(b.len==@sizeOf(e.tag_type)){
      out.*=@enumFromInt(try r.int(e.tag_type));
    },
    .optional=>|o|{
      if(b.len==0)return;
      if(b[0]==0){
        out.*=null;
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
        // this field's name hash, and its bytes
        const h=try r.int(u32);
        const e=try r.frame();
        inline for(s.fields)|f|{
          if(f.is_comptime)continue;
          if((comptime nameHash(f.name))==h)try read(f.type,gpa,e,&@field(out.*,f.name));
        }
      }
    },
    .@"union"=>|u|{
      // the stored tag name's hash, and the payload's bytes
      const h=try r.int(u32);
      const e=try r.frame();
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
