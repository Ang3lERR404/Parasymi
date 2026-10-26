//! shared HUD colours (every panel a trellis, every slot a husk), type scale and bar sizes. Muted greens/browns base,
//! amber accents.
const C = [4]u8;

/// type scale (text size multipliers), largest first
pub const text_banner:f32 = 3.5;
pub const text_title:f32 = 2.5;
pub const text_heading:f32 = 2;
pub const text_label:f32 = 1.75;
pub const text_row:f32 = 1.6;
pub const text_sub:f32 = 1.5;
/// a structure's or plant's description line
pub const text_body:f32 = 1.4;
pub const text_note:f32 = 1.25;
pub const text_small:f32 = 1.2;
pub const text_fine:f32 = 1.15;
pub const text_tiny:f32 = 1.1;
/// tendril (progress bar) thickness, slim and bold
pub const bar_h:f32 = 12;
pub const bar_h_bold:f32 = 14;
/// left-edge panels sit this far in from the screen's edge
pub const edge:f32 = 16;
/// a structure's description bar: offset from the text and width
pub const desc_bar_x:f32 = 250;
pub const desc_bar_w:f32 = 110;
/// spacing of item slots (belly, hotbar, a structure's store)
pub const slot_gap:f32 = 64;
/// a centred panel's title sits this far below its top
pub const title_y:f32 = 30;
/// centred panels shift up by this to clear the hotbar
pub const panel_lift:f32 = 30;
/// a menu's backdrop veil reaches this share of the screen's longer side
pub const veil_reach:f32 = 0.75;

pub const white:C = .{235, 240, 225, 255};
pub const dim:C = .{150, 170, 150, 255};
pub const gold:C = .{255, 215, 130, 255};
pub const dark:C = .{20, 20, 20, 255};
/// a large panel's bed under its trellis (belly, a structure's): dark leaf litter
pub const panel:C = .{24, 30, 18, 242};
/// a small panel's bed (tooltips, info cards): mossier
pub const card:C = .{24, 36, 22, 232};
/// empty inventory slot
pub const pod_empty:C = .{40, 55, 45, 160};
/// a slot under the mouse; one that will take what the cursor carries
pub const slot_hover:C = .{220, 235, 210, 70};
pub const drop_target:C = .{255, 215, 130, 120};
/// a slot's count drawn over its icon, and the shadow under it
pub const count_shadow:C = .{10, 12, 10, 220};
/// something not yet understood / locked
pub const unknown:C = .{70, 70, 80, 255};
/// growth tendril fill (symbiotic green)
pub const growth:C = .{120, 230, 150, 255};
/// free cam indicator (soft green-cyan)
pub const freecam:C = .{150, 230, 190, 255};
/// free cam glow (same hue, low alpha)
pub const freecam_glow:C = .{150, 230, 190, 90};
/// the middle of the screen, looking out of the wolf's eyes: a lit seed
/// and its glow
pub const aim:C = .{225, 245, 210, 230};
pub const aim_glow:C = .{150, 230, 190, 70};
/// pause menu veil (near-black, soft)
pub const veil:C = .{4, 6, 10, 200};
/// pause menu panel's bed: night-dark moss
pub const pause_panel:C = .{18, 26, 20, 244};
/// a pause menu row or option under the mouse
pub const menu_hover:C = .{255, 215, 130, 40};
/// research panel's bed: dusk-dark, a little violet, the sapling's sky
pub const research_panel:C = .{24, 22, 30, 240};
/// research row: completed
pub const research_done:C = .{140, 230, 170, 255};
/// research row: locked
pub const research_locked:C = .{105, 105, 120, 255};
/// research row: currently selected glow
pub const research_active:C = .{255, 210, 130, 120};
/// research node under the mouse
pub const research_hover:C = .{220, 235, 210, 90};
/// research bud that can be chosen: a faint gold call
pub const research_invite:C = .{255, 215, 130, 45};
/// research sapling bark: young green twig, old brown wood
pub const bark_young:C = .{100, 140, 80, 255};
pub const bark_old:C = .{105, 80, 58, 255};
/// research sapling: a known leaf, a bud that can be chosen, a dormant bud
pub const leaf:C = .{105, 185, 105, 235};
pub const bud:C = .{235, 195, 115, 245};
pub const bud_dormant:C = .{95, 95, 105, 200};
/// the soil the sapling stands in
pub const soil:C = .{70, 48, 32, 150};
/// sun orb (warm amber)
pub const sun:C = .{255, 210, 120, 255};
/// moon orb (cool blue)
pub const moon:C = .{170, 190, 255, 255};
/// sap fill tendril (amber)
pub const sap:C = .{255, 190, 90, 255};
/// research progress tendril (violet)
pub const research_tendril:C = .{200, 160, 255, 255};
/// root-digger progress tendril (warm amber-brown)
pub const digger:C = .{200, 170, 110, 255};
/// a lithophage condensing its crystal (pale lilac)
pub const lith:C = .{190, 165, 235, 255};
