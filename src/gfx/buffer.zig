//! GPU buffers. Prototype policy: host-visible, persistently mapped memory for
//! everything, written directly by the CPU. (Later: device-local + staging and
//! sub-allocation from large blocks.)
const std = @import("std");
const assert = std.debug.assert;
const vk = @import("vulkan");
const ctx = @import("ctx.zig");
const Ctx = ctx.Ctx;

pub const Buffer = struct {
  buf:vk.Buffer = .null_handle,
  mem:vk.DeviceMemory = .null_handle,
  size:u64 = 0,
  map:[*]u8 = undefined,

  pub fn init(c:*const Ctx, size:u64, usage:vk.BufferUsageFlags) ctx.Error!Buffer {
    return create(c, size, usage) catch |e| ctx.fold(e);
  }

  fn create(c:*const Ctx, size:u64, usage:vk.BufferUsageFlags) !Buffer {
    var b:Buffer = .{.size = size};
    b.buf = try c.device.createBuffer(&.{.size = size, .usage = usage, .sharing_mode = .exclusive}, null);
    errdefer c.device.destroyBuffer(b.buf, null);
    const req = c.device.getBufferMemoryRequirements(b.buf);
    b.mem = try c.device.allocateMemory(&.{
      .allocation_size = req.size,
      .memory_type_index = try c.memType(req.memory_type_bits, .{.host_visible = true, .host_coherent = true}),
    }, null);
    errdefer c.device.freeMemory(b.mem, null);
    try c.device.bindBufferMemory(b.buf, b.mem, 0);
    b.map = @ptrCast((try c.device.mapMemory(b.mem, 0, vk.WHOLE_SIZE, .{})).?);
    return b;
  }

  pub fn deinit(b:*Buffer, c:*const Ctx) void {
    if (b.buf == .null_handle) return;
    c.device.destroyBuffer(b.buf, null);
    c.device.freeMemory(b.mem, null);
    b.* = .{};
  }

  pub fn write(b:*Buffer, offset:usize, bytes:[]const u8) void {
    assert(offset + bytes.len <= b.size);
    @memcpy(b.map[offset .. offset + bytes.len], bytes);
  }
};
