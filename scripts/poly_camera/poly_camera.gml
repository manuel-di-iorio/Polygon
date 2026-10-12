// poly_camera — viewport camera, orbit/fly/pan/zoom, smooth transitions.

// ---------------------------------------------------------------------------
// Forward and home
// ---------------------------------------------------------------------------

// Computes normalized camera forward direction vector.
function __poly_view_forward(_ed) {
  var _fwd = __poly_quat_forward(_ed.rt.cam.getLocalRotation());
  _fwd.normalizeSafe(0.000001);
  return _fwd;
}

// Cached camera forward: reuses _ed.vp.camForward when available
// (computed once per frame in __poly_viewport), else falls back.
function __poly_view_forward_cached(_ed) {
  if (_ed != undefined && variable_struct_exists(_ed, "vp") && is_struct(_ed.vp)
  && variable_struct_exists(_ed.vp, "camForward") && _ed.vp.camForward != undefined) {
    var _f = _ed.vp.camForward;
    var _c = new GM3D_Vec3(_f.x, _f.y, _f.z);
    _c.normalizeSafe(0.000001);
    return _c;
  }

  return __poly_view_forward(_ed);
}

// Caches __poly_quat_basis per frame on _ed (same quaternion reuses basis).
function __poly_quat_basis_cached(_ed, _q) {
  if (_ed != undefined && variable_struct_exists(_ed, "_qb_cache") && is_struct(_ed._qb_cache)) {
    var _c = _ed._qb_cache;
    if (_c.x == _q.x && _c.y == _q.y && _c.z == _q.z && _c.w == _q.w) return _c.basis;
  }

  var _b = __poly_quat_basis(_q);

  if (_ed != undefined) {
    _ed._qb_cache = { x: _q.x, y: _q.y, z: _q.z, w: _q.w, basis: _b };
  }

  return _b;
}

// Stores current camera position and rotation as home.
function __poly_cam_remember(_ed) {
  _ed.cam_home = undefined;

  if (_ed.rt == undefined || _ed.rt.cam == undefined) return;
  var _pos = _ed.rt.cam.getLocalPosition();
  var _rot = _ed.rt.cam.getLocalRotation();
  _ed.cam_home = { pos: [ _pos.x, _pos.y, _pos.z ], rot: [ _rot.x, _rot.y, _rot.z, _rot.w ] };
}

// Starts a smooth camera transition (rotation kept when _to_quat undefined).
function __poly_cam_animate(_ed, _to_pos, _to_quat, _dur = 0.4) {
  var _pos = _ed.rt.cam.getLocalPosition();
  var _rot = _ed.rt.cam.getLocalRotation();
  var _q1 = _to_quat == undefined ? _rot : _to_quat;
  _ed.cam_anim = {
    t: 0,
    dur: _dur,
    q0: [ _rot.x, _rot.y, _rot.z, _rot.w ],
    q1: [ _q1.x, _q1.y, _q1.z, _q1.w ],
    p0: [ _pos.x, _pos.y, _pos.z ],
    p1: [ _to_pos.x, _to_pos.y, _to_pos.z ],
  };
}

// Advances smooth camera transition toward target pose.
function __poly_cam_anim_step(_ed, _dt) {
  var _anim = _ed.cam_anim;

  if (_anim == undefined) return;
  _anim.t += _dt / max(_anim.dur, 0.01);

  if (_anim.t >= 1) {
    _ed.rt.cam.setLocalPosition(new GM3D_Vec3(_anim.p1[0], _anim.p1[1], _anim.p1[2]));
    _ed.rt.cam.setLocalRotation(__poly_quat_slerp(_anim.q0, _anim.q1, 1));
    _ed.cam_anim = undefined;
    return;
  }

  var _e = _anim.t * _anim.t * (3 - 2 * _anim.t);
  _ed.rt.cam.setLocalPosition(
    new GM3D_Vec3(
      _anim.p0[0] + (_anim.p1[0] - _anim.p0[0]) * _e,
      _anim.p0[1] + (_anim.p1[1] - _anim.p0[1]) * _e,
      _anim.p0[2] + (_anim.p1[2] - _anim.p0[2]) * _e
    )
  );
  _ed.rt.cam.setLocalRotation(__poly_quat_slerp(_anim.q0, _anim.q1, _e));
}

// Restores camera to remembered home position instantly or animated.
function __poly_cam_home(_ed, _smooth = false) {
  if (
    _ed == undefined ||
    _ed.cam_home == undefined ||
    _ed.rt == undefined ||
    _ed.rt.cam == undefined
    ) {
    return;
  }

  var _home = _ed.cam_home;
  var _to_pos = new GM3D_Vec3(_home.pos[0], _home.pos[1], _home.pos[2]);
  var _to_rot = __poly_quat_from_array(_home.rot);

  if (!_smooth) {
    _ed.rt.cam.setLocalPosition(_to_pos);
    _ed.rt.cam.setLocalRotation(_to_rot);
    _ed.cam_anim = undefined;
    return;
  }

  __poly_cam_animate(_ed, _to_pos, _to_rot, 0.5);
}

// ---------------------------------------------------------------------------
// Viewport camera
// ---------------------------------------------------------------------------

// Ensures separate editor viewport camera exists and selects it.
function __poly_viewcam_ensure(_ed) {
  if (_ed == undefined || _ed.rt == undefined || _ed.rt.scene == undefined) return undefined;

  if (_ed.viewcam == undefined) {
    var _node = _ed.rt.scene.createNode("__editor_camera");

    if (_node == undefined) return undefined;
    var _comp = new GM3D_CameraComponent();
    _node.addComponent(_comp);
    _comp.setEnabled(false);
    _ed.viewcam = _node;
  }

  _ed.rt.cam = _ed.viewcam;
  return _ed.viewcam;
}

// Seeds editor camera from given gameplay camera pose and settings.
function __poly_viewcam_seed_from(_ed, _src) {
  if (_ed == undefined) return false;
  __poly_viewcam_ensure(_ed);
  var _cam = _ed.viewcam;

  if (_cam == undefined || _src == undefined) return false;
  var _pos = _src.getLocalPosition();
  var _rot = _src.getLocalRotation();
  _cam.setLocalPosition(new GM3D_Vec3(_pos.x, _pos.y, _pos.z));
  _cam.setLocalRotation(_rot.clone());
  __poly_camera_apply(_cam, __poly_camera_read(_src));
  var _comp = _cam.getCameraComponent();

  if (_comp != undefined) _comp.setEnabled(true);
  _ed.rt.scene.update(0);
  __poly_cam_remember(_ed);
  return true;
}

// Seeds editor camera from resolved gameplay camera.
function __poly_viewcam_seed(_ed) {
  if (_ed == undefined) return false;
  var _game = __poly_gamecam_resolve(_ed);

  if (_game == undefined) {
    __poly_viewcam_ensure(_ed);

    if (_ed.viewcam != undefined) {
      var _comp = _ed.viewcam.getCameraComponent();

      if (_comp != undefined) _comp.setEnabled(true);
    }

    __poly_cam_remember(_ed);
    return false;
  }

  return __poly_viewcam_seed_from(_ed, _game);
}

// ---------------------------------------------------------------------------
// Orbit and gestures
// ---------------------------------------------------------------------------

// Reads clamped mouse deltas.
function __poly_mouse_delta(_max_abs = 64) {
  return [
    clamp(window_mouse_get_delta_x(), -_max_abs, _max_abs),
    clamp(window_mouse_get_delta_y(), -_max_abs, _max_abs),
  ];
}

// Rotates camera incrementally from mouse deltas (Unity-style free loop,
// no pole clamp): yaw about world up, then pitch about the new camera right.
// Sets the node rotation directly and returns the live forward vector.
function __poly_orbit_apply(_ed, _dx, _dy) {
  var _node = _ed.rt.cam;
  var _rot = _node.getLocalRotation().clone();
  var _yaw = GM3D_Quaternion.fromAxisAngle(
    GM3D_Vec3.up(),
    degtorad(-_dx * 0.18)
  );
  _yaw.multiply(_rot);
  var _basis = __poly_quat_basis_cached(_ed, _yaw);
  var _pitch = GM3D_Quaternion.fromAxisAngle(_basis[0], degtorad(-_dy * 0.18));
  _pitch.multiply(_yaw);
  var _qn = _pitch.normalizeSafe(0.000001);
  _node.setLocalRotation(_qn);
  return __poly_quat_forward(_qn);
}

// Returns the orbit/pan/zoom pivot: selection pivot, else a point ahead.
function __poly_cam_pivot(_ed, _pos, _fwd, _dist = 10) {
  if (array_length(_ed.sel) > 0) return __poly_gizmo_pivot(_ed.sel);
  return new GM3D_Vec3(_pos.x - _fwd.x * _dist, _pos.y - _fwd.y * _dist, _pos.z - _fwd.z * _dist);
}

// Normalizes a forward vector onto the XZ plane.
function __poly_planar(_fwd) {
  var _len = sqrt(_fwd.x * _fwd.x + _fwd.z * _fwd.z);

  if (_len <= 0.000001) return [ 1.0, 0.0 ];
  return [ _fwd.x / _len, _fwd.z / _len ];
}

// Picks the active camera gesture from mouse state.
function __poly_cam_gesture(_ed, _allow_keys, _allow_zoom) {
  var _owner = __poly_input_owner_sync(_ed);
  var _alt = keyboard_check(vk_alt);
  var _can_start =
    _allow_keys &&
    _allow_zoom &&
    _owner == undefined &&
    _ed.giz.drag == -1 &&
    !_ed.press_vp;

  if (_can_start) {
    if (_alt && mouse_check_button(mb_left)) {
      _owner = "camera_orbit";
    } else if (_alt && mouse_check_button(mb_right)) {
      _owner = "camera_zoom";
    } else if (!_alt && mouse_check_button(mb_right)) {
      _owner = "camera_fly";
    } else if (mouse_check_button(mb_middle)) {
      _owner = "camera_pan";
    }

    _ed.input_owner = _owner;
  }

  return { owner: _owner, alt: _alt };
}

// Handles orbit, pan, zoom, and fly camera controls.
function __poly_cam_fly(_ed, _input, _dt) {
  var _vp = _input.vp;
  var _allow_keys = _input.camera_keys;
  var _allow_zoom = _input.camera_zoom;
  var _node = _ed.rt.cam;

  if (_node == undefined) return;
  _ed.cam_speed_notice = max(0, _ed.cam_speed_notice - _dt);
  var _fwd = __poly_view_forward_cached(_ed);
  var _yaw = radtodeg(arctan2(_fwd.x, -_fwd.z));
  var _pitch = radtodeg(arcsin(clamp(_fwd.y, -1.0, 1.0)));
  var _gesture = __poly_cam_gesture(_ed, _allow_keys, _allow_zoom);
  var _owner = _gesture.owner;
  var _alt = _gesture.alt;
  var _orbit =
    _allow_keys &&
    _owner == "camera_orbit" &&
    _alt &&
    mouse_check_button(mb_left);
  var _pan =
    _allow_keys && _owner == "camera_pan" && mouse_check_button(mb_middle);
  var _zoom =
    _allow_keys &&
    _owner == "camera_zoom" &&
    _alt &&
    mouse_check_button(mb_right);
  var _fly =
    _allow_keys &&
    _owner == "camera_fly" &&
    !_alt &&
    mouse_check_button(mb_right);

  if (_orbit && !_ed.cam_orbit) {
    var _origin = _node.getLocalPosition();
    _ed.cam_orbit_target = new GM3D_Vec3(
      _origin.x - _fwd.x * 10,
      _origin.y - _fwd.y * 10,
      _origin.z - _fwd.z * 10
    );
    _ed.cam_orbit_radius = 10;
  }

  if (_zoom && !_ed.cam_zoom) {
    var _zoom_pos = _node.getLocalPosition();
    _ed.cam_zoom_target = __poly_cam_pivot(_ed, _zoom_pos, _fwd);
  }

  _ed.cam_orbit = _orbit;
  _ed.cam_pan = _pan;
  _ed.cam_zoom = _zoom;
  _ed.cam_fly = _fly;

  if (
    (_owner == "camera_orbit" && !_orbit) ||
    (_owner == "camera_pan" && !_pan) ||
    (_owner == "camera_zoom" && !_zoom) ||
    (_owner == "camera_fly" && !_fly)
    ) {
    _ed.input_owner = undefined;
  }

  var _rotated = false;
  var _live_fwd = undefined;
  var _md = __poly_mouse_delta();

  if (_orbit || _fly) {
    _live_fwd = __poly_orbit_apply(_ed, _md[0], _md[1]);
    _rotated = true;
  }

  var _boost = keyboard_check(vk_shift) ? 2.0 : 1.0;
  var _step = _dt * _ed.cam_fly_speed * _boost;
  var _move = _fly && !keyboard_check(vk_control);
  var _fw = _move ? keyboard_check(ord("W")) - keyboard_check(ord("S")) : 0.0;
  var _strafe = _move ? keyboard_check(ord("A")) - keyboard_check(ord("D")) : 0.0;
  var _up = _move ? keyboard_check(ord("E")) - keyboard_check(ord("Q")) : 0.0;
  var _wheel = 0;

  if (_allow_zoom && _allow_keys) {
    if (mouse_wheel_up()) {
      _wheel = -1;
    } else if (mouse_wheel_down()) {
      _wheel = 1;
    }
  }

  if (_fly && _wheel != 0) {
    _ed.cam_fly_speed = clamp(
      _ed.cam_fly_speed * (_wheel < 0 ? 1.2 : 1 / 1.2),
      0.1,
      1000
    );
    _ed.cam_speed_notice = 2;
    _wheel = 0;
  }

  if (!_orbit && !_pan && !_zoom && !_fly && _wheel == 0) return;
  _ed.cam_anim = undefined;

  var _f = _rotated ? _live_fwd : __poly_cam_forward(_yaw, _pitch);
  var _flat = __poly_planar(_f);
  var _pfx = _flat[0];
  var _pfz = _flat[1];
  var _right = [ -_pfz, _pfx ];

  var _pos = _node.getLocalPosition();
  var _nx = _pos.x + (-_pfx * _fw + _right[0] * _strafe) * _step;
  var _nz = _pos.z + (-_pfz * _fw + _right[1] * _strafe) * _step;
  var _ny = _pos.y - _f.y * _fw * _step + _up * _step;

  if (_orbit) {
    _nx = _ed.cam_orbit_target.x + _f.x * _ed.cam_orbit_radius;
    _ny = _ed.cam_orbit_target.y + _f.y * _ed.cam_orbit_radius;
    _nz = _ed.cam_orbit_target.z + _f.z * _ed.cam_orbit_radius;
  }

  if (_zoom || _wheel != 0) {
    var _target = _zoom ? _ed.cam_zoom_target : __poly_cam_pivot(_ed, _pos, _f);
    var _zx = _nx - _target.x;
    var _zy = _ny - _target.y;
    var _zz = _nz - _target.z;
    var _zoom_factor = _zoom
      ? 1 + _md[1] * 0.001
      : _wheel < 0
      ? 0.9
      : 1.1;
    _zoom_factor = max(_zoom_factor, 0.01);
    _nx = _target.x + _zx * _zoom_factor;
    _ny = _target.y + _zy * _zoom_factor;
    _nz = _target.z + _zz * _zoom_factor;
  }

  if (_pan) {
    var _cam_quat = _node.getLocalRotation();
    var _basis = __poly_quat_basis_cached(_ed, _cam_quat);
    var _pivot = __poly_cam_pivot(_ed, _pos, _f);
    var _to_pivot = [ _pivot.x - _pos.x, _pivot.y - _pos.y, _pivot.z - _pos.z ];
    var _plen = sqrt(_to_pivot[0] * _to_pivot[0] + _to_pivot[1] * _to_pivot[1] + _to_pivot[2] * _to_pivot[2]);

    if (_plen > 0.001) {
      var _k = ((2 * _plen * tan(_vp.fovY * 0.5)) / max(_vp.winH, 1)) * 0.8;
      var _pmd = _md;
      _nx += (-_basis[0].x * _pmd[0] + _basis[1].x * _pmd[1]) * _k;
      _ny += (-_basis[0].y * _pmd[0] + _basis[1].y * _pmd[1]) * _k;
      _nz += (-_basis[0].z * _pmd[0] + _basis[1].z * _pmd[1]) * _k;
    }
  }

  _node.setLocalPosition(new GM3D_Vec3(_nx, _ny, _nz));

  if (_orbit || _pan || _zoom || _fly) __poly_wrap_camera(_ed);
}

// Pans camera in screen space for View tool drag.
function __poly_view_pan(_ed, _vp) {
  if (
    _ed == undefined ||
    _ed.rt == undefined ||
    _ed.rt.cam == undefined ||
    _vp == undefined
    ) {
    return;
  }

  var _node = _ed.rt.cam;
  var _pos = _node.getLocalPosition();
  var _basis = __poly_quat_basis_cached(_ed, _node.getLocalRotation());
  var _fwd = __poly_view_forward_cached(_ed);
  var _pivot = __poly_cam_pivot(_ed, _pos, _fwd);
  var _to_pivot = [ _pivot.x - _pos.x, _pivot.y - _pos.y, _pivot.z - _pos.z ];
  var _plen = sqrt(_to_pivot[0] * _to_pivot[0] + _to_pivot[1] * _to_pivot[1] + _to_pivot[2] * _to_pivot[2]);

  if (_plen <= 0.001) return;
  _ed.cam_anim = undefined;
  var _k = ((2 * _plen * tan(_vp.fovY * 0.5)) / max(_vp.winH, 1)) * 0.8;
  var _md = __poly_mouse_delta();
  _node.setLocalPosition(
    new GM3D_Vec3(
      _pos.x + (-_basis[0].x * _md[0] + _basis[1].x * _md[1]) * _k,
      _pos.y + (-_basis[0].y * _md[0] + _basis[1].y * _md[1]) * _k,
      _pos.z + (-_basis[0].z * _md[0] + _basis[1].z * _md[1]) * _k
    )
  );
  __poly_wrap_camera(_ed);
}

// Slides camera to center node keeping distance and orientation.
function __poly_view_focus_node(_ed, _node) {
  if (
    _ed == undefined ||
    _ed.rt == undefined ||
    _ed.rt.cam == undefined ||
    _node == undefined
    ) {
    return false;
  }

  var _target = _node.getWorldPosition();
  var _pos = _ed.rt.cam.getLocalPosition();
  var _fwd = __poly_view_forward_cached(_ed);
  var _flen = sqrt(_fwd.x * _fwd.x + _fwd.y * _fwd.y + _fwd.z * _fwd.z);

  if (_flen <= 0.0001) return false;
  var _n = [ _fwd.x / _flen, _fwd.y / _flen, _fwd.z / _flen ];
  var _delta = [ _target.x - _pos.x, _target.y - _pos.y, _target.z - _pos.z ];
  var _along = _delta[0] * _n[0] + _delta[1] * _n[1] + _delta[2] * _n[2];
  var _to_pos = new GM3D_Vec3(
    _pos.x + _delta[0] - _along * _n[0],
    _pos.y + _delta[1] - _along * _n[1],
    _pos.z + _delta[2] - _along * _n[2]
  );
  __poly_cam_animate(_ed, _to_pos, undefined, 0.4);
  return true;
}

// Animates camera to align with selected viewcube direction.
function __poly_viewcube_snap(_ed, _n) {
  if (_ed == undefined || _ed.rt == undefined || _ed.rt.cam == undefined) return;
  var _fwd = __poly_view_forward_cached(_ed);
  var _up = GM3D_Vec3.up();
  var _dir = new GM3D_Vec3(_n.x, _n.y, _n.z);
  var _tilted = false;

  if (abs(_n.x * _up.x + _n.y * _up.y + _n.z * _up.z) >= 0.99) {
    var _hx = _fwd.x;
    var _hz = _fwd.z;
    var _hl = sqrt(_hx * _hx + _hz * _hz);

    if (_hl > 0.001) {
      _dir = new GM3D_Vec3(
        _n.x + (_hx / _hl) * 0.035,
        _n.y,
        _n.z + (_hz / _hl) * 0.035
      );
      _dir.normalizeSafe(0.000001);
      _tilted = true;
    }
  }

  var _node = _ed.rt.cam;
  var _rot = _node.getLocalRotation();
  var _to_rot = _rot;

  if (_tilted || abs(_n.x * _up.x + _n.y * _up.y + _n.z * _up.z) < 0.99) _to_rot = GM3D_Quaternion.fromLookRotation(_dir, _up).normalizeSafe(0.000001);
  var _pos = _node.getLocalPosition();
  var _ax = _pos.x;
  var _ay = _pos.y;
  var _az = _pos.z;

  if (array_length(_ed.sel) > 0) {
    var _pivot = __poly_gizmo_pivot(_ed.sel);
    _ax = _pivot.x;
    _ay = _pivot.y;
    _az = _pivot.z;
  } else {
    _ax = _pos.x - _fwd.x * 10;
    _ay = _pos.y - _fwd.y * 10;
    _az = _pos.z - _fwd.z * 10;
  }

  var _dx = _pos.x - _ax;
  var _dy = _pos.y - _ay;
  var _dz = _pos.z - _az;
  var _dist = sqrt(_dx * _dx + _dy * _dy + _dz * _dz);

  if (_dist < 0.001) return;
  _ed.cam_anim = {
    t: 0,
    dur: 0.4,
    q0: [ _rot.x, _rot.y, _rot.z, _rot.w ],
    q1: [ _to_rot.x, _to_rot.y, _to_rot.z, _to_rot.w ],
    p0: [ _pos.x, _pos.y, _pos.z ],
    p1: [ _ax + _dir.x * _dist, _ay + _dir.y * _dist, _az + _dir.z * _dist ],
  };
}
