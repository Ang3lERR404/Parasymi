//! swapchain + matching depth buffer. Recreated whenever the window resizes.
/// the standard library
const std=@import("std");
/// the engine's maths: clamping the extent, the "no fixed size" marker
const m=@import("../core/math.zig");
/// the allocator the image and view lists are made with
const Allocator=std.mem.Allocator;
/// the Vulkan bindings
const vk=@import("vulkan");
/// the Vulkan context and its error fold
const ctx=@import("ctx.zig");
/// the device context the swapchain is made on
const Ctx=ctx.Ctx;
/// the one depth format every pass draws with: 32-bit float
pub const depthFormat:vk.Format=.d32_sfloat;
/// the window's chain of images to draw into and present, with a depth
/// image of the same size beside them
pub const Swapchain=struct{
  /// the Vulkan swapchain (null before it is made)
  handle:vk.SwapchainKHR=.null_handle,
  /// the images' pixel format and colour space
  format:vk.SurfaceFormatKHR=undefined,
  /// how big the images are, in pixels
  extent:vk.Extent2D=.{.width=0,.height=0},
  /// the images to draw into, one presented at a time
  images:[]vk.Image=&.{},
  /// a colour view of each image
  views:[]vk.ImageView=&.{},
  /// one "render finished" semaphore per image (safe reuse with present).
  done:[]vk.Semaphore=&.{},
  /// the depth image the passes test against
  depth:vk.Image=.null_handle,
  /// the memory under the depth image
  depthMem:vk.DeviceMemory=.null_handle,
  /// the depth image's view
  depthView:vk.ImageView=.null_handle,
  /// its images can be copied out (screenshots): 8-bit RGBA or BGRA, and
  /// the surface lets them be a transfer's source
  readable:bool=false,
  /// a swapchain of about `w`×`h` pixels, vsynced or not, handing `old` over
  /// when remade; anything half made is freed again on failure
  pub fn init(c:*const Ctx,gpa:Allocator,w:u32,h:u32,vsync:bool,old:vk.SwapchainKHR)ctx.Error!Swapchain{
    // the swapchain being made
    var s:Swapchain=.{};
    s.create(c,gpa,w,h,vsync,old)catch|e|{
      s.deinit(c,gpa,false);
      return ctx.fold(e);
    };
    return s;
  }
  /// on failure leaves `s` holding only what was made, for `deinit` to free.
  fn create(s:*Swapchain,c:*const Ctx,gpa:Allocator,w:u32,h:u32,vsync:bool,old:vk.SwapchainKHR)!void{
    // what the surface allows: sizes, image counts, usages, transform
    const caps=try c.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(c.pdev,c.surface);
    s.extent=if(caps.current_extent.width!=m.maxInt(u32))caps.current_extent else.{
      .width=m.clamp(w,caps.min_image_extent.width,caps.max_image_extent.width),
      .height=m.clamp(h,caps.min_image_extent.height,caps.max_image_extent.height),
    };
    // the formats the surface offers; 8-bit sRGB BGRA is preferred
    const formats=try c.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(c.pdev,c.surface,gpa);
    defer gpa.free(formats);
    s.format=formats[0];
    for(formats)|f|if(f.format==.b8g8r8a8_srgb and f.color_space==.srgb_nonlinear_khr){s.format=f;};
    // how frames are presented: fifo (vsync), or mailbox/immediate without
    var mode:vk.PresentModeKHR=.fifo_khr;
    if(!vsync){
      // the present modes the surface offers
      const modes=try c.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(c.pdev,c.surface,gpa);
      defer gpa.free(modes);
      for(modes)|md|if(md==.mailbox_khr or (md==.immediate_khr and mode!=.mailbox_khr)){mode=md;};
    }
    s.readable=caps.supported_usage_flags.transfer_src and switch(s.format.format){
      .b8g8r8a8_srgb,.b8g8r8a8_unorm,.r8g8b8a8_srgb,.r8g8b8a8_unorm=>true,
      else=>false,
    };
    // how many images: one above the least, under the most if there is one
    var count=caps.min_image_count+1;
    if(caps.max_image_count>0)count=@min(count,caps.max_image_count);
    s.handle=try c.device.createSwapchainKHR(&.{
      .surface=c.surface,
      .min_image_count=count,
      .image_format=s.format.format,
      .image_color_space=s.format.color_space,
      .image_extent=s.extent,
      .image_array_layers=1,
      .image_usage=.{.color_attachment=true,.transfer_src=s.readable},
      .image_sharing_mode=.exclusive,
      .pre_transform=caps.current_transform,
      .composite_alpha=.{.opaque_khr=true},
      .present_mode=mode,
      .clipped=.true,
      .old_swapchain=old,
    },null);
    s.images=try c.device.getSwapchainImagesAllocKHR(s.handle,gpa);
    s.views=try gpa.alloc(vk.ImageView,s.images.len);
    @memset(s.views,.null_handle);
    s.done=try gpa.alloc(vk.Semaphore,s.images.len);
    @memset(s.done,.null_handle);
    for(s.images,s.views,s.done)|img,*v,*d|{
      v.*=try c.device.createImageView(&.{
        .image=img,
        .view_type=.@"2d",
        .format=s.format.format,
        .components=.{.r=.identity,.g=.identity,.b=.identity,.a=.identity},
        .subresource_range=colorRange(),
      },null);
      d.*=try c.device.createSemaphore(&.{},null);
    }
    s.depth=try c.device.createImage(&.{
      .image_type=.@"2d",
      .format=depthFormat,
      .extent=.{.width=s.extent.width,.height=s.extent.height,.depth=1},
      .mip_levels=1,
      .array_layers=1,
      .samples=.{.@"1"=true},
      .tiling=.optimal,
      .usage=.{.depth_stencil_attachment=true,.sampled=true},
      .sharing_mode=.exclusive,
      .initial_layout=.undefined,
    },null);
    s.depthMem=try c.imageMemory(s.depth);
    s.depthView=try c.device.createImageView(&.{
      .image=s.depth,
      .view_type=.@"2d",
      .format=depthFormat,
      .components=.{.r=.identity,.g=.identity,.b=.identity,.a=.identity},
      .subresource_range=depthRange(),
    },null);
  }
  /// free the depth image, views, semaphores and lists; `keepHandle` keeps the
  /// swapchain itself alive, to be handed to its replacement as `old`
  pub fn deinit(s:*Swapchain,c:*const Ctx,gpa:Allocator,keepHandle:bool)void{
    c.device.destroyImageView(s.depthView,null);
    c.device.destroyImage(s.depth,null);
    c.device.freeMemory(s.depthMem,null);
    // null handles are no-ops, so a half-built swapchain frees cleanly too
    for(s.views)|v|c.device.destroyImageView(v,null);
    for(s.done)|d|c.device.destroySemaphore(d,null);
    gpa.free(s.views);
    gpa.free(s.done);
    gpa.free(s.images);
    if(!keepHandle)c.device.destroySwapchainKHR(s.handle,null);
  }
};
/// the whole of a one-layer, one-level colour image
pub fn colorRange()vk.ImageSubresourceRange{
  return.{.aspect_mask=.{.color=true},.base_mip_level=0,.level_count=1,.base_array_layer=0,.layer_count=1};
}
/// the whole of a one-layer, one-level depth image
pub fn depthRange()vk.ImageSubresourceRange{
  return.{.aspect_mask=.{.depth=true},.base_mip_level=0,.level_count=1,.base_array_layer=0,.layer_count=1};
}
/// move `range` of `image` from layout `old` to `new`, once what
/// `srcStage`/`srcAccess` name is done and before what `dstStage`/`dstAccess`
/// name begins (recorded into `cmd`)
pub fn barrier(cmd:vk.CommandBufferProxy,image:vk.Image,range:vk.ImageSubresourceRange,old:vk.ImageLayout,new:vk.ImageLayout,srcStage:vk.PipelineStageFlags2,srcAccess:vk.AccessFlags2,dstStage:vk.PipelineStageFlags2,dstAccess:vk.AccessFlags2)void{
  // the one image barrier
  const b=[_]vk.ImageMemoryBarrier2{.{
    .src_stage_mask=srcStage,
    .src_access_mask=srcAccess,
    .dst_stage_mask=dstStage,
    .dst_access_mask=dstAccess,
    .old_layout=old,
    .new_layout=new,
    .src_queue_family_index=vk.QUEUE_FAMILY_IGNORED,
    .dst_queue_family_index=vk.QUEUE_FAMILY_IGNORED,
    .image=image,
    .subresource_range=range,
  }};
  cmd.pipelineBarrier2(&.{.image_memory_barrier_count=b.len,.p_image_memory_barriers=&b});
}
