if (!poly_is_active()) {
  draw_set_halign(fa_center);
  draw_set_color(c_white);
  draw_text(display_get_gui_width() * 0.5, 24, "Press F1 for the 3D in-game editor");
  draw_set_halign(fa_left);
}