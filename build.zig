//! the garden's build: compiles the shaders, then the game, the two editors,
//! the sound check and the headless tests, each its own `zig build` step.
/// the standard library: the build system lives in it
const std=@import("std");
/// the package manifest: the game's name and version
const zon=@import("build.zig.zon");
/// the build graph's root type
const Build=std.Build;
/// how hard the compiler tries: debug or one of the release modes
const OptimizeMode=std.builtin.OptimizeMode;
/// the engine's build: glslc, vk.xml and shader compiling
const eb=@import("engine");
/// every shader in `shaders/` is compiled to SPIR-V at build time and exposed
/// as an anonymous import named after its file (`@embedFile("terrain.vert")`);
/// they may include the engine's (`light.glsl`).
const shaders=[_][]const u8{
  "terrain.vert","terrain.frag","detail.vert",
  "plant.vert","plant.frag",
  "part.vert","part.frag",
  "sky.vert","sky.frag",
  "fog.vert","fog.frag",
  "moisture.vert","moisture.frag",
  "moisture_source.vert","moisture_source.frag",
  "rain.vert","rain.frag","pools.vert","pools.frag",
};
/// shaders compiled a second time from the same source with a define,
/// imported under their own name: (name, source, define). The glass
/// variants draw only the see-through fragments the plain ones skip; the
/// head variants shade the always-solid triangles, lighter; the
/// shadow variants place what casts into each cascade of the key light's
/// shadow map, the cube ones into each face of a point of light's shadow
/// cube; the overhead ones draw the ground from above for the fog;
/// the air ones light the fog round what glows; the ray ones trace their
/// shadows as rays where the GPU can (RAY), and the capture ones write out
/// the casters for them (CAPTURE).
const variants=[_][3][]const u8{
  .{"plant_ray.frag","plant.frag","RAY"},
  .{"plant_glass_ray.frag","plant.frag","GLASS,RAY"},
  .{"plant_head_ray.frag","plant.frag","HEAD,RAY"},
  .{"part_ray.frag","part.frag","RAY"},
  .{"part_glass_ray.frag","part.frag","GLASS,RAY"},
  .{"part_head_ray.frag","part.frag","HEAD,RAY"},
  .{"terrain_ray.frag","terrain.frag","RAY"},
  .{"pools_ray.frag","pools.frag","RAY"},
  .{"fog_ray.frag","fog.frag","RAY"},
  .{"plant_capture.vert","plant.vert","CAPTURE"},
  .{"part_capture.vert","part.vert","CAPTURE"},
  .{"plant_glass.frag","plant.frag","GLASS"},
  .{"plant_head.frag","plant.frag","HEAD"},
  .{"part_glass.frag","part.frag","GLASS"},
  .{"part_head.frag","part.frag","HEAD"},
  .{"plant_shadow.vert","plant.vert","SHADOW"},
  .{"part_shadow.vert","part.vert","SHADOW"},
  .{"plant_cube.vert","plant.vert","CUBE"},
  .{"part_cube.vert","part.vert","CUBE"},
  .{"part_air.vert","part.vert","AIR"},
  .{"part_air.frag","part.frag","AIR"},
  .{"terrain_overhead.vert","terrain.vert","OVERHEAD"},
  .{"terrain_overhead.frag","terrain.frag","OVERHEAD"},
};
/// every shader name the game imports: the plain ones, then each variant's own
const names=shaders++blk:{
  // one name per variant, gathered from its first column
  var n:[variants.len][]const u8=undefined;
  for(variants,&n)|v,*o|o.*=v[0];
  break:blk n;
};
/// what the game's shaders include
const includes=[_][]const u8{"common.glsl","surface.glsl","ground.glsl","air.glsl","moisture.glsl"};
/// builds the garden: compiles every shader, makes the game, `animedit`,
/// `meshedit` and `audiocheck`, and the `test` step that runs the game's,
/// the engine's and the mesh editor's tests
pub fn build(b:*Build)!void{
  // the executable's name, from the manifest
  const name=@tagName(zon.name);
  // the game's version, read from the manifest
  const saman=try std.SemanticVersion.parse(zon.version);
  // the target machine (Windows, the host's by default)
  const t=b.resolveTargetQuery(b.standardTargetOptionsQueryOnly(.{}));
  // the optimize mode, ReleaseFast when `-Drelease=true` asks for it
  const o=b.standardOptimizeOption(.{
    .preferred_optimize_mode=.ReleaseFast
  });
  // `-Dtest-filter=<text>`: only the tests whose names hold it run (given
  // more than once, those holding any of them)
  const filters=b.option([]const []const u8,"test-filter","run only the tests whose names contain this")orelse&.{};
  // the shader compiler, found through the Vulkan SDK
  const glslc=eb.glslc(b);
  // the engine package, built for the same target and mode
  const eng=b.dependency("engine",.{
    .target=t,
    .optimize=o,
    .glslc=glslc,
    .@"vk-registry"=eb.registry(b),
  });
  // the engine's module, which every game module imports as "engine"
  const engine=eng.module("engine");
  // compile every shader once; both the game and the tests can import them
  // where the game's shaders live, and the engine's
  const dir=b.path("shaders");
  const engineDir=eng.path("shaders");
  // the files a shader may include: the game's, then the engine's
  var inputs:[includes.len+eb.includes.len]Build.LazyPath=undefined;
  for(includes,inputs[0..includes.len])|i,*in|in.*=dir.path(b,i);
  for(eb.includes,inputs[includes.len..])|i,*in|in.*=engineDir.path(b,i);
  // the compiled SPIR-V, one per name in `names`
  var spvs:[names.len]Build.LazyPath=undefined;
  for(names,&spvs,0..)|s,*spv,i|{
    // this shader's variant row (name, source, define), or null for a plain one
    const v:?[3][]const u8=if(i<shaders.len)null else variants[i-shaders.len];
    spv.*=eb.compile(b,glslc,dir,&.{dir,engineDir},&inputs,if(v)|vv|.{.name=s,.source=vv[1],.define=vv[2]}else.{.name=s});
  }
  // a little maker of game modules that see the engine and every shader
  const Mods=struct{
    /// makes a module rooted at `root` for target `tt` and mode `oo`, importing
    /// the engine, every compiled shader by name and the two stock cfg files
    fn make(bb:*Build,root:[]const u8,tt:Build.ResolvedTarget,oo:OptimizeMode,en:*Build.Module,sp:[]const Build.LazyPath)*Build.Module{
      // the module being made
      const md=bb.createModule(.{
        .optimize=oo,
        .target=tt,
        .root_source_file=bb.path(root),
        .imports=&.{.{.name="engine",.module=en}},
      });
      for(names,sp)|s,spv|md.addAnonymousImport(s,.{.root_source_file=spv});
      // the game ships its strings and controls (stock copies in `src/cfg/`),
      // writing them out to the gardener's folder (%LOCALAPPDATA%\Parasymi)
      // when missing; the tests check the strings file is complete
      for([_][]const u8{"parasymi.cfg","controls.cfg"})|c|md.addAnonymousImport(c,.{.root_source_file=bb.path(bb.fmt("src/cfg/{s}",.{c}))});
      // decision: the wolf's clips the game plays (the main menu's sleep)
      // ship inside it as the strings do, keyed in animedit as ever
      for([_][]const u8{"sleep.anim"})|c|md.addAnonymousImport(c,.{.root_source_file=bb.path(bb.fmt("src/anim/{s}",.{c}))});
      return md;
    }
  };
  // the game's own module, rooted at main.zig
  const mod=Mods.make(b,"src/main.zig",t,o,engine,&spvs);
  // the game executable
  const exe=b.addExecutable(.{
    .name=name,
    .version=saman,
    .root_module=mod,
  });
  b.installArtifact(exe);
  // the `run` step and the command it runs: the game, with any `--` args
  const run:struct{cmd:*Build.Step.Run,step:*Build.Step}=.{
    .cmd=b.addRunArtifact(exe),
    .step=b.step("run","run the build.")
  };
  run.cmd.step.dependOn(b.getInstallStep());
  run.step.dependOn(&run.cmd.step);
  if(b.args)|args|run.cmd.addArgs(args);
  // the animation editor (tools/animedit.zig): its own window over the
  // game's renderer, reaching the game's modules through src/lib.zig
  const editor=b.addExecutable(.{
    .name="animedit",
    .root_module=b.createModule(.{
      .optimize=o,
      .target=t,
      .root_source_file=b.path("tools/animedit.zig"),
      .imports=&.{
        .{.name="engine",.module=engine},
        .{.name="parasymi",.module=Mods.make(b,"src/lib.zig",t,o,engine,&spvs)},
      },
    }),
  });
  // the editor's install, and the command that runs it once installed
  const editInstall=b.addInstallArtifact(editor,.{});
  const editCmd=b.addRunArtifact(editor);
  editCmd.step.dependOn(&editInstall.step);
  // (it keeps its clips under the repo, so it runs from there)
  editCmd.setCwd(b.path("."));
  if(b.args)|args|editCmd.addArgs(args);
  b.step("animedit","run the animation editor.").dependOn(&editCmd.step);
  // the mesh editor (tools/meshedit.zig), built the same way
  // the hub module the tools reach the game through
  const lib=Mods.make(b,"src/lib.zig",t,o,engine,&spvs);
  // what every tool imports: the engine and the game as "parasymi"
  const toolImports:[]const Build.Module.Import=&.{
    .{.name="engine",.module=engine},
    .{.name="parasymi",.module=lib},
  };
  // the mesh editor executable
  const meshedit=b.addExecutable(.{
    .name="meshedit",
    .root_module=b.createModule(.{
      .optimize=o,
      .target=t,
      .root_source_file=b.path("tools/meshedit.zig"),
      .imports=toolImports,
    }),
  });
  // the mesh editor's install, and the command that runs it once installed
  const meshInstall=b.addInstallArtifact(meshedit,.{});
  const meshCmd=b.addRunArtifact(meshedit);
  meshCmd.step.dependOn(&meshInstall.step);
  // (it keeps its meshes under the repo, so it runs from there)
  meshCmd.setCwd(b.path("."));
  if(b.args)|args|meshCmd.addArgs(args);
  b.step("meshedit","run the mesh editor.").dependOn(&meshCmd.step);
  // the bridge (tools/bridge.zig): the MCP server Claude Code starts to
  // talk with the game (`--link`); installed with the game, so
  // `zig-out/bin/bridge.exe` is there for `.mcp.json`
  const bridge=b.addExecutable(.{
    .name="bridge",
    .root_module=b.createModule(.{
      .optimize=o,
      .target=t,
      .root_source_file=b.path("tools/bridge.zig"),
      .imports=toolImports,
    }),
  });
  b.installArtifact(bridge);
  // the tools' shared sound files and spectra (tools/audio.zig): the
  // transform, WAVs written and read, resampling; for the ear and voice
  const audioMod=b.createModule(.{
    .optimize=o,
    .target=t,
    .root_source_file=b.path("tools/audio.zig"),
    .imports=&.{.{.name="engine",.module=engine}},
  });
  // the ear (tools/hear.zig): the gardener's voice heard through the
  // microphone, read by whisper.cpp's server and sent through the link
  // folder, so it runs from the repo where that folder is
  const hearMod=b.createModule(.{
    .optimize=o,
    .target=t,
    .root_source_file=b.path("tools/hear.zig"),
    .imports=toolImports,
  });
  // the ear's executable, and the command that runs it with any `--` args
  const hear=b.addExecutable(.{.name="hear",.root_module=hearMod});
  const hearCmd=b.addRunArtifact(hear);
  hearCmd.setCwd(b.path("."));
  if(b.args)|args|hearCmd.addArgs(args);
  b.step("hear","listen to the gardener's voice and send it to Claude.").dependOn(&hearCmd.step);
  // the ear Claude's body keeps listening from login (`hear --body`, started
  // by TOXICCIBU's body): put in zig-out/body/ only by this step, so no
  // other build trips over it while it runs (stop the body to replace it)
  const earInstall=b.addInstallArtifact(hear,.{.dest_dir=.{.override=.{.custom="body"}}});
  b.step("ear","put the ear Claude's body runs in zig-out/body/.").dependOn(&earInstall.step);
  // the voice (tools/speak.zig): Claude's own, made from a throat and five
  // resonances; writes under shots/, so it runs from the repo too
  const speakMod=b.createModule(.{
    .optimize=o,
    .target=t,
    .root_source_file=b.path("tools/speak.zig"),
    .imports=&.{.{.name="engine",.module=engine}},
  });
  // the voice's executable, and the command that runs it with any `--` args
  const speak=b.addExecutable(.{.name="speak",.root_module=speakMod});
  const speakCmd=b.addRunArtifact(speak);
  speakCmd.setCwd(b.path("."));
  if(b.args)|args|speakCmd.addArgs(args);
  b.step("speak","say something in Claude's own voice.").dependOn(&speakCmd.step);
  // the voice ready to run straight away, beside the ear in zig-out/body/
  // (live talk-back, 2026-11-08: skips the build's look-over each reply;
  // run it from the repo, it writes under shots/)
  const voiceInstall=b.addInstallArtifact(speak,.{.dest_dir=.{.override=.{.custom="body"}}});
  b.step("voice","put Claude's voice in zig-out/body/ to run directly.").dependOn(&voiceInstall.step);
  // Claude's own ear (tools/ownear.zig): hears a word by imagining saying
  // it in the voice above, and learns the gardener's; the ear uses it
  const ownearMod=b.createModule(.{
    .optimize=o,
    .target=t,
    .root_source_file=b.path("tools/ownear.zig"),
    .imports=&.{.{.name="engine",.module=engine},.{.name="speak",.module=speakMod}},
  });
  hearMod.addImport("ownear",ownearMod);
  hearMod.addImport("audio",audioMod);
  speakMod.addImport("audio",audioMod);
  ownearMod.addImport("audio",audioMod);
  // the sound check (tools/audiocheck.zig): plays a tone and records it
  // back, so it needs real speakers and stays out of `test`
  // the sound check executable: it needs only the engine
  const audiocheck=b.addExecutable(.{
    .name="audiocheck",
    .root_module=b.createModule(.{
      .optimize=o,
      .target=t,
      .root_source_file=b.path("tools/audiocheck.zig"),
      .imports=&.{.{.name="engine",.module=engine}},
    }),
  });
  b.step("audiocheck","play a tone and check it is heard.").dependOn(&b.addRunArtifact(audiocheck).step);
  // the burst reader (tools/burst.zig): a held-still `--inspect --burst=`
  // run's frames as one contact sheet, and one spot's light measured
  // through them; it needs only the engine
  const burstMod=b.createModule(.{
    .optimize=o,
    .target=t,
    .root_source_file=b.path("tools/burst.zig"),
    .imports=&.{.{.name="engine",.module=engine}},
  });
  // the burst reader's executable, and the command that runs it with any `--` args
  const burst=b.addExecutable(.{.name="burst",.root_module=burstMod});
  const burstCmd=b.addRunArtifact(burst);
  if(b.args)|args|burstCmd.addArgs(args);
  b.step("burst","lay a burst of shots out as a sheet and measure a spot's light through it.").dependOn(&burstCmd.step);
  // the capture frame (tools/capture.zig): a see-through window laid over
  // anything on screen, recording a burst of what shows in it; always
  // fast (it copies the screen in time), a window of its own (no console),
  // installed alone so a held bridge.exe never stops it
  const captureMod=b.createModule(.{
    .optimize=.ReleaseFast,
    .target=t,
    .root_source_file=b.path("tools/capture.zig"),
    .imports=&.{.{.name="engine",.module=engine}},
  });
  captureMod.linkSystemLibrary("user32",.{});
  captureMod.linkSystemLibrary("gdi32",.{});
  // the capture frame's executable, installed on its own and then opened
  const capture=b.addExecutable(.{.name="capture",.root_module=captureMod});
  capture.subsystem=.windows;
  const captureInstall=b.addInstallArtifact(capture,.{});
  const captureCmd=b.addRunArtifact(capture);
  captureCmd.step.dependOn(&captureInstall.step);
  b.step("capture","open the capture frame over the screen.").dependOn(&captureCmd.step);

  // logic tests (world/sim/game, and the engine's own) need no window or
  // GPU, but share the game's imports so game-level code can be exercised
  // headless.
  // the game's headless test binary, rooted at tests.zig
  const tests=b.addTest(.{
    .root_module=Mods.make(b,"src/tests.zig",t,o,engine,&spvs),
    .filters=filters,
  });
  // the engine's own tests
  const engineTests=b.addTest(.{.root_module=engine,.filters=filters});
  // `zig build test`: runs all of them
  const testStep=b.step("test","run unit tests.");
  testStep.dependOn(&b.addRunArtifact(tests).step);
  testStep.dependOn(&b.addRunArtifact(engineTests).step);
  // the mesh editor's text and meshing
  // the mesh editor's tests, built from its own root
  const meshTests=b.addTest(.{.root_module=b.createModule(.{
    .optimize=o,
    .target=t,
    .root_source_file=b.path("tools/meshedit.zig"),
    .imports=toolImports,
  }),.filters=filters});
  testStep.dependOn(&b.addRunArtifact(meshTests).step);
  // the animation editor's tests (eases, copying, the wolf's mirror),
  // built from its own root the same way
  const animTests=b.addTest(.{.root_module=b.createModule(.{
    .optimize=o,
    .target=t,
    .root_source_file=b.path("tools/animedit.zig"),
    .imports=toolImports,
  }),.filters=filters});
  testStep.dependOn(&b.addRunArtifact(animTests).step);
  // the bridge's tests (its answers, the gardener's messages pushed)
  const bridgeTests=b.addTest(.{.root_module=b.createModule(.{
    .optimize=o,
    .target=t,
    .root_source_file=b.path("tools/bridge.zig"),
    .imports=toolImports,
  }),.filters=filters});
  testStep.dependOn(&b.addRunArtifact(bridgeTests).step);
  // the shared sound files' tests (a WAV round trip, the transform)
  testStep.dependOn(&b.addRunArtifact(b.addTest(.{.root_module=audioMod,.filters=filters})).step);
  // Claude's own ear's tests (a word matched stretched)
  testStep.dependOn(&b.addRunArtifact(b.addTest(.{.root_module=ownearMod,.filters=filters})).step);
  // the voice's tests (reading sounds, resonances, pitch, closes)
  testStep.dependOn(&b.addRunArtifact(b.addTest(.{.root_module=speakMod,.filters=filters})).step);
  // the ear's tests (breaths, pitch, words, sound written as text)
  testStep.dependOn(&b.addRunArtifact(b.addTest(.{.root_module=hearMod,.filters=filters})).step);
  // the burst reader's tests (a spot's light and change, a breath)
  testStep.dependOn(&b.addRunArtifact(b.addTest(.{.root_module=burstMod,.filters=filters})).step);
  // the capture frame's tests (its plan, its band, its edges), linked as it is
  const captureTestMod=b.createModule(.{
    .optimize=o,
    .target=t,
    .root_source_file=b.path("tools/capture.zig"),
    .imports=&.{.{.name="engine",.module=engine}},
  });
  captureTestMod.linkSystemLibrary("user32",.{});
  captureTestMod.linkSystemLibrary("gdi32",.{});
  testStep.dependOn(&b.addRunArtifact(b.addTest(.{.root_module=captureTestMod,.filters=filters})).step);
}
