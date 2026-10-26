//! GPU buffers. What changes as the CPU goes (per-frame instances, chunk
//! meshes) is host-visible, persistently mapped memory written directly;
//! what is written once and read every frame (the built-once meshes) is
//! device-local, filled through a staging buffer (`initWith`): read from
//! host memory, every vertex of every draw would cross the bus each frame.
//! (Later: sub-allocation from large blocks.)
const std = @import("std");
const assert = std.debug.assert;
const vk = @import("vulkan");
const m = @import("../core/math.zig");
const ctx = @import("ctx.zig");
const Ctx = ctx.Ctx;

pub const Buffer = struct {
  buf:vk.Buffer = .null_handle,
  mem:vk.DeviceMemory = .null_handle,
  size:u64 = 0,
  map:[*]u8 = undefined,

  pub fn init(c:*const Ctx, size:u64, usage:vk.BufferUsageFlags) ctx.Error!Buffer {
    return create(c, size, usage, .{.host_visible = true, .host_coherent = true}) catch |e| ctx.fold(e);
  }

  /// a device-local buffer holding `bytes`, which the CPU never touches
  /// again (`map` and `write` are not for it): copied in through a staging
  /// buffer, waiting for the queue (made once, at load)
  pub fn initWith(c:*const Ctx, usage:vk.BufferUsageFlags, bytes:[]const u8) ctx.Error!Buffer {
    return fill(c, usage, bytes) catch |e| ctx.fold(e);
  }

  fn fill(c:*const Ctx, usage:vk.BufferUsageFlags, bytes:[]const u8) !Buffer {
    var stage = try init(c, bytes.len, .{.transfer_src = true});
    defer stage.deinit(c);
    stage.write(0, bytes);
    var to = usage;
    to.transfer_dst = true;
    var b = try create(c, bytes.len, to, .{.device_local = true});
    errdefer b.deinit(c);
    const pool = try c.device.createCommandPool(&.{.flags = .{.transient = true}, .queue_family_index = c.family}, null);
    defer c.device.destroyCommandPool(pool, null);
    var cb:vk.CommandBuffer = undefined;
    try c.device.allocateCommandBuffers(&.{.command_pool = pool, .level = .primary, .command_buffer_count = 1}, @ptrCast(&cb));
    const cmd = vk.CommandBufferProxy.init(cb, c.vkd);
    try cmd.beginCommandBuffer(&.{.flags = .{.one_time_submit = true}});
    cmd.copyBuffer(stage.buf, b.buf, &.{.{.src_offset = 0, .dst_offset = 0, .size = bytes.len}});
    try cmd.endCommandBuffer();
    const fence = try c.device.createFence(&.{}, null);
    defer c.device.destroyFence(fence, null);
    const cbi = [_]vk.CommandBufferSubmitInfo{.{.command_buffer = cb, .device_mask = 0}};
    try c.device.queueSubmit2(c.queue, &.{.{.command_buffer_info_count = cbi.len, .p_command_buffer_infos = &cbi}}, fence);
    _ = try c.device.waitForFences(&.{fence}, .true, m.maxInt(u64));
    return b;
  }

  fn create(c:*const Ctx, size:u64, usage:vk.BufferUsageFlags, props:vk.MemoryPropertyFlags) !Buffer {
    var b:Buffer = .{.size = size};
    b.buf = try c.device.createBuffer(&.{.size = size, .usage = usage, .sharing_mode = .exclusive}, null);
    errdefer c.device.destroyBuffer(b.buf, null);
    const req = c.device.getBufferMemoryRequirements(b.buf);
    // a buffer shaders reach by address needs memory that has one
    const flags:vk.MemoryAllocateFlagsInfo = .{.flags = .{.device_address = true}, .device_mask = 0};
    b.mem = try c.device.allocateMemory(&.{
      .p_next = if (usage.shader_device_address) &flags else null,
      .allocation_size = req.size,
      .memory_type_index = try c.memType(req.memory_type_bits, props),
    }, null);
    errdefer c.device.freeMemory(b.mem, null);
    try c.device.bindBufferMemory(b.buf, b.mem, 0);
    if (props.host_visible) b.map = @ptrCast((try c.device.mapMemory(b.mem, 0, vk.WHOLE_SIZE, .{})).?);
    return b;
  }

  pub fn deinit(b:*Buffer, c:*const Ctx) void {
    if (b.buf == .null_handle) return;
    c.device.destroyBuffer(b.buf, null);
    c.device.freeMemory(b.mem, null);
    b.* = .{};
  }

  /// where shaders find it (made with `shader_device_address`)
  pub fn address(b:*const Buffer, c:*const Ctx) u64 {
    return c.device.getBufferDeviceAddress(&.{.buffer = b.buf});
  }

  pub fn write(b:*Buffer, offset:usize, bytes:[]const u8) void {
    assert(offset + bytes.len <= b.size);
    @memcpy(b.map[offset .. offset + bytes.len], bytes);
  }
};
