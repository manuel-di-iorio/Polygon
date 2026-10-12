// poly_imgui_insp_sections — per-kind sections (light, camera, env, asset, spawn).

// ---------------------------------------------------------------------------
// Generic edit wrappers (snap, mutate, apply, commit)
// ---------------------------------------------------------------------------

// Generic field edit: snapshots undo, assigns, applies, commits.
// Thin wrappers below delegate here so undo/apply stay in one place.
// _undo=false skips history (live color edits: history is grouped inside
// __poly_imgui_color_edit via col_gest, the caller marks dirty itself).
function __poly_edit_field(_ed, _node, _data, _field, _apply, _newval, _undo = true) {
  var _before = undefined;

  if (_undo) _before = __poly_history_snap(_ed);
  _data[$ _field] = _newval;
  _apply(_node, _data);

  if (_undo && _before != undefined) __poly_history_commit(_ed, _before);
}

// Edits a bool field with undo.
function __poly_edit_bool(_ed, _node, _data, _field, _label, _apply) {
  var _nv = ImGui.Checkbox(_label, _data[$ _field] == true);

  if (_nv != (_data[$ _field] == true)) __poly_edit_field(_ed, _node, _data, _field, _apply, _nv);
}

// Edits a float field with undo and optional clamping.
function __poly_edit_float(_ed, _node, _data, _id, _label, _field, _apply, _min = undefined, _max = undefined) {
  var _nv = __poly_imgui_prop_float(_ed, _id, _label, _data[$ _field], 120);

  if (_nv == undefined) return;
  var _v = _nv;

  if (_min != undefined) _v = max(_v, _min);
  if (_max != undefined) _v = min(_v, _max);
  __poly_edit_field(_ed, _node, _data, _field, _apply, _v);
}

// Edits a radio option with undo. Returns true when picked.
function __poly_edit_radio(_ed, _node, _data, _field, _value, _label, _apply) {
  if (!ImGui.RadioButton(_label, _data[$ _field] == _value)) return false;
  __poly_edit_field(_ed, _node, _data, _field, _apply, _value);
  return true;
}

// Edits an rgb color field live (no undo here, marks dirty).
// History grouping stays inside __poly_imgui_color_edit (col_gest).
function __poly_edit_color(_ed, _node, _data, _id, _label, _field, _apply) {
  var _cur = _data[$ _field];
  var _nv = __poly_imgui_color_edit(_ed, _id, _label, make_colour_rgb(_cur[0], _cur[1], _cur[2]));

  if (_nv == undefined) return;
  __poly_edit_field(_ed, _node, _data, _field, _apply, [ colour_get_red(_nv), colour_get_green(_nv), colour_get_blue(_nv) ], false);
  _ed.dirty = true;
}

// ---------------------------------------------------------------------------
// Asset and light sections
// ---------------------------------------------------------------------------

// Edits asset shadow flags in Inspector.
function __poly_imgui_asset_sec(_ed, _node, _en) {
  var _d = _en.data;
  ImGui.Spacing();
  __poly_edit_bool(_ed, _node, _d, "castShadows", "Cast", __poly_flags_apply_data);
  ImGui.SameLine(0, 18);
  __poly_edit_bool(_ed, _node, _d, "receiveShadows", "Receive", __poly_flags_apply_data);
  ImGui.Spacing();
}

// Edits light properties in Inspector.
function __poly_imgui_light_sec(_ed, _node, _en) {
  var _d = _en.data;

  if (__poly_edit_radio(_ed, _node, _d, "type", "directional", "Directional", __poly_light_apply)) __poly_sel_apply_tool(_ed);

  if (__poly_edit_radio(_ed, _node, _d, "type", "point", "Point", __poly_light_apply)) {
    if (_d.range < 0.5) {
      _d.range = 50.0;
      __poly_light_apply(_node, _d);
    }

    __poly_sel_apply_tool(_ed);
  }

  __poly_edit_bool(_ed, _node, _d, "enabled", "Enabled", __poly_light_apply);
  __poly_edit_float(_ed, _node, _d, "light_int", "Intensity", "intensity", __poly_light_apply, 0);
  __poly_edit_color(_ed, _node, _d, "light_col", "Color", "color", __poly_light_apply);

  if (_d.type != "directional") __poly_edit_float(_ed, _node, _d, "light_range", "Range", "range", __poly_light_apply, 0.01);

  if (_d.type == "spot") {
    __poly_edit_float(_ed, _node, _d, "light_inner", "Inner cone", "inner", __poly_light_apply, 0, 89);
    __poly_edit_float(_ed, _node, _d, "light_outer", "Outer cone", "outer", __poly_light_apply, 1, 89);
  }
}

// Notes when another light owns the single shadow map. Returns true when drawn.
function __poly_shadow_owner_note(_ed, _node) {
  var _owner = __poly_shadow_owner(_ed, _node);

  if (_owner == undefined) return false;
  ImGui.TextDisabled("Shadow maps already enabled on light:");
  ImGui.TextDisabled("\"" + __poly_label_get(_ed, _owner) + "\"");
  ImGui.SameLine();

  if (ImGui.SmallButton("Select")) __poly_sel_assign(_ed, [ _owner ]);
  return true;
}

// Edits light shadow properties in Inspector.
function __poly_imgui_light_shadow_sec(_ed, _node, _en) {
  var _d = _en.data;

  if (_d.shadow != true && __poly_shadow_owner_note(_ed, _node)) return;
  __poly_edit_bool(_ed, _node, _d, "shadow", "Cast shadows", __poly_light_apply);

  if (_d.shadow == true) {
    __poly_edit_shadow_float(_ed, _node, _d, "light_shadow_res", "Resolution", "shadowRes");
    __poly_edit_float(_ed, _node, _d, "light_shadow_dist", "Distance", "shadowDist", __poly_light_apply, 1);
    __poly_edit_float(_ed, _node, _d, "light_shadow_normal", "Normal bias", "shadowNormal", __poly_light_apply, 0, 1);
  }
}

// Edits shadow resolution (snapped to accepted powers of two) with undo.
function __poly_edit_shadow_float(_ed, _node, _d, _id, _label, _field) {
  var _nv = __poly_imgui_prop_float(_ed, _id, _label, _d[$ _field], 120);

  if (_nv == undefined) return;
  __poly_edit_field(_ed, _node, _d, _field, __poly_light_apply, __poly_shadow_res_snap(_nv));
}

// ---------------------------------------------------------------------------
// Camera and environment sections
// ---------------------------------------------------------------------------

// Edits camera properties in Inspector.
function __poly_imgui_camera_sec(_ed, _node, _en) {
  var _d = _en.data;

  __poly_edit_radio(_ed, _node, _d, "projection", "perspective", "Perspective", __poly_camera_apply);
  __poly_edit_radio(_ed, _node, _d, "projection", "ortho", "Ortho", __poly_camera_apply);
  __poly_edit_bool(_ed, _node, _d, "enabled", "Enabled", __poly_camera_apply);

  if (_d.projection == "ortho") {
    __poly_edit_float(_ed, _node, _d, "cam_ow", "Ortho width", "ow", __poly_camera_apply, 0.01);
    __poly_edit_float(_ed, _node, _d, "cam_oh", "Ortho height", "oh", __poly_camera_apply, 0.01);
  } else {
    __poly_edit_float(_ed, _node, _d, "cam_fov", "Fov", "fov", __poly_camera_apply, 1, 179);
  }

  __poly_edit_float(_ed, _node, _d, "cam_near", "Near", "near", __poly_camera_apply, 0.01);
  __poly_edit_cam_far(_ed, _node, _d);
  __poly_cameras_mute(_ed);
}

// Edits a float clamped above a sibling field (+0.01) with undo.
function __poly_edit_float_above(_ed, _node, _d, _id, _label, _field, _apply, _ref) {
  var _nv = __poly_imgui_prop_float(_ed, _id, _label, _d[$ _field], 120);

  if (_nv == undefined) return;
  __poly_edit_field(_ed, _node, _d, _field, _apply, max(_nv, _d[$ _ref] + 0.01));
}

// Edits camera far plane (clamped above near) with undo.
function __poly_edit_cam_far(_ed, _node, _d) {
  __poly_edit_float_above(_ed, _node, _d, "cam_far", "Far", "far", __poly_camera_apply, "near");
}

// Edits the environment size vector with undo.
function __poly_edit_env_size(_ed, _node, _d) {
  ImGui.Text("Size");
  var _size = [ _d.size[0], _d.size[1], _d.size[2] ];
  var _axes = [ "X", "Y", "Z" ];
  var _changed = false;

  for (var _a = 0; _a < 3; _a++) {
    if (_a == 0) {
      ImGui.SameLine(80);
    } else {
      ImGui.SameLine();
    }

    var _nv = __poly_imgui_prop_float(_ed, "env_size" + _axes[_a], "##envsize" + _axes[_a], _size[_a], 46);

    if (_nv != undefined) {
      _size[_a] = max(_nv, 0.01);
      _changed = true;
    }
  }

  if (_changed) __poly_edit_field(_ed, _node, _d, "size", __poly_env_apply, _size);
}

// Edits environment properties in Inspector.
function __poly_imgui_env_sec(_ed, _node, _en) {
  var _d = _en.data;
  __poly_edit_bool(_ed, _node, _d, "enabled", "Enabled", __poly_env_apply);
  __poly_edit_env_size(_ed, _node, _d);
  __poly_edit_color(_ed, _node, _d, "env_amb", "Ambient", "ambient", __poly_env_apply);
  __poly_edit_bool(_ed, _node, _d, "fog", "Fog", __poly_env_apply);

  if (_d.fog == true) {
    __poly_edit_color(_ed, _node, _d, "env_fogc", "Fog color", "fogcolor", __poly_env_apply);
    __poly_edit_float(_ed, _node, _d, "env_fogs", "Fog start", "fogstart", __poly_env_apply);
    __poly_edit_env_fog_end(_ed, _node, _d);
  }
}

// Edits environment fog end (clamped above fog start) with undo.
function __poly_edit_env_fog_end(_ed, _node, _d) {
  __poly_edit_float_above(_ed, _node, _d, "env_foge", "Fog end", "fogend", __poly_env_apply, "fogstart");
}

// ---------------------------------------------------------------------------
// Spawn defaults section
// ---------------------------------------------------------------------------

// Draws one spawn transform row (rotation or scale), returning drag-busy.
function __poly_spawn_mode_row(_ui, _t, _mode) {
  var _names = [ "X", "Y", "Z" ];
  var _arr = _mode == 0 ? _t.rot : _t.sca;
  var _speed = _mode == 0 ? 0.1 : 0.01;
  var _title = _mode == 0 ? "Rotation" : "Scale";
  var _busy = false;
  ImGui.PushID(_mode);
  ImGui.AlignTextToFramePadding();
  ImGui.Text(_title);

  for (var _ax = 0; _ax < 3; _ax++) {
    if (_ax == 0) {
      ImGui.SameLine(80);
    } else {
      ImGui.SameLine();
    }

    ImGui.SetNextItemWidth(46);
    var _key = "sp" + string(_mode) + "_" + _names[_ax];
    var _was = _ui.active[$ _key] == true;
    var _input = _arr[_ax];

    if (_was && variable_struct_exists(_ui.draft, _key) && is_real(_ui.draft[$ _key])) _input = _ui.draft[$ _key];
    var _nv = __poly_imgui_dragfloat(_names[_ax], _input, _speed);
    var _now = ImGui.IsItemActive();
    _ui.active[$ _key] = _now;
    _busy = _busy || _now;

    if (_now) {
      _ui.draft[$ _key] = _nv;
    } else {
      if (variable_struct_exists(_ui.draft, _key)) variable_struct_remove(_ui.draft, _key);
      if (_was && _nv != _arr[_ax]) _arr[_ax] = _mode == 1 ? max(_nv, 0.01) : _nv;
    }

    if (_ax < 2) {
      ImGui.SameLine();
      ImGui.Dummy(2, 0);
    }
  }

  ImGui.PopID();
  return _busy;
}

// Re-queues the thumbnail when spawn rotation changed (not while dragging).
function __poly_spawn_thumb_sync(_ed, _entry, _t, _busy) {
  if (_busy) return;
  var _known = _entry[$ "thumb_rot"];

  if (is_array(_known) && _known[0] == _t.rot[0] && _known[1] == _t.rot[1] && _known[2] == _t.rot[2]) return;
  _entry.thumb_rot = [ _t.rot[0], _t.rot[1], _t.rot[2] ];

  if (is_array(_ed.thumb_queue) && !array_contains(_ed.thumb_queue, _entry)) array_push(_ed.thumb_queue, _entry);
}

// Draws default spawn transform and shadows for a library asset.
function __poly_imgui_spawn_sec(_ed, _entry) {
  var _t = __poly_spawn_t(_entry);
  var _sh = __poly_spawn_shadow(_entry);

  if (_t == undefined || _sh == undefined) return;

  if (!variable_struct_exists(_entry, "spawn_ui") || !is_struct(_entry.spawn_ui)) {
    _entry.spawn_ui = { active: {}, draft: {} };
  }

  var _thumb = variable_struct_exists(_entry, "thumb") && sprite_exists(_entry.thumb) ? _entry.thumb : -1;
  __poly_imgui_inspector_asset_header(__poly_asset_label(_entry), "Prefab", _thumb, 96);

  __poly_imgui_sec_open();

  if (ImGui.CollapsingHeader("Transform")) {
    var _busy = __poly_spawn_mode_row(_entry.spawn_ui, _t, 0) || __poly_spawn_mode_row(_entry.spawn_ui, _t, 1);
    __poly_spawn_thumb_sync(_ed, _entry, _t, _busy);
  }

  ImGui.Spacing();
  __poly_imgui_sec_open();

  if (ImGui.CollapsingHeader("Shadows")) {
    ImGui.Spacing();
    __poly_edit_spawn_shadow(_entry, "cast", "Cast");
    ImGui.SameLine(0, 18);
    __poly_edit_spawn_shadow(_entry, "recv", "Receive");
    ImGui.Spacing();
  }

  ImGui.Spacing();
  __poly_imgui_sec_open();

  var _asset_mats = __poly_collect_asset_mats(_entry);

  if (__poly_imgui_section_meta("Materials", __poly_imgui_mat_slot_meta(_asset_mats))) __poly_imgui_mat_rows(_ed, _asset_mats);
  var _clips = __poly_imgui_anim_count(_entry.model);

  if (_clips > 0) {
    ImGui.Spacing();
    __poly_imgui_sec_open();

    if (__poly_imgui_section_meta("Animations", string(_clips) + " clips")) __poly_imgui_prefab_anim_sec(_ed, _entry);
  }

  ImGui.Spacing();
  __poly_imgui_sec_open();

  if (ImGui.CollapsingHeader("Actor")) {
    ImGui.Spacing();
    __poly_imgui_actor_sec(_ed, _entry);
    ImGui.Spacing();
  }
}

// Edits one spawn shadow flag live (no undo: library defaults).
function __poly_edit_spawn_shadow(_entry, _field, _label) {
  var _nv = ImGui.Checkbox(_label, _entry.spawn_shadow[$ _field] == true);

  if (_nv != (_entry.spawn_shadow[$ _field] == true)) _entry.spawn_shadow[$ _field] = _nv;
}

// ---------------------------------------------------------------------------
// Actor binding section (per-model companion config, saved to file)
// ---------------------------------------------------------------------------

// Ensures the per-model file-meta map exists.
function __poly_asset_meta(_ed) {
  if (!variable_struct_exists(_ed, "asset_meta") || !is_struct(_ed.asset_meta)) _ed.asset_meta = {};
  return _ed.asset_meta;
}

// Returns the actor binding struct for an asset key, or undefined.
function __poly_actor_get(_ed, _key) {
  if (!is_string(_key) || _key == "") return undefined;
  var _meta = __poly_asset_meta(_ed);

  if (!variable_struct_exists(_meta, _key) || !is_struct(_meta[$ _key])) return undefined;
  var _entry = _meta[$ _key];

  if (!variable_struct_exists(_entry, "actor") || !is_struct(_entry.actor)) return undefined;
  return _entry.actor;
}

// Draws the Actor section for a library entry (model inspector, no undo:
// file metadata like spawn defaults). The binding counts when an object
// is set; an empty object means no companion.
function __poly_imgui_actor_sec(_ed, _entry) {
  var _key = is_struct(_entry) ? _entry[$ "key"] : undefined;

  if (!is_string(_key) || _key == "") return;
  var _ac = __poly_actor_get(_ed, _key);

  if (_ac == undefined) {
    var _meta = __poly_asset_meta(_ed);
    _meta[$ _key] = { type: "model", actor: { object: "", layer: "Instances" } };
    _ac = __poly_actor_get(_ed, _key);

    if (_ac == undefined) return;
  }

  if (!variable_struct_exists(_entry, "actor_ui") || !is_struct(_entry.actor_ui)) _entry.actor_ui = { filter: "" };
  var _cur = (is_string(_ac[$ "object"]) && _ac.object != "") ? _ac.object : "(none)";
  ImGui.AlignTextToFramePadding();
  ImGui.Text("Object");
  ImGui.SameLine(80);
  ImGui.SetNextItemWidth(220);

  if (ImGui.BeginCombo("##actor_obj", _cur)) {
    _entry.actor_ui.filter = __poly_imgui_text_hint("##actor_find", "Search...", _entry.actor_ui.filter);

    if (ImGui.Selectable("(none)", _cur == "(none)", 0, 0, 0)) {
      _ac.object = "";
      _ed.dirty = true;
    }

    var _ids = asset_get_ids(asset_object);
    var _flt = string_lower(_entry.actor_ui.filter);
    var _shown = 0;

    for (var _i = 0, _n = array_length(_ids); _i < _n; _i++) {
      var _nm = object_get_name(_ids[_i]);

      if (!is_string(_nm) || _nm == "") continue;
      if (_flt != "" && string_pos(_flt, string_lower(_nm)) <= 0) continue;

      if (ImGui.Selectable(_nm, _cur == _nm, 0, 0, 0)) {
        _ac.object = _nm;
        _ed.dirty = true;
      }

      _shown++;
      if (_shown >= 200) break;
    }

    ImGui.EndCombo();
  }

  var _base_layer = (is_string(_ac[$ "layer"]) && _ac.layer != "") ? _ac.layer : "Instances";
  ImGui.AlignTextToFramePadding();
  ImGui.Text("Layer");
  ImGui.SameLine(80);
  ImGui.SetNextItemWidth(220);
  var _lr = __poly_imgui_text("actor_layer_" + _key, "##actor_layer", _base_layer);

  if (!_lr.active && _lr.was_active) {
    var _v = _lr.text == "" ? "Instances" : _lr.text;

    if (_v != _base_layer) {
      _ac.layer = _v;
      _ed.dirty = true;
    }
  }
}
