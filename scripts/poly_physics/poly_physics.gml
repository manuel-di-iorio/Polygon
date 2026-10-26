// poly_physics — editor physics data, GM3D components and static debug view.

function __poly_physics_defaults() {
  return {
    mode: "none",
    shape: "Box",
    shapes: undefined,
    constraint: undefined,
    vehicle: undefined,
    layer: "Default",
    mass: 1.0,
    linearDamping: 0.05,
    angularDamping: 0.05,
    gravityFactor: 1.0,
    isSensor: false,
    triggerEnter: true,
    triggerStay: false,
    triggerExit: true,
    friction: 0.8,
    restitution: 0.0,
    halfExtents: [0.5, 0.5, 0.5],
    offset: [0.0, 0.0, 0.0],
    character: {
      radius: 0.33,
      halfHeight: 0.92,
      stepHeight: 0.3,
      maxSlopeAngle: 55.0,
      stickToGround: true,
      mass: 80.0,
      maxStrength: 160.0,
      visualOffset: [0.0, -0.92, 0.0],
    },
  };
}

function __poly_world_defaults() {
  var _lc = [];
  for (var _i = 0; _i < 5; _i++) { var _r = []; for (var _j = 0; _j < 5; _j++) array_push(_r, true); array_push(_lc, _r); }
  return { gravity: [0.0, -9.81, 0.0], fixedTimeStep: 1.0 / 60.0, maxSubSteps: 4, maxBodies: 512, layerCollision: _lc, enabled: false };
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
  var _keys = ["mode", "shape", "layer", "mass", "linearDamping", "angularDamping", "gravityFactor", "isSensor", "triggerEnter", "triggerStay", "triggerExit", "friction", "restitution"];
  for (var _i = 0; _i < array_length(_keys); _i++) {
    var _k = _keys[_i];
    if (variable_struct_exists(_source, _k)) _out[$ _k] = _source[$ _k];
  }
  if (variable_struct_exists(_source, "halfExtents") && is_array(_source.halfExtents) && array_length(_source.halfExtents) == 3) _out.halfExtents = __poly_physics_copy3(_source.halfExtents);
  if (variable_struct_exists(_source, "offset") && is_array(_source.offset) && array_length(_source.offset) == 3) _out.offset = __poly_physics_copy3(_source.offset);
  if (variable_struct_exists(_source, "shapes") && is_array(_source.shapes)) {
    var _shapes_out = [];
    for (var _s = 0; _s < array_length(_source.shapes); _s++) {
      var _sh = _source.shapes[_s];
      if (!is_struct(_sh)) continue;
      var _shd = { type: "Box", halfExtents: [0.5, 0.5, 0.5], offset: [0.0, 0.0, 0.0], rotation: [0.0, 0.0, 0.0] };
      if (is_string(_sh[$ "type"])) _shd.type = _sh.type;
      if (is_array(_sh[$ "halfExtents"]) && array_length(_sh.halfExtents) == 3) _shd.halfExtents = __poly_physics_copy3(_sh.halfExtents);
      if (is_array(_sh[$ "offset"]) && array_length(_sh.offset) == 3) _shd.offset = __poly_physics_copy3(_sh.offset);
      if (is_array(_sh[$ "rotation"]) && array_length(_sh.rotation) == 3) _shd.rotation = __poly_physics_copy3(_sh.rotation);
      array_push(_shapes_out, _shd);
    }
    _out.shapes = _shapes_out;
  }
  if (variable_struct_exists(_source, "constraint") && is_struct(_source.constraint)) {
    var _c = _source.constraint;
    var _cd = { type: "Point", nodeB: "", pivotA: [0.0, 0.0, 0.0], pivotB: [0.0, 0.0, 0.0], axisA: [0.0, 1.0, 0.0], minLimit: 0.0, maxLimit: 0.0, motorEnabled: false, motorVelocity: 0.0, motorMaxForce: 0.0 };
    if (is_string(_c[$ "type"])) _cd.type = _c.type;
    if (is_string(_c[$ "nodeB"])) _cd.nodeB = _c.nodeB;
    if (is_array(_c[$ "pivotA"]) && array_length(_c.pivotA) == 3) _cd.pivotA = __poly_physics_copy3(_c.pivotA);
    if (is_array(_c[$ "pivotB"]) && array_length(_c.pivotB) == 3) _cd.pivotB = __poly_physics_copy3(_c.pivotB);
    if (is_array(_c[$ "axisA"]) && array_length(_c.axisA) == 3) _cd.axisA = __poly_physics_copy3(_c.axisA);
    if (is_real(_c[$ "minLimit"])) _cd.minLimit = _c.minLimit;
    if (is_real(_c[$ "maxLimit"])) _cd.maxLimit = _c.maxLimit;
    if (is_bool(_c[$ "motorEnabled"])) _cd.motorEnabled = _c.motorEnabled;
    if (is_real(_c[$ "motorVelocity"])) _cd.motorVelocity = _c.motorVelocity;
    if (is_real(_c[$ "motorMaxForce"])) _cd.motorMaxForce = _c.motorMaxForce;
    // Validate type.
    if (_cd.type != "Fixed" && _cd.type != "Point" && _cd.type != "Hinge" && _cd.type != "Slider" && _cd.type != "Cone" && _cd.type != "Distance") _cd.type = "Point";
    _out.constraint = _cd;
  }
  // Vehicle (optional configuration for dynamic bodies).
  if (variable_struct_exists(_source, "vehicle") && is_struct(_source[$ "vehicle"])) {
    var _v = _source.vehicle;
    var _vd = { enabled: true, mass: 1325.0, linearDamping: 0.08, angularDamping: 1.05, friction: 0.22, wheelRadius: 0.33, wheelWidth: 0.24, wheelCount: 4, maxSteerAngle: 0.5, maxTorque: 500.0, minRPM: 900.0, maxRPM: 6000.0, shiftUpRPM: 5200.0, shiftDownRPM: 2200.0, finalDriveRatio: 3.4, gearCount: 6, reverseGearRatio: -3.2, clutchStrength: 8.0, automatic: true, antiRollStiffness: 12000.0 };
    if (is_bool(_v[$ "enabled"])) _vd.enabled = _v.enabled;
    if (is_real(_v[$ "mass"])) _vd.mass = max(0.001, _v.mass);
    if (is_real(_v[$ "linearDamping"])) _vd.linearDamping = max(0.0, _v.linearDamping);
    if (is_real(_v[$ "angularDamping"])) _vd.angularDamping = max(0.0, _v.angularDamping);
    if (is_real(_v[$ "friction"])) _vd.friction = clamp(_v.friction, 0.0, 1.0);
    if (is_real(_v[$ "wheelRadius"])) _vd.wheelRadius = max(0.001, _v.wheelRadius);
    if (is_real(_v[$ "wheelWidth"])) _vd.wheelWidth = max(0.001, _v.wheelWidth);
    if (is_real(_v[$ "wheelCount"])) _vd.wheelCount = clamp(round(_v.wheelCount), 2, 16);
    if (is_real(_v[$ "maxSteerAngle"])) _vd.maxSteerAngle = clamp(_v.maxSteerAngle, 0.0, 3.14);
    if (is_real(_v[$ "maxTorque"])) _vd.maxTorque = max(0.0, _v.maxTorque);
    if (is_real(_v[$ "minRPM"])) _vd.minRPM = max(0.0, _v.minRPM);
    if (is_real(_v[$ "maxRPM"])) _vd.maxRPM = max(1.0, _v.maxRPM);
    if (is_real(_v[$ "shiftUpRPM"])) _vd.shiftUpRPM = max(0.0, _v.shiftUpRPM);
    if (is_real(_v[$ "shiftDownRPM"])) _vd.shiftDownRPM = max(0.0, _v.shiftDownRPM);
    if (is_real(_v[$ "finalDriveRatio"])) _vd.finalDriveRatio = _v.finalDriveRatio;
    if (is_real(_v[$ "gearCount"])) _vd.gearCount = clamp(round(_v.gearCount), 1, 12);
    if (is_real(_v[$ "reverseGearRatio"])) _vd.reverseGearRatio = _v.reverseGearRatio;
    if (is_real(_v[$ "clutchStrength"])) _vd.clutchStrength = max(0.0, _v.clutchStrength);
    if (is_bool(_v[$ "automatic"])) _vd.automatic = _v.automatic;
    if (is_real(_v[$ "antiRollStiffness"])) _vd.antiRollStiffness = max(0.0, _v.antiRollStiffness);
    _out.vehicle = _vd;
  }
  if (variable_struct_exists(_source, "character") && is_struct(_source[$ "character"])) {
    var _ck = ["radius", "halfHeight", "stepHeight", "maxSlopeAngle", "mass", "maxStrength"];
    for (var _c = 0; _c < array_length(_ck); _c++) if (variable_struct_exists(_source.character, _ck[_c])) _out.character[$ _ck[_c]] = _source.character[$ _ck[_c]];
    if (is_array(_source.character[$ "visualOffset"]) && array_length(_source.character.visualOffset) == 3) _out.character.visualOffset = __poly_physics_copy3(_source.character.visualOffset);
  if (variable_struct_exists(_source.character, "stickToGround")) _out.character.stickToGround = (_source.character.stickToGround == true);
  }
  if (!__poly_physics_mode_valid(_out.mode)) _out.mode = "none";
  if (_out.shape != "Box" && _out.shape != "Sphere" && _out.shape != "Capsule" && _out.shape != "Cylinder" && _out.shape != "Mesh" && _out.shape != "ConvexHull") { _out.shape = "Box"; _out.mode = "none"; }
  // Mesh shape is only supported on static bodies in GM3D.
  if (_out.shape == "Mesh" && _out.mode != "none" && _out.mode != "static") _out.mode = "static";
  if (!is_string(_out.layer) || (_out.layer != "Static" && _out.layer != "Default" && _out.layer != "Character" && _out.layer != "Trigger" && _out.layer != "Debris")) _out.layer = "Default";
  _out.mass = max(0.001, is_real(_out.mass) ? _out.mass : 1.0);
  _out.linearDamping = max(0.0, is_real(_out.linearDamping) ? _out.linearDamping : 0.05);
  _out.angularDamping = max(0.0, is_real(_out.angularDamping) ? _out.angularDamping : 0.05);
  _out.gravityFactor = is_real(_out.gravityFactor) ? _out.gravityFactor : 1.0;
  _out.isSensor = _out.isSensor == true;
  _out.triggerEnter = _out.triggerEnter == true;
  _out.triggerStay = _out.triggerStay == true;
  _out.triggerExit = _out.triggerExit == true;
  _out.friction = clamp(is_real(_out.friction) ? _out.friction : 0.8, 0.0, 1.0);
  _out.restitution = clamp(is_real(_out.restitution) ? _out.restitution : 0.0, 0.0, 1.0);
  for (var _a = 0; _a < 3; _a++) {
    _out.halfExtents[_a] = max(0.001, is_real(_out.halfExtents[_a]) ? abs(_out.halfExtents[_a]) : 0.5);
    _out.offset[_a] = is_real(_out.offset[_a]) ? _out.offset[_a] : 0.0;
    if (!is_real(_out.character.visualOffset[_a])) _out.character.visualOffset[_a] = 0.0;
  }
  _out.character.radius = clamp(is_real(_out.character.radius) ? _out.character.radius : 0.33, 0.01, 1000.0);
  _out.character.halfHeight = clamp(is_real(_out.character.halfHeight) ? _out.character.halfHeight : 0.92, 0.01, 1000.0);
  _out.character.stepHeight = max(0.0, is_real(_out.character.stepHeight) ? _out.character.stepHeight : 0.3);
  _out.character.maxSlopeAngle = clamp(is_real(_out.character.maxSlopeAngle) ? _out.character.maxSlopeAngle : 55.0, 0.0, 89.0);
  _out.character.mass = max(0.001, is_real(_out.character.mass) ? _out.character.mass : 80.0);
  _out.character.maxStrength = max(0.001, is_real(_out.character.maxStrength) ? _out.character.maxStrength : 160.0);
  return _out;
}

// Normalizes physics data and auto-fits the character visual when the source
// did not carry an explicit visualOffset. Used by direct (non-spawn) apply
// paths such as the AI bridge, so a character added to an existing node still
// gets its model centered on the capsule.
function __poly_physics_data_auto(_ed, _node, _source) {
  var _raw_char = undefined;

  if (is_struct(_source) && is_struct(_source[$ "character"])) _raw_char = _source.character;
  var _has_visual = is_struct(_raw_char) && variable_struct_exists(_raw_char, "visualOffset");
  var _d = __poly_physics_data(_source);
  if (_d.mode != "character" || _has_visual) return _d;
  var _model = undefined;
  var _en = __poly_registry_find(_ed, _node);
  if (_en != undefined && is_string(_en.asset) && _en.asset != "") {
    var _entry = __poly_asset_get(_ed, _en.asset);
    if (_entry != undefined) _model = _entry.model;
  }
  return __poly_physics_fit_visual(_model, _d);
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
  var _constraint_find = _node[$ "findPhysicsConstraintComponent"];
  if (_constraint_find != undefined) { var _constraint_old = _node.findPhysicsConstraintComponent(); if (_constraint_old != undefined) _node.removeComponent(_constraint_old); }
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
  _body.setMotionType(_d.mode == "static" ? GM3D_EPhysicsMotionType.Static : (_d.mode == "kinematic" ? GM3D_EPhysicsMotionType.Kinematic : GM3D_EPhysicsMotionType.Dynamic));
  _body.setMotionQuality(GM3D_EPhysicsMotionQuality.Discrete);
  _body.setLayer(_d.isSensor || _d.layer == "Trigger" ? GM3D_EPhysicsLayer.Trigger : (_d.layer == "Static" ? GM3D_EPhysicsLayer.Static : (_d.layer == "Character" ? GM3D_EPhysicsLayer.Character : (_d.layer == "Debris" ? GM3D_EPhysicsLayer.Debris : GM3D_EPhysicsLayer.Default))));
  _body.setMass(_d.mass);
  _body.setLinearDamping(_d.linearDamping);
  _body.setAngularDamping(_d.angularDamping);
  _body.setGravityFactor(_d.gravityFactor);
  _body.setIsSensor(_d.isSensor);
  _body.setStartAwake(true);
  _body.setAllowSleeping(true);
  _node.addComponent(_body);
  var _shape = new GM3D_PhysicsShapeComponent();
  var _stype = _d.shape == "Sphere" ? GM3D_EPhysicsShapeType.Sphere : (_d.shape == "Capsule" ? GM3D_EPhysicsShapeType.Capsule : (_d.shape == "Cylinder" ? GM3D_EPhysicsShapeType.Cylinder : (_d.shape == "Mesh" ? GM3D_EPhysicsShapeType.Mesh : (_d.shape == "ConvexHull" ? GM3D_EPhysicsShapeType.ConvexHull : GM3D_EPhysicsShapeType.Box))));
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
    var _cma = _cc[$ "getMass"];
    var _cst = _cc[$ "getMaxStrength"];
    if (_cma != undefined) _out.character.mass = method(_cc, _cma)();
    if (_cst != undefined) _out.character.maxStrength = method(_cc, _cst)();
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
    _out.mode = _motion == GM3D_EPhysicsMotionType.Static ? "static" : (_motion == GM3D_EPhysicsMotionType.Kinematic ? "kinematic" : "dynamic");
  } else _out.mode = "static";
  var _shape_fn2 = _shape[$ "getShapeType"];
  if (_shape_fn2 != undefined) {
    var _st = method(_shape, _shape_fn2)();
    _out.shape = _st == GM3D_EPhysicsShapeType.Sphere ? "Sphere" : (_st == GM3D_EPhysicsShapeType.Capsule ? "Capsule" : (_st == GM3D_EPhysicsShapeType.Cylinder ? "Cylinder" : (_st == GM3D_EPhysicsShapeType.Mesh ? "Mesh" : (_st == GM3D_EPhysicsShapeType.ConvexHull ? "ConvexHull" : "Box"))));
  }
  var _read_body = [["mass", "getMass"], ["linearDamping", "getLinearDamping"], ["angularDamping", "getAngularDamping"], ["gravityFactor", "getGravityFactor"], ["isSensor", "getIsSensor"]];
  for (var _i = 0; _i < array_length(_read_body); _i++) {
    var _fn = _body[$ _read_body[_i][1]];
    if (_fn != undefined) _out[$ _read_body[_i][0]] = method(_body, _fn)();
  }
  var _layer_fn = _body[$ "getLayer"];
  if (_layer_fn != undefined) {
    var _layer = method(_body, _layer_fn)();
    _out.layer = _layer == GM3D_EPhysicsLayer.Static ? "Static" : (_layer == GM3D_EPhysicsLayer.Character ? "Character" : (_layer == GM3D_EPhysicsLayer.Trigger ? "Trigger" : (_layer == GM3D_EPhysicsLayer.Debris ? "Debris" : "Default")));
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
  var _layers = ["Static", "Default", "Character", "Trigger", "Debris"];
  var _lvals = [1, 2, 4, 8, 16];
  if (is_array(_ed.world.layerCollision)) {
    for (var _i = 0; _i < 5; _i++) for (var _j = 0; _j < 5; _j++) {
      var _setlc = _ed.physics_debug_world[$ "setLayerCollision"];
      if (_setlc != undefined) method(_ed.physics_debug_world, _setlc)(_lvals[_i], _lvals[_j], _ed.world.layerCollision[_i][_j] == true);
    }
  }
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
  if (variable_struct_exists(_source, "enabled")) _out.enabled = _source.enabled == true;
  // layerCollision: 5x5 bool matrix (default all true).
  var _lc = [];
  for (var _i = 0; _i < 5; _i++) {
    var _row = [];
    for (var _j = 0; _j < 5; _j++) {
      var _val = true;
      if (is_array(_source[$ "layerCollision"]) && array_length(_source.layerCollision) == 5 && is_array(_source.layerCollision[_i]) && array_length(_source.layerCollision[_i]) == 5) _val = _source.layerCollision[_i][_j] == true;
      array_push(_row, _val);
    }
    array_push(_lc, _row);
  }
  _out.layerCollision = _lc;
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
