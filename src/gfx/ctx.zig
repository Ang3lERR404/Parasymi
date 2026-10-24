//! Vulkan instance + device bring-up. Function pointers are loaded through
//! GLFW (which loads vulkan-1.dll itself), so nothing links against the SDK.
const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;
const sliceAsBytes = std.mem.sliceAsBytes;
const sliceTo = std.mem.sliceTo;
const builtin = @import("builtin");
const vk = @import("vulkan");
const glfw = @import("zglfw");

extern fn glfwGetInstanceProcAddress(instance:?vk.Instance, name:[*:0]const u8) vk.PfnVoidFunction;

/// what the graphics layer fails with. Vulkan's and GLFW's long error sets
/// are folded into these at each public entry point (see `fold`).
pub const Error = error{OutOfMemory, DeviceLost, SurfaceLost, NoVulkan, NoSuitableGpu, NoMemoryType, GpuFailure};

/// translate a Vulkan/GLFW error into `Error`, logging any detail it loses.
pub fn fold(e:anytype) Error {
  const name = @errorName(e);
  const known = .{
    .{"OutOfMemory", error.OutOfMemory}, .{"OutOfHostMemory", error.OutOfMemory}, .{"OutOfDeviceMemory", error.OutOfMemory},
    .{"DeviceLost", error.DeviceLost}, .{"SurfaceLostKHR", error.SurfaceLost},
    .{"IncompatibleDriver", error.NoVulkan}, .{"InitializationFailed", error.NoVulkan}, .{"APIUnavailable", error.NoVulkan},
    .{"NoSuitableGpu", error.NoSuitableGpu}, .{"NoMemoryType", error.NoMemoryType},
  };
  inline for (known) |k| if (eql(u8, name, k[0])) return k[1];
  log.err("gpu: {s}", .{name});
  return error.GpuFailure;
}

const validate = builtin.mode == .Debug;
const validation_layer = "VK_LAYER_KHRONOS_validation";

pub const Ctx = struct {
  vkb:vk.BaseWrapper,
  vki:*vk.InstanceWrapper,
  vkd:*vk.DeviceWrapper,
  instance:vk.InstanceProxy,
  device:vk.DeviceProxy,
  messenger:vk.DebugUtilsMessengerEXT = .null_handle,
  surface:vk.SurfaceKHR,
  pdev:vk.PhysicalDevice,
  props:vk.PhysicalDeviceProperties,
  mem_props:vk.PhysicalDeviceMemoryProperties,
  family:u32,
  queue:vk.Queue,
  /// whether pipelines may shade every sample (MSAA edges a shader decides)
  sample_shading:bool,

  pub fn init(gpa:Allocator, window:*glfw.Window) Error!Ctx {
    var c:Ctx = undefined;
    c.bringUp(gpa, window) catch |e| return fold(e);
    return c;
  }

  fn bringUp(c:*Ctx, gpa:Allocator, window:*glfw.Window) !void {
    c.messenger = .null_handle;
    c.vkb = vk.BaseWrapper.load(glfwGetInstanceProcAddress);

    var exts:std.ArrayList([*:0]const u8) = .empty;
    defer exts.deinit(gpa);
    try exts.appendSlice(gpa, try glfw.getRequiredInstanceExtensions());
    var layers:std.ArrayList([*:0]const u8) = .empty;
    defer layers.deinit(gpa);
    const debug = validate and try hasLayer(gpa, c.vkb, validation_layer);
    if (debug) {
      try layers.append(gpa, validation_layer);
      try exts.append(gpa, vk.extensions.ext_debug_utils.name);
    } else if (validate) {
      log.warn("validation layer not found; running without it", .{});
    }

    const app:vk.ApplicationInfo = .{
      .p_application_name = "Parasymi",
      .application_version = 0,
      .p_engine_name = "Parasymi",
      .engine_version = 0,
      .api_version = @bitCast(vk.API_VERSION_1_3),
    };
    const inst = try c.vkb.createInstance(&.{
      .p_application_info = &app,
      .enabled_extension_count = @intCast(exts.items.len),
      .pp_enabled_extension_names = exts.items.ptr,
      .enabled_layer_count = @intCast(layers.items.len),
      .pp_enabled_layer_names = layers.items.ptr,
    }, null);
    c.vki = try gpa.create(vk.InstanceWrapper);
    errdefer gpa.destroy(c.vki);
    c.vki.* = vk.InstanceWrapper.load(inst, c.vkb.dispatch.vkGetInstanceProcAddr.?);
    c.instance = vk.InstanceProxy.init(inst, c.vki);
    errdefer c.instance.destroyInstance(null);

    if (debug) {
      c.messenger = try c.instance.createDebugUtilsMessengerEXT(&.{
        .message_severity = .{.warning_ext = true, .error_ext = true},
        .message_type = .{.general_ext = true, .validation_ext = true, .performance_ext = true},
        .pfn_user_callback = &onDebug,
      }, null);
    }
    errdefer if (c.messenger != .null_handle) c.instance.destroyDebugUtilsMessengerEXT(c.messenger, null);

    try glfw.createWindowSurface(inst, window, null, &c.surface);
    errdefer c.instance.destroySurfaceKHR(c.surface, null);
    try c.pickDevice(gpa);

    const prio = [_]f32{1};
    const qci = [_]vk.DeviceQueueCreateInfo{.{.queue_family_index = c.family, .queue_count = 1, .p_queue_priorities = &prio}};
    var f13:vk.PhysicalDeviceVulkan13Features = .{.dynamic_rendering = .true, .synchronization_2 = .true, .shader_demote_to_helper_invocation = .true};
    const dev_exts = [_][*:0]const u8{vk.extensions.khr_swapchain.name};
    c.sample_shading = c.instance.getPhysicalDeviceFeatures(c.pdev).sample_rate_shading == .true;
    const f10:vk.PhysicalDeviceFeatures = .{.sample_rate_shading = if (c.sample_shading) .true else .false};
    const dev = try c.instance.createDevice(c.pdev, &.{
      .p_next = &f13,
      .p_enabled_features = &f10,
      .queue_create_info_count = qci.len,
      .p_queue_create_infos = &qci,
      .enabled_extension_count = dev_exts.len,
      .pp_enabled_extension_names = &dev_exts,
    }, null);
    c.vkd = try gpa.create(vk.DeviceWrapper);
    c.vkd.* = vk.DeviceWrapper.load(dev, c.vki.dispatch.vkGetDeviceProcAddr.?);
    c.device = vk.DeviceProxy.init(dev, c.vkd);
    c.queue = c.device.getDeviceQueue(c.family, 0);
    log.info("gpu: {s}", .{sliceTo(&c.props.device_name, 0)});
  }

  pub fn deinit(c:*Ctx, gpa:Allocator) void {
    c.device.destroyDevice(null);
    c.instance.destroySurfaceKHR(c.surface, null);
    if (c.messenger != .null_handle) c.instance.destroyDebugUtilsMessengerEXT(c.messenger, null);
    c.instance.destroyInstance(null);
    gpa.destroy(c.vkd);
    gpa.destroy(c.vki);
  }

  /// prefer a discrete GPU with a graphics+present queue and Vulkan 1.3.
  fn pickDevice(c:*Ctx, gpa:Allocator) !void {
    const devs = try c.instance.enumeratePhysicalDevicesAlloc(gpa);
    defer gpa.free(devs);
    var best:i32 = -1;
    for (devs) |pd| {
      const props = c.instance.getPhysicalDeviceProperties(pd);
      const ver:vk.Version = @bitCast(props.api_version);
      if (ver.major < 1 or (ver.major == 1 and ver.minor < 3)) continue;
      const fams = try c.instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pd, gpa);
      defer gpa.free(fams);
      for (fams, 0..) |f, i| {
        if (!f.queue_flags.graphics) continue;
        const fi:u32 = @intCast(i);
        if (try c.instance.getPhysicalDeviceSurfaceSupportKHR(pd, fi, c.surface) != .true) continue;
        const score:i32 = if (props.device_type == .discrete_gpu) 2 else 1;
        if (score > best) {
          best = score;
          c.pdev = pd;
          c.props = props;
          c.family = fi;
        }
        break;
      }
    }
    if (best < 0) return error.NoSuitableGpu;
    c.mem_props = c.instance.getPhysicalDeviceMemoryProperties(c.pdev);
  }

  pub fn memType(c:*const Ctx, bits:u32, want:vk.MemoryPropertyFlags) Error!u32 {
    for (c.mem_props.memory_types[0..c.mem_props.memory_type_count], 0..) |t, i| {
      if (bits & (@as(u32, 1) << @intCast(i)) != 0 and t.property_flags.contains(want)) return @intCast(i);
    }
    return error.NoMemoryType;
  }

  /// `name` is a build-time compiled shader (see build.zig `shaders`).
  pub fn shader(c:*const Ctx, comptime name:[]const u8) Error!vk.ShaderModule {
    const words = comptime blk: {
      const spv = @embedFile(name);
      var w:[spv.len / 4]u32 = undefined;
      @memcpy(sliceAsBytes(&w), spv);
      break :blk w;
    };
    return c.device.createShaderModule(&.{.code_size = words.len * 4, .p_code = &words}, null) catch |e| fold(e);
  }
};

fn hasLayer(gpa:Allocator, vkb:vk.BaseWrapper, name:[]const u8) !bool {
  const props = try vkb.enumerateInstanceLayerPropertiesAlloc(gpa);
  defer gpa.free(props);
  for (props) |p| if (eql(u8, sliceTo(&p.layer_name, 0), name)) return true;
  return false;
}

fn onDebug(
  sev:vk.DebugUtilsMessageSeverityFlagsEXT,
  _:vk.DebugUtilsMessageTypeFlagsEXT,
  data:?*const vk.DebugUtilsMessengerCallbackDataEXT,
  _:?*anyopaque,
) callconv(vk.vulkan_call_conv) vk.Bool32 {
  const msg = if (data) |d| (d.p_message orelse "?") else "?";
  if (sev.error_ext) log.err("vk: {s}", .{msg}) else log.warn("vk: {s}", .{msg});
  return .false;
}
