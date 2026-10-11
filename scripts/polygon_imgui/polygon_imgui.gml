// polygon_imgui — shell: setup, draw orchestrator, Models window.

// Draws all editor ImGui windows and menus.
function __polygon_imgui_draw(_ed) {
  if (!_ed.active)  return;
  __polygon_imgui_style_once(_ed);
  var _dock_id = ImGui.GetID("PolygonEditorDockspace");
  var _dock_root = ImGui.DockSpaceOverViewport(
    _dock_id,
    0,
    ImGuiDockNodeFlags.PassthruCentralNode
  );
  __polygon_imgui_dock_build(_ed, _dock_root);

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
    __polygon_imgui_modals(_ed);
    _ed.imgui.dock_pos_skip = false;
    return;
  }

  var _reset = _ed.imgui.reset_layout == true;

  if (_reset) {
    _ed.imgui.dock_rebuild = true;
    _ed.imgui.dock_tries = 0;
    __polygon_cube_home(_ed);
  } else if (_resized) {
    __polygon_cube_home(_ed);
  }

  __polygon_imgui_menu(_ed);
  __polygon_imgui_assets(_ed);
  __polygon_imgui_scene_win(_ed);
  __polygon_imgui_inspector(_ed);
  __polygon_imgui_scene_panel(_ed);
  __polygon_imgui_toolbar(_ed);
  __polygon_imgui_fps(_ed);
  __polygon_anim_ui_window(_ed);
  __polygon_imgui_modals(_ed);

  if (_reset || _resized) {
    _ed.imgui.cond = ImGuiCond.FirstUseEver;
    _ed.imgui.reset_layout = false;
  }

  _ed.imgui.dock_pos_skip = false;
}

// Draws whichever modal dialogs are open.
function __polygon_imgui_modals(_ed) {
  if (_ed.confirm != undefined)  __polygon_imgui_confirm(_ed);
  if (variable_struct_exists(_ed, "delete_confirm") && _ed.delete_confirm != undefined)  __polygon_imgui_delete_confirm(_ed);
  if (_ed.about != undefined)  __polygon_imgui_about(_ed);
  if (_ed.scene_dlg != undefined)  __polygon_imgui_scene_dlg(_ed);
}

// Draws Models asset browser window.
function __polygon_imgui_assets(_ed) {
  var _ui = _ed.imgui;

  if (!_ui.win_assets.open)  return;
  var _place = __polygon_imgui_place(_ed).assets;

  if (!__polygon_imgui_dock_fresh(_ed)) {
    ImGui.SetNextWindowPos(_place.x, _place.y, _ui.cond);
    ImGui.SetNextWindowSize(_place.w, _place.h, _ui.cond);
  }

  ImGui.SetNextWindowBgAlpha(1);

  var _flags = __polygon_imgui_panel_flags(_ed, "assets");

  if (__polygon_imgui_lock_move(_ed))  _flags = _flags | ImGuiWindowFlags.NoMove;
  if (!ImGui.Begin("Models", _ui.win_assets, _flags)) {
    __polygon_imgui_panel_save(_ed, "assets");
    ImGui.End();
    return;
  }

  __polygon_imgui_panel_save(_ed, "assets");
  __polygon_imgui_asset_list(_ed);

  if (
    ImGui.IsWindowHovered() &&
    mouse_check_button_pressed(mb_left) &&
    !ImGui.IsAnyItemHovered()
  ) {
    _ed.lib_sel = undefined;
  }

  ImGui.End();
}
