const std = @import("std");
const zon = @import("build.zig.zon");
const Build = std.Build;

/// every shader in `shaders/` is compiled to SPIR-V at build time and exposed
/// as an anonymous import named after its file (`@embedFile("terrain.vert")`).
const shaders = [_][]const u8{
  "terrain.vert", "terrain.frag",
  "plant.vert", "plant.frag",
  "ui.vert", "ui.frag",
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

  const mod = b.createModule(.{
    .optimize = o,
    .target = t,
    .root_source_file = b.path("src/main.zig"),
    .imports = &.{
      .{.name = "vulkan", .module = vulkan},
      .{.name = "zglfw", .module = glfw_mod},
    },
  });
  mod.linkLibrary(zglfw.artifact("glfw"));

  for (shaders) |s| {
    const cmd = b.addSystemCommand(&.{glslc, "--target-env=vulkan1.3", "-O"});
    cmd.addPrefixedDirectoryArg("-I", b.path("shaders"));
    cmd.addFileInput(b.path("shaders/common.glsl"));
    cmd.addFileArg(b.path(b.fmt("shaders/{s}", .{s})));
    cmd.addArg("-o");
    const spv = cmd.addOutputFileArg(b.fmt("{s}.spv", .{s}));
    mod.addAnonymousImport(s, .{.root_source_file = spv});
  }

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

  // pure-logic tests (core/world/sim/game) need no window or GPU.
  const tests = b.addTest(.{
    .root_module = b.createModule(.{
      .optimize = o,
      .target = t,
      .root_source_file = b.path("src/tests.zig"),
    }),
  });
  const test_step = b.step("test", "run unit tests.");
  test_step.dependOn(&b.addRunArtifact(tests).step);
}
