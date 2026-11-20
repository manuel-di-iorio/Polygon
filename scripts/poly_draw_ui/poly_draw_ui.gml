// poly_draw_ui - public API.

// Draws window-level editor hints and tooltips.
function poly_draw_ui() {
  var _ed = __poly_inst();

  if (_ed == undefined) return;

  // Modal dimming is drawn inside ImGui (__poly_imgui_modal_veil): a GameMaker
  // rectangle here would be covered by the ImGui frame. Keep the early return
  // so the drag ghost is not drawn behind a dialog.
  if (__poly_modal_active(_ed)) return;

  if (_ed.active) __poly_draw_drag_ghost(_ed);
  draw_set_color(c_white);
  draw_set_alpha(1);
  draw_set_halign(fa_left);
  draw_set_valign(fa_top);
}
