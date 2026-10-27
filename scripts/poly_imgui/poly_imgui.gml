// poly_imgui - shell: setup, draw orchestrator, Models window.

// Draws all editor ImGui windows and menus.
function __poly_imgui_draw(_ed) {
  if (!_ed.active) return;
  // First frame: reload the runtime ini through the binding (native side,
  // sandbox-proof). Our own build is skipped on later sessions, so whatever
  // the runtime restores is left untouched.
  if (!variable_struct_exists(_ed.imgui, "rt_ini_tried")) {
    _ed.imgui.rt_ini_tried = true;
    if (variable_struct_exists(_ed.imgui, "dock_init") && _ed.imgui.dock_init == true) __poly_rt_ini_load();
  }

  __poly_imgui_style_once(_ed);
  var _dock_id = ImGui.GetID("PolygonEditorDockspace");
  var _dock_root = ImGui.DockSpaceOverViewport(
    _dock_id,
    0,
    ImGuiDockNodeFlags.PassthruCentralNode
  );
  // (Re)builds the default dock unless the runtime ini was just loaded.
  __poly_imgui_dock_build(_ed, _dock_root);

  if (!variable_struct_exists(_ed.imgui, "_pw")) {
    _ed.imgui._pw = 0;
    _ed.imgui._ph = 0;
  }

  var _resized = _ed.imgui._pw != _ed.gw || _ed.imgui._ph != _ed.gh;
  _ed.imgui._pw = _ed.gw;
  _ed.imgui._ph = _ed.gh;
  var _modal_open =
    _ed.confirm != undefined ||
    _ed.delete_confirm != undefined ||
    _ed.about != undefined ||
    _ed.scene_dlg != undefined;

  if (_modal_open) {
    __poly_imgui_modals(_ed);
    _ed.imgui.dock_pos_skip = false;
    return;
  }

  var _reset = _ed.imgui.reset_layout == true;

  if (_reset) {
    _ed.imgui.dock_rebuild = true;
    _ed.imgui.dock_tries = 0;
    __poly_cube_home(_ed);
  } else if (_resized) {
    __poly_cube_home(_ed);
  }

  __poly_imgui_menu(_ed);
  __poly_imgui_assets(_ed);
  __poly_imgui_scene_win(_ed);
  __poly_imgui_inspector(_ed);
  __poly_imgui_scene_panel(_ed);
  __poly_imgui_toolbar(_ed);
  __poly_imgui_console_win(_ed);
  __poly_imgui_fps(_ed);
  __poly_anim_ui_window(_ed);
  __poly_imgui_modals(_ed);

  if (_reset || _resized) {
    _ed.imgui.cond = ImGuiCond.FirstUseEver;
    _ed.imgui.reset_layout = false;
  }

  _ed.imgui.dock_pos_skip = false;
}

// Draws whichever modal dialogs are open.
function __poly_imgui_modals(_ed) {
  if (_ed.confirm != undefined) __poly_imgui_confirm(_ed);
  if (variable_struct_exists(_ed, "delete_confirm") && _ed.delete_confirm != undefined) __poly_imgui_delete_confirm(_ed);
  if (_ed.about != undefined) __poly_imgui_about(_ed);
  if (_ed.scene_dlg != undefined) __poly_imgui_scene_dlg(_ed);
}

// Draws Models asset browser window.
function __poly_imgui_assets(_ed) {
  var _ui = _ed.imgui;

  if (!_ui.win_assets.open) return;
  var _place = __poly_imgui_place(_ed).assets;

  if (!__poly_imgui_dock_fresh(_ed)) {
    ImGui.SetNextWindowPos(_place.x, _place.y, _ui.cond);
    ImGui.SetNextWindowSize(_place.w, _place.h, _ui.cond);
  }

  ImGui.SetNextWindowBgAlpha(1);

  var _flags = __poly_imgui_panel_flags(_ed, "assets");

  if (__poly_imgui_lock_move(_ed)) _flags = _flags | ImGuiWindowFlags.NoMove;

  if (!ImGui.Begin("Models", _ui.win_assets, _flags)) {
    __poly_imgui_panel_save(_ed, "assets");
    ImGui.End();
    return;
  }

  __poly_imgui_panel_save(_ed, "assets");
  _ui.models_focused = __poly_imgui_safe("IsWindowFocused", false);
  __poly_imgui_asset_list(_ed);

  if (
    ImGui.IsWindowHovered() &&
    mouse_check_button_pressed(mb_left) &&
    !ImGui.IsAnyItemHovered()
    ) {
    _ed.lib_sel = undefined;
  }

  ImGui.End();
}
