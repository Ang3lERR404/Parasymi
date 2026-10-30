//! runtime text: templates (`{0}`, `{1:.2}`) filled at runtime, and the
//! `key = value` cfg format they are loaded from (see `game/text.zig`).
const std=@import("std");
const Allocator=std.mem.Allocator;
const Writer=std.Io.Writer;
const indexOf=std.mem.indexOf;
const EnumArray=std.enums.EnumArray;
const trim=std.mem.trim;
const eql=std.mem.eql;
const splitScalar=std.mem.splitScalar;
const indexOfScalar=std.mem.indexOfScalar;
const indexOfScalarPos=std.mem.indexOfScalarPos;
const parseUnsigned=std.fmt.parseUnsigned;
const stringToEnum=std.meta.stringToEnum;
const testing=std.testing;
const countOf=std.mem.count;
const bufPrint=std.fmt.bufPrint;
const ArenaAllocator=std.heap.ArenaAllocator;
/// separates the entries of a list value (`a | b | c`).
pub const listSep='|';
/// longest dotted key (section prefix included).
const maxKey=128;
/// writes `tpl` with `{N}` replaced by `args[N]`: strings as they are,
/// integers in decimal, floats with `{N:.P}` decimals (0 without), errors
/// by name. `{{` is a literal brace; an unknown index writes nothing.
pub fn render(w:*Writer,tpl:[]const u8,args:anytype)Writer.Error!void{
  const fields=@typeInfo(@TypeOf(args)).@"struct".fields;
  var i:usize=0;
  while(i<tpl.len){
    if(tpl[i]!='{'){try w.writeByte(tpl[i]);i+=1;continue;}
    if(i+1<tpl.len and tpl[i+1]=='{'){try w.writeByte('{');i+=2;continue;}
    const end=indexOfScalarPos(u8,tpl,i,'}') orelse return w.writeAll(tpl[i..]);
    const spec=tpl[i+1..end];
    i=end+1;
    const colon=indexOfScalar(u8,spec,':');
    const idx=parseUnsigned(usize,spec[0..colon orelse spec.len],10) catch continue;
    const prec:usize=if(colon)|k|precision(spec[k+1..])else 0;
    inline for(fields,0..)|f,n|if(n==idx)try arg(w,@field(args,f.name),prec);
  }
}
/// `render` into `buf`, truncated to fit.
pub fn bufRender(buf:[]u8,tpl:[]const u8,args:anytype)[]const u8{
  var w:Writer=.fixed(buf);
  render(&w,tpl,args)catch{};
  return w.buffered();
}
fn precision(s:[]const u8)usize{
  if(s.len<2 or s[0]!='.')return 0;
  return parseUnsigned(usize,s[1..],10) catch 0;
}
fn arg(w:*Writer,a:anytype,prec:usize)Writer.Error!void{
  const T=@TypeOf(a);
  switch(@typeInfo(T)){
    .int,.comptime_int=>try w.print("{d}",.{a}),
    .float,.comptime_float=>try w.printFloat(@as(f64,a),.{.precision=prec}),
    .error_set=>try w.writeAll(@errorName(a)),
    .pointer=>try w.writeAll(a),
    else=>@compileError("text.render: unsupported argument "++@typeName(T)),
  }
}
/// entry `i` of a list value, trimmed ("" past the end).
pub fn nth(list:[]const u8,i:usize)[]const u8{
  var it=splitScalar(u8,list,listSep);
  var k:usize=0;
  while(it.next())|e|:(k+=1)if(k==i)return trim(u8,e," \t");
  return"";
}
/// number of entries in a list value.
pub fn count(list:[]const u8)usize{
  if(list.len==0)return 0;
  return countOf(u8,list,&.{listSep})+1;
}
pub const ParseError=error{BadLine,UnknownKey,MissingKey};
/// fills `out` from cfg source `src`: one `key = value` per line, `#`
/// comment lines, `[a.b]` prefixes the keys below it. Keys are dotted
/// paths through `T`: struct fields, `EnumArray` tags, ending at a
/// `[]const u8` (required, must end up non-empty) or `?[]const u8`
/// (optional). Values are slices of `src`, which must outlive `out`.
/// On error the offending line or key is written to `bad`.
pub fn parse(comptime T:type,out:*T,src:[]const u8,bad:*Writer)ParseError!void{
  var keyBuf:[maxKey]u8=undefined;
  var prefix:[]const u8="";
  var prefixBuf:[maxKey]u8=undefined;
  var lines=splitScalar(u8,src,'\n');
  while(lines.next())|raw|{
    const line=trim(u8,raw," \t\r");
    if(line.len==0 or line[0]=='#')continue;
    if(line[0]=='['){
      if(line[line.len-1]!=']' or line.len-2>maxKey)return fail(bad,line,error.BadLine);
      const p=trim(u8,line[1..line.len-1]," \t");
      @memcpy(prefixBuf[0..p.len],p);
      prefix=prefixBuf[0..p.len];
      continue;
    }
    const eq=indexOfScalar(u8,line,'=') orelse return fail(bad,line,error.BadLine);
    const name=trim(u8,line[0..eq]," \t");
    const key=if(prefix.len==0)name else bufPrint(&keyBuf,"{s}.{s}",.{prefix,name}) catch return fail(bad,line,error.BadLine);
    if(!set(T,out,key,trim(u8,line[eq+1..]," \t")))return fail(bad,key,error.UnknownKey);
  }
  var pathBuf:[maxKey]u8=undefined;
  var path:Writer=.fixed(&pathBuf);
  if(missing(T,out,&path))return fail(bad,path.buffered(),error.MissingKey);
}
fn fail(bad:*Writer,what:[]const u8,e:ParseError)ParseError{
  bad.writeAll(what)catch{};
  return e;
}
fn isEnumArray(comptime T:type)bool{
  return@typeInfo(T)==.@"struct"and@hasDecl(T,"Key")and@hasDecl(T,"Value") and T==EnumArray(T.Key,T.Value);
}
fn set(comptime T:type,p:*T,path:[]const u8,val:[]const u8)bool{
  if(T==[]const u8 or T==?[]const u8){
    if(path.len!=0)return false;
    p.*=val;
    return true;
  }
  const dot=indexOfScalar(u8,path,'.');
  const head=path[0..dot orelse path.len];
  const rest=if(dot)|k|path[k+1..]else"";
  if(comptime isEnumArray(T)){
    const k=stringToEnum(T.Key,head) orelse return false;
    return set(T.Value,p.getPtr(k),rest,val);
  }
  inline for(@typeInfo(T).@"struct".fields)|f|if(eql(u8,f.name,head))return set(f.type,&@field(p,f.name),rest,val);
  return false;
}
/// the first required leaf left empty; its dotted path goes to `path`.
fn missing(comptime T:type,p:*const T,path:*Writer)bool{
  if(T==?[]const u8)return false;
  if(T==[]const u8)return p.len==0;
  const at=path.end;
  if(comptime isEnumArray(T)){
    inline for(0..T.len)|i|{
      const k=T.Indexer.keyForIndex(i);
      path.end=at;
      path.print("{s}{s}",.{if(at==0)""else".",@tagName(k)})catch{};
      if(missing(T.Value,p.getPtrConst(k),path))return true;
    }
    return false;
  }
  inline for(@typeInfo(T).@"struct".fields)|f|{
    path.end=at;
    path.print("{s}{s}",.{if(at==0)""else".",f.name})catch{};
    if(missing(f.type,&@field(p,f.name),path))return true;
  }
  return false;
}
/// opens a load-time token (`{@name}`): replaced once, by `expand`, before
/// anything is rendered.
pub const token="{@";
/// writes what token `name` stands for; false for no such name.
pub const Lookup=*const fn(w:*Writer,name:[]const u8)Writer.Error!bool;
pub const ExpandError=error{UnknownToken,BadLine}||Allocator.Error;
/// replaces every `{@name}` in the string leaves of `p` with what `lookup`
/// writes for `name`; changed strings are allocated from `gpa` (an arena:
/// nothing is freed here). On an unknown name it is written to `bad`.
pub fn expand(comptime T:type,p:*T,gpa:Allocator,lookup:Lookup,bad:*Writer)ExpandError!void{
  if(T==?[]const u8){
    if(p.*)|*v|try expand([]const u8,v,gpa,lookup,bad);
    return;
  }
  if(T==[]const u8){
    if(indexOf(u8,p.*,token)==null)return;
    var out:Writer.Allocating=.init(gpa);
    const w=&out.writer;
    var rest=p.*;
    while(indexOf(u8,rest,token))|at|{
      const end=indexOfScalarPos(u8,rest,at,'}') orelse return failExpand(bad,rest[at..],error.BadLine);
      const name=rest[at+token.len..end];
      w.writeAll(rest[0..at]) catch return error.OutOfMemory;
      if(!(lookup(w,name) catch return error.OutOfMemory))return failExpand(bad,name,error.UnknownToken);
      rest=rest[end+1..];
    }
    w.writeAll(rest) catch return error.OutOfMemory;
    p.*=try out.toOwnedSlice();
    return;
  }
  if(comptime isEnumArray(T)){
    inline for(0..T.len)|i|try expand(T.Value,p.getPtr(T.Indexer.keyForIndex(i)),gpa,lookup,bad);
    return;
  }
  inline for(@typeInfo(T).@"struct".fields)|f|try expand(f.type,&@field(p,f.name),gpa,lookup,bad);
}
fn failExpand(bad:*Writer,what:[]const u8,e:ExpandError)ExpandError{
  bad.writeAll(what)catch{};
  return e;
}
test"expand replaces load-time tokens"{
  const T=struct{a:[]const u8="",b:?[]const u8=null,c:[]const u8=""};
  var arena:ArenaAllocator=.init(testing.allocator);
  defer arena.deinit();
  const look=struct{
    fn f(w:*Writer,name:[]const u8)Writer.Error!bool{
      if(!eql(u8,name,"k"))return false;
      try w.writeAll("KEY");
      return true;
    }
  }.f;
  var badBuf:[maxKey]u8=undefined;
  var bad:Writer=.fixed(&badBuf);
  var t:T=.{.a="PRESS {@k} OR {@k} {0}",.b="{@k}",.c="PLAIN"};
  try expand(T,&t,arena.allocator(),look,&bad);
  try testing.expectEqualStrings("PRESS KEY OR KEY {0}",t.a);
  try testing.expectEqualStrings("KEY",t.b.?);
  try testing.expectEqualStrings("PLAIN",t.c);
  var u:T=.{.a="{@nope}"};
  try testing.expectError(error.UnknownToken,expand(T,&u,arena.allocator(),look,&bad));
  try testing.expectEqualStrings("nope",bad.buffered());
}
test"render fills positional templates"{
  var buf:[64]u8=undefined;
  try testing.expectEqualStrings("A 3 B 1.50 x",bufRender(&buf,"{1} {0} {2} {3:.2} x",.{@as(u32,3),"A","B",@as(f32,1.5)}));
  try testing.expectEqualStrings("{x} 2%",bufRender(&buf,"{{x} {0}%",.{@as(f32,2.4)}));
  try testing.expectEqualStrings("OutOfMemory",bufRender(&buf,"{0}",.{error.OutOfMemory}));
  try testing.expectEqualStrings("ab",bufRender(buf[0..2],"abcdef",.{}));
}
test"lists"{
  try testing.expectEqualStrings("SOUTH",nth("EAST | SOUTH | WEST",1));
  try testing.expectEqualStrings("",nth("EAST",3));
  try testing.expectEqual(3,count("a|b|c"));
}
test"parse fills, rejects unknown and missing keys"{
  const E=enum{a,b};
  const T=struct{
    top:[]const u8="",
    sec:struct{x:[]const u8="",y:?[]const u8=null}=.{},
    tab:EnumArray(E,struct{name:[]const u8=""})=.initFill(.{}),
  };
  var t:T=.{};
  var badBuf:[maxKey]u8=undefined;
  var bad:Writer=.fixed(&badBuf);
  try parse(T,&t,"# c\ntop = HI {0}\n[sec]\nx = X = 1\n[tab]\na.name = A\nb.name=B\n",&bad);
  try testing.expectEqualStrings("HI {0}",t.top);
  try testing.expectEqualStrings("X = 1",t.sec.x);
  try testing.expectEqual(null,t.sec.y);
  try testing.expectEqualStrings("B",t.tab.get(.b).name);
  var u:T=.{};
  try testing.expectError(error.UnknownKey,parse(T,&u,"nope = 1",&bad));
  try testing.expectEqualStrings("nope",bad.buffered());
  u=.{};
  bad.end=0;
  try testing.expectError(error.MissingKey,parse(T,&u,"top = 1\nsec.x = 2\ntab.a.name = A",&bad));
  try testing.expectEqualStrings("tab.b.name",bad.buffered());
}
