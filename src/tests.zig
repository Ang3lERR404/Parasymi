//! pure-logic test root: no window, no GPU (the engine's own tests run beside these).
const lib = @import("lib.zig");
test {
  _ = lib.txt;
  _ = lib.controls;
  _ = lib.gen;
  _ = lib.world;
  _ = lib.ecology;
  _ = lib.items;
  _ = lib.progression;
  _ = lib.craft;
  _ = lib.plants;
  _ = lib.turn;
  _ = lib.structures;
  _ = lib.seeds;
  _ = lib.play;
  _ = lib.orbit;
  _ = lib.specimen;
  _ = lib.player;
  _ = lib.save;
  _ = lib.options;
  _ = lib.home;
  _ = lib.meshgen;
  _ = lib.growth;
  _ = lib.skeleton;
  _ = lib.wolf_belly;
  _ = lib.wolf_rump;
  _ = lib.radiant_kit;
}
