// poly_imgui_chrome — toolbar, menu, dialogs, UI persistence.

// ---------------------------------------------------------------------------
// Toolbar
// ---------------------------------------------------------------------------

// Gizmo tool buttons table: [id, tip, tool, fallback, sprite, w, h].
function __poly_toolbar_tools() {
  static _tools = [
    [ "##tb_view", "View (Q)", PolygonEditorTool.View, "V", "sprPolygonEditorIconHand", 12, 16 ],
    [ "##tb_move", "Move (W)", PolygonEditorTool.Translate, "M", "sprPolygonEditorIconMove", 15, 15 ],
    [ "##tb_rotate", "Rotate (E)", PolygonEditorTool.Rotate, "R", "sprPolygonEditorIconRotate", 15, 15 ],
    [ "##tb_scale", "Scale (R)", PolygonEditorTool.Scale, "S", "sprPolygonEditorIconScale", 15, 15 ],
  ];
  return _tools;
}

// Draws a toolbar separator.
function __poly_toolbar_sep() {
  ImGui.SameLine();
  ImGui.TextDisabled("|");
  ImGui.SameLine();
}

// Sets the shaded/unlit draw mode and refreshes previews.
function __poly_draw_mode(_ed, _unlit) {
  _ed.show_unlit = _unlit;
  _ed.show_shadows = !_unlit;
  __poly_unlit_apply(_ed);
  __poly_shadowpreview_apply(_ed);
}

// Draws gizmo tools and snap options toolbar.
function __poly_imgui_toolbar(_ed) {
  if (!_ed.imgui.win_toolbar.open) return;
  ImGui.SetNextWindowPos(300, 34, _ed.imgui.cond);
  var _flags =
    ImGuiWindowFlags.NoTitleBar |
  ImGuiWindowFlags.NoResize |
  ImGuiWindowFlags.AlwaysAutoResize;

  if (!ImGui.Begin("##toolbar", _ed.imgui.win_toolbar, _flags)) {
    ImGui.End();
    return;
  }

  var _tools = __poly_toolbar_tools();

  for (var _i = 0, _n = array_length(_tools); _i < _n; _i++) {
    var _t = _tools[_i];

    if (_i > 0) ImGui.SameLine();
    if (__poly_imgui_icon_btn(_t[0], _t[1], _ed.giz.tool == _t[2], _t[3], _t[4], _t[5], _t[6])) _ed.giz.tool = _t[2];
  }

  __poly_toolbar_sep();
  var _pmode = _ed.giz.pivot_mode == 1 ? "Center" : "Pivot";

  if (__poly_imgui_tool_btn("Gizmo pivot at bounds center (" + _pmode + ", click to switch) [Z]", _pmode, false, 22)) __poly_toggle_pivot(_ed);
  ImGui.SameLine();
  var _orient = _ed.giz.orient == 1 ? "Local" : "World";

  if (__poly_imgui_tool_btn("Gizmo axes space (" + _orient + ", click to switch) [X]", _orient, false, 22)) __poly_toggle_orient(_ed);

  __poly_toolbar_sep();

  if (__poly_imgui_icon_btn("##tb_snap", "Snap to increments (on/off) [\\]", _ed.snap_on, "Sn", "sprPolygonEditorIconSnap", 15, 15)) _ed.snap_on = !_ed.snap_on;
  ImGui.SameLine();

  if (__poly_imgui_icon_btn("##tb_grid", "Show grid (on/off)", _ed.show_grid, "Gr", "sprPolygonEditorIconGrid", 15, 15)) {
    _ed.show_grid = !_ed.show_grid;
    // Apply now: grid_ensure also runs in step, but after the toggle the
    // flipped view key would consume the re-render on the stale scene.
    __poly_grid_ensure(_ed);
  }

  ImGui.SameLine();
  if (__poly_imgui_icon_btn("##tb_colliders", "Show collider debug (on/off) [P]", _ed.show_colliders == true, "Co", "", 15, 15)) {
    _ed.show_colliders = !_ed.show_colliders;
    if (_ed.show_colliders) __poly_physics_debug_rebuild(_ed); else __poly_physics_debug_destroy(_ed);
    _ed.view_dirty = true;
  }

  ImGui.SameLine();
  __poly_imgui_grid_snap(_ed);
  __poly_toolbar_sep();

  if (__poly_imgui_icon_btn("##tb_unlit", "Unlit Draw Mode", _ed.show_unlit == true, "Un", "sprPolygonEditorIconUnlit", 15, 15)) __poly_draw_mode(_ed, true);
  ImGui.SameLine();

  if (__poly_imgui_icon_btn("##tb_shaded", "Shaded Draw Mode", _ed.show_unlit != true, "Sh", "sprPolygonEditorIconShaded", 15, 15)) __poly_draw_mode(_ed, false);
  __poly_toolbar_sep();

  if (__poly_imgui_icon_btn("##tb_home", "Reset camera to the initial view", false, "Hm", "sprPolygonEditorIconCenter", 15, 15)) __poly_cam_home(_ed, true);
  ImGui.SameLine();
  ImGui.SetNextItemWidth(86);
  var _aa = __poly_aa_mode(_ed);
  var _aa_label = _aa == "off" ? "AA Off" : _aa == "fxaa" ? "FXAA" : _aa == "smaa" ? "SMAA" : "SSAA";

  if (!ImGui.BeginCombo("##aa_mode", _aa_label)) {
    if (ImGui.IsItemHovered()) ImGui.SetTooltip("Viewport antialiasing");
  } else {
    if (ImGui.Selectable("AA Off", _aa == "off", 0, 0, 0)) __poly_aa_set(_ed, "off");
    if (ImGui.Selectable("FXAA", _aa == "fxaa", 0, 0, 0)) __poly_aa_set(_ed, "fxaa");
    if (ImGui.Selectable("SMAA", _aa == "smaa", 0, 0, 0)) __poly_aa_set(_ed, "smaa");
    if (ImGui.Selectable("SSAA", _aa == "ssaa", 0, 0, 0)) __poly_aa_set(_ed, "ssaa");
    ImGui.EndCombo();
  }

  ImGui.SameLine();
  __poly_vis_defaults(_ed);

  if (__poly_imgui_icon_btn("##tb_vis", "Visibility: hidden objects, skybox, outline", false, "Ey", "sprPolygonEditorIconEye", 15, 15)) ImGui.OpenPopup("##visoptions");

  if (ImGui.BeginPopup("##visoptions")) {
    var _vh = ImGui.Checkbox("Hidden objects", _ed.show_hidden);

    if (ImGui.IsItemHovered()) ImGui.SetTooltip("Click to toggle hidden objects visibility");

    if (_vh != _ed.show_hidden) {
      _ed.show_hidden = _vh;
      __poly_hidden_apply_all(_ed);
    }

    var _vs = ImGui.Checkbox("Skybox", _ed.vis_sky);

    if (ImGui.IsItemHovered()) ImGui.SetTooltip("Click to toggle skybox visibility");

    if (_vs != _ed.vis_sky) {
      _ed.vis_sky = _vs;
      __poly_sky_set_visible(_ed, _vs);
    }

    var _vo = ImGui.Checkbox("Selection outline", _ed.vis_outline);

    if (ImGui.IsItemHovered()) ImGui.SetTooltip("Click to toggle selection outline");

    if (_vo != _ed.vis_outline) {
      _ed.vis_outline = _vo;
      _ed.view_dirty = true;
    }

    ImGui.EndPopup();
  }

  ImGui.End();
}

// ---------------------------------------------------------------------------
// Grid and snap popup
// ---------------------------------------------------------------------------

// Ensures snap settings exist with defaults.
function __poly_snap_defaults(_ed) {
  if (!variable_struct_exists(_ed, "grid_step") || !is_real(_ed.grid_step)) _ed.grid_step = 1;
  if (!variable_struct_exists(_ed, "snap_to_grid")) _ed.snap_to_grid = true;
  if (!variable_struct_exists(_ed, "snap_pos") || !is_real(_ed.snap_pos)) _ed.snap_pos = 0.5;
  if (!variable_struct_exists(_ed, "snap_x")) _ed.snap_x = true;
  if (!variable_struct_exists(_ed, "snap_y")) _ed.snap_y = true;
  if (!variable_struct_exists(_ed, "snap_z")) _ed.snap_z = true;
}

// Draws the grid section of the snap popup.
function __poly_snap_grid_sec(_ed) {
  ImGui.Separator();
  ImGui.TextDisabled("GRID");
  ImGui.SetNextItemWidth(150);
  _ed.snap_to_grid = ImGui.Checkbox("Snap to Grid", _ed.snap_to_grid == true);
  ImGui.TextDisabled("Grid size");
  ImGui.SetNextItemWidth(120);
  var _custom = __poly_imgui_dragfloat("##gridsnap_custom", _ed.grid_step, 0.01);
  __poly_grid_set_step(_ed, clamp(_custom, 0.1, 8));
}

// Draws one snap-axis toggle.
function __poly_snap_axis_btn(_ed, _tip, _label, _field) {
  if (__poly_imgui_tool_btn(_tip, _label, _ed[$ _field], 28, 34)) _ed[$ _field] = !_ed[$ _field];
}

// Draws the position section of the snap popup.
function __poly_snap_pos_sec(_ed) {
  ImGui.Separator();
  ImGui.TextDisabled("POSITION SNAP");
  ImGui.TextDisabled("Snap axes");
  __poly_snap_axis_btn(_ed, "Snap translation on X", "X", "snap_x");
  ImGui.SameLine();
  __poly_snap_axis_btn(_ed, "Snap translation on Y", "Y", "snap_y");
  ImGui.SameLine();
  __poly_snap_axis_btn(_ed, "Snap translation on Z", "Z", "snap_z");

  if (_ed.snap_to_grid != true) {
    ImGui.TextDisabled("Move step (m)");
    var _presets = [ 0.1, 0.25, 0.5, 1, 2 ];

    for (var _j = 0, _n = array_length(_presets); _j < _n; _j++) {
      var _step = _presets[_j];
      var _sel = abs(_ed.snap_pos - _step) < 0.0001;

      if (ImGui.Selectable(string(_step), _sel)) _ed.snap_pos = _step;
      if (_sel) ImGui.SetItemDefaultFocus();
    }

    ImGui.SetNextItemWidth(120);
    _ed.snap_pos = max(0.01, __poly_imgui_dragfloat("##gridsnap_move", _ed.snap_pos, 0.005));
  }
}

// Draws the rotation section of the snap popup.
// Edits grid size and snap increments in one place.
function __poly_imgui_grid_snap(_ed) {
  __poly_snap_defaults(_ed);
  ImGui.SetNextItemWidth(64);

  if (!ImGui.BeginCombo("##gridsnap", string(_ed.grid_step) + " m")) {
    if (ImGui.IsItemHovered()) ImGui.SetTooltip("Grid and snap settings");
    return;
  }

  __poly_snap_grid_sec(_ed);
  __poly_snap_pos_sec(_ed);
  ImGui.Separator();
  ImGui.TextDisabled("ROTATION SNAP");
  ImGui.SetNextItemWidth(120);
  _ed.snap_rot = max(0.5, __poly_imgui_dragfloat("##gridsnap_rot", _ed.snap_rot, 0.1));
  ImGui.EndCombo();
}

// ---------------------------------------------------------------------------
// UI persistence
// ---------------------------------------------------------------------------

// UI settings file name.
function __poly_ui_file() {
  return "polygon_ui.json";
}

// Saves view cube offset and first-build flag to file.
function __poly_ui_save(_ed) {
  if (_ed == undefined) return;
  var _dock_init = (is_struct(_ed.imgui) && variable_struct_exists(_ed.imgui, "dock_init") && _ed.imgui.dock_init == true)
    || (variable_struct_exists(_ed, "dock_init") && _ed.dock_init == true);
  __poly_write_text_file(
    working_directory + __poly_ui_file(),
    json_stringify({ cube_off: _ed.cube_off, dock_init: _dock_init }, true)
  );
}

// Loads view cube offset and first-build flag from file.
function __poly_ui_load(_ed) {
  if (_ed == undefined) return;
  var _path = working_directory + __poly_ui_file();
  // One-shot migration from the old file name.
  if (!file_exists(_path)) {
    var _legacy = working_directory + "poly_ui.json";
    if (file_exists(_legacy)) _path = _legacy;
  }

  if (!file_exists(_path)) return;
  var _json = __poly_read_text_file(_path);

  if (_json == "") return;
  var _data = json_parse(_json);

  if (!is_struct(_data)) return;

  if (variable_struct_exists(_data, "dock_init") && _data.dock_init == true) {
    _ed.dock_init = true;
    if (is_struct(_ed.imgui)) _ed.imgui.dock_init = true;
  }

  if (!variable_struct_exists(_data, "cube_off")) return;
  var _off = _data.cube_off;

  if (!is_array(_off) || array_length(_off) < 2 || !is_real(_off[0]) || !is_real(_off[1])) return;
  // Legacy offsets from the floating layout reset to home.
  if ((_off[0] == 85 || _off[0] == 375) && _off[1] == 100) {
    __poly_cube_home(_ed);
    return;
  }

  _ed.cube_off = [ clamp(_off[0], 0, 10000), clamp(_off[1], 0, 10000) ];
}

// ---------------------------------------------------------------------------
// Menu bar
// ---------------------------------------------------------------------------

// Draws the File menu, returning pending actions.
function __poly_menu_file(_ed) {
  var _pending = { do_new: false, do_load: false, do_saveas: false, do_close: false };

  if (!ImGui.BeginMenu("File")) return _pending;
  ImGui.TextDisabled(_ed.scene_file != "" ? __poly_base_name(_ed.scene_file) : "(unsaved scene)");

  if (ImGui.MenuItem("New", __poly_bind_label(_ed.cfg.keys, "new_scene"))) _pending.do_new = true;
  if (ImGui.MenuItem("Save", __poly_bind_label(_ed.cfg.keys, "save"))) __poly_save_or_ask(_ed);
  if (ImGui.MenuItem("Save As...")) _pending.do_saveas = true;
  if (ImGui.MenuItem("Load", __poly_bind_label(_ed.cfg.keys, "load"))) _pending.do_load = true;
  ImGui.Separator();

  if (ImGui.MenuItem("Close Editor", __poly_bind_label(_ed.cfg.keys, "close"))) _pending.do_close = true;
  ImGui.EndMenu();
  return _pending;
}

// Draws the Create menu.
function __poly_menu_create(_ed) {
  if (!ImGui.BeginMenu("Create")) return;

  if (__poly_light_count(_ed) >= 8) {
    ImGui.TextDisabled("Lights (8 max reached)");
  } else {
    if (ImGui.MenuItem("Directional Light")) __poly_create_light(_ed, "directional");
    if (ImGui.MenuItem("Point Light")) __poly_create_light(_ed, "point");
  }

  ImGui.Separator();

  if (ImGui.MenuItem("Perspective Camera")) __poly_create_camera(_ed, "perspective");
  if (ImGui.MenuItem("Ortho Camera")) __poly_create_camera(_ed, "ortho");
  ImGui.Separator();

  if (__poly_env_node(_ed) == undefined) {
    if (ImGui.MenuItem("Environment")) __poly_create_env(_ed);
  } else {
    ImGui.TextDisabled("Environment (already in scene)");
  }

  ImGui.EndMenu();
}

// Toggles one window-visibility menu entry.
function __poly_menu_win(_label, _win) {
  if (ImGui.MenuItem(_win.open ? "[x] " + _label : "[  ] " + _label)) _win.open = !_win.open;
}

// Draws the View menu.
function __poly_menu_view(_ed) {
  var _ui = _ed.imgui;

  if (!ImGui.BeginMenu("View")) return;
  __poly_menu_win("Models", _ui.win_assets);
  __poly_menu_win("Hierarchy", _ui.win_hier);
  __poly_menu_win("Inspector", _ui.win_insp);
  __poly_menu_win("Toolbar", _ui.win_toolbar);
  __poly_menu_win("View Cube", _ui.win_cube);
  __poly_menu_win("Scene", _ui.win_scene);

  if (ImGui.MenuItem(_ed.show_grid ? "[x] Grid" : "[  ] Grid")) {
    _ed.show_grid = !_ed.show_grid;
    // Apply now: see toolbar toggle above.
    __poly_grid_ensure(_ed);
  }

  ImGui.Separator();

  if (ImGui.MenuItem("Reset Layout")) {
    _ui.reset_layout = true;
    __poly_cube_home(_ed);
    _ui.win_cube.open = true;
    __poly_ui_save(_ed);
  }

  ImGui.EndMenu();
}

// Draws the non-clickable brand label at the start of the menu bar.
function __poly_menu_brand() {
  static _logo = -2;

  if (_logo == -2) _logo = asset_get_index("sprPolygonEditorIconLogo");
  ImGui.Dummy(1, 0);

  if (_logo != -1) {
    // Fixed logo size: it no longer follows FramePadding, so the bar
    // padding stays visible as margin around it (tweak _marg/_max_h).
    var _marg = 3;
    var _max_h = 25;
    var _fh = ImGui.GetFrameHeight();
    var _h = min(_max_h, max(1, _fh - _marg * 2));
    var _w = _h * sprite_get_width(_logo) / max(1, sprite_get_height(_logo));
    ImGui.SetCursorScreenPos(ImGui.GetCursorScreenPosX(), ImGui.GetCursorScreenPosY() + max(0, (_fh - _h) * 0.5));
    ImGui.Image(_logo, 0, c_white, 1, _w, _h);
  }

  ImGui.AlignTextToFramePadding();
  ImGui.PushStyleColor(ImGuiCol.Text, make_colour_rgb(147, 197, 253), 1);
  ImGui.SetWindowFontScale(1.12);
  ImGui.Text("Polygon");
  ImGui.SetWindowFontScale(1);
  __poly_imgui_pop(1);
  ImGui.Dummy(-3, 0);
  ImGui.TextDisabled("|");
}

// Draws the Help menu.
function __poly_menu_help(_ed) {
  if (!ImGui.BeginMenu("Help")) return;
  if (ImGui.MenuItem("Report a Bug/Feature Request")) url_open("https://github.com/manuel-di-iorio/Polygon/issues");

  if (ImGui.MenuItem("About")) {
    _ed.about = { open: true };
  }

  ImGui.EndMenu();
}

// Executes pending menu bar actions.
function __poly_menu_do(_ed, _file) {
  if (_file.do_new) __poly_confirm_ask(_ed, "new");
  if (_file.do_load) __poly_confirm_ask(_ed, "load");
  if (_file.do_saveas) __poly_scene_dlg_open(_ed, "save", undefined);
  if (_file.do_close) __poly_confirm_ask(_ed, "close");
}

// Tries to pad the menu bar via FramePadding (Dear ImGui StyleVar 11).
// Returns true when active: caller must pop with __poly_menu_pad_pop().
// Pops a menu bar padding override.
function __poly_menu_pad_pop() {
  ImGui.PopStyleVar();
}

// Draws the AI bridge toggle + link status at the right end of the menu bar.
function __poly_menu_ai(_ed) {
  var _ai = __poly_ai_state(_ed);
  var _w = ImGui.GetWindowWidth();
  var _st = __poly_ai_link(_ed);

  if (_st != 0) {
    var _txt = _st == 3 ? "Connected" : (_st == 2 ? "Reconnecting.." : "Connecting to AI..");
    ImGui.SameLine(max(0, _w - 60 - 8 - ImGui.CalcTextWidth(_txt)));

    if (_st == 3) {
      ImGui.PushStyleColor(ImGuiCol.Text, c_green, 1);
      ImGui.Text(_txt);
      __poly_imgui_pop(1);
    } else {
      ImGui.Text(_txt);
    }
  } else if (_ai.notice != "" && current_time < _ai.notice_until) {
    ImGui.SameLine(max(0, _w - 60 - 8 - ImGui.CalcTextWidth(_ai.notice)));
    ImGui.PushStyleColor(ImGuiCol.Text, c_red, 1);
    ImGui.Text(_ai.notice);
    __poly_imgui_pop(1);
  }

  ImGui.SameLine(max(0, _w - 60));

  if (__poly_imgui_tool_btn("MCP bridge: connect/disconnect the relay", "MCP", _ai.on, 0, 0)) __poly_ai_enable(!_ai.on);
}

// Draws main menu bar with actions.
function __poly_imgui_menu(_ed) {
  ImGui.PushStyleVar(11, 8, 12);
  var _pad = true;

  if (!ImGui.BeginMainMenuBar()) {
    if (_pad) __poly_menu_pad_pop();
    return;
  }

  ImGui.SetNextWindowBgAlpha(1);
  __poly_menu_brand();
  var _file = __poly_menu_file(_ed);
  __poly_menu_create(_ed);
  __poly_menu_view(_ed);
  __poly_menu_help(_ed);
  __poly_menu_ai(_ed);
  ImGui.EndMainMenuBar();

  if (_pad) __poly_menu_pad_pop();
  __poly_menu_do(_ed, _file);
}
