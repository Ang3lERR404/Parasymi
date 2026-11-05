//! the command line's flags, read once at the edge: `--name` or
//! `--name=value` split a single time and the name turned into the caller's
//! own flag enum, so past here a flag is a tag the caller `switch`es on
//! (exhaustively: a flag it forgets won't build), never a string held
//! against every name. A name the enum can't spell plainly is a tag like
//! `@"long-name"`, keeping its own spelling.
const std=@import("std");
/// the standard library's test helpers
const testing=std.testing;
/// whether a string begins with another
const startsWith=std.mem.startsWith;
/// where a byte first stands in a string
const indexOfScalar=std.mem.indexOfScalar;
/// an enum's tag named by a string
const stringToEnum=std.meta.stringToEnum;
/// a string's leading `--`, which every flag starts with
const lead="--";
/// one argument read as a flag of enum `E`: which it is, and what follows
/// its `=` (null: no `=`, as `--demo`; empty: `--name=`)
pub fn Flag(comptime E:type)type{
  return struct{
    /// which flag it is
    name:E,
    /// what follows its `=`, if it has one
    value:?[]const u8,
  };
}
/// argument `a` as a flag of enum `E`, or null when it is none of them (no
/// leading `--`, or a name `E` has no tag for)
pub fn parse(comptime E:type,a:[]const u8)?Flag(E){
  if(!startsWith(u8,a,lead))return null;
  // the flag past its `--`, and where its `=` stands, if anywhere
  const rest=a[lead.len..];
  const eq=indexOfScalar(u8,rest,'=');
  // the flag's name, as the enum spells it
  const name=stringToEnum(E,if(eq)|i|rest[0..i]else rest) orelse return null;
  return.{.name=name,.value=if(eq)|i|rest[i+1..]else null};
}
test"a flag is split once at its `=`, its name the caller's tag, its value what follows"{
  // a caller's flags, one spelled with a hyphen
  const F=enum{demo,plant,@"long-name"};
  try testing.expectEqual(F.demo,parse(F,"--demo").?.name);
  try testing.expect(parse(F,"--demo").?.value==null);
  // the value keeps every later `=`, and may be empty
  const p=parse(F,"--plant=a=b").?;
  try testing.expectEqual(F.plant,p.name);
  try testing.expectEqualStrings("a=b",p.value.?);
  try testing.expectEqualStrings("",parse(F,"--plant=").?.value.?);
  try testing.expectEqual(F.@"long-name",parse(F,"--long-name=3").?.name);
  // not a flag, or not one of these: none
  try testing.expect(parse(F,"demo")==null);
  try testing.expect(parse(F,"-demo")==null);
  try testing.expect(parse(F,"--nope")==null);
  try testing.expect(parse(F,"--plan=x")==null);
}
