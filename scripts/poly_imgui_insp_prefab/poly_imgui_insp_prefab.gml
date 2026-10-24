// poly_imgui_insp_prefab — prefab overrides row.

// ---------------------------------------------------------------------------
// Override detection
// ---------------------------------------------------------------------------

// Angular difference in degrees wrapped to [0, 180].
function __poly_ang_diff(_a, _b) {
  var _d = abs(_a - _b) mod 360;

  if (_d > 180) _d = 360 - _d;
  return _d;
}

// Collects rotation/scale/shadow overrides against spawn defaults.
function __poly_over_diffs(_ed, _node, _en, _entry) {
  var _diffs = [];
  var _spawn = __poly_spawn_t(_entry);

  if (_spawn != undefined) {
    var _rot = _node.getLocalRotation();

    if (_rot != undefined) {
      var _euler = __poly_quat_to_euler(_rot);

      if (is_array(_euler) && array_length(_euler) >= 3) {
        var _deg = [ radtodeg(_euler[0]), radtodeg(_euler[1]), radtodeg(_euler[2]) ];

        if (__poly_ang_diff(_deg[0], _spawn.rot[0]) > 0.05 || __poly_ang_diff(_deg[1], _spawn.rot[1]) > 0.05 || __poly_ang_diff(_deg[2], _spawn.rot[2]) > 0.05) {
          array_push(_diffs, { kind: "rot", label: "Rotation" });
        }
      }
    }

    var _sca = _node.getLocalScale();

    if (_sca != undefined) {
      if (abs(_sca.x - _spawn.sca[0]) > 0.001 || abs(_sca.y - _spawn.sca[1]) > 0.001 || abs(_sca.z - _spawn.sca[2]) > 0.001) {
        array_push(_diffs, { kind: "sca", label: "Scale" });
      }
    }
  }

  var _shadow = __poly_spawn_shadow(_entry);

  if (_shadow != undefined && is_struct(_en.data)) {
    if ((_en.data.castShadows == true) != (_shadow.cast == true) || (_en.data.receiveShadows == true) != (_shadow.recv == true)) {
      array_push(_diffs, { kind: "shad", label: "Shadows" });
    }
  }

  var _defaults = is_struct(_entry[$ "physics_default"]) ? _entry.physics_default
    : (is_struct(_ed.asset_meta) && is_struct(_ed.asset_meta[$ _entry.key]) && is_struct(_ed.asset_meta[$ _entry.key][$ "physics"])
      ? _ed.asset_meta[$ _entry.key].physics : undefined);
  if (_defaults != undefined && is_struct(_en.data) && is_struct(_en.data[$ "physics"])) {
    if (json_stringify(__poly_physics_data(_defaults)) != json_stringify(__poly_physics_data(_en.data.physics))) array_push(_diffs, { kind: "physics", label: "Physics" });
  }

  return _diffs;
}

// ---------------------------------------------------------------------------
// Revert and apply
// ---------------------------------------------------------------------------

// Reverts one override kind to the asset prefab (no history here).
function __poly_over_revert(_ed, _node, _en, _entry, _kind) {
  var _spawn = __poly_spawn_t(_entry);
  var _shadow = __poly_spawn_shadow(_entry);
  var _physics_default = is_struct(_entry[$ "physics_default"]) ? _entry.physics_default : undefined;

  if (_kind == "rot" && _spawn != undefined) {
    _node.setLocalRotation(__poly_euler_to_quat(degtorad(_spawn.rot[0]), degtorad(_spawn.rot[1]), degtorad(_spawn.rot[2])));
  } else if (_kind == "sca" && _spawn != undefined) {
    _node.setLocalScale(new GM3D_Vec3(max(_spawn.sca[0], 0.01), max(_spawn.sca[1], 0.01), max(_spawn.sca[2], 0.01)));
  } else if (_kind == "shad" && _shadow != undefined && is_struct(_en.data)) {
    _en.data.castShadows = _shadow.cast == true;
    _en.data.receiveShadows = _shadow.recv == true;
    __poly_flags_apply(_node, _en.data.castShadows, _en.data.receiveShadows);
  } else if (_kind == "physics" && is_struct(_physics_default) && is_struct(_en.data)) {
    _en.data.physics = __poly_physics_data(_physics_default);
    __poly_physics_debug_destroy(_ed);
    __poly_physics_apply(_node, _en.data.physics);
    __poly_physics_debug_rebuild(_ed);
  }
}

// Saves one live value into the asset prefab (no history here).
function __poly_over_apply(_ed, _node, _en, _entry, _kind) {
  var _spawn = __poly_spawn_t(_entry);
  var _shadow = __poly_spawn_shadow(_entry);

  if (_kind == "rot" && _spawn != undefined) {
    var _rot = _node.getLocalRotation();

    if (_rot != undefined) {
      var _euler = __poly_quat_to_euler(_rot);

      if (is_array(_euler) && array_length(_euler) >= 3) {
        _spawn.rot = [ radtodeg(_euler[0]), radtodeg(_euler[1]), radtodeg(_euler[2]) ];
        _entry.thumb_rot = [ _spawn.rot[0], _spawn.rot[1], _spawn.rot[2] ];

        if (is_array(_ed.thumb_queue) && !array_contains(_ed.thumb_queue, _entry)) array_push(_ed.thumb_queue, _entry);
      }
    }
  } else if (_kind == "sca" && _spawn != undefined) {
    var _sca = _node.getLocalScale();

    if (_sca != undefined) _spawn.sca = [ max(_sca.x, 0.01), max(_sca.y, 0.01), max(_sca.z, 0.01) ];
  } else if (_kind == "shad" && _shadow != undefined && is_struct(_en.data)) {
    _shadow.cast = _en.data.castShadows == true;
    _shadow.recv = _en.data.receiveShadows == true;
  } else if (_kind == "physics" && is_struct(_en.data) && is_struct(_en.data[$ "physics"])) {
    _entry.physics_default = __poly_physics_data(_en.data.physics);
    if (!is_struct(_ed.asset_meta)) _ed.asset_meta = {};
    var _meta = variable_struct_exists(_ed.asset_meta, _entry.key) ? _ed.asset_meta[$ _entry.key] : { type: "model" };
    _meta.physics = __poly_physics_data(_en.data.physics);
    _ed.asset_meta[$ _entry.key] = _meta;
  }
}

// Reverts one override with undo.
function __poly_over_revert_one(_ed, _node, _en, _entry, _kind) {
  var _before = __poly_history_snap(_ed);
  __poly_over_revert(_ed, _node, _en, _entry, _kind);

  if (_before != undefined) __poly_history_commit(_ed, _before);
}

// Reverts all overrides with undo.
function __poly_over_revert_all(_ed, _node, _en, _entry, _diffs) {
  var _before = __poly_history_snap(_ed);

  for (var _i = 0, _n = array_length(_diffs); _i < _n; _i++) __poly_over_revert(_ed, _node, _en, _entry, _diffs[_i].kind);
  if (_before != undefined) __poly_history_commit(_ed, _before);
}

// ---------------------------------------------------------------------------
// Row UI
// ---------------------------------------------------------------------------

// Draws one override diff with Revert/Apply buttons.
function __poly_over_diff_row(_ed, _node, _en, _entry, _diff, _idx) {
  var _btn_w = 60;
  var _avail = ImGui.GetContentRegionAvailX();
  ImGui.AlignTextToFramePadding();
  ImGui.Text(_diff.label);
  ImGui.SameLine(_avail - _btn_w * 2 - 8);
  ImGui.PushID(_idx * 2);

  if (ImGui.Button("Revert", _btn_w, 0)) __poly_over_revert_one(_ed, _node, _en, _entry, _diff.kind);
  if (ImGui.IsItemHovered()) ImGui.SetTooltip("Revert " + _diff.label + " to spawn default");
  ImGui.PopID();
  ImGui.SameLine();
  ImGui.PushID(_idx * 2 + 1);

  if (ImGui.Button("Apply", _btn_w, 0)) __poly_over_apply(_ed, _node, _en, _entry, _diff.kind);
  if (ImGui.IsItemHovered()) ImGui.SetTooltip("Save current " + _diff.label + " as spawn default");
  ImGui.PopID();
}

// Draws the overrides combo (or the empty state).
function __poly_over_combo(_ed, _node, _en, _entry, _diffs) {
  ImGui.SetNextItemWidth(220);
  ImGui.PushStyleColor(ImGuiCol.PopupBg, make_colour_rgb(24, 30, 48), 1);
  ImGui.SetNextWindowBgAlpha(1);

  if (array_length(_diffs) == 0) {
    ImGui.TextDisabled("(no overrides)");
  } else if (ImGui.BeginCombo("##prefab_over", "Overrides (" + string(array_length(_diffs)) + ")")) {
    for (var _d = 0, _n = array_length(_diffs); _d < _n; _d++) __poly_over_diff_row(_ed, _node, _en, _entry, _diffs[_d], _d);
    ImGui.Separator();

    if (ImGui.Button("Revert All", 0, 0)) __poly_over_revert_all(_ed, _node, _en, _entry, _diffs);
    if (ImGui.IsItemHovered()) ImGui.SetTooltip("Revert all overrides to prefab");
    ImGui.SameLine();

    if (ImGui.Button("Apply All", 0, 0)) for (var _a = 0, _na = array_length(_diffs); _a < _na; _a++) __poly_over_apply(_ed, _node, _en, _entry, _diffs[_a].kind);
    if (ImGui.IsItemHovered()) ImGui.SetTooltip("Save all current values as prefab");
    ImGui.EndCombo();
  }

  __poly_imgui_pop(1);
  ImGui.SameLine();

  if (ImGui.Button("Select", 0, 0)) {
    _ed.lib_sel = __poly_asset_index(_ed, _entry);
    __poly_sel_clear(_ed);
    return true;
  }

  ImGui.Spacing();
  return false;
}

// Finds the library index of an entry.
function __poly_asset_index(_ed, _entry) {
  if (!is_array(_ed.assets)) return -1;
  for (var _i = 0, _n = array_length(_ed.assets); _i < _n; _i++) if (_ed.assets[_i] == _entry) return _i;
  return -1;
}

// Draws Prefab row: source asset link, overrides, select.
// Returns true when the caller must stop drawing the inspector.
function __poly_imgui_prefab_row(_ed, _node) {
  var _en = __poly_registry_find(_ed, _node);

  if (_en == undefined || !is_string(_en.asset) || !is_array(_ed.assets)) return false;
  var _entry = __poly_asset_get(_ed, _en.asset);

  if (_entry == undefined) return false;
  var _diffs = __poly_over_diffs(_ed, _node, _en, _entry);
  _ed.prefab_override_count = array_length(_diffs);

  ImGui.AlignTextToFramePadding();
  ImGui.Text("Prefab");
  ImGui.SameLine(80);
  ImGui.Text(__poly_display_from_key(_entry.key));
  return __poly_over_combo(_ed, _node, _en, _entry, _diffs);
}
