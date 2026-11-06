//! a see-through frame laid over anything on the screen (a game in a
//! borderless window, a video, Parasymi), so the gardener can catch what
//! moves there and show it to Claude: a borderless window, always on top,
//! its middle see-through and clicked through, a thin border to size it by
//! and a band along its top to drag it by. REC (or F9, wherever the focus
//! is) records a burst of what shows inside the border over the seconds
//! set (- and +, or the wheel), into `shots/capture/<time>/`: its frames,
//! one contact sheet and a spot's light measured through them
//! (`tools/burst.zig`). Its own button in the taskbar closes it, or Esc.
/// the standard library
const std=@import("std");
/// the engine: its PNG writing and its maths
const engine=@import("engine");
/// all the maths: casts, clamps
const m=engine.core.math;
/// screenshots written
const png=engine.core.png;
/// the burst's sheet and its spot's curve
const burst=@import("burst.zig");
/// the allocator everything is made with
const Allocator=std.mem.Allocator;
/// the I/O interface every file call goes through
const Io=std.Io;
/// a directory handle
const Dir=Io.Dir;
/// where text is written
const Writer=Io.Writer;
/// a text written into a buffer
const bufPrint=std.fmt.bufPrint;
/// a UTF-16 text literal, as Windows takes them
const wide=std.unicode.utf8ToUtf16LeStringLiteral;
/// a growable list
const ArrayList=std.ArrayList;
/// the test harness
const testing=std.testing;
/// where every capture goes, under the working directory
const captureDir="shots/capture";
/// how many frames a second a capture takes at most
const fps:f32=15;
/// the fewest frames a capture takes
const minFrames=2;
/// the seconds a capture runs at first, the least and most it may run, and
/// how far - and + (and a notch of the wheel) move it
const startSeconds:f32=2;
/// (the least)
const leastSeconds:f32=0.5;
/// (the most)
const mostSeconds:f32=20;
/// (a step)
const stepSeconds:f32=0.5;
/// each frame is kept at 1/this its size each side
const keepShrink:u32=2;
/// frames a row on the sheet
const sheetCols=6;
/// the spot measured in every frame: its radius (pixels, kept size)
const spotR:u32=24;
/// the border's thickness (pixels): what is grabbed to size the frame
const border:i32=6;
/// the band along the top: its height (pixels)
const band:i32=30;
/// along the band: where REC ends, then -, the seconds and + (pixels)
const recEnd:i32=74;
/// (- ends)
const minusEnd:i32=102;
/// (the seconds end)
const secondsEnd:i32=160;
/// (+ ends)
const plusEnd:i32=188;
/// a corner's grip reaches this far along its edges (pixels)
const cornerReach:i32=18;
/// the smallest the frame may be (pixels)
const leastSize=Point{.x=320,.y=120};
/// where the frame first opens and how big (pixels)
const startRect=Rect{.left=120,.top=120,.right=760,.bottom=520};
/// the colour Windows makes see-through and clicks through (magenta)
const keyCol=rgb(255,0,255);
/// the band's bed: dark leaf litter
const bandCol=rgb(24,30,18);
/// the border and REC at rest: the amber accent
const restCol=rgb(255,215,130);
/// the border and REC while recording: a withered rust
const recCol=rgb(230,120,90);
/// the band's words: pale leaf-white
const textCol=rgb(235,240,225);
/// the band's quiet words: muted sage
const dimCol=rgb(150,170,150);
/// the band's words' height (pixels; negative: the letters' own height)
const fontH:i32=-16;
/// F9's id as a hotkey
const hotkeyId:i32=1;
/// a Windows colour, red in the low byte
fn rgb(r:u8,g:u8,b:u8)u32{return@as(u32,r)|@as(u32,g)<<8|@as(u32,b)<<16;}
/// how many frames a capture of `s` seconds takes, and how far apart (ms)
pub fn plan(s:f32)struct{frames:usize,gapMs:f32}{
  // as many as `fps` allows, held between the fewest and the burst's most
  const n=@min(@max(m.floorTo(usize,s*fps+0.5),minFrames),burst.maxFrames);
  return.{.frames=n,.gapMs=s*1000/m.f(n)};
}
/// what a press at `x` along the band does
pub const BandHit=enum{
  /// record
  rec,
  /// fewer seconds
  less,
  /// more seconds
  more,
  /// nothing here: the band is dragged
  drag,
};
/// what a press at `x` along the band does
pub fn bandHit(x:i32)BandHit{
  if(x<recEnd)return.rec;
  if(x<minusEnd)return.less;
  if(x>=secondsEnd and x<plusEnd)return.more;
  return.drag;
}
/// `s` seconds moved by `steps` steps, held between the least and most
pub fn nudge(s:f32,steps:f32)f32{return m.clamp(s+steps*stepSeconds,leastSeconds,mostSeconds);}
/// a Windows handle (a window, a picture, a device's drawing surface)
const Handle=*anyopaque;
/// a point, in pixels
const Point=extern struct{
  /// across
  x:i32,
  /// down
  y:i32,
};
/// a rectangle, in pixels
const Rect=extern struct{
  /// its left edge
  left:i32,
  /// its top edge
  top:i32,
  /// its right edge (past its last pixel)
  right:i32,
  /// its bottom edge (past its last pixel)
  bottom:i32,
};
/// a window class as Windows registers it
const WndClass=extern struct{
  /// its own size
  cbSize:u32=@sizeOf(WndClass),
  /// how its windows draw (none here)
  style:u32=0,
  /// what answers its windows' messages
  lpfnWndProc:*const fn(Handle,u32,usize,isize)callconv(.winapi)isize,
  /// spare bytes for the class (none)
  cbClsExtra:i32=0,
  /// spare bytes for each window (none)
  cbWndExtra:i32=0,
  /// the program it belongs to
  hInstance:?Handle,
  /// its icon (Windows' own)
  hIcon:?Handle=null,
  /// its pointer
  hCursor:?Handle=null,
  /// what fills it before drawing (nothing)
  hbrBackground:?Handle=null,
  /// its menu (none)
  lpszMenuName:?[*:0]const u16=null,
  /// its name
  lpszClassName:[*:0]const u16,
  /// its small icon (Windows' own)
  hIconSm:?Handle=null,
};
/// a message from Windows
const Msg=extern struct{
  /// the window it is for
  hwnd:?Handle,
  /// what it is
  message:u32,
  /// its first word
  wParam:usize,
  /// its second word
  lParam:isize,
  /// when it came
  time:u32,
  /// where the pointer was
  pt:Point,
  /// kept by Windows
  lPrivate:u32,
};
/// a window's drawing, begun and ended
const Paint=extern struct{
  /// where it is drawn
  hdc:?Handle,
  /// whether to clear first
  fErase:i32,
  /// what needs drawing
  rcPaint:Rect,
  /// kept by Windows
  fRestore:i32,
  /// kept by Windows
  fIncUpdate:i32,
  /// kept by Windows
  rgbReserved:[32]u8,
};
/// a picture's header, top row first (a negative height)
const BitmapInfo=extern struct{
  /// its own size
  biSize:u32=40,
  /// its width
  biWidth:i32,
  /// its height (negative: top row first)
  biHeight:i32,
  /// planes: always one
  biPlanes:u16=1,
  /// bits a pixel
  biBitCount:u16=32,
  /// no compression
  biCompression:u32=0,
  /// its size in bytes (worked out by Windows)
  biSizeImage:u32=0,
  /// pixels a metre across (unused)
  biXPelsPerMeter:i32=0,
  /// pixels a metre down (unused)
  biYPelsPerMeter:i32=0,
  /// palette colours used (none)
  biClrUsed:u32=0,
  /// palette colours that matter (none)
  biClrImportant:u32=0,
  /// the palette's one unused entry
  bmiColors:u32=0,
};
/// how small and large a window may be dragged
const MinMax=extern struct{
  /// kept by Windows
  ptReserved:Point,
  /// its size maximized
  ptMaxSize:Point,
  /// where it sits maximized
  ptMaxPosition:Point,
  /// the smallest it may be dragged to
  ptMinTrackSize:Point,
  /// the largest it may be dragged to
  ptMaxTrackSize:Point,
};
extern "kernel32" fn GetModuleHandleW(name:?[*:0]const u16)callconv(.winapi)?Handle;
extern "user32" fn SetProcessDpiAwarenessContext(ctx:?Handle)callconv(.winapi)i32;
extern "user32" fn RegisterClassExW(c:*const WndClass)callconv(.winapi)u16;
extern "user32" fn CreateWindowExW(ex:u32,class:[*:0]const u16,name:[*:0]const u16,style:u32,x:i32,y:i32,w:i32,h:i32,parent:?Handle,menu:?Handle,inst:?Handle,param:?*anyopaque)callconv(.winapi)?Handle;
extern "user32" fn DefWindowProcW(h:Handle,msg:u32,wp:usize,lp:isize)callconv(.winapi)isize;
extern "user32" fn GetMessageW(msg:*Msg,h:?Handle,from:u32,to:u32)callconv(.winapi)i32;
extern "user32" fn TranslateMessage(msg:*const Msg)callconv(.winapi)i32;
extern "user32" fn DispatchMessageW(msg:*const Msg)callconv(.winapi)isize;
extern "user32" fn PostQuitMessage(code:i32)callconv(.winapi)void;
extern "user32" fn DestroyWindow(h:Handle)callconv(.winapi)i32;
extern "user32" fn ShowWindow(h:Handle,cmd:i32)callconv(.winapi)i32;
extern "user32" fn UpdateWindow(h:Handle)callconv(.winapi)i32;
extern "user32" fn InvalidateRect(h:Handle,r:?*const Rect,erase:i32)callconv(.winapi)i32;
extern "user32" fn GetWindowRect(h:Handle,r:*Rect)callconv(.winapi)i32;
extern "user32" fn GetClientRect(h:Handle,r:*Rect)callconv(.winapi)i32;
extern "user32" fn BeginPaint(h:Handle,p:*Paint)callconv(.winapi)?Handle;
extern "user32" fn EndPaint(h:Handle,p:*const Paint)callconv(.winapi)i32;
extern "user32" fn FillRect(dc:Handle,r:*const Rect,brush:Handle)callconv(.winapi)i32;
extern "user32" fn LoadCursorW(inst:?Handle,name:usize)callconv(.winapi)?Handle;
extern "user32" fn SetLayeredWindowAttributes(h:Handle,key:u32,alpha:u8,flags:u32)callconv(.winapi)i32;
extern "user32" fn SetWindowDisplayAffinity(h:Handle,affinity:u32)callconv(.winapi)i32;
extern "user32" fn SetWindowLongPtrW(h:Handle,index:i32,value:isize)callconv(.winapi)isize;
extern "user32" fn GetWindowLongPtrW(h:Handle,index:i32)callconv(.winapi)isize;
extern "user32" fn RegisterHotKey(h:Handle,id:i32,mods:u32,key:u32)callconv(.winapi)i32;
extern "user32" fn GetDC(h:?Handle)callconv(.winapi)?Handle;
extern "user32" fn ReleaseDC(h:?Handle,dc:Handle)callconv(.winapi)i32;
extern "user32" fn MessageBoxW(h:?Handle,text:[*:0]const u16,title:[*:0]const u16,kind:u32)callconv(.winapi)i32;
extern "gdi32" fn CreateSolidBrush(col:u32)callconv(.winapi)?Handle;
extern "gdi32" fn DeleteObject(o:Handle)callconv(.winapi)i32;
extern "gdi32" fn CreateCompatibleDC(dc:?Handle)callconv(.winapi)?Handle;
extern "gdi32" fn DeleteDC(dc:Handle)callconv(.winapi)i32;
extern "gdi32" fn CreateDIBSection(dc:?Handle,info:*const BitmapInfo,usage:u32,bits:*?[*]u8,section:?Handle,offset:u32)callconv(.winapi)?Handle;
extern "gdi32" fn SelectObject(dc:Handle,o:Handle)callconv(.winapi)?Handle;
extern "gdi32" fn BitBlt(dc:Handle,x:i32,y:i32,w:i32,h:i32,src:Handle,sx:i32,sy:i32,op:u32)callconv(.winapi)i32;
extern "gdi32" fn SetBkMode(dc:Handle,mode:i32)callconv(.winapi)i32;
extern "gdi32" fn SetTextColor(dc:Handle,col:u32)callconv(.winapi)u32;
extern "gdi32" fn TextOutW(dc:Handle,x:i32,y:i32,text:[*]const u16,n:i32)callconv(.winapi)i32;
extern "gdi32" fn CreateFontW(h:i32,w:i32,esc:i32,orient:i32,weight:i32,italic:u32,under:u32,strike:u32,charset:u32,outPrec:u32,clipPrec:u32,quality:u32,pitch:u32,face:[*:0]const u16)callconv(.winapi)?Handle;
/// Windows' message and style numbers, by what they mean
const win=struct{
  /// a window being drawn
  const paint:u32=0x000F;
  /// its background asked to be cleared (left as is: no flicker)
  const eraseBackground:u32=0x0014;
  /// a window gone: the program ends
  const destroy:u32=0x0002;
  /// resized
  const size:u32=0x0005;
  /// asked how small it may go
  const getMinMax:u32=0x0024;
  /// asked what part of it the pointer is over
  const hitTest:u32=0x0084;
  /// a press of the left button inside it
  const leftDown:u32=0x0201;
  /// the wheel turned
  const wheel:u32=0x020A;
  /// a key pressed
  const keyDown:u32=0x0100;
  /// a hotkey pressed, wherever the focus is
  const hotkey:u32=0x0312;
  /// Esc
  const escape:usize=0x1B;
  /// F9
  const f9:u32=0x78;
  /// a hotkey held is not repeated
  const noRepeat:u32=0x4000;
  /// a window with no frame of Windows' own
  const popup:u32=0x80000000;
  /// one Windows lets be sized from its edges (its frame then given no room)
  const thickFrame:u32=0x00040000;
  /// asked how much of the window is its frame
  const calcSize:u32=0x0083;
  /// one shown
  const visible:u32=0x10000000;
  /// one with a system menu (closed from the taskbar)
  const sysMenu:u32=0x00080000;
  /// see-through where it is the key colour
  const layered:u32=0x00080000;
  /// above every window not also on top
  const topmost:u32=0x00000008;
  /// its own button in the taskbar
  const appWindow:u32=0x00040000;
  /// the layered window's key colour is see-through
  const colorKey:u32=0x1;
  /// left out of every screen capture (its own frame never shows in one)
  const excludeFromCapture:u32=0x11;
  /// where a window keeps a word of its own (the app it belongs to)
  const userData:i32=-21;
  /// the plain arrow pointer
  const arrow:usize=32512;
  /// show it
  const show:i32=5;
  /// a copy of the screen, as it is
  const srcCopy:u32=0x00CC0020;
  /// words drawn over what is there
  const transparentBk:i32=1;
  /// DPI awareness: every pixel a real one, on every screen
  const perMonitorV2:isize=-4;
  /// a message box that warns
  const warn:u32=0x30;
  /// hit test: the pointer is over the client (pressed as a button)
  const client:isize=1;
  /// hit test: over a caption (dragged to move)
  const caption:isize=2;
  /// hit tests: over an edge or corner (dragged to size)
  const left:isize=10;
  /// (right)
  const right:isize=11;
  /// (top)
  const top:isize=12;
  /// (top left)
  const topLeft:isize=13;
  /// (top right)
  const topRight:isize=14;
  /// (bottom)
  const bottom:isize=15;
  /// (bottom left)
  const bottomLeft:isize=16;
  /// (bottom right)
  const bottomRight:isize=17;
};
/// the frame and what it holds: how long a capture runs, what the band says
const App=struct{
  /// the allocator captures are made with
  gpa:Allocator,
  /// the I/O files are written through
  io:Io,
  /// the frame's window
  hwnd:?Handle=null,
  /// the band's words' font
  font:?Handle=null,
  /// how long a capture runs (s)
  seconds:f32=startSeconds,
  /// whether it is recording now
  recording:bool=false,
  /// what the band last says (after the seconds)
  status:[96]u8=undefined,
  /// how much of `status` is said
  statusLen:usize=0,
  /// says `text` along the band
  fn say(a:*App,comptime fmt:[]const u8,args:anytype)void{
    const s=bufPrint(&a.status,fmt,args) catch a.status[0..0];
    a.statusLen=s.len;
    a.redraw();
  }
  /// draws the frame again now
  fn redraw(a:*App)void{
    const h=a.hwnd orelse return;
    _=InvalidateRect(h,null,0);
    _=UpdateWindow(h);
  }
  /// the screen's pixels showing inside the border (screen pixels)
  fn region(a:*const App)Rect{
    // the window's place on the screen
    var r:Rect=undefined;
    _=GetWindowRect(a.hwnd.?,&r);
    return.{.left=r.left+border,.top=r.top+band,.right=r.right-border,.bottom=r.bottom-border};
  }
  /// records what shows inside the border over `seconds`, then writes it
  fn capture(a:*App)void{
    if(a.recording)return;
    a.recording=true;
    a.say("recording...",.{});
    // the folder it was written in, or why it failed
    const done=a.record()catch|e|{
      a.recording=false;
      a.say("failed: {t}",.{e});
      return;
    };
    a.recording=false;
    a.say("saved {d} frames: {s}",.{done.frames,done.name});
  }
  /// takes the frames, then writes them, their sheet and their curve
  fn record(a:*App)!struct{frames:usize,name:[]const u8}{
    const r=a.region();
    const w=r.right-r.left;
    const h=r.bottom-r.top;
    if(w<@as(i32,keepShrink)*2 or h<@as(i32,keepShrink)*2)return error.TooSmall;
    // how many frames, how far apart, and the frames kept (BGRA, shrunk)
    const p=plan(a.seconds);
    var frames:ArrayList([]u8)=.empty;
    defer{
      for(frames.items)|f|a.gpa.free(f);
      frames.deinit(a.gpa);
    }
    try frames.ensureTotalCapacity(a.gpa,p.frames);
    // the screen, a surface to copy it into and its pixels
    const screen=GetDC(null) orelse return error.NoScreen;
    defer _=ReleaseDC(null,screen);
    const mem=CreateCompatibleDC(screen) orelse return error.NoSurface;
    defer _=DeleteDC(mem);
    const info=BitmapInfo{.biWidth=w,.biHeight=-h};
    var bits:?[*]u8=null;
    const pic=CreateDIBSection(screen,&info,0,&bits,null,0) orelse return error.NoSurface;
    defer _=DeleteObject(pic);
    const old=SelectObject(mem,pic);
    defer if(old)|o|{_=SelectObject(mem,o);};
    const px=bits orelse return error.NoSurface;
    const uw:u32=@intCast(w);
    const uh:u32=@intCast(h);
    // when it began (ns)
    const start=Io.Clock.real.now(a.io).nanoseconds;
    for(0..p.frames)|i|{
      // wait for this frame's moment
      const due=start+@as(i96,@intFromFloat(m.f(i)*p.gapMs*std.time.ns_per_ms));
      const now=Io.Clock.real.now(a.io).nanoseconds;
      if(due>now)a.io.sleep(.fromNanoseconds(@intCast(due-now)),.awake)catch{};
      if(BitBlt(mem,0,0,w,h,screen,r.left,r.top,win.srcCopy)==0)return error.CopyFailed;
      frames.appendAssumeCapacity(try png.shrink(a.gpa,px[0..@as(usize,uw)*uh*4],uw,uh,keepShrink));
    }
    a.say("writing {d} frames...",.{p.frames});
    // the folder, named by when it was taken
    const secs:i64=@intCast(@divFloor(start,std.time.ns_per_s));
    var nb:[64]u8=undefined;
    const dir=try bufPrint(&nb,captureDir++"/{d}",.{secs});
    try Dir.cwd().createDirPath(a.io,dir);
    try write(a.gpa,a.io,dir,frames.items,uw/keepShrink,uh/keepShrink);
    // the newest capture's folder, for Claude to find
    try Dir.cwd().writeFile(a.io,.{.sub_path=captureDir++"/latest.txt",.data=dir});
    return.{.frames=p.frames,.name=dir[captureDir.len+1..]};
  }
};
/// writes each frame (BGRA, `w`×`h`) as `<dir>/<n>.png`, then their sheet
/// (`sheet.png`) and a spot's light through them (`curve.txt`)
fn write(gpa:Allocator,io:Io,dir:[]const u8,frames:[]const []u8,w:u32,h:u32)!void{
  // the frames as pictures for the sheet, and the path being written
  var ims:ArrayList(png.Image)=.empty;
  defer{
    for(ims.items)|im|im.deinit(gpa);
    ims.deinit(gpa);
  }
  try ims.ensureTotalCapacity(gpa,frames.len);
  var pb:[96]u8=undefined;
  for(frames,0..)|f,i|{
    const file=try png.encode(gpa,w,h,f,.bgra);
    defer gpa.free(file);
    try Dir.cwd().writeFile(io,.{.sub_path=try bufPrint(&pb,"{s}/{d}.png",.{dir,i}),.data=file});
    // the frame as RGB, top row first
    const rgbPx=try gpa.alloc(u8,@as(usize,w)*h*3);
    for(0..@as(usize,w)*h)|k|{
      rgbPx[k*3]=f[k*4+2];
      rgbPx[k*3+1]=f[k*4+1];
      rgbPx[k*3+2]=f[k*4];
    }
    ims.appendAssumeCapacity(.{.w=w,.h=h,.rgb=rgbPx});
  }
  try burst.sheet(gpa,io,ims.items,sheetCols,try bufPrint(&pb,"{s}/sheet.png",.{dir}));
  var aw:Writer.Allocating=.init(gpa);
  defer aw.deinit();
  try burst.report(ims.items,.{.r=spotR},&aw.writer);
  try Dir.cwd().writeFile(io,.{.sub_path=try bufPrint(&pb,"{s}/curve.txt",.{dir}),.data=aw.written()});
}
/// the app a window belongs to (kept in its user word), if it is set yet
fn appOf(h:Handle)?*App{
  const v=GetWindowLongPtrW(h,win.userData);
  return if(v==0)null else @ptrFromInt(@as(usize,@bitCast(v)));
}
/// the low and high halves of a message word, as signed pixels
fn halves(lp:isize)Point{
  const v:usize=@bitCast(lp);
  return.{.x=@as(i16,@bitCast(@as(u16,@truncate(v)))),.y=@as(i16,@bitCast(@as(u16,@truncate(v>>16))))};
}
/// what part of the frame (`w`×`h`) point `p` (in the frame's pixels) is:
/// an edge or corner sizes it, the band's buttons are pressed, the rest of
/// the band drags it, and the middle is see-through (never asked)
fn hit(p:Point,w:i32,h:i32)isize{
  // which edges it is near
  const l=p.x<border or (p.x<cornerReach and (p.y<border or p.y>=h-border));
  const r=p.x>=w-border or (p.x>=w-cornerReach and (p.y<border or p.y>=h-border));
  const t=p.y<border or (p.y<cornerReach and (p.x<border or p.x>=w-border));
  const b=p.y>=h-border or (p.y>=h-cornerReach and (p.x<border or p.x>=w-border));
  if(t and l)return win.topLeft;
  if(t and r)return win.topRight;
  if(b and l)return win.bottomLeft;
  if(b and r)return win.bottomRight;
  if(t)return win.top;
  if(b)return win.bottom;
  if(l)return win.left;
  if(r)return win.right;
  if(p.y<band)return if(bandHit(p.x-border)==.drag)win.caption else win.client;
  return win.client;
}
/// answers the frame's messages
fn wndProc(h:Handle,msg:u32,wp:usize,lp:isize)callconv(.winapi)isize{
  // the sizing frame takes no room, from the start: all of it is drawn as the frame
  if(msg==win.calcSize and wp!=0)return 0;
  const a=appOf(h) orelse return DefWindowProcW(h,msg,wp,lp);
  switch(msg){
    win.paint=>{
      draw(a,h);
      return 0;
    },
    win.eraseBackground=>return 1,
    win.size=>{
      _=InvalidateRect(h,null,0);
      return 0;
    },
    win.getMinMax=>{
      const mm:*MinMax=@ptrFromInt(@as(usize,@bitCast(lp)));
      mm.ptMinTrackSize=leastSize;
      return 0;
    },
    win.hitTest=>{
      // the pointer, in the frame's pixels
      var r:Rect=undefined;
      _=GetWindowRect(h,&r);
      const p=halves(lp);
      return hit(.{.x=p.x-r.left,.y=p.y-r.top},r.right-r.left,r.bottom-r.top);
    },
    win.leftDown=>{
      const p=halves(lp);
      if(p.y<band)switch(bandHit(p.x-border)){
        .rec=>a.capture(),
        .less=>{a.seconds=nudge(a.seconds,-1);a.redraw();},
        .more=>{a.seconds=nudge(a.seconds,1);a.redraw();},
        .drag=>{},
      };
      return 0;
    },
    win.wheel=>{
      // the wheel's turn: up for more seconds
      const turn:i16=@bitCast(@as(u16,@truncate(wp>>16)));
      a.seconds=nudge(a.seconds,if(turn>0)1 else -1);
      a.redraw();
      return 0;
    },
    win.hotkey=>{
      if(wp==hotkeyId)a.capture();
      return 0;
    },
    win.keyDown=>{
      if(wp==win.escape)_=DestroyWindow(h);
      return 0;
    },
    win.destroy=>{
      PostQuitMessage(0);
      return 0;
    },
    else=>return DefWindowProcW(h,msg,wp,lp),
  }
}
/// `text` (ASCII) at (x, y) in `col`
fn words(dc:Handle,x:i32,y:i32,col:u32,text:[]const u8)void{
  // the text as UTF-16
  var buf:[128]u16=undefined;
  const n=@min(text.len,buf.len);
  for(text[0..n],0..)|c,i|buf[i]=c;
  _=SetTextColor(dc,col);
  _=TextOutW(dc,x,y,&buf,@intCast(n));
}
/// paints the frame: the middle the key colour (see-through), the border
/// and the band with its buttons, the seconds and what it last said
fn draw(a:*App,h:Handle)void{
  var ps:Paint=undefined;
  const dc=BeginPaint(h,&ps) orelse return;
  defer _=EndPaint(h,&ps);
  var c:Rect=undefined;
  _=GetClientRect(h,&c);
  // its brushes
  const key=CreateSolidBrush(keyCol) orelse return;
  defer _=DeleteObject(key);
  const edge=CreateSolidBrush(if(a.recording)recCol else restCol) orelse return;
  defer _=DeleteObject(edge);
  const bed=CreateSolidBrush(bandCol) orelse return;
  defer _=DeleteObject(bed);
  _=FillRect(dc,&c,key);
  _=FillRect(dc,&.{.left=0,.top=0,.right=border,.bottom=c.bottom},edge);
  _=FillRect(dc,&.{.left=c.right-border,.top=0,.right=c.right,.bottom=c.bottom},edge);
  _=FillRect(dc,&.{.left=0,.top=c.bottom-border,.right=c.right,.bottom=c.bottom},edge);
  _=FillRect(dc,&.{.left=0,.top=0,.right=c.right,.bottom=border},edge);
  _=FillRect(dc,&.{.left=border,.top=border,.right=c.right-border,.bottom=band},bed);
  _=FillRect(dc,&.{.left=border+recEnd-2,.top=border,.right=border+recEnd,.bottom=band},edge);
  _=SetBkMode(dc,win.transparentBk);
  if(a.font)|f|_=SelectObject(dc,f);
  // the words' line
  const y=border+2;
  words(dc,border+10,y,if(a.recording)recCol else restCol,"REC (F9)");
  words(dc,border+minusEnd-20,y,textCol,"-");
  var sb:[16]u8=undefined;
  words(dc,border+minusEnd+6,y,textCol,bufPrint(&sb,"{d:.1} s",.{a.seconds})catch"");
  words(dc,border+secondsEnd+8,y,textCol,"+");
  words(dc,border+plusEnd+10,y,dimCol,a.status[0..a.statusLen]);
}
/// opens the frame over the screen and answers it until it is closed
pub fn main(init:std.process.Init)!void{
  // every pixel a real one, so what is copied is what shows inside the border
  _=SetProcessDpiAwarenessContext(@ptrFromInt(@as(usize,@bitCast(win.perMonitorV2))));
  var app=App{.gpa=init.gpa,.io=init.io};
  app.say("drag the band to move, the edges to size; Esc closes",.{});
  const inst=GetModuleHandleW(null);
  const class=wide("ParasymiCapture");
  if(RegisterClassExW(&.{.lpfnWndProc=wndProc,.hInstance=inst,.lpszClassName=class,.hCursor=LoadCursorW(null,win.arrow)})==0)return error.NoClass;
  const h=CreateWindowExW(win.layered|win.topmost|win.appWindow,class,wide("Parasymi capture"),win.popup|win.thickFrame|win.sysMenu,startRect.left,startRect.top,startRect.right-startRect.left,startRect.bottom-startRect.top,null,null,inst,null) orelse return error.NoWindow;
  app.hwnd=h;
  _=SetWindowLongPtrW(h,win.userData,@bitCast(@intFromPtr(&app)));
  _=SetLayeredWindowAttributes(h,keyCol,255,win.colorKey);
  _=SetWindowDisplayAffinity(h,win.excludeFromCapture);
  app.font=CreateFontW(fontH,0,0,0,600,0,0,0,1,0,0,5,0,wide("Segoe UI"));
  defer if(app.font)|f|{_=DeleteObject(f);};
  if(RegisterHotKey(h,hotkeyId,win.noRepeat,win.f9)==0)app.say("F9 is taken elsewhere: use REC",.{});
  _=ShowWindow(h,win.show);
  _=UpdateWindow(h);
  // the messages, until the frame is closed
  var msg:Msg=undefined;
  while(GetMessageW(&msg,null,0,0)>0){
    _=TranslateMessage(&msg);
    _=DispatchMessageW(&msg);
  }
}
test"a capture takes as many frames as its seconds allow, evenly apart"{
  const p=plan(2);
  try testing.expectEqual(@as(usize,30),p.frames);
  try testing.expectApproxEqAbs(@as(f32,66.67),p.gapMs,0.01);
  // a long one is held to the burst's most
  try testing.expectEqual(burst.maxFrames,plan(mostSeconds).frames);
  try testing.expectEqual(@as(usize,minFrames),plan(0.01).frames);
}
test"the band's buttons, and the seconds held within their range"{
  try testing.expectEqual(BandHit.rec,bandHit(10));
  try testing.expectEqual(BandHit.less,bandHit(80));
  try testing.expectEqual(BandHit.drag,bandHit(120));
  try testing.expectEqual(BandHit.more,bandHit(170));
  try testing.expectEqual(BandHit.drag,bandHit(400));
  try testing.expectEqual(@as(f32,2.5),nudge(2,1));
  try testing.expectEqual(leastSeconds,nudge(leastSeconds,-1));
  try testing.expectEqual(mostSeconds,nudge(mostSeconds,1));
}
test"the frame's edges size it, its band's empty stretch drags it"{
  try testing.expectEqual(win.topLeft,hit(.{.x=1,.y=1},400,200));
  try testing.expectEqual(win.bottomRight,hit(.{.x=399,.y=199},400,200));
  try testing.expectEqual(win.left,hit(.{.x=2,.y=100},400,200));
  try testing.expectEqual(win.caption,hit(.{.x=300,.y=15},400,200));
  try testing.expectEqual(win.client,hit(.{.x=20,.y=15},400,200));
}
