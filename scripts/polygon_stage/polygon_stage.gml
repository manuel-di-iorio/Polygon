// polygon_stage — editor grid, skybox dome, chrome checks.

// ---------------------------------------------------------------------------
// Chrome checks
// ---------------------------------------------------------------------------

// Checks if node is editor grid.
function __polygon_is_grid(_ed, _node) {
  if (_node == undefined)  return false;
  if (_ed != undefined && variable_struct_exists(_ed, "grid_node") && _ed.grid_node != undefined)  if (__polygon_node_same(_node, _ed.grid_node))  return true;
  return is_string(_node.name) && _node.name == "__editor_grid";
}

// Checks if node is skybox dome.
function __polygon_is_sky(_node) {
  if (_node == undefined)  return false;
  return is_string(_node.name) && _node.name == "__skybox";
}

// ---------------------------------------------------------------------------
// Shared source loading
// ---------------------------------------------------------------------------

// Loads an editor chrome model and assigns one forward shader to its materials.
function __polygon_stage_load(_rel_path, _shader) {
  var _path = working_directory + _rel_path;

  if (!file_exists(_path))  return undefined;
  var _src = GM3D_Scene.loadGltf(_path);

  if (_src == undefined)  return undefined;
  var _mats = _src.getMaterials();

  for (var _i = 0, _n = array_length(_mats); _i < _n; _i++)  _mats[_i].setShader(GM3D_ERenderPass.Forward, _shader);
  _src.freeze();
  return _src;
}

// ---------------------------------------------------------------------------
// Grid
// ---------------------------------------------------------------------------

// Creates editor grid if enabled.
function __polygon_grid_ensure(_ed) {
  if (_ed == undefined || _ed.rt == undefined || _ed.rt.scene == undefined)  return;
  if (!variable_struct_exists(_ed, "grid_node"))  _ed.grid_node = undefined;
  if (!variable_struct_exists(_ed, "grid_src"))  _ed.grid_src = undefined;
  if (!variable_struct_exists(_ed, "grid_mat"))  _ed.grid_mat = undefined;
  if (!variable_struct_exists(_ed, "grid_step") || !is_real(_ed.grid_step))  _ed.grid_step = 1;
  if (!variable_struct_exists(_ed, "show_grid") || !_ed.show_grid) {
    __polygon_grid_remove(_ed);
    return;
  }

  if (_ed.grid_node != undefined)  return;
  if (_ed.grid_src == undefined) {
    _ed.grid_src = __polygon_stage_load("__PolygonEditor__/models/grid.glb", shPolygonEditorGrid);

    if (_ed.grid_src == undefined)  return;
  }

  var _node = __polygon_spawn(_ed, { kind: "chrome", model: _ed.grid_src, sx: 6, sy: 1, sz: 6 });

  if (_node == undefined)  return;
  _ed.grid_node = _node;
  _node.setLocalScale(new GM3D_Vec3(6, 1, 6));
  __polygon_flags_apply(_node, false, true);
  var _mats = _ed.grid_src.getMaterials();
  _ed.grid_mat = array_length(_mats) > 0 ? _mats[0] : undefined;

  if (_ed.grid_mat != undefined)  _ed.grid_mat.setBlendEnable(false);
  __polygon_grid_bg_sync(_ed);
  __polygon_grid_step_sync(_ed);
  _ed.rt.scene.update(0);
}

// Updates grid shader step size.
function __polygon_grid_step_sync(_ed) {
  if (_ed == undefined)  return;
  var _step = 1;

  if (variable_struct_exists(_ed, "grid_step") && is_real(_ed.grid_step))  _step = clamp(_ed.grid_step, 0.1, 8);
  var _mats = [];

  if (variable_struct_exists(_ed, "grid_src") && _ed.grid_src != undefined)  _mats = _ed.grid_src.getMaterials();
  if (!is_array(_mats) || array_length(_mats) == 0)  if (variable_struct_exists(_ed, "grid_mat") && _ed.grid_mat != undefined)  _mats = [ _ed.grid_mat ];
  for (var _i = 0, _n = array_length(_mats); _i < _n; _i++)  _mats[_i].setFloat("u_grid_step", _step);
}

// Sets grid step and refreshes.
function __polygon_grid_set_step(_ed, _v) {
  if (_ed == undefined || !is_real(_v))  return;
  _ed.grid_step = clamp(_v, 0.1, 8);
  __polygon_grid_step_sync(_ed);

  if (_ed.rt != undefined && _ed.rt.scene != undefined && variable_struct_exists(_ed, "grid_node") && _ed.grid_node != undefined)  _ed.rt.scene.update(0);
}

// Syncs grid background color (sky horizon when the dome is up).
function __polygon_grid_bg_sync(_ed) {
  if (_ed == undefined || !variable_struct_exists(_ed, "grid_mat") || _ed.grid_mat == undefined)  return;
  var _bg = [ 0.84, 0.87, 0.91 ]; // must match u_skyHorizon in __polygon_sky_paint

  if (__polygon_sky_find(_ed) == undefined) {
    var _win = window_get_colour();
    _bg = [ colour_get_red(_win) / 255, colour_get_green(_win) / 255, colour_get_blue(_win) / 255 ];
  }

  _ed.grid_mat.setFloatArray("u_grid_bg", _bg);
}

// Drops a stage node (grid/sky) by field key.
function __polygon_stage_drop(_ed, _key) {
  if (_ed == undefined || !variable_struct_exists(_ed, _key))  return;
  var _node = _ed[$ _key];

  if (_node == undefined)  return;
  _node.destroy();
  _ed[$ _key] = undefined;

  if (_ed.rt != undefined && _ed.rt.scene != undefined)  _ed.rt.scene.update(0);
}

// Removes editor grid node.
function __polygon_grid_remove(_ed) {
  __polygon_stage_drop(_ed, "grid_node");
}

// Keeps grid quad centered under the camera (lines stay world-anchored,
// so the grid feels infinite in every direction).
function __polygon_grid_follow(_ed) {
  if (_ed == undefined || _ed.rt == undefined || _ed.rt.cam == undefined)  return;
  if (!variable_struct_exists(_ed, "grid_node") || _ed.grid_node == undefined)  return;
  var _cam_pos = _ed.rt.cam.getLocalPosition();
  var _grid_pos = _ed.grid_node.getLocalPosition();

  if (_grid_pos.x != _cam_pos.x || _grid_pos.z != _cam_pos.z)  _ed.grid_node.setLocalPosition(new GM3D_Vec3(_cam_pos.x, 0, _cam_pos.z));
}

// ---------------------------------------------------------------------------
// Skybox dome
// ---------------------------------------------------------------------------

// Finds skybox dome root node.
function __polygon_sky_find(_ed) {
  if (_ed == undefined || _ed.rt == undefined || _ed.rt.scene == undefined)  return undefined;
  if (variable_struct_exists(_ed, "sky_node") && _ed.sky_node != undefined && is_string(_ed.sky_node.name) && _ed.sky_node.name == "__skybox")  return _ed.sky_node;
  var _roots = _ed.rt.scene.getNodes();

  for (var _i = 0, _n = array_length(_roots); _i < _n; _i++)  if (is_string(_roots[_i].name) && _roots[_i].name == "__skybox")  return _roots[_i];
  return undefined;
}

// Ensures editor skybox dome (editor-only, like the grid).
function __polygon_sky_ensure(_ed) {
  if (_ed == undefined || _ed.rt == undefined || _ed.rt.scene == undefined)  return;
  if (!variable_struct_exists(_ed, "sky_node"))  _ed.sky_node = undefined;
  if (!variable_struct_exists(_ed, "sky_src"))  _ed.sky_src = undefined;
  if (!variable_struct_exists(_ed, "sky_mat"))  _ed.sky_mat = undefined;
  if (_ed.sky_node != undefined)  return;
  if (_ed.sky_src == undefined) {
    _ed.sky_src = __polygon_stage_load("__PolygonEditor__/models/skybox.glb", shPolygonEditorSky);

    if (_ed.sky_src == undefined)  return;
    var _mats = _ed.sky_src.getMaterials();
    _ed.sky_mat = array_length(_mats) > 0 ? _mats[0] : undefined;
  }

  var _node = __polygon_spawn(_ed, { kind: "chrome", model: _ed.sky_src });

  if (_node == undefined)  return;
  _ed.sky_node = _node;
  var _mesh = _node.getMeshComponent();

  if (_mesh != undefined)  _mesh.setFlags(0);
  __polygon_sky_paint(_ed);
  __polygon_grid_bg_sync(_ed);
  _ed.rt.scene.update(0);
}

// Removes editor skybox dome.
function __polygon_sky_remove(_ed) {
  __polygon_stage_drop(_ed, "sky_node");
  __polygon_grid_bg_sync(_ed);
}

// Finds first tracked directional light world-forward direction.
function __polygon_sky_sun_dir(_ed) {
  var _ens = __polygon_reg_each(_ed);

  for (var _i = 0, _n = array_length(_ens); _i < _n; _i++) {
    var _en = _ens[_i];

    if (!is_struct(_en) || _en.kind != "light")  continue;
    if (!is_struct(_en.data) || _en.data.type != "directional")  continue;
    var _node = _en[$ "node"];

    if (_node == undefined)  continue;
    var _fwd = _node.getWorldForward();

    if (_fwd == undefined)  continue;
    var _len = sqrt(_fwd.x * _fwd.x + _fwd.y * _fwd.y + _fwd.z * _fwd.z);

    if (_len > 0.0001)  return [ _fwd.x / _len, _fwd.y / _len, _fwd.z / _len ];
    break;
  }

  return undefined;
}

// Paints skybox palette and syncs sun glow.
function __polygon_sky_paint(_ed) {
  if (_ed == undefined || !variable_struct_exists(_ed, "sky_mat") || _ed.sky_mat == undefined)  return;
  var _mat = _ed.sky_mat;
  _mat.setFloatArray("u_skyTop", [ 0.25, 0.5, 0.83 ]);
  _mat.setFloatArray("u_skyHorizon", [ 0.84, 0.87, 0.91 ]);
  _mat.setFloatArray("u_skyBottom", [ 0.412, 0.388, 0.365 ]);
  _mat.setFloatArray("u_sunColor", [ 1.0, 1.0, 1.0 ]);
  _mat.setFloat("u_sunGlow", 1.0);
  var _dir = __polygon_sky_sun_dir(_ed);
  _dir ??= [ 0.3, 0.69, 0.39 ];

  _mat.setFloatArray("u_sunDir", _dir);
}

// Follows camera with skybox dome and syncs sun glow.
function __polygon_sky_sync(_ed) {
  if (_ed == undefined || _ed.rt == undefined || _ed.rt.scene == undefined || _ed.rt.cam == undefined)  return;
  var _sky = __polygon_sky_find(_ed);
  _ed.sky_node = _sky;

  if (_sky == undefined)  return;
  var _cam_pos = _ed.rt.cam.getLocalPosition();
  _sky.setLocalPosition(new GM3D_Vec3(_cam_pos.x, _cam_pos.y, _cam_pos.z));
  var _mat = undefined;
  var _mesh = _sky.getMeshComponent();

  if (_mesh != undefined)  _mat = _mesh.getMaterial();
  if (_mat == undefined)  return;
  var _dir = __polygon_sky_sun_dir(_ed);

  if (_dir == undefined)  return;
  _mat.setFloatArray("u_sunDir", _dir);
}
