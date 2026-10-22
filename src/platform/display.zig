//! fullscreen toggling: borderless on the primary monitor at its native mode,
//! returning to the exact windowed position and size it left.
const glfw = @import("zglfw");

pub const Display = struct {
  win:*glfw.Window,
  full:bool = false,
  /// windowed placement to restore
  pos:[2]c_int = .{100, 100},
  size:[2]c_int = .{1600, 900},

  pub fn toggle(d:*Display) !void {
    if (d.full) {
      d.win.setMonitor(null, d.pos[0], d.pos[1], d.size[0], d.size[1], 0);
      d.full = false;
      return;
    }
    const mon = glfw.getPrimaryMonitor() orelse return error.NoMonitor;
    const mode = try mon.getVideoMode();
    d.pos = d.win.getPos();
    d.size = d.win.getSize();
    d.win.setMonitor(mon, 0, 0, mode.width, mode.height, mode.refresh_rate);
    d.full = true;
  }
};
