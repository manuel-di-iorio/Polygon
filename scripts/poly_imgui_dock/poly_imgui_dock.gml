// poly_imgui_dock — dock layout, placement, panel flags.

// ---------------------------------------------------------------------------
// Placement
// ---------------------------------------------------------------------------

// Default panel layout metrics.
function __poly_layout() {
  static _layout = { top: 30, gap: 8, side: 8, left_w: 250, right_w: 300 };
  return _layout;
}

// Computes default panel positions and sizes.
function __poly_imgui_place(_ed) {
  var _lay = __poly_layout();
  var _gw = max(800, _ed.gw);
  var _gh = max(500, _ed.gh);
  var _mh = clamp((_gh - _lay.top - _lay.gap * 2) * 0.20, 142, 172);
  var _ih = max(280, _gh - _mh - _lay.top - _lay.gap - 8);
  var _mx = _lay.left_w + _lay.gap * 2;
  var _rx = _gw - _lay.right_w - 8;
  return {
    hier: { x: 8, y: _lay.top, w: _lay.left_w, h: max(200, _gh - _lay.top - 8) },
    insp: { x: _gw - _lay.right_w - 8, y: _lay.top, w: _lay.right_w, h: _ih },
    assets: { x: _mx, y: _gh - _mh - 8, w: max(200, _gw - _mx - 8), h: _mh },
    scene: { x: _mx, y: _lay.top, w: max(200, _rx - _mx - _lay.gap), h: max(150, _gh - _mh - 8 - _lay.gap - _lay.top) },
  };
}

// ---------------------------------------------------------------------------
// Dock builder
// ---------------------------------------------------------------------------

// Returns true while a fresh dock layout must win over SetNextWindowPos/Size.
function __poly_imgui_dock_fresh(_ed) {
  return variable_struct_exists(_ed.imgui, "dock_pos_skip") && _ed.imgui.dock_pos_skip == true;
}

// Checks if the dock layout still needs (re)building.
// ImGui alone owns the layout: the default dock is built on the very
// first run and on Reset Layout only. Later sessions skip the build and
// trust the runtime ini (reloaded explicitly on the first frame).
// NOTE: never probe the ini file from GML — the sandbox forbids file
// ops outside working_directory. Our own flag lives in polygon_ui.json.
function __poly_dock_needs_build(_ed) {
  var _rebuild = (variable_struct_exists(_ed.imgui, "dock_rebuild") && _ed.imgui.dock_rebuild == true)
    || (variable_struct_exists(_ed.imgui, "reset_layout") && _ed.imgui.reset_layout == true);

  if (!_rebuild) {
    if (variable_struct_exists(_ed.imgui, "dock_init") && _ed.imgui.dock_init == true) {
      _ed.imgui.dock_built = true;
      return false;
    }
  }

  if (variable_struct_exists(_ed.imgui, "dock_built") && _ed.imgui.dock_built == true
  && !(variable_struct_exists(_ed.imgui, "dock_rebuild") && _ed.imgui.dock_rebuild == true)) {
    return false;
  }

  if (!variable_struct_exists(_ed.imgui, "dock_tries")) _ed.imgui.dock_tries = 0;
  if (_ed.imgui.dock_tries > 5) return false;
  _ed.imgui.dock_tries++;
  return true;
}

// Splits a dock node, returning [kept, rest] or undefined.
function __poly_dock_split(_node, _dir, _ratio) {
  var _parts = ImGui.DockBuilderSplitNode(_node, _dir, _ratio);

  if (!is_array(_parts) || array_length(_parts) < 2) return undefined;
  var _rest = array_length(_parts) > 2 ? _parts[2] : _parts[array_length(_parts) - 1];
  return [ _parts[0], _rest ];
}

// Builds initial dock layout: Scene panel centered first, then Hierarchy left
// (full height), Inspector top-right, Models bottom spanning everything
// except Hierarchy. Split order Left, Down, Right gives Models the full
// bottom strip; windows dock in priority order Scene panel, then the panels.
// Runs when no runtime ini exists yet and on Reset Layout. Undocked windows
// keep working floating via their SetNextWindowPos/Size fallbacks.
function __poly_imgui_dock_build(_ed, _root) {
  if (_root == undefined) return;
  if (!__poly_dock_needs_build(_ed)) return;
  var _lay = __poly_layout();
  var _gw = max(800, _ed.gw);
  var _gh = max(500, _ed.gh);
  // Pixel-based defaults like the 1366x768 floating layout: derive split
  // ratios from the reference rects so panels keep their width/height on
  // any window size instead of stretching proportionally.
  var _pl = __poly_imgui_place(_ed);
  var _left_w = _pl.hier.w + 8;
  var _insp_w = _pl.insp.w + 8;
  var _bot_h = _pl.assets.h + 8;
  var _r_left = clamp(_left_w / _gw, 0.08, 0.30);
  var _r_bot = clamp(_bot_h / max(200, _gh - _lay.top), 0.15, 0.50);
  var _r_right = clamp(_insp_w / max(200, _gw - _left_w), 0.10, 0.40);
  ImGui.DockBuilderRemoveNode(_root);
  ImGui.DockBuilderAddNode(_root, ImGuiDockNodeFlags.DockSpace);
  ImGui.DockBuilderSetNodePos(_root, 0, _lay.top);
  ImGui.DockBuilderSetNodeSize(_root, _gw, max(200, _gh - _lay.top));

  var _split_left = __poly_dock_split(_root, ImGuiDir.Left, _r_left);

  if (_split_left == undefined) return;
  var _left = _split_left[0];
  var _split_bot = __poly_dock_split(_split_left[1], ImGuiDir.Down, _r_bot);

  if (_split_bot == undefined) return;
  var _bottom = _split_bot[0];
  var _split_right = __poly_dock_split(_split_bot[1], ImGuiDir.Right, _r_right);

  if (_split_right == undefined) return;
  var _right = _split_right[0];
  var _center = _split_right[1];
  ImGui.DockBuilderDockWindow("Scene", _center);
  ImGui.DockBuilderDockWindow("Inspector", _right);
  ImGui.DockBuilderDockWindow("Models", _bottom);
  ImGui.DockBuilderDockWindow("Hierarchy", _left);
  ImGui.DockBuilderFinish(_root);
  _ed.imgui.dock_built = true;
  _ed.imgui.dock_rebuild = false;
  _ed.imgui.dock_pos_skip = true;
  // First default build done: remember it in our own file and flush the
  // runtime ini (native side, no sandbox involved).
  _ed.imgui.dock_init = true;
  _ed.dock_init = true;
  __poly_ui_save(_ed);
  __poly_rt_ini_save();
}

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

// Editor theme table: [color id, rgb color, alpha].
function __poly_theme() {
  static _theme = [
    [ ImGuiCol.Text, make_colour_rgb(229, 233, 240), 1 ],
    [ ImGuiCol.TextDisabled, make_colour_rgb(120, 130, 150), 1 ],
    [ ImGuiCol.WindowBg, make_colour_rgb(21, 23, 32), 1 ],
    [ ImGuiCol.ChildBg, make_colour_rgb(21, 23, 32), 1 ],
    [ ImGuiCol.PopupBg, make_colour_rgb(25, 28, 38), 1 ],
    [ ImGuiCol.Border, make_colour_rgb(40, 44, 60), 1 ],
    [ ImGuiCol.FrameBg, make_colour_rgb(30, 34, 48), 1 ],
    [ ImGuiCol.FrameBgHovered, make_colour_rgb(36, 40, 56), 1 ],
    [ ImGuiCol.FrameBgActive, make_colour_rgb(45, 60, 95), 1 ],
    [ ImGuiCol.TitleBg, make_colour_rgb(21, 23, 32), 1 ],
    [ ImGuiCol.TitleBgActive, make_colour_rgb(33, 36, 48), 1 ],
    [ ImGuiCol.MenuBarBg, make_colour_rgb(21, 23, 32), 1 ],
    [ ImGuiCol.ScrollbarBg, make_colour_rgb(21, 23, 32), 1 ],
    [ ImGuiCol.ScrollbarGrab, make_colour_rgb(50, 58, 80), 1 ],
    [ ImGuiCol.ScrollbarGrabHovered, make_colour_rgb(68, 78, 106), 1 ],
    [ ImGuiCol.CheckMark, make_colour_rgb(96, 165, 250), 1 ],
    [ ImGuiCol.Button, make_colour_rgb(36, 42, 60), 1 ],
    [ ImGuiCol.ButtonHovered, make_colour_rgb(48, 56, 80), 1 ],
    [ ImGuiCol.ButtonActive, make_colour_rgb(37, 99, 235), 1 ],
    [ ImGuiCol.Header, make_colour_rgb(37, 99, 235), 1 ],
    [ ImGuiCol.HeaderHovered, make_colour_rgb(45, 60, 95), 1 ],
    [ ImGuiCol.HeaderActive, make_colour_rgb(37, 99, 235), 1 ],
    [ ImGuiCol.Separator, make_colour_rgb(40, 44, 60), 1 ],
    [ ImGuiCol.DockingEmptyBg, c_black, 0 ],
  ];
  return _theme;
}

// Applies editor ImGui theme once.
function __poly_imgui_style_once(_ed) {
  if (_ed.imgui.style_init) return;
  _ed.imgui.style_init = true;
  var _theme = __poly_theme();

  for (var _i = 0, _n = array_length(_theme); _i < _n; _i++) __poly_imgui_style_color(_theme[_i][0], _theme[_i][1], _theme[_i][2]);
}

// ---------------------------------------------------------------------------
// Panel move flags
// ---------------------------------------------------------------------------

// Tests if the mouse is over a panel body (below the titlebar).
function __poly_panel_body_hit(_r, _mx, _my) {
  if (!is_struct(_r)) return false;
  if (!is_real(_mx) || !is_real(_my) || !is_real(_r.x) || !is_real(_r.y) || !is_real(_r.w) || !is_real(_r.h)) return false;
  if (_mx < _r.x || _mx > _r.x + _r.w || _my < _r.y || _my > _r.y + _r.h) return false;
  var _title_h = is_real(_r.t) && _r.t > 0 ? _r.t : 19;
  return _my > _r.y + _title_h;
}

// Returns NoMove when mouse is over panel body, None on titlebar/outside.
// Latches flags while left button is held to avoid toggling mid-drag.
function __poly_imgui_panel_flags(_ed, _key) {
  var _none = ImGuiWindowFlags.None;
  var _nomove = ImGuiWindowFlags.NoMove;

  if (!variable_struct_exists(_ed.imgui, "_winrect")) {
    _ed.imgui._winrect = {};
  }

  if (!variable_struct_exists(_ed.imgui, "_winflags")) {
    _ed.imgui._winflags = {};
  }

  if (ImGui.IsMouseDown(0)) {
    var _latched = _ed.imgui._winflags[$ _key];
    return is_real(_latched) ? _latched : _none;
  }

  var _flags = _none;

  if (__poly_panel_body_hit(_ed.imgui._winrect[$ _key], ImGui.GetMousePosX(), ImGui.GetMousePosY())) _flags = _nomove;
  _ed.imgui._winflags[$ _key] = _flags;
  return _flags;
}

// Caches current window rect for panel move detection. Call inside Begin/End.
function __poly_imgui_panel_save(_ed, _key) {
  var _x = ImGui.GetWindowX();
  var _y = ImGui.GetWindowY();
  var _w = ImGui.GetWindowWidth();
  var _h = ImGui.GetWindowHeight();

  if (!is_real(_x) || !is_real(_y) || !is_real(_w) || !is_real(_h)) return;
  var _title_h = 19;
  var _fh = ImGui.GetFrameHeight();

  if (is_real(_fh) && _fh > 0) _title_h = _fh;

  if (!variable_struct_exists(_ed.imgui, "_winrect")) {
    _ed.imgui._winrect = {};
  }

  _ed.imgui._winrect[$ _key] = { x: _x, y: _y, w: _w, h: _h, t: _title_h };
}

// Returns the runtime imgui.ini path (next to the build exe).
function __poly_rt_ini_path() {
  var _dir = program_directory;
  if (!is_string(_dir) || _dir == "") return "";
  var _sep = "\\";
  if (string_char_at(_dir, string_length(_dir)) == "\\" || string_char_at(_dir, string_length(_dir)) == "/") _sep = "";
  return _dir + _sep + "imgui.ini";
}

// Reloads the runtime ini through the binding (native side, the GML
// sandbox is not involved).
function __poly_rt_ini_load() {
  var _fn = ImGui[$ "LoadIniSettingsFromDisk"];
  if (_fn == undefined) return;
  method(ImGui, _fn)();
}

// Flushes the runtime ini through the binding.
function __poly_rt_ini_save() {
  var _fn = ImGui[$ "SaveIniSettingsToDisk"];
  if (_fn == undefined) return;
  method(ImGui, _fn)();
}
