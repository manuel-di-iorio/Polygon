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
  demo_cam_pos = new GM3D_Vec3(-1.3, 1.0, 4.5);
  demo_cam_yaw = 190.0;
  demo_cam_pitch = 10.0;

  demo_build_environment();
  demo_build_sun();
  demo_build_camera();
  demo_build_props();

  demo_scene.update(0);
}

// Destroys demo scene and loaded models.
function demo_destroy() {
  if (!is_undefined(demo_scene)) demo_scene.destroy();
  demo_scene = undefined;
  demo_cam = undefined;
  demo_cam_comp = undefined;

  for (var _i = 0, _n = array_length(demo_models); _i < _n; _i++) demo_models[_i].destroy();
  demo_models = [];
  demo_cache = {};
  demo_renderer = undefined;
}

// Updates demo scene animation.
function demo_step() {
  demo_scene.update(delta_time * 0.000001);
}

// Renders demo scene.
function demo_draw() {
  demo_renderer.render(demo_scene);
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
  var _props = [
    { path: "kenney_platformer-kit/platform.glb", pos: [ 0, -0.4, 0 ], scale: 2.4 },
    { path: "kenney_platformer-kit/tree.glb", pos: [ -3.2, 0, -3.6 ], scale: 1.2 },
    { path: "kenney_platformer-kit/tree-pine.glb", pos: [ 3.4, 0, -3.2 ], scale: 1.1 },
    { path: "kenney_platformer-kit/flowers.glb", pos: [ -1.6, 0, -1.8 ] },
    { path: "kenney_platformer-kit/grass.glb", pos: [ 1.8, 0, -1.6 ] },
    { path: "kenney_platformer-kit/rocks.glb", pos: [ 0, 0, -2.8 ], yaw: 20, scale: 1.1 },
    { path: "kenney_mini-characters/character-female-b.glb", pos: [ -0.9, 0, 0 ], yaw: 20 },
    { path: "kenney_cube-pets_1.0/animal-fox.glb", pos: [ 0.95, 0, 0.55 ], yaw: -25, scale: 0.3 },
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
function demo_load_model(_path, _label = undefined) {
  var _src = undefined;

  if (variable_struct_exists(demo_cache, _path)) _src = demo_cache[$ _path];

  if (_src == undefined) {
    _src = GM3D_Scene.loadGltf(working_directory + _path);

    if (_src == undefined) return undefined;
    demo_assign_shaders(_src);
    _src.freeze();
    array_push(demo_models, _src);
    demo_cache[$ _path] = _src;
  }

  var _lab = (is_string(_label) && _label != "") ? _label : demo_pretty_label(_path);
  return { model: _src, label: _lab, path: _path };
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
  demo_on_spawn(_node, _res.path, _res.model);
  return _node;
}

// Editor spawn hook: assigns shaders and starts the idle animation.
// Signature is fixed by the editor (wrapper node, model id, model):
// walk the subtree, the model root lives inside the wrapper.
function demo_on_spawn(_node, _model_id, _src) {
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
  demo_look_at(demo_cam, demo_forward(demo_cam_yaw, demo_cam_pitch));
}
