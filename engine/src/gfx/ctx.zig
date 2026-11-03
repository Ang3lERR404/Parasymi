//! Vulkan instance + device bring-up. Function pointers are loaded through
//! GLFW (which loads vulkan-1.dll itself), so nothing links against the SDK.
/// the standard library
const std=@import("std");
/// where bring-up says which GPU it found, or what went wrong
const log=std.log;
/// the allocator the wrappers and lists are made with
const Allocator=std.mem.Allocator;
/// byte-for-byte equality, for matching error and layer names
const eql=std.mem.eql;
/// a slice seen as its bytes, for turning SPIR-V words round
const sliceAsBytes=std.mem.sliceAsBytes;
/// a fixed name buffer cut at its first zero
const sliceTo=std.mem.sliceTo;
/// where one string turns up inside another
const indexOf=std.mem.indexOf;
/// a zero-ended C string seen as a slice
const span=std.mem.span;
/// the build's mode: debug builds turn validation on
const builtin=@import("builtin");
/// the Vulkan bindings: handles, flags, wrappers and proxies
const vk=@import("vulkan");
/// the window library, which loads Vulkan itself and makes the surface
const glfw=@import("zglfw");
/// GLFW's loader for Vulkan's instance-level calls, so nothing links the SDK
extern fn glfwGetInstanceProcAddress(instance:?vk.Instance,name:[*:0]const u8)vk.PfnVoidFunction;
/// what the graphics layer fails with. Vulkan's and GLFW's long error sets
/// are folded into these at each public entry point (see `fold`).
pub const Error=error{OutOfMemory,DeviceLost,SurfaceLost,NoVulkan,NoSuitableGpu,NoMemoryType,GpuFailure};
/// translate a Vulkan/GLFW error into `Error`, logging any detail it loses.
/// Folding an `Error` again keeps it as it is.
pub fn fold(e:anyerror)Error{
  // the error's name, matched against the known ones below
  const name=@errorName(e);
  // pairs of a Vulkan/GLFW error name and the `Error` it folds into
  const known=.{
    .{"OutOfMemory",error.OutOfMemory},.{"OutOfHostMemory",error.OutOfMemory},.{"OutOfDeviceMemory",error.OutOfMemory},
    .{"DeviceLost",error.DeviceLost},.{"SurfaceLostKHR",error.SurfaceLost},.{"SurfaceLost",error.SurfaceLost},
    .{"IncompatibleDriver",error.NoVulkan},.{"InitializationFailed",error.NoVulkan},.{"APIUnavailable",error.NoVulkan},
    .{"NoVulkan",error.NoVulkan},.{"NoSuitableGpu",error.NoSuitableGpu},.{"NoMemoryType",error.NoMemoryType},
    .{"GpuFailure",error.GpuFailure},
  };
  inline for(known)|k|if(eql(u8,name,k[0]))return k[1];
  log.err("gpu: {s}",.{name});
  return error.GpuFailure;
}
/// whether the validation layer is asked for (debug builds only)
const validate=builtin.mode==.Debug;
/// the Khronos validation layer's name
const validationLayer="VK_LAYER_KHRONOS_validation";
/// the Vulkan context: instance, device, the window's surface and the one
/// queue that draws and presents, made once and handed to every GPU call
pub const Ctx=struct{
  /// the loader's base calls (no instance needed)
  vkb:vk.BaseWrapper,
  /// the instance's calls, loaded once the instance exists
  vki:*vk.InstanceWrapper,
  /// the device's calls, loaded once the device exists
  vkd:*vk.DeviceWrapper,
  /// the instance, with its calls attached
  instance:vk.InstanceProxy,
  /// the logical device, with its calls attached
  device:vk.DeviceProxy,
  /// where validation messages arrive (null without the layer)
  messenger:vk.DebugUtilsMessengerEXT=.null_handle,
  /// the window's drawing surface
  surface:vk.SurfaceKHR,
  /// the chosen GPU
  pdev:vk.PhysicalDevice,
  /// that GPU's name, kind, limits and version
  props:vk.PhysicalDeviceProperties,
  /// that GPU's memory types and heaps
  memProps:vk.PhysicalDeviceMemoryProperties,
  /// the queue family that both draws and presents
  family:u32,
  /// the one queue every frame is submitted to
  queue:vk.Queue,
  /// whether pipelines may shade every sample (MSAA edges a shader decides)
  sampleShading:bool,
  /// `app`: the game's name, as the driver is told it
  /// bring Vulkan up on `window`: instance, validation (debug builds), surface,
  /// GPU and device; any failure is folded into `Error`
  pub fn init(gpa:Allocator,window:*glfw.Window,app:[*:0]const u8)Error!Ctx{
    // the context being filled in
    var c:Ctx=undefined;
    c.bringUp(gpa,window,app)catch|e|return fold(e);
    return c;
  }
  /// the steps of `init`, failing with the raw Vulkan/GLFW errors `init` folds
  fn bringUp(c:*Ctx,gpa:Allocator,window:*glfw.Window,name:[*:0]const u8)!void{
    c.messenger=.null_handle;
    c.vkb=vk.BaseWrapper.load(glfwGetInstanceProcAddress);
    // the instance extensions asked for: GLFW's, plus debug utils with validation
    var exts:std.ArrayList([*:0]const u8)=.empty;
    defer exts.deinit(gpa);
    try exts.appendSlice(gpa,try glfw.getRequiredInstanceExtensions());
    // the instance layers asked for: validation, when it is there
    var layers:std.ArrayList([*:0]const u8)=.empty;
    defer layers.deinit(gpa);
    // whether validation runs: a debug build with the layer installed
    const debug=validate and try hasLayer(gpa,c.vkb,validationLayer);
    if(debug){
      try layers.append(gpa,validationLayer);
      try exts.append(gpa,vk.extensions.ext_debug_utils.name);
    }else if(validate){
      log.warn("validation layer not found; running without it",.{});
    }
    // what the driver is told: the game, the engine, and Vulkan 1.3
    const app:vk.ApplicationInfo=.{
      .p_application_name=name,
      .application_version=0,
      .p_engine_name="engine",
      .engine_version=0,
      .api_version=@bitCast(vk.API_VERSION_1_3),
    };
    // the wrappers are allocated before what they wrap, so a failed
    // allocation never strands a live instance or device
    c.vki=try gpa.create(vk.InstanceWrapper);
    errdefer gpa.destroy(c.vki);
    // the new instance
    const inst=try c.vkb.createInstance(&.{
      .p_application_info=&app,
      .enabled_extension_count=@intCast(exts.items.len),
      .pp_enabled_extension_names=exts.items.ptr,
      .enabled_layer_count=@intCast(layers.items.len),
      .pp_enabled_layer_names=layers.items.ptr,
    },null);
    c.vki.*=vk.InstanceWrapper.load(inst,c.vkb.dispatch.vkGetInstanceProcAddr.?);
    c.instance=vk.InstanceProxy.init(inst,c.vki);
    errdefer c.instance.destroyInstance(null);
    if(debug){
      c.messenger=try c.instance.createDebugUtilsMessengerEXT(&.{
        .message_severity=.{.warning_ext=true,.error_ext=true},
        .message_type=.{.general_ext=true,.validation_ext=true,.performance_ext=true},
        .pfn_user_callback=&onDebug,
      },null);
    }
    errdefer if(c.messenger!=.null_handle)c.instance.destroyDebugUtilsMessengerEXT(c.messenger,null);
    try glfw.createWindowSurface(inst,window,null,&c.surface);
    errdefer c.instance.destroySurfaceKHR(c.surface,null);
    try c.pickDevice(gpa);
    // the one queue's priority
    const prio=[_]f32{1};
    // the one queue asked for, in the drawing family
    const qci=[_]vk.DeviceQueueCreateInfo{.{.queue_family_index=c.family,.queue_count=1,.p_queue_priorities=&prio}};
    // the Vulkan 1.3 features used: dynamic rendering, sync2, demote to helper
    var f13:vk.PhysicalDeviceVulkan13Features=.{.dynamic_rendering=.true,.synchronization_2=.true,.shader_demote_to_helper_invocation=.true};
    // skinned meshes read their bones through a buffer's address (core in 1.2)
    var f12:vk.PhysicalDeviceVulkan12Features=.{.p_next=&f13,.buffer_device_address=.true};
    // the shadow map's cascades are drawn in one pass, one view each (core in 1.1)
    var f11:vk.PhysicalDeviceVulkan11Features=.{.p_next=&f12,.multiview=.true};
    // the device extensions asked for: only the swapchain
    const devExts=[_][*:0]const u8{vk.extensions.khr_swapchain.name};
    c.sampleShading=c.instance.getPhysicalDeviceFeatures(c.pdev).sample_rate_shading==.true;
    // (a vertex may be clipped away by a distance of its own: what a
    // skinned mesh hides, see part.vert; every desktop GPU has it), and
    // the points of light's shadow cubes are read as one cube array
    // (render/cube.zig; every desktop GPU has that too)
    const f10:vk.PhysicalDeviceFeatures=.{.sample_rate_shading=if(c.sampleShading).true else.false,.shader_clip_distance=.true,.image_cube_array=.true};
    c.vkd=try gpa.create(vk.DeviceWrapper);
    errdefer gpa.destroy(c.vkd);
    // the new logical device
    const dev=try c.instance.createDevice(c.pdev,&.{
      .p_next=&f11,
      .p_enabled_features=&f10,
      .queue_create_info_count=qci.len,
      .p_queue_create_infos=&qci,
      .enabled_extension_count=devExts.len,
      .pp_enabled_extension_names=&devExts,
    },null);
    c.vkd.*=vk.DeviceWrapper.load(dev,c.vki.dispatch.vkGetDeviceProcAddr.?);
    c.device=vk.DeviceProxy.init(dev,c.vkd);
    c.queue=c.device.getDeviceQueue(c.family,0);
    log.info("gpu: {s}",.{sliceTo(&c.props.device_name,0)});
  }
  /// destroy the device, surface, messenger and instance, then free the wrappers
  pub fn deinit(c:*Ctx,gpa:Allocator)void{
    c.device.destroyDevice(null);
    c.instance.destroySurfaceKHR(c.surface,null);
    if(c.messenger!=.null_handle)c.instance.destroyDebugUtilsMessengerEXT(c.messenger,null);
    c.instance.destroyInstance(null);
    gpa.destroy(c.vkd);
    gpa.destroy(c.vki);
  }
  /// prefer a discrete GPU with a graphics+present queue and Vulkan 1.3.
  fn pickDevice(c:*Ctx,gpa:Allocator)!void{
    // every GPU Vulkan can see
    const devs=try c.instance.enumeratePhysicalDevicesAlloc(gpa);
    defer gpa.free(devs);
    // the best score found yet (discrete 2, integrated 1); -1 while none fits
    var best:i32=-1;
    for(devs)|pd|{
      // this GPU's name, kind and version
      const props=c.instance.getPhysicalDeviceProperties(pd);
      // its Vulkan version, to skip anything older than 1.3
      const ver:vk.Version=@bitCast(props.api_version);
      if(ver.major<1 or (ver.major==1 and ver.minor<3))continue;
      // its queue families
      const fams=try c.instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pd,gpa);
      defer gpa.free(fams);
      for(fams,0..)|f,i|{
        if(!f.queue_flags.graphics)continue;
        // the family's index
        const fi:u32=@intCast(i);
        if(try c.instance.getPhysicalDeviceSurfaceSupportKHR(pd,fi,c.surface)!=.true)continue;
        // how much this GPU is wanted: discrete over integrated
        const score:i32=if(props.device_type==.discrete_gpu)2 else 1;
        if(score>best){
          best=score;
          c.pdev=pd;
          c.props=props;
          c.family=fi;
        }
        break;
      }
    }
    if(best<0)return error.NoSuitableGpu;
    c.memProps=c.instance.getPhysicalDeviceMemoryProperties(c.pdev);
  }
  /// the index of a memory type allowed by `bits` with every property in
  /// `want`; `NoMemoryType` when none has them
  pub fn memType(c:*const Ctx,bits:u32,want:vk.MemoryPropertyFlags)Error!u32{
    for(c.memProps.memory_types[0..c.memProps.memory_type_count],0..)|t,i|{
      if(bits&(@as(u32,1)<<@intCast(i))!=0 and t.property_flags.contains(want))return@intCast(i);
    }
    return error.NoMemoryType;
  }
  /// device-local memory allocated for `image` and bound to it.
  pub fn imageMemory(c:*const Ctx,image:vk.Image)Error!vk.DeviceMemory{
    // how much memory the image needs, how aligned, which types will do
    const req=c.device.getImageMemoryRequirements(image);
    // the device-local memory made for it
    const mem=c.device.allocateMemory(&.{
      .allocation_size=req.size,
      .memory_type_index=try c.memType(req.memory_type_bits,.{.device_local=true}),
    },null)catch|e|return fold(e);
    errdefer c.device.freeMemory(mem,null);
    c.device.bindImageMemory(image,mem,0)catch|e|return fold(e);
    return mem;
  }
  /// `spv`: a build-time compiled shader's SPIR-V, embedded by the module
  /// that compiled it (`@embedFile("post.vert")`; see build.zig).
  pub fn shader(c:*const Ctx,comptime spv:[]const u8)Error!vk.ShaderModule{
    // the SPIR-V bytes as 32-bit words, turned round at compile time
    const words=comptime blk:{
      // the words being filled
      var w:[spv.len/4]u32=undefined;
      @memcpy(sliceAsBytes(&w),spv);
      break:blk w;
    };
    return c.device.createShaderModule(&.{.code_size=words.len*4,.p_code=&words},null)catch|e|fold(e);
  }
};
/// whether the instance layer called `name` is installed
fn hasLayer(gpa:Allocator,vkb:vk.BaseWrapper,name:[]const u8)!bool{
  // every installed instance layer
  const props=try vkb.enumerateInstanceLayerPropertiesAlloc(gpa);
  defer gpa.free(props);
  for(props)|p|if(eql(u8,sliceTo(&p.layer_name,0),name))return true;
  return false;
}
/// where validation messages land: errors are logged as errors, the rest as
/// warnings, and one known-harmless message is dropped; never aborts the call
fn onDebug(
  // how bad the message is
  sev:vk.DebugUtilsMessageSeverityFlagsEXT,
  // what kind of message (unused)
  _:vk.DebugUtilsMessageTypeFlagsEXT,
  // the message itself and its id
  data:?*const vk.DebugUtilsMessengerCallbackDataEXT,
  // the user pointer (unused)
  _:?*anyopaque,
)callconv(vk.vulkan_call_conv)vk.Bool32{
  // the message text, or "?" when there is none
  const msg=if(data)|d|(d.p_message orelse "?")else"?";
  // decision: a shadow caster's vertex shader is the drawn one, its
  // outputs left to a depth-only fragment shader on purpose (render/light.zig)
  // the message's id name, matched against the ones let pass
  const id:[]const u8=if(data)|d|if(d.p_message_id_name)|n|span(n)else""else"";
  if(indexOf(u8,id,"OutputNotConsumed")!=null)return.false;
  if(sev.error_ext)log.err("vk: {s}",.{msg})else log.warn("vk: {s}",.{msg});
  return.false;
}
