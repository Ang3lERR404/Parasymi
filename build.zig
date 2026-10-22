const std = @import("std");
const zon = @import("build.zig.zon");
const Build = std.Build;

/// every shader in `shaders/` is compiled to SPIR-V at build time and exposed
/// as an anonymous import named after its file (`@embedFile("terrain.vert")`).
const shaders = [_][]const u8{
  "terrain.vert", "terrain.frag",
  "plant.vert", "plant.frag",
  "part.vert", "part.frag",
  "ui.vert", "ui.frag",
  "sky.vert", "sky.frag",
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
  var spvs:[shaders.len]Build.LazyPath = undefined;
  for (shaders, &spvs) |s, *spv| {
    const cmd = b.addSystemCommand(&.{glslc, "--target-env=vulkan1.3", "-O"});
    cmd.addPrefixedDirectoryArg("-I", b.path("shaders"));
    cmd.addFileInput(b.path("shaders/common.glsl"));
    cmd.addFileArg(b.path(b.fmt("shaders/{s}", .{s})));
    cmd.addArg("-o");
    spv.* = cmd.addOutputFileArg(b.fmt("{s}.spv", .{s}));
  }

  const Mods = struct {
    fn make(bb:*Build, root:[]const u8, tt:Build.ResolvedTarget, oo:std.builtin.OptimizeMode, vk:*Build.Module, gm:*Build.Module, glfw:*Build.Step.Compile, sp:[]const Build.LazyPath) *Build.Module {
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
      for (shaders, sp) |s, spv| md.addAnonymousImport(s, .{.root_source_file = spv});
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
