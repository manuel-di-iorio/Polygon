// poly_overlay — light/camera/environment viewport overlays.

// ---------------------------------------------------------------------------
// Clipping and projection
// ---------------------------------------------------------------------------

// Draws clipped 3D line segment overlay.
function __poly_overlay_seg(_vp, _a, _b, _wd, _col) {
  var _eps = 0.001;
  var _ca = new GM3D_Vec4(_a.x, _a.y, _a.z, 1.0);
  _ca.applyMatrix4(_vp.viewProj);
  var _cb = new GM3D_Vec4(_b.x, _b.y, _b.z, 1.0);
  _cb.applyMatrix4(_vp.viewProj);
  var _a_in = _ca.w >= _eps;
  var _b_in = _cb.w >= _eps;

  if (!_a_in && !_b_in) return;
  var _pa = _a;
  var _pb = _b;

  if (!_a_in || !_b_in) {
    var _t = (_eps - _ca.w) / (_cb.w - _ca.w);
    var _cross = new GM3D_Vec3(_a.x + (_b.x - _a.x) * _t, _a.y + (_b.y - _a.y) * _t, _a.z + (_b.z - _a.z) * _t);

    if (!_a_in) {
      _pa = _cross;
    } else {
      _pb = _cross;
    }
  }

  var _sa = __poly_world_to_screen(_vp, _pa, true);
  var _sb = __poly_world_to_screen(_vp, _pb, true);

  if (_sa == undefined || _sb == undefined) return;
  var _clipped = __poly_clip_seg(_sa[0], _sa[1], _sb[0], _sb[1], _vp.winW, _vp.winH);

  if (_clipped == undefined) return;
  __poly_vp_line(_clipped[0], _clipped[1], _clipped[2], _clipped[3], _wd, _col);
}

// ---------------------------------------------------------------------------
// Icons
// ---------------------------------------------------------------------------

// Draws cached overlay sprite tinted.
function __poly_overlay_sprite(_sp, _sprname, _tint) {
  static _cache = {};

  if (!variable_struct_exists(_cache, _sprname)) {
    var _idx = asset_get_index(_sprname);

    if (_idx == -1) {
      _cache[$ _sprname] = { spr: -1, w: 0, h: 0, ox: 0, oy: 0 };
    } else {
      _cache[$ _sprname] = { spr: _idx, w: sprite_get_width(_idx), h: sprite_get_height(_idx), ox: sprite_get_xoffset(_idx), oy: sprite_get_yoffset(_idx) };
    }
  }

  var _e = _cache[$ _sprname];

  if (_e.spr == -1) return false;
  var _scale = 2.5;
  draw_sprite_ext(_e.spr, 0, _sp[0] + _scale * (_e.ox - _e.w * 0.5), _sp[1] + _scale * (_e.oy - _e.h * 0.5), _scale, _scale, 0, _tint, 1);
  return true;
}

// Draws object icon or diamond marker.
function __poly_overlay_icon(_sp, _col, _sel, _sprname) {
  var _tint = _sel ? make_colour_rgb(255, 220, 80) : _col;
  var _r = 9;
  var _spr_drawn = false;

  if (_sprname != "") _spr_drawn = __poly_overlay_sprite(_sp, _sprname, _tint);

  if (!_spr_drawn) {
    if (_sel) {
      draw_primitive_begin(pr_trianglefan);
      draw_vertex_colour(_sp[0], _sp[1] - _r, _tint, 0.85);
      draw_vertex_colour(_sp[0] + _r, _sp[1], _tint, 0.85);
      draw_vertex_colour(_sp[0], _sp[1] + _r, _tint, 0.85);
      draw_vertex_colour(_sp[0] - _r, _sp[1], _tint, 0.85);
      draw_primitive_end();
    }

    draw_line_width_color(_sp[0], _sp[1] - _r, _sp[0] + _r, _sp[1], 2, _tint, _tint);
    draw_line_width_color(_sp[0] + _r, _sp[1], _sp[0], _sp[1] + _r, 2, _tint, _tint);
    draw_line_width_color(_sp[0], _sp[1] + _r, _sp[0] - _r, _sp[1], 2, _tint, _tint);
    draw_line_width_color(_sp[0] - _r, _sp[1], _sp[0], _sp[1] - _r, 2, _tint, _tint);
  }
}

// ---------------------------------------------------------------------------
// Shared overlay bits
// ---------------------------------------------------------------------------

// Returns selection tint (gold) or base color.
function __poly_overlay_col(_sel, _base = c_white) {
  return _sel ? make_colour_rgb(255, 220, 80) : _base;
}

// Returns normalized negated world forward (light travel direction).
function __poly_travel_dir(_node) {
  var _fwd = _node.getWorldForward();
  var _len = sqrt(_fwd.x * _fwd.x + _fwd.y * _fwd.y + _fwd.z * _fwd.z);

  if (_len > 0.0001) return new GM3D_Vec3(-_fwd.x / _len, -_fwd.y / _len, -_fwd.z / _len);
  return new GM3D_Vec3(0, 0, -1);
}

// Builds an orthonormal basis around a direction.
function __poly_ortho_basis(_dir) {
  var _up = GM3D_Vec3.up();
  var _u = new GM3D_Vec3();
  _u.crossVectors(_dir, _up);

  if (_u.x * _u.x + _u.y * _u.y + _u.z * _u.z < 0.000001) {
    _u = new GM3D_Vec3(1, 0, 0);
  } else {
    _u.normalizeSafe(0.000001);
  }

  var _v = new GM3D_Vec3();
  _v.crossVectors(_dir, _u);
  return [ _u, _v ];
}

// Builds ring points around a center in the (u, v) plane.
function __poly_basis_ring(_center, _u, _v, _r, _seg = 12) {
  var _pts = [];

  for (var _i = 0; _i <= _seg; _i++) {
    var _t = (_i / _seg) * pi * 2;
    array_push(
      _pts,
      new GM3D_Vec3(
        _center.x + (cos(_t) * _u.x + sin(_t) * _v.x) * _r,
        _center.y + (cos(_t) * _u.y + sin(_t) * _v.y) * _r,
        _center.z + (cos(_t) * _u.z + sin(_t) * _v.z) * _r,
      ),
    );
  }

  return _pts;
}

// Draws a closed ring polyline as overlay segments.
function __poly_overlay_ring(_vp, _pts, _wd, _col) {
  for (var _i = 0, _n = array_length(_pts) - 1; _i < _n; _i++) __poly_overlay_seg(_vp, _pts[_i], _pts[_i + 1], _wd, _col);
}

// Box edges shared by frustum and environment boxes.
function __poly_box_edges() {
  static _edges = [ [ 0, 1 ], [ 1, 3 ], [ 3, 2 ], [ 2, 0 ], [ 4, 5 ], [ 5, 7 ], [ 7, 6 ], [ 6, 4 ], [ 0, 4 ], [ 1, 5 ], [ 2, 6 ], [ 3, 7 ] ];
  return _edges;
}

// Draws box corners as overlay segments.
function __poly_overlay_box(_vp, _corners, _wd, _col) {
  var _edges = __poly_box_edges();

  for (var _e = 0; _e < 12; _e++) __poly_overlay_seg(_vp, _corners[_edges[_e][0]], _corners[_edges[_e][1]], _wd, _col);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

// Draws overlays for lights, cameras, environments.
function __poly_overlay_draw(_ed, _vp) {
  var _pairs = __poly_root_pairs(_ed);
  var _selset = __poly_sel_set(_ed);

  for (var _i = 0, _n = array_length(_pairs); _i < _n; _i++) {
    var _node = _pairs[_i].node;
    var _en = _pairs[_i].en;
    var _kind = is_string(_en.kind) ? _en.kind : undefined;

    if (_kind != "light" && _kind != "camera" && _kind != "environment") continue;
    if (_en.hidden == true) continue;
    var _wp = _node.getWorldPosition();
    var _sp = __poly_world_to_screen(_vp, _wp);
    var _sel = __poly_sel_in(_selset, _node, _en);

    if (_kind == "light") {
      __poly_overlay_light(_vp, _node, _en, _wp, _sp, _sel);
    } else if (_kind == "camera") {
      __poly_overlay_camera(_vp, _node, _en, _wp, _sp, _sel);
    } else {
      __poly_overlay_env(_vp, _en, _wp, _sp, _sel);
    }
  }

  draw_set_alpha(1);
  draw_set_color(c_white);
  draw_set_halign(fa_left);
  draw_set_valign(fa_top);
}

// ---------------------------------------------------------------------------
// Lights
// ---------------------------------------------------------------------------

// Draws directional light arrow gizmo.
function __poly_overlay_dir_light(_vp, _wp, _fwd, _col) {
  var _basis = __poly_ortho_basis(_fwd);
  var _u = _basis[0];
  var _v = _basis[1];
  var _len = 0.7;
  var _rad = 0.1;
  var _rim = [];

  for (var _i = 0; _i <= 12; _i++) {
    var _t = (_i / 12) * pi * 2;
    array_push(
      _rim,
      new GM3D_Vec3(
        _wp.x + (cos(_t) * _u.x + sin(_t) * _v.x) * _rad,
        _wp.y + (cos(_t) * _u.y + sin(_t) * _v.y) * _rad,
        _wp.z + (cos(_t) * _u.z + sin(_t) * _v.z) * _rad,
      ),
    );
  }

  for (var _e = 0; _e < 12; _e++) __poly_overlay_seg(_vp, _rim[_e], _rim[_e + 1], 1, _col);

  for (var _r = 0; _r < 5; _r++) {
    var _a = (_r / 5) * pi * 2;
    var _ox = (cos(_a) * _u.x + sin(_a) * _v.x) * _rad;
    var _oy = (cos(_a) * _u.y + sin(_a) * _v.y) * _rad;
    var _oz = (cos(_a) * _u.z + sin(_a) * _v.z) * _rad;
    __poly_overlay_seg(
      _vp,
      new GM3D_Vec3(_wp.x + _ox, _wp.y + _oy, _wp.z + _oz),
      new GM3D_Vec3(_wp.x + _ox + _fwd.x * _len, _wp.y + _oy + _fwd.y * _len, _wp.z + _oz + _fwd.z * _len),
      1,
      _col
    );
  }
}

// Draws spot light cone gizmo.
function __poly_overlay_spot_cone(_vp, _wp, _fwd, _range, _outer_deg, _col) {
  var _len = max(_range, 0.5);
  var _center = new GM3D_Vec3(_wp.x + _fwd.x * _len, _wp.y + _fwd.y * _len, _wp.z + _fwd.z * _len);
  var _rad = tan(degtorad(clamp(_outer_deg, 1, 89))) * _len;
  var _basis = __poly_ortho_basis(_fwd);
  var _u = _basis[0];
  var _v = _basis[1];
  var _rim = __poly_basis_ring(_center, _u, _v, _rad);
  __poly_overlay_ring(_vp, _rim, 1.5, _col);

  var _spokes = [
    new GM3D_Vec3(_center.x + _u.x * _rad, _center.y + _u.y * _rad, _center.z + _u.z * _rad),
    new GM3D_Vec3(_center.x - _u.x * _rad, _center.y - _u.y * _rad, _center.z - _u.z * _rad),
    new GM3D_Vec3(_center.x + _v.x * _rad, _center.y + _v.y * _rad, _center.z + _v.z * _rad),
    new GM3D_Vec3(_center.x - _v.x * _rad, _center.y - _v.y * _rad, _center.z - _v.z * _rad),
  ];

  for (var _q = 0; _q < 4; _q++) __poly_overlay_seg(_vp, _wp, _spokes[_q], 1.5, _col);
}

// Draws light gizmos and range indicators.
function __poly_overlay_light(_vp, _nd, _en, _wp, _sp, _sel) {
  var _col = __poly_overlay_col(_sel);
  var _d = (_en != undefined && is_struct(_en.data)) ? _en.data : __poly_light_defaults();
  var _fwd = __poly_travel_dir(_nd);

  if (_d.type == "directional") {
    if (_sel) __poly_overlay_dir_light(_vp, _wp, _fwd, _col);
  } else {
    var _ws = __poly_gizmo_world_size(_vp, _wp, 120);
    var _px = (_ws > 0.0001 ? _d.range / _ws : 0) * 120;

    if (_sel && _sp != undefined && _d.range > 0 && _px >= 4) {
      draw_set_alpha(0.7);
      draw_circle(_sp[0], _sp[1], min(_px, 600), true);
      draw_set_alpha(1);
    }

    if (_sel && _d.type == "spot") __poly_overlay_spot_cone(_vp, _wp, _fwd, _d.range, _d.outer, _col);
  }

  if (_sp != undefined) {
    var _spr = _d.type == "directional" ? "sprPolygonEditorIconDirectionalLight" : "sprPolygonEditorIconPointLight";
    __poly_overlay_icon(_sp, _col, _sel, _spr);
  }
}

// ---------------------------------------------------------------------------
// Cameras and environments
// ---------------------------------------------------------------------------

// Draws camera frustum and icon.
function __poly_overlay_camera(_vp, _nd, _en, _wp, _sp, _sel) {
  var _col = __poly_overlay_col(_sel);
  var _d = (_en != undefined && is_struct(_en.data)) ? _en.data : __poly_camera_defaults();

  if (!_sel) {
    if (_sp != undefined) __poly_overlay_icon(_sp, _col, _sel, "sprPolygonEditorIconCamera");
    return;
  }

  var _fwd = __poly_travel_dir(_nd);
  var _right = _nd.getWorldRight();
  var _up = _nd.getWorldUp();
  var _near = max(_d.near, 0.05);
  var _far = max(_d.far, _near + 0.01);
  var _hw0 = 0.5;
  var _hh0 = 0.5;
  var _hw1 = 1.0;
  var _hh1 = 1.0;

  if (_d.projection == "ortho") {
    _hw0 = max(_d.ow, 0.01) * 0.5;
    _hh0 = max(_d.oh, 0.01) * 0.5;
    _hw1 = _hw0;
    _hh1 = _hh0;
  } else {
    var _aspect = _vp.winW / max(_vp.winH, 1);
    var _t = tan(degtorad(clamp(_d.fov, 1, 179)) * 0.5);
    _hh0 = _t * _near;
    _hw0 = _hh0 * _aspect;
    _hh1 = _t * _far;
    _hw1 = _hh1 * _aspect;
  }

  var _cn = new GM3D_Vec3(_wp.x + _fwd.x * _near, _wp.y + _fwd.y * _near, _wp.z + _fwd.z * _near);
  var _cf = new GM3D_Vec3(_wp.x + _fwd.x * _far, _wp.y + _fwd.y * _far, _wp.z + _fwd.z * _far);
  var _corners = [];

  for (var _k = 0; _k < 8; _k++) {
    var _is_far = _k >= 4;
    // Order must match __poly_box_edges (same as the env box):
    // 0=(-,-), 1=(+,-), 2=(-,+), 3=(+,+). The old (_k mod 4 == 3)
    // variant swapped 2/3 and drew bowties (diagonals) instead of rects.
    var _sx = (_k mod 2 == 0) ? -1 : 1;
    var _sy = (_k mod 4 < 2) ? -1 : 1;
    var _base = _is_far ? _cf : _cn;
    var _hx = _is_far ? _hw1 : _hw0;
    var _hy = _is_far ? _hh1 : _hh0;
    array_push(
      _corners,
      new GM3D_Vec3(
        _base.x + _right.x * _hx * _sx + _up.x * _hy * _sy,
        _base.y + _right.y * _hx * _sx + _up.y * _hy * _sy,
        _base.z + _right.z * _hx * _sx + _up.z * _hy * _sy,
      ),
    );
  }

  __poly_overlay_box(_vp, _corners, 1.5, _col);
  __poly_overlay_seg(_vp, _wp, _cn, 1.5, _col);

  if (_sp != undefined) __poly_overlay_icon(_sp, _col, _sel, "sprPolygonEditorIconCamera");
}

// Draws environment volume box and icon.
function __poly_overlay_env(_vp, _en, _wp, _sp, _sel) {
  var _col = __poly_overlay_col(_sel);

  if (_sel) {
    var _d = (_en != undefined && is_struct(_en.data)) ? _en.data : __poly_env_defaults();
    var _hx = _d.size[0] * 0.5;
    var _hy = _d.size[1] * 0.5;
    var _hz = _d.size[2] * 0.5;
    var _corners = [
      new GM3D_Vec3(_wp.x - _hx, _wp.y - _hy, _wp.z - _hz),
      new GM3D_Vec3(_wp.x + _hx, _wp.y - _hy, _wp.z - _hz),
      new GM3D_Vec3(_wp.x - _hx, _wp.y + _hy, _wp.z - _hz),
      new GM3D_Vec3(_wp.x + _hx, _wp.y + _hy, _wp.z - _hz),
      new GM3D_Vec3(_wp.x - _hx, _wp.y - _hy, _wp.z + _hz),
      new GM3D_Vec3(_wp.x + _hx, _wp.y - _hy, _wp.z + _hz),
      new GM3D_Vec3(_wp.x - _hx, _wp.y + _hy, _wp.z + _hz),
      new GM3D_Vec3(_wp.x + _hx, _wp.y + _hy, _wp.z + _hz),
    ];
    draw_set_alpha(0.5);
    __poly_overlay_box(_vp, _corners, 1, _col);
    draw_set_alpha(1);
  }

  if (_sp != undefined) __poly_overlay_icon(_sp, _col, _sel, "sprPolygonEditorIconPointLight");
}
