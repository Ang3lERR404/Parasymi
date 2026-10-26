//! fullscreen toggling: borderless on the primary monitor at its native mode,
//! returning to the exact windowed position and size it left.
const glfw = @import("zglfw");

pub const Error = error{NoMonitor};

pub const Display = struct {
  win:*glfw.Window,
  mode:Mode = .windowed,

  pub const Mode = union(enum) {
    windowed,
    /// remembers the windowed placement to return to
    fullscreen:struct { pos:[2]c_int, size:[2]c_int },
  };

  pub fn toggle(d:*Display) Error!void {
    switch (d.mode) {
      .fullscreen => |back| {
        d.win.setMonitor(null, back.pos[0], back.pos[1], back.size[0], back.size[1], 0);
        d.mode = .windowed;
      },
      .windowed => {
        const mon = glfw.getPrimaryMonitor() orelse return error.NoMonitor;
        const vm = mon.getVideoMode() catch return error.NoMonitor;
        d.mode = .{.fullscreen = .{.pos = d.win.getPos(), .size = d.win.getSize()}};
        d.win.setMonitor(mon, 0, 0, vm.width, vm.height, vm.refresh_rate);
      },
    }
  }
};
