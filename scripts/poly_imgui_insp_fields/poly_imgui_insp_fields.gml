// poly_imgui_insp_fields - field editors (axis rows, floats, colors, section state).

// ---------------------------------------------------------------------------
// Axis cache
// ---------------------------------------------------------------------------

// Reads one transform component from cached node parts.
function __poly_axis_comp(_mode, _idx, _pos, _euler, _sca) {
  if (_mode == 0) {
    return _idx == 0 ? _pos.x : (_idx == 1 ? _pos.y : _pos.z);
  } else if (_mode == 1) {
    return radtodeg(_euler[_idx]);
  } else {
    return _idx == 0 ? _sca.x : (_idx == 1 ? _sca.y : _sca.z);
  }
}

// Gets shared axis value detecting mixed selection.
function __poly_axis_val(_ed, _mode, _idx) {
  if (!variable_struct_exists(_ed.imgui, "axis_values") || _ed.imgui.axis_values == undefined) {
    var _values = [ [ 0, 0, 0 ], [ 0, 0, 0 ], [ 0, 0, 0 ] ];
    var _mixed = [ [ false, false, false ], [ false, false, false ], [ false, false, false ] ];
    var _n = array_length(_ed.sel);

    for (var _i = 0; _i < _n; _i++) {
      var _node = _ed.sel[_i];
      var _pos = _node.getLocalPosition();
      var _euler = __poly_quat_to_euler(_node.getLocalRotation());
      var _sca = _node.getLocalScale();

      for (var _m = 0; _m < 3; _m++) {
        for (var _a = 0; _a < 3; _a++) {
          var _c = __poly_axis_comp(_m, _a, _pos, _euler, _sca);

          if (_i == 0) {
            _values[_m][_a] = _c;
          } else if (abs(_c - _values[_m][_a]) > 0.0005) {
            _mixed[_m][_a] = true;
          }
        }
      }
    }

    _ed.imgui.axis_values = { values: _values, mixed: _mixed };
  }

  var _cache = _ed.imgui.axis_values;
  return { mixed: _cache.mixed[_mode][_idx], val: _cache.values[_mode][_idx] };
}

// Opens collapsible section by default on first use.
function __poly_imgui_sec_open() {
  ImGui.SetNextItemOpen(true, ImGuiCond.FirstUseEver);
}

// ---------------------------------------------------------------------------
// Axis rows
// ---------------------------------------------------------------------------

// True while an inspector drag gesture (axis/float/color) is live:
// these mutate the scene with live preview but no undo commit yet.
function __poly_inspector_gesturing(_ed) {
  if (!is_struct(_ed) || !is_struct(_ed.imgui)) return false;
  var _maps = [ "ax_active", "flt_active" ];

  for (var _m = 0; _m < array_length(_maps); _m++) {
    var _map = _ed.imgui[$ _maps[_m]];
    if (!is_struct(_map)) continue;
    var _ns = variable_struct_get_names(_map);
    for (var _i = 0, _n = array_length(_ns); _i < _n; _i++) if (_map[$ _ns[_i]] == true) return true;
  }

  var _cg = _ed.imgui[$ "col_gest"];
  if (!is_struct(_cg)) return false;
  var _cn = variable_struct_get_names(_cg);

  for (var _j = 0, _nj = array_length(_cn); _j < _nj; _j++) {
    var _r = _cg[$ _cn[_j]];
    if (is_struct(_r) && _r.active == true) return true;
  }

  return false;
}

// Commits a finished axis drag (applies final value, single undo entry).
function __poly_axis_release(_ed, _fkey, _nv, _shown, _was, _mode, _ax) {
  if (variable_struct_exists(_ed.imgui.ax_draft, _fkey)) variable_struct_remove(_ed.imgui.ax_draft, _fkey);
  var _before = undefined;

  if (variable_struct_exists(_ed.imgui.ax_before, _fkey)) {
    _before = _ed.imgui.ax_before[$ _fkey];
    variable_struct_remove(_ed.imgui.ax_before, _fkey);
  }

  if (_was) {
    if (is_real(_nv) && _nv != _shown) __poly_apply_axis(_ed, _mode, _ax, _nv);
    if (_before != undefined) __poly_history_commit(_ed, _before);
    __poly_physics_debug_rebuild(_ed);
  }
}

// Edits one axis cell with drag tracking and live preview.
function __poly_axis_cell(_ed, _mode, _ax, _names, _speed) {
  var _shown = __poly_axis_val(_ed, _mode, _ax);
  var _fkey = "ax" + string(_mode) + "_" + _names[_ax];
  var _was = _ed.imgui.ax_active[$ _fkey] == true;
  var _input = _shown.val;

  if (_was && variable_struct_exists(_ed.imgui.ax_draft, _fkey)) {
    var _draft = _ed.imgui.ax_draft[$ _fkey];

    if (is_real(_draft)) _input = _draft;
  }

  var _nv = __poly_imgui_dragfloat(_names[_ax], _input, _speed);
  var _now = ImGui.IsItemActive();

  if (_now && !_was) {
    // Gesture start: capture undo state once (mirrors gizmo hist_before).
    _ed.imgui.ax_before[$ _fkey] = __poly_history_snap(_ed);
  }

  _ed.imgui.ax_active[$ _fkey] = _now;

  if (_now) {
    _ed.imgui.ax_draft[$ _fkey] = _nv;
    // Live preview: apply to the nodes every frame while dragging.
    // No history here - a single undo entry is committed on release.
    if (is_real(_nv) && _nv != _shown.val) __poly_apply_axis(_ed, _mode, _ax, _nv);
  } else {
    __poly_axis_release(_ed, _fkey, _nv, _shown.val, _was, _mode, _ax);
  }
}

// Edits Position Rotation or Scale axis row.
function __poly_imgui_axis_row(_ed, _mode, _label) {
  var _names = [ "X", "Y", "Z" ];
  ImGui.PushID(_mode);
  ImGui.AlignTextToFramePadding();
  ImGui.Text(_label);
  var _speed = _mode == 1 ? 0.1 : 0.01;

  for (var _a = 0; _a < 3; _a++) {
    if (_a == 0) {
      ImGui.SameLine(80);
    } else {
      ImGui.SameLine();
    }

    ImGui.SetNextItemWidth(46);
    __poly_axis_cell(_ed, _mode, _a, _names, _speed);

    if (_a < 2) {
      ImGui.SameLine();
      ImGui.Dummy(2, 0);
    }
  }

  ImGui.PopID();
}

// ---------------------------------------------------------------------------
// Floats, colors, commit
// ---------------------------------------------------------------------------

// Edits float property with edit tracking.
function __poly_imgui_prop_float(_ed, _key, _label, _val, _w) {
  ImGui.SetNextItemWidth(_w);
  var _was = _ed.imgui.flt_active[$ _key] == true;
  var _input = _val;

  if (_was && variable_struct_exists(_ed.imgui.flt_draft, _key)) {
    var _draft = _ed.imgui.flt_draft[$ _key];

    if (is_real(_draft)) _input = _draft;
  }

  var _nv = __poly_imgui_dragfloat(_label, _input, 0.01);
  var _now = ImGui.IsItemActive();
  _ed.imgui.flt_active[$ _key] = _now;

  if (_now) {
    _ed.imgui.flt_draft[$ _key] = _nv;
    return undefined;
  }

  if (variable_struct_exists(_ed.imgui.flt_draft, _key)) variable_struct_remove(_ed.imgui.flt_draft, _key);
  if (_was && _nv != _val) return _nv;
  return undefined;
}

// Commits history snapshot.
// Edits color with undo history grouping.
function __poly_imgui_color_edit(_ed, _key, _label, _packed) {
  if (!variable_struct_exists(_ed.imgui, "col_gest")) {
    _ed.imgui.col_gest = {};
  }

  var _nv = ImGui.ColorEdit3(_label, _packed);
  var _now = ImGui.IsItemActive();
  var _rec = _ed.imgui.col_gest[$ _key];
  var _was = is_struct(_rec) && _rec.active == true;

  if (_now && !_was) {
    _ed.imgui.col_gest[$ _key] = { active: true, before: __poly_history_snap(_ed) };
  }

  if (!_now && _was) {
    var _before = _rec.before;
    _ed.imgui.col_gest[$ _key] = { active: false, before: undefined };

    if (_before != undefined) __poly_history_commit(_ed, _before);
  }

  if (_nv != _packed) return _nv;
  return undefined;
}
