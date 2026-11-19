// poly_draw_ui - public API.

// Draws window-level editor hints and tooltips.
function poly_draw_ui() {
  var _ed = __poly_inst();

  if (_ed == undefined) return;
  var _modal = _ed.confirm != undefined || _ed.delete_confirm != undefined || _ed.hist_confirm != undefined || _ed.about != undefined || _ed.scene_dlg != undefined;

  if (_modal) {
    // Dialogs are plain ImGui windows (not popups), so ImGui never dims the
    // editor behind them: this veil does it. Keep it light, or the whole
    // editor reads as black instead of just unfocused.
    draw_set_alpha(0.25);
    draw_set_color(c_black);
    draw_rectangle(0, 0, display_get_gui_width(), display_get_gui_height(), false);
    draw_set_color(c_white);
    draw_set_alpha(1);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    return;
  }

  if (_ed.active) __poly_draw_drag_ghost(_ed);
  draw_set_color(c_white);
  draw_set_alpha(1);
  draw_set_halign(fa_left);
  draw_set_valign(fa_top);
}
