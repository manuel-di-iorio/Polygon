// Loads scene file into runtime scene.
function polygon_load(_scene, _fname, _models) {
  var _rep = { placed: 0, failed: 0 };

  if (_scene == undefined || _fname == undefined || _fname == "" || !is_struct(_models)) return _rep;
  if (!file_exists(_fname)) return _rep;
  var _json = "";
  var _f = file_text_open_read(_fname);

  if (_f < 0) return _rep;

  while (!file_text_eof(_f)) {
    _json += file_text_read_string(_f);
    file_text_readln(_f);
  }

  file_text_close(_f);

  if (_json == "") return _rep;
  var _data = undefined;
  _data = json_parse(_json);

  if (!is_struct(_data) || !variable_struct_exists(_data, "nodes") || !is_array(_data.nodes)) return _rep;
  var _nodes = _data.nodes;

  for (var _i = 0, _nnod = array_length(_nodes); _i < _nnod; ++_i) {
    var _ok = false;
    _ok = __polygon_load_node(_scene, _models, _nodes[_i]) != undefined;

    if (_ok) {
      _rep.placed++;
    } else {
      _rep.failed++;
    }
  }

  _scene.update(0);
  return _rep;
}

// Spawns single node from descriptor (v2: id/label/asset).
// Assets spawn inside a wrapper named after the id so editor imports
// preserve identity; props are single nodes carrying the id.
function __polygon_load_node(_scene, _models, _p) {
  if (_scene == undefined || !is_struct(_p)) return undefined;
  var _kind = undefined;

  if (variable_struct_exists(_p, "kind") && is_string(_p.kind) && _p.kind != "") _kind = _p.kind;
  var _id = "node";

  if (variable_struct_exists(_p, "id") && is_string(_p.id) && _p.id != "") {
    _id = _p.id;
  } else if (variable_struct_exists(_p, "label") && is_string(_p.label) && _p.label != "") {
    _id = _p.label;
  } else if (variable_struct_exists(_p, "name") && is_string(_p.name) && _p.name != "") {
    _id = _p.name;
  }

  if (_kind == "light" || _kind == "camera" || _kind == "environment") return __polygon_load_prop(_scene, _p, _kind, _id);
  if (_kind != "instance") return undefined;
  if (!variable_struct_exists(_p, "asset") || !is_string(_p.asset) || _p.asset == "") return undefined;
  var _akey = _p.asset;

  if (!variable_struct_exists(_models, _akey)) return undefined;
  var _model = _models[$ _akey];

  if (_model == undefined) return undefined;
  var _flags = undefined;

  if (variable_struct_exists(_p, "flags") && is_struct(_p.flags)) {
    _flags = { castShadows: _p.flags[$ "castShadows"] == true, receiveShadows: _p.flags[$ "receiveShadows"] == true };
  }

  return __polygon_spawn(_scene, {
    kind: "instance",
    model: _model,
    pos: _p.position,
    rotation: _p.rotation,
    scale: _p.scale,
    id: _id,
    data: _flags,
    skip_hook: true,
    skip_register: true,
  });
}

// Creates light camera environment from descriptor.
function __polygon_load_prop(_scene, _p, _kind, _name) {
  var _node = _scene.createNode(_name);

  if (_node == undefined) return undefined;
  _node.setLocalPosition(__polygon_load_vec3(_p, "position", 0, 0, 0));
  _node.setLocalScale(__polygon_load_vec3(_p, "scale", 1, 1, 1));

  if (_kind == "camera") {
    _node.setLocalRotation(__polygon_quat_no_roll(__polygon_load_quat(_p)));
  } else {
    _node.setLocalRotation(__polygon_load_quat(_p));
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
    var _lt = __polygon_str(_l, "type");
    _lc.setType(_lt == "point" ? GM3D_ELightType.Point : _lt == "spot" ? GM3D_ELightType.Spot : GM3D_ELightType.Directional);

    var _lic = __polygon_read_col(_l, "color", undefined);

    if (_lic != undefined) _lc.setColor(make_colour_rgb(_lic[0], _lic[1], _lic[2]));
    var _lii = __polygon_read_num(_l, "intensity", undefined, undefined, undefined);

    if (_lii != undefined) _lc.setIntensity(max(_lii, 0));
    var _rg = _l[$ "range"];

    if (is_real(_rg) && _rg > 0) _lc.setRange(_rg);
    var _licone = __polygon_read_num(_l, "innerCone", undefined, undefined, undefined);

    if (_licone != undefined) _lc.setInnerConeAngle(degtorad(clamp(_licone, 0, 89)));
    var _locone = __polygon_read_num(_l, "outerCone", undefined, undefined, undefined);

    if (_locone != undefined) _lc.setOuterConeAngle(degtorad(clamp(_locone, 1, 89)));
    _lc.setEnabled(!variable_struct_exists(_l, "enabled") || _l.enabled == true);

    if (is_struct(_l[$ "shadow"])) {
      var _sh = _l[$ "shadow"];
      _lc.setShadowEnabled(!variable_struct_exists(_sh, "enabled") || _sh.enabled == true);

      if (variable_struct_exists(_sh, "resolution") && is_real(_sh.resolution) && _sh.resolution > 0) _lc.setShadowResolution(__polygon_shadow_res_snap(_sh.resolution));
      if (variable_struct_exists(_sh, "distance") && is_real(_sh.distance) && _sh.distance > 0) _lc.setShadowDistance(max(_sh.distance, 1));
      if (variable_struct_exists(_sh, "normalOffset") && is_real(_sh.normalOffset) && _sh.normalOffset >= 0) _lc.setShadowNormalOffset(clamp(_sh.normalOffset, 0, 1));
    }
  } else if (_kind == "camera") {

    var _cc = new GM3D_CameraComponent();
    _node.addComponent(_cc);
    var _c = _sub;
    var _cp = __polygon_str(_c, "projection");
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

    var _esz = __polygon_read_vec(_e, "size", undefined);

    if (_esz != undefined) _ec.setSize(new GM3D_Vec3(max(_esz[0], 0.01), max(_esz[1], 0.01), max(_esz[2], 0.01)));
    var _eamb = __polygon_read_col(_e, "ambient", undefined);

    if (_eamb != undefined) _ec.setAmbientColor(make_colour_rgb(_eamb[0], _eamb[1], _eamb[2]));
    _ec.setFogEnabled(_e[$ "fogEnabled"] == true);

    var _efc = __polygon_read_col(_e, "fogColor", undefined);

    if (_efc != undefined) _ec.setFogColor(make_colour_rgb(_efc[0], _efc[1], _efc[2]));
    var _efs = __polygon_read_num(_e, "fogStart", undefined, undefined, undefined);

    if (_efs != undefined) _ec.setFogStart(_efs);
    var _efe = __polygon_read_num(_e, "fogEnd", undefined, undefined, undefined);

    if (_efe != undefined) _ec.setFogEnd(_efe);
    _ec.setEnabled(!variable_struct_exists(_e, "enabled") || _e.enabled == true);
  } else {
    _node.destroy();
    return undefined;
  }

  return _node;
}

// Parses vector from descriptor with fallback.
function __polygon_load_vec3(_p, _field, _fx, _fy, _fz) {
  var _a = _p[$ _field];

  if (is_array(_a) && array_length(_a) == 3 && is_real(_a[0]) && is_real(_a[1]) && is_real(_a[2])) return new GM3D_Vec3(_a[0], _a[1], _a[2]);
  return new GM3D_Vec3(_fx, _fy, _fz);
}

// Parses quaternion from descriptor with fallback.
function __polygon_load_quat(_p) {
  var _a = _p.rotation;

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
