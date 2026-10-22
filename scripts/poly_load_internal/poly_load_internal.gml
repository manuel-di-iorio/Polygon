
// Queues a runtime load job.
function __poly_load_jobs_push(_job) {
  if (!variable_global_exists("__poly_load_jobs") || !is_array(global.__poly_load_jobs)) global.__poly_load_jobs = [];
  array_push(global.__poly_load_jobs, _job);
}

// Places one descriptor of a job (hooks, companions and report included).
function __poly_load_place(_job, _p) {
  var _rep = _job.report;
  var _pl = __poly_load_node(_job.scene, _job.assets, _p, _job.actors);

  if (_pl == undefined) {
    _rep.failed++;
    return;
  }

  _rep.placed++;
  if (!is_struct(_pl) || _pl.kind != "instance") return;
  if (is_method(_job.on_create)) _job.on_create(_pl.node, _pl.asset, _pl.model, _pl.id);
  var _entry = _job.assets[$ _pl.asset];
  if (is_struct(_entry) && is_method(_entry[$ "on_create"])) _entry.on_create(_pl.node, _pl.asset, _pl.model, _pl.id);
  var _inst = undefined;

  if (__poly_load_actor(_job.actors, _pl, _rep)) {
    _rep.companions++;
    _inst = __poly_actor_of(_pl.id);
  }

  var _physics = variable_struct_exists(_pl, "physics") ? _pl.physics : __poly_physics_live_read(_pl.node);
  array_push(_rep.placements, { node: _pl.node, asset: _pl.asset, id: _pl.id, label: _pl.label, model: _pl.model, instance: _inst, physics: _physics });
}

// Reads the tolerant per-model file map ("assets"). Unknown content is
// ignored: only struct values are kept.
function __poly_file_assets(_data) {
  var _out = {};

  if (!is_struct(_data) || !is_struct(_data[$ "assets"])) return _out;
  var _src = _data.assets;
  var _keys = variable_struct_get_names(_src);

  for (var _i = 0, _n = array_length(_keys); _i < _n; _i++) {
    var _v = _src[$ _keys[_i]];

    if (is_struct(_v)) _out[$ _keys[_i]] = _v;
  }

  return _out;
}

// Spawns the companion instance for a placement when the file carries an
// actor binding for its asset key. Never fails the load: problems become
// report warnings. Returns true when a companion was created.
function __poly_load_actor(_actors, _pl, _rep) {
  if (!is_struct(_actors) || _pl == undefined) return false;
  if (!variable_struct_exists(_actors, _pl.asset)) return false;
  var _meta = _actors[$ _pl.asset];

  if (!is_struct(_meta)) return false;
  if (variable_struct_exists(_meta, "type") && _meta.type != "model") return false;
  if (!variable_struct_exists(_meta, "actor") || !is_struct(_meta.actor)) return false;
  var _ac = _meta.actor;
  var _obj_name = _ac[$ "object"];

  if (!is_string(_obj_name) || _obj_name == "") return false;
  var _oi = asset_get_index(_obj_name);

  if (_oi < 0 || !object_exists(_oi)) {
    array_push(_rep.warnings, "actor object '" + _obj_name + "' not found for asset '" + _pl.asset + "'");
    return false;
  }

  var _layer = _ac[$ "layer"];

  if (!is_string(_layer) || _layer == "") _layer = "Instances";

  if (!layer_exists(_layer)) {
    array_push(_rep.warnings, "actor layer '" + _layer + "' not found for asset '" + _pl.asset + "'");
    return false;
  }

  var _inst = instance_create_layer(0, 0, _layer, _oi, { node: _pl.node, poly_id: _pl.id, poly_asset_id: _pl.asset });
  __poly_actor_map()[$ _pl.id] = _inst;
  return true;
}

// ---------------------------------------------------------------------------
// Actor companions (node <-> instance binding)
// ---------------------------------------------------------------------------

// Returns the node-id -> companion-instance map, creating it.
function __poly_actor_map() {
  if (!variable_global_exists("__poly_actor_map")) global.__poly_actor_map = {};
  return global.__poly_actor_map;
}



// Spawns single node from descriptor (v1: id/asset).
// Assets spawn inside a wrapper named after the id so editor imports
// preserve identity; props are single nodes carrying the id.
// Returns a placement struct { node, kind, asset, id, label, model } for
// spawned instances (asset/model feed the spawn hooks and companions),
// { node, kind, ... } for props, or undefined on failure.
function __poly_load_node(_scene, _assets, _p, _meta = undefined) {
  if (_scene == undefined || !is_struct(_p)) return undefined;
  var _kind = undefined;

  if (variable_struct_exists(_p, "kind") && is_string(_p.kind) && _p.kind != "") _kind = _p.kind;
  var _id = "node";

  if (variable_struct_exists(_p, "id") && is_string(_p.id) && _p.id != "") {
    _id = _p.id;
  } else if (variable_struct_exists(_p, "name") && is_string(_p.name) && _p.name != "") {
    _id = _p.name;
  }

  if (_kind == "light" || _kind == "camera" || _kind == "environment") {
    var _prop = __poly_load_prop(_scene, _p, _kind, _id);
    if (_prop == undefined) return undefined;
    return { node: _prop, kind: _kind, asset: "", id: _id, label: _p[$ "label"], model: undefined };
  }

  if (_kind != "instance") return undefined;
  if (!variable_struct_exists(_p, "assetId") || !is_string(_p.assetId) || _p.assetId == "") return undefined;
  var _akey = _p.assetId;

  if (!variable_struct_exists(_assets, _akey) || !is_struct(_assets[$ _akey])) return undefined;
  var _entry = _assets[$ _akey];
  var _model = _entry[$ "model"];

  if (_model == undefined) return undefined;
  var _flags = undefined;

  if (variable_struct_exists(_p, "shadows") && is_struct(_p.shadows)) {
    _flags = { castShadows: _p.shadows[$ "cast"] == true, receiveShadows: _p.shadows[$ "receive"] == true };
  }
  if (!is_struct(_flags)) _flags = {};
  if (variable_struct_exists(_p, "physics")) _flags.physics = __poly_physics_data(_p.physics);
  else if (is_struct(_meta) && is_struct(_meta[$ _akey]) && is_struct(_meta[$ _akey][$ "physics"])) _flags.physics = __poly_physics_data(_meta[$ _akey].physics);

  var _t = is_struct(_p[$ "transform"]) ? _p.transform : {};

  var _node = __poly_spawn(_scene, {
    kind: "instance",
    model: _model,
    pos: _t[$ "position"],
    rotation: _t[$ "rotation"],
    scale: _t[$ "scale"],
    id: _id,
    data: _flags,
    skip_hook: true,
    skip_register: true,
  });

  if (_node == undefined) return undefined;
  return { node: _node, kind: "instance", asset: _akey, id: _id, label: _p[$ "label"], model: _model, physics: is_struct(_flags[$ "physics"]) ? _flags.physics : undefined };
}

// Creates light camera environment from descriptor.
function __poly_load_prop(_scene, _p, _kind, _name) {
  var _node = _scene.createNode(_name);

  if (_node == undefined) return undefined;
  var _t = is_struct(_p[$ "transform"]) ? _p.transform : {};
  _node.setLocalPosition(__poly_load_vec3(_t, "position", 0, 0, 0));
  _node.setLocalScale(__poly_load_vec3(_t, "scale", 1, 1, 1));

  if (_kind == "camera") {
    _node.setLocalRotation(__poly_quat_no_roll(__poly_load_quat(_t)));
  } else {
    _node.setLocalRotation(__poly_load_quat(_t));
  }

  var _sub = is_struct(_p) ? _p[$ _kind] : undefined;

  if (!is_struct(_sub)) {
    _node.destroy();
    return undefined;
  }

  if (_kind == "light") {
    var _lc = new GM3D_LightComponent();
    _node.addComponent(_lc);
    var _l = _sub;
    var _lt = __poly_str(_l, "type");
    _lc.setType(_lt == "point" ? GM3D_ELightType.Point : _lt == "spot" ? GM3D_ELightType.Spot : GM3D_ELightType.Directional);

    var _lic = __poly_read_col(_l, "color", undefined);

    if (_lic != undefined) _lc.setColor(make_colour_rgb(_lic[0], _lic[1], _lic[2]));
    var _lii = __poly_read_num(_l, "intensity", undefined, undefined, undefined);

    if (_lii != undefined) _lc.setIntensity(max(_lii, 0));
    var _rg = _l[$ "range"];

    if (is_real(_rg) && _rg > 0) _lc.setRange(_rg);
    var _licone = __poly_read_num(_l, "innerCone", undefined, undefined, undefined);

    if (_licone != undefined) _lc.setInnerConeAngle(degtorad(clamp(_licone, 0, 89)));
    var _locone = __poly_read_num(_l, "outerCone", undefined, undefined, undefined);

    if (_locone != undefined) _lc.setOuterConeAngle(degtorad(clamp(_locone, 1, 89)));
    _lc.setEnabled(!variable_struct_exists(_l, "enabled") || _l.enabled == true);

    if (is_struct(_l[$ "shadow"])) {
      var _sh = _l[$ "shadow"];
      _lc.setShadowEnabled(!variable_struct_exists(_sh, "enabled") || _sh.enabled == true);

      if (variable_struct_exists(_sh, "resolution") && is_real(_sh.resolution) && _sh.resolution > 0) _lc.setShadowResolution(__poly_shadow_res_snap(_sh.resolution));
      if (variable_struct_exists(_sh, "distance") && is_real(_sh.distance) && _sh.distance > 0) _lc.setShadowDistance(max(_sh.distance, 1));
      if (variable_struct_exists(_sh, "normalOffset") && is_real(_sh.normalOffset) && _sh.normalOffset >= 0) _lc.setShadowNormalOffset(clamp(_sh.normalOffset, 0, 1));
    }
  } else if (_kind == "camera") {

    var _cc = new GM3D_CameraComponent();
    _node.addComponent(_cc);
    var _c = _sub;
    var _cp = __poly_str(_c, "projection");
    _cc.setProjection(_cp == "ortho" ? GM3D_ECameraProjection.Orthographic : GM3D_ECameraProjection.Perspective);

    if (_cp == "ortho") {
      var _ow = _c[$ "orthoWidth"];

      if (is_real(_ow) && _ow > 0) _cc.setOrthoWidth(_ow);
      var _oh = _c[$ "orthoHeight"];

      if (is_real(_oh) && _oh > 0) _cc.setOrthoHeight(_oh);
    } else {
      var _fy = _c[$ "fovY"];

      if (is_real(_fy) && _fy > 0) _cc.setFovY(degtorad(clamp(_fy, 1, 179)));
    }

    var _nr = _c[$ "near"];

    if (is_real(_nr) && _nr > 0) _cc.setNear(_nr);
    var _fr = _c[$ "far"];

    if (is_real(_fr) && _fr > 0) _cc.setFar(_fr);
    _cc.setEnabled(!variable_struct_exists(_c, "enabled") || _c.enabled == true);
  } else if (_kind == "environment") {

    var _ec = new GM3D_EnvironmentVolumeComponent();
    _node.addComponent(_ec);
    var _e = _sub;

    var _esz = __poly_read_vec(_e, "size", undefined);

    if (_esz != undefined) _ec.setSize(new GM3D_Vec3(max(_esz[0], 0.01), max(_esz[1], 0.01), max(_esz[2], 0.01)));
    var _eamb = __poly_read_col(_e, "ambient", undefined);

    if (_eamb != undefined) _ec.setAmbientColor(make_colour_rgb(_eamb[0], _eamb[1], _eamb[2]));
    _ec.setFogEnabled(_e[$ "fogEnabled"] == true);

    var _efc = __poly_read_col(_e, "fogColor", undefined);

    if (_efc != undefined) _ec.setFogColor(make_colour_rgb(_efc[0], _efc[1], _efc[2]));
    var _efs = __poly_read_num(_e, "fogStart", undefined, undefined, undefined);

    if (_efs != undefined) _ec.setFogStart(_efs);
    var _efe = __poly_read_num(_e, "fogEnd", undefined, undefined, undefined);

    if (_efe != undefined) _ec.setFogEnd(_efe);
    _ec.setEnabled(!variable_struct_exists(_e, "enabled") || _e.enabled == true);
  } else {
    _node.destroy();
    return undefined;
  }

  return _node;
}

// Parses vector from descriptor with fallback.
function __poly_load_vec3(_p, _field, _fx, _fy, _fz) {
  var _a = _p[$ _field];

  if (is_array(_a) && array_length(_a) == 3 && is_real(_a[0]) && is_real(_a[1]) && is_real(_a[2])) return new GM3D_Vec3(_a[0], _a[1], _a[2]);
  return new GM3D_Vec3(_fx, _fy, _fz);
}

// Parses quaternion from a transform struct with fallback.
function __poly_load_quat(_t) {
  var _a = is_struct(_t) ? _t[$ "rotation"] : undefined;

  if (is_array(_a) && array_length(_a) == 4 && is_real(_a[0]) && is_real(_a[1]) && is_real(_a[2]) && is_real(_a[3])) {
    var _q = new GM3D_Quaternion();
    _q.x = _a[0];
    _q.y = _a[1];
    _q.z = _a[2];
    _q.w = _a[3];
    return _q.normalizeSafe(0.000001);
  }

  var _q0 = new GM3D_Quaternion();
  return _q0;
}
