//! the editors' undo and redo: each settled state kept as the text its
//! file would hold, so going back is reading an older text again. A state
//! settles once the hands let go (no drag held, no name being typed): a
//! whole drag, or a whole typed name, is one step back.
/// the standard library, reached through the game's hub
const std=ps.std;
/// the allocator type the kept texts live in
const Allocator=std.mem.Allocator;
/// whether two byte strings are the same
const eql=std.mem.eql;
/// formats text into a fixed buffer (the tests' states)
const bufPrint=std.fmt.bufPrint;
/// the test helpers
const testing=std.testing;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the most steps kept back (the oldest let go past it)
pub const depth=256;
/// the steps back and forward from the state now, as texts
pub const History=struct{
  /// the allocator every kept text lives in
  gpa:Allocator,
  /// the states before this one, oldest first
  back:std.ArrayList([]u8)=.empty,
  /// the states undone, the next to redo last
  ahead:std.ArrayList([]u8)=.empty,
  /// the settled state now, as text
  now:[]u8,
  /// a history starting at `text`, nothing to undo or redo
  pub fn init(gpa:Allocator,text:[]const u8)Allocator.Error!History{
    return.{.gpa=gpa,.now=try gpa.dupe(u8,text)};
  }
  /// lets every kept text go
  pub fn deinit(h:*History)void{
    h.drop(&h.back);
    h.drop(&h.ahead);
    h.back.deinit(h.gpa);
    h.ahead.deinit(h.gpa);
    h.gpa.free(h.now);
  }
  /// every text in `list` let go, the list left empty
  fn drop(h:*History,list:*std.ArrayList([]u8))void{
    for(list.items)|t|h.gpa.free(t);
    list.clearRetainingCapacity();
  }
  /// the state `text` settled: if it differs from the last, the last
  /// becomes a step back and whatever was undone is forgotten; true if it
  /// was a new step
  pub fn settle(h:*History,text:[]const u8)Allocator.Error!bool{
    if(eql(u8,text,h.now))return false;
    // the new state's own copy, made before anything is let go
    const fresh=try h.gpa.dupe(u8,text);
    errdefer h.gpa.free(fresh);
    try h.back.append(h.gpa,h.now);
    h.now=fresh;
    h.drop(&h.ahead);
    if(h.back.items.len>depth)h.gpa.free(h.back.orderedRemove(0));
    return true;
  }
  /// one step back: the text to read again, null with nothing to undo
  pub fn undo(h:*History)Allocator.Error!?[]const u8{
    return h.step(&h.back,&h.ahead);
  }
  /// one step forward again: the text to read, null with nothing to redo
  pub fn redo(h:*History)Allocator.Error!?[]const u8{
    return h.step(&h.ahead,&h.back);
  }
  /// the last of `from` becomes the state now, the state now pushed onto `to`
  fn step(h:*History,from:*std.ArrayList([]u8),to:*std.ArrayList([]u8))Allocator.Error!?[]const u8{
    if(from.items.len==0)return null;
    try to.ensureUnusedCapacity(h.gpa,1);
    to.appendAssumeCapacity(h.now);
    h.now=from.pop().?;
    return h.now;
  }
};
test"undo walks back through settled states and redo walks forward"{
  // a history from "a", settled through "b" and "c"
  var h=try History.init(testing.allocator,"a");
  defer h.deinit();
  try testing.expect(!try h.settle("a"));
  try testing.expect(try h.settle("b"));
  try testing.expect(try h.settle("c"));
  try testing.expectEqualStrings("b",(try h.undo()).?);
  try testing.expectEqualStrings("a",(try h.undo()).?);
  try testing.expectEqual(null,try h.undo());
  try testing.expectEqualStrings("b",(try h.redo()).?);
  // a new state after an undo forgets what was undone
  try testing.expect(try h.settle("d"));
  try testing.expectEqual(null,try h.redo());
  try testing.expectEqualStrings("b",(try h.undo()).?);
}
test"the oldest step is let go past the depth"{
  // a history settled through more states than it keeps
  var h=try History.init(testing.allocator,"0");
  defer h.deinit();
  // each state's text
  var buf:[8]u8=undefined;
  for(1..depth+10)|i|_=try h.settle(try bufPrint(&buf,"{d}",.{i}));
  try testing.expectEqual(depth,h.back.items.len);
  // every undo there is, then none
  for(0..depth)|_|try testing.expect(try h.undo()!=null);
  try testing.expectEqual(null,try h.undo());
}
