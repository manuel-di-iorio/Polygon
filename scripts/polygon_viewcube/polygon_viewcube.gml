// polygon_viewcube — orientation widget geometry, picking, drawing.

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

// Resets viewcube screen offset position (top-right of the scene).
function __polygon_cube_home(_ed) {
  _ed.cube_off = [ 48, 48 ];
}

// Builds projected axis frame for the cube center.
// Builds viewcube corners from the projected frame.
function __polygon_cube_corners(_frame) {
  var _corners = [];

  for (var _i = 0; _i < 8; _i++) {
    var _sx = (_i & 1) > 0 ? 1 : -1;
    var _sy = (_i & 2) > 0 ? 1 : -1;
    var _sz = (_i & 4) > 0 ? 1 : -1;
    array_push(_corners, [
      _frame.cx + _frame.R * (_sx * _frame.ex[0][0] + _sy * _frame.ex[1][0] + _sz * _frame.ex[2][0]),
      _frame.cy + _frame.R * (_sx * _frame.ex[0][1] + _sy * _frame.ex[1][1] + _sz * _frame.ex[2][1]),
    ]);
  }

  return _corners;
}

// Face shading table [axis][sign+] -> [top, bottom] grays.
function __polygon_cube_shade(_a, _s) {
  static _table = [
    [ [ 232, 162 ], [ 222, 152 ] ],
    [ [ 245, 245 ], [ 245, 140 ] ],
    [ [ 200, 130 ], [ 190, 120 ] ],
  ];
  var _pair = _table[_a][_s > 0 ? 0 : 1];
  return { top: make_colour_rgb(_pair[0], _pair[0], _pair[0]), bot: make_colour_rgb(_pair[1], _pair[1], _pair[1]) };
}

// Builds viewcube faces from axes and view forward.
function __polygon_cube_faces(_axes, _fwd) {
  var _faces = [];

  for (var _a = 0; _a < 3; _a++) {
    var _axis = _axes[_a];

    for (var _si = 0; _si < 2; _si++) {
      var _s = _si == 0 ? 1 : -1;
      var _shade = __polygon_cube_shade(_a, _s);
      array_push(_faces, {
        a: _a,
        s: _s,
        facing: _axis[0] * _s * _fwd.x + _axis[1] * _s * _fwd.y + _axis[2] * _s * _fwd.z,
        n: new GM3D_Vec3(_axis[0] * _s, _axis[1] * _s, _axis[2] * _s),
        idx: __polygon_cube_face_idx(_a, _s),
        ct: _shade.top,
        cb: _shade.bot,
      });
    }
  }

  return _faces;
}

// Solves ellipse tangent points for a cone (falls back to plain corners).
function __polygon_cone_tangents(_fx, _fy, _ux, _uy, _dx, _dy, _apex_x, _apex_y, _rb, _facing) {
  var _t1 = [ _fx + _ux * _rb, _fy + _uy * _rb ];
  var _t2 = [ _fx - _ux * _rb, _fy - _uy * _rb ];
  var _open = _rb * abs(_facing);

  if (_open < 1.5) return [ _t1, _t2 ];
  var _u0 = (_apex_x - _fx) * _ux + (_apex_y - _fy) * _uy;
  var _v0 = (_apex_x - _fx) * _dx + (_apex_y - _fy) * _dy;
  var _pu = _u0 / (_rb * _rb);
  var _qv = _v0 / (_open * _open);
  var _qa = 1 / (_rb * _rb) + (_pu * _pu) / (_qv * _qv * _open * _open);
  var _qb = (-2 * _pu) / (_qv * _qv * _open * _open);
  var _qc = 1 / (_qv * _qv * _open * _open) - 1;
  var _disc = _qb * _qb - 4 * _qa * _qc;

  if (_disc > 0 && abs(_qv) > 0.000001) {
    var _sq = sqrt(_disc);
    var _r1 = (-_qb + _sq) / (2 * _qa);
    var _r2 = (-_qb - _sq) / (2 * _qa);
    var _v1 = (1 - _pu * _r1) / _qv;
    var _v2 = (1 - _pu * _r2) / _qv;
    _t1 = [ _fx + _ux * _r1 + _dx * _v1, _fy + _uy * _r1 + _dy * _v1 ];
    _t2 = [ _fx + _ux * _r2 + _dx * _v2, _fy + _uy * _r2 + _dy * _v2 ];
  }

  return [ _t1, _t2 ];
}

// Builds one axis cone (disk when facing the camera head-on).
function __polygon_cube_cone(_frame, _axes, _fwd, _axis_i, _sign, _lite, _dark, _len, _rb) {
  var _axis = _axes[_axis_i];
  var _px = _frame.ex[_axis_i][0] * _sign;
  var _py = _frame.ex[_axis_i][1] * _sign;
  var _cone = {
    a: _axis_i,
    s: _sign,
    muted: _sign < 0,
    facing: _axis[0] * _sign * _fwd.x + _axis[1] * _sign * _fwd.y + _axis[2] * _sign * _fwd.z,
    front: false,
    disk: false,
    dx: 0,
    dy: 0,
    n: new GM3D_Vec3(_axis[0] * _sign, _axis[1] * _sign, _axis[2] * _sign),
    lcol: _lite[_axis_i],
    dcol: _dark[_axis_i],
    r: _rb,
  };
  _cone.front = _cone.facing > 0.08;
  var _plen = sqrt(_px * _px + _py * _py);

  if (_plen < 0.25) {
    _cone.disk = true;
    _cone.c = [ _frame.cx + (_frame.R + _len) * _px, _frame.cy + (_frame.R + _len) * _py ];
    return _cone;
  }

  var _dx = _px / _plen;
  var _dy = _py / _plen;
  _cone.dx = _dx;
  _cone.dy = _dy;
  var _apex = [ _frame.cx + _frame.R * 0.9 * _px, _frame.cy + _frame.R * 0.9 * _py ];
  var _fc = [ _frame.cx + (_frame.R + _len) * _px, _frame.cy + (_frame.R + _len) * _py ];
  _cone.apex = _apex;
  _cone.fc = _fc;
  var _ux = -_dy;
  var _uy = _dx;
  var _tang = __polygon_cone_tangents(_fc[0], _fc[1], _ux, _uy, _dx, _dy, _apex[0], _apex[1], _rb, _cone.facing);

  if (_tang[0][1] <= _tang[1][1]) {
    _cone.lc = _tang[0];
    _cone.dc = _tang[1];
  } else {
    _cone.lc = _tang[1];
    _cone.dc = _tang[0];
  }

  return _cone;
}

// Builds viewcube geometry and orientation data.
function __polygon_viewcube(_ed) {
  if (_ed.rt == undefined || _ed.rt.cam == undefined) return undefined;
  if (_ed.gw <= 0 || _ed.gh <= 0) return undefined;
  var _panel_w = _ed.gw;

  if (variable_struct_exists(_ed, "svp") && is_struct(_ed.svp) && _ed.svp.w > 0) _panel_w = _ed.svp.w;
  var _cx = _panel_w - _ed.cube_off[0];
  var _cy = _ed.cube_off[1];
  var _R = 10;
  var _basis = __polygon_quat_basis_cached(_ed, _ed.rt.cam.getLocalRotation());
  var _right = _basis[0];
  var _up = _basis[1];
  var _fwd = __polygon_view_forward_cached(_ed);
  var _axes = [
    [ 1, 0, 0 ],
    [ 0, 1, 0 ],
    [ 0, 0, 1 ],
  ];
  var _ex = [];

  for (var _a = 0; _a < 3; _a++) {
    var _ew = _axes[_a];
    array_push(_ex, [
      _ew[0] * _right.x + _ew[1] * _right.y + _ew[2] * _right.z,
      -(_ew[0] * _up.x + _ew[1] * _up.y + _ew[2] * _up.z),
    ]);
  }

  var _frame = { cx: _cx, cy: _cy, R: _R, ex: _ex };
  static _cone_lite = [
    make_colour_rgb(235, 90, 90),
    make_colour_rgb(110, 220, 110),
    make_colour_rgb(110, 150, 245),
  ];
  static _cone_dark = [
    make_colour_rgb(150, 45, 45),
    make_colour_rgb(45, 140, 45),
    make_colour_rgb(45, 70, 160),
  ];
  var _cone_len = 18;
  var _cone_rb = 6;
  var _cones = [];

  for (var _g = 0; _g < 3; _g++) for (var _qi = 0; _qi < 2; _qi++) array_push(_cones, __polygon_cube_cone(_frame, _axes, _fwd, _g, _qi == 0 ? 1 : -1, _cone_lite, _cone_dark, _cone_len, _cone_rb));
  var _m = _R + _cone_len + 12;
  return {
    cx: _cx,
    cy: _cy,
    faces: __polygon_cube_faces(_axes, _fwd),
    cones: _cones,
    corners: __polygon_cube_corners(_frame),
    box: [ _cx - _m, _cy - _m, _cx + _m, _cy + _m ],
  };
}

// ---------------------------------------------------------------------------
// Picking
// ---------------------------------------------------------------------------

// Grows a triangle corner away from the centroid for fat-finger picking.
function __polygon_grow_pt(_pt, _cx, _cy, _amt) {
  var _dx = _pt[0] - _cx;
  var _dy = _pt[1] - _cy;
  var _len = sqrt(_dx * _dx + _dy * _dy);

  if (_len > 0.001) return [ _pt[0] + (_dx / _len) * _amt, _pt[1] + (_dy / _len) * _amt ];
  return _pt;
}

// Finds axis cone under mouse cursor.
function __polygon_viewcube_cone_at(_vc, _mx, _my) {
  if (_vc == undefined) return undefined;

  for (var _i = 0, _n = array_length(_vc.cones); _i < _n; _i++) {
    var _cone = _vc.cones[_i];

    if (_cone.facing > 0.96) continue;

    if (_cone.disk == true) {
      if (point_distance(_mx, _my, _cone.c[0], _cone.c[1]) <= 10) return [ _cone.a, _cone.s ];
      continue;
    }

    var _ccx = (_cone.apex[0] + _cone.lc[0] + _cone.dc[0]) / 3;
    var _ccy = (_cone.apex[1] + _cone.lc[1] + _cone.dc[1]) / 3;
    var _tip = __polygon_grow_pt(_cone.apex, _ccx, _ccy, 3);
    var _left = __polygon_grow_pt(_cone.lc, _ccx, _ccy, 3);
    var _right = __polygon_grow_pt(_cone.dc, _ccx, _ccy, 3);

    if (__polygon_tri_hit(_mx, _my, _tip[0], _tip[1], _left[0], _left[1], _right[0], _right[1])) return [ _cone.a, _cone.s ];
  }

  return undefined;
}

// Tests if point inside viewcube bounds.
function __polygon_viewcube_box_at(_vc, _mx, _my) {
  if (_vc == undefined) return false;
  var _box = _vc.box;
  return _mx >= _box[0] && _mx <= _box[2] && _my >= _box[1] && _my <= _box[3];
}

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

// Checks if a cone is the hovered one.
function __polygon_cube_hovered(_ed, _cone) {
  return _ed.cube_hover != undefined && _ed.cube_hover[0] == _cone.a && _ed.cube_hover[1] == _cone.s;
}

// Draws the head-on disk variant of an axis cone.
function __polygon_viewcube_disk(_cone, _hov) {
  var _al = _cone.muted ? (_hov ? 0.75 : 0.35) : 1;
  var _lite = _hov ? merge_colour(_cone.lcol, c_white, 0.45) : _cone.lcol;
  var _n = 10;
  var _rim = merge_colour(_lite, _cone.dcol, 0.45);
  draw_primitive_begin(pr_trianglefan);
  draw_vertex_colour(_cone.c[0], _cone.c[1], _lite, _al);

  for (var _k = 0; _k <= _n; _k++) {
    var _t = (_k / _n) * 2 * pi;
    draw_vertex_colour(_cone.c[0] + cos(_t) * 6, _cone.c[1] + sin(_t) * 6, _rim, _al);
  }

  draw_primitive_end();

  for (var _e = 0; _e < _n; _e++) {
    var _t0 = (_e / _n) * 2 * pi;
    var _t1 = ((_e + 1) / _n) * 2 * pi;
    __polygon_vp_line(
      _cone.c[0] + cos(_t0) * 6,
      _cone.c[1] + sin(_t0) * 6,
      _cone.c[0] + cos(_t1) * 6,
      _cone.c[1] + sin(_t1) * 6,
      1,
      _cone.dcol
    );
  }
}

// Draws the cone cap ellipse (only when the opening is wide enough).
function __polygon_viewcube_cap(_cone, _al) {
  if (_cone.r * abs(_cone.facing) < 1.5) return;
  var _ux = -_cone.dy * _cone.r;
  var _uy = _cone.dx * _cone.r;
  var _vx = _cone.dx * _cone.r * abs(_cone.facing);
  var _vy = _cone.dy * _cone.r * abs(_cone.facing);
  var _cap = merge_colour(_cone.dcol, c_black, 0.25);
  var _seg = 8;
  var _arc = _cone.facing > 0 ? 2 * pi : pi;
  draw_primitive_begin(pr_trianglefan);
  draw_vertex_colour(_cone.fc[0], _cone.fc[1], _cap, _al);

  for (var _h = 0; _h <= _seg; _h++) {
    var _ha = (_h / _seg) * _arc;
    draw_vertex_colour(
      _cone.fc[0] + cos(_ha) * _ux + sin(_ha) * _vx,
      _cone.fc[1] + cos(_ha) * _uy + sin(_ha) * _vy,
      _cap,
      _al
    );
  }

  draw_primitive_end();
  var _qx = _cone.fc[0] + _ux;
  var _qy = _cone.fc[1] + _uy;

  for (var _j = 1; _j <= _seg; _j++) {
    var _ja = (_j / _seg) * _arc;
    var _nx = _cone.fc[0] + cos(_ja) * _ux + sin(_ja) * _vx;
    var _ny = _cone.fc[1] + cos(_ja) * _uy + sin(_ja) * _vy;
    __polygon_vp_line(_qx, _qy, _nx, _ny, 1, _cone.dcol);
    _qx = _nx;
    _qy = _ny;
  }
}

// Draws axis cone gizmo.
function __polygon_viewcube_cone(_cone, _hov) {
  var _al = _cone.muted ? (_hov ? 0.75 : 0.35) : 1;
  var _lite = _hov ? merge_colour(_cone.lcol, c_white, 0.45) : _cone.lcol;
  var _dark = _hov ? _cone.lcol : _cone.dcol;

  if (_cone.disk == true) {
    __polygon_viewcube_disk(_cone, _hov);
    return;
  }

  __polygon_viewcube_cap(_cone, _al);

  var _strips = 5;
  draw_primitive_begin(pr_trianglelist);

  for (var _s = 0; _s < _strips; _s++) {
    var _t0 = _s / _strips;
    var _t1 = (_s + 1) / _strips;
    var _c0 = merge_colour(_lite, _dark, _t0);
    var _c1 = merge_colour(_lite, _dark, _t1);
    var _cm = merge_colour(_lite, _dark, (_t0 + _t1) * 0.5);
    var _shade = make_colour_rgb(
      colour_get_red(_cm) * 0.55,
      colour_get_green(_cm) * 0.55,
      colour_get_blue(_cm) * 0.55
    );
    var _p0x = _cone.lc[0] + (_cone.dc[0] - _cone.lc[0]) * _t0;
    var _p0y = _cone.lc[1] + (_cone.dc[1] - _cone.lc[1]) * _t0;
    var _p1x = _cone.lc[0] + (_cone.dc[0] - _cone.lc[0]) * _t1;
    var _p1y = _cone.lc[1] + (_cone.dc[1] - _cone.lc[1]) * _t1;
    draw_vertex_colour(_cone.apex[0], _cone.apex[1], _shade, _al);
    draw_vertex_colour(_p0x, _p0y, _c0, _al);
    draw_vertex_colour(_p1x, _p1y, _c1, _al);
  }

  draw_primitive_end();
  __polygon_vp_line(
    _cone.apex[0],
    _cone.apex[1],
    _cone.lc[0],
    _cone.lc[1],
    2,
    merge_colour(_lite, c_white, 0.5)
  );
  __polygon_vp_line(
    _cone.apex[0],
    _cone.apex[1],
    _cone.dc[0],
    _cone.dc[1],
    1,
    _cone.dcol
  );
}

// Renders interactive viewcube widget.
function __polygon_viewcube_draw(_ed) {
  if (!_ed.imgui.win_cube.open) return;
  var _vc = __polygon_viewcube(_ed);

  if (_vc == undefined) return;
  var _labels = [ "X", "Y", "Z" ];
  draw_set_halign(fa_center);
  draw_set_valign(fa_middle);

  for (var _b = 0, _ncone = array_length(_vc.cones); _b < _ncone; _b++) {
    var _back = _vc.cones[_b];

    if (_back.front || _back.facing > 0.93) continue;
    __polygon_viewcube_cone(_back, __polygon_cube_hovered(_ed, _back));
  }

  var _faces = _vc.faces;
  __polygon_sort_by_field(_faces, "facing", true);

  for (var _k = 0, _nface = array_length(_faces); _k < _nface; _k++) {
    var _face = _faces[_k];

    if (abs(_face.facing) <= 0.02) continue;
    var _pts = [];

    for (var _v = 0; _v < 4; _v++) array_push(_pts, _vc.corners[_face.idx[_v]]);
    draw_primitive_begin(pr_trianglefan);

    for (var _w = 0; _w < 4; _w++) {
      var _kc = (_face.idx[_w] & 2) > 0 ? _face.ct : _face.cb;
      draw_vertex_colour(_pts[_w][0], _pts[_w][1], _kc, 1);
    }

    draw_primitive_end();
  }

  for (var _n = 0, _nfront = array_length(_vc.cones); _n < _nfront; _n++) {
    var _front = _vc.cones[_n];

    if (!_front.front || _front.facing > 0.93) continue;
    __polygon_viewcube_cone(_front, __polygon_cube_hovered(_ed, _front));

    if (!_front.disk) {
      draw_set_color(c_white);
      draw_text(
        _front.fc[0] + _front.dx * 10,
        _front.fc[1] + _front.dy * 10,
        _labels[_front.a]
      );
    }
  }

  draw_set_halign(fa_left);
  draw_set_valign(fa_top);
  draw_set_color(c_white);
}
