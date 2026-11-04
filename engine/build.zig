//! builds the engine as the module `engine` (Vulkan through vulkan-zig,
//! windows through zglfw, WASAPI through zig-wsapi, its shaders compiled to SPIR-V and embedded) and
//! its tests. A game's build.zig depends on it by path or URL and uses the
//! helpers below (`@import("engine")`) to find glslc and vk.xml and compile
//! its own shaders, which may `#include` the engine's (`light.glsl`,
//! `growth.glsl`).
const std=@import("std");
/// the build graph's types: steps, modules, lazy paths
const Build=std.Build;
/// cuts a list of defines at its commas
const splitScalar=std.mem.splitScalar;
/// the engine's own shaders, embedded in its module
const shaders=[_][]const u8{
  "post.vert","bloom_down.frag","bloom_up.frag","composite.frag","fxaa.frag",
  "ui.vert","ui.frag","shadow.frag","volume_compose.frag","cells.comp",
};
/// files the engine's shaders (and a game's) may include
pub const includes=[_][]const u8{"post.glsl","light.glsl","lighting.glsl","growth.glsl","volume.glsl"};
/// one shader to compile: `name` it is imported as, the `source` file it is
/// compiled from (`name` when null) and a `define` to compile it with
/// (several split by commas: "GLASS,RAY")
pub const Shader=struct{name:[]const u8,source:?[]const u8=null,define:?[]const u8=null};
/// glslc: the `glslc` option, else the Vulkan SDK's, else whichever is on
/// PATH. Returns the path (or bare name) the shader steps run.
pub fn glslc(b:*Build)[]const u8{
  // where the Vulkan SDK lies, if the environment says
  const sdk=b.graph.environ_map.get("VULKAN_SDK");
  return b.option([]const u8,"glslc","path to glslc") orelse
    if(sdk)|s|b.pathJoin(&.{s,"Bin","glslc"})else"glslc";
}
/// vk.xml: the `vk-registry` option, else the Vulkan SDK's. Panics when
/// neither is given, since nothing Vulkan can be generated without it.
pub fn registry(b:*Build)[]const u8{
  if(b.option([]const u8,"vk-registry","path to vk.xml"))|p|return p;
  // the Vulkan SDK's folder, which must be set when no option is
  const s=b.graph.environ_map.get("VULKAN_SDK") orelse
    @panic("set VULKAN_SDK or pass -Dvk-registry=<path to vk.xml>");
  return b.pathJoin(&.{s,"share","vulkan","registry","vk.xml"});
}
/// `s` from `dir` compiled to SPIR-V for Vulkan 1.3, its includes found in
/// `includeDirs` (`inputs`: the included files, so a change rebuilds it).
/// Returns the `.spv` the compile step leaves behind.
pub fn compile(b:*Build,glslcPath:[]const u8,dir:Build.LazyPath,includeDirs:[]const Build.LazyPath,inputs:[]const Build.LazyPath,s:Shader)Build.LazyPath{
  // the glslc run, optimising for size and speed
  const cmd=b.addSystemCommand(&.{glslcPath,"--target-env=vulkan1.3","-O"});
  for(includeDirs)|d|cmd.addPrefixedDirectoryArg("-I",d);
  for(inputs)|f|cmd.addFileInput(f);
  // each define, several split at commas ("GLASS,RAY")
  if(s.define)|d|{
    // the defines, one at a time
    var it=splitScalar(u8,d,',');
    while(it.next())|one|cmd.addArg(b.fmt("-D{s}",.{one}));
  }
  // glslc reads the stage from the source's extension
  cmd.addFileArg(dir.path(b,s.source orelse s.name));
  cmd.addArg("-o");
  return cmd.addOutputFileArg(b.fmt("{s}.spv",.{s.name}));
}
/// the engine's own build: its module (with Vulkan, GLFW and WASAPI wired
/// in, and its shaders embedded) and the `test` step that runs its tests
pub fn build(b:*Build)void{
  // the target and optimisation the caller chose
  const t=b.standardTargetOptions(.{});
  const o=b.standardOptimizeOption(.{});
  // where glslc lives, found once
  const glslcPath=glslc(b);
  // the Vulkan bindings, generated from vk.xml
  const vulkan=b.dependency("vulkan",.{.registry=@as(Build.LazyPath,.{.cwd_relative=registry(b)})}).module("vulkan-zig");
  // GLFW for windows and input, with Vulkan surfaces enabled
  const zglfw=b.dependency("zglfw",.{
    .target=t,
    .optimize=o,
    .import_vulkan=true,
  });
  // GLFW's Zig module, told where the Vulkan bindings are
  const glfwMod=zglfw.module("root");
  glfwMod.addImport("vulkan",vulkan);
  // the Windows audio bindings
  const wasapi=b.dependency("wasapi",.{.target=t,.optimize=o}).module("wasapi");
  // the engine itself, as the module a game imports
  const mod=b.addModule("engine",.{
    .target=t,
    .optimize=o,
    .root_source_file=b.path("src/engine.zig"),
    .imports=&.{
      .{.name="vulkan",.module=vulkan},
      .{.name="zglfw",.module=glfwMod},
      .{.name="wasapi",.module=wasapi},
    },
  });
  mod.linkLibrary(zglfw.artifact("glfw"));
  // the shader folder
  const dir=b.path("shaders");
  // every include file, so editing one recompiles the shaders that use it
  var inputs:[includes.len]Build.LazyPath=undefined;
  for(includes,&inputs)|i,*in|in.*=dir.path(b,i);
  for(shaders)|s|{
    mod.addAnonymousImport(s,.{.root_source_file=compile(b,glslcPath,dir,&.{dir},&inputs,.{.name=s})});
  }
  // the engine's logic tests need no window or GPU
  // `-Dtest-filter=<text>`: only the tests whose names hold it run (given
  // more than once, those holding any of them)
  const filters=b.option([]const []const u8,"test-filter","run only the tests whose names contain this")orelse&.{};
  const tests=b.addTest(.{.root_module=mod,.filters=filters});
  // the `test` step a caller (or `zig build test`) runs
  const testStep=b.step("test","run the engine's unit tests.");
  testStep.dependOn(&b.addRunArtifact(tests).step);
}
