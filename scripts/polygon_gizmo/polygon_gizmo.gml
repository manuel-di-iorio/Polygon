// polygon_gizmo — pivot, handles, hover, drag (translate/scale/rotate).

// ---------------------------------------------------------------------------
// Pivot, directions, sizes
// ---------------------------------------------------------------------------

// Calculates average world position of selected nodes.
function __polygon_gizmo_pivot(_sel) {
  var _n = array_length(_sel);

  if (_n == 0) return undefined;
  var _cx = 0;
  var _cy = 0;
  var _cz = 0;

  for (var _i = 0; _i < _n; _i++) {
    var _pos = _sel[_i].getWorldPosition();
    _cx += _pos.x;
    _cy += _pos.y;
    _cz += _pos.z;
  }

  return new GM3D_Vec3(_cx / _n, _cy / _n, _cz / _n);
}

// Returns active gizmo axes in world or local orientation.
// In local mode the reference is always the first selected node's local rotation.
function __polygon_gizmo_dirs(_ed) {
  if (_ed.giz.orient == 1 && array_length(_ed.sel) > 0) {
    var _local = _ed.sel[0].getLocalRotation();

    if (_local != undefined) return __polygon_quat_basis_cached(_ed, _local);
  }

  return [ new GM3D_Vec3(1, 0, 0), GM3D_Vec3.up(), GM3D_Vec3.forward() ];
}

// Computes pixel-constant gizmo handle length at pivot.
function __polygon_gizmo_len(_ed, _vp, _pivot) {
  return __polygon_gizmo_world_size(_vp, _pivot, _ed.giz.size);
}

// Estimates world size for a constant pixel size from camera distance.
// Used when screen projection fails (e.g. camera very close to pivot).
function __polygon_gizmo_world_size_dist(_vp, _dist, _pixels) {
  var _h = 768;

  if (is_real(_vp.winH) && _vp.winH > 0) _h = _vp.winH;
  var _fov = pi / 3.0;

  if (is_real(_vp.fovY) && _vp.fovY > 0.001) _fov = _vp.fovY;
  var _ws = _pixels * max(_dist, 0.001) * max(tan(_fov * 0.5), 0.001) * 2.0 / _h;
  return clamp(_ws, 0.0005, 10000);
}

// Measures camera distance to pivot, -1 when unknown.
function __polygon_gizmo_cam_dist(_vp, _pivot) {
  if (_vp == undefined || _vp.camNode == undefined || _pivot == undefined) return -1;
  var _cam = _vp.camNode.getWorldPosition();

  if (_cam == undefined) return -1;
  var _vx = _cam.x - _pivot.x;
  var _vy = _cam.y - _pivot.y;
  var _vz = _cam.z - _pivot.z;
  return sqrt(_vx * _vx + _vy * _vy + _vz * _vz);
}

// Converts desired pixel size to world units.
function __polygon_gizmo_world_size(_vp, _pivot, _pixels) {
  var _dist = __polygon_gizmo_cam_dist(_vp, _pivot);
  var _fallback = _dist > 0 ? __polygon_gizmo_world_size_dist(_vp, _dist, _pixels) : 1;
  var _a = __polygon_world_to_screen(_vp, _pivot);

  if (_a == undefined) return _fallback;
  var _b = __polygon_world_to_screen(
    _vp,
    new GM3D_Vec3(_pivot.x + _vp.camRight.x, _pivot.y + _vp.camRight.y, _pivot.z + _vp.camRight.z)
  );

  if (_b == undefined) return _fallback;
  var _dx = _b[0] - _a[0];
  var _dy = _b[1] - _a[1];
  var _len = sqrt(_dx * _dx + _dy * _dy);

  if (_len < 0.5) return _fallback;
  return _pixels / _len;
}

// Converts world movement delta into node local space.
function __polygon_gizmo_world_delta_to_local(_node, _delta) {
  if (_node.parent == undefined) return _delta.clone();
  var _inv = _node.parent.getWorldMatrix().clone();
  _inv.invert();
  var _a = new GM3D_Vec3(0, 0, 0);
  var _b = _delta.clone();
  var _ta = _inv.transformPoint(_a);
  var _tb = _inv.transformPoint(_b);

  if (_ta != undefined) _a = _ta;
  if (_tb != undefined) _b = _tb;
  _b.sub(_a);
  return _b;
}

// ---------------------------------------------------------------------------
// Rings and quads
// ---------------------------------------------------------------------------

// Builds orthonormal basis (u,v) for a rotation ring axis (computed once per ring).
function __polygon_gizmo_ring_basis(_axis) {
  var _ref = GM3D_Vec3.up();

  if (abs(_axis.dot(_ref)) >= 0.99) _ref = GM3D_Vec3.forward();
  var _u = new GM3D_Vec3();
  _u.crossVectors(_axis, _ref);
  _u.normalizeSafe(0.000001);
  var _v = new GM3D_Vec3();
  _v.crossVectors(_axis, _u);
  _v.normalizeSafe(0.000001);
  return [ _u, _v ];
}

// Computes single point on rotation ring circle from precomputed basis.
function __polygon_gizmo_ring_point_fast(_pivot, _u, _v, _ws, _t) {
  var _ct = cos(_t);
  var _st = sin(_t);
  return new GM3D_Vec3(
    _pivot.x + (_ct * _u.x + _st * _v.x) * _ws,
    _pivot.y + (_ct * _u.y + _st * _v.y) * _ws,
    _pivot.z + (_ct * _u.z + _st * _v.z) * _ws,
  );
}

// Builds world-space circle points for rotation ring (basis hoisted).
function __polygon_gizmo_ring_world_fast(_pivot, _u, _v, _ws) {
  var _seg = 36;
  var _world = array_create(_seg + 1);

  for (var _i = 0; _i <= _seg; _i++) _world[_i] = __polygon_gizmo_ring_point_fast(_pivot, _u, _v, _ws, (_i / _seg) * pi * 2);
  return _world;
}

// Builds world-space circle points for rotation ring.
function __polygon_gizmo_ring_world(_pivot, _axis, _ws) {
  var _basis = __polygon_gizmo_ring_basis(_axis);
  return __polygon_gizmo_ring_world_fast(_pivot, _basis[0], _basis[1], _ws);
}

// Projects rotation ring to screen pixel coordinates.
function __polygon_gizmo_ring_pts(_vp, _pivot, _axis, _ws) {
  var _mapped = __polygon_world_corners_to_screen(_vp, __polygon_gizmo_ring_world(_pivot, _axis, _ws));
  var _pts = [];

  for (var _j = 0, _n = array_length(_mapped); _j < _n; _j++) if (_mapped[_j] != undefined) array_push(_pts, _mapped[_j]);
  return _pts;
}

// Finds front-facing rotation ring segments for display.
function __polygon_gizmo_ring_front(_vp, _pivot, _axis, _ws) {
  var _world = __polygon_gizmo_ring_world(_pivot, _axis, _ws);
  var _cam = _vp.camNode.getWorldPosition();
  var _vx = _cam.x - _pivot.x;
  var _vy = _cam.y - _pivot.y;
  var _vz = _cam.z - _pivot.z;
  var _len = sqrt(_vx * _vx + _vy * _vy + _vz * _vz);
  var _out = [];

  for (var _k = 0, _n = array_length(_world); _k < _n; _k++) {
    var _w = _world[_k];
    var _front = false;

    if (_len > 0.0001) _front = ((_w.x - _pivot.x) * _vx + (_w.y - _pivot.y) * _vy + (_w.z - _pivot.z) * _vz) > 0;
    array_push(_out, { s: __polygon_world_to_screen(_vp, _w), front: _front });
  }

  return _out;
}

// Builds planar translation handle quad from two axes.
function __polygon_gizmo_quad(_pivot, _dirs, _a, _h, _view = undefined) {
  var _b = (_a + 1) mod 3;
  var _c = (_a + 2) mod 3;
  var _sb = 1.0;
  var _sc = 1.0;

  if (_view != undefined) {
    if (_dirs[_b].dot(_view) < 0) _sb = -1.0;
    if (_dirs[_c].dot(_view) < 0) _sc = -1.0;
  }

  var _pb = _pivot.clone();
  _pb.addScaledVector(_dirs[_b], _h * _sb);
  var _pc = _pivot.clone();
  _pc.addScaledVector(_dirs[_c], _h * _sc);
  var _pbc = _pivot.clone();
  _pbc.addScaledVector(_dirs[_b], _h * _sb);
  _pbc.addScaledVector(_dirs[_c], _h * _sc);
  return [ _pivot, _pb, _pbc, _pc ];
}

// Measures squared mouse distance to front ring segments.
function __polygon_ring_front_dist2(_mx, _my, _ring) {
  var _best = 1000000000;

  for (var _i = 0, _n = array_length(_ring) - 1; _i < _n - 1; _i++) {
    var _a = _ring[_i];
    var _b = _ring[_i + 1];

    if (_a.s == undefined || _b.s == undefined || !_a.front || !_b.front) continue;
    var _d = __polygon_point_seg_dist2(_mx, _my, _a.s[0], _a.s[1], _b.s[0], _b.s[1]);

    if (_d < _best) _best = _d;
  }

  return _best;
}

// Computes normalized view direction from pivot to camera.
function __polygon_gizmo_cam_view(_vp, _pivot) {
  if (_vp == undefined || _vp.camNode == undefined || _pivot == undefined) return undefined;
  var _cam = _vp.camNode.getWorldPosition();
  var _view = new GM3D_Vec3(_cam.x - _pivot.x, _cam.y - _pivot.y, _cam.z - _pivot.z);
  _view.normalizeSafe(0.000001);
  return _view;
}

// Measures screen-space polygon area in square pixels.
function __polygon_screen_poly_area(_pts) {
  var _area = 0;
  var _n = array_length(_pts);

  for (var _i = 0; _i < _n; _i++) {
    var _p0 = _pts[_i];
    var _p1 = _pts[(_i + 1) mod _n];
    _area += _p0[0] * _p1[1] - _p1[0] * _p0[1];
  }

  return abs(_area) * 0.5;
}

// Checks shift screen-space move mode (not while flying camera).
function __polygon_gizmo_shift_square(_ed) {
  if (!keyboard_check(vk_shift)) return false;
  if (mouse_check_button(mb_right) || mouse_check_button(mb_middle)) return false;
  if (_ed.cam_fly == true || _ed.cam_orbit == true || _ed.cam_pan == true || _ed.cam_zoom == true) return false;
  return true;
}

// ---------------------------------------------------------------------------
// Hover
// ---------------------------------------------------------------------------

// Per-frame shared gizmo metrics (ws + planar quads), cached on _ed.giz._ring_cache.
// Same inputs reuse the cached screen polys; signatures unchanged.
function __polygon_gizmo_frame_cache(_ed, _vp, _pivot, _dirs, _ws, _view) {
  var _g = _ed.giz;
  var _c = _g[$ "_ring_cache"];
  var _same = is_struct(_c) && _c.ws == _ws && _c.pivot != undefined && _c.pivot.x == _pivot.x && _c.pivot.y == _pivot.y && _c.pivot.z == _pivot.z;
  if (_same) return _c;
  var _quads = [];
  for (var _q = 0; _q < 3; _q++) array_push(_quads, __polygon_clip_screen_poly(_vp, __polygon_gizmo_quad(_pivot, _dirs, _q, _ws * 0.3, _view)));
  _g._ring_cache = { pivot: _pivot.clone(), ws: _ws, quads: _quads, view: _view };
  return _g._ring_cache;
}

// Tests if mouse is inside a translate quad (largest quad wins).
function __polygon_gizmo_hover_quad(_vp, _pivot, _dirs, _ws, _view, _mx, _my) {
  var _best_quad = -1;
  var _best_area = -1;

  for (var _q = 0; _q < 3; _q++) {
    var _poly = __polygon_clip_screen_poly(_vp, __polygon_gizmo_quad(_pivot, _dirs, _q, _ws * 0.3, _view));

    if (array_length(_poly) < 3 || __polygon_screen_poly_area(_poly) < 200) continue;
    var _inside = false;

    for (var _t = 1, _n = array_length(_poly) - 1; _t < _n - 1; _t++) {
      if (__polygon_tri_hit(_mx, _my, _poly[0][0], _poly[0][1], _poly[_t][0], _poly[_t][1], _poly[_t + 1][0], _poly[_t + 1][1])) {
        _inside = true;
        break;
      }
    }

    if (!_inside) continue;
    var _area = __polygon_screen_poly_area(_poly);

    if (_area > _best_area) {
      _best_area = _area;
      _best_quad = _q;
    }
  }

  return _best_quad;
}

// Tests mouse distance to translate quad edges.
function __polygon_gizmo_hover_edge(_vp, _pivot, _dirs, _ws, _view, _mx, _my) {
  var _pad = 36.0;
  var _best_quad = -1;
  var _best_d = 1000000000;

  for (var _q = 0; _q < 3; _q++) {
    var _poly = __polygon_clip_screen_poly(_vp, __polygon_gizmo_quad(_pivot, _dirs, _q, _ws * 0.3, _view));
    var _n = array_length(_poly);

    if (_n < 3 || __polygon_screen_poly_area(_poly) < 200) continue;
    var _dmin = 1000000000;

    for (var _e = 0; _e < _n; _e++) {
      var _pa = _poly[_e];
      var _pb = _poly[(_e + 1) mod _n];
      var _d = __polygon_point_seg_dist2(_mx, _my, _pa[0], _pa[1], _pb[0], _pb[1]);

      if (_d < _dmin) _dmin = _d;
    }

    if (_dmin <= _pad && _dmin < _best_d) {
      _best_d = _dmin;
      _best_quad = _q;
    }
  }

  return _best_quad;
}

// Tests rotate view-ring and disc handles.
function __polygon_gizmo_hover_rotate(_vp, _pivot, _look, _ws, _mx, _my, _ps, _best, _best_d) {
  var _ring = __polygon_gizmo_ring_pts(_vp, _pivot, _look, _ws);
  var _rd = __polygon_point_polyline_dist2(_mx, _my, _ring);

  if (_rd < _best_d) return 6;
  if (_best != -1) return _best;
  var _rr = 0;

  for (var _i = 0, _n = array_length(_ring); _i < _n; _i++) {
    var _dx = _ring[_i][0] - _ps[0];
    var _dy = _ring[_i][1] - _ps[1];
    var _d2 = _dx * _dx + _dy * _dy;

    if (_d2 > _rr) _rr = _d2;
  }

  if (_rr > 1) {
    var _mcx = _mx - _ps[0];
    var _mcy = _my - _ps[1];

    if (_mcx * _mcx + _mcy * _mcy <= _rr) return 7;
  }

  return -1;
}

// Detects which gizmo handle mouse currently hovers.
function __polygon_gizmo_hover(_ed, _vp, _mx, _my) {
  if (array_length(_ed.sel) == 0) return -1;
  if (!__polygon_gizmo_allowed(_ed)) return -1;
  var _pivot = __polygon_gizmo_pivot(_ed.sel);
  var _ps = __polygon_world_to_screen(_vp, _pivot);

  if (_ps == undefined) return -1;
  if (_ed.giz.tool == PolygonEditorTool.Scale) if ((_mx - _ps[0]) * (_mx - _ps[0]) + (_my - _ps[1]) * (_my - _ps[1]) <= 64) return -2;
  var _dirs = __polygon_gizmo_dirs(_ed);
  var _ws = __polygon_gizmo_len(_ed, _vp, _pivot);
  var _view = __polygon_gizmo_cam_view(_vp, _pivot);
  var _fwd = __polygon_view_forward_cached(_ed);
  var _look = new GM3D_Vec3(-_fwd.x, -_fwd.y, -_fwd.z);
  __polygon_gizmo_frame_cache(_ed, _vp, _pivot, _dirs, _ws, _view);

  if (_ed.giz.tool == PolygonEditorTool.Translate) {
    var _shift = __polygon_gizmo_shift_square(_ed);

    if (_shift && abs(_mx - _ps[0]) <= 15 && abs(_my - _ps[1]) <= 15) return -2;

    if (!_shift) {
      var _quad = __polygon_gizmo_hover_quad(_vp, _pivot, _dirs, _ws, _view, _mx, _my);

      if (_quad != -1) return 3 + _quad;
      var _edge = __polygon_gizmo_hover_edge(_vp, _pivot, _dirs, _ws, _view, _mx, _my);

      if (_edge != -1) return 3 + _edge;
    }
  }

  var _best = -1;
  var _best_d = 400.0;

  for (var _a = 0; _a < 3; _a++) {
    var _d = 0;

    if (_ed.giz.tool == PolygonEditorTool.Rotate) {
      _d = __polygon_ring_front_dist2(_mx, _my, __polygon_gizmo_ring_front(_vp, _pivot, _dirs[_a], _ws));
    } else {
      var _tip = __polygon_world_to_screen(
        _vp,
        new GM3D_Vec3(_pivot.x + _dirs[_a].x * _ws, _pivot.y + _dirs[_a].y * _ws, _pivot.z + _dirs[_a].z * _ws)
      );

      if (_tip == undefined) continue;
      _d = __polygon_point_seg_dist2(_mx, _my, _ps[0], _ps[1], _tip[0], _tip[1]);
      _d = min(_d, (_mx - _tip[0]) * (_mx - _tip[0]) + (_my - _tip[1]) * (_my - _tip[1]));
    }

    if (_d < _best_d) {
      _best_d = _d;
      _best = _a;
    }
  }

  if (_ed.giz.tool == PolygonEditorTool.Rotate) return __polygon_gizmo_hover_rotate(_vp, _pivot, _look, _ws, _mx, _my, _ps, _best, _best_d);
  return _best;
}

// ---------------------------------------------------------------------------
// Drag begin
// ---------------------------------------------------------------------------

// Calibrates the rotate-ring grab angle from the mouse position (basis hoisted).
function __polygon_gizmo_calibrate_ring(_ed, _vp, _g, _pivot, _mx, _my) {
  var _ws = __polygon_gizmo_len(_ed, _vp, _pivot);
  var _basis = __polygon_gizmo_ring_basis(_g.dir);
  var _u = _basis[0];
  var _v = _basis[1];
  var _best_d2 = 1000000000;
  var _samples = 144;

  for (var _s = 0; _s < _samples; _s++) {
    var _t = (_s / _samples) * 2 * pi;
    var _pt = __polygon_world_to_screen(_vp, __polygon_gizmo_ring_point_fast(_pivot, _u, _v, _ws, _t));

    if (_pt == undefined) continue;
    var _dx = _pt[0] - _mx;
    var _dy = _pt[1] - _my;
    var _d2 = _dx * _dx + _dy * _dy;

    if (_d2 < _best_d2) {
      _best_d2 = _d2;
      _g.sector_t0 = _t;
    }
  }

  var _step = (2 * pi) / _samples;

  for (var _r = 0; _r < 6; _r++) {
    var _refined = _g.sector_t0;

    for (var _off = -1; _off <= 1; _off++) {
      var _cand_t = _g.sector_t0 + _off * _step;
      var _cand = __polygon_world_to_screen(_vp, __polygon_gizmo_ring_point_fast(_pivot, _u, _v, _ws, _cand_t));

      if (_cand == undefined) continue;
      var _cdx = _cand[0] - _mx;
      var _cdy = _cand[1] - _my;
      var _cd2 = _cdx * _cdx + _cdy * _cdy;

      if (_cd2 < _best_d2) {
        _best_d2 = _cd2;
        _refined = _cand_t;
      }
    }

    _g.sector_t0 = _refined;
    _step /= 3;
  }

  var _tap = 0.01;
  var _ta = __polygon_world_to_screen(_vp, __polygon_gizmo_ring_point_fast(_pivot, _u, _v, _ws, _g.sector_t0 - _tap));
  var _tb = __polygon_world_to_screen(_vp, __polygon_gizmo_ring_point_fast(_pivot, _u, _v, _ws, _g.sector_t0 + _tap));

  if (_ta != undefined && _tb != undefined) {
    var _tx = _tb[0] - _ta[0];
    var _ty = _tb[1] - _ta[1];
    var _tlen = sqrt(_tx * _tx + _ty * _ty);

    if (_tlen > 0.0001) {
      _g.rot_tx = _tx / _tlen;
      _g.rot_ty = _ty / _tlen;
    }
  }
}

// Initializes gizmo drag state and interaction plane.
function __polygon_gizmo_begin(_ed, _vp, _mx, _my) {
  var _g = _ed.giz;
  _g.starts = [];
  _ed.hist_before = __polygon_history_snap(_ed);
  __polygon_cmd_begin(_ed, "gizmo-drag");

  for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) {
    array_push(_g.starts, {
      pos: _ed.sel[_i].getLocalPosition().clone(),
      sca: _ed.sel[_i].getLocalScale().clone(),
      rot: _ed.sel[_i].getLocalRotation().clone(),
    });
  }

  var _pivot = __polygon_gizmo_pivot(_ed.sel);
  _g.pivot = _pivot.clone();
  _g.center = _g.drag < 0;
  _g.planar = _g.drag >= 3 && _g.drag <= 5;
  var _dirs = __polygon_gizmo_dirs(_ed);
  var _ax = 0;

  if (_g.drag == 6) {
    _g.dir = __polygon_view_forward_cached(_ed);
  } else if (_g.drag == 7) {
    _g.dir = __polygon_view_forward_cached(_ed);
    _g.tblen = __polygon_gizmo_len(_ed, _vp, _pivot);
    _g.tb_mx = _mx;
    _g.tb_my = _my;
  } else if (_g.planar) {
    _g.dir = _dirs[_g.drag - 3];
  } else {
    _ax = _g.center ? 0 : _g.drag;
    _g.dir = _dirs[_ax];
  }

  _g.axis_idx = _ax;
  _g.world_len = 0.0001;

  for (var _j = 0, _ns = array_length(_g.starts); _j < _ns; _j++) {
    var _sca = _g.starts[_j].sca;
    var _c = _ax == 0 ? _sca.x : _ax == 1 ? _sca.y : _sca.z;
    _g.world_len = max(_g.world_len, abs(_c));
  }

  if (_g.center && _g.tool == PolygonEditorTool.Translate) {
    var _cf = __polygon_view_forward_cached(_ed);
    _g.plane_n = new GM3D_Vec3(-_cf.x, -_cf.y, -_cf.z);
  } else if (_g.planar) {
    _g.plane_n = _g.dir.clone();
  } else {
    var _cam = _vp.camNode.getWorldPosition();
    var _view = new GM3D_Vec3(_cam.x - _pivot.x, _cam.y - _pivot.y, _cam.z - _pivot.z);
    _view.normalizeSafe(0.000001);
    _g.plane_n = _view.clone();
    _g.plane_n.addScaledVector(_g.dir, -_view.dot(_g.dir));

    if (_g.plane_n.lengthSq() < 0.000001) _g.plane_n.crossVectors(_g.dir, _vp.camUp);
    _g.plane_n.normalizeSafe(0.000001);
  }

  var _ray = __polygon_screen_ray(_vp, _mx, _my);
  _g.start_hit = __polygon_ray_plane(_ray.origin, _ray.dir, _pivot, _g.plane_n);

  if (_g.start_hit == undefined) _g.start_hit = _pivot.clone();
  _g.mx0 = _mx;
  _g.my0 = _my;
  var _ps = __polygon_world_to_screen(_vp, _pivot);
  _ps ??= [ _mx, _my ];
  _g.piv_sx = _ps[0];
  _g.piv_sy = _ps[1];
  _g.rot_mx = _mx;
  _g.rot_my = _my;
  _g.rot_tx = 1;
  _g.rot_ty = 0;
  _g.total_ang = 0;
  _g.display_ang = 0;
  _g.sector_t0 = 0;

  if (_g.tool == PolygonEditorTool.Rotate && _g.drag != 7) __polygon_gizmo_calibrate_ring(_ed, _vp, _g, _pivot, _mx, _my);
}

// ---------------------------------------------------------------------------
// Drag
// ---------------------------------------------------------------------------

// Routes active drag to translate, scale, or rotate.
function __polygon_gizmo_drag(_ed, _vp, _mx, _my) {
  var _g = _ed.giz;
  var _ray = __polygon_screen_ray(_vp, _mx, _my);

  if (_g.tool == PolygonEditorTool.Translate) {
    __polygon_gizmo_drag_translate(_ed, _g, _ray);
  } else if (_g.tool == PolygonEditorTool.Scale) {
    __polygon_gizmo_drag_scale(_ed, _g, _ray, _my);
  } else if (_g.tool == PolygonEditorTool.Rotate) {
    __polygon_gizmo_drag_rotate(_ed, _vp, _g, _mx, _my);
  }
}

// Moves selected nodes along axis or plane.
function __polygon_gizmo_drag_translate(_ed, _g, _ray) {
  var _hit = __polygon_ray_plane(_ray.origin, _ray.dir, _g.pivot, _g.plane_n);

  if (_hit == undefined) return;
  var _delta = new GM3D_Vec3();
  _delta.subVectors(_hit, _g.start_hit);

  if (_g.planar) {
    var _dn = _delta.dot(_g.dir);
    _delta.addScaledVector(_g.dir, -_dn);
  } else if (!_g.center) {
    var _d = _delta.dot(_g.dir);
    _delta = _g.dir.clone();
    _delta.multiplyScalar(_d);
  }

  for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) {
    if (!__polygon_tool_allowed(_ed, _ed.sel[_i], PolygonEditorTool.Translate) || __polygon_hidden_get(_ed, _ed.sel[_i])) continue;
    var _local = __polygon_gizmo_world_delta_to_local(_ed.sel[_i], _delta);
    var _pos = _g.starts[_i].pos.clone();
    _pos.add(_local);
    var _step = _ed.snap_on || keyboard_check(vk_control) ? __polygon_snap_step(_ed) : 0;

    if (_step > 0) {
      if (!variable_struct_exists(_ed, "snap_x") || _ed.snap_x) _pos.x = __polygon_snap(_pos.x, _step);
      if (!variable_struct_exists(_ed, "snap_y") || _ed.snap_y) _pos.y = __polygon_snap(_pos.y, _step);
      if (!variable_struct_exists(_ed, "snap_z") || _ed.snap_z) _pos.z = __polygon_snap(_pos.z, _step);
    }

    _ed.sel[_i].setLocalPosition(_pos);
  }
}

// Scales a start scale by factor along one axis (center scales all).
function __polygon_scale_axis(_sca, _factor, _center, _axis) {
  if (_center || _axis == 0) _sca.x *= _factor;
  if (_center || _axis == 1) _sca.y *= _factor;
  if (_center || _axis == 2) _sca.z *= _factor;
  _sca.x = max(_sca.x, 0.01);
  _sca.y = max(_sca.y, 0.01);
  _sca.z = max(_sca.z, 0.01);
  return _sca;
}

// Scales selected nodes uniformly or along axis.
function __polygon_gizmo_drag_scale(_ed, _g, _ray, _my) {
  var _f = 1.0;

  if (_g.center) {
    _f = 1.0 + (_g.my0 - _my) / _g.size;
  } else {
    var _hit = __polygon_ray_plane(_ray.origin, _ray.dir, _g.pivot, _g.plane_n);

    if (_hit == undefined) return;
    var _dd = new GM3D_Vec3();
    _dd.subVectors(_hit, _g.start_hit);
    _f = 1.0 + _dd.dot(_g.dir) / max(_g.world_len, 0.0001);
  }

  _f = max(_f, 0.01);

  for (var _j = 0, _n = array_length(_ed.sel); _j < _n; _j++) {
    if (!__polygon_tool_allowed(_ed, _ed.sel[_j], PolygonEditorTool.Scale) || __polygon_hidden_get(_ed, _ed.sel[_j])) continue;
    _ed.sel[_j].setLocalScale(__polygon_scale_axis(_g.starts[_j].sca.clone(), _f, _g.center, _g.axis_idx));
  }
}

// Rotates selected nodes via trackball.
function __polygon_gizmo_drag_trackball(_ed, _vp, _g, _mx, _my) {
  var _dx = _mx - _g.tb_mx;
  var _dy = _my - _g.tb_my;
  _g.tb_mx = _mx;
  _g.tb_my = _my;
  var _mag = sqrt(_dx * _dx + _dy * _dy);

  if (_mag <= 0.0001 || _vp.camRight == undefined || _vp.camUp == undefined) return;
  var _axis = new GM3D_Vec3(
    _vp.camRight.x * _dy + _vp.camUp.x * _dx,
    _vp.camRight.y * _dy + _vp.camUp.y * _dx,
    _vp.camRight.z * _dy + _vp.camUp.z * _dx,
  );
  _axis.normalizeSafe(0.000001);
  var _twist = GM3D_Quaternion.fromAxisAngle(_axis, _mag * 0.01);

  for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) {
    if (!__polygon_tool_allowed(_ed, _ed.sel[_i], PolygonEditorTool.Rotate) || __polygon_hidden_get(_ed, _ed.sel[_i])) continue;
    var _rot = _twist.clone();
    _rot.multiply(_ed.sel[_i].getLocalRotation().clone());

    if (is_nan(_rot.x) || is_nan(_rot.y) || is_nan(_rot.z) || is_nan(_rot.w)) continue;
    _ed.sel[_i].setLocalRotation(_rot.normalizeSafe(0.000001));
  }
}

// Resolves the rotate-ring axis in world or local orientation.
// NOTE: drag_ring composes _starts.rot * R(axis) in the local branch, so
// the axis must be given in LOCAL components here. The fixed unit vectors
// double as local axes numerically, which is why local mode deliberately
// uses world-fixed axes while _g.dir (world-space local dirs, used to DRAW
// the rings) would skew the rotation.
function __polygon_gizmo_ring_axis(_ed, _g) {
  var _axis = _g.dir;

  if (_g.drag != 6 && _ed.giz.orient == 1) {
    var _ax = _g.center ? 1 : _g.axis_idx;

    if (_ax == 2) {
      _axis = GM3D_Vec3.forward();
    } else if (_ax == 1) {
      _axis = GM3D_Vec3.up();
    } else {
      _axis = new GM3D_Vec3(1, 0, 0);
    }
  }

  return _axis;
}

// Rotates selected nodes via ring.
function __polygon_gizmo_drag_ring(_ed, _g, _mx, _my) {
  var _dx = _mx - _g.rot_mx;
  var _dy = _my - _g.rot_my;
  _g.rot_mx = _mx;
  _g.rot_my = _my;
  var _step = (_dx * _g.rot_tx + _dy * _g.rot_ty) * 0.01;
  _g.total_ang += _step;
  var _deg = radtodeg(_g.total_ang);
  var _snap = _ed.snap_on || keyboard_check(vk_control) ? _ed.snap_rot : 0;

  if (_snap > 0) _deg = __polygon_snap(_deg, _snap);
  _g.display_ang = degtorad(_deg);
  var _axis = __polygon_gizmo_ring_axis(_ed, _g);

  for (var _k = 0, _n = array_length(_ed.sel); _k < _n; _k++) {
    if (!__polygon_tool_allowed(_ed, _ed.sel[_k], PolygonEditorTool.Rotate) || __polygon_hidden_get(_ed, _ed.sel[_k])) continue;
    var _rot = GM3D_Quaternion.fromAxisAngle(_axis, degtorad(_deg));

    if (_ed.giz.orient == 1) {
      var _local = _g.starts[_k].rot.clone();
      _local.multiply(_rot);
      _rot = _local;
    } else {
      _rot.multiply(_g.starts[_k].rot);
    }

    _ed.sel[_k].setLocalRotation(_rot.normalizeSafe(0.000001));
  }
}

// Rotates selected nodes via trackball or ring.
function __polygon_gizmo_drag_rotate(_ed, _vp, _g, _mx, _my) {
  if (_g.drag == 7 && variable_struct_exists(_g, "tb_mx") && variable_struct_exists(_g, "tb_my")) {
    __polygon_gizmo_drag_trackball(_ed, _vp, _g, _mx, _my);
  } else {
    __polygon_gizmo_drag_ring(_ed, _g, _mx, _my);
  }
}
