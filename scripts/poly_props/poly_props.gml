// poly_props — light/camera/environment defaults, read/apply, creation.

// ---------------------------------------------------------------------------
// Defaults
// ---------------------------------------------------------------------------

// Builds a defaults struct from schema descriptors (arrays copied).
function __poly_schema_defaults(_schema, _kind) {
  var _out = {};
  var _arr = (is_struct(_schema) && variable_struct_exists(_schema, _kind)) ? _schema[$ _kind] : undefined;

  if (!is_array(_arr)) return _out;

  for (var _i = 0, _n = array_length(_arr); _i < _n; _i++) {
    var _f = _arr[_i];

    if (!is_struct(_f) || !is_string(_f[$ "key"])) continue;
    var _dv = _f[$ "def"];
    _out[$ _f[$ "key"]] = (is_array(_dv) && array_length(_dv) == 3) ? [ _dv[0], _dv[1], _dv[2] ] : _dv;
  }

  return _out;
}

// Returns default light property values.
function __poly_light_defaults() {
  return __poly_schema_defaults(__poly_prop_schema(), "light");
}

// Returns default camera property values.
function __poly_camera_defaults() {
  return __poly_schema_defaults(__poly_prop_schema(), "camera");
}

// Returns default environment property values.
function __poly_env_defaults() {
  return __poly_schema_defaults(__poly_prop_schema(), "env");
}

// ---------------------------------------------------------------------------
// Property schema (data table + generic read/apply helpers)
// ---------------------------------------------------------------------------

// Returns the property schema: per-kind field descriptors {key,type,min,max,def}.
// Covers every field used in light/camera/env defaults. Descriptor builders
// (poly_serialize) map these to file keys: inner->innerCone, outer->outerCone,
// fov->fovY, ow->orthoWidth, oh->orthoHeight, fog->fogEnabled,
// fogcolor->fogColor, fogstart->fogStart, fogend->fogEnd,
// shadow/shadowRes/shadowDist/shadowNormal->shadow.{enabled,resolution,distance,normalOffset}.
function __poly_prop_schema() {
  return {
    light: [
      { key: "type", type: "string", min: undefined, max: undefined, def: "directional" },
      { key: "color", type: "color", min: 0, max: 255, def: [ 255, 255, 255 ] },
      { key: "intensity", type: "float", min: 0, max: undefined, def: 1.0 },
      { key: "range", type: "float", min: 0, max: undefined, def: 50.0 },
      { key: "inner", type: "float", min: 0, max: 89, def: 30.0 },
      { key: "outer", type: "float", min: 1, max: 89, def: 45.0 },
      { key: "enabled", type: "bool", min: undefined, max: undefined, def: true },
      { key: "shadow", type: "bool", min: undefined, max: undefined, def: false },
      { key: "shadowRes", type: "int", min: 256, max: 8192, def: 2048 },
      { key: "shadowDist", type: "float", min: 1, max: undefined, def: 20.0 },
      { key: "shadowNormal", type: "float", min: 0, max: 1, def: 0.05 },
    ],
    camera: [
      { key: "projection", type: "string", min: undefined, max: undefined, def: "perspective" },
      { key: "fov", type: "float", min: 1, max: 179, def: 60.0 },
      { key: "ow", type: "float", min: 0.01, max: undefined, def: 10.0 },
      { key: "oh", type: "float", min: 0.01, max: undefined, def: 10.0 },
      { key: "near", type: "float", min: 0.01, max: undefined, def: 0.1 },
      { key: "far", type: "float", min: undefined, max: undefined, def: 10000.0 },
      { key: "enabled", type: "bool", min: undefined, max: undefined, def: true },
    ],
    env: [
      { key: "size", type: "vec3", min: 0.01, max: undefined, def: [ 20000.0, 20000.0, 20000.0 ] },
      { key: "ambient", type: "color", min: 0, max: 255, def: [ 70, 70, 85 ] },
      { key: "fog", type: "bool", min: undefined, max: undefined, def: false },
      { key: "fogcolor", type: "color", min: 0, max: 255, def: [ 192, 192, 192 ] },
      { key: "fogstart", type: "float", min: undefined, max: undefined, def: 20.0 },
      { key: "fogend", type: "float", min: undefined, max: undefined, def: 100.0 },
      { key: "enabled", type: "bool", min: undefined, max: undefined, def: true },
    ],
  };
}

// Assigns one field with an is_real guard for numeric destinations.
// Optional _min/_max act as IGNORE thresholds (out-of-range values keep the
// old value, they are NOT clamped) so component/descriptor read semantics
// (e.g. range/shadowDist require > 0, shadowNormal requires >= 0) are preserved.
// Pass _clamp=true to clamp instead (inspector-style). Returns true on assign.
function __poly_apply_field(_data, _field, _val, _min = undefined, _max = undefined, _clamp = false) {
  if (!is_struct(_data) || !is_string(_field) || !variable_struct_exists(_data, _field)) return false;
  if (_val == undefined) return false;
  if (is_real(_data[$ _field]) && !is_real(_val)) return false;

  if (is_real(_val)) {
    if (_min != undefined && _val < _min) {
      if (_clamp) {
        _val = _min;
      } else {
        return false;
      }
    }

    if (_max != undefined && _val > _max) {
      if (_clamp) {
        _val = _max;
      } else {
        return false;
      }
    }
  }

  _data[$ _field] = _val;
  return true;
}

// Reads a real number from a struct with fallback and IGNORE-threshold
// semantics (out-of-range returns _def, never clamped). Supports
// _def=undefined for "skip when invalid" call sites.
// Reads a non-empty string field, else undefined (safe on file data).
function __poly_str(_s, _k) {
  if (!is_struct(_s) || !is_string(_k) || !variable_struct_exists(_s, _k)) return undefined;
  var _v = _s[$ _k];
  return (is_string(_v) && _v != "") ? _v : undefined;
}

function __poly_read_num(_s, _k, _def, _min, _max) {
  if (!is_struct(_s) || !is_string(_k) || !variable_struct_exists(_s, _k)) return _def;
  var _v = _s[$ _k];

  if (!is_real(_v)) return _def;
  if (_min != undefined && _v < _min) return _def;
  if (_max != undefined && _v > _max) return _def;
  return _v;
}

// Reads a 3-element numeric array from a struct, returning a copy.
// On invalid source returns _def verbatim when _def is undefined (skip
// pattern), else a copy of _def (or [0,0,0] when _def is malformed).
function __poly_read_vec(_s, _k, _def) {
  var _fallback = undefined;

  if (_def != undefined) _fallback = (is_array(_def) && array_length(_def) == 3) ? [ _def[0], _def[1], _def[2] ] : [ 0, 0, 0 ];
  if (!is_struct(_s) || !is_string(_k) || !variable_struct_exists(_s, _k)) return _fallback;
  var _a = _s[$ _k];

  if (!is_array(_a) || array_length(_a) != 3 || !is_real(_a[0]) || !is_real(_a[1]) || !is_real(_a[2])) return _fallback;
  return [ _a[0], _a[1], _a[2] ];
}

// Reads an rgb color array like __poly_read_vec, clamped to [0,255].
// Same _def=undefined skip pattern as __poly_read_vec.
function __poly_read_col(_s, _k, _def) {
  var _v = __poly_read_vec(_s, _k, _def);

  if (_v == undefined) return undefined;
  _v[0] = clamp(_v[0], 0, 255);
  _v[1] = clamp(_v[1], 0, 255);
  _v[2] = clamp(_v[2], 0, 255);
  return _v;
}

// ---------------------------------------------------------------------------
// Enum maps
// ---------------------------------------------------------------------------

// Converts light enum to string.
function __poly_light_type_to_str(_v) {
  if (_v == GM3D_ELightType.Point) return "point";
  if (_v == GM3D_ELightType.Spot) return "spot";
  if (_v == GM3D_ELightType.Directional) return "directional";
  return undefined;
}

// Converts light string to enum.
function __poly_light_type_to_enum(_s) {
  if (_s == "point") return GM3D_ELightType.Point;
  if (_s == "spot") return GM3D_ELightType.Spot;
  return GM3D_ELightType.Directional;
}

// Converts projection enum to string.
function __poly_cam_proj_to_str(_v) {
  if (_v == GM3D_ECameraProjection.Orthographic) return "ortho";
  if (_v == GM3D_ECameraProjection.Perspective) return "perspective";
  return undefined;
}

// Converts projection string to enum.
function __poly_cam_proj_to_enum(_s) {
  if (_s == "ortho") return GM3D_ECameraProjection.Orthographic;
  return GM3D_ECameraProjection.Perspective;
}

// ---------------------------------------------------------------------------
// Lights
// ---------------------------------------------------------------------------

// Reads an enabled-style flag (true/1) with fallback.
function __poly_read_flag(_v, _cur) {
  return _v == undefined ? _cur : (_v == true || _v == 1);
}

// Reads light properties from node.
function __poly_light_read(_node) {
  var _d = __poly_light_defaults();
  var _lc = _node.getLightComponent();

  if (_lc == undefined) return _d;
  var _type = __poly_light_type_to_str(_lc.getType());

  if (_type != undefined) _d.type = _type;
  var _col = _lc.getColor();

  if (is_real(_col)) _d.color = [ colour_get_red(_col), colour_get_green(_col), colour_get_blue(_col) ];
  __poly_apply_field(_d, "intensity", _lc.getIntensity());

  var _val = _lc.getRange();

  if (is_real(_val) && _val > 0) _d.range = _val;
  var _iv = _lc.getInnerConeAngle();
  __poly_apply_field(_d, "inner", is_real(_iv) ? radtodeg(_iv) : undefined);

  var _ov = _lc.getOuterConeAngle();
  __poly_apply_field(_d, "outer", is_real(_ov) ? radtodeg(_ov) : undefined);

  _d.enabled = __poly_read_flag(_lc.getEnabled(), _d.enabled);
  _d.shadow = __poly_read_flag(_lc.getShadowEnabled(), _d.shadow);

  _val = _lc.getShadowResolution();

  if (is_real(_val) && _val > 0) _d.shadowRes = _val;
  _val = _lc.getShadowDistance();

  if (is_real(_val) && _val > 0) _d.shadowDist = _val;
  _val = _lc.getShadowNormalOffset();

  if (is_real(_val) && _val >= 0) _d.shadowNormal = _val;
  return _d;
}

// Snaps a shadow map resolution to what LightComponent accepts:
// a power of two in [256, 8192]. Anything else throws at apply time.
function __poly_shadow_res_snap(_v) {
  if (!is_real(_v)) return 2048;
  var _clamped = clamp(round(_v), 256, 8192);
  var _pow = 256;

  while (_pow * 2 <= _clamped) _pow *= 2;
  var _up = min(_pow * 2, 8192);

  if ((_up - _clamped) < (_clamped - _pow)) _pow = _up;
  return _pow;
}

// Applies light properties to node.
function __poly_light_apply(_node, _d, _show_shadows = undefined) {
  if (_node == undefined || _d == undefined) return;
  var _lc = _node.getLightComponent();

  if (_lc == undefined) return;
  _lc.setType(__poly_light_type_to_enum(_d.type));
  _lc.setColor(make_colour_rgb(clamp(_d.color[0], 0, 255), clamp(_d.color[1], 0, 255), clamp(_d.color[2], 0, 255)));
  _lc.setIntensity(max(_d.intensity, 0));

  if (_d.type != "directional") _lc.setRange(max(_d.range, 0.01));

  if (_d.type == "spot") {
    _lc.setInnerConeAngle(degtorad(clamp(_d.inner, 0, 89)));
    _lc.setOuterConeAngle(degtorad(clamp(_d.outer, 1, 89)));
  }

  _lc.setEnabled(_d.enabled == true);

  if (_d.type == "directional") {
    _lc.setShadowEnabled(_d.shadow == true);
    _lc.setShadowResolution(__poly_shadow_res_snap(_d.shadowRes));
    _lc.setShadowDistance(max(_d.shadowDist, 1));
    _lc.setShadowNormalOffset(clamp(_d.shadowNormal, 0, 1));
  }

  if (_show_shadows == undefined) {
    var _gi = __poly_inst();
    _show_shadows = (_gi == undefined) ? true : _gi.show_shadows != false;
  }

  if (_show_shadows == false) _lc.setShadowEnabled(false);
}

// Applies shadow preview override to tracked directionals.
function __poly_shadowpreview_apply(_ed) {
  if (_ed == undefined) return;
  var _roots = __poly_root_tracked(_ed);

  for (var _i = 0, _n = array_length(_roots); _i < _n; _i++) {
    var _node = _roots[_i];

    if (__poly_kind_of(_ed, _node) != "light") continue;
    var _en = __poly_registry_find(_ed, _node);

    if (_en == undefined || !is_struct(_en.data) || _en.data.type != "directional") continue;
    var _lc = _node.getLightComponent();

    if (_lc == undefined) continue;
    _lc.setShadowEnabled(_ed.show_shadows != false && _en.data.shadow == true);
  }

  _ed.view_dirty = true;
}

// Counts tracked lights (any type; shaders expose 8 slots total).
function __poly_light_count(_ed) {
  var _n = 0;
  var _ens = __poly_reg_each(_ed);

  for (var _i = 0, _nt = array_length(_ens); _i < _nt; _i++) {
    var _en = _ens[_i];

    if (is_struct(_en) && variable_struct_exists(_en, "kind") && _en.kind == "light") _n++;
  }

  return _n;
}

// Finds another light node with shadow maps enabled (single map only).
function __poly_shadow_owner(_ed, _except) {
  if (_ed == undefined) return undefined;
  var _roots = __poly_tracked_nodes(_ed);

  for (var _i = 0, _n = array_length(_roots); _i < _n; _i++) {
    var _node = _roots[_i];

    if (_node == undefined || __poly_node_same(_node, _except)) continue;
    if (__poly_kind_of(_ed, _node) != "light") continue;
    var _en = __poly_registry_find(_ed, _node);

    if (_en != undefined && is_struct(_en.data) && _en.data.shadow == true) return _node;
  }

  return undefined;
}

// ---------------------------------------------------------------------------
// Cameras
// ---------------------------------------------------------------------------

// Reads camera properties from node.
function __poly_camera_read(_node) {
  var _d = __poly_camera_defaults();
  var _cc = _node.getCameraComponent();

  if (_cc == undefined) return _d;
  var _proj = __poly_cam_proj_to_str(_cc.getProjection());

  if (_proj != undefined) _d.projection = _proj;
  var _val = _cc.getFovY();

  if (is_real(_val) && _val > 0) _d.fov = radtodeg(_val);
  _val = _cc.getOrthoWidth();

  if (is_real(_val) && _val > 0) _d.ow = _val;
  _val = _cc.getOrthoHeight();

  if (is_real(_val) && _val > 0) _d.oh = _val;
  _val = _cc.getNear();

  if (is_real(_val) && _val > 0) _d.near = _val;
  _val = _cc.getFar();

  if (is_real(_val) && _val > _d.near) _d.far = _val;
  _d.enabled = __poly_read_flag(_cc.getEnabled(), _d.enabled);
  return _d;
}

// Applies camera properties to node.
function __poly_camera_apply(_node, _d) {
  if (_node == undefined || _d == undefined) return;
  var _cc = _node.getCameraComponent();

  if (_cc == undefined) return;
  _cc.setProjection(__poly_cam_proj_to_enum(_d.projection));

  if (_d.projection == "ortho") {
    _cc.setOrthoWidth(max(_d.ow, 0.01));
    _cc.setOrthoHeight(max(_d.oh, 0.01));
  } else {
    _cc.setFovY(degtorad(clamp(_d.fov, 1, 179)));
  }

  _cc.setNear(max(_d.near, 0.01));
  _cc.setFar(max(_d.far, _d.near + 0.01));
  _cc.setEnabled(_d.enabled == true);
}

// Resolves gameplay camera: first enabled, else first.
function __poly_gamecam_resolve(_ed) {
  if (_ed == undefined) return undefined;
  var _pairs = __poly_root_pairs(_ed);
  var _first = undefined;
  var _enabled = undefined;

  for (var _i = 0, _n = array_length(_pairs); _i < _n; _i++) {
    if (_pairs[_i].en.kind != "camera") continue;
    var _node = _pairs[_i].node;
    var _en = _pairs[_i].en;
    _first ??= _node;

    if (!is_struct(_en.data)) continue;
    if (_enabled == undefined && _en.data.enabled == true) _enabled = _node;
  }

  if (_enabled != undefined) return _enabled;
  return _first;
}

// Ensures a gameplay camera exists, creating a default one when missing.
function __poly_gamecam_ensure(_ed) {
  var _found = __poly_gamecam_resolve(_ed);

  if (_found != undefined) return _found;
  if (_ed == undefined || _ed.rt == undefined || _ed.rt.scene == undefined) return undefined;
  var _node = _ed.rt.scene.createNode(__poly_wrap_new(_ed));

  if (_node == undefined) return undefined;
  _node.addComponent(new GM3D_CameraComponent());
  var _pos = [ 0, 2, 5 ];

  if (_ed.rt.cam != undefined) {
    var _seed = _ed.rt.cam.getWorldPosition();
    _pos = [ _seed.x, _seed.y, _seed.z ];
  }

  _node.setLocalPosition(new GM3D_Vec3(_pos[0], _pos[1], _pos[2]));
  var _data = __poly_camera_defaults();
  __poly_camera_apply(_node, _data);
  _ed.rt.scene.update(0);
  var _pp = _node.getLocalPosition();
  __poly_kind_register(_ed, _node, "camera", "", undefined, _data);
  return _node;
}

// Disables one tracked scene camera (never the editor view camera).
function __poly_camera_mute_node(_ed, _node) {
  if (_node == _ed.rt.cam) return;
  if (__poly_kind_of(_ed, _node) != "camera") return;
  var _cc = _node.getCameraComponent();

  if (_cc != undefined) _cc.setEnabled(false);
}

// Disables all tracked scene cameras.
function __poly_cameras_mute(_ed) {
  if (_ed == undefined || _ed.rt == undefined) return;
  var _roots = __poly_root_tracked(_ed);

  for (var _i = 0, _n = array_length(_roots); _i < _n; _i++) __poly_camera_mute_node(_ed, _roots[_i]);
}

// Restores tracked cameras enabled state.
function __poly_cameras_restore(_ed) {
  if (_ed == undefined || _ed.rt == undefined) return;
  var _roots = __poly_root_tracked(_ed);

  for (var _i = 0, _n = array_length(_roots); _i < _n; _i++) {
    var _en = __poly_registry_find(_ed, _roots[_i]);

    if (_en == undefined || !is_struct(_en.data)) continue;
    if (__poly_kind_of(_ed, _roots[_i]) != "camera") continue;
    var _cc = _roots[_i].getCameraComponent();

    if (_cc != undefined) _cc.setEnabled(_en.data.enabled == true);
  }
}

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------

// Reads environment properties from node.
function __poly_env_read(_node) {
  var _d = __poly_env_defaults();
  var _ec = _node.getEnvironmentVolumeComponent();

  if (_ec == undefined) return _d;
  var _size = _ec.getSize();

  if (is_array(_size) && array_length(_size) == 3) {
    _d.size = [ max(_size[0], 0.01), max(_size[1], 0.01), max(_size[2], 0.01) ];
  } else if (is_struct(_size) && variable_struct_exists(_size, "x")) {
    _d.size = [ max(_size.x, 0.01), max(_size.y, 0.01), max(_size.z, 0.01) ];
  }

  var _col = _ec.getAmbientColor();

  if (is_real(_col)) _d.ambient = [ colour_get_red(_col), colour_get_green(_col), colour_get_blue(_col) ];
  _d.fog = __poly_read_flag(_ec.getFogEnabled(), _d.fog);

  _col = _ec.getFogColor();

  if (is_real(_col)) _d.fogcolor = [ colour_get_red(_col), colour_get_green(_col), colour_get_blue(_col) ];
  __poly_apply_field(_d, "fogstart", _ec.getFogStart());
  __poly_apply_field(_d, "fogend", _ec.getFogEnd());

  _d.enabled = __poly_read_flag(_ec.getEnabled(), _d.enabled);
  return _d;
}

// Applies environment properties to node.
function __poly_env_apply(_node, _d) {
  if (_node == undefined || _d == undefined) return;
  var _ec = _node.getEnvironmentVolumeComponent();

  if (_ec == undefined) return;
  _ec.setSize(new GM3D_Vec3(max(_d.size[0], 0.01), max(_d.size[1], 0.01), max(_d.size[2], 0.01)));
  _ec.setAmbientColor(make_colour_rgb(clamp(_d.ambient[0], 0, 255), clamp(_d.ambient[1], 0, 255), clamp(_d.ambient[2], 0, 255)));
  _ec.setFogEnabled(_d.fog == true);
  _ec.setFogColor(make_colour_rgb(clamp(_d.fogcolor[0], 0, 255), clamp(_d.fogcolor[1], 0, 255), clamp(_d.fogcolor[2], 0, 255)));
  _ec.setFogStart(_d.fogstart);
  _ec.setFogEnd(max(_d.fogend, _d.fogstart + 0.01));
  _ec.setEnabled(_d.enabled == true);
}

// Finds tracked environment node.
function __poly_env_node(_ed) {
  var _pairs = __poly_root_pairs(_ed);

  for (var _i = 0, _n = array_length(_pairs); _i < _n; _i++) if (_pairs[_i].en.kind == "environment") return _pairs[_i].node;
  return undefined;
}

// ---------------------------------------------------------------------------
// Creation
// ---------------------------------------------------------------------------

// Registers a fresh node and selects it.
function __poly_create_finish(_ed, _node, _kind, _label, _data) {
  _ed.rt.scene.update(0);
  __poly_kind_register(_ed, _node, _kind, "", _label, _data);
  _ed.sel = [ _node ];
  _ed.giz.drag = -1;
}

// Snapshots undo then creates the wrapper node (snap-first: the empty
// node must not leak into the before-snapshot). Undefined when impossible.
function __poly_create_begin(_ed) {
  if (_ed == undefined || _ed.rt == undefined) return undefined;
  var _before = __poly_history_snap(_ed);
  var _node = _ed.rt.scene.createNode(__poly_wrap_new(_ed));

  if (_node == undefined) return undefined;
  return { before: _before, node: _node };
}

// Creates new light node in scene (wrapper carries id + component).
function __poly_create_light(_ed, _type) {
  if (_type != "point" && _type != "spot") _type = "directional";
  var _b = __poly_create_begin(_ed);

  if (_b == undefined) return undefined;
  var _before = _b.before;
  var _node = _b.node;
  _node.addComponent(new GM3D_LightComponent());

  if (_type == "directional") {
    _node.setLocalPosition(new GM3D_Vec3(0, 3, 0));
    _node.setLocalRotation(__poly_euler_to_quat(degtorad(-50), 0, 0));
  } else {
    _node.setLocalPosition(new GM3D_Vec3(0, 2, 0));
  }

  var _data = __poly_light_defaults();
  _data.type = _type;
  __poly_light_apply(_node, _data);
  __poly_create_finish(_ed, _node, "light", undefined, _data);
  __poly_sel_assign(_ed, [ _node ]);
  __poly_history_commit(_ed, _before);
  return _node;
}

// Creates new camera node in scene (wrapper carries id + component).
function __poly_create_camera(_ed, _proj) {
  if (_proj != "ortho") _proj = "perspective";
  var _b = __poly_create_begin(_ed);

  if (_b == undefined) return undefined;
  var _before = _b.before;
  var _node = _b.node;
  _node.addComponent(new GM3D_CameraComponent());
  _node.setLocalPosition(new GM3D_Vec3(0, 2, 5));
  var _data = __poly_camera_defaults();
  _data.projection = _proj;
  __poly_camera_apply(_node, _data);
  __poly_create_finish(_ed, _node, "camera", undefined, _data);
  _ed.sel = [ _node ];
  _ed.giz.drag = -1;
  __poly_history_commit(_ed, _before);
  __poly_cameras_mute(_ed);
  return _node;
}


// Creates a primitive (cube/sphere) instance at origin.
function __poly_create_primitive(_ed, _type) {
  var _rel = "";
  if (_type == "sphere") _rel = "__PolygonEditor__/models/sphere.glb";
  else if (_type == "plane") _rel = "__PolygonEditor__/models/plane.glb";
  else if (_type == "quad") _rel = "__PolygonEditor__/models/quad.glb";
  else if (_type == "cylinder") _rel = "__PolygonEditor__/models/cylinder.glb";
  else if (_type == "capsule") _rel = "__PolygonEditor__/models/capsule.glb";
  else _rel = "__PolygonEditor__/models/cube.glb";
  var _asset = _rel;
  // Cache loaded models in a static struct.
  static _cache = undefined;
  if (_cache == undefined) _cache = {};
  var _model = undefined;
  if (variable_struct_exists(_cache, _rel)) {
    _model = _cache[$ _rel];
  } else {
    var _path = working_directory + _rel;
    if (file_exists(_path)) {
      _model = GM3D_Scene.loadGltf(_path);
      if (_model != undefined) {
        var _mats = _model.getMaterials();
        for (var _mi = 0, _mn = array_length(_mats); _mi < _mn; _mi++) _mats[_mi].setShader(GM3D_ERenderPass.Forward, shPolygonEditorLit);
        _model.freeze();
      }
    }
    _cache[$ _rel] = _model;
  }
  if (_model == undefined) return undefined;
  var _before = __poly_history_snap(_ed);
  var _node = __poly_place(_ed, _asset, _model, [ 0, 0, 0 ], undefined, [ 1, 1, 1 ], undefined);
  if (_node == undefined) return undefined;
  _ed.rt.scene.update(0);
  var _shadow_data = { castShadows: true, receiveShadows: true };
  __poly_kind_register(_ed, _node, "instance", _asset, undefined, _shadow_data);
  var _en = __poly_registry_find(_ed, _node);
  if (_en != undefined) {
    _en.asset = _asset;
  }
  _ed.sel = [ _node ];
  _ed.giz.drag = -1;
  __poly_history_commit(_ed, _before);
  return _node;
}
// Creates new environment node in scene (wrapper carries id + component).
function __poly_create_env(_ed) {
  if (_ed == undefined || _ed.rt == undefined) return undefined;
  if (__poly_env_node(_ed) != undefined) return undefined;
  var _b = __poly_create_begin(_ed);

  if (_b == undefined) return undefined;
  var _before = _b.before;
  var _node = _b.node;
  _node.addComponent(new GM3D_EnvironmentVolumeComponent());
  var _data = __poly_env_defaults();
  __poly_env_apply(_node, _data);
  __poly_create_finish(_ed, _node, "environment", undefined, _data);
  _ed.sel = [ _node ];
  _ed.giz.drag = -1;
  __poly_history_commit(_ed, _before);
  return _node;
}
