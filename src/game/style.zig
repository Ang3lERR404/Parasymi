//! shared HUD colours. Muted greens/browns base, amber accents.
const C = [4]u8;
pub const white:C = .{235, 240, 225, 255};
pub const dim:C = .{150, 170, 150, 255};
pub const gold:C = .{255, 215, 130, 255};
pub const dark:C = .{20, 20, 20, 255};
/// large panel membrane (belly, research, etc) — dark purple-green
pub const membrane:C = .{30, 22, 40, 225};
/// small panel membrane (tooltips, info cards) — greener
pub const skin:C = .{24, 40, 30, 215};
/// empty inventory slot
pub const pod_empty:C = .{40, 55, 45, 160};
/// something not yet understood / locked
pub const unknown:C = .{70, 70, 80, 255};
/// growth tendril fill (symbiotic green)
pub const growth:C = .{120, 230, 150, 255};
/// free cam indicator (soft green-cyan)
pub const freecam:C = .{150, 230, 190, 255};
/// free cam glow (same hue, low alpha)
pub const freecam_glow:C = .{150, 230, 190, 90};
/// pause menu veil (near-black, soft)
pub const veil:C = .{4, 6, 10, 200};
/// pause menu panel membrane
pub const pause_panel:C = .{24, 30, 40, 235};
/// research panel membrane (dark purple)
pub const research_panel:C = .{26, 18, 44, 225};
/// research row: completed
pub const research_done:C = .{140, 230, 170, 255};
/// research row: locked
pub const research_locked:C = .{105, 105, 120, 255};
/// research row: currently selected glow
pub const research_active:C = .{255, 210, 130, 120};
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