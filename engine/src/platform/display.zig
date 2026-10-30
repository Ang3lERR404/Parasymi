//! fullscreen toggling: borderless on the primary monitor at its native mode,
//! returning to the exact windowed position and size it left.
/// GLFW: the window and the monitors
const glfw=@import("zglfw");
/// what toggling can fail with
pub const Error=error{
  /// no primary monitor, or none that reports its video mode
  NoMonitor
};
/// the window's fullscreen state, and the switch between windowed and
/// borderless fullscreen
pub const Display=struct{
  /// the window being switched
  win:*glfw.Window,
  /// windowed now, or fullscreen with the way back remembered
  mode:Mode=.windowed,
  /// how the window is shown
  pub const Mode=union(enum){
    /// in a window, wherever the player put it
    windowed,
    /// remembers the windowed placement to return to
    fullscreen:struct{
      /// the window's top-left corner when windowed (screen pixels)
      pos:[2]c_int,
      /// its size when windowed (screen pixels)
      size:[2]c_int
    },
  };
  /// windowed goes fullscreen on the primary monitor at its native mode;
  /// fullscreen goes back to the remembered window. Fails only when there
  /// is no monitor to go fullscreen on.
  pub fn toggle(d:*Display)Error!void{
    switch(d.mode){
      .fullscreen=>|back|{
        d.win.setMonitor(null,back.pos[0],back.pos[1],back.size[0],back.size[1],0);
        d.mode=.windowed;
      },
      .windowed=>{
        // the primary monitor, and its native video mode
        const mon=glfw.getPrimaryMonitor() orelse return error.NoMonitor;
        const vm=mon.getVideoMode() catch return error.NoMonitor;
        d.mode=.{.fullscreen=.{.pos=d.win.getPos(),.size=d.win.getSize()}};
        d.win.setMonitor(mon,0,0,vm.width,vm.height,vm.refresh_rate);
      },
    }
  }
};
