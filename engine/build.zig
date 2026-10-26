//! builds the engine as the module `engine` (Vulkan through vulkan-zig,
//! windows through zglfw, its shaders compiled to SPIR-V and embedded) and
//! its tests. A game's build.zig depends on it by path or URL and uses the
//! helpers below (`@import("engine")`) to find glslc and vk.xml and compile
//! its own shaders, which may `#include` the engine's (`light.glsl`,
//! `growth.glsl`).
const std = @import("std");
const Build = std.Build;

/// the engine's own shaders, embedded in its module
const shaders = [_][]const u8{
  "post.vert", "bloom_down.frag", "bloom_up.frag", "composite.frag", "fxaa.frag",
  "ui.vert", "ui.frag", "shadow.frag",
};
/// files the engine's shaders (and a game's) may include
pub const includes = [_][]const u8{"post.glsl", "light.glsl", "growth.glsl"};

/// one shader to compile: `name` it is imported as, the `source` file it is
/// compiled from (`name` when null) and a `define` to compile it with
pub const Shader = struct { name:[]const u8, source:?[]const u8 = null, define:?[]const u8 = null };

/// glslc: the `glslc` option, else the Vulkan SDK's, else whichever is on PATH
pub fn glslc(b:*Build) []const u8 {
  const sdk = b.graph.environ_map.get("VULKAN_SDK");
  return b.option([]const u8, "glslc", "path to glslc") orelse
    if (sdk) |s| b.pathJoin(&.{s, "Bin", "glslc"}) else "glslc";
}

/// vk.xml: the `vk-registry` option, else the Vulkan SDK's
pub fn registry(b:*Build) []const u8 {
  if (b.option([]const u8, "vk-registry", "path to vk.xml")) |p| return p;
  const s = b.graph.environ_map.get("VULKAN_SDK") orelse
    @panic("set VULKAN_SDK or pass -Dvk-registry=<path to vk.xml>");
  return b.pathJoin(&.{s, "share", "vulkan", "registry", "vk.xml"});
}

/// `s` from `dir` compiled to SPIR-V for Vulkan 1.3, its includes found in
/// `include_dirs` (`inputs`: the included files, so a change rebuilds it)
pub fn compile(b:*Build, glslc_path:[]const u8, dir:Build.LazyPath, include_dirs:[]const Build.LazyPath, inputs:[]const Build.LazyPath, s:Shader) Build.LazyPath {
  const cmd = b.addSystemCommand(&.{glslc_path, "--target-env=vulkan1.3", "-O"});
  for (include_dirs) |d| cmd.addPrefixedDirectoryArg("-I", d);
  for (inputs) |f| cmd.addFileInput(f);
  if (s.define) |d| cmd.addArg(b.fmt("-D{s}", .{d}));
  // glslc reads the stage from the source's extension
  cmd.addFileArg(dir.path(b, s.source orelse s.name));
  cmd.addArg("-o");
  return cmd.addOutputFileArg(b.fmt("{s}.spv", .{s.name}));
}

pub fn build(b:*Build) void {
  const t = b.standardTargetOptions(.{});
  const o = b.standardOptimizeOption(.{});
  const glslc_path = glslc(b);

  const vulkan = b.dependency("vulkan", .{.registry = @as(Build.LazyPath, .{.cwd_relative = registry(b)})}).module("vulkan-zig");
  const zglfw = b.dependency("zglfw", .{
    .target = t,
    .optimize = o,
    .import_vulkan = true,
  });
  const glfw_mod = zglfw.module("root");
  glfw_mod.addImport("vulkan", vulkan);

  const mod = b.addModule("engine", .{
    .target = t,
    .optimize = o,
    .root_source_file = b.path("src/engine.zig"),
    .imports = &.{
      .{.name = "vulkan", .module = vulkan},
      .{.name = "zglfw", .module = glfw_mod},
    },
  });
  mod.linkLibrary(zglfw.artifact("glfw"));
  const dir = b.path("shaders");
  var inputs:[includes.len]Build.LazyPath = undefined;
  for (includes, &inputs) |i, *in| in.* = dir.path(b, i);
  for (shaders) |s| {
    mod.addAnonymousImport(s, .{.root_source_file = compile(b, glslc_path, dir, &.{dir}, &inputs, .{.name = s})});
  }

  // the engine's logic tests need no window or GPU
  const tests = b.addTest(.{.root_module = mod});
  const test_step = b.step("test", "run the engine's unit tests.");
  test_step.dependOn(&b.addRunArtifact(tests).step);
}
