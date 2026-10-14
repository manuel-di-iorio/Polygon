// poly_serialize — descriptors, validation, rebuild, scene file IO.

// ---------------------------------------------------------------------------
// Paths
// ---------------------------------------------------------------------------

// Resolves scene path to absolute path.
function __poly_scene_path(_ed) {
  var _file = _ed.scene_file;

  if (_file == undefined || _file == "") return "";
  var _abs = string_pos(":", _file) > 0 || string_copy(_file, 1, 2) == "\\\\" || string_copy(_file, 1, 1) == "/";

  if (_abs) return _file;
  return working_directory + _file;
}

// Creates parent directory for path.
function __poly_ensure_dir(_path) {
  var _at = max(string_last_pos("\\", _path), string_last_pos("/", _path));

  if (_at > 1) directory_create(string_copy(_path, 1, _at - 1));
}

// ---------------------------------------------------------------------------
// Descriptors
// ---------------------------------------------------------------------------

// Converts node to serializable descriptor skipping system.
function __poly_node_to_descriptor(_ed, _node) {
  if (__poly_is_grid(_ed, _node)) return undefined;
  if (_ed != undefined && variable_struct_exists(_ed, "rt") && is_struct(_ed.rt)) if (variable_struct_exists(_ed.rt, "cam") && __poly_node_same(_node, _ed.rt.cam)) return undefined;
  if (_ed != undefined && variable_struct_exists(_ed, "drag_preview") && __poly_node_same(_node, _ed.drag_preview)) return undefined;
  return __poly_node_desc(_ed, _node);
}

// Converts tracked node to descriptor.
function __poly_node_desc(_ed, _node) {
  var _en = __poly_registry_find(_ed, _node);

  if (_en == undefined) return undefined;
  var _kind = __poly_kind_of(_ed, _node);

  if (_kind == undefined) return undefined;
  if (_kind == "light" || _kind == "camera" || _kind == "environment") return __poly_prop_desc(_ed, _node, _kind);
  var _asset = __poly_asset_desc(_ed, _node);

  if (_asset == undefined) return undefined;
  var _desc = {
    kind: "instance",
    id: _asset.id,
    assetId: _asset.asset,
    transform: _asset.transform,
    shadows: _asset.shadows,
  };

  if (is_string(_asset.label) && _asset.label != "") _desc.label = _asset.label;
  return _desc;
}

// Reads prop data from registry entry, else live from the node.
function __poly_prop_data(_ed, _node, _kind) {
  var _en = __poly_registry_find(_ed, _node);

  if (_en != undefined && is_struct(_en.data)) return _en.data;

  if (_kind == "light") {
    return __poly_light_read(_node);
  } else if (_kind == "camera") {
    return __poly_camera_read(_node);
  } else {
    return __poly_env_read(_node);
  }
}

// File<->internal key map per kind. k: internal key, j: file key
// (dotted for nested), b: desc bool mode (1 = ==true), br: rebuild bool
// mode (1 = ==true, 2 = !=false), arr: copy as 3-array, gt/ge: rebuild
// skips the source unless _v > gt / _v >= ge (defaults survive).
function __poly_prop_keymap() {
  return {
    light: [
      { k: "type", j: "type" },
      { k: "color", j: "color", arr: 3 },
      { k: "intensity", j: "intensity" },
      { k: "range", j: "range" },
      { k: "inner", j: "innerCone" },
      { k: "outer", j: "outerCone" },
      { k: "enabled", j: "enabled", b: 1, br: 2 },
      { k: "shadow", j: "shadow.enabled", b: 1, br: 1 },
      { k: "shadowRes", j: "shadow.resolution", gt: 0 },
      { k: "shadowDist", j: "shadow.distance", gt: 0 },
      { k: "shadowNormal", j: "shadow.normalOffset", ge: 0 },
    ],
    camera: [
      { k: "projection", j: "projection" },
      { k: "fov", j: "fovY" },
      { k: "ow", j: "orthoWidth" },
      { k: "oh", j: "orthoHeight" },
      { k: "near", j: "near" },
      { k: "far", j: "far" },
      { k: "enabled", j: "enabled", b: 1, br: 2 },
    ],
    environment: [
      { k: "size", j: "size", arr: 3 },
      { k: "ambient", j: "ambient", arr: 3 },
      { k: "fog", j: "fogEnabled", b: 1, br: 1 },
      { k: "fogcolor", j: "fogColor", arr: 3 },
      { k: "fogstart", j: "fogStart" },
      { k: "fogend", j: "fogEnd" },
      { k: "enabled", j: "enabled", b: 1, br: 2 },
    ],
  };
}

// Sets a (possibly dotted) key on a descriptor struct.
function __poly_desc_set(_o, _j, _v) {
  var _dot = string_pos(".", _j);

  if (_dot <= 0) {
    _o[$ _j] = _v;
    return;
  }

  var _head = string_copy(_j, 1, _dot - 1);
  var _tail = string_delete(_j, 1, _dot);

  if (!variable_struct_exists(_o, _head) || !is_struct(_o[$ _head])) _o[$ _head] = {};
  _o[$ _head][$ _tail] = _v;
}

// Reads a (possibly dotted) key from a descriptor struct (undefined when absent).
function __poly_desc_get(_o, _j) {
  var _dot = string_pos(".", _j);

  if (_dot <= 0) return is_struct(_o) ? _o[$ _j] : undefined;
  if (!is_struct(_o)) return undefined;
  var _head = _o[$ string_copy(_j, 1, _dot - 1)];

  if (!is_struct(_head)) return undefined;
  return _head[$ string_delete(_j, 1, _dot)];
}

// Builds the file sub-descriptor for a kind from internal data.
function __poly_prop_subdesc(_pd, _kind) {
  var _map = __poly_prop_keymap()[$ _kind];
  var _out = {};

  for (var _i = 0, _n = array_length(_map); _i < _n; _i++) {
    var _e = _map[_i];
    var _v = _pd[$ _e.k];

    if (_e[$ "arr"] == 3) _v = [ _v[0], _v[1], _v[2] ];
    else if (_e[$ "b"] == 1)  _v = (_v == true);
    __poly_desc_set(_out, _e.j, _v);
  }

  return _out;
}

// Builds the light sub-descriptor.
function __poly_light_desc(_pd) {
  return __poly_prop_subdesc(_pd, "light");
}

// Builds the camera sub-descriptor.
function __poly_camera_desc(_pd) {
  return __poly_prop_subdesc(_pd, "camera");
}

// Builds the environment sub-descriptor.
function __poly_env_desc(_pd) {
  return __poly_prop_subdesc(_pd, "environment");
}

// Builds light camera environment descriptor.
function __poly_prop_desc(_ed, _node, _kind) {
  var _en = __poly_registry_find(_ed, _node);
  var _id = (_en != undefined && is_string(_en.id)) ? _en.id : _node.name;
  var _pos = _node.getLocalPosition();
  var _rot = _node.getLocalRotation();
  var _sca = _node.getLocalScale();

  if (_kind == "camera") _rot = __poly_quat_no_roll(_rot);
  var _desc = {
    kind: _kind,
    id: _id,
    assetId: "",
    transform: {
      position: [ _pos.x, _pos.y, _pos.z ],
      rotation: [ _rot.x, _rot.y, _rot.z, _rot.w ],
      scale: [ _sca.x, _sca.y, _sca.z ],
    },
  };

  if (_en != undefined && is_string(_en.label) && _en.label != "") _desc.label = _en.label;
  var _data = __poly_prop_data(_ed, _node, _kind);

  if (_kind == "light") {
    _desc.light = __poly_light_desc(_data);
  } else if (_kind == "camera") {
    _desc.camera = __poly_camera_desc(_data);
  } else {
    _desc.environment = __poly_env_desc(_data);
  }

  return _desc;
}

// Serializes tracked nodes to descriptor array.
function __poly_serialize_scene(_ed) {
  var _nodes = __poly_tracked_nodes(_ed);
  var _out = [];

  for (var _i = 0, _n = array_length(_nodes); _i < _n; _i++) {
    var _desc = __poly_node_to_descriptor(_ed, _nodes[_i]);

    if (_desc != undefined) array_push(_out, _desc);
  }

  return _out;
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

// Checks for a real-number field.
function __poly_req_real(_s, _key) {
  return variable_struct_exists(_s, _key) && is_real(_s[$ _key]);
}

// Checks for a three-element array field.
function __poly_req_vec3(_s, _key) {
  return variable_struct_exists(_s, _key) && is_array(_s[$ _key]) && array_length(_s[$ _key]) == 3;
}

// Checks for three number array.
function __poly_is_num(_d, _key, _n) {
  if (!variable_struct_exists(_d, _key)) return false;
  var _arr = _d[$ _key];

  if (!is_array(_arr) || array_length(_arr) != _n) return false;

  for (var _i = 0; _i < _n; _i++) if (!is_real(_arr[_i])) return false;
  return true;
}

// Checks for three number array.
function __poly_is_num3(_d, _key) {
  return __poly_is_num(_d, _key, 3);
}

// Checks for four number array.
function __poly_is_num4(_d, _key) {
  return __poly_is_num(_d, _key, 4);
}

// Validates light descriptor structure.
function __poly_is_light_struct(_d) {
  if (!variable_struct_exists(_d, "light") || !is_struct(_d.light)) return false;
  var _lit = _d.light;

  if (!variable_struct_exists(_lit, "type") || !is_string(_lit.type)) return false;
  if (_lit.type != "directional" && _lit.type != "point" && _lit.type != "spot") return false;
  if (!__poly_req_vec3(_lit, "color")) return false;
  if (!__poly_req_real(_lit, "intensity") || !__poly_req_real(_lit, "range")) return false;
  if (!__poly_req_real(_lit, "innerCone") || !__poly_req_real(_lit, "outerCone")) return false;

  if (variable_struct_exists(_lit, "shadow")) {
    if (!is_struct(_lit.shadow)) return false;
    var _sh = _lit.shadow;

    if (!variable_struct_exists(_sh, "enabled") || !is_bool(_sh.enabled)) return false;
    if (!__poly_req_real(_sh, "resolution") || !__poly_req_real(_sh, "distance") || !__poly_req_real(_sh, "normalOffset")) return false;
  }

  return true;
}

// Validates camera descriptor structure.
function __poly_is_camera_struct(_d) {
  if (!variable_struct_exists(_d, "camera") || !is_struct(_d.camera)) return false;
  var _cam = _d.camera;

  if (!variable_struct_exists(_cam, "projection") || !is_string(_cam.projection)) return false;
  if (_cam.projection != "perspective" && _cam.projection != "ortho") return false;
  if (!__poly_req_real(_cam, "fovY") || !__poly_req_real(_cam, "orthoWidth") || !__poly_req_real(_cam, "orthoHeight")) return false;
  if (!__poly_req_real(_cam, "near") || !__poly_req_real(_cam, "far")) return false;
  return true;
}

// Validates environment descriptor structure.
function __poly_is_env_struct(_d) {
  if (!variable_struct_exists(_d, "environment") || !is_struct(_d.environment)) return false;
  var _env = _d.environment;

  if (!__poly_req_vec3(_env, "size") || !__poly_req_vec3(_env, "ambient") || !__poly_req_vec3(_env, "fogColor")) return false;
  if (!__poly_req_real(_env, "fogStart") || !__poly_req_real(_env, "fogEnd")) return false;
  return true;
}

// Validates scene descriptor array structure (strict v1: kind, id and
// assetId are required; "label" is an optional custom instance name).
function __poly_validate_descs(_nodes) {
  if (!is_array(_nodes)) return false;

  for (var _i = 0, _n = array_length(_nodes); _i < _n; _i++) {
    var _desc = _nodes[_i];

    if (!is_struct(_desc)) return false;
    if (!variable_struct_exists(_desc, "kind") || !is_string(_desc.kind)) return false;
    if (!variable_struct_exists(_desc, "id") || !is_string(_desc.id) || _desc.id == "") return false;
    if (variable_struct_exists(_desc, "label") && !is_string(_desc.label)) return false;
    if (!variable_struct_exists(_desc, "assetId") || !is_string(_desc.assetId)) return false;
    var _kind = _desc.kind;

    if (!variable_struct_exists(_desc, "transform") || !is_struct(_desc.transform)) return false;
    var _t = _desc.transform;

    if (!__poly_is_num3(_t, "position") || !__poly_is_num4(_t, "rotation") || !__poly_is_num3(_t, "scale")) return false;

    if (_kind == "instance") {
      if (!__poly_validate_asset_desc(_desc)) return false;
    } else if (_kind == "light") {
      if (!__poly_is_light_struct(_desc)) return false;
    } else if (_kind == "camera") {
      if (!__poly_is_camera_struct(_desc)) return false;
    } else if (_kind == "environment") {
      if (!__poly_is_env_struct(_desc)) return false;
    } else {
      return false;
    }
  }

  return true;
}

// Validates asset descriptor flags (asset key required, non-empty).
function __poly_validate_asset_desc(_desc) {
  if (!variable_struct_exists(_desc, "assetId") || !is_string(_desc.assetId) || _desc.assetId == "") return false;

  if (variable_struct_exists(_desc, "shadows")) {
    if (!is_struct(_desc.shadows)) return false;
    if (!variable_struct_exists(_desc.shadows, "cast") || !is_bool(_desc.shadows.cast)) return false;
    if (!variable_struct_exists(_desc.shadows, "receive") || !is_bool(_desc.shadows.receive)) return false;
  }

  return true;
}

// ---------------------------------------------------------------------------
// Rebuild
// ---------------------------------------------------------------------------

// Clears tracked scene content, remembering hidden/locked ids.
function __poly_rebuild_clear(_ed) {
  var _tracked = __poly_root_tracked(_ed);
  var _hidden = [];
  var _locked = [];

  for (var _i = 0, _n = array_length(_tracked); _i < _n; _i++) {
    var _en = __poly_registry_find(_ed, _tracked[_i]);

    if (_en != undefined && is_string(_en.id)) {
      if (_en.hidden == true) array_push(_hidden, _en.id);
      if (_en.locked == true) array_push(_locked, _en.id);
    }

    __poly_destroy_subtree(_tracked[_i]);
  }

  _ed.rt.scene.update(0);
  __poly_reg_clear(_ed);
  _ed.view_dirty = true;

  if (variable_struct_exists(_ed, "outline") && is_struct(_ed.outline)) {
    _ed.outline.cheap = undefined;
    _ed.outline.has = false;
  }

  return { hidden: _hidden, locked: _locked };
}

// Places one asset descriptor, applying saved shadow flags.
// The id is claimed before the wrapper is born (collisions get fresh).
function __poly_rebuild_place_asset(_ed, _p, _key) {
  var _model = __poly_asset_find(_ed, _key);

  if (_model == undefined) throw "unknown model '" + string(_key) + "'";
  var _flags = undefined;

  if (variable_struct_exists(_p, "shadows") && is_struct(_p.shadows)) {
    _flags = { castShadows: _p.shadows.cast == true, receiveShadows: _p.shadows.receive == true };
  }

  var _wrap = __poly_spawn(_ed, {
    kind: "instance",
    asset: _key,
    model: _model,
    pos: _p.transform.position,
    rotation: _p.transform.rotation,
    scale: _p.transform.scale,
    label: _p[$ "label"],
    id: __poly_wrap_claim(_ed, _p.id),
    data: _flags,
  });

  if (_wrap == undefined) throw "place failed for '" + string(_key) + "'";
}

// Restores hidden/locked states by id after rebuild.
function __poly_rebuild_restore_states(_ed, _states) {
  var _roots = __poly_root_tracked(_ed);

  for (var _i = 0, _n = array_length(_roots); _i < _n; _i++) {
    var _en = __poly_registry_find(_ed, _roots[_i]);

    if (_en == undefined || !is_string(_en.id)) continue;
    if (array_contains(_states.hidden, _en.id)) __poly_hidden_set(_ed, _roots[_i], true);
    if (array_contains(_states.locked, _en.id)) __poly_locked_set(_ed, _roots[_i], true);
  }
}

// Clears scene and rebuilds from descriptors.
function __poly_rebuild(_ed, _nodes) {
  _ed.unlit_quiet = false;
  var _report = { placed: 0, failed: 0, err: "" };

  if (!is_array(_nodes)) _nodes = [];
  if (!__poly_validate_descs(_nodes)) throw "invalid descriptors";
  __poly_drop_preview_clear(_ed);
  var _states = __poly_rebuild_clear(_ed);
  _ed.unlit_quiet = true;

  for (var _i = 0, _n = array_length(_nodes); _i < _n; _i++) {
    __poly_rebuild_place_one(_ed, _nodes[_i], _report);
  }

  _ed.unlit_quiet = false;
  _ed.rt.scene.update(0);
  __poly_seq_reseed(_ed);
  __poly_gamecam_ensure(_ed);
  __poly_cameras_mute(_ed);
  __poly_unlit_apply(_ed);
  __poly_rebuild_restore_states(_ed, _states);

  return _report;
}

// Places one descriptor during (re)build (shared by sync + chunked load).
function __poly_rebuild_place_one(_ed, _p, _report) {
  if (!is_struct(_p)) return;
  var _kind = _p.kind;

  if (_kind == "light" || _kind == "camera" || _kind == "environment") {
    if (__poly_rebuild_prop(_ed, _p, _kind) == undefined) throw "place failed for '" + string(_p.id) + "'";
    _report.placed++;
    return;
  }

  if (_kind != "instance") throw "unknown kind '" + string(_kind) + "'";
  __poly_rebuild_place_asset(_ed, _p, _p.assetId);
  _report.placed++;
}

// Loads scene data from an absolute path (JSON v1 or PLYB binary).
// Returns { seq, assets, nodes } or undefined.
function __poly_load_data_file(_abs) {
  if (!is_string(_abs) || _abs == "" || !file_exists(_abs)) return undefined;
  // Binary first when the extension (or magic) says so.
  if (__poly_bin_is_path(_abs) || __poly_bin_has_magic(_abs)) {
    var _bin = __poly_bin_load_data(_abs);

    if (_bin != undefined) return _bin;
    // Fall through to JSON: a mislabeled file still gets a chance.
  }

  var _json = __poly_read_text_file(_abs);

  if (_json == "") return undefined;
  var _data = undefined;

  try {
    _data = json_parse(_json);
  } catch (_ex) {
    return undefined;
  }

  var _ok = is_struct(_data) && _data.version == 1 && variable_struct_exists(_data, "nodes") && is_array(_data.nodes);

  if (!_ok) return undefined;
  return { seq: _data[$ "seq"], assets: _data[$ "assets"], nodes: _data.nodes };
}

// Starts a chunked scene load: parses now, places nodes across steps so
// the Load dialog can show progress instead of freezing. Returns "" on
// start, else an error message (same cases as the sync load).
function __poly_load_scene_begin(_ed) {
  var _path = __poly_scene_path(_ed);

  if (_path == "" || !file_exists(_path)) {
    // Fallback to the other extension (radio may point at the wrong one).
    var _alt = __poly_scene_path_as(_path, __poly_scene_fmt_of(_path) == "bin" ? "json" : "bin");

    if (_alt == "" || !file_exists(_alt)) return "missing";
    _ed.scene_file = __poly_scene_path_as(_ed.scene_file, __poly_scene_fmt_of(_alt));
    _path = _alt;
  }

  var _file = __poly_load_data_file(_path);

  if (_file == undefined) return "invalid";
  var _nodes = _file.nodes;

  if (!__poly_validate_descs(_nodes)) return "invalid";

  if (is_real(_file[$ "seq"])) {
    __poly_reg_ensure(_ed);
    _ed.id_seq = max(_ed.id_seq, floor(_file.seq));
  }

  __poly_drop_preview_clear(_ed);
  _ed.unlit_quiet = false;
  var _states = __poly_rebuild_clear(_ed);
  _ed.unlit_quiet = true;
  _ed.asset_meta = __poly_file_assets(_file);
  __poly_history_clear(_ed);
  _ed.load_job = { nodes: _nodes, idx: 0, report: { placed: 0, failed: 0, err: "" }, states: _states };
  return "";
}

// Places up to _budget pending nodes. Returns true when the load is done.
function __poly_load_scene_pump(_ed, _budget = 48) {
  if (!variable_struct_exists(_ed, "load_job") || !is_struct(_ed.load_job)) return true;
  var _job = _ed.load_job;
  var _n = array_length(_job.nodes);
  var _stop = min(_n, _job.idx + max(1, _budget));

  while (_job.idx < _stop) {
    try {
      __poly_rebuild_place_one(_ed, _job.nodes[_job.idx], _job.report);
    } catch (_ex) {
      _job.report.failed++;
    }

    _job.idx++;
  }

  if (_job.idx < _n) return false;
  __poly_load_scene_finish(_ed);
  return true;
}

// Completes a chunked load (same tail as the sync rebuild).
function __poly_load_scene_finish(_ed) {
  var _job = _ed.load_job;
  _ed.load_job = undefined;
  _ed.unlit_quiet = false;
  _ed.rt.scene.update(0);
  __poly_seq_reseed(_ed);
  __poly_gamecam_ensure(_ed);
  __poly_cameras_mute(_ed);
  __poly_unlit_apply(_ed);
  __poly_rebuild_restore_states(_ed, _job.states);
  // Files rarely carry sun/env: without them the
  // exterior renders pitch black. Same ensure as import/new scene.
  if (__poly_light_count(_ed) == 0) __poly_default_sun(_ed);
  if (__poly_env_node(_ed) == undefined) __poly_create_env(_ed);
  __poly_viewcam_seed(_ed);
  _ed.sel = [];
  _ed.giz.drag = -1;
  _ed.giz.hover = -1;
  __poly_history_clear(_ed);
  _ed.dirty = false;
  _ed.scene_dlg = undefined;
}

// Reads internal data for a kind from a file sub-descriptor
// (defaults + mapped overrides; dotted keys resolve nesting).
function __poly_rebuild_data(_p, _kind) {
  var _data = _kind == "light" ? __poly_light_defaults()
    : _kind == "camera" ? __poly_camera_defaults() : __poly_env_defaults();
  var _sub = is_struct(_p) ? _p[$ _kind] : undefined;

  if (!is_struct(_sub)) return _data;
  var _map = __poly_prop_keymap()[$ _kind];

  for (var _i = 0, _n = array_length(_map); _i < _n; _i++) {
    var _e = _map[_i];
    var _v = __poly_desc_get(_sub, _e.j);

    if (_v == undefined) continue;

    if (_e[$ "arr"] == 3) {
      if (is_array(_v) && array_length(_v) == 3) _data[$ _e.k] = [ _v[0], _v[1], _v[2] ];
      continue;
    }

    if (_e[$ "gt"] != undefined && !(is_real(_v) && _v > _e[$ "gt"])) continue;
    if (_e[$ "ge"] != undefined && !(is_real(_v) && _v >= _e[$ "ge"])) continue;

    if (_e[$ "br"] == 1) _data[$ _e.k] = (_v == true);
    else if (_e[$ "br"] == 2)  _data[$ _e.k] = (_v != false);
    else  _data[$ _e.k] = _v;
  }

  return _data;
}

// Reads light data from a descriptor (defaults + overrides).
function __poly_rebuild_light_data(_p) {
  return __poly_rebuild_data(_p, "light");
}

// Reads camera data from a descriptor.
function __poly_rebuild_camera_data(_p) {
  return __poly_rebuild_data(_p, "camera");
}

// Reads environment data from a descriptor.
function __poly_rebuild_env_data(_p) {
  return __poly_rebuild_data(_p, "environment");
}

// Rebuilds light camera environment node (wrapper carries id).
function __poly_rebuild_prop(_ed, _p, _kind) {
  var _data = undefined;

  if (_kind == "light") {
    _data = __poly_rebuild_light_data(_p);
  } else if (_kind == "camera") {
    _data = __poly_rebuild_camera_data(_p);
  } else {
    _data = __poly_rebuild_env_data(_p);
  }

  var _t = is_struct(_p[$ "transform"]) ? _p.transform : {};
  var _rot = _t[$ "rotation"];

  if (_kind == "camera") {
    var _nr = __poly_quat_no_roll(__poly_quat_from_array(_t[$ "rotation"]));
    _rot = [ _nr.x, _nr.y, _nr.z, _nr.w ];
  }

  var _node = __poly_spawn(_ed, {
    kind: _kind,
    pos: _t[$ "position"],
    rotation: _rot,
    scale: _t[$ "scale"],
    label: _p[$ "label"],
    id: __poly_wrap_claim(_ed, _p.id),
    data: _data,
  });

  if (_node == undefined) return undefined;
  if (_kind == "environment") __poly_hidden_set(_ed, _node, true);
  if (_kind == "light" && is_struct(_data) && variable_struct_exists(_data, "type") && _data.type == "directional") __poly_hidden_set(_ed, _node, true);
  return _node;
}

// ---------------------------------------------------------------------------
// Load and save
// ---------------------------------------------------------------------------

// Builds the top-level per-model file map: every asset referenced by the
// scene gets a { type: "model" } entry, overlaid with stored bindings
// (actor, ...). Actors without an object set are pruned: only a set
// object counts as a binding.
function __poly_write_file_assets(_ed) {
  var _out = {};
  var _tracked = __poly_root_tracked(_ed);

  for (var _i = 0, _n = array_length(_tracked); _i < _n; _i++) {
    var _en = __poly_registry_find(_ed, _tracked[_i]);

    if (_en == undefined || !is_string(_en.asset) || _en.asset == "") continue;
    if (!variable_struct_exists(_out, _en.asset)) _out[$ _en.asset] = { type: "model" };
  }

  if (variable_struct_exists(_ed, "asset_meta") && is_struct(_ed.asset_meta)) {
    var _keys = variable_struct_get_names(_ed.asset_meta);

    for (var _j = 0, _m = array_length(_keys); _j < _m; _j++) {
      var _mv = _ed.asset_meta[$ _keys[_j]];

      if (!is_struct(_mv)) continue;
      if (!variable_struct_exists(_out, _keys[_j])) _out[$ _keys[_j]] = { type: "model" };
      var _dst = _out[$ _keys[_j]];

      if (is_string(_mv[$ "type"]) && _mv.type != "") _dst.type = _mv.type;

      if (variable_struct_exists(_mv, "actor") && is_struct(_mv.actor)
      && is_string(_mv.actor[$ "object"]) && _mv.actor.object != "") {
        _dst.actor = _mv.actor;
      }
    }
  }

  return _out;
}

// Writes serialized scene to disk (JSON v1 or PLYB binary by extension).
function __poly_save_scene(_ed) {
  __poly_reg_ensure(_ed);
  var _nodes = __poly_serialize_scene(_ed);
  var _assets = __poly_write_file_assets(_ed);
  var _path = __poly_scene_path(_ed);

  if (_path == "") return false;
  __poly_ensure_dir(_path);

  if (__poly_scene_fmt_of(_path) == "bin") {
    if (!__poly_bin_save_descs(_path, _ed.id_seq, _assets, _nodes)) return false;
  } else {
    var _json = __poly_json_stringify_ordered({ version: 1, seq: _ed.id_seq, assets: _assets, nodes: _nodes }, true, 100);

    if (!__poly_write_text_file(_path, _json)) return false;
  }

  _ed.dirty = false;
  return true;
}

// Loads a scene file (JSON v1 or PLYB binary) into the editor.
function __poly_load_scene(_ed) {
  var _path = __poly_scene_path(_ed);

  if (_path == "" || !file_exists(_path)) {
    var _alt = __poly_scene_path_as(_path, __poly_scene_fmt_of(_path) == "bin" ? "json" : "bin");

    if (_alt == "" || !file_exists(_alt)) return false;
    _ed.scene_file = __poly_scene_path_as(_ed.scene_file, __poly_scene_fmt_of(_alt));
    _path = _alt;
  }

  var _file = __poly_load_data_file(_path);

  if (_file == undefined) return false;
  var _nodes = _file.nodes;

  if (!__poly_validate_descs(_nodes)) return false;

  if (is_real(_file[$ "seq"])) {
    __poly_reg_ensure(_ed);
    _ed.id_seq = max(_ed.id_seq, floor(_file.seq));
  }

  __poly_rebuild(_ed, _nodes);
  _ed.asset_meta = __poly_file_assets(_file);
  if (__poly_light_count(_ed) == 0) __poly_default_sun(_ed);
  if (__poly_env_node(_ed) == undefined) __poly_create_env(_ed);
  __poly_viewcam_seed(_ed);
  _ed.sel = [];
  _ed.giz.drag = -1;
  _ed.giz.hover = -1;
  __poly_history_clear(_ed);
  _ed.dirty = false;
  return true;
}

// ---------------------------------------------------------------------------
// File IO
// ---------------------------------------------------------------------------

// Reads whole text file contents.
function __poly_read_text_file(_path) {
  if (_path == "" || !file_exists(_path)) return "";
  var _file = file_text_open_read(_path);

  if (_file < 0) return "";
  var _out = "";

  while (!file_text_eof(_file)) {
    _out += file_text_read_string(_file);
    file_text_readln(_file);
  }

  file_text_close(_file);
  return _out;
}

// Writes text to file.
function __poly_write_text_file(_path, _txt) {
  var _file = file_text_open_write(_path);

  if (_file < 0) return false;
  file_text_write_string(_file, _txt);
  file_text_close(_file);
  return file_exists(_path);
}
