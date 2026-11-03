//! `--plant=<species>` / `--structure=<kind>`: one plant or structure alone
//! (or `--samples=<mesh>,...`: library meshes side by side along the x
//! axis, to compare looks; or `--sculpt=<name>`: one of the gardener's
//! sculpts, looping its clip)
//! in the world, held in one state or looping one animation (`--state=`,
//! `--period=`), for testing how it grows, looks and works. Nothing else is
//! put down or drawn (no wolf or motes; a plant has no nodes or structures
//! round it, a structure keeps the world's resource nodes, which it may
//! work), and the renderer builds only the meshes it draws (`only`). Not
//! part of play: it sets the thing's state itself.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the specimen's plant, structure and mesh list need
const Allocator=std.mem.Allocator;
/// reads a species, structure kind or state from its name
const stringToEnum=std.meta.stringToEnum;
/// reads a share of growth
const parseFloat=std.fmt.parseFloat;
/// finds the `..` in a span
const indexOf=std.mem.indexOf;
/// are two strings equal?
const eql=std.mem.eql;
/// every tag of an enum: tile kinds, items, studies
const values=std.enums.values;
/// reads the names in a list of samples
const tokenizeScalar=std.mem.tokenizeScalar;
/// tells a sample's structure by the start of its name
const startsWith=std.mem.startsWith;
/// finds a mesh among those a structure declares
const indexOfScalar=std.mem.indexOfScalar;
/// the test harness
const testing=std.testing;
/// the engine package
const engine=lib.engine;
/// all the maths: tiles, rings, easing
const m=engine.core.math;
/// the chunk grid: tiles, kinds and heights
const ck=lib.ck;
/// the species registry: sizes, floating, mana, radiance
const species=lib.species;
/// what can be held: every item, to feed a structure
const items=lib.items;
/// the mesh library: ids for the meshes to build
const meshlib=lib.meshlib;
/// the plant mesh builder, for its levels of detail
const meshgen=lib.meshgen;
/// the garden's renderer, told which meshes to build
const renderer=lib.renderer;
/// the structures registry: placing, feeding, meshes, emitting
const st=lib.structures;
/// the research tree, for an arsthraxia's study
const prog=lib.progression;
/// what each kind of ground's nodes give and look like
const resources=lib.resources;
/// the scene's list of moving parts (the mesh test)
const Parts=lib.parts.Parts;
/// the game's state and its tick
const play=lib.play;
/// the wolf's actions, for turning a thing as R does
const actions=lib.actions;
/// how a turn is timed
const turn=lib.turn;
/// the whole running game the specimen stands in
const Game=play.Game;
/// tells why a structure could not be put down
const diag=lib.diagnostics;
/// a loop's animation runs `period` seconds, then holds its end this long
/// before it starts again
const holdTime:f32=1.5;
/// seconds a loop runs unless `--period` says
/// long enough for a weave or a study unit
const period:f32=8;
/// an active structure's loop: long enough for a weave or a study unit
const activePeriod:f32=30;
/// turning, it turns a quarter this often (s) unless `--period` says
const turnPeriod:f32=turn.time+1;
/// live, a grown (or dead) plant is sown afresh this long after
const regrow:f32=4;
/// a lone water plant's pond: how deep it is filled (m), the spring's reach
/// (units) and how much it pours a second (field units)
const pondDeep:f32=0.2;
const pondReach:f32=2.5;
const pondPour:f32=3;
/// how long the spring pours at most (s of the world's clock): on a slope
/// the water runs off and its tile may never fill, and pools last an hour,
/// so a spring left pouring floods the land round it
const pondFor:f32=90;
/// held, a plant never grows on its own
const never:f32=1e9;
/// a sculpt's clip is timed by the game's clock wrapped this often (s),
/// so a long run keeps its precision
const loopWrap:f64=3600;
/// a tile to sow on: searched this far round the wolf
const search:i32=8;
/// active, a structure is handed one of what it wants this often (s), and
/// what it made is taken from it
const feedRate:f32=0.4;
/// a carrier lets go of what it carries this long after taking it (s),
/// since nothing stands ahead to take it
const carry:f32=2;
/// plucked, the wolf starts this far (m) from its footprint's edge
const standBack:f32=1.2;
/// the specimen's seed (its variant, its phase)
const seed:f32=0.37;
/// samples laid out this many tiles apart along the x axis
const sampleGap:i32=3;
/// the most samples laid out at once
pub const maxSamples=8;
/// library meshes to compare, laid out in a line along the x axis
pub const Samples=struct{
  /// the meshes, the first `n` in use
  ids:[maxSamples]meshlib.Id=undefined,
  /// how many are in use
  n:usize=0,
  /// the meshes in use, in the order they stand along x
  pub fn list(s:*const Samples)[]const meshlib.Id{return s.ids[0..s.n];}
  /// reads `a,b,c`: library mesh names, at least one, at most `maxSamples`
  pub fn parse(text:[]const u8)error{BadSample}!Samples{
    // the samples read so far, and the walk over the names
    var s=Samples{};
    var it=tokenizeScalar(u8,text,',');
    while(it.next())|name|{
      if(s.n==maxSamples)return error.BadSample;
      s.ids[s.n]=stringToEnum(meshlib.Id,name) orelse return error.BadSample;
      s.n+=1;
    }
    if(s.n==0)return error.BadSample;
    return s;
  }
};
/// how a sample sways and how full of sap it shows: as the structure whose
/// mesh its name begins with (`polypColony` as the polyp)
const Like=struct{
  /// how far it bends in the garden's wind
  sway:f32=0.4,
  /// the height it bends over
  tall:f32=1,
  /// how full of sap it shows
  sap:f32=1,
};
/// what stands alone
pub const Subject=union(enum){
  /// a plant of a species
  plant:species.Id,
  /// a structure of a kind
  structure:st.Kind,
  /// library meshes side by side along the x axis
  samples:Samples,
  /// the gardener's sculpt on the shelf at this place (sculpts.zig)
  sculpt:u8,
};
/// how the specimen is shown: grown in a loop, held still, worn out, or left live
pub const State=union(enum){
  /// grows from nothing to grown, again and again
  grow,
  /// growth from one share to another, again and again
  span:m.Vice(f32,2),
  /// held at one share of growth (`mature`: grown)
  held:f32,
  /// a plant grown, its health failing to nothing, again and again (a
  /// radiant plant comes loose, its light dims)
  wither,
  /// a plant grown, sap rising through it and ebbing (flow), round and round
  flow,
  /// a plant grown, its mana draining to empty, again and again
  drain,
  /// a plant grown, a celestial bloom's network dark
  dark,
  /// a plant sown and left to the ecology as in play; sown afresh once grown
  live,
  /// a structure grown and working: fed what it wants, what it makes taken
  /// away, put down afresh each loop (its emitted pieces as in play)
  active,
  /// grown, turned a quarter (R) each loop: a rooted one uproots itself on
  /// its roots, turns and digs back in; a floater only turns
  turn,
  /// a plant grown and ripe, plucked by the wolf (drawn beside it) as
  /// harvest does it in play, ripened afresh each loop
  pluck,
  /// a plant grown, its yield ripening from nothing to full in its pods,
  /// again and again
  ripen,
  /// a radiant plant grown, glitching, shattering and blinking out as the
  /// unforming takes it, again and again (game/unforming.zig)
  unform,
  /// shown as set from outside (the animation editor, tools/animedit.zig)
  look:Look,
  /// a name, a share of growth (`0.4`) or a span (`0.2..0.8`)
  pub fn parse(s:[]const u8)error{BadState}!State{
    if(eql(u8,s,"mature") or eql(u8,s,"idle"))return.{.held=1};
    if(stringToEnum(enum{grow,wither,flow,drain,dark,live,active,turn,pluck,ripen,unform},s))|k|return switch(k){
      .grow=>.grow,.wither=>.wither,.flow=>.flow,.drain=>.drain,.dark=>.dark,.live=>.live,.active=>.active,.turn=>.turn,.pluck=>.pluck,.ripen=>.ripen,.unform=>.unform,
    };
    if(indexOf(u8,s,".."))|dots|{
      // where the dots are, and the shares either side of them
      const a=parseFloat(f32,s[0..dots]) catch return error.BadState;
      const b=parseFloat(f32,s[dots+2..]) catch return error.BadState;
      return.{.span=.{m.clamp01(a),m.clamp01(b)}};
    }
    return.{.held=m.clamp01(parseFloat(f32,s) catch return error.BadState)};
  }
  /// whether a subject can show it (growth states suit both; plants
  /// wither, flow, drain, darken, live and are plucked; structures work)
  pub fn suits(s:State,what:Subject)bool{
    return switch(s){
      .grow,.span,.held=>true,
      .turn,.look=>what!=.samples and what!=.sculpt,
      .wither,.flow,.drain,.dark,.live,.pluck,.ripen=>what==.plant,
      .unform=>switch(what){.plant=>|sp|lib.unforming.radiant(sp) or lib.unforming.dies(sp),.structure,.samples,.sculpt=>false},
      .active=>what==.structure,
    };
  }
};
/// what it shows this moment (a structure: `growth` only)
pub const Look=struct{
  /// how grown, 0..1
  growth:f32=1,
  /// how full of mana, 0..1 of its cap
  mana:f32=1,
  /// how much sap rises through it, 0..1
  flow:f32=0,
  /// how healthy, 0..1
  health:f32=1,
  /// how ripe its yield, 0..1 of its cap (its pods swell with it)
  ripe:f32=0,
  /// whether its radiance network is lit
  radiating:bool=true
};
/// one plant or structure alone: what it is, how it is shown, its clock
/// and the tile it stands on
pub const Specimen=struct{
  /// what stands alone
  what:Subject,
  /// how it is shown
  state:State=.grow,
  /// seconds one loop's animation runs (unset: `period`, `activePeriod`)
  period:?f32=null,
  /// seconds into the loop
  t:f32=0,
  /// active: seconds to the next feeding
  feedT:f32=0,
  /// active: seconds since its carried item came
  carryT:f32=0,
  /// the tile it stands on (found by `sow`)
  at:m.Vice(i32,2)=.{0,0},
  /// a structure: the share of light it is held in (`--lit=`; unset, the
  /// light grid's, none alone), its crown gathering and ley-blue following
  lit:?f32=null,
  /// a structure: the crown it is given (`--crown=`; unset, its seed's)
  crown:?lib.lightCrown.Design=null,
  /// whether the wolf is drawn beside it (plucking it)
  pub fn wolf(s:*const Specimen)bool{return s.state==.pluck;}
  /// the meshes to build: the species' (and a floater's shadow; the wolf's
  /// plucking it), or what the structure draws and the resource nodes round it
  pub fn only(s:*const Specimen,arena:Allocator)Allocator.Error!renderer.Only{
    switch(s.what){
      .plant=>|sp|{
        // what it draws with, and (a water plant's pond grows them) the wild flowers
        var list:std.ArrayList(meshlib.Id)=.empty;
        try list.appendSlice(arena,if(s.wolf())&.{.shadow,.turnRoot,.turnRootPale,.wolfBody,.wolfEars,.wolfPanel,.bellyLump,.itemPod,.pluckBurst,.wolfBelly,.wolfPecL,.wolfPecR,.wolfRumpL,.wolfRumpR,.pawPad,.pawBean}else&.{.shadow,.turnRoot,.turnRootPale});
        if(species.get(sp).onWater)try list.appendSlice(arena,&lib.wild.meshes);
        return.{.species=sp,.parts=list.items};
      },
      .structure=>|k|{
        // the meshes, gathered
        var list:std.ArrayList(meshlib.Id)=.empty;
        try list.appendSlice(arena,st.meshes(k));
        try list.appendSlice(arena,&.{.turnRoot,.turnRootPale});
        for(values(ck.Kind))|t|if(resources.of(t))|n|try list.append(arena,n.mesh);
        return.{.parts=list.items};
      },
      .samples=>|sm|{
        // the samples, and what glows with each
        var list:std.ArrayList(meshlib.Id)=.empty;
        try list.appendSlice(arena,sm.list());
        for(sm.list())|id|for(meshlib.glows(id))|gl|try list.append(arena,stringToEnum(meshlib.Id,gl.mesh).?);
        return.{.parts=list.items};
      },
      .sculpt=>|i|return.{.parts=meshlib.sculptSlots[i..i+1]},
    }
  }
  /// put it down on the free tile nearest the wolf (a structure beside a
  /// resource node if one is near, for it may work it) and stand the wolf
  /// (and the camera) over it
  pub fn sow(s:*Specimen,g:*Game)Allocator.Error!void{
    if(s.state==.active)study(g);
    // the wolf's tile, and whether a tile has been found
    const cx,const cz=m.tileAt(g.player.pos);
    var found=false;
    for([_]bool{true,false})|byNode|{
      // (samples stand anywhere)
      if(byNode and (s.what==.samples or s.what==.sculpt))continue;
      // the ring being searched, outward from the wolf
      var r:i32=0;
      find:while(r<search):(r+=1){
        // the walk round that ring
        var it=m.ring(r);
        while(it.next())|o|{
          // the tile tried
          const x=cx+o[0];
          const z=cz+o[1];
          if(!s.fits(g,x,z)or(byNode and !nodeNear(g,x,z)))continue;
          s.at=.{x,z};
          found=true;
          break:find;
        }
      }
      if(found or s.what==.plant)break;
    }
    if(!found)switch(s.what){
      .structure=>|k|{
        s.at=.{cx,cz};
        // the structure's def, its size, and the ground it may first stand on
        const sdef=st.defs.get(k);
        const size=sdef.size;
        const fallback=st.firstGround(k);
        // the wolf's chunk, and the ground height under the wolf
        const c0=g.world.chunkOfTile(cx,cz) orelse return;
        const h0=c0.height[ck.localIndex(cx,cz)];
        // every tile of the footprint, row by row (not just its diagonal)
        for(0..size)|dx|for(0..size)|dz|{
          // the tile in the footprint, flattened to that ground
          const lx=cx+@as(i32,@intCast(dx));
          const lz=cz+@as(i32,@intCast(dz));
          if(g.world.chunkOfTile(lx,lz))|c|{
            // the tile within its chunk
            const t=ck.localIndex(lx,lz);
            c.kind[t]=fallback;
            c.height[t]=h0;
          }
        };
      },
      else=>{}
    };
    try s.put(g);
    // its footprint's size, and how far it hovers
    const size:u8,const up:f32=switch(s.what){
      .plant=>|sp|.{if(species.get(sp).floating)1 else species.get(sp).size,0},
      .structure=>|k|.{st.defs.get(k).size,st.defs.get(k).hover},
      .samples,.sculpt=>.{1,0},
    };
    g.player.pos=m.footprintCentre(s.at[0],s.at[1],size,g.heightAt(s.at[0],s.at[1]));
    g.cam.target=g.player.pos+m.v3(0,up,0);
    // plucking, the wolf stands back from it and steps up to it
    if(s.wolf())g.player.pos[2]-=standBack+m.f(size)*0.5;
  }
  /// whether it may stand at (x, z)
  fn fits(s:*const Specimen,g:*const Game,x:i32,z:i32)bool{
    return switch(s.what){
      .plant=>|sp|g.plants.canPlace(&g.world,x,z,sp),
      .structure=>|k|g.structs.canPlace(&g.world,x,z,k),
      .samples,.sculpt=>true,
    };
  }
  /// puts it down at its tile, as its state shows it now
  fn put(s:*Specimen,g:*Game)Allocator.Error!void{
    // what it shows now
    const l=s.look();
    switch(s.what){
      .plant=>|sp|_=try g.plants.placeEx(g.gpa,&g.world,s.at[0],s.at[1],.{
        .x=s.at[0],.y=s.at[1],.chunk=undefined,.tile=undefined,.sp=sp,.seed=seed,
        .growth=if(s.state==.live)0 else l.growth,.span=if(s.state==.live)0 else never,
      }),
      .structure=>|k|{
        // whether it took root
        const ok=try g.structs.place(g.gpa,&g.world,s.at[0],s.at[1],k,0,if(s.crown)|c|lib.lightCrown.seedOf(c)else seed);
        if(!ok)diag.whyNot(&g.structs,&g.world,s.at[0],s.at[1],k);
        // (put down as by the gardener's hand, in the garden's act: a
        // strange seed shown in act 2 is planted)
        if(ok)st.sown(g.structs.get(.of(g.structs.list.items.len-1)),g.act);
        if(g.structs.list.items.len>0)g.structs.list.items[0].grown=l.growth;
      },
      // (samples and sculpts are drawn, never put down: `drawSamples`)
      .samples,.sculpt=>{},
    }
  }
  /// one tick before the world's: held, it is set as its state says and
  /// the world's tick is left out (whether this tick is handled); live or
  /// active, the world runs (`after` it)
  pub fn hold(s:*Specimen,g:*Game,dt:f32)Allocator.Error!bool{
    if(s.state==.live or s.state==.active)return false;
    s.t+=dt;
    // what it shows this moment
    const l=s.look();
    // turning: a quarter each loop, as R does it in play
    if(s.state==.turn){
      s.feedT-=dt;
      if(s.feedT<=0){
        s.feedT=s.loop();
        _=actions.turnAt(g,s.at,false);
      }
    }
    switch(s.what){
      .plant=>|sp|{
        // uprooted: back it comes
        if(g.plants.len()==0)try s.put(g);
        // its species, and the plant list's columns
        const def=species.get(sp);
        const p=g.plants.list.slice();
        p.items(.growth)[0]=l.growth;
        p.items(.mana)[0]=l.mana*def.manaCap;
        p.items(.flow)[0]=l.flow;
        p.items(.health)[0]=l.health;
        p.items(.span)[0]=never;
        // its yield, as ripe as its look (plucked, ripened full below)
        if(s.state!=.pluck)p.items(.essence)[0]=l.ripe*def.manaCap;
        // plucked: once the last pluck is done and its end held, ripened
        // afresh and harvested again
        if(s.state==.pluck){
          if(g.pluck!=null)s.feedT=holdTime;
          s.feedT-=dt;
          if(s.feedT<=0){
            p.items(.essence)[0]=def.manaCap;
            actions.harvest(g,s.at);
            s.feedT=holdTime;
          }
        }
        // unforming: the event held where it is this far through its shattering
        if(s.state==.unform)g.unforming=.{.phase=.shattering,.t=if(lib.unforming.radiant(sp))lib.unforming.momentOf(seed,s.share())else lib.unforming.witherMoment(seed,s.share())};
        // the light each relay carries; it alone, lit as its look says
        const lit=&g.eco.light.carried;
        try lit.resize(g.gpa,g.plants.len());
        lit.items[0]=if(def.lightNode() and l.radiating)1 else 0;
      },
      .structure=>{
        if(g.structs.list.items.len==0)try s.put(g);
        // it notices its neighbours (a conduit its arches) but never works
        lib.structures.Structures.linkWith(g.structCtx(.{}));
        if(g.structs.list.items.len==0)return false;
        // the one structure
        const one=&g.structs.list.items[0];
        one.grown=l.growth;
        one.activity=0;
        // held in light: its crown gathers and its ley-blue creeps as in play
        if(s.lit)|v|{
          one.lit=v;
          one.shine=m.damp(one.shine,v,lib.structures.shineEase,dt);
        }
      },
      .samples,.sculpt=>{},
    }
    return true;
  }
  /// samples: each mesh drawn on its own tile along the x axis, the line
  /// centred on its tile, grown as its state shows and swaying as its
  /// structure does; a sculpt: drawn on its tile, its bones turned by its
  /// clip looping
  pub fn drawSamples(s:*const Specimen,g:*Game)Allocator.Error!void{
    // the samples (none: nothing to draw)
    const sm=switch(s.what){
      .samples=>|x|x,
      .sculpt=>|i|return drawSculpt(g,i,m.footprintCentre(s.at[0],s.at[1],1,g.heightAt(s.at[0],s.at[1]))),
      .plant=>|sp|return pond(g,sp,s.at),
      .structure=>return,
    };
    // what they show this moment
    const l=s.look();
    for(sm.list(),0..)|id,i|{
      // its tile along the line, and the middle of it on the ground
      const x=s.at[0]+@divFloor((@as(i32,@intCast(i))*2-@as(i32,@intCast(sm.n-1)))*sampleGap,2);
      const at=m.footprintCentre(x,s.at[1],1,g.heightAt(x,s.at[1]));
      // how it sways
      const like=likeOf(id);
      // (a skinned sample: posed by its bones, on the game's clock)
      if(meshlib.poser(id))|pose|{
        // its bones now, and where they go in this frame's list
        var bones:[meshlib.maxPoseBones]m.M4=undefined;
        const n=pose(@floatCast(@mod(g.time,loopWrap)),m.translate(at),&bones);
        const base=try g.parts.pose(bones[0..n]);
        try g.parts.emitSkinned(id,base,at,.{.phase=seed});
        continue;
      }
      try g.parts.emit(id,m.translate(at),.{.phase=seed,.fade=like.sap,.sway=like.sway,.tall=like.tall,.grown=l.growth});
      // what glows with it, lit from within, throwing its light
      for(meshlib.glows(id))|gl|{
        // the glowing mesh (a name the library lacks: a bug in the sample)
        const mesh=stringToEnum(meshlib.Id,gl.mesh).?;
        try g.parts.emit(mesh,m.chain(&.{m.translate(at+gl.at),m.scale3(m.splat3(gl.scale))}),.{.phase=seed,.glow=gl.glow,.sway=like.sway,.tall=like.tall,.grown=l.growth});
        try g.parts.light(at+gl.at,gl.light,gl.reach);
      }
    }
  }
  /// the `i`th sculpt standing at `at`, its bones where its clip has them now
  /// a plant that floats on water (`Species.onWater`) shown alone: a
  /// spring pours rain onto the ground round its tile until the water
  /// stands `pondDeep` over it (for `pondFor` at most), so it floats on a pond
  fn pond(g:*Game,sp:species.Id,at:m.Vice(i32,2))Allocator.Error!void{
    if(!species.get(sp).onWater or g.time>pondFor)return;
    // the chunk under it, and how deep the water stands there now
    const c=g.world.chunkOfTile(at[0],at[1]) orelse return;
    if(c.pool[ck.localIndex(at[0],at[1])]>=pondDeep)return;
    // the spring, in the middle of its tile
    const mid=m.footprintCentre(at[0],at[1],1,0);
    try g.parts.spring(.{mid[0],mid[2]},pondReach,pondPour);
  }
  fn drawSculpt(g:*Game,i:u8,at:m.V3)Allocator.Error!void{
    // the sculpt, its bones now, and where they go in this frame's list
    const k=&lib.sculpts.all()[i];
    var bones:[lib.sculptRig.maxBones]m.M4=undefined;
    const n=k.bonesAt(@floatCast(@mod(g.time,loopWrap)),m.translate(at),&bones);
    const base=try g.parts.pose(bones[0..n]);
    try g.parts.emitSkinned(meshlib.sculptSlots[i],base,at,.{.phase=seed});
  }
  /// after the world's tick. A live plant, once grown (or gone) and left a
  /// while, is sown afresh; an active structure is fed, emptied of what it
  /// made, and put down afresh each loop.
  pub fn after(s:*Specimen,g:*Game,dt:f32)Allocator.Error!void{
    switch(s.state){
      .live=>{
        // whether the plant is gone (uprooted, withered)
        const gone=g.plants.len()==0;
        if(!gone and g.plants.list.items(.growth)[0]<1)return;
        s.t+=dt;
        if(s.t<regrow)return;
        s.t=0;
        if(!gone)g.plants.remove(&g.world,.of(0));
        try s.put(g);
      },
      .active=>{
        s.t+=dt;
        // whether the structure is gone
        const gone=g.structs.list.items.len==0;
        if(gone or s.t>=s.loop()){
          s.t=0;
          // what it put down (a polyp's diamond) goes with it
          while(g.structs.list.items.len>0){
            // the last structure, lifted out and freed
            var goneS=g.structs.remove(&g.world,.of(g.structs.list.items.len-1));
            goneS.deinit(g.gpa);
          }
          try s.put(g);
        }
        s.feedT-=dt;
        s.carryT+=dt;
        if(s.feedT>0)return;
        s.feedT=feedRate;
        feed(s,g);
      },
      else=>{},
    }
  }
  /// one of the next thing it wants handed in (a carrier takes it in from
  /// behind), what it made taken away; a carrier lets go of what it has
  /// carried a while
  fn feed(s:*Specimen,g:*Game)void{
    // the structure: the only one
    const id:st.Id=.of(0);
    const one=g.structs.get(id);
    if(one.def().carrier){
      if(s.carryT>=carry)_=st.release(one);
    }else if(g.structs.output(id))|made|{
      if(g.structs.wants(&g.prog,id,made)==0)_=one.inv.take(made,1);
    }
    // every kind of item
    const all=values(items.Item);
    // a different kind each time, round all it takes
    // where in the list this feeding starts
    const from:usize=@intFromFloat(@mod(g.time*7+m.f(g.ticks),m.f(all.len)));
    for(0..all.len)|i|{
      // the item offered
      const item=all[(from+i)%all.len];
      if(!one.def().carrier and g.structs.wants(&g.prog,id,item)==0)continue;
      if(g.structs.handIn(&g.prog,id,item,2)){
        s.carryT=0;
        return;
      }
      if(one.def().carrier)return;
    }
  }
  /// seconds one loop runs
  fn loop(s:*const Specimen)f32{
    return s.period orelse switch(s.state){
      .active=>activePeriod,
      .turn=>turnPeriod,
      else=>period,
    };
  }
  /// how far through this loop's animation (0..1; 1 through the hold)
  fn share(s:*const Specimen)f32{
    // the loop's length
    const p=s.loop();
    return m.clamp01(@mod(s.t,p+holdTime)/p);
  }
  /// what it shows this moment, from its state and how far through the loop it is
  fn look(s:*const Specimen)Look{
    // how far through the loop
    const k=s.share();
    return switch(s.state){
      .grow=>.{.growth=k},
      .span=>|ab|.{.growth=m.lerp(ab[0],ab[1],k)},
      .held=>|h|.{.growth=h},
      .wither=>.{.health=1-k},
      .flow=>.{.flow=0.5-0.5*@cos(s.t/s.loop()*m.tau)},
      .drain=>.{.mana=1-k},
      .dark=>.{.radiating=false},
      .ripen=>.{.ripe=k},
      .live=>.{.growth=0},
      .look=>|l|l,
      .active,.turn,.pluck,.unform=>.{},
    };
  }
};
/// how sample `id` sways: as the structure whose mesh name its own begins
/// with, the longest such (none: `Like`'s defaults)
fn likeOf(id:meshlib.Id)Like{
  // the best match yet, and its name's length
  var best:?st.Kind=null;
  var len:usize=0;
  for(values(st.Kind))|k|{
    // the name of that structure's mesh
    const name=@tagName(st.defs.get(k).mesh);
    if(startsWith(u8,@tagName(id),name) and name.len>len){
      best=k;
      len=name.len;
    }
  }
  // the structure it is a look for
  const k=best orelse return.{};
  return.{.sway=st.defs.get(k).sway,.tall=st.defs.get(k).tall,.sap=st.defs.get(k).sap};
}
/// an arsthraxia studies what is chosen: the first open study that takes
/// ingredients
fn study(g:*Game)void{
  if(g.prog.current!=null)return;
  for(values(prog.Id))|id|if(g.prog.status(id)==.open and prog.tree.get(id).perUnit.len>0){
    g.prog.current=id;
    return;
  };
}
/// a resource node beside (x, z), edge to edge (what a digger digs, and
/// one of the eight tiles a lithophage drains)
fn nodeNear(g:*const Game,x:i32,z:i32)bool{
  for(m.dirs)|d|{
    // the way being looked
    const v=m.dirVec(d);
    // the chunk holding that tile (none: not streamed in), and the tile in it
    const c=g.world.chunkOfTile(x+v.x,z+v.z) orelse continue;
    const t=ck.localIndex(x+v.x,z+v.z);
    if(c.res[t]>0 and resources.of(c.kind[t])!=null)return true;
  }
  return false;
}
test"a state is a name, a share of growth or a span"{
  try testing.expect(try State.parse("grow")==.grow);
  try testing.expectEqual(@as(f32,1),(try State.parse("mature")).held);
  try testing.expectEqual(@as(f32,0.4),(try State.parse("0.4")).held);
  try testing.expectEqual(m.Vice(f32,2){0.2,0.8},(try State.parse("0.2..0.8")).span);
  try testing.expectError(error.BadState,State.parse("sideways"));
  try testing.expect((try State.parse("unform")).suits(.{.plant=.bloom}));
  try testing.expect((try State.parse("unform")).suits(.{.plant=.lumenroot}));
  try testing.expect(!(try State.parse("unform")).suits(.{.plant=.confluence}));
  try testing.expect((try State.parse("active")).suits(.{.structure=.germinator}));
  try testing.expect(!(try State.parse("wither")).suits(.{.structure=.germinator}));
}
test"samples are library mesh names, one to `maxSamples`, and sway as their structure"{
  // two meshes, read in order
  const s=try Samples.parse("polyp,shadow");
  try testing.expectEqualSlices(meshlib.Id,&.{.polyp,.shadow},s.list());
  try testing.expectError(error.BadSample,Samples.parse(""));
  try testing.expectError(error.BadSample,Samples.parse("polyp,nothing"));
  try testing.expect(!@as(State,.turn).suits(.{.samples=s}));
  try testing.expectEqual(st.defs.get(.polyp).sway,likeOf(.polyp).sway);
}
test"a loop runs its period, holds its end, then starts again"{
  // a plant looping every four seconds
  var s:Specimen=.{.what=.{.plant=.lumenroot},.period=4};
  s.t=2;
  try testing.expectApproxEqAbs(@as(f32,0.5),s.look().growth,1e-5);
  s.t=4+holdTime*0.5;
  try testing.expectEqual(@as(f32,1),s.look().growth);
  s.t=4+holdTime+1;
  try testing.expectApproxEqAbs(@as(f32,0.25),s.look().growth,1e-5);
}
test"held, the plant shows its state and nothing else grows it"{
  // the test allocator, and a fresh game
  const gpa=testing.allocator;
  var g=try Game.init(gpa,play.defaultSeed);
  defer g.deinit();
  g.specimen=.{.what=.{.plant=.vesper},.state=.{.held=0.5}};
  try g.specimen.?.sow(&g);
  try testing.expectEqual(@as(usize,1),g.plants.len());
  // a vesper out of radiance would wither: held, it does not
  for(0..120)|_|try g.step();
  try testing.expectEqual(@as(usize,1),g.plants.len());
  try testing.expectEqual(@as(f32,0.5),g.plants.list.items(.growth)[0]);
  try testing.expectEqual(@as(f32,1),g.plants.list.items(.health)[0]);
}
test"a structure alone draws only the meshes it declares"{
  // the test allocator
  const gpa=testing.allocator;
  for(values(st.Kind))|k|for([_]State{.grow,.active})|state|{
    // a fresh game
    var g=try Game.init(gpa,play.defaultSeed);
    defer g.deinit();
    g.specimen=.{.what=.{.structure=k},.state=state,.period=20};
    try g.specimen.?.sow(&g);
    try testing.expectEqual(@as(usize,1),g.structs.list.items.len);
    // the meshes the structure says it draws, and the parts collector
    const declared=st.meshes(k);
    var parts=Parts.init(gpa);
    defer parts.deinit();
    // a loop and a half, its pieces looked at four times a second
    // seconds looked at so far
    var t:f32=0;
    while(t<30):(t+=0.25){
      for(0..@intFromFloat(0.25/play.tickTime))|_|try g.step();
      parts.clear();
      for(g.structs.list.items)|*s|{
        // its centre on the ground
        const ctr=s.at+m.v3(0,g.heightAt(s.x,s.y),0);
        try st.emit(s,&parts,ctr,t);
      }
      for(parts.lists,0..)|l,slot|if(l.items.len>0){
        // the mesh this slot's instances belong to
        const id:meshlib.Id=@enumFromInt(slot/meshgen.lods);
        if(indexOfScalar(meshlib.Id,declared,id)==null){
          std.debug.print("{t} emits {t}, not in its `meshes`\n",.{k,id});
          return error.UndeclaredMesh;
        }
      };
    }
  };
}
