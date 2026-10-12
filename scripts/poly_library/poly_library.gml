// poly_library — asset library + spawn defaults (rotation/scale, shadow flags).

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

// Returns a non-empty string field of a struct, else "".
function __poly_asset_str(_entry, _field) {
  if (is_struct(_entry) && variable_struct_exists(_entry, _field) && is_string(_entry[$ _field]) && _entry[$ _field] != "") return _entry[$ _field];
  return "";
}

// Returns the display label for a library entry (label, else root name, else id).
function __poly_asset_label(_entry) {
  var _label = __poly_asset_str(_entry, "label");

  if (_label != "") return _label;
  var _name = __poly_asset_str(_entry, "name");

  if (_name != "") return _name;
  return __poly_asset_str(_entry, "key");
}

// ---------------------------------------------------------------------------
// Public library
// ---------------------------------------------------------------------------

// Adds model asset to editor library.
// Identity is the load path (_path): models with duplicate root names can
// coexist. When _path is omitted, the model root name is used as id.
// _label is display-only; matching/saving always use the id.
// _on_create (optional) is called for every spawned instance of this model,
// after the global on_create, as (node, asset, model, id, label).
function poly_asset_add(_model, _kind = "prefab", _label = undefined, _path = undefined, _on_create = undefined) {
  var _ed = __poly_inst();

  if (_ed == undefined) return undefined;
  if (!variable_struct_exists(_ed, "assets") || !is_array(_ed.assets)) _ed.assets = [];
  if (_model == undefined) return undefined;
  if (!is_string(_kind) || _kind == "") _kind = "prefab";
  var _root = __poly_model_key(_model);
  var _key = undefined;

  if (is_string(_path) && _path != "") {
    _key = _path;
  } else if (is_string(_root) && _root != "") {
    _key = _root;
  }

  if (!is_string(_key) || _key == "") return undefined;
  if (__poly_asset_get(_ed, _key) != undefined) return undefined;
  var _entry = { key: _key, model: _model, kind: _kind };

  if (is_string(_root) && _root != "") _entry.name = _root;
  if (is_string(_label) && _label != "") _entry.label = _label;
  if (is_method(_on_create)) _entry.on_create = _on_create;
  array_push(_ed.assets, _entry);
  return _key;
}

// Returns the library asset selected in the Models panel, if still valid.
function __poly_lib_sel_asset(_ed) {
  if (_ed == undefined || !variable_struct_exists(_ed, "lib_sel") || !is_real(_ed.lib_sel)) return undefined;
  if (!is_array(_ed.assets) || _ed.lib_sel < 0 || _ed.lib_sel >= array_length(_ed.assets)) return undefined;
  return _ed.assets[_ed.lib_sel];
}

// Clears all editor library assets.
function poly_asset_clear() {
  var _ed = __poly_inst();

  if (_ed == undefined) return;
  __poly_thumbs_free(_ed);
  _ed.assets = [];
  _ed.lib_sel = undefined;
  _ed.anim_ui = undefined;
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
