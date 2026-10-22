// poly_imgui_inspector — shell: Inspector window dispatcher.

// ---------------------------------------------------------------------------
// Material/texture sub-inspectors
// ---------------------------------------------------------------------------

// Closes the material (and texture) inspector state.
function __poly_mat_inspector_close(_ed) {
  _ed.mat_inspector = undefined;
  _ed.mat_inspect_key = undefined;
  _ed.mat_inspector_sel = undefined;
  _ed.mat_inspector_lib_sel = undefined;
  _ed.mat_inspector_back = undefined;
  _ed.tex_inspector = undefined;
}

// Checks if the open material inspector no longer matches the selection.
function __poly_mat_inspector_stale(_ed) {
  if (!variable_struct_exists(_ed, "mat_inspector_sel") || !is_array(_ed.mat_inspector_sel)) return true;
  if (!variable_struct_exists(_ed, "mat_inspector_lib_sel")) return true;
  if (array_length(_ed.mat_inspector_sel) != array_length(_ed.sel)) return true;
  if (_ed.mat_inspector_lib_sel != _ed.lib_sel) return true;
  for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) if (!__poly_node_same(_ed.mat_inspector_sel[_i], _ed.sel[_i])) return true;
  return false;
}

// Draws the texture sub-inspector (with back navigation).
function __poly_imgui_tex_view(_ed) {
  if (ImGui.Button("< Back to material")) _ed.tex_inspector = undefined;
  ImGui.Spacing();
  __poly_imgui_tex_inspector(_ed);
  ImGui.End();
}

// Draws the material sub-inspector (with back navigation).
function __poly_imgui_mat_view(_ed) {
  // Back is only offered when the material was opened from an
  // object/prefab inspector; generic entry points hide it.
  if (_ed[$ "mat_inspector_back"] == true) {
    if (ImGui.Button("< Back to object")) __poly_mat_inspector_close(_ed);
    ImGui.Spacing();
  }

  __poly_imgui_mat_inspector(_ed);
  ImGui.End();
}

// ---------------------------------------------------------------------------
// Titles and headers
// ---------------------------------------------------------------------------

// Builds the inspector title and type label for a selection.
function __poly_inspector_titles(_ed, _n, _skind, _stype) {
  var _title = _n == 1 ? __poly_node_display(_ed, _ed.sel[0]) : string(_n) + " objects";
  var _type = _n == 1 ? "Object" : "Objects";

  if (_skind == "instance") {
    _type = "Instance";
  } else if (_skind == "camera") {
    _type = "Camera";
  } else if (_skind == "environment") {
    _type = "Environment";
  } else if (_skind == "light") {
    _type = is_string(_stype) ? "Light (" + _stype + ")" : "Light";
  }

  return { title: _title, type: _type };
}

// Finds the library thumbnail for a selected asset node.
function __poly_inspector_asset_thumb(_ed, _node) {
  var _en = __poly_registry_find(_ed, _node);

  if (_en == undefined || !is_string(_en.asset) || !is_array(_ed.assets)) return -1;
  var _entry = __poly_asset_get(_ed, _en.asset);

  if (_entry != undefined && variable_struct_exists(_entry, "thumb") && sprite_exists(_entry.thumb)) return _entry.thumb;
  return -1;
}

// Draws the instance header (thumbnail + prefab row).
// Returns true when the prefab row consumed the inspector.
function __poly_imgui_instance_head(_ed, _node, _title, _type) {
  var _thumb = __poly_inspector_asset_thumb(_ed, _node);

  if (_thumb != -1) __poly_imgui_inspector_asset_header(_title, _type, _thumb, 96);
  return __poly_imgui_prefab_row(_ed, _node);
}

// Draws the plain title block for non-asset selections.
function __poly_imgui_plain_head(_title, _type) {
  var _short = __poly_short_name(_title);
  var _rx = ImGui.GetCursorScreenPosX();
  var _ry = ImGui.GetCursorScreenPosY();
  var _rw = ImGui.GetContentRegionAvailX();
  ImGui.Text(_short);
  var _rh = ImGui.GetCursorScreenPosY() - _ry;

  if (_rh <= 0) _rh = ImGui.GetTextLineHeight();
  ImGui.SetCursorScreenPos(_rx, _ry);
  ImGui.InvisibleButton("##tip_title", max(0, _rw), max(1, _rh));
  var _hov = ImGui.IsItemHovered();
  ImGui.SetCursorScreenPos(_rx, _ry + _rh);
  __poly_imgui_tip_delayed("insp|title|" + string(_title), string(_title), _hov);
  ImGui.TextDisabled(_type);
  ImGui.Spacing();
  ImGui.Separator();
  ImGui.Spacing();
}

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

// Computes transform axis visibility for a selection.
function __poly_axis_visibility(_n, _skind, _stype) {
  var _show = [ true, true, true ];

  if (_n == 1 && _skind != undefined && _skind != "instance") {
    if (_skind == "environment") {
      _show = [ false, false, false ];
    } else if (_skind == "camera") {
      _show = [ true, true, false ];
    } else if (_skind == "light") {
      _show = [ true, _stype != "point", false ];
    }
  }

  return _show;
}

// Draws the Transform section.
function __poly_imgui_transform_sec(_ed, _show) {
  if (!_show[0] && !_show[1] && !_show[2]) return;
  ImGui.Spacing();
  __poly_imgui_sec_open();

  if (!ImGui.CollapsingHeader("Transform")) return;
  if (_show[0]) __poly_imgui_axis_row(_ed, 0, "Position");
  if (_show[1]) __poly_imgui_axis_row(_ed, 1, "Rotation");
  if (_show[2]) __poly_imgui_axis_row(_ed, 2, "Scale");
}

// Draws one collapsing section with a body function.

// Draws light/camera/environment sections for a single selection.
function __poly_imgui_prop_secs(_ed, _node, _en, _skind) {
  if (_skind == "light") {
    ImGui.Spacing();
    __poly_imgui_sec_open();

    if (ImGui.CollapsingHeader("Light")) __poly_imgui_light_sec(_ed, _node, _en);

    if (_en.data.type == "directional") {
      ImGui.Spacing();
      __poly_imgui_sec_open();

      if (ImGui.CollapsingHeader("Shadows")) __poly_imgui_light_shadow_sec(_ed, _node, _en);
    }
  } else if (_skind == "camera") {
    ImGui.Spacing();
    __poly_imgui_sec_open();

    if (ImGui.CollapsingHeader("Camera")) __poly_imgui_camera_sec(_ed, _node, _en);
  } else if (_skind == "environment") {
    ImGui.Spacing();
    __poly_imgui_sec_open();

    if (ImGui.CollapsingHeader("Environment")) __poly_imgui_env_sec(_ed, _node, _en);
  }
}

// Draws asset instance sections (shadows, materials, animations).
function __poly_imgui_asset_secs(_ed, _node, _en) {
  ImGui.Spacing();
  __poly_imgui_sec_open();

  if (ImGui.CollapsingHeader("Shadows")) __poly_imgui_asset_sec(_ed, _node, _en);
  __poly_imgui_physics_sec(_ed, _node, _en);
  ImGui.Spacing();
  __poly_imgui_sec_open();

  var _node_mats = __poly_collect_node_mats(_node);

  if (__poly_imgui_section_meta("Materials", __poly_imgui_mat_slot_meta(_node_mats))) __poly_imgui_mat_rows(_ed, _node_mats);
  var _model = __poly_imgui_node_model(_ed, _node);

  if (__poly_imgui_anim_count(_model) > 0) {
    ImGui.Spacing();
    __poly_imgui_sec_open();

    if (__poly_imgui_section_meta("Animations", string(__poly_imgui_anim_count(_model)) + " clips")) __poly_imgui_anim_sec(_ed, _node);
  }
}

// ---------------------------------------------------------------------------
// Dispatcher
// ---------------------------------------------------------------------------

// Reads the light subtype for a single selection (undefined otherwise).
function __poly_inspector_light_subtype(_ed, _node) {
  var _en = __poly_registry_find(_ed, _node);

  if (_en != undefined && is_struct(_en.data) && is_string(_en.data.type)) return _en.data.type;
  return undefined;
}

// Draws the object inspector body for a non-empty selection.
// Returns true when the window is already closed (caller must return).
function __poly_imgui_sel_body(_ed, _n) {
  var _skind = undefined;
  var _stype = undefined;

  if (_n == 1) {
    _skind = __poly_kind_of(_ed, _ed.sel[0]);

    if (_skind == "light") _stype = __poly_inspector_light_subtype(_ed, _ed.sel[0]);
  }

  var _titles = __poly_inspector_titles(_ed, _n, _skind, _stype);

  if (_n == 1 && _skind == "instance") {
    if (__poly_imgui_instance_head(_ed, _ed.sel[0], _titles.title, _titles.type)) {
      ImGui.End();
      return true;
    }
  } else {
    __poly_imgui_plain_head(_titles.title, _titles.type);
  }

  __poly_imgui_transform_sec(_ed, __poly_axis_visibility(_n, _skind, _stype));

  if (_n == 1 && _skind != undefined) {
    var _en = __poly_registry_find(_ed, _ed.sel[0]);

    if (_en != undefined && is_struct(_en.data)) {
      if (_skind == "instance") {
        __poly_imgui_asset_secs(_ed, _ed.sel[0], _en);
      } else {
        __poly_imgui_prop_secs(_ed, _ed.sel[0], _en, _skind);
      }
    }
  }

  return false;
}

// Draws Inspector window for current selection.
function __poly_imgui_inspector(_ed) {
  var _ui = _ed.imgui;

  if (!_ui.win_insp.open) return;
  var _place = __poly_imgui_place(_ed).insp;

  if (!__poly_imgui_dock_fresh(_ed)) {
    ImGui.SetNextWindowPos(_place.x, _place.y, _ui.cond);
    ImGui.SetNextWindowSize(_place.w, _place.h, _ui.cond);
  }

  ImGui.SetNextWindowBgAlpha(1);

  var _flags = __poly_imgui_panel_flags(_ed, "insp");

  if (__poly_imgui_lock_move(_ed)) _flags = _flags | ImGuiWindowFlags.NoMove;

  if (!ImGui.Begin("Inspector", _ui.win_insp, _flags)) {
    __poly_imgui_panel_save(_ed, "insp");
    ImGui.End();
    return;
  }

  __poly_imgui_panel_save(_ed, "insp");
  _ui.axis_values = undefined;

  if (variable_struct_exists(_ed, "mat_inspector") && is_struct(_ed.mat_inspector) && __poly_mat_inspector_stale(_ed)) __poly_mat_inspector_close(_ed);

  if (variable_struct_exists(_ed, "tex_inspector") && is_struct(_ed.tex_inspector)) {
    __poly_imgui_tex_view(_ed);
    return;
  }

  if (variable_struct_exists(_ed, "mat_inspector") && is_struct(_ed.mat_inspector)) {
    __poly_imgui_mat_view(_ed);
    return;
  }

  var _n = array_length(_ed.sel);

  if (_n > 0 && _ed.lib_sel != undefined) _ed.lib_sel = undefined;

  if (_n == 0) {
    var _lib = __poly_lib_sel_asset(_ed);

    if (_lib != undefined) {
      __poly_imgui_spawn_sec(_ed, _lib);
    } else {
      ImGui.TextDisabled("No selection");
      ImGui.Text("Click an object or drag a model in.");
      __poly_imgui_world_sec(_ed);
    }
  } else if (__poly_imgui_sel_body(_ed, _n)) {
    return;
  }

  ImGui.End();
}
