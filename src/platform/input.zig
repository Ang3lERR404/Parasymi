//! per-frame input snapshot with edge detection, fed by GLFW.
const glfw = @import("zglfw");

pub const Key = glfw.Key;
pub const Button = glfw.MouseButton;

const tracked = [_]Key{
  .w, .a, .s, .d, .q, .e, .r, .f, .t, .c, .up, .down, .left, .right,
  .one, .two, .three, .four, .five, .six, .seven, .eight, .nine,
  .tab, .escape, .F3, .F5, .F9, .F11, .left_shift, .space,
};
const buttons = [_]Button{.left, .right, .middle};

pub const Input = struct {
  win:*glfw.Window,
  cur:[tracked.len]bool = @splat(false),
  prev:[tracked.len]bool = @splat(false),
  bcur:[buttons.len]bool = @splat(false),
  bprev:[buttons.len]bool = @splat(false),
  mouse:[2]f32 = .{0, 0},
  mouse_delta:[2]f32 = .{0, 0},
  scroll:f32 = 0,
  scroll_acc:f32 = 0,
  resized:bool = false,

  /// must be called once the Input has its final address.
  pub fn attach(in:*Input) void {
    in.win.setUserPointer(in);
    _ = in.win.setScrollCallback(onScroll);
    _ = in.win.setFramebufferSizeCallback(onResize);
  }

  pub fn update(in:*Input) void {
    in.prev = in.cur;
    in.bprev = in.bcur;
    inline for (tracked, 0..) |k, i| in.cur[i] = in.win.getKey(k) == .press;
    inline for (buttons, 0..) |b, i| in.bcur[i] = in.win.getMouseButton(b) == .press;
    const mp = in.win.getCursorPos();
    const m:[2]f32 = .{@floatCast(mp[0]), @floatCast(mp[1])};
    in.mouse_delta = .{m[0] - in.mouse[0], m[1] - in.mouse[1]};
    in.mouse = m;
    in.scroll = in.scroll_acc;
    in.scroll_acc = 0;
  }

  fn idx(comptime k:Key) usize {
    inline for (tracked, 0..) |t, i| if (t == k) return i;
    @compileError("key not tracked: " ++ @tagName(k));
  }
  fn bidx(comptime b:Button) usize {
    inline for (buttons, 0..) |t, i| if (t == b) return i;
    @compileError("button not tracked");
  }

  pub fn down(in:*const Input, comptime k:Key) bool { return in.cur[idx(k)]; }
  pub fn pressed(in:*const Input, comptime k:Key) bool { const i = idx(k); return in.cur[i] and !in.prev[i]; }
  pub fn held(in:*const Input, comptime b:Button) bool { return in.bcur[bidx(b)]; }
  pub fn clicked(in:*const Input, comptime b:Button) bool { const i = bidx(b); return in.bcur[i] and !in.bprev[i]; }
};

fn onScroll(w:*glfw.Window, _:f64, y:f64) callconv(.c) void {
  if (w.getUserPointer(Input)) |in| in.scroll_acc += @floatCast(y);
}
fn onResize(w:*glfw.Window, _:c_int, _:c_int) callconv(.c) void {
  if (w.getUserPointer(Input)) |in| in.resized = true;
}
