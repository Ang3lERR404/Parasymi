//! item icons for the HUD: what sits in a belly slot, a hotbar pod or on the
//! cursor. A structure's bulb or a plant's seed is a seed broken open, its
//! sprout or two showing what it will grow into (the structure's `icon`
//! hook, or its module in `seeds.zig`, drawn with the kit below); anything
//! else is its colour, for now.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("engine").core.math;
const Draw = @import("engine").ui.draw.Draw;
const Color = @import("engine").ui.draw.Color;
const items = @import("../sim/items.zig");
const st = @import("structures.zig");
const seeds = @import("seeds.zig");
const s = @import("style.zig");
const txt = @import("text.zig");

/// a point in icon units: x right, y up, origin at the slot's centre, 1 = its radius.
pub const P = [2]f32;

/// the seed sits low in the slot, its split tip at `TOP`, where sprouts rise from
const SEED_C:P = .{0, -0.38};
const SEED_W:f32 = 0.62;
const SEED_H:f32 = 0.92;
pub const TOP:f32 = 0.06;
const CRACK:f32 = 0.8;
/// stems: segments along a curve, thinning to this share of their base
const STEM_SEGS = 6;
const STEM_TIP:f32 = 0.35;
/// the sprouts bend in a breeze: radians-ish per unit of height, and its tempo
const SWAY:f32 = 0.1;
const SWAY_RATE:f32 = 1.3;
/// an item that is not a bulb: a filled pod this share of the slot, its
/// short name on it
const FILL_R:f32 = 0.95;

pub const sprout:Color = .{110, 190, 95, 255};
pub const stem_col:Color = s.bark_young;
/// a woven root (conduit arches, a digger's roots)
pub const root_col:Color = .{150, 112, 72, 255};
/// an anther's pollen (meshgen `POLLEN`)
pub const pollen:Color = .{235, 185, 80, 255};

pub const Icon = struct {
  d:*Draw,
  /// the slot's centre and radius, in pixels
  c:[2]f32,
  r:f32,
  /// UI seconds (the sprouts sway) and a per-slot phase
  t:f32,
  phase:f32,
  /// faded (not understood yet, or lifted out of its slot)
  alpha:u8 = 255,

  /// a colour at this icon's fade.
  pub fn col(ic:Icon, c:Color) Color {
    return .{c[0], c[1], c[2], @intCast(@as(u32, c[3]) * ic.alpha / 255)};
  }

  /// how far the breeze leans the sprouts at height `y`.
  fn lean(ic:Icon, y:f32) f32 {
    const h = @max(y - TOP, 0);
    return SWAY * @sin(ic.t * SWAY_RATE + ic.phase * 6) * h * h;
  }

  /// pixel position of icon point `p`, leaning with the breeze.
  pub fn px(ic:Icon, p:P) [2]f32 {
    return .{ic.c[0] + (p[0] + ic.lean(p[1])) * ic.r, ic.c[1] - p[1] * ic.r};
  }

  /// the seed coat, split open at its tip.
  pub fn coat(ic:Icon, c:Color) Allocator.Error!void {
    const q = ic.px(SEED_C);
    try ic.d.grain(q[0], q[1], SEED_W * ic.r, SEED_H * ic.r, ic.col(c), CRACK, ic.phase);
  }

  /// a stem along the cubic Bézier `p` (icon units), `w` thick at its
  /// base, thinning toward its tip.
  pub fn stem(ic:Icon, p:[4]P, w:f32, c:Color) Allocator.Error!void {
    var prev = ic.px(p[0]);
    var arc:f32 = 0;
    for (1..STEM_SEGS + 1) |i| {
      const k0 = m.ratio(i - 1, STEM_SEGS);
      const k = m.ratio(i, STEM_SEGS);
      const next = ic.px(curve(p, k));
      const r0 = w * ic.r * 0.5 * m.lerp(1, STEM_TIP, k0);
      const r1 = w * ic.r * 0.5 * m.lerp(1, STEM_TIP, k);
      try ic.d.limb(prev, next, r0, r1, ic.col(c), arc);
      arc += @sqrt((next[0] - prev[0]) * (next[0] - prev[0]) + (next[1] - prev[1]) * (next[1] - prev[1]));
      prev = next;
    }
  }

  /// a leaf from `base`, pointing `ang` radians (0 right, counter-clockwise),
  /// `len` long and `wid` wide (icon units); it flutters a little.
  pub fn leaf(ic:Icon, base:P, ang:f32, len:f32, wid:f32, c:Color, open:f32) Allocator.Error!void {
    const flutter = 0.08 * @sin(ic.t * 2.1 + ic.phase * 5 + base[0] * 7);
    try ic.d.leaf(ic.px(base), -(ang + flutter), len * ic.r, wid * ic.r, ic.col(c), open, ic.phase + base[1]);
  }

  /// a small round pod (a bud, a bead of sap, a stone).
  pub fn bud(ic:Icon, at:P, r:f32, c:Color, lit:f32) Allocator.Error!void {
    const q = ic.px(at);
    try ic.d.pod(q[0], q[1], r * ic.r, ic.col(c), lit, ic.phase + at[0]);
  }

  pub fn glow(ic:Icon, at:P, r:f32, c:Color) Allocator.Error!void {
    const q = ic.px(at);
    try ic.d.glow(q[0], q[1], r * ic.r, ic.col(c));
  }

  pub fn gem(ic:Icon, at:P, r:f32, c:Color) Allocator.Error!void {
    const q = ic.px(at);
    try ic.d.gem(q[0], q[1], r * ic.r, ic.col(c), 1, ic.phase);
  }

  /// a flower's stamens: `n` thin filaments fanning `spread` radians either
  /// side of `ang` from its heart `at`, `len` long, each tipped with a
  /// grain of pollen; they sway with the flower.
  pub fn stamens(ic:Icon, at:P, ang:f32, spread:f32, n:u32, len:f32, c:Color) Allocator.Error!void {
    for (0..n) |i| {
      const k = if (n > 1) m.ratio(i, n - 1) * 2 - 1 else 0;
      const a = ang + k * spread + 0.05 * @sin(ic.t * 1.9 + ic.phase * 5 + m.f(i));
      // the outer ones shorter, as they lean away
      const l = len * (1 - 0.25 * k * k);
      const tip:P = .{at[0] + @cos(a) * l, at[1] + @sin(a) * l};
      const mid:P = .{at[0] + @cos(ang + k * spread * 0.6) * l * 0.5, at[1] + @sin(ang + k * spread * 0.6) * l * 0.5};
      try ic.stem(.{at, mid, mid, tip}, 0.025, c);
      try ic.bud(tip, 0.028, pollen, 1);
    }
  }

  /// a hair-thin thread hanging from `from` straight down `len`, waving
  /// `waves` times across its length, the swing `amp` widening toward its
  /// free tip and a wave running down it; it tapers from `w` to nothing.
  pub fn thread(ic:Icon, from:P, len:f32, waves:f32, amp:f32, w:f32, ph:f32, c:Color) Allocator.Error!void {
    const N = 14;
    var prev = ic.px(from);
    var arc:f32 = 0;
    for (1..N + 1) |i| {
      const k0 = m.ratio(i - 1, N);
      const k = m.ratio(i, N);
      const swing = amp * k * @sin(k * waves * m.tau - ic.t * 2.2 + ph);
      const next = ic.px(.{from[0] + swing, from[1] - len * k});
      try ic.d.limb(prev, next, w * ic.r * 0.5 * (1 - k0) + 0.3, w * ic.r * 0.5 * (1 - k) + 0.3, ic.col(c), arc);
      arc += @sqrt((next[0] - prev[0]) * (next[0] - prev[0]) + (next[1] - prev[1]) * (next[1] - prev[1]));
      prev = next;
    }
  }

  /// a small seed of its own (what a germinator makes).
  pub fn kernel(ic:Icon, at:P, h:f32, c:Color) Allocator.Error!void {
    const q = ic.px(at);
    try ic.d.grain(q[0], q[1], h * 0.66 * ic.r, h * ic.r, ic.col(c), 0, ic.phase + 0.5);
  }
};

/// the point `k` (0..1) along the cubic Bézier `p`.
pub fn curve(p:[4]P, k:f32) P {
  var o:P = undefined;
  for (0..2) |a| {
    const ab = m.lerp(p[0][a], p[1][a], k);
    const bc = m.lerp(p[1][a], p[2][a], k);
    const cd = m.lerp(p[2][a], p[3][a], k);
    o[a] = m.lerp(m.lerp(ab, bc, k), m.lerp(bc, cd, k), k);
  }
  return o;
}

/// draws `item` in a slot of radius `r` at `c`: a bulb's seed and sprouts,
/// else its colour. `alpha` fades it; `phase` keeps neighbours apart.
pub fn draw(d:*Draw, item:items.Item, c:[2]f32, r:f32, t:f32, phase:f32, lit:f32, alpha:u8) Allocator.Error!void {
  const ic:Icon = .{.d = d, .c = c, .r = r, .t = t, .phase = phase, .alpha = alpha};
  const info = item.info();
  if (st.kindOf(item)) |k| {
    try st.icon(k, ic, info.col);
    return;
  }
  if (try seeds.icon(item, ic, info.col)) return;
  try d.pod(c[0], c[1], r * FILL_R, ic.col(info.col), lit, phase);
  const short = txt.item(item).short;
  const size = s.text_heading * r / 24;
  _ = try d.text(c[0] - Draw.width(short, size) / 2, c[1] - r * 0.5, size, ic.col(s.dark), short);
}

/// how many, low on the right of a slot, over a shadow so it reads on any icon.
pub fn count(d:*Draw, c:[2]f32, r:f32, n:u32) Allocator.Error!void {
  const size = s.text_note * r / 24;
  const x = c[0] + r * 0.2;
  const y = c[1] + r * 0.3;
  _ = try d.number(x + 1, y + 1, size, s.count_shadow, n);
  _ = try d.number(x, y, size, if (n > 0) s.white else s.dim, n);
}

/// a plain bulb: the seed and a pair of leaves (a structure with no `icon`).
pub fn plain(ic:Icon, c:Color) Allocator.Error!void {
  try ic.stem(.{.{0, TOP}, .{0, 0.3}, .{0.02, 0.45}, .{0, 0.6}}, 0.1, stem_col);
  try ic.leaf(.{0, 0.55}, 0.5, 0.4, 0.22, sprout, 0.9);
  try ic.leaf(.{0, 0.5}, m.pi - 0.5, 0.36, 0.2, sprout, 0.9);
  try ic.coat(c);
}
