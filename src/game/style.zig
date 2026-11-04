//! shared HUD colours (every panel a trellis, every slot a husk), type scale and bar sizes. Muted greens/browns base,
//! amber accents.
/// the import hub
const lib=@import("../lib.zig");
/// the maths: vectors (Vec), rows (Vice) and matrices (Mat)
const m=lib.engine.core.math;
/// a UI colour: red, green, blue and alpha bytes
const C=m.Vice(u8,4);
/// the type scale (text size multipliers), largest first: a banner across the screen
pub const textBanner:f32=3.5;
/// a panel's title
pub const textTitle:f32=2.5;
/// a section heading
pub const textHeading:f32=2;
/// a slot's or button's label
pub const textLabel:f32=1.75;
/// a row in a list
pub const textRow:f32=1.6;
/// a subtitle under a heading
pub const textSub:f32=1.5;
/// a structure's or plant's description line
pub const textBody:f32=1.4;
/// a note under a description
pub const textNote:f32=1.25;
/// small print
pub const textSmall:f32=1.2;
/// finer print
pub const textFine:f32=1.15;
/// the tiniest print
pub const textTiny:f32=1.1;
/// a slim tendril (progress bar), in pixels thick
pub const barH:f32=12;
/// a bold tendril, in pixels thick
pub const barHBold:f32=14;
/// left-edge panels sit this far in from the screen's edge
pub const edge:f32=16;
/// a structure's description bar: how far it sits right of the text (px)
pub const descBarX:f32=250;
/// how wide a structure's description bar is (px)
pub const descBarW:f32=110;
/// spacing of item slots (belly, hotbar, a structure's store)
pub const slotGap:f32=64;
/// a centred panel's title sits this far below its top
pub const titleY:f32=30;
/// centred panels shift up by this to clear the hotbar
pub const panelLift:f32=30;
/// a menu's backdrop veil reaches this share of the screen's longer side
pub const veilReach:f32=0.75;
/// bright text: pale leaf-white
pub const white:C=.{235,240,225,255};
/// dim text: muted sage
pub const dim:C=.{150,170,150,255};
/// the amber accent: gold
pub const gold:C=.{255,215,130,255};
/// near-black, for outlines and shadows
pub const dark:C=.{20,20,20,255};
/// a large panel's bed under its trellis (belly, a structure's): dark leaf litter
pub const panel:C=.{24,30,18,242};
/// a small panel's bed (tooltips, info cards): mossier
pub const card:C=.{24,36,22,232};
/// empty inventory slot
pub const podEmpty:C=.{40,55,45,160};
/// a slot under the mouse: a pale wash
pub const slotHover:C=.{220,235,210,70};
/// a slot that will take what the cursor carries: a gold wash
pub const dropTarget:C=.{255,215,130,120};
/// a slot's count drawn over its icon, and the shadow under it
pub const countShadow:C=.{10,12,10,220};
/// something not yet understood / locked
pub const unknown:C=.{70,70,80,255};
/// growth tendril fill (symbiotic green)
pub const growth:C=.{120,230,150,255};
/// free cam indicator (soft green-cyan)
pub const freecam:C=.{150,230,190,255};
/// free cam glow (same hue, low alpha)
pub const freecamGlow:C=.{150,230,190,90};
/// the middle of the screen, looking out of the wolf's eyes: a lit seed
pub const aim:C=.{225,245,210,230};
/// the lit seed's soft halo
pub const aimGlow:C=.{150,230,190,70};
/// pause menu veil (near-black, soft)
pub const veil:C=.{4,6,10,200};
/// pause menu panel's bed: night-dark moss
pub const pausePanel:C=.{18,26,20,244};
/// a pause menu row or option under the mouse
pub const menuHover:C=.{255,215,130,40};
/// selected text: a sheath of sap lit behind its letters
pub const selection:C=.{255,200,110,95};
/// `--link`: the gardener's name over their messages, young leaf green
pub const chatGardener:C=.{150,220,140,255};
/// `--link`: Claude's name over its messages, a soft lilac
pub const chatClaude:C=.{200,180,255,255};
/// research panel's bed: dusk-dark, a little violet, the sapling's sky
pub const researchPanel:C=.{24,22,30,240};
/// research row: completed
pub const researchDone:C=.{140,230,170,255};
/// research row: locked
pub const researchLocked:C=.{105,105,120,255};
/// research row: currently selected glow
pub const researchActive:C=.{255,210,130,120};
/// research node under the mouse
pub const researchHover:C=.{220,235,210,90};
/// research bud that can be chosen: a faint gold call
pub const researchInvite:C=.{255,215,130,45};
/// research sapling bark: young green twig
pub const barkYoung:C=.{100,140,80,255};
/// research sapling bark: old brown wood, toward the trunk
pub const barkOld:C=.{105,80,58,255};
/// research sapling: a known leaf
pub const leaf:C=.{105,185,105,235};
/// a bud that can be chosen
pub const bud:C=.{235,195,115,245};
/// a dormant bud, still waiting
pub const budDormant:C=.{95,95,105,200};
/// the research tree's roots, darker than its bark for living in the earth
pub const rootBark:C=.{62,46,34,255};
/// the research tree's painted backdrop: opaque, its own colours in the shader
pub const dusk:C=.{255,255,255,255};
/// the mist a dormant study waits in
pub const mist:C=.{150,150,175,60};
/// a symbiotic study's petals: soft rose
pub const symbioticBloom:C=.{240,170,190,255};
/// a parasitic study's gall: deep wine
pub const parasiticGall:C=.{120,40,80,255};
/// a radiant study's light: pale gold
pub const radiantLight:C=.{255,235,175,255};
/// a convergent study's bloom in its braided ring: lilac
pub const convergentBloom:C=.{200,170,240,255};
/// sun orb (warm amber)
pub const sun:C=.{255,210,120,255};
/// moon orb (cool blue)
pub const moon:C=.{170,190,255,255};
/// sap fill tendril (amber)
pub const sap:C=.{255,190,90,255};
/// research progress tendril (violet)
pub const researchTendril:C=.{200,160,255,255};
/// root-digger progress tendril (warm amber-brown)
pub const digger:C=.{200,170,110,255};
/// a lithophage condensing its crystal (pale lilac)
pub const lith:C=.{190,165,235,255};
