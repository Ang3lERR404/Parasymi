const std = @import("std");
const zon = @import("build.zig.zon");
const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;

/// every shader in `shaders/` is compiled to SPIR-V at build time and exposed
/// as an anonymous import named after its file (`@embedFile("terrain.vert")`).
const shaders = [_][]const u8{
  "terrain.vert", "terrain.frag", "detail.vert",
  "plant.vert", "plant.frag",
  "part.vert", "part.frag",
  "ui.vert", "ui.frag",
  "sky.vert", "sky.frag",
  "post.vert", "bloom_down.frag", "bloom_up.frag", "composite.frag", "fxaa.frag",
  "shadow.frag",
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

pub fn build(b:*Build) !void {
  const name = @tagName(zon.name);
  const saman = try std.SemanticVersion.parse(zon.version);
  const t = b.resolveTargetQuery(b.standardTargetOptionsQueryOnly(.{}));
  const o = b.standardOptimizeOption(.{
    .preferred_optimize_mode = .ReleaseFast
  });

  const sdk = b.graph.environ_map.get("VULKAN_SDK");
  const registry:Build.LazyPath = if (b.option([]const u8, "vk-registry", "path to vk.xml")) |p|
    .{.cwd_relative = p}
  else if (sdk) |s|
    .{.cwd_relative = b.pathJoin(&.{s, "share", "vulkan", "registry", "vk.xml"})}
  else
    @panic("set VULKAN_SDK or pass -Dvk-registry=<path to vk.xml>");
  const glslc = b.option([]const u8, "glslc", "path to glslc") orelse
    if (sdk) |s| b.pathJoin(&.{s, "Bin", "glslc"}) else "glslc";

  const vulkan = b.dependency("vulkan", .{.registry = registry}).module("vulkan-zig");
  const zglfw = b.dependency("zglfw", .{
    .target = t,
    .optimize = o,
    .import_vulkan = true,
  });
  const glfw_mod = zglfw.module("root");
  glfw_mod.addImport("vulkan", vulkan);

  // compile every shader once; both the game and the tests can import them
  var spvs:[names.len]Build.LazyPath = undefined;
  for (names, &spvs, 0..) |s, *spv, i| {
    const v:?[3][]const u8 = if (i < shaders.len) null else variants[i - shaders.len];
    const cmd = b.addSystemCommand(&.{glslc, "--target-env=vulkan1.3", "-O"});
    cmd.addPrefixedDirectoryArg("-I", b.path("shaders"));
    for ([_][]const u8{"common.glsl", "surface.glsl", "post.glsl"}) |inc| cmd.addFileInput(b.path(b.fmt("shaders/{s}", .{inc})));
    if (v) |vv| cmd.addArg(b.fmt("-D{s}", .{vv[2]}));
    // glslc reads the stage from the source's extension
    cmd.addFileArg(b.path(b.fmt("shaders/{s}", .{if (v) |vv| vv[1] else s})));
    cmd.addArg("-o");
    spv.* = cmd.addOutputFileArg(b.fmt("{s}.spv", .{s}));
  }

  const Mods = struct {
    fn make(bb:*Build, root:[]const u8, tt:Build.ResolvedTarget, oo:OptimizeMode, vk:*Build.Module, gm:*Build.Module, glfw:*Build.Step.Compile, sp:[]const Build.LazyPath) *Build.Module {
      const md = bb.createModule(.{
        .optimize = oo,
        .target = tt,
        .root_source_file = bb.path(root),
        .imports = &.{
          .{.name = "vulkan", .module = vk},
          .{.name = "zglfw", .module = gm},
        },
      });
      md.linkLibrary(glfw);
      for (names, sp) |s, spv| md.addAnonymousImport(s, .{.root_source_file = spv});
      // the game ships its strings and controls, writing them out where the
      // gardener can edit them; the tests check the strings file is complete
      for ([_][]const u8{"parasymi.cfg", "controls.cfg"}) |c| md.addAnonymousImport(c, .{.root_source_file = bb.path(c)});
      return md;
    }
  };
  const mod = Mods.make(b, "src/main.zig", t, o, vulkan, glfw_mod, zglfw.artifact("glfw"), &spvs);

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

  // logic tests (core/world/sim/game) need no window or GPU, but share the
  // game's imports so game-level code can be exercised headless.
  const tests = b.addTest(.{
    .root_module = Mods.make(b, "src/tests.zig", t, o, vulkan, glfw_mod, zglfw.artifact("glfw"), &spvs),
  });
  const test_step = b.step("test", "run unit tests.");
  test_step.dependOn(&b.addRunArtifact(tests).step);
}
