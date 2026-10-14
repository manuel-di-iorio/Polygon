// poly_scene_ops — drop point, destroy/new, delete/duplicate, focus, selection.

// ---------------------------------------------------------------------------
// Drop point and rect
// ---------------------------------------------------------------------------

// Computes ground plane drop point.
function __poly_drop_point(_vp, _mx, _my) {
  var _ray = __poly_screen_ray(_vp, _mx, _my);
  return __poly_ray_plane(
    _ray.origin,
    _ray.dir,
    new GM3D_Vec3(0, 0, 0),
    new GM3D_Vec3(0, 1, 0)
  );
}

// Normalizes rectangle corner coordinates.
function __poly_rect_norm(_r) {
  return {
    x0: min(_r.x0, _r.x1),
    y0: min(_r.y0, _r.y1),
    x1: max(_r.x0, _r.x1),
    y1: max(_r.y0, _r.y1),
  };
}

// Destroys node and all children.
function __poly_destroy_subtree(_node) {
  if (_node == undefined) return;
  var _kids = _node.getChildren();

  for (var _i = 0, _n = array_length(_kids); _i < _n; _i++) __poly_destroy_subtree(_kids[_i]);
  _node.destroy();
}

// ---------------------------------------------------------------------------
// New and discard
// ---------------------------------------------------------------------------

// Clears scene to empty state.
function __poly_new_scene(_ed) {
  __poly_drop_preview_clear(_ed);
  var _tracked = __poly_root_tracked(_ed);

  for (var _i = 0, _n = array_length(_tracked); _i < _n; _i++) __poly_destroy_subtree(_tracked[_i]);
  _ed.rt.scene.update(0);
  __poly_reg_clear(_ed);
  var _main_cam = __poly_gamecam_ensure(_ed);

  if (_main_cam != undefined) {
    // Keep the current view: a fresh scene must not yank the viewport to
    // the new camera's identity pose. Seed the gameplay camera from the
    // viewcam instead, so the seed below becomes a no-op.
    if (_ed.rt != undefined && _ed.rt.cam != undefined && _ed.rt.cam != _main_cam) {
      var _vp0 = _ed.rt.cam.getLocalPosition();
      var _vr0 = _ed.rt.cam.getLocalRotation();
      _main_cam.setLocalPosition(new GM3D_Vec3(_vp0.x, _vp0.y, _vp0.z));
      _main_cam.setLocalRotation(_vr0.clone());
      __poly_camera_apply(_main_cam, __poly_camera_read(_ed.rt.cam));
      var _seed_en = __poly_registry_find(_ed, _main_cam);

      if (_seed_en != undefined) _seed_en.data = __poly_camera_read(_main_cam);
    }

    var _cam_entry = __poly_registry_find(_ed, _main_cam);

    if (_cam_entry != undefined && is_struct(_cam_entry.data)) {
      _cam_entry.data.far = 10000.0;
      __poly_camera_apply(_main_cam, _cam_entry.data);
    }
  }

  __poly_default_sun(_ed);
  var _env = __poly_create_env(_ed);

  if (_env != undefined) __poly_hidden_set(_ed, _env, false);
  _ed.rt.scene.update(0);
  __poly_viewcam_seed(_ed);
  // Tracked cameras stay muted while editing (same invariant as enable
  // and create_camera): only the viewcam renders.
  __poly_cameras_mute(_ed);
  __poly_sky_remove(_ed);
  __poly_sky_ensure(_ed);
  __poly_sky_sync(_ed);
  __poly_sel_clear(_ed);
  __poly_history_clear(_ed);
  _ed.asset_meta = {};
  _ed.dirty = false;
  _ed.drag_lib = undefined;
  _ed.drag_moved = false;
  _ed.rect = undefined;
  _ed.press_vp = false;
  _ed.scene_file = "";
}

// Creates the default raised sun for a fresh scene.
function __poly_default_sun(_ed) {
  static _sun_pos = [ 0.3, 2.2, 1.3 ];
  static _sun_dir = [ 0.35, 0.8, 0.45 ];
  var _sun = __poly_create_light(_ed, "directional");

  if (_sun == undefined) return undefined;
  _sun.setLocalPosition(new GM3D_Vec3(_sun_pos[0], _sun_pos[1], _sun_pos[2]));
  var _dir = new GM3D_Vec3(_sun_dir[0], _sun_dir[1], _sun_dir[2]);
  _sun.setLocalRotation(
    GM3D_Quaternion.fromLookRotation(_dir.normalize(), GM3D_Vec3.up()).normalizeSafe(0.000001)
  );
  var _entry = __poly_registry_find(_ed, _sun);

  if (_entry != undefined && is_struct(_entry.data)) {
    _entry.data.shadow = true;
    _entry.data.shadowDist = 30.0;
    __poly_light_apply(_sun, _entry.data);
  }

  return _sun;
}

// Drops session edits, restoring the last clean state.
function __poly_discard_changes(_ed) {
  var _path = __poly_scene_path(_ed);

  if (_path != "" && file_exists(_path)) {
    if (__poly_load_scene(_ed)) {
      __poly_sel_clear(_ed);
      __poly_history_clear(_ed);
    }

    return;
  }

  if (variable_struct_exists(_ed, "open_snapshot") && is_array(_ed.open_snapshot)) {
    __poly_rebuild(_ed, _ed.open_snapshot);
    __poly_sel_clear(_ed);
    __poly_history_clear(_ed);
    _ed.dirty = false;
    return;
  }

  __poly_new_scene(_ed);
}

// ---------------------------------------------------------------------------
// Delete and duplicate
// ---------------------------------------------------------------------------

// Asks for confirmation when deleting multiple nodes, deletes directly
// when a single node (or less) is affected.
function __poly_delete_ask(_ed) {
  if (array_length(_ed.sel) == 0) return;
  if (variable_struct_exists(_ed, "delete_confirm") && _ed.delete_confirm != undefined) return;
  var _victims = 0;

  for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) {
    if (_ed.rt != undefined && __poly_node_same(_ed.sel[_i], _ed.rt.cam)) continue;
    _victims++;
  }

  if (_victims <= 1) {
    __poly_delete_sel(_ed);
    return;
  }

  _ed.delete_confirm = { open: true, count: _victims };
}

// Deletes selected nodes with undo.
function __poly_delete_sel(_ed) {
  if (array_length(_ed.sel) == 0) return;
  var _victims = [];

  for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) {
    if (_ed.rt != undefined && __poly_node_same(_ed.sel[_i], _ed.rt.cam)) continue;
    array_push(_victims, _ed.sel[_i]);
  }

  if (array_length(_victims) == 0) return;
  var _before = __poly_history_snap(_ed);

  for (var _j = 0, _nv = array_length(_victims); _j < _nv; _j++) {
    __poly_spawn_unregister(_ed, _victims[_j]);
    __poly_destroy_subtree(_victims[_j]);
  }

  _ed.rt.scene.update(0);
  __poly_sel_clear(_ed);
  __poly_history_commit(_ed, _before);
}

// Duplicates one asset node in place, copying shadow flags.
function __poly_duplicate_asset(_ed, _src) {
  var _key = __poly_asset_name(_ed, _src);

  if (_key == undefined) return undefined;
  var _model = __poly_asset_find(_ed, _key);

  if (_model == undefined) return undefined;
  var _pos = _src.getLocalPosition();
  var _sca = _src.getLocalScale();
  var _src_en = __poly_registry_find(_ed, _src);
  var _copy_label = (_src_en != undefined && is_string(_src_en.label)) ? _src_en.label : undefined;
  var _copy = __poly_place(
    _ed,
    _key,
    _model,
    [ _pos.x, _pos.y, _pos.z ],
    _src.getLocalRotation().clone(),
    [ _sca.x, _sca.y, _sca.z ],
    _copy_label
  );

  if (_copy == undefined) return undefined;

  if (_src_en != undefined && is_struct(_src_en.data)) {
    var _cast = _src_en.data.castShadows == true;
    var _recv = _src_en.data.receiveShadows == true;
    var _copy_en = __poly_registry_find(_ed, _copy);

    if (_copy_en != undefined) {
      _copy_en.data = { castShadows: _cast, receiveShadows: _recv };
    }

    __poly_flags_apply(_copy, _cast, _recv);
  }

  return _copy;
}

// Duplicates selected nodes in place.
function __poly_duplicate_sel(_ed) {
  var _n = array_length(_ed.sel);

  if (_n == 0) return;
  var _before = __poly_history_snap(_ed);
  var _out = [];

  for (var _i = 0; _i < _n; _i++) {
    var _src = _ed.sel[_i];
    var _kind = __poly_kind_of(_ed, _src);
    var _copy = undefined;

    if (_kind == "light" || _kind == "camera" || _kind == "environment") {
      _copy = __poly_duplicate_prop(_ed, _src, _kind);
    } else {
      _copy = __poly_duplicate_asset(_ed, _src);
    }

    if (_copy != undefined) array_push(_out, _copy);
  }

  if (array_length(_out) > 0) _ed.sel = _out;
  __poly_history_commit(_ed, _before);
}

// Copies prop data for duplication (shape-preserving deep copy: the
// entry data must stay data-shaped, not descriptor-shaped, or the
// inspector/overlay reads wrong fields on the duplicate).
function __poly_duplicate_prop_data(_src_data) {
  if (!is_struct(_src_data)) return undefined;
  return json_parse(json_stringify(_src_data));
}

// Duplicates light camera environment node in place (fresh wrapper id).
function __poly_duplicate_prop(_ed, _src, _kind) {
  var _en = __poly_registry_find(_ed, _src);

  if (_en == undefined || !is_struct(_en.data)) return undefined;
  var _slabel = (is_string(_en.label)) ? _en.label : undefined;
  var _node = _ed.rt.scene.createNode(__poly_wrap_new(_ed));

  if (_node == undefined) return undefined;
  var _pos = _src.getLocalPosition();
  _node.setLocalPosition(new GM3D_Vec3(_pos.x, _pos.y, _pos.z));
  _node.setLocalScale(_src.getLocalScale().clone());
  _node.setLocalRotation(_src.getLocalRotation().clone());
  var _data = __poly_duplicate_prop_data(_en.data);

  if (_kind == "light") {
    _node.addComponent(new GM3D_LightComponent());
    __poly_light_apply(_node, _data);
  } else if (_kind == "camera") {
    _node.addComponent(new GM3D_CameraComponent());
    __poly_camera_apply(_node, _data);
  } else {
    _node.addComponent(new GM3D_EnvironmentVolumeComponent());
    __poly_env_apply(_node, _data);
  }

  _ed.rt.scene.update(0);
  var _pp = _node.getLocalPosition();
  __poly_kind_register(
    _ed,
    _node,
    _kind,
    "",
    _slabel,
    _data
  );

  if (__poly_hidden_get(_ed, _src)) __poly_hidden_set(_ed, _node, true);
  if (__poly_locked_get(_ed, _src)) __poly_locked_set(_ed, _node, true);
  __poly_cameras_mute(_ed);
  return _node;
}

// ---------------------------------------------------------------------------
// Clipboard (copy/cut/paste) and invert selection
// ---------------------------------------------------------------------------

// Snapshots current selection as descriptors (skips system nodes).
function __poly_clipboard_descs(_ed) {
  var _out = [];

  if (_ed == undefined || !is_array(_ed.sel)) return _out;

  for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) {
    var _d = __poly_node_to_descriptor(_ed, _ed.sel[_i]);

    if (_d != undefined) array_push(_out, _d);
  }

  return _out;
}

// Copies selection to the clipboard (no scene change, no undo).
function __poly_clipboard_copy(_ed) {
  if (_ed == undefined) return false;
  var _descs = __poly_clipboard_descs(_ed);

  if (array_length(_descs) == 0) return false;
  _ed.clipboard = { descs: _descs, cut: false };
  return true;
}

// Cuts selection to the clipboard (single undo entry with the delete).
function __poly_clipboard_cut(_ed) {
  if (_ed == undefined || !is_array(_ed.sel) || array_length(_ed.sel) == 0) return false;
  var _descs = __poly_clipboard_descs(_ed);

  if (array_length(_descs) == 0) return false;
  var _victims = [];

  for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) {
    if (_ed.rt != undefined && __poly_node_same(_ed.sel[_i], _ed.rt.cam)) continue;
    array_push(_victims, _ed.sel[_i]);
  }

  if (array_length(_victims) == 0) return false;
  var _before = __poly_history_snap(_ed);
  _ed.clipboard = { descs: _descs, cut: true };

  for (var _j = 0, _nv = array_length(_victims); _j < _nv; _j++) {
    __poly_spawn_unregister(_ed, _victims[_j]);
    __poly_destroy_subtree(_victims[_j]);
  }

  _ed.rt.scene.update(0);
  __poly_sel_clear(_ed);
  __poly_history_commit(_ed, _before);
  return true;
}

// Pastes clipboard content in place with fresh ids
// (single undo entry; unknown models are skipped, no commit when empty).
function __poly_clipboard_paste(_ed) {
  if (_ed == undefined) return false;
  var _cb = variable_struct_exists(_ed, "clipboard") ? _ed.clipboard : undefined;

  if (!is_struct(_cb) || !is_array(_cb.descs) || array_length(_cb.descs) == 0) return false;
  var _before = __poly_history_snap(_ed);
  var _rep = { placed: 0, failed: 0, err: "" };
  var _ids = [];

  for (var _i = 0, _n = array_length(_cb.descs); _i < _n; _i++) {
    var _d = json_parse(json_stringify(_cb.descs[_i]));
    _d.id = __poly_wrap_new(_ed);

    try {
      __poly_rebuild_place_one(_ed, _d, _rep);
      array_push(_ids, _d.id);
    } catch (_ex) {
      _rep.failed++;
    }
  }

  if (array_length(_ids) == 0) return false;
  var _nodes = [];

  for (var _k = 0, _nk = array_length(_ids); _k < _nk; _k++) {
    var _node = __poly_find_by_id(_ed, _ids[_k]);

    if (_node != undefined) array_push(_nodes, _node);
  }

  _ed.rt.scene.update(0);
  __poly_seq_reseed(_ed);
  __poly_cameras_mute(_ed);

  if (array_length(_nodes) > 0) __poly_sel_assign(_ed, _nodes);
  __poly_history_commit(_ed, _before);
  return true;
}

// Inverts selection over tracked roots (locked nodes are never picked up).
function __poly_invert_sel(_ed) {
  if (_ed == undefined) return false;
  var _all = __poly_root_list(_ed, false);
  var _out = [];

  for (var _i = 0, _n = array_length(_all); _i < _n; _i++) {
    var _node = _all[_i];

    if (_node == undefined || __poly_locked_get(_ed, _node)) continue;
    if (__poly_node_list_has(_ed.sel, _node)) continue;
    array_push(_out, _node);
  }

  __poly_sel_assign(_ed, _out);
  _ed.scene_anchor = undefined;
  return true;
}

// Selects all tracked root nodes (locked nodes excluded).
function __poly_select_all(_ed) {
  if (_ed == undefined) return false;
  var _all = __poly_root_list(_ed, false);
  var _out = [];

  for (var _i = 0, _n = array_length(_all); _i < _n; _i++) {
    var _node = _all[_i];

    if (_node == undefined || __poly_locked_get(_ed, _node)) continue;
    array_push(_out, _node);
  }

  __poly_sel_assign(_ed, _out);
  _ed.scene_anchor = undefined;
  return true;
}

// Focuses the Hierarchy or Models search field (Ctrl+F), whichever panel
// was focused last frame. No-op when neither is focused/open.
function __poly_focus_search(_ed) {
  if (_ed == undefined || !is_struct(_ed.imgui)) return false;
  var _ui = _ed.imgui;
  var _hier_foc = variable_struct_exists(_ui, "hier_focused") && _ui.hier_focused == true;
  var _models_foc = variable_struct_exists(_ui, "models_focused") && _ui.models_focused == true;

  if (_hier_foc && _ui.win_hier.open) {
    _ui.scene_focus_search = true;
    return true;
  }

  if (_models_foc && _ui.win_assets.open) {
    _ui.models_focus_search = true;
    return true;
  }

  return false;
}

// ---------------------------------------------------------------------------
// Focus
// ---------------------------------------------------------------------------

// Computes focus center from selection.
function __poly_focus_target(_ed) {
  var _n = array_length(_ed.sel);

  if (_n == 0) return undefined;
  var _mn = undefined;
  var _mx = undefined;

  for (var _i = 0; _i < _n; _i++) {
    var _box = __poly_node_aabb(_ed.sel[_i]);

    if (_box == undefined || !_box.valid) continue;

    if (_mn == undefined) {
      _mn = _box.min.clone();
      _mx = _box.max.clone();
    } else {
      _mn.x = min(_mn.x, _box.min.x);
      _mn.y = min(_mn.y, _box.min.y);
      _mn.z = min(_mn.z, _box.min.z);
      _mx.x = max(_mx.x, _box.max.x);
      _mx.y = max(_mx.y, _box.max.y);
      _mx.z = max(_mx.z, _box.max.z);
    }
  }

  if (_mn != undefined) {
    var _cx = (_mn.x + _mx.x) * 0.5;
    var _cy = (_mn.y + _mx.y) * 0.5;
    var _cz = (_mn.z + _mx.z) * 0.5;
    return {
      center: new GM3D_Vec3(_cx, _cy, _cz),
      mn: _mn,
      mx: _mx,
      radius: 1.0,
    };
  }

  var _pivot = __poly_gizmo_pivot(_ed.sel);

  if (_pivot == undefined) return undefined;
  return { center: _pivot, radius: 1.0 };
}

// Computes a horizontal right vector for a view forward.
function __poly_view_right(_fwd) {
  var _rx = _fwd.z;
  var _rz = -_fwd.x;
  var _len = sqrt(_rx * _rx + _rz * _rz);

  if (_len < 0.0001) return [ 1.0, 0.0, 0.0 ];
  return [ _rx / _len, 0.0, _rz / _len ];
}

// Computes fit distance for a focus target.
function __poly_fit_dist(_ed, _t, _fwd, _fov) {
  if (!variable_struct_exists(_t, "mn")) return (_t.radius / max(sin(_fov * 0.5), 0.1)) * 1.2 + 0.3;
  var _back = [ -_fwd.x, -_fwd.y, -_fwd.z ];
  var _right = __poly_view_right(_fwd);
  var _up = [
    _right[1] * _back[2] - _right[2] * _back[1],
    _right[2] * _back[0] - _right[0] * _back[2],
    _right[0] * _back[1] - _right[1] * _back[0],
  ];
  var _ext = [ (_t.mx.x - _t.mn.x) * 0.5, (_t.mx.y - _t.mn.y) * 0.5, (_t.mx.z - _t.mn.z) * 0.5 ];
  var _h = _ext[0] * abs(_up[0]) + _ext[1] * abs(_up[1]) + _ext[2] * abs(_up[2]);
  var _w = _ext[0] * abs(_right[0]) + _ext[1] * abs(_right[1]) + _ext[2] * abs(_right[2]);
  var _d = _ext[0] * abs(_back[0]) + _ext[1] * abs(_back[1]) + _ext[2] * abs(_back[2]);
  var _tan_y = max(tan(_fov * 0.5), 0.05);
  var _aspect = 16.0 / 9.0;

  if (_ed.gw > 0 && _ed.gh > 0) _aspect = _ed.gw / _ed.gh;
  var _tan_x = _tan_y * max(_aspect, 0.1);
  return max(_h / _tan_y, _w / _tan_x) * 1.2 + _d + 0.3;
}

// Moves camera to frame selection.
function __poly_focus_selection(_ed) {
  var _t = __poly_focus_target(_ed);

  if (_t == undefined) return false;
  if (_ed.rt == undefined) return false;
  var _vp = __poly_viewport(_ed);
  var _fwd = __poly_view_forward_cached(_ed);
  var _fov = clamp(_vp.fovY, 0.05, 3.1);
  var _dist = clamp(__poly_fit_dist(_ed, _t, _fwd, _fov), 1.5, 150.0);
  var _to = new GM3D_Vec3(
    _t.center.x + _fwd.x * _dist,
    _t.center.y + _fwd.y * _dist,
    _t.center.z + _fwd.z * _dist
  );
  var _pos = _ed.rt.cam.getLocalPosition();
  var _rot = _ed.rt.cam.getLocalRotation();
  _ed.cam_anim = {
    t: 0,
    dur: 0.5,
    q0: [ _rot.x, _rot.y, _rot.z, _rot.w ],
    q1: [ _rot.x, _rot.y, _rot.z, _rot.w ],
    p0: [ _pos.x, _pos.y, _pos.z ],
    p1: [ _to.x, _to.y, _to.z ],
  };
  return true;
}

// Selects and focuses single node.
function __poly_focus_node(_ed, _node) {
  if (_node == undefined) return false;
  __poly_sel_assign(_ed, [ _node ]);
  return __poly_focus_selection(_ed);
}

// ---------------------------------------------------------------------------
// Scene-list selection
// ---------------------------------------------------------------------------

// Selects single scene node.
function __poly_scene_select(_ed, _node) {
  if (__poly_locked_get(_ed, _node)) return;
  __poly_sel_assign(_ed, [ _node ]);
  _ed.scene_anchor = _node;
}

// Toggles single node in current selection (Shift+Click).
function __poly_scene_toggle(_ed, _node) {
  if (__poly_locked_get(_ed, _node) && !__poly_sel_has(_ed, _node)) return;
  __poly_sel_toggle(_ed, _node);
  _ed.giz.drag = -1;
  _ed.scene_anchor = _node;
  __poly_sel_apply_tool(_ed);
}

// Extracts the node from a hierarchy row ({ node, ... } or bare node).
function __poly_row_node(_item) {
  if (is_struct(_item) && variable_struct_exists(_item, "node")) return _item.node;
  return _item;
}

// Selects visible range between anchor and clicked node (Ctrl+Click).
function __poly_scene_range(
  _ed,
  _visible,
  _anchor_node,
  _clicked_node,
  _additive
  ) {
  if (
    !is_array(_visible) ||
    array_length(_visible) == 0 ||
    _clicked_node == undefined
    ) {
    return false;
  }

  var _ai = -1;
  var _ci = -1;

  for (var _i = 0, _n = array_length(_visible); _i < _n; _i++) {
    var _node = __poly_row_node(_visible[_i]);

    if (__poly_node_same(_node, _anchor_node)) _ai = _i;
    if (__poly_node_same(_node, _clicked_node)) _ci = _i;
  }

  if (_ci < 0) return false;

  if (_ai < 0) {
    __poly_scene_select(_ed, _clicked_node);
    return true;
  }

  var _from = min(_ai, _ci);
  var _to = max(_ai, _ci);

  if (!_additive) _ed.sel = [];

  for (var _k = _from; _k <= _to; _k++) {
    var _cand = __poly_row_node(_visible[_k]);

    if (__poly_locked_get(_ed, _cand)) continue;
    if (!__poly_sel_has(_ed, _cand)) array_push(_ed.sel, _cand);
  }

  _ed.giz.drag = -1;
  __poly_sel_apply_tool(_ed);
  return true;
}

// Commits rubber-band rectangle selection over hierarchy rows.
function __poly_hier_rect_commit(_ed, _y0, _y1) {
  if (!is_array(_ed.hier_rows)) return;
  var _rh = _ed.hier_row_h;

  if (!is_numeric(_rh) || _rh <= 0) return;
  var _add = keyboard_check(vk_shift);
  var _picked = [];
  var _n = array_length(_ed.hier_rows);

  for (var _i = 0; _i < _n; _i++) {
    var _sy = _ed.hier_row_y[$ string(_i)];

    if (_sy == undefined) continue;
    if (max(_y0, _sy) > min(_y1, _sy + _rh)) continue;
    var _nd = __poly_row_node(_ed.hier_rows[_i]);

    if (_nd == undefined || __poly_locked_get(_ed, _nd)) continue;
    if (_add && __poly_sel_has(_ed, _nd)) continue;
    array_push(_picked, _nd);
  }

  if (_add) {
    if (array_length(_picked) == 0) return;
    for (var _k = 0, _nk = array_length(_picked); _k < _nk; _k++) array_push(_ed.sel, _picked[_k]);
  } else {
    _ed.sel = _picked;
  }

  _ed.giz.drag = -1;

  if (array_length(_picked) > 0) _ed.scene_anchor = _picked[array_length(_picked) - 1];
  _ed.scene_click_idx = -1;
  _ed.scene_click_time = -10000;
  __poly_sel_apply_tool(_ed);
}

// Handles scene list click, Shift toggle and Ctrl range, plus doubleclick.
function __poly_scene_click(_ed, _nd, _row, _visible = undefined) {
  if (__poly_locked_get(_ed, _nd)) return;
  var _now = current_time;
  var _ctrl = keyboard_check(vk_control);
  var _shift = keyboard_check(vk_shift);

  if (!variable_struct_exists(_ed, "scene_anchor")) _ed.scene_anchor = undefined;

  if (_shift && !_ctrl) {
    __poly_scene_toggle(_ed, _nd);
    _ed.scene_click_idx = _row;
    _ed.scene_click_time = _now;
    return;
  }

  if (_ctrl && is_array(_visible)) {
    if (__poly_scene_range(_ed, _visible, _ed.scene_anchor, _nd, _shift)) {
      _ed.scene_click_idx = _row;
      _ed.scene_click_time = _now;
      return;
    }
  }

  if (
    _ed.scene_click_idx == _row &&
    _now - _ed.scene_click_time <= 400 &&
    !_ctrl &&
    !_shift
    ) {
    __poly_scene_select(_ed, _nd);
    __poly_focus_node(_ed, _nd);
    _ed.scene_click_idx = -1;
    _ed.scene_click_time = -10000;
  } else {
    __poly_scene_select(_ed, _nd);
    _ed.scene_click_idx = _row;
    _ed.scene_click_time = _now;
  }
}

// Commits a custom instance name with undo.
function __poly_scene_commit_rename(_ed, _node, _new_label) {
  var _before = __poly_history_snap(_ed);
  var _en = __poly_registry_find(_ed, _node);

  if (_en != undefined) _en.label = _new_label;
  __poly_history_commit(_ed, _before);
}

// Applies pending scene list actions.
function __poly_scene_list_commit(_ed, _ren, _foc, _dup, _del, _cop = false, _cut = false, _pas = false) {
  if (_ren != undefined) {
    __poly_scene_select(_ed, _ren);
    __poly_rename_begin(_ed, _ren);
  }

  if (_foc != undefined) __poly_focus_node(_ed, _foc);

  if (_dup != undefined) {
    if (!__poly_sel_has(_ed, _dup) || array_length(_ed.sel) <= 1) __poly_scene_select(_ed, _dup);
    __poly_duplicate_sel(_ed);
  }

  if (_del != undefined) {
    if (!__poly_sel_has(_ed, _del) || array_length(_ed.sel) <= 1) __poly_scene_select(_ed, _del);
    __poly_delete_ask(_ed);
  }

  if (_cop == true) __poly_clipboard_copy(_ed);

  if (_cut == true) __poly_clipboard_cut(_ed);

  if (_pas == true) __poly_clipboard_paste(_ed);
}

// ---------------------------------------------------------------------------
// Inspector axis edit
// ---------------------------------------------------------------------------

// Snaps every selected node position to the grid step (undoable).
function __poly_push_sel_to_grid(_ed) {
  if (array_length(_ed.sel) == 0) return;
  var _step = __poly_snap_step(_ed);
  var _before = __poly_history_snap(_ed);

  for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) {
    if (!__poly_tool_allowed(_ed, _ed.sel[_i], PolygonEditorTool.Translate) || __poly_hidden_get(_ed, _ed.sel[_i])) continue;
    var _pos = _ed.sel[_i].getLocalPosition().clone();

    if (!variable_struct_exists(_ed, "snap_x") || _ed.snap_x) _pos.x = __poly_snap(_pos.x, _step);
    if (!variable_struct_exists(_ed, "snap_y") || _ed.snap_y) _pos.y = __poly_snap(_pos.y, _step);
    if (!variable_struct_exists(_ed, "snap_z") || _ed.snap_z) _pos.z = __poly_snap(_pos.z, _step);
    _ed.sel[_i].setLocalPosition(_pos);
  }

  __poly_history_commit(_ed, _before);
}

// Applies position rotation scale axis edit (mode 0/1/2, axis 0/1/2).
function __poly_apply_axis(_ed, _mode, _idx, _v) {
  _ed.view_dirty = true;

  for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) {
    var _node = _ed.sel[_i];

    if (_mode == 0) {
      var _pos = _node.getLocalPosition().clone();

      if (_idx == 0) {
        _pos.x = _v;
      } else if (_idx == 1) {
        _pos.y = _v;
      } else {
        _pos.z = _v;
      }

      _node.setLocalPosition(_pos);
    } else if (_mode == 1) {
      var _euler = __poly_quat_to_euler(_node.getLocalRotation());
      _euler[_idx] = degtorad(_v);
      _node.setLocalRotation(__poly_euler_to_quat(_euler[0], _euler[1], _euler[2]));
    } else {
      var _sca = _node.getLocalScale().clone();

      if (_idx == 0) {
        _sca.x = max(_v, 0.01);
      } else if (_idx == 1) {
        _sca.y = max(_v, 0.01);
      } else {
        _sca.z = max(_v, 0.01);
      }

      _node.setLocalScale(_sca);
    }
  }
}
