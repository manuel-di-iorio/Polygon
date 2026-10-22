// poly_physics — editor physics data, GM3D components and static debug view.

function __poly_physics_defaults() {
  return {
    mode: "none",
    shape: "Box",
    layer: "Default",
    mass: 1.0,
    linearDamping: 0.05,
    angularDamping: 0.05,
    gravityFactor: 1.0,
    isSensor: false,
    friction: 0.8,
    restitution: 0.0,
    halfExtents: [0.5, 0.5, 0.5],
    offset: [0.0, 0.0, 0.0],
    character: {
      radius: 0.33,
      halfHeight: 0.92,
      stepHeight: 0.3,
      maxSlopeAngle: 55.0,
      mass: 80.0,
      maxStrength: 160.0,
      visualOffset: [0.0, -0.92, 0.0],
    },
  };
}

function __poly_world_defaults() {
  return { gravity: [0.0, -9.81, 0.0], fixedTimeStep: 1.0 / 60.0, maxSubSteps: 4, maxBodies: 512 };
}

function __poly_physics_copy3(_a) {
  if (!is_array(_a) || array_length(_a) != 3) return [0.0, 0.0, 0.0];
  return [_a[0], _a[1], _a[2]];
}

// Centers the visual model on the wrapper origin for a centered character capsule.
function __poly_physics_fit_visual(_model, _source) {
  var _d = __poly_physics_data(_source);
  if (_model == undefined) return _d;
  var _bb = _model.getBoundingBox();
  if (is_struct(_bb) && _bb.min != undefined && _bb.max != undefined) {
    _d.character.visualOffset = [-(_bb.min.x + _bb.max.x) * 0.5, -(_bb.min.y + _bb.max.y) * 0.5, -(_bb.min.z + _bb.max.z) * 0.5];
  }
  return _d;
}

function __poly_physics_mode_valid(_mode) {
  return _mode == "none" || _mode == "static" || _mode == "kinematic" || _mode == "dynamic" || _mode == "character";
}

function __poly_physics_validate(_source) {
  if (!is_struct(_source)) return false;
  return __poly_validate_asset_desc({ assetId: "__physics_check__", physics: _source });
}

function __poly_physics_data(_source) {
  var _out = __poly_physics_defaults();
  if (!is_struct(_source)) return _out;
  var _keys = ["mode", "shape", "layer", "mass", "linearDamping", "angularDamping", "gravityFactor", "isSensor", "friction", "restitution"];
  for (var _i = 0; _i < array_length(_keys); _i++) {
    var _k = _keys[_i];
    if (variable_struct_exists(_source, _k)) _out[$ _k] = _source[$ _k];
  }
  if (variable_struct_exists(_source, "halfExtents") && is_array(_source.halfExtents) && array_length(_source.halfExtents) == 3) _out.halfExtents = __poly_physics_copy3(_source.halfExtents);
  if (variable_struct_exists(_source, "offset") && is_array(_source.offset) && array_length(_source.offset) == 3) _out.offset = __poly_physics_copy3(_source.offset);
  if (variable_struct_exists(_source, "character") && is_struct(_source[$ "character"])) {
    var _ck = ["radius", "halfHeight", "stepHeight", "maxSlopeAngle", "mass", "maxStrength"];
    for (var _c = 0; _c < array_length(_ck); _c++) if (variable_struct_exists(_source.character, _ck[_c])) _out.character[$ _ck[_c]] = _source.character[$ _ck[_c]];
    if (is_array(_source.character[$ "visualOffset"]) && array_length(_source.character.visualOffset) == 3) _out.character.visualOffset = __poly_physics_copy3(_source.character.visualOffset);
  }
  if (!__poly_physics_mode_valid(_out.mode)) _out.mode = "none";
  if (_out.shape != "Box" && _out.shape != "Sphere" && _out.shape != "Capsule" && _out.shape != "Cylinder" && _out.shape != "Mesh" && _out.shape != "ConvexHull") { _out.shape = "Box"; _out.mode = "none"; }
  if (!is_string(_out.layer)) _out.layer = "Default";
  _out.mass = max(0.001, is_real(_out.mass) ? _out.mass : 1.0);
  _out.linearDamping = max(0.0, is_real(_out.linearDamping) ? _out.linearDamping : 0.05);
  _out.angularDamping = max(0.0, is_real(_out.angularDamping) ? _out.angularDamping : 0.05);
  _out.gravityFactor = is_real(_out.gravityFactor) ? _out.gravityFactor : 1.0;
  _out.isSensor = _out.isSensor == true;
  _out.friction = clamp(is_real(_out.friction) ? _out.friction : 0.8, 0.0, 1.0);
  _out.restitution = clamp(is_real(_out.restitution) ? _out.restitution : 0.0, 0.0, 1.0);
  for (var _a = 0; _a < 3; _a++) {
    _out.halfExtents[_a] = max(0.001, is_real(_out.halfExtents[_a]) ? abs(_out.halfExtents[_a]) : 0.5);
    _out.offset[_a] = is_real(_out.offset[_a]) ? _out.offset[_a] : 0.0;
  }
  return _out;
}

function __poly_physics_apply(_node, _source) {
  if (_node == undefined) return false;
  var _d = __poly_physics_data(_source);
  var _old = _node[$ "findPhysicsBodyComponent"];
  if (_old != undefined) { var _body_old = _node.findPhysicsBodyComponent(); if (_body_old != undefined) _node.removeComponent(_body_old); }
  var _shape_find = _node[$ "findPhysicsShapeComponent"];
  if (_shape_find != undefined) { var _shape_old = _node.findPhysicsShapeComponent(); if (_shape_old != undefined) _node.removeComponent(_shape_old); }
  var _cc_find = _node[$ "findCharacterControllerComponent"];
  var _was_character = false;
  if (_cc_find != undefined) { var _cc_old = _node.findCharacterControllerComponent(); if (_cc_old != undefined) { _was_character = true; _node.removeComponent(_cc_old); } }
  if (_d.mode == "none") {
    if (_was_character) { var _old_visual = __poly_first_child(_node); if (_old_visual != undefined) _old_visual.setLocalPosition(new GM3D_Vec3(0, 0, 0)); }
    return true;
  }
  if (_d.mode == "character") {
    var _cc = new GM3D_CharacterControllerComponent();
    _cc.setRadius(_d.character.radius);
    _cc.setHalfHeight(_d.character.halfHeight);
    _cc.setStepHeight(_d.character.stepHeight);
    _cc.setMaxSlopeAngle(degtorad(_d.character.maxSlopeAngle));
    _cc.setMass(_d.character.mass);
    _cc.setMaxStrength(_d.character.maxStrength);
    _cc.setLayer(GM3D_EPhysicsLayer.Character);
    _node.addComponent(_cc);
    var _visual = __poly_first_child(_node);
    if (_visual != undefined) _visual.setLocalPosition(new GM3D_Vec3(_d.character.visualOffset[0], _d.character.visualOffset[1], _d.character.visualOffset[2]));
    return true;
  }
  if (_was_character) { var _reset_visual = __poly_first_child(_node); if (_reset_visual != undefined) _reset_visual.setLocalPosition(new GM3D_Vec3(0, 0, 0)); }
  var _body = new GM3D_PhysicsBodyComponent();
  _body.setMotionType(_d.mode == "static" ? GM3D_EPhysicsMotionType.Static : _d.mode == "kinematic" ? GM3D_EPhysicsMotionType.Kinematic : GM3D_EPhysicsMotionType.Dynamic);
  _body.setMotionQuality(GM3D_EPhysicsMotionQuality.Discrete);
  _body.setLayer(_d.isSensor || _d.layer == "Trigger" ? GM3D_EPhysicsLayer.Trigger : _d.layer == "Static" ? GM3D_EPhysicsLayer.Static : _d.layer == "Character" ? GM3D_EPhysicsLayer.Character : _d.layer == "Debris" ? GM3D_EPhysicsLayer.Debris : GM3D_EPhysicsLayer.Default);
  _body.setMass(_d.mass);
  _body.setLinearDamping(_d.linearDamping);
  _body.setAngularDamping(_d.angularDamping);
  _body.setGravityFactor(_d.gravityFactor);
  _body.setIsSensor(_d.isSensor);
  _body.setStartAwake(true);
  _body.setAllowSleeping(true);
  _node.addComponent(_body);
  var _shape = new GM3D_PhysicsShapeComponent();
  var _stype = _d.shape == "Sphere" ? GM3D_EPhysicsShapeType.Sphere : _d.shape == "Capsule" ? GM3D_EPhysicsShapeType.Capsule : _d.shape == "Cylinder" ? GM3D_EPhysicsShapeType.Cylinder : _d.shape == "Mesh" ? GM3D_EPhysicsShapeType.Mesh : _d.shape == "ConvexHull" ? GM3D_EPhysicsShapeType.ConvexHull : GM3D_EPhysicsShapeType.Box;
  _shape.setShapeType(_stype);
  _shape.setHalfExtents(new GM3D_Vec3(_d.halfExtents[0], _d.halfExtents[1], _d.halfExtents[2]));
  _shape.setLocalOffset(new GM3D_Vec3(_d.offset[0], _d.offset[1], _d.offset[2]));
  _shape.setFriction(_d.friction);
  _shape.setRestitution(_d.restitution);
  _node.addComponent(_shape);
  return true;
}

function __poly_physics_live_read(_node) {
  if (_node == undefined) return undefined;
  var _body_fn = _node[$ "findPhysicsBodyComponent"];
  var _shape_fn = _node[$ "findPhysicsShapeComponent"];
  var _char_fn = _node[$ "findCharacterControllerComponent"];
  var _cc = _char_fn != undefined ? _node.findCharacterControllerComponent() : undefined;
  var _body = _body_fn != undefined ? _node.findPhysicsBodyComponent() : undefined;
  var _shape = _shape_fn != undefined ? _node.findPhysicsShapeComponent() : undefined;
  if (_cc == undefined && (_body == undefined || _shape == undefined)) return undefined;
  var _out = __poly_physics_defaults();
  if (_cc != undefined) {
    _out.mode = "character";
    _out.shape = "Capsule";
    var _cr = _cc[$ "getRadius"], _ch = _cc[$ "getHalfHeight"], _cs = _cc[$ "getStepHeight"], _cms = _cc[$ "getMaxSlopeAngle"];
    if (_cr != undefined) _out.character.radius = method(_cc, _cr)();
    if (_ch != undefined) _out.character.halfHeight = method(_cc, _ch)();
    if (_cs != undefined) _out.character.stepHeight = method(_cc, _cs)();
    if (_cms != undefined) _out.character.maxSlopeAngle = radtodeg(method(_cc, _cms)());
    var _visual = __poly_first_child(_node);
    if (_visual != undefined) {
      var _vp = _visual.getLocalPosition();
      _out.character.visualOffset = [_vp.x, _vp.y, _vp.z];
    }
    return _out;
  }
  var _motion_fn = _body[$ "getMotionType"];
  if (_motion_fn != undefined) {
    var _motion = method(_body, _motion_fn)();
    _out.mode = _motion == GM3D_EPhysicsMotionType.Static ? "static" : _motion == GM3D_EPhysicsMotionType.Kinematic ? "kinematic" : "dynamic";
  } else _out.mode = "static";
  var _shape_fn2 = _shape[$ "getShapeType"];
  if (_shape_fn2 != undefined) {
    var _st = method(_shape, _shape_fn2)();
    _out.shape = _st == GM3D_EPhysicsShapeType.Sphere ? "Sphere" : _st == GM3D_EPhysicsShapeType.Capsule ? "Capsule" : _st == GM3D_EPhysicsShapeType.Cylinder ? "Cylinder" : _st == GM3D_EPhysicsShapeType.Mesh ? "Mesh" : _st == GM3D_EPhysicsShapeType.ConvexHull ? "ConvexHull" : "Box";
  }
  var _read_body = [["mass", "getMass"], ["linearDamping", "getLinearDamping"], ["angularDamping", "getAngularDamping"], ["gravityFactor", "getGravityFactor"], ["isSensor", "getIsSensor"]];
  for (var _i = 0; _i < array_length(_read_body); _i++) {
    var _fn = _body[$ _read_body[_i][1]];
    if (_fn != undefined) _out[$ _read_body[_i][0]] = method(_body, _fn)();
  }
  var _layer_fn = _body[$ "getLayer"];
  if (_layer_fn != undefined) {
    var _layer = method(_body, _layer_fn)();
    _out.layer = _layer == GM3D_EPhysicsLayer.Static ? "Static" : _layer == GM3D_EPhysicsLayer.Character ? "Character" : _layer == GM3D_EPhysicsLayer.Trigger ? "Trigger" : _layer == GM3D_EPhysicsLayer.Debris ? "Debris" : "Default";
  }
  var _read_shape = [["friction", "getFriction"], ["restitution", "getRestitution"]];
  for (var _j = 0; _j < array_length(_read_shape); _j++) {
    var _sfn = _shape[$ _read_shape[_j][1]];
    if (_sfn != undefined) _out[$ _read_shape[_j][0]] = method(_shape, _sfn)();
  }
  var _he_fn = _shape[$ "getHalfExtents"];
  if (_he_fn != undefined) { var _he = method(_shape, _he_fn)(); _out.halfExtents = [_he.x, _he.y, _he.z]; }
  var _off_fn = _shape[$ "getLocalOffset"];
  if (_off_fn != undefined) { var _off = method(_shape, _off_fn)(); _out.offset = [_off.x, _off.y, _off.z]; }
  return __poly_physics_data(_out);
}

function __poly_physics_debug_destroy(_ed) {
  if (_ed == undefined || _ed.physics_debug_world == undefined) return;
  _ed.physics_debug_world.destroy();
  _ed.physics_debug_world = undefined;
}

function __poly_physics_debug_rebuild(_ed) {
  if (_ed == undefined || _ed.show_colliders != true || _ed.rt == undefined || _ed.rt.scene == undefined) return;
  __poly_physics_debug_destroy(_ed);
  _ed.rt.scene.update(0.0);
  _ed.world = __poly_world_data(_ed.world);
  _ed.physics_debug_world = new GM3D_PhysicsWorld(_ed.rt.scene, _ed.world);
  _ed.physics_debug_world.setGravity(new GM3D_Vec3(_ed.world.gravity[0], _ed.world.gravity[1], _ed.world.gravity[2]));
  _ed.view_dirty = true;
  _ed.physics_debug_world.setDebugDrawEnabled(true);
  _ed.physics_debug_world.syncScene();
  var _all = __poly_root_tracked(_ed);
  for (var _i = 0; _i < array_length(_all); _i++) {
    var _entry = __poly_registry_find(_ed, _all[_i]);
    if (_entry != undefined && is_struct(_entry.data) && is_struct(_entry.data[$ "physics"]) && _entry.data.physics.mode == "character") _ed.physics_debug_world.addCharacter(_all[_i]);
  }
}

function __poly_world_data(_source) {
  var _out = __poly_world_defaults();
  if (!is_struct(_source)) return _out;
  if (variable_struct_exists(_source, "gravity") && is_array(_source[$ "gravity"]) && array_length(_source.gravity) == 3) _out.gravity = __poly_physics_copy3(_source.gravity);
  for (var _i = 0; _i < 3; _i++) if (!is_real(_out.gravity[_i])) _out.gravity[_i] = 0.0;
  if (variable_struct_exists(_source, "fixedTimeStep") && is_real(_source.fixedTimeStep)) _out.fixedTimeStep = clamp(_source.fixedTimeStep, 0.001, 1.0);
  if (variable_struct_exists(_source, "maxSubSteps") && is_real(_source.maxSubSteps)) _out.maxSubSteps = clamp(round(_source.maxSubSteps), 1, 64);
  if (variable_struct_exists(_source, "maxBodies") && is_real(_source.maxBodies)) _out.maxBodies = clamp(round(_source.maxBodies), 1, 65535);
  return _out;
}

function __poly_physics_prefab_meta_sync(_ed) {
  if (_ed == undefined || !is_array(_ed.assets) || !is_struct(_ed.asset_meta)) return;
  for (var _i = 0; _i < array_length(_ed.assets); _i++) {
    var _entry = _ed.assets[_i];
    if (!is_struct(_entry) || !is_string(_entry.key)) continue;
    var _meta = _ed.asset_meta[$ _entry.key];
    if (is_struct(_meta) && is_struct(_meta[$ "physics"])) _entry.physics_default = __poly_physics_data(_meta.physics);
    else if (variable_struct_exists(_entry, "physics_default")) variable_struct_remove(_entry, "physics_default");
  }
}
