// polygon_serialize — descriptors, validation, rebuild, scene file IO.

// ---------------------------------------------------------------------------
// Paths
// ---------------------------------------------------------------------------

// Resolves scene path to absolute path.
function __polygon_scene_path(_ed) {
  var _file = _ed.scene_file;

  if (_file == undefined || _file == "")  return "";
  var _abs = string_pos(":", _file) > 0 || string_copy(_file, 1, 2) == "\\\\" || string_copy(_file, 1, 1) == "/";

  if (_abs)  return _file;
  return working_directory + _file;
}

// Creates parent directory for path.
function __polygon_ensure_dir(_path) {
  var _at = max(string_last_pos("\\", _path), string_last_pos("/", _path));

  if (_at > 1)  directory_create(string_copy(_path, 1, _at - 1));
}

// ---------------------------------------------------------------------------
// Descriptors
// ---------------------------------------------------------------------------

// Converts node to serializable descriptor skipping system.
function __polygon_node_to_descriptor(_ed, _node) {
  if (__polygon_is_grid(_ed, _node))  return undefined;
  if (_ed != undefined && variable_struct_exists(_ed, "rt") && is_struct(_ed.rt))  if (variable_struct_exists(_ed.rt, "cam") && __polygon_node_same(_node, _ed.rt.cam))  return undefined;
  if (_ed != undefined && variable_struct_exists(_ed, "drag_preview") && __polygon_node_same(_node, _ed.drag_preview))  return undefined;
  return __polygon_node_desc(_ed, _node);
}

// Converts tracked node to descriptor.
function __polygon_node_desc(_ed, _node) {
  var _en = __polygon_registry_find(_ed, _node);

  if (_en == undefined)  return undefined;
  var _kind = __polygon_kind_of(_ed, _node);

  if (_kind == undefined)  return undefined;
  if (_kind == "light" || _kind == "camera" || _kind == "environment")  return __polygon_prop_desc(_ed, _node, _kind);
  var _asset = __polygon_asset_desc(_ed, _node);

  if (_asset == undefined)  return undefined;
  return {
    kind: "instance",
    id: _asset.id,
    label: _asset.label,
    asset: _asset.asset,
    position: _asset.position,
    rotation: _asset.rotation,
    scale: _asset.scale,
    flags: _asset.flags,
  };
}

// Reads prop data from registry entry, else live from the node.
function __polygon_prop_data(_ed, _node, _kind) {
  var _en = __polygon_registry_find(_ed, _node);

  if (_en != undefined && is_struct(_en.data))  return _en.data;
  if (_kind == "light") {
    return __polygon_light_read(_node);
  } else if (_kind == "camera") {
    return __polygon_camera_read(_node);
  } else {
    return __polygon_env_read(_node);
  }
}

// File<->internal key map per kind. k: internal key, j: file key
// (dotted for nested), b: desc bool mode (1 = ==true), br: rebuild bool
// mode (1 = ==true, 2 = !=false), arr: copy as 3-array, gt/ge: rebuild
// skips the source unless _v > gt / _v >= ge (defaults survive).
function __polygon_prop_keymap() {
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
function __polygon_desc_set(_o, _j, _v) {
  var _dot = string_pos(".", _j);

  if (_dot <= 0) {
    _o[$ _j] = _v;
    return;
  }

  var _head = string_copy(_j, 1, _dot - 1);
  var _tail = string_delete(_j, 1, _dot);

  if (!variable_struct_exists(_o, _head) || !is_struct(_o[$ _head]))  _o[$ _head] = {};
  _o[$ _head][$ _tail] = _v;
}

// Reads a (possibly dotted) key from a descriptor struct (undefined when absent).
function __polygon_desc_get(_o, _j) {
  var _dot = string_pos(".", _j);

  if (_dot <= 0)  return is_struct(_o) ? _o[$ _j] : undefined;
  if (!is_struct(_o))  return undefined;
  var _head = _o[$ string_copy(_j, 1, _dot - 1)];

  if (!is_struct(_head))  return undefined;
  return _head[$ string_delete(_j, 1, _dot)];
}

// Builds the file sub-descriptor for a kind from internal data.
function __polygon_prop_subdesc(_pd, _kind) {
  var _map = __polygon_prop_keymap()[$ _kind];
  var _out = {};

  for (var _i = 0, _n = array_length(_map); _i < _n; _i++) {
    var _e = _map[_i];
    var _v = _pd[$ _e.k];

    if (_e[$ "arr"] == 3)  _v = [ _v[0], _v[1], _v[2] ];
    else if (_e[$ "b"] == 1)  _v = (_v == true);
    __polygon_desc_set(_out, _e.j, _v);
  }

  return _out;
}

// Builds the light sub-descriptor.
function __polygon_light_desc(_pd) {
  return __polygon_prop_subdesc(_pd, "light");
}

// Builds the camera sub-descriptor.
function __polygon_camera_desc(_pd) {
  return __polygon_prop_subdesc(_pd, "camera");
}

// Builds the environment sub-descriptor.
function __polygon_env_desc(_pd) {
  return __polygon_prop_subdesc(_pd, "environment");
}

// Builds light camera environment descriptor.
function __polygon_prop_desc(_ed, _node, _kind) {
  var _en = __polygon_registry_find(_ed, _node);
  var _label = (_en != undefined && is_string(_en.label) && _en.label != "") ? _en.label : _node.name;
  var _id = (_en != undefined && is_string(_en.id)) ? _en.id : _node.name;
  var _pos = _node.getLocalPosition();
  var _rot = _node.getLocalRotation();
  var _sca = _node.getLocalScale();

  if (_kind == "camera")  _rot = __polygon_quat_no_roll(_rot);
  var _desc = {
    kind: _kind,
    id: _id,
    label: _label,
    asset: "",
    position: [ _pos.x, _pos.y, _pos.z ],
    rotation: [ _rot.x, _rot.y, _rot.z, _rot.w ],
    scale: [ _sca.x, _sca.y, _sca.z ],
  };
  var _data = __polygon_prop_data(_ed, _node, _kind);

  if (_kind == "light") {
    _desc.light = __polygon_light_desc(_data);
  } else if (_kind == "camera") {
    _desc.camera = __polygon_camera_desc(_data);
  } else {
    _desc.environment = __polygon_env_desc(_data);
  }

  return _desc;
}

// Serializes tracked nodes to descriptor array.
function __polygon_serialize_scene(_ed) {
  var _nodes = __polygon_tracked_nodes(_ed);
  var _out = [];

  for (var _i = 0, _n = array_length(_nodes); _i < _n; _i++) {
    var _desc = __polygon_node_to_descriptor(_ed, _nodes[_i]);

    if (_desc != undefined)  array_push(_out, _desc);
  }

  return _out;
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

// Checks for a real-number field.
function __polygon_req_real(_s, _key) {
  return variable_struct_exists(_s, _key) && is_real(_s[$ _key]);
}

// Checks for a three-element array field.
function __polygon_req_vec3(_s, _key) {
  return variable_struct_exists(_s, _key) && is_array(_s[$ _key]) && array_length(_s[$ _key]) == 3;
}

// Checks for three number array.
function __polygon_is_num(_d, _key, _n) {
  if (!variable_struct_exists(_d, _key))  return false;
  var _arr = _d[$ _key];

  if (!is_array(_arr) || array_length(_arr) != _n)  return false;

  for (var _i = 0; _i < _n; _i++)  if (!is_real(_arr[_i]))  return false;
  return true;
}

// Checks for three number array.
function __polygon_is_num3(_d, _key) {
  return __polygon_is_num(_d, _key, 3);
}

// Checks for four number array.
function __polygon_is_num4(_d, _key) {
  return __polygon_is_num(_d, _key, 4);
}

// Validates light descriptor structure.
function __polygon_is_light_struct(_d) {
  if (!variable_struct_exists(_d, "light") || !is_struct(_d.light))  return false;
  var _lit = _d.light;

  if (!variable_struct_exists(_lit, "type") || !is_string(_lit.type))  return false;
  if (_lit.type != "directional" && _lit.type != "point" && _lit.type != "spot")  return false;
  if (!__polygon_req_vec3(_lit, "color"))  return false;
  if (!__polygon_req_real(_lit, "intensity") || !__polygon_req_real(_lit, "range"))  return false;
  if (!__polygon_req_real(_lit, "innerCone") || !__polygon_req_real(_lit, "outerCone"))  return false;
  if (variable_struct_exists(_lit, "shadow")) {
    if (!is_struct(_lit.shadow))  return false;
    var _sh = _lit.shadow;

    if (!variable_struct_exists(_sh, "enabled") || !is_bool(_sh.enabled))  return false;
    if (!__polygon_req_real(_sh, "resolution") || !__polygon_req_real(_sh, "distance") || !__polygon_req_real(_sh, "normalOffset"))  return false;
  }

  return true;
}

// Validates camera descriptor structure.
function __polygon_is_camera_struct(_d) {
  if (!variable_struct_exists(_d, "camera") || !is_struct(_d.camera))  return false;
  var _cam = _d.camera;

  if (!variable_struct_exists(_cam, "projection") || !is_string(_cam.projection))  return false;
  if (_cam.projection != "perspective" && _cam.projection != "ortho")  return false;
  if (!__polygon_req_real(_cam, "fovY") || !__polygon_req_real(_cam, "orthoWidth") || !__polygon_req_real(_cam, "orthoHeight"))  return false;
  if (!__polygon_req_real(_cam, "near") || !__polygon_req_real(_cam, "far"))  return false;
  return true;
}

// Validates environment descriptor structure.
function __polygon_is_env_struct(_d) {
  if (!variable_struct_exists(_d, "environment") || !is_struct(_d.environment))  return false;
  var _env = _d.environment;

  if (!__polygon_req_vec3(_env, "size") || !__polygon_req_vec3(_env, "ambient") || !__polygon_req_vec3(_env, "fogColor"))  return false;
  if (!__polygon_req_real(_env, "fogStart") || !__polygon_req_real(_env, "fogEnd"))  return false;
  return true;
}

// Validates scene descriptor array structure (strict v2: kind, id,
// label and asset are all required; no legacy name fallback).
function __polygon_validate_descs(_nodes) {
  if (!is_array(_nodes))  return false;
  for (var _i = 0, _n = array_length(_nodes); _i < _n; _i++) {
    var _desc = _nodes[_i];

    if (!is_struct(_desc))  return false;
    if (!variable_struct_exists(_desc, "kind") || !is_string(_desc.kind))  return false;
    if (!variable_struct_exists(_desc, "id") || !is_string(_desc.id) || _desc.id == "")  return false;
    if (!variable_struct_exists(_desc, "label") || !is_string(_desc.label) || _desc.label == "")  return false;
    if (!variable_struct_exists(_desc, "asset") || !is_string(_desc.asset))  return false;
    var _kind = _desc.kind;

    if (!__polygon_is_num3(_desc, "position") || !__polygon_is_num4(_desc, "rotation") || !__polygon_is_num3(_desc, "scale"))  return false;
    if (_kind == "instance") {
      if (!__polygon_validate_asset_desc(_desc))  return false;
    } else if (_kind == "light") {
      if (!__polygon_is_light_struct(_desc))  return false;
    } else if (_kind == "camera") {
      if (!__polygon_is_camera_struct(_desc))  return false;
    } else if (_kind == "environment") {
      if (!__polygon_is_env_struct(_desc))  return false;
    } else {
      return false;
    }
  }

  return true;
}

// Validates asset descriptor flags (asset key required, non-empty).
function __polygon_validate_asset_desc(_desc) {
  if (!variable_struct_exists(_desc, "asset") || !is_string(_desc.asset) || _desc.asset == "")  return false;
  if (variable_struct_exists(_desc, "flags")) {
    if (!is_struct(_desc.flags))  return false;
    if (!variable_struct_exists(_desc.flags, "castShadows") || !is_bool(_desc.flags.castShadows))  return false;
    if (!variable_struct_exists(_desc.flags, "receiveShadows") || !is_bool(_desc.flags.receiveShadows))  return false;
  }

  return true;
}

// ---------------------------------------------------------------------------
// Rebuild
// ---------------------------------------------------------------------------

// Clears tracked scene content, remembering hidden/locked ids.
function __polygon_rebuild_clear(_ed) {
  var _tracked = __polygon_root_tracked(_ed);
  var _hidden = [];
  var _locked = [];

  for (var _i = 0, _n = array_length(_tracked); _i < _n; _i++) {
    var _en = __polygon_registry_find(_ed, _tracked[_i]);

    if (_en != undefined && is_string(_en.id)) {
      if (_en.hidden == true)  array_push(_hidden, _en.id);
      if (_en.locked == true)  array_push(_locked, _en.id);
    }

    __polygon_destroy_subtree(_tracked[_i]);
  }

  _ed.rt.scene.update(0);
  __polygon_reg_clear(_ed);
  _ed.view_dirty = true;

  if (variable_struct_exists(_ed, "outline") && is_struct(_ed.outline)) {
    _ed.outline.cheap = undefined;
    _ed.outline.has = false;
  }

  return { hidden: _hidden, locked: _locked };
}

// Places one asset descriptor, applying saved shadow flags.
// The id is claimed before the wrapper is born (collisions get fresh).
function __polygon_rebuild_place_asset(_ed, _p, _key) {
  var _model = __polygon_asset_find(_ed, _key);

  if (_model == undefined)  throw "unknown model '" + string(_key) + "'";
  var _flags = undefined;

  if (variable_struct_exists(_p, "flags") && is_struct(_p.flags)) {
    _flags = { castShadows: _p.flags.castShadows == true, receiveShadows: _p.flags.receiveShadows == true };
  }

  var _wrap = __polygon_spawn(_ed, {
    kind: "instance",
    asset: _key,
    model: _model,
    pos: _p.position,
    rotation: _p.rotation,
    scale: _p.scale,
    label: _p.label,
    id: __polygon_wrap_claim(_ed, _p.id),
    data: _flags,
  });

  if (_wrap == undefined)  throw "place failed for '" + string(_key) + "'";
}

// Restores hidden/locked states by id after rebuild.
function __polygon_rebuild_restore_states(_ed, _states) {
  var _roots = __polygon_root_tracked(_ed);

  for (var _i = 0, _n = array_length(_roots); _i < _n; _i++) {
    var _en = __polygon_registry_find(_ed, _roots[_i]);

    if (_en == undefined || !is_string(_en.id))  continue;
    if (array_contains(_states.hidden, _en.id))  __polygon_hidden_set(_ed, _roots[_i], true);
    if (array_contains(_states.locked, _en.id))  __polygon_locked_set(_ed, _roots[_i], true);
  }
}

// Clears scene and rebuilds from descriptors.
function __polygon_rebuild(_ed, _nodes) {
  _ed.unlit_quiet = false;
  var _report = { placed: 0, failed: 0, err: "" };

  if (!is_array(_nodes))  _nodes = [];
  if (!__polygon_validate_descs(_nodes))  throw "invalid descriptors";
  __polygon_drop_preview_clear(_ed);
  var _states = __polygon_rebuild_clear(_ed);
  _ed.unlit_quiet = true;

  for (var _i = 0, _n = array_length(_nodes); _i < _n; _i++) {
    var _p = _nodes[_i];

    if (!is_struct(_p))  continue;
    var _kind = _p.kind;

    if (_kind == "light" || _kind == "camera" || _kind == "environment") {
      if (__polygon_rebuild_prop(_ed, _p, _kind) == undefined)  throw "place failed for '" + string(_p.id) + "'";
      _report.placed++;
      continue;
    }

    if (_kind != "instance")  throw "unknown kind '" + string(_kind) + "'";
    __polygon_rebuild_place_asset(_ed, _p, _p.asset);
    _report.placed++;
  }

  _ed.unlit_quiet = false;
  _ed.rt.scene.update(0);
  __polygon_seq_reseed(_ed);
  __polygon_gamecam_ensure(_ed);
  __polygon_cameras_mute(_ed);
  __polygon_unlit_apply(_ed);
  __polygon_rebuild_restore_states(_ed, _states);

  return _report;
}

// Reads internal data for a kind from a file sub-descriptor
// (defaults + mapped overrides; dotted keys resolve nesting).
function __polygon_rebuild_data(_p, _kind) {
  var _data = _kind == "light" ? __polygon_light_defaults()
    : _kind == "camera" ? __polygon_camera_defaults() : __polygon_env_defaults();
  var _sub = is_struct(_p) ? _p[$ _kind] : undefined;

  if (!is_struct(_sub))  return _data;
  var _map = __polygon_prop_keymap()[$ _kind];

  for (var _i = 0, _n = array_length(_map); _i < _n; _i++) {
    var _e = _map[_i];
    var _v = __polygon_desc_get(_sub, _e.j);

    if (_v == undefined)  continue;

    if (_e[$ "arr"] == 3) {
      if (is_array(_v) && array_length(_v) == 3)  _data[$ _e.k] = [ _v[0], _v[1], _v[2] ];
      continue;
    }

    if (_e[$ "gt"] != undefined && !(is_real(_v) && _v > _e[$ "gt"]))  continue;
    if (_e[$ "ge"] != undefined && !(is_real(_v) && _v >= _e[$ "ge"]))  continue;

    if (_e[$ "br"] == 1)  _data[$ _e.k] = (_v == true);
    else if (_e[$ "br"] == 2)  _data[$ _e.k] = (_v != false);
    else  _data[$ _e.k] = _v;
  }

  return _data;
}

// Reads light data from a descriptor (defaults + overrides).
function __polygon_rebuild_light_data(_p) {
  return __polygon_rebuild_data(_p, "light");
}

// Reads camera data from a descriptor.
function __polygon_rebuild_camera_data(_p) {
  return __polygon_rebuild_data(_p, "camera");
}

// Reads environment data from a descriptor.
function __polygon_rebuild_env_data(_p) {
  return __polygon_rebuild_data(_p, "environment");
}

// Rebuilds light camera environment node (wrapper carries id).
function __polygon_rebuild_prop(_ed, _p, _kind) {
  var _data = undefined;

  if (_kind == "light") {
    _data = __polygon_rebuild_light_data(_p);
  } else if (_kind == "camera") {
    _data = __polygon_rebuild_camera_data(_p);
  } else {
    _data = __polygon_rebuild_env_data(_p);
  }

  var _rot = _p.rotation;

  if (_kind == "camera") {
    var _nr = __polygon_quat_no_roll(__polygon_quat_from_array(_p.rotation));
    _rot = [ _nr.x, _nr.y, _nr.z, _nr.w ];
  }

  var _node = __polygon_spawn(_ed, {
    kind: _kind,
    pos: _p.position,
    rotation: _rot,
    scale: _p.scale,
    label: _p.label,
    id: __polygon_wrap_claim(_ed, _p.id),
    data: _data,
  });

  if (_node == undefined)  return undefined;
  if (_kind == "environment")  __polygon_hidden_set(_ed, _node, true);
  if (_kind == "light" && is_struct(_data) && variable_struct_exists(_data, "type") && _data.type == "directional")  __polygon_hidden_set(_ed, _node, true);
  return _node;
}

// ---------------------------------------------------------------------------
// Load and save
// ---------------------------------------------------------------------------

// Writes serialized scene to JSON file (v2: seq + id/label/asset).
function __polygon_save_scene(_ed) {
  __polygon_reg_ensure(_ed);
  var _nodes = __polygon_serialize_scene(_ed);
  var _json = json_stringify({ version: 2, seq: _ed.id_seq, nodes: _nodes }, true);
  var _path = __polygon_scene_path(_ed);

  if (_path == "")  return false;
  __polygon_ensure_dir(_path);

  if (!__polygon_write_text_file(_path, _json))  return false;
  _ed.dirty = false;
  return true;
}

// Loads scene JSON into editor.
function __polygon_load_scene(_ed) {
  var _path = __polygon_scene_path(_ed);

  if (_path == "" || !file_exists(_path))  return false;
  var _json = __polygon_read_text_file(_path);

  if (_json == "")  return false;
  var _data = json_parse(_json);
  var _ok = is_struct(_data) && _data.version == 2 && variable_struct_exists(_data, "nodes") && is_array(_data.nodes);

  if (!_ok)  return false;
  if (variable_struct_exists(_data, "seq") && is_real(_data.seq)) {
    __polygon_reg_ensure(_ed);
    _ed.id_seq = max(_ed.id_seq, floor(_data.seq));
  }

  __polygon_rebuild(_ed, _data.nodes);
  __polygon_viewcam_seed(_ed);
  _ed.sel = [];
  _ed.giz.drag = -1;
  _ed.giz.hover = -1;
  __polygon_history_clear(_ed);
  _ed.dirty = false;
  return true;
}

// ---------------------------------------------------------------------------
// File IO
// ---------------------------------------------------------------------------

// Reads whole text file contents.
function __polygon_read_text_file(_path) {
  if (_path == "" || !file_exists(_path))  return "";
  var _file = file_text_open_read(_path);

  if (_file < 0)  return "";
  var _out = "";

  while (!file_text_eof(_file)) {
    _out += file_text_read_string(_file);
    file_text_readln(_file);
  }

  file_text_close(_file);
  return _out;
}

// Writes text to file.
function __polygon_write_text_file(_path, _txt) {
  var _file = file_text_open_write(_path);

  if (_file < 0)  return false;
  file_text_write_string(_file, _txt);
  file_text_close(_file);
  return file_exists(_path);
}
