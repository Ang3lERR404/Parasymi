//! `--inspect`: the camera fixed on one thing (the wolf, the nearest plant
//! of a species or structure of a kind, or a tile), turning slowly round
//! it and asking for a screenshot at evenly spaced bearings; once every
//! shot is taken the game closes. For looking at visual work unattended.
//! `eyes` looks out of the wolf's own eyes instead, turning round where it
//! stands, `--pitch` down.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// reads a species or structure kind from its name
const stringToEnum=std.meta.stringToEnum;
/// reads a tile's coordinates
const parseInt=std.fmt.parseInt;
/// finds the comma in `x,z`
const indexOfScalar=std.mem.indexOfScalar;
/// formats a tile into a file name
const bufPrint=std.fmt.bufPrint;
/// are two strings equal?
const eql=std.mem.eql;
/// the test harness
const testing=std.testing;
/// all the maths: vectors, angles, footprints
const m=lib.engine.core.math;
/// the species registry, for the plants a focus names
const species=lib.species;
/// the structures registry, for the kinds a focus names
const st=lib.structures;
/// the game's state
const play=lib.play;
/// the whole running game the camera is set on
const Game=play.Game;
/// the point looked at sits this far above a thing's ground (the wolf's
/// follow height; floaters add their hover)
const focusUp:f32=0.6;
// decision: a structure is looked at halfway up its height (`Def.tall`),
// over its hover: its middle, so it sits at the frame's centre however
// low or tall it is
const tallFocus:f32=0.5;
/// what the camera turns round
pub const Focus=union(enum){
  /// the wolf, from behind and above
  player,
  /// out of the wolf's eyes (first person)
  eyes,
  /// the nearest plant of a species (the wolf itself while there is none)
  species:species.Id,
  /// the nearest structure of a kind (the wolf itself while there is none)
  structure:st.Kind,
  /// a tile, by its coordinates
  tile:[2]i32,
  /// reads a focus: `player`, `eyes`, a species or structure name, or `x,z`
  pub fn parse(s:[]const u8)error{BadFocus}!Focus{
    if(eql(u8,s,"player"))return.player;
    if(eql(u8,s,"eyes"))return.eyes;
    if(stringToEnum(species.Id,s))|id|return.{.species=id};
    if(stringToEnum(st.Kind,s))|k|return.{.structure=k};
    // where the comma is, and the coordinates either side of it
    const comma=indexOfScalar(u8,s,',') orelse return error.BadFocus;
    const x=parseInt(i32,s[0..comma],0) catch return error.BadFocus;
    const z=parseInt(i32,s[comma+1..],0) catch return error.BadFocus;
    return.{.tile=.{x,z}};
  }
  /// a short name for the focus, for screenshot file names (`buf` holds a tile's)
  pub fn name(f:Focus,buf:[]u8)[]const u8{
    return switch(f){
      .player=>"player",
      .eyes=>"eyes",
      .species=>|id|@tagName(id),
      .structure=>|k|@tagName(k),
      .tile=>|t|bufPrint(buf,"{d}_{d}",.{t[0],t[1]})catch"tile",
    };
  }
};
/// the turn round the focus: what is looked at, how long a turn takes, how
/// many shots, how far and how high, and how far along it is
pub const Orbit=struct{
  /// what the camera turns round
  focus:Focus=.player,
  /// seconds one full turn takes
  period:f32=24,
  /// how many shots are spread evenly round the turn
  shots:u32=8,
  /// how far the camera stands from the focus
  dist:f32=9,
  /// how high it looks down from, above the horizon (radians)
  pitch:f32=m.rad(35.0),
  /// seconds before the turn (and the first shot) starts: streaming,
  /// meshing and growth settle
  settle:f32=3,
  /// seconds since the orbit began
  t:f32=0,
  /// how many shots have been taken
  taken:u32=0,
  /// place the camera for this frame (after `Game.update`); true while a
  /// shot is due (it stays due until `took`)
  pub fn step(o:*Orbit,g:*Game,dt:f32)bool{
    o.t+=dt;
    // the bearing now (radians), the point looked at, and the camera
    const yaw=o.turn()*m.tau;
    const at=o.point(g);
    const c=&g.cam;
    if(o.focus==.eyes){
      c.yaw=yaw;
      c.view=.{.eyes=.{.pos=g.player.eyes(),.pitch=-o.pitch,.k=1}};
      g.sinceSave=0;
      g.hover=null;
      return o.due();
    }
    c.target=at;
    c.dist=o.dist;
    c.yaw=yaw;
    c.pitch=o.pitch;
    // decision: a free view aimed straight at the focus, so it sits at the
    // frame's centre at any pitch (following lifts the gaze below rest)
    // the cosine of the pitch, and the way out from the focus to the camera
    const cp=@cos(o.pitch);
    const out=m.v3(@sin(yaw)*cp,@sin(o.pitch),@cos(yaw)*cp);
    c.view=.{.free=.{.pos=at+out*m.splat3(o.dist),.yaw=yaw,.pitch=-o.pitch}};
    // the garden is not saved over while it is looked at, and the mouse
    // marks no tile
    g.sinceSave=0;
    g.hover=null;
    return o.due();
  }
  /// counts a shot taken
  pub fn took(o:*Orbit)void{o.taken+=1;}
  /// whether every shot is taken (the game may close)
  pub fn done(o:*const Orbit)bool{return o.taken>=o.shots;}
  /// how far round it has turned (turns)
  fn turn(o:*const Orbit)f32{return@max(o.t-o.settle,0)/o.period;}
  /// the next shot's bearing is reached
  fn due(o:*const Orbit)bool{
    return!o.done() and o.t>=o.settle and o.turn()*m.f(o.shots)>=m.f(o.taken);
  }
  /// the point the camera looks at: the wolf, a tile's centre, or the
  /// nearest plant of the species or structure of the kind (the wolf if none)
  fn point(o:*const Orbit,g:*const Game)m.V3{
    // the wolf's follow point
    const wolf=g.player.pos+m.v3(0,focusUp,0);
    switch(o.focus){
      .player,.eyes=>return wolf,
      .tile=>|t|return m.tileCentre(t[0],t[1],g.heightAt(t[0],t[1])+focusUp),
      .species=>|id|{
        // the plant list's columns
        const s=g.plants.list.slice();
        // the nearest so far, and how far it is
        var best:?m.V3=null;
        var near:f32=m.inf(f32);
        for(s.items(.sp),s.items(.x),s.items(.y),s.items(.at))|sp,x,y,at|if(sp==id){
          // the plant's species
          const def=species.get(sp);
          // its centre, lifted by the follow height and any hover
          const c=at+m.v3(0,g.heightAt(x,y)+focusUp+if(def.floating)def.hover else 0,0);
          // how far it is from the wolf
          const d=m.len(c-wolf);
          if(d<near){near=d;best=c;}
        };
        return best orelse wolf;
      },
      .structure=>|k|{
        // the nearest so far, and how far it is
        var best:?m.V3=null;
        var near:f32=m.inf(f32);
        for(g.structs.list.items)|*s|if(s.kind()==k){
          // the structure's kind
          const def=s.def();
          // its centre, halfway up its height and over any hover
          const c=s.at+m.v3(0,g.heightAt(s.x,s.y)+def.tall*tallFocus+def.hover,0);
          // how far it is from the wolf
          const d=m.len(c-wolf);
          if(d<near){near=d;best=c;}
        };
        return best orelse wolf;
      },
    }
  }
};
test"a focus is the wolf, a species, a structure or a tile"{
  try testing.expect(try Focus.parse("player")==.player);
  try testing.expect(try Focus.parse("diamond")==.structure);
  // a tile focus
  const t=try Focus.parse("-4,12");
  try testing.expectEqual([2]i32{-4,12},t.tile);
  try testing.expectError(error.BadFocus,Focus.parse("nowhere"));
  // room for its name
  var buf:[24]u8=undefined;
  try testing.expectEqualStrings("-4_12",t.name(&buf));
}
test"shots are due evenly round one turn, after the settle"{
  // a fast orbit, how many shots fell due, and seconds ticked
  var o:Orbit=.{.period=8,.shots=4,.settle=1};
  var due:u32=0;
  var t:f32=0;
  while(t<10):(t+=0.25){
    o.t=t;
    if(o.due()){
      // a quarter turn apart
      try testing.expectApproxEqAbs(m.f(o.taken)/4,o.turn(),0.05);
      due+=1;
      o.took();
    }
  }
  try testing.expectEqual(@as(u32,4),due);
  try testing.expect(o.done());
}
