// poly_library - asset library + spawn defaults (rotation/scale, shadow flags).

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------

// Reads the first named root node of a model (e.g. "tree-pine").
// Used for library display and for matching live nodes back to models.
// Identity of placed nodes is the wrapper id, not this name.
function __poly_model_key(_model) {
  if (_model == undefined) return undefined;
  var _nodes = undefined;
  _nodes = _model.getNodes();
  if (!is_array(_nodes)) return undefined;

  for (var _i = 0, _n = array_length(_nodes); _i < _n; _i++) {
    var _node = _nodes[_i];

    if (_node == undefined || _node.parent != undefined) continue;
    if (is_string(_node.name) && _node.name != "") return _node.name;
  }

  return undefined;
}

// Checks if a library id is already registered.
// Finds library entry by key.
function __poly_asset_get(_ed, _key) {
  if (_ed == undefined || !is_string(_key) || !is_array(_ed.assets)) return undefined;
  for (var _i = 0, _n = array_length(_ed.assets); _i < _n; _i++) if (is_struct(_ed.assets[_i]) && _ed.assets[_i].key == _key) return _ed.assets[_i];
  return undefined;
}

// Finds library model by key.
function __poly_asset_find(_ed, _key) {
  var _entry = __poly_asset_get(_ed, _key);
  return _entry == undefined ? undefined : _entry.model;
}

// Derives display text from an asset id: file name without path or
// extension ("house/Prop_Bar_Stool.glb" -> "Prop_Bar_Stool").
function __poly_display_from_key(_key) {
  var _s = is_string(_key) ? _key : "";
  var _slash = string_last_pos("/", _s);

  if (_slash > 0) _s = string_copy(_s, _slash + 1, string_length(_s) - _slash);
  var _dot = string_last_pos(".", _s);

  if (_dot > 1) _s = string_copy(_s, 1, _dot - 1);
  return _s;
}

// Extracts the trailing number of a stable id ("__PolygonEditor__47" -> "47").
function __poly_id_number(_id) {
  if (!is_string(_id)) return "";
  var _n = string_length(_id);
  var _i = _n;

  while (_i >= 1 && string_char_at(_id, _i) >= "0" && string_char_at(_id, _i) <= "9") _i--;
  return string_copy(_id, _i + 1, _n - _i);
}

// Returns the display text for a node: the custom instance name when set,
// else the asset file name (or kind for lights/cameras/environment) plus
// the stable id number, so rows stay unique ("Prop_Bar_Stool #47").
function __poly_node_display(_ed, _node, _en = undefined) {
  if (_node == undefined) return "node";
  _en ??= __poly_registry_find(_ed, _node);

  if (_en != undefined && is_string(_en.label) && _en.label != "") return _en.label;
  var _base = "";

  if (_en != undefined && is_string(_en.asset) && _en.asset != "") {
    _base = __poly_display_from_key(_en.asset);
  } else if (_en != undefined && is_string(_en.kind) && _en.kind != "") {
    _base = _en.kind == "light" ? "Light" : (_en.kind == "camera" ? "Camera" : (_en.kind == "environment" ? "Environment" : "node"));
  }

  if (_base == "") _base = "node";
  var _id = _en != undefined ? _en.id : __poly_wrap_id_of(_node);
  var _num = __poly_id_number(_id);
  return _num != "" ? _base + " #" + _num : _base;
}

// ---------------------------------------------------------------------------
// Public library
// ---------------------------------------------------------------------------


// Returns the library asset selected in the Models panel, if still valid.
function __poly_lib_sel_asset(_ed) {
  if (_ed == undefined || !variable_struct_exists(_ed, "lib_sel") || !is_real(_ed.lib_sel)) return undefined;
  if (!is_array(_ed.assets) || _ed.lib_sel < 0 || _ed.lib_sel >= array_length(_ed.assets)) return undefined;
  return _ed.assets[_ed.lib_sel];
}


// ---------------------------------------------------------------------------
// Spawn defaults
// ---------------------------------------------------------------------------

// Returns editable default spawn transform for a library asset.
function __poly_spawn_t(_entry) {
  if (!is_struct(_entry)) return undefined;

  if (!variable_struct_exists(_entry, "spawn_t") || !is_struct(_entry.spawn_t)) {
    _entry.spawn_t = { rot: [ 0, 0, 0 ], sca: [ 1, 1, 1 ] };
  }

  return _entry.spawn_t;
}

// Returns editable default shadow flags for a library asset.
function __poly_spawn_shadow(_entry) {
  if (!is_struct(_entry)) return undefined;

  if (!variable_struct_exists(_entry, "spawn_shadow") || !is_struct(_entry.spawn_shadow)) {
    _entry.spawn_shadow = { cast: true, recv: true };
  }

  return _entry.spawn_shadow;
}

// Builds spawn rotation/scale from asset defaults.
function __poly_spawn_apply(_entry) {
  var _t = __poly_spawn_t(_entry);
  var _rot = undefined;
  var _sca = [ 1, 1, 1 ];

  if (_t != undefined) {
    _rot = __poly_euler_to_quat(
      degtorad(_t.rot[0]),
      degtorad(_t.rot[1]),
      degtorad(_t.rot[2])
    );
    _sca = [ max(_t.sca[0], 0.01), max(_t.sca[1], 0.01), max(_t.sca[2], 0.01) ];
  }

  return { rot: _rot, sca: _sca };
}

// Applies asset default shadow flags to a freshly spawned node.
function __poly_spawn_shadow_apply(_ed, _entry, _node) {
  var _sh = __poly_spawn_shadow(_entry);

  if (_sh == undefined || _node == undefined) return;
  var _en = __poly_registry_find(_ed, _node);

  if (_en == undefined || !is_struct(_en.data)) return;
  _en.data.castShadows = _sh.cast == true;
  _en.data.receiveShadows = _sh.recv == true;
  __poly_flags_apply(_node, _en.data.castShadows, _en.data.receiveShadows);
}

// ---------------------------------------------------------------------------
// Model-space bounds (pivot derivation)
//
// A glb never declares "pivot at base/center": the pivot IS the model-space
// origin. We derive it from the geometry AABB (GM3D getBoundingBox):
//   bottomOffset = min.y  (0 = base pivot, -h/2 = center pivot)
// Resting math only needs bottomOffset, so callers never guess Y again.
// Cached per library entry (source scenes are frozen, bounds are static).
// ---------------------------------------------------------------------------

/// Returns model-space bounds for a source model, or undefined.
/// Shape: { min:[x,y,z], max:[x,y,z], size:[x,y,z], bottom, top, height,
///          pivot_ratio (0=base, 0.5=center), origin ("base"|"center"|"custom") }
function __poly_asset_measure(_model) {
  if (_model == undefined) return undefined;
  var _get = _model[$ "getBoundingBox"];

  if (_get == undefined) return undefined;
  var _bb = method(_model, _get)();

  if (!is_struct(_bb)) return undefined;
  if (!variable_struct_exists(_bb, "min") || !variable_struct_exists(_bb, "max")) return undefined;
  var _mn = _bb.min;
  var _mx = _bb.max;

  if (_mn == undefined || _mx == undefined) return undefined;
  var _min = [ _mn.x, _mn.y, _mn.z ];
  var _max = [ _mx.x, _mx.y, _mx.z ];
  var _sx = _max[0] - _min[0];
  var _sy = _max[1] - _min[1];
  var _sz = _max[2] - _min[2];
  var _h = _sy;
  var _ratio = 0.0;

  if (_h > 0.000001) _ratio = (0.0 - _min[1]) / _h;
  var _origin = "custom";

  if (abs(_min[1]) <= 0.02) {
    _origin = "base";
  } else if (_h > 0.000001 && abs(_min[1] + _h * 0.5) <= max(_h * 0.05, 0.02)) {
    _origin = "center";
  }

  return {
    min: _min,
    max: _max,
    size: [ _sx, _sy, _sz ],
    bottom: _min[1],
    top: _max[1],
    height: _h,
    pivot_ratio: _ratio,
    origin: _origin,
  };
}

// Returns cached model-space bounds for a library entry, measuring lazily.
function __poly_asset_bounds(_entry) {
  if (!is_struct(_entry) || _entry.model == undefined) return undefined;
  if (variable_struct_exists(_entry, "bounds_local") && is_struct(_entry.bounds_local)) return _entry.bounds_local;
  var _b = __poly_asset_measure(_entry.model);

  if (_b != undefined) _entry.bounds_local = _b;
  return _b;
}
