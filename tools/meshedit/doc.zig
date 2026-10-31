//! a mesh as the editor keeps it: the game's sculpt format (sculpt_doc.zig),
//! and what the editor's hands are dragging.
/// the game, reached through its import hub
const ps=@import("parasymi");
/// one form of the sculpt
pub const Piece=ps.sculptDoc.Piece;
/// what a mesh's text holds: its cells, bones and forms
pub const Doc=ps.sculptDoc.Doc;
/// a tube's centre line
pub const arc=ps.sculptDoc.arc;
/// what is being dragged: nothing, a value, or the gizmo
pub const Drag=enum{
  /// nothing held
  none,
  /// the selected value, changing as the mouse moves
  value,
  /// one of the selected form's gizmo handles
  gizmo,
};
