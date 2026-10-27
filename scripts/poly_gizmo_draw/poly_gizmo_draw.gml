// poly_gizmo_draw - transform gizmo handles, sweep, trails, selboxes.

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

// Draws complete transform gizmo with handles.
function __poly_gizmo_draw(_ed, _vp) {
  static _cols = [ c_red, c_lime, c_blue ];
  static _high = [ make_colour_rgb(255, 150, 60), make_colour_rgb(255, 255, 120), make_colour_rgb(110, 200, 255) ];

  if (array_length(_ed.sel) == 0) return;
  if (_ed.show_gizmo != true) return;
  if (!__poly_gizmo_allowed(_ed)) return;
  var _pivot = __poly_gizmo_pivot_draw(_ed);
  var _ps = __poly_world_to_screen(_vp, _pivot);

  if (_ps == undefined) {
    if (_ed.giz.tool == PolygonEditorTool.Translate && _ed.giz.drag != -1) __poly_gizmo_draw_trail_far(_ed, _vp);
    return;
  }

  var _dirs = __poly_gizmo_dirs(_ed);
  var _ws = __poly_gizmo_len(_ed, _vp, _pivot);
  var _fwd = __poly_view_forward_cached(_ed);
  var _look = new GM3D_Vec3(-_fwd.x, -_fwd.y, -_fwd.z);
  __poly_gizmo_draw_translate_quads(_ed, _vp, _pivot, _dirs, _ws, _cols, _high);
  __poly_gizmo_draw_axes(_ed, _vp, _pivot, _ps, _dirs, _ws, _cols, _high);
  __poly_gizmo_draw_viewring(_ed, _vp, _pivot, _look, _ws);
  __poly_gizmo_draw_center(_ed, _ps);

  if (_ed.giz.tool == PolygonEditorTool.Rotate && (_ed.giz.drag == 6 || (_ed.giz.drag >= 0 && _ed.giz.drag <= 2))) {
    __poly_gizmo_draw_rotate_sweep(_ed, _vp, _pivot, _ps, _ws, _high);
  } else if (_ed.giz.tool == PolygonEditorTool.Translate && _ed.giz.drag != -1) {
    __poly_gizmo_draw_trail(_ed, _ps);
  }
}

// ---------------------------------------------------------------------------
// Translate quads and axes
// ---------------------------------------------------------------------------

// Renders planar translation handle quads.
function __poly_gizmo_draw_translate_quads(_ed, _vp, _pivot, _dirs, _ws, _cols, _high) {
  if (_ed.giz.tool == PolygonEditorTool.Translate && !__poly_gizmo_shift_square(_ed)) {
    var _view = __poly_gizmo_cam_view(_vp, _pivot);

    for (var _q = 0; _q < 3; _q++) {
      var _poly = __poly_clip_screen_poly(_vp, __poly_gizmo_quad(_pivot, _dirs, _q, _ws * 0.3, _view));

      if (array_length(_poly) < 3) continue;
      if (_ed.giz.drag != 3 + _q && __poly_screen_poly_area(_poly) < 200) continue;
      var _hot = (_ed.giz.hover == 3 + _q && _ed.giz.drag == -1) || _ed.giz.drag == 3 + _q;
      var _col = _hot ? _high[_q] : _cols[_q];
      var _al = _hot ? 0.55 : 0.3;

      if (_ed.giz.drag != -1 && _ed.giz.drag != 3 + _q) {
        _col = merge_colour(_col, c_white, 0.6);
        _al = 0.15;
      }

      draw_primitive_begin(pr_trianglefan);

      for (var _v = 0, _n = array_length(_poly); _v < _n; _v++) draw_vertex_colour(_poly[_v][0], _poly[_v][1], _col, _al);
      draw_primitive_end();
      draw_set_alpha(_al <= 0.2 ? 0.35 : 0.8);

      for (var _e = 0, _ne = array_length(_poly); _e < _ne; _e++) {
        var _nx = _poly[(_e + 1) mod array_length(_poly)];
        __poly_vp_line(_poly[_e][0], _poly[_e][1], _nx[0], _nx[1], 1, _col);
      }

      draw_set_alpha(1);
    }
  }
}

// Renders translate, scale, or rotate axis handles.
function __poly_gizmo_draw_axes(_ed, _vp, _pivot, _ps, _dirs, _ws, _cols, _high) {
  for (var _a = 0; _a < 3; _a++) {
    var _mine = _ed.giz.drag == _a;
    var _hot = (_ed.giz.hover == _a && _ed.giz.drag == -1) || _mine;
    var _col = _hot ? _high[_a] : _cols[_a];
    var _al = 1;

    if (_ed.giz.drag != -1 && !_mine && _ed.giz.tool != PolygonEditorTool.Rotate) {
      _col = merge_colour(_col, c_white, 0.6);
      _al = 0.2;
    }

    if (_ed.giz.tool == PolygonEditorTool.Translate) {
      var _tip = __poly_world_to_screen(
        _vp,
        new GM3D_Vec3(_pivot.x + _dirs[_a].x * _ws, _pivot.y + _dirs[_a].y * _ws, _pivot.z + _dirs[_a].z * _ws)
      );

      if (_tip == undefined) continue;
      __poly_gizmo_shaft(_ps[0], _ps[1], _tip[0], _tip[1], _col, _al);
      __poly_arrow(_ps[0], _ps[1], _tip[0], _tip[1], _col, _hot ? 12 : 9, _al);
    } else if (_ed.giz.tool == PolygonEditorTool.Scale) {
      var _box = __poly_world_to_screen(
        _vp,
        new GM3D_Vec3(_pivot.x + _dirs[_a].x * _ws, _pivot.y + _dirs[_a].y * _ws, _pivot.z + _dirs[_a].z * _ws)
      );

      if (_box == undefined) continue;
      __poly_gizmo_shaft(_ps[0], _ps[1], _box[0], _box[1], _col, _al);
      draw_set_alpha(_al);
      draw_rectangle_color(_box[0] - 5, _box[1] - 5, _box[0] + 5, _box[1] + 5, _col, _col, _col, _col, false);
      draw_set_color(merge_colour(_col, c_white, 0.5));
      draw_line_width(_box[0] - 5, _box[1] - 5, _box[0] + 5, _box[1] - 5, 1);
      draw_set_color(merge_colour(_col, c_black, 0.3));
      draw_line_width(_box[0] - 5, _box[1] + 5, _box[0] + 5, _box[1] + 5, 1);
      draw_set_color(c_white);
      draw_set_alpha(1);
    } else if (_ed.giz.tool == PolygonEditorTool.Rotate) {
      var _pts = __poly_gizmo_ring_front(_vp, _pivot, _dirs[_a], _ws);
      var _ring_hot = _ed.giz.hover == _a || _ed.giz.drag == _a;
      var _ring_full = _ed.giz.drag == _a;
      var _th = _ring_hot ? 3 : 2;
      draw_set_alpha(_al);

      for (var _p = 0, _n = array_length(_pts); _p < _n - 1; _p++) {
        if (_pts[_p].s == undefined || _pts[_p + 1].s == undefined) continue;
        // Full circle only while dragging this ring; on hover the front
        // arc alone highlights.
        if (!_ring_full && (!_pts[_p].front || !_pts[_p + 1].front)) continue;
        __poly_vp_line(_pts[_p].s[0], _pts[_p].s[1], _pts[_p + 1].s[0], _pts[_p + 1].s[1], _th, _col);
      }

      draw_set_alpha(1);
    }
  }
}

// ---------------------------------------------------------------------------
// View ring and center handles
// ---------------------------------------------------------------------------

// Measures the view-ring disc radius on screen.
function __poly_gizmo_disc_radius(_pts, _ps) {
  var _rr = 0;

  for (var _i = 0, _n = array_length(_pts); _i < _n; _i++) {
    var _dx = _pts[_i][0] - _ps[0];
    var _dy = _pts[_i][1] - _ps[1];
    var _d2 = _dx * _dx + _dy * _dy;

    if (_d2 > _rr) _rr = _d2;
  }

  return sqrt(_rr);
}

// Draws camera-facing rotation ring and trackball disc.
function __poly_gizmo_draw_viewring(_ed, _vp, _pivot, _look, _ws) {
  if (_ed.giz.tool == PolygonEditorTool.Rotate) {
    var _pts = __poly_gizmo_ring_pts(_vp, _pivot, _look, __poly_gizmo_viewring_ws(_ws));
    var _pc = __poly_world_to_screen(_vp, _pivot);

    if (_pc != undefined && array_length(_pts) > 0) {
      // Trackball disc keeps the axis-rings extent (as before the outer
      // ring was enlarged); only the white polyline uses the larger radius.
      var _rr = __poly_gizmo_disc_radius(__poly_gizmo_ring_pts(_vp, _pivot, _look, _ws), _pc);

      if (_rr > 1 && (_ed.giz.hover == 7 || _ed.giz.drag == 7)) {
        draw_set_alpha(0.25);
        draw_circle_colour(_pc[0], _pc[1], _rr, c_black, c_black, false);
        draw_set_alpha(1);
      }
    }

    var _ring_hot = _ed.giz.hover == 6 || _ed.giz.drag == 6;
    var _th = _ring_hot ? 3 : 2;
    var _col = _ring_hot ? c_yellow : c_white;
    var _al = 1;
    var _hh = _ed.giz.hover;
    var _dd = _ed.giz.drag;

    if ((_hh >= 0 && _hh <= 2) || (_dd >= 0 && _dd <= 2) || _hh == 7 || _dd == 7) _al = 0.2;
    draw_set_alpha(_al);

    for (var _v = 0, _n = array_length(_pts); _v < _n - 1; _v++) __poly_vp_line(_pts[_v][0], _pts[_v][1], _pts[_v + 1][0], _pts[_v + 1][1], _th, _col);
    draw_set_alpha(1);
  }
}

// Reads center-handle style (hover color, dim when dragging elsewhere).
function __poly_gizmo_center_style(_ed, _handle) {
  static _dim = make_colour_rgb(200, 200, 200);
  var _hot = _ed.giz.hover == _handle || _ed.giz.drag == _handle;
  var _col = _hot ? c_yellow : c_white;
  var _al = 1;

  if (_ed.giz.drag != -1 && _ed.giz.drag != _handle) {
    _col = _dim;
    _al = 0.2;
  }

  return { col: _col, al: _al, hot: _hot };
}

// Draws shift screen-space move square.
function __poly_gizmo_draw_move_square(_ed, _ps) {
  var _style = __poly_gizmo_center_style(_ed, -2);
  var _half = _style.hot ? 16 : 14;
  draw_set_alpha(_style.al * 0.25);
  draw_rectangle_colour(_ps[0] - _half, _ps[1] - _half, _ps[0] + _half, _ps[1] + _half, _style.col, _style.col, _style.col, _style.col, false);
  draw_set_alpha(_style.al);
  draw_rectangle_colour(_ps[0] - _half, _ps[1] - _half, _ps[0] + _half, _ps[1] + _half, _style.col, _style.col, _style.col, _style.col, true);
  draw_set_alpha(1);
}

// Draws scale uniform handle disc.
function __poly_gizmo_draw_scale_disc(_ed, _ps) {
  var _style = __poly_gizmo_center_style(_ed, -2);
  var _r = _style.hot ? 6 : 4;
  var _rim = merge_colour(_style.col, c_black, 0.35);
  var _seg = 12;
  draw_set_alpha(_style.al);
  draw_primitive_begin(pr_trianglefan);
  draw_vertex_colour(_ps[0] - 1, _ps[1] - 1, c_white, 1);

  for (var _i = 0; _i <= _seg; _i++) {
    var _t = (_i / _seg) * 2 * pi;
    draw_vertex_colour(_ps[0] + cos(_t) * _r, _ps[1] + sin(_t) * _r, _style.col, 1);
  }

  draw_primitive_end();

  for (var _e = 0; _e < _seg; _e++) {
    var _t0 = (_e / _seg) * 2 * pi;
    var _t1 = ((_e + 1) / _seg) * 2 * pi;
    __poly_vp_line(
      _ps[0] + cos(_t0) * _r,
      _ps[1] + sin(_t0) * _r,
      _ps[0] + cos(_t1) * _r,
      _ps[1] + sin(_t1) * _r,
      1,
      _rim
    );
  }

  draw_set_alpha(1);
}

// Draws shift screen-space move square or scale uniform handle.
function __poly_gizmo_draw_center(_ed, _ps) {
  if (_ed.giz.tool == PolygonEditorTool.Translate) {
    if (!__poly_gizmo_shift_square(_ed) && _ed.giz.drag != -2) return;
    __poly_gizmo_draw_move_square(_ed, _ps);
    return;
  }

  if (_ed.giz.tool == PolygonEditorTool.Scale) __poly_gizmo_draw_scale_disc(_ed, _ps);
}

// ---------------------------------------------------------------------------
// Rotate sweep and trails
// ---------------------------------------------------------------------------

// Collects sweep arc screen points from t0 over a signed sweep.
function __poly_sweep_pts(_ed, _vp, _pivot, _ws, _t0, _sweep) {
  var _steps = max(2, ceil(abs(_sweep) / (2 * pi) * 72));
  var _arc = [];
  var _basis = __poly_gizmo_ring_basis(_ed.giz.dir);
  var _u = _basis[0];
  var _v = _basis[1];

  for (var _i = 0; _i <= _steps; _i++) {
    var _t = _t0 + _sweep * (_i / _steps);
    var _pt = __poly_world_to_screen(_vp, __poly_gizmo_ring_point_fast(_pivot, _u, _v, _ws, _t));

    if (_pt != undefined) array_push(_arc, _pt);
  }

  return _arc;
}

// Draws a filled fan from pivot over arc points.
function __poly_sweep_fan(_ps, _arc, _col, _al) {
  draw_primitive_begin(pr_trianglefan);
  draw_vertex_colour(_ps[0], _ps[1], _col, _al);

  for (var _i = 0, _n = array_length(_arc); _i < _n; _i++) draw_vertex_colour(_arc[_i][0], _arc[_i][1], _col, _al);
  draw_primitive_end();
}

// Visualizes current rotation angle sweep arc.
function __poly_gizmo_draw_rotate_sweep(_ed, _vp, _pivot, _ps, _ws, _high) {
  var _sweep = _ed.giz.display_ang;

  if (abs(_sweep) <= 0.01) return;
  var _wsr = _ed.giz.drag == 6 ? __poly_gizmo_viewring_ws(_ws) : _ws;
  var _t0 = _ed.giz.sector_t0;
  var _draw_sweep = clamp(_sweep, -2 * pi, 2 * pi);
  var _arc = __poly_sweep_pts(_ed, _vp, _pivot, _wsr, _t0, _draw_sweep);
  var _basis = __poly_gizmo_ring_basis(_ed.giz.dir);
  var _bu = _basis[0];
  var _bv = _basis[1];

  if (array_length(_arc) >= 2) {
    var _col = _ed.giz.drag == 6 ? c_yellow : _high[_ed.giz.drag];
    var _rim = merge_colour(_col, c_white, 0.4);
    var _laps = floor(abs(_sweep) / (2 * pi));
    var _boost = min(_laps, 4) * 0.12;
    var _fill = merge_colour(c_yellow, c_black, min(0.25 + _laps * 0.1, 0.55));
    var _fill_al = min(0.3 + _boost * 0.5, 0.55);
    __poly_sweep_fan(_ps, _arc, _fill, _fill_al);

    if (_laps >= 1) {
      var _sign = _sweep >= 0 ? 1 : -1;
      var _rem = _sweep - _sign * _laps * 2 * pi;

      if (abs(_rem) > 0.01) {
        var _tri_col = merge_colour(c_yellow, c_black, min(0.25 + _laps * 0.15, 0.7));
        var _tri_al = min(0.3 + _boost, 0.85);
        __poly_sweep_fan(_ps, __poly_sweep_pts(_ed, _vp, _pivot, _wsr, _t0, _rem), _tri_col, _tri_al);
      }
    }

    draw_set_alpha(min(0.8 + _boost, 1.0));

    for (var _e = 0, _ne = array_length(_arc) - 1; _e < _ne - 1; _e++) __poly_vp_line(_arc[_e][0], _arc[_e][1], _arc[_e + 1][0], _arc[_e + 1][1], 2, _col);
    var _start = __poly_world_to_screen(_vp, __poly_gizmo_ring_point_fast(_pivot, _bu, _bv, _wsr, _t0));
    var _current = __poly_world_to_screen(_vp, __poly_gizmo_ring_point_fast(_pivot, _bu, _bv, _wsr, _t0 + _sweep));

    if (_start != undefined) __poly_vp_line(_ps[0], _ps[1], _start[0], _start[1], 1, _rim);
    if (_current != undefined) __poly_vp_line(_ps[0], _ps[1], _current[0], _current[1], 1, _rim);
    draw_set_alpha(1);
  }
}

// Draws line from drag start to current pivot.
function __poly_gizmo_draw_trail(_ed, _ps) {
  _ed.giz.trail_sx = _ps[0];
  _ed.giz.trail_sy = _ps[1];
  draw_set_alpha(0.7);
  __poly_vp_line(_ed.giz.piv_sx, _ed.giz.piv_sy, _ps[0], _ps[1], 2, c_white);
  draw_set_alpha(1);
  draw_circle_color(_ed.giz.piv_sx, _ed.giz.piv_sy, 4, c_yellow, c_yellow, false);
}

// Draws drag trail when the pivot itself is off-screen: line from the drag
// start marker to the last visible pivot position (clamped to the edges).
function __poly_gizmo_draw_trail_far(_ed, _vp) {
  var _sx = _ed.giz.piv_sx;
  var _sy = _ed.giz.piv_sy;

  if (!is_real(_sx) || !is_real(_sy)) return;
  var _ww = 1366;
  var _wh = 768;

  if (_vp != undefined) {
    if (is_real(_vp.winW) && _vp.winW > 0) _ww = _vp.winW;
    if (is_real(_vp.winH) && _vp.winH > 0) _wh = _vp.winH;
  }

  var _ex = _sx;
  var _ey = _sy;

  if (variable_struct_exists(_ed.giz, "trail_sx") && variable_struct_exists(_ed.giz, "trail_sy")
  && is_real(_ed.giz.trail_sx) && is_real(_ed.giz.trail_sy)) {
    _ex = clamp(_ed.giz.trail_sx, -50, _ww + 50);
    _ey = clamp(_ed.giz.trail_sy, -50, _wh + 50);
  }

  draw_set_alpha(0.7);
  __poly_vp_line(_sx, _sy, _ex, _ey, 2, c_white);
  draw_set_alpha(1);
  draw_circle_color(_sx, _sy, 4, c_yellow, c_yellow, false);
}

// ---------------------------------------------------------------------------
// Arrow, shaft, selbox
// ---------------------------------------------------------------------------

// Draws 3D-style arrowhead at axis endpoint.
function __poly_arrow(_x1, _y1, _x2, _y2, _col, _sz, _al) {
  var _dx = _x2 - _x1;
  var _dy = _y2 - _y1;
  var _len = sqrt(_dx * _dx + _dy * _dy);

  if (_len < 0.001) return;
  _dx /= _len;
  _dy /= _len;
  var _tipx = _x2 + _dx * _sz;
  var _tipy = _y2 + _dy * _sz;
  var _lx = _x2 - _dy * _sz * 0.6;
  var _ly = _y2 + _dx * _sz * 0.6;
  var _rx = _x2 + _dy * _sz * 0.6;
  var _ry = _y2 - _dx * _sz * 0.6;
  var _lit = merge_colour(_col, c_white, 0.35);
  var _dark = merge_colour(_col, c_black, 0.25);
  var _hx = _lx;
  var _hy = _ly;
  var _kx = _rx;
  var _ky = _ry;

  if (_ry < _ly) {
    _hx = _rx;
    _hy = _ry;
    _kx = _lx;
    _ky = _ly;
  }

  draw_set_alpha(_al);
  draw_primitive_begin(pr_trianglelist);
  draw_vertex_colour(_tipx, _tipy, _lit, 1);
  draw_vertex_colour(_x2, _y2, _lit, 1);
  draw_vertex_colour(_hx, _hy, _lit, 1);
  draw_vertex_colour(_tipx, _tipy, _dark, 1);
  draw_vertex_colour(_x2, _y2, _dark, 1);
  draw_vertex_colour(_kx, _ky, _dark, 1);
  draw_primitive_end();
  draw_set_alpha(1);
}

// Draws highlighted gizmo axis shaft line.
function __poly_gizmo_shaft(_x1, _y1, _x2, _y2, _col, _al) {
  var _dx = _x2 - _x1;
  var _dy = _y2 - _y1;
  var _len = sqrt(_dx * _dx + _dy * _dy);
  draw_set_alpha(_al);
  __poly_vp_line(_x1, _y1, _x2, _y2, 3, _col);

  if (_len > 0.001) {
    var _nx = -_dy / _len;
    var _ny = _dx / _len;

    if (_ny > 0) {
      _nx = -_nx;
      _ny = -_ny;
    }

    __poly_vp_line(_x1 + _nx, _y1 + _ny, _x2 + _nx, _y2 + _ny, 1, merge_colour(_col, c_white, 0.35));
  }

  draw_set_alpha(1);
}
