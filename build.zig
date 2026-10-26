const std = @import("std");
const zon = @import("build.zig.zon");
const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;
/// the engine's build: glslc, vk.xml and shader compiling
const eb = @import("engine");

/// every shader in `shaders/` is compiled to SPIR-V at build time and exposed
/// as an anonymous import named after its file (`@embedFile("terrain.vert")`);
/// they may include the engine's (`light.glsl`).
const shaders = [_][]const u8{
  "terrain.vert", "terrain.frag", "detail.vert",
  "plant.vert", "plant.frag",
  "part.vert", "part.frag",
  "sky.vert", "sky.frag",
};
/// shaders compiled a second time from the same source with a define,
/// imported under their own name: (name, source, define). The glass
/// variants draw only the see-through fragments the plain ones skip; the
/// shadow variants place what casts into each cascade of the key light's
/// shadow map.
const variants = [_][3][]const u8{
  .{"plant_glass.frag", "plant.frag", "GLASS"},
  .{"part_glass.frag", "part.frag", "GLASS"},
  .{"plant_shadow.vert", "plant.vert", "SHADOW"},
  .{"part_shadow.vert", "part.vert", "SHADOW"},
};
const names = shaders ++ blk: {
  var n:[variants.len][]const u8 = undefined;
  for (variants, &n) |v, *o| o.* = v[0];
  break :blk n;
};
/// what the game's shaders include
const includes = [_][]const u8{"common.glsl", "surface.glsl"};

pub fn build(b:*Build) !void {
  const name = @tagName(zon.name);
  const saman = try std.SemanticVersion.parse(zon.version);
  const t = b.resolveTargetQuery(b.standardTargetOptionsQueryOnly(.{}));
  const o = b.standardOptimizeOption(.{
    .preferred_optimize_mode = .ReleaseFast
  });

  const glslc = eb.glslc(b);
  const eng = b.dependency("engine", .{
    .target = t,
    .optimize = o,
    .glslc = glslc,
    .@"vk-registry" = eb.registry(b),
  });
  const engine = eng.module("engine");

  // compile every shader once; both the game and the tests can import them
  const dir = b.path("shaders");
  const engine_dir = eng.path("shaders");
  var inputs:[includes.len + eb.includes.len]Build.LazyPath = undefined;
  for (includes, inputs[0..includes.len]) |i, *in| in.* = dir.path(b, i);
  for (eb.includes, inputs[includes.len..]) |i, *in| in.* = engine_dir.path(b, i);
  var spvs:[names.len]Build.LazyPath = undefined;
  for (names, &spvs, 0..) |s, *spv, i| {
    const v:?[3][]const u8 = if (i < shaders.len) null else variants[i - shaders.len];
    spv.* = eb.compile(b, glslc, dir, &.{dir, engine_dir}, &inputs, if (v) |vv| .{.name = s, .source = vv[1], .define = vv[2]} else .{.name = s});
  }

  const Mods = struct {
    fn make(bb:*Build, root:[]const u8, tt:Build.ResolvedTarget, oo:OptimizeMode, en:*Build.Module, sp:[]const Build.LazyPath) *Build.Module {
      const md = bb.createModule(.{
        .optimize = oo,
        .target = tt,
        .root_source_file = bb.path(root),
        .imports = &.{.{.name = "engine", .module = en}},
      });
      for (names, sp) |s, spv| md.addAnonymousImport(s, .{.root_source_file = spv});
      // the game ships its strings and controls (stock copies in `src/cfg/`),
      // writing them out to the gardener's folder (%LOCALAPPDATA%\Parasymi)
      // when missing; the tests check the strings file is complete
      for ([_][]const u8{"parasymi.cfg", "controls.cfg"}) |c| md.addAnonymousImport(c, .{.root_source_file = bb.path(bb.fmt("src/cfg/{s}", .{c}))});
      return md;
    }
  };
  const mod = Mods.make(b, "src/main.zig", t, o, engine, &spvs);

  const exe = b.addExecutable(.{
    .name = name,
    .version = saman,
    .root_module = mod,
  });
  b.installArtifact(exe);
  const run:struct{cmd:*Build.Step.Run, step:*Build.Step} = .{
    .cmd = b.addRunArtifact(exe),
    .step = b.step("run", "run the build.")
  };
  run.cmd.step.dependOn(b.getInstallStep());
  run.step.dependOn(&run.cmd.step);
  if (b.args) |args| run.cmd.addArgs(args);

  // logic tests (world/sim/game, and the engine's own) need no window or
  // GPU, but share the game's imports so game-level code can be exercised
  // headless.
  const tests = b.addTest(.{
    .root_module = Mods.make(b, "src/tests.zig", t, o, engine, &spvs),
  });
  const engine_tests = b.addTest(.{.root_module = engine});
  const test_step = b.step("test", "run unit tests.");
  test_step.dependOn(&b.addRunArtifact(tests).step);
  test_step.dependOn(&b.addRunArtifact(engine_tests).step);
}
