// poly_math - camera vectors, quaternions, 2D picking, snap, sorting.

// ---------------------------------------------------------------------------
// Camera
// ---------------------------------------------------------------------------

// Computes forward vector from yaw and pitch.
function __poly_cam_forward(_yaw, _pitch) {
  var _y = degtorad(_yaw);
  var _p = degtorad(_pitch);
  var _cp = cos(_p);
  return new GM3D_Vec3(sin(_y) * _cp, sin(_p), -cos(_y) * _cp);
}

// ---------------------------------------------------------------------------
// Quaternions
// ---------------------------------------------------------------------------

// Interpolates between two quaternions spherically ([x, y, z, w] arrays).
function __poly_quat_slerp(_from, _to, _t) {
  var _dot = _from[0] * _to[0] + _from[1] * _to[1] + _from[2] * _to[2] + _from[3] * _to[3];
  var _tx = _to[0];
  var _ty = _to[1];
  var _tz = _to[2];
  var _tw = _to[3];

  if (_dot < 0) {
    _dot = -_dot;
    _tx = -_tx;
    _ty = -_ty;
    _tz = -_tz;
    _tw = -_tw;
  }

  var _s0 = 1 - _t;
  var _s1 = _t;

  if (_dot < 0.9995) {
    var _th = arccos(clamp(_dot, -1, 1));
    var _s = sin(_th);
    _s0 = sin((1 - _t) * _th) / _s;
    _s1 = sin(_t * _th) / _s;
  }

  var _q = new GM3D_Quaternion();
  _q.x = _from[0] * _s0 + _tx * _s1;
  _q.y = _from[1] * _s0 + _ty * _s1;
  _q.z = _from[2] * _s0 + _tz * _s1;
  _q.w = _from[3] * _s0 + _tw * _s1;
  return _q.normalizeSafe(0.000001);
}

// Creates quaternion from four-element array (normalized; identity fallback).
function __poly_quat_from_array(_arr) {
  var _q = new GM3D_Quaternion();

  if (is_array(_arr) && array_length(_arr) == 4 && is_real(_arr[0]) && is_real(_arr[1]) && is_real(_arr[2]) && is_real(_arr[3])) {
    _q.x = _arr[0];
    _q.y = _arr[1];
    _q.z = _arr[2];
    _q.w = _arr[3];
    return _q.normalizeSafe(0.000001);
  }

  return _q;
}

// Converts quaternion to three basis vectors.
function __poly_quat_basis(_q) {
  var _x = _q.x;
  var _y = _q.y;
  var _z = _q.z;
  var _w = _q.w;
  var _xx = _x * _x;
  var _yy = _y * _y;
  var _zz = _z * _z;
  var _xy = _x * _y;
  var _xz = _x * _z;
  var _yz = _y * _z;
  var _wx = _w * _x;
  var _wy = _w * _y;
  var _wz = _w * _z;
  return [
    new GM3D_Vec3(1 - 2 * (_yy + _zz), 2 * (_xy + _wz), 2 * (_xz - _wy)),
    new GM3D_Vec3(2 * (_xy - _wz), 1 - 2 * (_xx + _zz), 2 * (_yz + _wx)),
    new GM3D_Vec3(2 * (_xz + _wy), 2 * (_yz - _wx), 1 - 2 * (_xx + _yy)),
  ];
}

// Converts quaternion to Euler angles.
function __poly_quat_to_euler(_q) {
  var _qx = _q.x;
  var _qy = _q.y;
  var _qz = _q.z;
  var _qw = _q.w;

  if (is_nan(_qx) || is_nan(_qy) || is_nan(_qz) || is_nan(_qw)) return [ 0, 0, 0 ];
  var _len = sqrt(_qx * _qx + _qy * _qy + _qz * _qz + _qw * _qw);

  if (_len > 0.000001) {
    _qx /= _len;
    _qy /= _len;
    _qz /= _len;
    _qw /= _len;
  }

  var _ex = arctan2(2 * (_qw * _qx + _qy * _qz), 1 - 2 * (_qx * _qx + _qy * _qy));
  var _ey = arcsin(clamp(2 * (_qw * _qy - _qz * _qx), -1, 1));
  var _ez = arctan2(2 * (_qw * _qz + _qx * _qy), 1 - 2 * (_qy * _qy + _qz * _qz));
  return [ _ex, _ey, _ez ];
}

// Converts Euler angles to quaternion.
function __poly_euler_to_quat(_ex, _ey, _ez) {
  var _c1 = cos(_ex * 0.5);
  var _c2 = cos(_ey * 0.5);
  var _c3 = cos(_ez * 0.5);
  var _s1 = sin(_ex * 0.5);
  var _s2 = sin(_ey * 0.5);
  var _s3 = sin(_ez * 0.5);
  var _q = new GM3D_Quaternion();
  _q.x = _s1 * _c2 * _c3 - _c1 * _s2 * _s3;
  _q.y = _c1 * _s2 * _c3 + _s1 * _c2 * _s3;
  _q.z = _c1 * _c2 * _s3 - _s1 * _s2 * _c3;
  _q.w = _c1 * _c2 * _c3 + _s1 * _s2 * _s3;
  return _q.normalizeSafe(0.000001);
}

// Returns the quaternion with roll (about the view axis) removed,
// keeping yaw and pitch. No-ops when looking straight up/down.
function __poly_quat_no_roll(_q) {
  if (_q == undefined) return new GM3D_Quaternion();
  var _f = __poly_quat_forward(_q);
  var _fl = sqrt(_f.x * _f.x + _f.y * _f.y + _f.z * _f.z);

  if (_fl < 0.000001) return _q;
  var _fv = new GM3D_Vec3(-_f.x / _fl, -_f.y / _fl, -_f.z / _fl);
  var _w = new GM3D_Vec3(-_fv.x * _fv.y, 1 - _fv.y * _fv.y, -_fv.z * _fv.y);
  var _wl = sqrt(_w.x * _w.x + _w.y * _w.y + _w.z * _w.z);

  if (_wl < 0.001) return _q;
  _w.x /= _wl;
  _w.y /= _wl;
  _w.z /= _wl;
  var _u = __poly_quat_basis(_q)[1];
  var _c = new GM3D_Vec3();
  _c.crossVectors(_w, _u);
  var _roll = arctan2(_c.dot(_fv), _w.dot(_u));
  var _r = GM3D_Quaternion.fromAxisAngle(_fv, -_roll);
  _r.multiply(_q);
  return _r.normalizeSafe(0.000001);
}

// Computes forward direction from a quaternion (unnormalized).
function __poly_quat_forward(_q) {
  return new GM3D_Vec3(
    2.0 * (_q.x * _q.z + _q.w * _q.y),
    2.0 * (_q.y * _q.z - _q.w * _q.x),
    1.0 - 2.0 * (_q.x * _q.x + _q.y * _q.y)
  );
}

// ---------------------------------------------------------------------------
// View cube
// ---------------------------------------------------------------------------

// Computes cube face corner indices for axis.
function __poly_cube_face_idx(_axis, _sign) {
  var _b = (_axis + 1) mod 3;
  var _c = (_axis + 2) mod 3;
  var _corners = [
    [ -1, -1 ],
    [ 1, -1 ],
    [ 1, 1 ],
    [ -1, 1 ],
  ];
  var _out = [];

  for (var _k = 0; _k < 4; _k++) {
    var _sv = [ 0, 0, 0 ];
    _sv[_axis] = _sign;
    _sv[_b] = _corners[_k][0];
    _sv[_c] = _corners[_k][1];
    array_push(_out, (_sv[0] > 0 ? 1 : 0) + (_sv[1] > 0 ? 2 : 0) + (_sv[2] > 0 ? 4 : 0));
  }

  return _out;
}

// Interpolates vectors at near clip plane.
function __poly_clip_lerp(_a, _b, _eps) {
  var _t = (_a.w - _eps) / (_a.w - _b.w);
  return new GM3D_Vec4(_a.x + (_b.x - _a.x) * _t, _a.y + (_b.y - _a.y) * _t, _a.z + (_b.z - _a.z) * _t, _eps);
}

// ---------------------------------------------------------------------------
// 2D picking
// ---------------------------------------------------------------------------

// Computes squared distance point to segment.
function __poly_point_seg_dist2(_px, _py, _ax, _ay, _bx, _by) {
  var _dx = _bx - _ax;
  var _dy = _by - _ay;
  var _len2 = _dx * _dx + _dy * _dy;
  var _t = 0.0;

  if (_len2 > 0.000001) {
    _t = ((_px - _ax) * _dx + (_py - _ay) * _dy) / _len2;
    _t = clamp(_t, 0.0, 1.0);
  }

  var _cx = _ax + _dx * _t;
  var _cy = _ay + _dy * _t;
  var _qx = _px - _cx;
  var _qy = _py - _cy;
  return _qx * _qx + _qy * _qy;
}

// Finds closest squared distance to polyline.
function __poly_point_polyline_dist2(_px, _py, _pts) {
  var _n = array_length(_pts);

  if (_n < 2) return 1000000000;
  var _best = 1000000000;

  for (var _i = 0; _i < _n - 1; _i++) {
    var _a = _pts[_i];
    var _b = _pts[_i + 1];
    var _d = __poly_point_seg_dist2(_px, _py, _a[0], _a[1], _b[0], _b[1]);

    if (_d < _best) _best = _d;
  }

  return _best;
}

// Tests if point lies inside triangle.
function __poly_tri_hit(_px, _py, _ax, _ay, _bx, _by, _cx, _cy) {
  var _d1 = (_px - _bx) * (_ay - _by) - (_ax - _bx) * (_py - _by);
  var _d2 = (_px - _cx) * (_by - _cy) - (_bx - _cx) * (_py - _cy);
  var _d3 = (_px - _ax) * (_cy - _ay) - (_cx - _ax) * (_py - _ay);
  var _neg = _d1 < 0 || _d2 < 0 || _d3 < 0;
  var _pos = _d1 > 0 || _d2 > 0 || _d3 > 0;
  return !(_neg && _pos);
}

// ---------------------------------------------------------------------------
// Snap and sort
// ---------------------------------------------------------------------------

// Snaps value to nearest step increment.
function __poly_snap(_v, _step) {
  if (_step <= 0) return _v;
  return round(_v / _step) * _step;
}

// Returns effective move snap step (grid cell when linked).
function __poly_snap_step(_ed) {
  var _grid_linked = variable_struct_exists(_ed, "snap_to_grid") && _ed.snap_to_grid == true;
  var _grid_step = variable_struct_exists(_ed, "grid_step") && is_real(_ed.grid_step);

  if (_grid_linked && _grid_step) return clamp(_ed.grid_step, 0.1, 8);
  if (variable_struct_exists(_ed, "snap_pos") && is_real(_ed.snap_pos)) return max(0.01, _ed.snap_pos);
  return 0.5;
}

// Sorts array of structs by field (insertion sort, in place).
function __poly_sort_by_field(_arr, _field, _asc) {
  for (var _i = 1, _n = array_length(_arr); _i < _n; _i++) {
    var _item = _arr[_i];
    var _j = _i - 1;

    if (_asc) {
      while (_j >= 0 && _arr[_j][$ _field] > _item[$ _field]) {
        _arr[_j + 1] = _arr[_j];
        _j--;
      }
    } else {
      while (_j >= 0 && _arr[_j][$ _field] < _item[$ _field]) {
        _arr[_j + 1] = _arr[_j];
        _j--;
      }
    }

    _arr[_j + 1] = _item;
  }

  return _arr;
}
