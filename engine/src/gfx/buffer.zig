//! GPU buffers. What changes as the CPU goes (per-frame instances, chunk
//! meshes) is host-visible, persistently mapped memory written directly;
//! what is written once and read every frame (the built-once meshes) is
//! device-local, filled through a staging buffer (`initWith`): read from
//! host memory, every vertex of every draw would cross the bus each frame.
//! (Later: sub-allocation from large blocks.)
/// the standard library
const std=@import("std");
/// checks that hold in debug builds: sizes and offsets that must fit
const assert=std.debug.assert;
/// the Vulkan bindings: handles, flags and the device's calls
const vk=@import("vulkan");
/// the engine's maths, here only for the largest u64 (wait without end)
const m=@import("../core/math.zig");
/// the Vulkan context: device, queue, memory types and the error fold
const ctx=@import("ctx.zig");
/// the device context every buffer is made and freed with
const Ctx=ctx.Ctx;
/// a stretch of GPU memory and the buffer over it: host-visible and kept
/// mapped (`init`) for what changes as the CPU goes, or device-local
/// (`initWith`) for what is written once and read every frame
pub const Buffer=struct{
  /// the Vulkan buffer handle (null while empty)
  buf:vk.Buffer=.null_handle,
  /// the memory bound under it
  mem:vk.DeviceMemory=.null_handle,
  /// how long it is, in bytes
  size:u64=0,
  /// where the CPU writes it, for a host-visible buffer (undefined otherwise)
  map:[*]u8=undefined,
  /// a host-visible, coherent buffer of `size` bytes, mapped for good so
  /// `write` lands straight in it
  pub fn init(c:*const Ctx,size:u64,usage:vk.BufferUsageFlags)ctx.Error!Buffer{
    return create(c,size,usage,.{.host_visible=true,.host_coherent=true})catch|e|ctx.fold(e);
  }
  /// a device-local buffer holding `bytes`, which the CPU never touches
  /// again (`map` and `write` are not for it): copied in through a staging
  /// buffer, waiting for the queue (made once, at load)
  pub fn initWith(c:*const Ctx,usage:vk.BufferUsageFlags,bytes:[]const u8)ctx.Error!Buffer{
    return initRoom(c,usage,bytes.len,bytes);
  }
  /// as `initWith`, `size` bytes long (at least `bytes`), the rest left
  /// for `overwrite` to fill later
  pub fn initRoom(c:*const Ctx,usage:vk.BufferUsageFlags,size:u64,bytes:[]const u8)ctx.Error!Buffer{
    assert(size>=bytes.len);
    // the usage asked for, plus being the target of the staging copy
    var to=usage;
    to.transfer_dst=true;
    // the device-local buffer, freed again if the copy fails
    var b=create(c,size,to,.{.device_local=true})catch|e|return ctx.fold(e);
    errdefer b.deinit(c);
    copyIn(c,&b,0,bytes)catch|e|return ctx.fold(e);
    return b;
  }
  /// copy `bytes` into a device-local buffer at `offset`, once the device
  /// is idle (no frame in flight may read it while it changes): for a tool
  /// remaking a mesh as it is edited, not for every frame
  pub fn overwrite(b:*Buffer,c:*const Ctx,offset:u64,bytes:[]const u8)ctx.Error!void{
    assert(offset+bytes.len<=b.size);
    c.device.deviceWaitIdle()catch|e|return ctx.fold(e);
    copyIn(c,b,offset,bytes)catch|e|return ctx.fold(e);
  }
  /// through a staging buffer, waiting for the queue
  fn copyIn(c:*const Ctx,b:*Buffer,offset:u64,bytes:[]const u8)!void{
    if(bytes.len==0)return;
    // the host-visible staging buffer the bytes are written into first
    var stage=try init(c,bytes.len,.{.transfer_src=true});
    defer stage.deinit(c);
    stage.write(0,bytes);
    // a one-off command pool for the single copy
    const pool=try c.device.createCommandPool(&.{.flags=.{.transient=true},.queue_family_index=c.family},null);
    defer c.device.destroyCommandPool(pool,null);
    // the one command buffer the copy is recorded into
    var cb:vk.CommandBuffer=undefined;
    try c.device.allocateCommandBuffers(&.{.command_pool=pool,.level=.primary,.command_buffer_count=1},@ptrCast(&cb));
    // that command buffer with its device calls attached
    const cmd=vk.CommandBufferProxy.init(cb,c.vkd);
    try cmd.beginCommandBuffer(&.{.flags=.{.one_time_submit=true}});
    cmd.copyBuffer(stage.buf,b.buf,&.{.{.src_offset=0,.dst_offset=offset,.size=bytes.len}});
    try cmd.endCommandBuffer();
    // signalled once the queue has finished the copy
    const fence=try c.device.createFence(&.{},null);
    defer c.device.destroyFence(fence,null);
    // the submit record naming that command buffer
    const cbi=[_]vk.CommandBufferSubmitInfo{.{.command_buffer=cb,.device_mask=0}};
    try c.device.queueSubmit2(c.queue,&.{.{.command_buffer_info_count=cbi.len,.p_command_buffer_infos=&cbi}},fence);
    _=try c.device.waitForFences(&.{fence},.true,m.maxInt(u64));
  }
  /// make the buffer and its memory with the given usage and memory
  /// properties, binding them and mapping the memory if it is host-visible
  fn create(c:*const Ctx,size:u64,usage:vk.BufferUsageFlags,props:vk.MemoryPropertyFlags)!Buffer{
    // the buffer being made, knowing its size
    var b:Buffer=.{.size=size};
    b.buf=try c.device.createBuffer(&.{.size=size,.usage=usage,.sharing_mode=.exclusive},null);
    errdefer c.device.destroyBuffer(b.buf,null);
    // how much memory it needs, how aligned, and which types will do
    const req=c.device.getBufferMemoryRequirements(b.buf);
    // a buffer shaders reach by address needs memory that has one
    const flags:vk.MemoryAllocateFlagsInfo=.{.flags=.{.device_address=true},.device_mask=0};
    b.mem=try c.device.allocateMemory(&.{
      .p_next=if(usage.shader_device_address)&flags else null,
      .allocation_size=req.size,
      .memory_type_index=try c.memType(req.memory_type_bits,props),
    },null);
    errdefer c.device.freeMemory(b.mem,null);
    try c.device.bindBufferMemory(b.buf,b.mem,0);
    if(props.host_visible)b.map=@ptrCast((try c.device.mapMemory(b.mem,0,vk.WHOLE_SIZE,.{})).?);
    return b;
  }
  /// free the buffer and its memory and leave it empty; safe to call twice
  pub fn deinit(b:*Buffer,c:*const Ctx)void{
    if(b.buf==.null_handle)return;
    c.device.destroyBuffer(b.buf,null);
    c.device.freeMemory(b.mem,null);
    b.*=.{};
  }
  /// where shaders find it (made with `shader_device_address`)
  pub fn address(b:*const Buffer,c:*const Ctx)u64{
    return c.device.getBufferDeviceAddress(&.{.buffer=b.buf});
  }
  /// copy `bytes` into the mapped memory at `offset` (host-visible buffers only)
  pub fn write(b:*Buffer,offset:usize,bytes:[]const u8)void{
    assert(offset+bytes.len<=b.size);
    @memcpy(b.map[offset..offset+bytes.len],bytes);
  }
};
