// scr_demo — demo game world (instance state lives on oGame).
//
// State (demo_* instance vars, set up by demo_create):
//   demo_scene, demo_renderer, demo_models, demo_cache,
//   demo_cam, demo_cam_comp, demo_cam_pos, demo_cam_yaw, demo_cam_pitch.

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

// Creates demo scene with environment, sun, camera and props.
function demo_create() {
  demo_scene = GM3D_Scene.createEmpty();
  demo_renderer = new GM3D_Renderer();
  demo_models = [];
  demo_cache = {};

  demo_cam = undefined;
  demo_cam_comp = undefined;
  demo_sun_node = undefined;
  demo_skybox_node = undefined;
  demo_skybox_material = undefined;
  demo_cam_pos = new GM3D_Vec3(-1.3, 1.0, -4.1);
  demo_cam_yaw = 180.0;
  demo_cam_pitch = 14.0;
  demo_cam_follow_distance = 4.1;
  demo_cam_follow_speed = 14.0;
  demo_physics = new GM3D_PhysicsWorld(demo_scene, {
    maxBodies: 64,
    fixedTimeStep: 1 / 60,
    maxSubSteps: 4,
  });
  demo_physics.setGravity(new GM3D_Vec3(0.0, -22.0, 0.0));
  demo_player = undefined;
  demo_player_controller = undefined;
  demo_player_vertical_speed = 0.0;
  // Face the trees at the north side of the platform from the initial spawn.
  demo_player_facing = 0.0;
  demo_player_turn_speed = 180.0;
  demo_player_turn_velocity = 0.0;
  demo_player_turn_response = 9.0;
  // Camera heading follows the character; there is no mouse camera orbit.
  demo_player_anim = undefined;
  demo_player_anim_idle = 0;
  demo_player_anim_walk = 0;
  demo_player_anim_run = 0;
  demo_player_anim_jump = 0;
  demo_player_anim_fall = 0;
  demo_player_anim_current = -1;
  demo_walk_speed = 4.0;
  demo_run_speed = 6.0;
  demo_jump_speed = 9.2;
  demo_jump_gravity = 30.0;
  demo_cam_shoulder_offset = 0.75;

  demo_build_environment();
  demo_build_sun();
  demo_build_camera();
  demo_build_skybox();
  demo_build_props();

  demo_scene.update(0);
  demo_physics.syncScene();
  demo_build_player();
}

// Destroys demo scene and loaded models.
function demo_destroy() {
  window_mouse_set_locked(false);
  if (!is_undefined(demo_physics)) demo_physics.destroy();
  demo_physics = undefined;
  if (!is_undefined(demo_scene)) demo_scene.destroy();
  demo_scene = undefined;
  demo_cam = undefined;
  demo_cam_comp = undefined;
  demo_sun_node = undefined;
  demo_skybox_node = undefined;
  demo_skybox_material = undefined;

  for (var _i = 0, _n = array_length(demo_models); _i < _n; _i++) demo_models[_i].destroy();
  demo_models = [];
  demo_cache = {};
  demo_renderer = undefined;
}

// Updates demo scene animation.
function demo_step() {
  var _dt = min(delta_time * 0.000001, 1 / 20);
  var _ground = demo_physics.getCharacterGroundState(demo_player);
  // A wall/tree contact can report NotSupported; only a real ground contact
  // may reset vertical speed or allow another jump.
  var _grounded = (_ground == GM3D_ECharacterGroundState.OnGround);

  var _forward_input = keyboard_check(ord("W")) - keyboard_check(ord("S"));
  var _strafe_input = keyboard_check(ord("D")) - keyboard_check(ord("A"));
  var _jump_requested = keyboard_check_pressed(vk_space);
  // A/D turn the character with eased angular acceleration and braking;
  // W/S move along its local forward axis.
  var _target_turn_velocity = -_strafe_input * demo_player_turn_speed;
  var _turn_response = 1.0 - exp(-demo_player_turn_response * _dt);
  demo_player_turn_velocity += (_target_turn_velocity - demo_player_turn_velocity) * _turn_response;
  demo_player_facing += demo_player_turn_velocity * _dt;
  if (demo_player_facing >= 360.0) demo_player_facing -= 360.0;
  else if (demo_player_facing < 0.0) demo_player_facing += 360.0;
  demo_cam_yaw = demo_player_facing;
  var _player_forward_move = demo_player_heading(demo_player_facing);
  var _move = new GM3D_Vec3(
    _player_forward_move.x * _forward_input,
    0.0,
    _player_forward_move.z * _forward_input
  );
  if (_move.lengthSq() > 1.0) _move.normalize();
  var _sprinting = keyboard_check(vk_shift)
    && _move.lengthSq() > 0.000001;
  if (demo_player_visual != undefined) demo_player_visual.setLocalRotation(demo_yaw_quat(demo_player_facing + 180.0));

  if (_grounded && demo_player_vertical_speed < 0.0) demo_player_vertical_speed = 0.0;
  if (_grounded && _jump_requested) demo_player_vertical_speed = demo_jump_speed;
  if (!_grounded) demo_player_vertical_speed -= demo_jump_gravity * _dt;

  demo_physics.setCharacterVelocity(demo_player, new GM3D_Vec3(
    _move.x * (_sprinting ? demo_run_speed : demo_walk_speed),
    demo_player_vertical_speed,
    _move.z * (_sprinting ? demo_run_speed : demo_walk_speed)
  ));

  demo_scene.update(_dt);
  demo_physics.step(_dt);
  demo_physics.interpolateForRender();

  var _player_pos = demo_player.getWorldPosition();

  if (demo_player_anim != undefined) {
    var _moving = _move.lengthSq() > 0.000001;
    var _anim_target = demo_player_anim_idle;
    if (!_grounded) {
      _anim_target = (demo_player_vertical_speed > 0.0) ? demo_player_anim_jump : demo_player_anim_fall;
    } else if (_moving) {
      _anim_target = _sprinting ? demo_player_anim_run : demo_player_anim_walk;
    }
    if (_anim_target != demo_player_anim_current) {
      demo_player_anim.setTime(0.0);
      demo_player_anim.play(_anim_target, true);
      demo_player_anim_current = _anim_target;
    }
    demo_player_anim.setSpeed((_anim_target == demo_player_anim_walk) ? 1.25 : 1.0);
  }

  if (demo_player_visual != undefined) {
    demo_player_visual.setLocalPosition(new GM3D_Vec3(
      _player_pos.x,
      _player_pos.y + demo_player_visual_offset_y,
      _player_pos.z
    ));
  }

  // TDS chase camera orbits independently while tracking the player position.
  var _pitch_rad = degtorad(demo_cam_pitch);
  var _camera_forward = demo_player_heading(demo_cam_yaw);
  var _target_pos = demo_camera_target_position(_player_pos);
  var _blend = clamp(_dt * demo_cam_follow_speed, 0.0, 1.0);
  demo_cam_pos.lerp(_target_pos, _blend);
  demo_cam.setLocalPosition(demo_cam_pos);
  // The player turn is already smoothed by A/D, so apply this matching camera
  // quaternion directly instead of adding a second yaw interpolation.
  var _camera_back = new GM3D_Vec3(
    -_camera_forward.x * cos(_pitch_rad),
    sin(_pitch_rad),
    -_camera_forward.z * cos(_pitch_rad)
  );
  demo_cam.setLocalRotation(GM3D_Quaternion.fromLookRotation(_camera_back, GM3D_Vec3.up()));
  demo_sync_skybox();
}

// Renders demo scene.
function demo_draw() {
  demo_renderer.render(demo_scene);
  demo_physics.restoreSimulationPositions();
}

// ---------------------------------------------------------------------------
// World building
// ---------------------------------------------------------------------------

// Creates the ambient environment volume.
function demo_build_environment() {
  var _node = demo_scene.createNode("Environment");
  var _comp = new GM3D_EnvironmentVolumeComponent();
  _node.addComponent(_comp);
  _comp.setSize(new GM3D_Vec3(20000.0, 20000.0, 20000.0));
  _comp.setAmbientColor(make_colour_rgb(70, 70, 85));
}

// Creates the directional sun light.
function demo_build_sun() {
  var _node = demo_scene.createNode("Sun");
  demo_sun_node = _node;
  var _comp = new GM3D_LightComponent();
  _node.addComponent(_comp);
  _comp.setType(GM3D_ELightType.Directional);
  _comp.setColor(c_white);
  _comp.setIntensity(1.0);
  _comp.setShadowEnabled(true);
  _comp.setShadowResolution(2048);
  _comp.setShadowDistance(30.0);
  _comp.setShadowNormalOffset(0.05);
  _node.setLocalPosition(new GM3D_Vec3(0.3, 2.2, 1.3));
  demo_look_at(_node, new GM3D_Vec3(0.35, 0.8, 0.45));
}

// Creates a gameplay-owned sky dome with the editor sky palette and sun glow.
function demo_build_skybox() {
  var _res = demo_load_model("__PolygonEditor__/models/skybox.glb", "Demo Sky", shPolygonEditorSky);
  if (_res == undefined) return;
  var _materials = _res.model.getMaterials();
  if (array_length(_materials) > 0) demo_skybox_material = _materials[0];

  demo_skybox_node = demo_scene.createNode("DemoSkybox");
  var _model_root = _res.model.spawnInto(demo_scene, demo_skybox_node);
  if (_model_root == undefined) {
    demo_skybox_node.destroy();
    demo_skybox_node = undefined;
    return;
  }
  var _mesh = _model_root.getMeshComponent();
  if (_mesh != undefined) _mesh.setFlags(0);
  if (demo_skybox_material != undefined) {
    demo_skybox_material.setFloatArray("u_skyTop", [ 0.25, 0.5, 0.83 ]);
    demo_skybox_material.setFloatArray("u_skyHorizon", [ 0.84, 0.87, 0.91 ]);
    demo_skybox_material.setFloatArray("u_skyBottom", [ 0.412, 0.388, 0.365 ]);
    demo_skybox_material.setFloatArray("u_sunColor", [ 1.0, 1.0, 1.0 ]);
    demo_skybox_material.setFloat("u_sunGlow", 1.0);
  }
  demo_sync_skybox();
}

// Keeps the independent gameplay dome centered on the game camera and updates
// its sun disk from the demo's own directional light.
function demo_sync_skybox() {
  if (demo_skybox_node == undefined || demo_cam == undefined) return;
  var _cam_pos = demo_cam.getWorldPosition();
  demo_skybox_node.setLocalPosition(new GM3D_Vec3(_cam_pos.x, _cam_pos.y, _cam_pos.z));
  var _far = 10000.0;
  if (demo_cam_comp != undefined) {
    var _camera_far = demo_cam_comp.getFar();
    if (is_real(_camera_far) && _camera_far > 0.0) _far = _camera_far;
  }
  var _fit = clamp(_far * 0.5 / 4000.0, 0.001, 1.0);
  demo_skybox_node.setLocalScale(new GM3D_Vec3(_fit, _fit, _fit));

  if (demo_skybox_material != undefined && demo_sun_node != undefined) {
    var _sun_dir = demo_sun_node.getWorldForward();
    if (_sun_dir != undefined && _sun_dir.lengthSq() > 0.000001) {
      _sun_dir.normalize();
      demo_skybox_material.setFloatArray("u_sunDir", [ _sun_dir.x, _sun_dir.y, _sun_dir.z ]);
    }
  }
}

// Creates the main camera and frames the scene.
function demo_build_camera() {
  var _node = demo_scene.createNode("MainCamera");
  var _comp = new GM3D_CameraComponent();
  _node.addComponent(_comp);
  _comp.setFar(10000.0);
  _comp.setScreenRect([ 0.0, 0.0, 1.0, 1.0 ]);
  demo_cam = _node;
  demo_cam_comp = _comp;

  demo_place_camera();
}

// Spawns all demo props.
function demo_build_props() {
  var _terrain = demo_load_model("demo/terrain.glb");
  if (_terrain != undefined) {
    demo_terrain_visual = _terrain.model.spawnInto(demo_scene, undefined);
    if (demo_terrain_visual != undefined) {
      demo_terrain_visual.setLocalPosition(new GM3D_Vec3(0.0, -0.020, 0.0));
      demo_terrain_visual.setLocalScale(new GM3D_Vec3(1.0));
      demo_on_create(demo_terrain_visual, _terrain.path, _terrain.model);
    }
  }

  // The demo's walkable terrain is a simple static physics slab; no render mesh
  // or editor-side physics data is needed for a flat ground surface.
  var _ground_node = demo_scene.createNode("GameplayGround");
  _ground_node.setLocalPosition(new GM3D_Vec3(0.0, -0.2, 0.0));
  var _ground_body = new GM3D_PhysicsBodyComponent();
  _ground_body.setMotionType(GM3D_EPhysicsMotionType.Static);
  _ground_body.setLayer(GM3D_EPhysicsLayer.Static);
  var _ground_shape = new GM3D_PhysicsShapeComponent();
  _ground_shape.setShapeType(GM3D_EPhysicsShapeType.Cylinder);
  _ground_shape.setHalfExtents(new GM3D_Vec3(15.0, 0.2, 15.0));
  _ground_shape.setFriction(0.85);
  _ground_node.addComponent(_ground_body);
  _ground_node.addComponent(_ground_shape);

  var _props = [
    { path: "kenney_platformer-kit/platform.glb", pos: [ 0, -0.15, 0 ], scale: 2.4, collider: true },
    { path: "kenney_platformer-kit/tree.glb", pos: [ -3.2, 0, -3.6 ], scale: 1.2, collider: true, colliderKind: "wall" },
    { path: "kenney_platformer-kit/tree-pine.glb", pos: [ 3.4, 0, -3.2 ], scale: 1.1, collider: true, colliderKind: "wall" },
    { path: "kenney_platformer-kit/flowers.glb", pos: [ -1.6, 0, -1.8 ] },
    { path: "kenney_platformer-kit/grass.glb", pos: [ 1.8, 0, -1.6 ] },
    { path: "kenney_platformer-kit/rocks.glb", pos: [ 0, 0, -2.8 ], yaw: 20, scale: 2, collider: true, colliderKind: "mesh" },
    { path: "kenney_cube-pets_1.0/animal-fox.glb", pos: [ 0.95, 0.3, 0.55 ], yaw: -25, scale: 0.3, collider: true, colliderKind: "blocker" },
  ];

  for (var _i = 0, _n = array_length(_props); _i < _n; _i++) demo_spawn_prop(_props[_i]);
}

// ---------------------------------------------------------------------------
// Model loading
// ---------------------------------------------------------------------------

// Builds a display label from a load path ("tree-pine.glb" -> "Tree Pine").
function demo_pretty_label(_path) {
  var _base = is_string(_path) ? _path : "";
  var _slash = string_last_pos("/", _base);

  if (_slash > 0) _base = string_copy(_base, _slash + 1, string_length(_base) - _slash);
  var _dot = string_last_pos(".", _base);

  if (_dot > 0) _base = string_copy(_base, 1, _dot - 1);
  _base = string_replace_all(_base, "-", " ");
  _base = string_replace_all(_base, "_", " ");
  var _words = string_split(_base, " ");
  var _out = "";

  for (var _i = 0, _n = array_length(_words); _i < _n; _i++) {
    var _word = _words[_i];

    if (!is_string(_word) || _word == "") continue;
    var _cap = string_upper(string_copy(_word, 1, 1)) + string_copy(_word, 2, string_length(_word) - 1);
    _out += (_out == "" ? "" : " ") + _cap;
  }

  return _out == "" ? _path : _out;
}

// Loads cached GLTF model file, returning { model, label, path }.
function demo_load_model(_path, _label = undefined, _shader_override = undefined) {
  var _src = undefined;

  if (variable_struct_exists(demo_cache, _path)) _src = demo_cache[$ _path];

  if (_src == undefined) {
    _src = GM3D_Scene.loadGltf(working_directory + _path);

    if (_src == undefined) return undefined;
    demo_assign_shaders(_src);
    if (_shader_override != undefined) {
      var _materials = _src.getMaterials();
      for (var _i = 0, _nmat = array_length(_materials); _i < _nmat; _i++) _materials[_i].setShader(GM3D_ERenderPass.Forward, _shader_override);
    }
    _src.freeze();
    array_push(demo_models, _src);
    demo_cache[$ _path] = _src;
  }

  var _lab = (is_string(_label) && _label != "") ? _label : demo_pretty_label(_path);
  return { model: _src, label: _lab, path: _path };
}

// Loads every model path and returns the poly assets struct:
// { path: { model, label } }. Skips paths that fail to load.
function demo_load_models(_paths) {
  var _assets = {};

  if (!is_array(_paths)) return _assets;

  for (var _i = 0, _n = array_length(_paths); _i < _n; _i++) {
    var _r = demo_load_model(_paths[_i]);

    if (_r != undefined) _assets[$ _paths[_i]] = { model: _r.model, label: _r.label };
  }

  return _assets;
}

// ---------------------------------------------------------------------------
// Spawning
// ---------------------------------------------------------------------------

// Builds a vec3 from a [x, y, z] array, falling back to defaults.
function demo_vec3(_arr, _fallback) {
  if (!is_array(_arr) || array_length(_arr) < 3) return new GM3D_Vec3(_fallback[0], _fallback[1], _fallback[2]);
  return new GM3D_Vec3(_arr[0], _arr[1], _arr[2]);
}

// Builds a scale vec3 from a number (uniform), an array, or defaults to 1.
function demo_scale3(_prop) {
  if (variable_struct_exists(_prop, "scale")) {
    if (is_real(_prop.scale)) return new GM3D_Vec3(_prop.scale, _prop.scale, _prop.scale);
    if (is_array(_prop.scale) && array_length(_prop.scale) >= 3) return new GM3D_Vec3(_prop.scale[0], _prop.scale[1], _prop.scale[2]);
  }

  return new GM3D_Vec3(1, 1, 1);
}

// Spawns one prop descriptor ({ path, pos, yaw?, scale? }) into the scene.
function demo_spawn_prop(_prop) {
  var _res = demo_load_model(_prop.path);

  if (_res == undefined) return undefined;
  var _node = _res.model.spawnInto(demo_scene, undefined);

  if (_node == undefined) return undefined;
  _node.setLocalPosition(demo_vec3(_prop.pos, [ 0, 0, 0 ]));
  _node.setLocalScale(demo_scale3(_prop));

  if (variable_struct_exists(_prop, "yaw") && is_real(_prop.yaw)) _node.setLocalRotation(demo_yaw_quat(_prop.yaw));
  demo_on_create(_node, _res.path, _res.model);
  if (variable_struct_exists(_prop, "collider") && _prop.collider) {
    var _kind = variable_struct_exists(_prop, "colliderKind") ? _prop.colliderKind : "box";
    var _yaw = (variable_struct_exists(_prop, "yaw") && is_real(_prop.yaw)) ? _prop.yaw : 0.0;
    demo_add_model_collider(_node, _res.model, demo_vec3(_prop.pos, [ 0, 0, 0 ]), demo_scale3(_prop), _kind, _yaw);
  }
  return _node;
}

// Adds a static box from the source model bounds. This keeps gameplay collision
// independent of editor metadata and avoids expensive triangle meshes.
function demo_add_model_collider(_visual, _src, _position, _scale, _kind = "box", _yaw = 0.0) {
  var _bounds = _src.getBoundingBox();
  if (_bounds == undefined) return undefined;
  var _min = _bounds.min;
  var _max = _bounds.max;
  var _center = new GM3D_Vec3(
    (_min.x + _max.x) * 0.5 * _scale.x,
    (_min.y + _max.y) * 0.5 * _scale.y,
    (_min.z + _max.z) * 0.5 * _scale.z
  );
  var _half = new GM3D_Vec3(
    max(abs(_max.x - _min.x) * 0.5 * _scale.x, 0.08),
    max(abs(_max.y - _min.y) * 0.5 * _scale.y, 0.08),
    max(abs(_max.z - _min.z) * 0.5 * _scale.z, 0.08)
  );
  var _body_node = demo_scene.createNode("Collider_" + string(_visual.name));
  if (_kind == "wall") {
    // Tall invisible boxes use the model footprint but rise well above the
    // maximum jump, so trees and rocks cannot become platforms.
    var _wall_half_height = max(_half.y, 4.0);
    var _wall_bottom = _position.y + _min.y * _scale.y;
    _body_node.setLocalPosition(new GM3D_Vec3(
      _position.x + _center.x,
      _wall_bottom + _wall_half_height,
      _position.z + _center.z
    ));
    _half.y = _wall_half_height;
  } else if (_kind == "blocker") {
    // The fox should block the player without becoming a jumpable perch.
    // Keep the box grounded, widen its footprint slightly, and extend it above
    // the maximum character jump.
    var _blocker_half_height = max(_half.y, 1.5);
    var _blocker_bottom = _position.y + _min.y * _scale.y;
    _body_node.setLocalPosition(new GM3D_Vec3(
      _position.x + _center.x,
      _blocker_bottom + _blocker_half_height,
      _position.z + _center.z
    ));
    _half.x = max(_half.x, 0.25);
    _half.y = _blocker_half_height;
    _half.z = max(_half.z, 0.25);
  } else if (_kind == "mesh") {
    // Use the model's own mesh as the collider (static bodies only).
    _body_node = _visual;
  } else {
    _body_node.setLocalPosition(new GM3D_Vec3(_position.x + _center.x, _position.y + _center.y, _position.z + _center.z));
  }
  var _body = new GM3D_PhysicsBodyComponent();
  _body.setMotionType(GM3D_EPhysicsMotionType.Static);
  _body.setLayer(GM3D_EPhysicsLayer.Static);
  var _shape = new GM3D_PhysicsShapeComponent();
  if (_kind == "mesh") {
    _shape.setShapeType(GM3D_EPhysicsShapeType.Mesh);
  } else {
    _shape.setShapeType(GM3D_EPhysicsShapeType.Box);
    _shape.setHalfExtents(_half);
    if (_yaw != 0.0) _shape.setLocalRotation(demo_yaw_quat(_yaw));
  }
  _shape.setFriction(0.8);
  _body_node.addComponent(_body);
  _body_node.addComponent(_shape);
  return _body_node;
}

function demo_build_player() {
  // Spawn above the platform with enough clearance to avoid an initial
  // character/platform overlap while staying close to the surface.
  var _support_top = 0.0;
  var _platform = demo_load_model("kenney_platformer-kit/platform.glb");
  if (_platform != undefined) {
    var _bounds = _platform.model.getBoundingBox();
    if (_bounds != undefined) _support_top = max(_support_top, -0.15 + _bounds.max.y * 2.4);
  }
  var _spawn_y = _support_top + 0.3 + 0.55 + 0.35;
  // Keep the capsule fully inside the platform footprint at startup.
  var _spawn = new GM3D_Vec3(-0.55, _spawn_y, 0.0);
  demo_player = demo_scene.createNode("PlayerController");
  demo_player.setLocalPosition(_spawn);
  demo_player_controller = new GM3D_CharacterControllerComponent();
  demo_player_controller.setRadius(0.3);
  demo_player_controller.setHalfHeight(0.55);
  demo_player_controller.setStepHeight(0.35);
  demo_player_controller.setMaxSlopeAngle(degtorad(55.0));
  demo_player_controller.setLayer(GM3D_EPhysicsLayer.Character);
  demo_player_controller.setMass(70.0);
  demo_player_controller.setMaxStrength(140.0);
  demo_player_controller.setPredictiveContactDistance(0.12);
  demo_player.addComponent(demo_player_controller);
  demo_physics.addCharacter(demo_player);
  demo_physics.setCharacterVelocity(demo_player, new GM3D_Vec3());
  demo_physics.setCharacterStickToGroundEnabled(demo_player, false);

  var _character = demo_load_model("kenney_mini-characters/character-female-b.glb");
  demo_player_visual = undefined;
  demo_player_visual_offset_y = -(0.3 + 0.55);
  demo_player_anim = undefined;
  if (_character != undefined) {
    // Keep the gameplay pivot at the controller origin and offset the model
    // locally so turning cannot swing an off-centre asset around in an orbit.
    // The editor's live-scene importer matches prefab roots by model root name,
    // so name this pivot after the source root instead of a custom label.
    var _visual_root_name = "PlayerVisualPivot";
    var _source_nodes = _character.model.getNodes();
    if (is_array(_source_nodes)) {
      for (var _i = 0, _n = array_length(_source_nodes); _i < _n; _i++) {
        if (_source_nodes[_i] == undefined || _source_nodes[_i].parent != undefined) continue;
        if (is_string(_source_nodes[_i].name) && _source_nodes[_i].name != "") _visual_root_name = _source_nodes[_i].name;
        break;
      }
    }
    demo_player_visual = demo_scene.createNode(_visual_root_name);
    var _model_root = _character.model.spawnInto(demo_scene, demo_player_visual);
    if (_model_root != undefined) {
      var _character_bounds = _character.model.getBoundingBox();
      var _model_center_x = 0.0;
      var _model_center_z = 0.0;
      if (_character_bounds != undefined) {
        demo_player_visual_offset_y -= _character_bounds.min.y;
        _model_center_x = (_character_bounds.min.x + _character_bounds.max.x) * 0.5;
        _model_center_z = (_character_bounds.min.z + _character_bounds.max.z) * 0.5;
      }
      demo_player_visual.setLocalPosition(new GM3D_Vec3(_spawn.x, 0.250, _spawn.z));
      demo_player_visual.setLocalScale(new GM3D_Vec3(1.0));
      _model_root.setLocalPosition(new GM3D_Vec3(-_model_center_x, 0.0, -_model_center_z));
      demo_on_create(demo_player_visual, _character.path, _character.model);
      demo_player_anim = demo_find_anim(demo_player_visual);
      if (demo_player_anim != undefined && _character.model.animationCount > 0) {
        demo_player_anim_idle = demo_find_anim_index(_character.model, "idle");
        demo_player_anim_walk = demo_find_anim_index(_character.model, "walk");
        demo_player_anim_run = demo_find_anim_index(_character.model, "sprint");
        demo_player_anim_jump = demo_find_anim_index(_character.model, "jump");
        demo_player_anim_fall = demo_find_anim_index(_character.model, "fall");
        demo_player_anim_current = demo_player_anim_idle;
      }
      demo_player_visual.setLocalRotation(demo_yaw_quat(demo_player_facing + 180.0));
    }
  }

  // Start at the same follow target used by demo_step, avoiding a camera sweep
  // from the old spawn-side position across the player.
  demo_cam_pos = demo_camera_target_position(_spawn, 0.0);
  demo_cam.setLocalPosition(demo_cam_pos);
}

// Editor create hook: assigns shaders and starts the idle animation.
// Signature is fixed by the editor (wrapper node, model id, model):
// walk the subtree, the model root lives inside the wrapper.
function demo_on_create(_node, _asset_id, _src) {
  if (_node == undefined || _src == undefined) return;
  demo_assign_instance_shaders(_node);

  if (_src.animationCount > 0) {
    var _anim = demo_find_anim(_node);

    if (_anim != undefined) {
      var _idx = demo_find_anim_index(_src, "idle");
      _anim.setEnabled(true);
      _anim.setTime(0.0);
      _anim.setSpeed(1.0);
      _anim.play(_idx, true);
    }
  }
}

// ---------------------------------------------------------------------------
// Shaders
// ---------------------------------------------------------------------------

// Assigns forward+shadow shaders to one material unless already set.
function demo_shade_material(_mat, _skinned) {
  var _forward = _skinned ? sAnimated : sStatic;
  var _shadow = _skinned ? sAnimatedShadow : sStaticShadow;

  if (_mat.getShader(GM3D_ERenderPass.Forward) == undefined) _mat.setShader(GM3D_ERenderPass.Forward, _forward);
  if (_mat.getShader(GM3D_ERenderPass.Shadow) == undefined) _mat.setShader(GM3D_ERenderPass.Shadow, _shadow);
}

// Assigns shaders to one mesh component (shared by source and live nodes).
function demo_shade_comp(_comp, _skinned) {
  if (_comp == undefined) return;
  var _mat = _comp.getMaterial();

  if (_mat != undefined) demo_shade_material(_mat, _skinned);
}

// Assigns static and skinned shaders to a freshly loaded source scene.
function demo_assign_shaders(_src) {
  var _materials = _src.getMaterials();

  for (var _i = 0, _nmat = array_length(_materials); _i < _nmat; _i++) demo_shade_material(_materials[_i], false);
  var _nodes = _src.getNodes();

  for (var _j = 0, _nnod = array_length(_nodes); _j < _nnod; _j++) demo_shade_comp(_nodes[_j].getSkinnedMeshComponent(), true);
}

// Assigns lighting shaders across a live node subtree.
function demo_assign_instance_shaders(_node) {
  var _stack = [ _node ];

  while (array_length(_stack) > 0) {
    var _cur = array_pop(_stack);

    if (_cur == undefined) continue;
    demo_shade_comp(_cur.getMeshComponent(), false);
    demo_shade_comp(_cur.getSkinnedMeshComponent(), true);

    var _kids = _cur.getChildren();

    for (var _k = 0, _nkid = array_length(_kids); _k < _nkid; _k++) array_push(_stack, _kids[_k]);
  }
}

// ---------------------------------------------------------------------------
// Animation
// ---------------------------------------------------------------------------

// Finds the first animation component in a subtree.
function demo_find_anim(_node) {
  if (_node == undefined) return undefined;
  var _found = _node.findAnimationComponent();

  if (_found != undefined) return _found;
  var _comp = _node.getAnimationComponent();

  if (_comp != undefined) return _comp;
  var _children = _node.getChildren();

  for (var _i = 0, _nchild = array_length(_children); _i < _nchild; _i++) {
    var _nested = demo_find_anim(_children[_i]);

    if (_nested != undefined) return _nested;
  }

  return undefined;
}

// Finds an animation index by name (exact, then substring, else first).
function demo_find_anim_index(_src, _name) {
  var _count = _src.animationCount;
  var _target = string_lower(string(_name));
  var _fallback = -1;

  for (var _i = 0; _i < _count; _i++) {
    var _anim = _src.getAnimation(_i);
    var _anim_name = string_lower(string(_anim.path));

    if (_anim_name == _target) return _i;
    if (_fallback < 0 && string_pos(_target, _anim_name) > 0) _fallback = _i;
  }

  if (_fallback >= 0) return _fallback;
  return 0;
}

// ---------------------------------------------------------------------------
// Camera math
// ---------------------------------------------------------------------------

// Builds a yaw-only quaternion from degrees.
function demo_yaw_quat(_deg) {
  var _half = degtorad(_deg) * 0.5;
  var _quat = new GM3D_Quaternion();
  _quat.x = 0;
  _quat.y = sin(_half);
  _quat.z = 0;
  _quat.w = cos(_half);
  return _quat;
}

// Computes a forward vector from yaw/pitch angles.
function demo_forward(_yaw, _pitch) {
  var _y = degtorad(_yaw);
  var _p = degtorad(_pitch);
  var _cp = cos(_p);
  return new GM3D_Vec3(sin(_y) * _cp, sin(_p), -cos(_y) * _cp);
}

// Computes the character's heading using the same +Y yaw convention as
// demo_yaw_quat(), whose local forward axis is -Z.
function demo_player_heading(_yaw) {
  var _y = degtorad(_yaw);
  return new GM3D_Vec3(-sin(_y), 0.0, -cos(_y));
}

// Computes the third-person camera target from the player's heading.
function demo_camera_target_position(_player_pos) {
  var _pitch_rad = degtorad(demo_cam_pitch);
  var _horizontal_offset = demo_cam_follow_distance * cos(_pitch_rad);
  var _camera_forward = demo_player_heading(demo_cam_yaw);
  var _camera_right = new GM3D_Vec3(-_camera_forward.z, 0.0, _camera_forward.x);
  return new GM3D_Vec3(
    _player_pos.x - _camera_forward.x * _horizontal_offset + _camera_right.x * demo_cam_shoulder_offset,
    max(_player_pos.y + 0.55 + demo_cam_follow_distance * sin(_pitch_rad), 0.85),
    _player_pos.z - _camera_forward.z * _horizontal_offset + _camera_right.z * demo_cam_shoulder_offset
  );
}

// Orients a node toward a direction vector.
function demo_look_at(_node, _dir) {
  var _forward = _dir.clone();
  _forward.normalize();
  var _up = GM3D_Vec3.up();

  if (abs(_forward.dot(_up)) >= 0.999) _up = GM3D_Vec3.forward();
  var _rot = GM3D_Quaternion.fromLookRotation(_forward, _up);
  _node.setLocalRotation(_rot.normalizeSafe(0.000001));
}

// Positions the camera from stored settings.
function demo_place_camera() {
  demo_cam.setLocalPosition(demo_cam_pos);
  var _pitch_rad = degtorad(demo_cam_pitch);
  var _camera_forward = demo_player_heading(demo_cam_yaw);
  var _camera_back = new GM3D_Vec3(
    -_camera_forward.x * cos(_pitch_rad),
    sin(_pitch_rad),
    -_camera_forward.z * cos(_pitch_rad)
  );
  demo_cam.setLocalRotation(GM3D_Quaternion.fromLookRotation(_camera_back, GM3D_Vec3.up()));
}
