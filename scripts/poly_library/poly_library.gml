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
    _base = _en.kind == "light" ? "Light" : (_en.kind == "camera" ? "Camera" : (_en.kind == "environment" ? "Environment" : (_en.kind == "audio" ? "Audio Source" : "node")));
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
// Custom variables (code-declared, per-model defaults, per-instance overrides)
//
// Declarations are authored in code (struct of name -> default value, or an
// array of { name, type, def?, min?, max? } descriptors). Per-model saved
// values become the defaults; instances may override individual names.
// Types: "bool", "int", "float", "string", "vec3".
// ---------------------------------------------------------------------------

// Checks a variable type name.
function __poly_var_type_valid(_type) {
  return _type == "bool" || _type == "int" || _type == "float" || _type == "string" || _type == "vec3";
}

// Returns the zero value for a variable type.
function __poly_var_type_default(_type) {
  if (_type == "bool") return false;
  if (_type == "int") return 0;
  if (_type == "float") return 0.0;
  if (_type == "string") return "";
  if (_type == "vec3") return [ 0.0, 0.0, 0.0 ];
  return undefined;
}

// Infers a variable type from a value, or undefined when unsupported.
function __poly_var_type_of(_v) {
  if (is_bool(_v)) return "bool";
  if (is_real(_v)) return floor(_v) == _v ? "int" : "float";
  if (is_string(_v)) return "string";
  if (is_array(_v) && array_length(_v) == 3
  && is_real(_v[0]) && is_real(_v[1]) && is_real(_v[2])) return "vec3";
  return undefined;
}

// Coerces a value to a variable type (undefined when incompatible).
function __poly_var_coerce(_type, _v) {
  if (_type == "bool") return is_bool(_v) ? _v : undefined;
  if (_type == "int") return is_real(_v) ? round(_v) : undefined;
  if (_type == "float") return is_real(_v) ? _v : undefined;
  if (_type == "string") return is_string(_v) ? _v : undefined;

  if (_type == "vec3") {
    if (!is_array(_v) || array_length(_v) != 3) return undefined;
    if (!is_real(_v[0]) || !is_real(_v[1]) || !is_real(_v[2])) return undefined;
    return [ _v[0], _v[1], _v[2] ];
  }

  return undefined;
}

// Clamps a numeric value to a spec's optional range.
function __poly_var_clamp(_spec, _v) {
  if (!is_struct(_spec) || !is_real(_v)) return _v;
  var _min = _spec[$ "min"];
  var _max = _spec[$ "max"];

  if (is_real(_min)) _v = max(_v, _min);
  if (is_real(_max)) _v = min(_v, _max);
  if (_spec.type == "int") _v = round(_v);
  return _v;
}

// Builds a normalized { name, type, def, min?, max? } spec.
function __poly_var_spec_make(_name, _type, _def, _min, _max) {
  if (!is_string(_name) || _name == "") return undefined;
  if (!is_string(_type) || !__poly_var_type_valid(_type)) _type = __poly_var_type_of(_def);
  if (!__poly_var_type_valid(_type)) return undefined;
  var _v = __poly_var_coerce(_type, _def);

  if (_v == undefined) _v = __poly_var_type_default(_type);
  var _spec = { name: _name, type: _type, def: _v };

  if (is_real(_min)) _spec.min = _min;
  if (is_real(_max)) _spec.max = _max;
  _spec.def = __poly_var_clamp(_spec, _spec.def);
  return _spec;
}

// Adds or replaces a spec by name (declaration order preserved).
function __poly_vars_spec_put(_specs, _spec) {
  if (!is_array(_specs) || !is_struct(_spec)) return _specs;

  for (var _i = 0, _n = array_length(_specs); _i < _n; _i++) {
    if (is_struct(_specs[_i]) && _specs[_i].name == _spec.name) {
      _specs[_i] = _spec;
      return _specs;
    }
  }

  array_push(_specs, _spec);
  return _specs;
}

// Returns the index of a spec by name, or -1.
function __poly_vars_spec_index(_specs, _name) {
  if (!is_array(_specs) || !is_string(_name)) return -1;

  for (var _i = 0, _n = array_length(_specs); _i < _n; _i++) {
    if (is_struct(_specs[_i]) && _specs[_i].name == _name) return _i;
  }

  return -1;
}

// Parses a code declaration (struct of values or descriptor array) to specs.
function __poly_vars_parse(_source) {
  var _out = [];

  if (is_struct(_source)) {
    var _names = variable_struct_get_names(_source);

    for (var _i = 0, _n = array_length(_names); _i < _n; _i++) {
      var _name = _names[_i];
      var _v = _source[$ _name];
      var _type = __poly_var_type_of(_v);

      if (_type == undefined) continue;
      var _spec = __poly_var_spec_make(_name, _type, _v, undefined, undefined);

      if (_spec != undefined) __poly_vars_spec_put(_out, _spec);
    }

    return _out;
  }

  if (is_array(_source)) {
    for (var _j = 0, _m = array_length(_source); _j < _m; _j++) {
      var _d = _source[_j];

      if (!is_struct(_d)) continue;
      var _dn = _d[$ "name"];

      if (!is_string(_dn) || _dn == "") continue;
      var _dt = _d[$ "type"];
      var _spec2 = __poly_var_spec_make(
        _dn,
        is_string(_dt) ? _dt : undefined,
        _d[$ "def"],
        _d[$ "min"],
        _d[$ "max"]
      );

      if (_spec2 != undefined) __poly_vars_spec_put(_out, _spec2);
    }
  }

  return _out;
}

// Deep-copies a spec array.
function __poly_vars_specs_clone(_specs) {
  var _out = [];

  if (!is_array(_specs)) return _out;

  for (var _i = 0, _n = array_length(_specs); _i < _n; _i++) {
    var _s = _specs[_i];

    if (!is_struct(_s)) continue;
    var _c = { name: _s.name, type: _s.type, def: __poly_var_coerce(_s.type, _s.def) };

    if (_c.def == undefined) _c.def = __poly_var_type_default(_s.type);
    if (is_real(_s[$ "min"])) _c.min = _s.min;
    if (is_real(_s[$ "max"])) _c.max = _s.max;
    array_push(_out, _c);
  }

  return _out;
}

// Deep-copies a variable map (vec3 arrays included).
function __poly_vars_clone(_vars) {
  var _out = {};

  if (!is_struct(_vars)) return _out;
  var _names = variable_struct_get_names(_vars);

  for (var _i = 0, _n = array_length(_names); _i < _n; _i++) {
    var _v = _vars[$ _names[_i]];

    if (is_array(_v)) {
      _out[$ _names[_i]] = [ _v[0], _v[1], _v[2] ];
    } else {
      _out[$ _names[_i]] = _v;
    }
  }

  return _out;
}

// Returns true when a map has at least one key.
function __poly_vars_has(_vars) {
  if (!is_struct(_vars)) return false;
  return array_length(variable_struct_get_names(_vars)) > 0;
}

// Checks whether a raw value is a supported variable value.
function __poly_vars_value_ok(_v) {
  return __poly_var_type_of(_v) != undefined;
}

// Normalizes a raw value map against specs (only declared names survive).
function __poly_vars_overrides(_specs, _raw) {
  var _out = {};

  if (!is_struct(_raw)) return _out;

  if (!is_array(_specs) || array_length(_specs) == 0) {
    var _names = variable_struct_get_names(_raw);

    for (var _i = 0, _n = array_length(_names); _i < _n; _i++) {
      var _v = _raw[$ _names[_i]];

      if (__poly_vars_value_ok(_v)) _out[$ _names[_i]] = __poly_vars_clone({ v: _v }).v;
    }

    return _out;
  }

  for (var _j = 0, _m = array_length(_specs); _j < _m; _j++) {
    var _s = _specs[_j];

    if (!is_struct(_s) || !variable_struct_exists(_raw, _s.name)) continue;
    var _cv = __poly_var_coerce(_s.type, _raw[$ _s.name]);

    if (_cv == undefined) continue;
    _out[$ _s.name] = __poly_var_clamp(_s, _cv);
  }

  return _out;
}

// Fills a complete value map from specs and optional overrides/defaults.
function __poly_vars_fill(_specs, _values) {
  var _out = {};

  if (!is_array(_specs)) return _out;

  for (var _i = 0, _n = array_length(_specs); _i < _n; _i++) {
    var _s = _specs[_i];

    if (!is_struct(_s)) continue;
    var _v = undefined;

    if (is_struct(_values) && variable_struct_exists(_values, _s.name)) _v = __poly_var_coerce(_s.type, _values[$ _s.name]);
    if (_v == undefined) _v = __poly_var_coerce(_s.type, _s.def);
    if (_v == undefined) _v = __poly_var_type_default(_s.type);
    _out[$ _s.name] = __poly_var_clamp(_s, _v);
  }

  return _out;
}

// Overlays override values onto a base map.
function __poly_vars_merge(_base, _over) {
  var _out = __poly_vars_clone(_base);

  if (!is_struct(_over)) return _out;
  var _names = variable_struct_get_names(_over);

  for (var _i = 0, _n = array_length(_names); _i < _n; _i++) _out[$ _names[_i]] = __poly_vars_clone({ v: _over[$ _names[_i]] }).v;
  return _out;
}

// Compares two variable values.
function __poly_var_value_equal(_a, _b) {
  if (is_array(_a) || is_array(_b)) {
    if (!is_array(_a) || !is_array(_b) || array_length(_a) != array_length(_b)) return false;

    for (var _i = 0, _n = array_length(_a); _i < _n; _i++) if (_a[_i] != _b[_i]) return false;
    return true;
  }

  if (is_bool(_a) != is_bool(_b)) return false;
  if (is_real(_a) != is_real(_b)) return false;
  if (is_string(_a) != is_string(_b)) return false;
  return _a == _b;
}

// Compares two variable maps (missing keys compare as undefined).
function __poly_vars_equal(_a, _b) {
  if (!is_struct(_a)) _a = {};
  if (!is_struct(_b)) _b = {};
  var _na = variable_struct_get_names(_a);
  var _nb = variable_struct_get_names(_b);
  var _n = array_length(_na);

  if (_n != array_length(_nb)) return false;

  for (var _i = 0; _i < _n; _i++) {
    var _k = _na[_i];

    if (!variable_struct_exists(_b, _k)) return false;
    if (!__poly_var_value_equal(_a[$ _k], _b[$ _k])) return false;
  }

  return true;
}

// Builds the file-side spec array ({ name, type, def, min?, max? }).
function __poly_vars_specs_file(_specs, _values) {
  var _out = [];

  if (!is_array(_specs)) return _out;

  for (var _i = 0, _n = array_length(_specs); _i < _n; _i++) {
    var _s = _specs[_i];

    if (!is_struct(_s)) continue;
    var _v = undefined;

    if (is_struct(_values) && variable_struct_exists(_values, _s.name)) _v = __poly_var_coerce(_s.type, _values[$ _s.name]);
    if (_v == undefined) _v = __poly_var_coerce(_s.type, _s.def);
    if (_v == undefined) _v = __poly_var_type_default(_s.type);
    _v = __poly_var_clamp(_s, _v);
    var _f = { name: _s.name, type: _s.type, def: _v };

    if (is_real(_s[$ "min"])) _f.min = _s.min;
    if (is_real(_s[$ "max"])) _f.max = _s.max;
    array_push(_out, _f);
  }

  return _out;
}

// Merges loaded/file specs into a schema and value map.
// Existing names keep the code-declared type; unknown names are appended.
function __poly_vars_merge_file(_specs, _values, _file_specs) {
  var _schema = __poly_vars_specs_clone(_specs);
  var _vals = __poly_vars_fill(_schema, _values);

  if (!is_array(_file_specs)) return { schema: _schema, values: _vals };

  for (var _i = 0, _n = array_length(_file_specs); _i < _n; _i++) {
    var _fs = _file_specs[_i];

    if (!is_struct(_fs)) continue;
    var _idx = __poly_vars_spec_index(_schema, _fs.name);

    if (_idx >= 0) {
      var _s = _schema[_idx];
      var _cv = __poly_var_coerce(_s.type, _fs.def);

      if (_cv != undefined) _vals[$ _s.name] = __poly_var_clamp(_s, _cv);
    } else {
      array_push(_schema, _fs);
      _vals[$ _fs.name] = __poly_var_clamp(_fs, __poly_var_coerce(_fs.type, _fs.def));
    }
  }

  return { schema: _schema, values: _vals };
}

// Sets (or replaces) the code declaration for a library entry.
function __poly_vars_set_code(_entry, _source) {
  if (!is_struct(_entry)) return;

  var _specs = __poly_vars_parse(_source);
  _entry.vars_code_schema = __poly_vars_specs_clone(_specs);
  _entry.vars_code_def = __poly_vars_fill(_specs, undefined);
  _entry.vars_schema = __poly_vars_specs_clone(_specs);
  _entry.vars_def = __poly_vars_fill(_specs, undefined);
}

// Resolves a library entry's current vars state.
// _file_specs: optional specs loaded from a scene file.
// _reset_code: ignore file values and restore the code snapshot.
function __poly_vars_entry_state(_entry, _file_specs, _reset_code) {
  if (!is_struct(_entry)) return;

  var _code_schema = is_array(_entry[$ "vars_code_schema"]) ? _entry.vars_code_schema : undefined;
  var _code_def = is_struct(_entry[$ "vars_code_def"]) ? _entry.vars_code_def : undefined;

  if (_code_schema == undefined) {
    _code_schema = is_array(_entry[$ "vars_schema"]) ? __poly_vars_specs_clone(_entry.vars_schema) : [];
    _code_def = is_struct(_entry[$ "vars_def"]) ? __poly_vars_clone(_entry.vars_def) : __poly_vars_fill(_code_schema, undefined);
    _entry.vars_code_schema = __poly_vars_specs_clone(_code_schema);
    _entry.vars_code_def = __poly_vars_clone(_code_def);
  }

  var _specs = [];
  var _vals = {};

  if (_reset_code == true) {
    _specs = __poly_vars_specs_clone(_code_schema);
    _vals = __poly_vars_fill(_specs, _code_def);
  } else {
    _specs = __poly_vars_specs_clone(_code_schema);
    var _cur = is_struct(_entry[$ "vars_def"]) ? _entry.vars_def : _code_def;
    _vals = __poly_vars_fill(_specs, _cur);
  }

  var _merged = __poly_vars_merge_file(_specs, _vals, _file_specs);

  _entry.vars_schema = _merged.schema;
  _entry.vars_def = _merged.values;
}

// Returns the resolved default map for a library entry.
function __poly_vars_entry_def(_entry) {
  if (!is_struct(_entry)) return {};

  if (!is_array(_entry[$ "vars_schema"]) || !is_struct(_entry[$ "vars_def"])) {
    __poly_vars_entry_state(_entry, undefined, false);
  }

  return __poly_vars_fill(_entry.vars_schema, _entry.vars_def);
}

// Resolves a full value map for an asset key plus per-instance overrides.
function __poly_vars_resolve_entry(_ed, _key, _over) {
  var _entry = __poly_asset_get(_ed, _key);

  if (_entry == undefined) return __poly_vars_overrides(undefined, _over);
  var _defs = __poly_vars_entry_def(_entry);
  var _specs = is_array(_entry[$ "vars_schema"]) ? _entry.vars_schema : [];
  var _ov = __poly_vars_overrides(_specs, _over);
  return __poly_vars_merge(_defs, _ov);
}

// Writes an entry's current schema/defaults into the per-model file map.
function __poly_vars_meta_set(_ed, _entry) {
  if (!is_struct(_ed) || !is_struct(_entry) || !is_string(_entry[$ "key"]) || _entry.key == "") return;
  if (!variable_struct_exists(_ed, "asset_meta") || !is_struct(_ed.asset_meta)) _ed.asset_meta = {};
  var _key = _entry.key;
  var _meta = variable_struct_exists(_ed.asset_meta, _key) ? _ed.asset_meta[$ _key] : undefined;

  if (!is_struct(_meta)) _meta = { type: "model" };
  var _specs = is_array(_entry[$ "vars_schema"]) ? _entry.vars_schema : [];

  if (array_length(_specs) == 0 && variable_struct_exists(_meta, "vars")) variable_struct_remove(_meta, "vars");
  else _meta.vars = __poly_vars_specs_file(_specs, _entry[$ "vars_def"]);
  _ed.asset_meta[$ _key] = _meta;
}

// Applies the file-side per-model vars to library entries (mirror of the
// physics prefab sync): stored values become defaults, code defines names.
function __poly_vars_prefab_meta_sync(_ed) {
  if (_ed == undefined || !is_array(_ed.assets) || !is_struct(_ed[$ "asset_meta"])) return;

  for (var _i = 0, _n = array_length(_ed.assets); _i < _n; _i++) {
    var _entry = _ed.assets[_i];

    if (!is_struct(_entry) || !is_string(_entry[$ "key"]) || _entry.key == "") continue;
    var _meta = _ed.asset_meta[$ _entry.key];
    var _file = is_struct(_meta) && is_array(_meta[$ "vars"]) ? _meta.vars : undefined;

    __poly_vars_entry_state(_entry, _file, _file == undefined);
  }
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
