// poly_viewport - matrices, projection, rays, bounding boxes.

// ---------------------------------------------------------------------------
// Matrices and projection
// ---------------------------------------------------------------------------

// Builds viewport matrices and camera data.
function __poly_viewport(_ed) {
  var _cam = _ed.rt.cam;
  var _comp = _cam.getCameraComponent();

  var _fov = pi / 3.0;
  var _near = 0.1;
  var _far = 10000.0;
  var _w = display_get_gui_width();
  var _h = display_get_gui_height();

  if (_w <= 0 || _h <= 0) {
    _w = 1366.0;
    _h = 768.0;
  }

  var _ox = 0;
  var _oy = 0;

  if (__poly_scene_panel_open(_ed) && variable_struct_exists(_ed, "svp") && is_struct(_ed.svp) && _ed.svp.w > 0 && _ed.svp.h > 0) {
    _w = _ed.svp.w;
    _h = _ed.svp.h;
    _ox = _ed.svp.x;
    _oy = _ed.svp.y;
  }

  if (_comp != undefined) {
    _fov = _comp.getFovY();
    _near = _comp.getNear();
    _far = _comp.getFar();
  }

  var _aspect = _w / _h;

  var _world = _cam.getWorldMatrix();
  var _view = _world.clone();
  _view.invert();

  var _proj = GM3D_Matrix4.perspective(_fov, _aspect, _near, _far);
  var _vp = _proj.clone();
  _vp.multiply(_view);
  var _inv = _vp.clone();
  _inv.invert();

  return {
    camNode: _cam,
    ndc_yup: _ed.ndc_yup,
    winW: _w,
    winH: _h,
    offX: _ox,
    offY: _oy,
    fovY: _fov,
    near: _near,
    far: _far,
    view: _view,
    proj: _proj,
    viewProj: _vp,
    inv: _inv,
    camForward: _cam.getWorldForward(),
    camRight: _cam.getWorldRight(),
    camUp: _cam.getWorldUp(),
  };
}

// Converts NDC coordinates to screen pixels.
function __poly_ndc_to_screen(_vp, _nx, _ny) {
  var _sx = (_nx * 0.5 + 0.5) * _vp.winW;
  var _sy = 0;

  if (_vp.ndc_yup) {
    _sy = (1.0 - (_ny * 0.5 + 0.5)) * _vp.winH;
  } else {
    _sy = (_ny * 0.5 + 0.5) * _vp.winH;
  }

  return [ _sx, _sy ];
}

// Converts world position to screen coordinates.
// _wide skips the +/-2 NDC window cull (for Cohen-Sutherland-clipped
// segments whose endpoints project off-screen but cross the viewport).
function __poly_world_to_screen(_vp, _p, _wide = false) {
  var _v = new GM3D_Vec4(_p.x, _p.y, _p.z, 1.0);
  _v.applyMatrix4(_vp.viewProj);

  if (_v.w <= 0.0001) return undefined;
  var _nx = _v.x / _v.w;
  var _ny = _v.y / _v.w;

  if (!_wide && (_nx < -2.0 || _nx > 2.0 || _ny < -2.0 || _ny > 2.0)) return undefined;
  return __poly_ndc_to_screen(_vp, _nx, _ny);
}

// Unprojects NDC coordinates to world space.
function __poly_unproject(_inv, _nx, _ny, _nz) {
  var _v = new GM3D_Vec4(_nx, _ny, _nz, 1.0);
  _v.applyMatrix4(_inv);

  if (abs(_v.w) < 0.0001) _v.w = 1.0;
  return new GM3D_Vec3(_v.x / _v.w, _v.y / _v.w, _v.z / _v.w);
}

// Creates world ray from screen pixel.
function __poly_screen_ray(_vp, _mx, _my) {
  var _nx = (2.0 * _mx) / _vp.winW - 1.0;
  var _ny = 0;

  if (_vp.ndc_yup) {
    _ny = 1.0 - (2.0 * _my) / _vp.winH;
  } else {
    _ny = (2.0 * _my) / _vp.winH - 1.0;
  }

  var _near = __poly_unproject(_vp.inv, _nx, _ny, -1.0);
  var _far = __poly_unproject(_vp.inv, _nx, _ny, 1.0);

  var _dir = new GM3D_Vec3();
  _dir.subVectors(_far, _near);
  _dir.normalizeSafe(0.000001);

  return { origin: _near, dir: _dir };
}

// Clips poly and projects to screen.
function __poly_clip_screen_poly(_vp, _corners) {
  var _eps = 0.001;
  var _clip = [];

  for (var _i = 0, _n = array_length(_corners); _i < _n; _i++) {
    var _v = new GM3D_Vec4(_corners[_i].x, _corners[_i].y, _corners[_i].z, 1.0);
    _v.applyMatrix4(_vp.viewProj);
    array_push(_clip, _v);
  }

  var _any = false;

  for (var _a = 0, _na = array_length(_clip); _a < _na; _a++) {
    if (_clip[_a].w >= _eps) {
      _any = true;
      break;
    }
  }

  if (!_any) return [];
  var _out = [];

  for (var _e = 0, _ne = array_length(_clip); _e < _ne; _e++) {
    var _cur = _clip[_e];
    var _nxt = _clip[(_e + 1) mod _ne];
    var _cur_in = _cur.w >= _eps;
    var _nxt_in = _nxt.w >= _eps;

    if (_nxt_in) {
      if (!_cur_in) array_push(_out, __poly_clip_lerp(_cur, _nxt, _eps));
      array_push(_out, _nxt);
    } else if (_cur_in) {
      array_push(_out, __poly_clip_lerp(_cur, _nxt, _eps));
    }
  }

  var _sp = [];

  for (var _s = 0, _ns = array_length(_out); _s < _ns; _s++) {
    var _p = _out[_s];
    array_push(_sp, __poly_ndc_to_screen(_vp, _p.x / _p.w, _p.y / _p.w));
  }

  return _sp;
}

// Projects corner array to screen positions.
function __poly_world_corners_to_screen(_vp, _corners) {
  var _out = [];

  for (var _i = 0, _n = array_length(_corners); _i < _n; _i++) array_push(_out, __poly_world_to_screen(_vp, _corners[_i]));
  return _out;
}

// ---------------------------------------------------------------------------
// Ray tests
// ---------------------------------------------------------------------------

// Intersects ray with plane.
function __poly_ray_plane(_origin, _dir, _point, _normal) {
  var _den = _dir.dot(_normal);

  if (abs(_den) < 0.000001) return undefined;
  var _t = (_point.dot(_normal) - _origin.dot(_normal)) / _den;

  if (_t < 0.0) return undefined;
  var _hit = new GM3D_Vec3();
  _hit.copy(_dir);
  _hit.multiplyScalar(_t);
  _hit.add(_origin);
  return _hit;
}

// ---------------------------------------------------------------------------
// Bounding boxes and draw helpers
// ---------------------------------------------------------------------------

// Collects mesh bounding boxes of one node.
function __poly_node_mesh_boxes(_node) {
  var _boxes = [];
  var _comps = _node.getMeshComponents();

  for (var _i = 0, _n = array_length(_comps); _i < _n; _i++) {
    var _mesh = _comps[_i].getMesh();

    if (_mesh == undefined) continue;
    var _box = _mesh.getBoundingBox();

    if (_box == undefined || _box.min == undefined || _box.max == undefined) continue;
    array_push(_boxes, { min: _box.min, max: _box.max });
  }

  var _skin = _node.getSkinnedMeshComponent();

  if (_skin != undefined) {
    var _skin_mesh = _skin.getMesh();

    if (_skin_mesh != undefined) {
      var _skin_box = _skin_mesh.getBoundingBox();

      if (_skin_box != undefined && _skin_box.min != undefined && _skin_box.max != undefined) {
        array_push(_boxes, { min: _skin_box.min, max: _skin_box.max });
      }
    }
  }

  return _boxes;
}

// Expands min/max with one world point.
function __poly_aabb_grow(_mm, _p) {
  if (_mm.min == undefined) {
    _mm.min = _p.clone();
    _mm.max = _p.clone();
    return;
  }

  _mm.min.x = min(_mm.min.x, _p.x);
  _mm.min.y = min(_mm.min.y, _p.y);
  _mm.min.z = min(_mm.min.z, _p.z);
  _mm.max.x = max(_mm.max.x, _p.x);
  _mm.max.y = max(_mm.max.y, _p.y);
  _mm.max.z = max(_mm.max.z, _p.z);
}

// Computes world bounding box for subtree.
function __poly_node_aabb(_node) {
  var _mm = { min: undefined, max: undefined };
  var _stack = [ _node ];

  while (array_length(_stack) > 0) {
    var _cur = array_pop(_stack);
    var _wm = _cur.getWorldMatrix().clone();
    var _boxes = __poly_node_mesh_boxes(_cur);

    for (var _i = 0, _nb = array_length(_boxes); _i < _nb; _i++) {
      var _bmin = _boxes[_i].min;
      var _bmax = _boxes[_i].max;

      if (_bmin == undefined || _bmax == undefined) continue;

      for (var _ix = 0; _ix < 2; _ix++) {
        for (var _iy = 0; _iy < 2; _iy++) {
          for (var _iz = 0; _iz < 2; _iz++) {
            var _p = new GM3D_Vec3(
              _ix == 0 ? _bmin.x : _bmax.x,
              _iy == 0 ? _bmin.y : _bmax.y,
              _iz == 0 ? _bmin.z : _bmax.z,
            );
            var _tw = _wm.transformPoint(_p);

            if (_tw != undefined) _p = _tw;
            __poly_aabb_grow(_mm, _p);
          }
        }
      }
    }

    var _kids = _cur.getChildren();

    for (var _k = 0, _nk = array_length(_kids); _k < _nk; _k++) array_push(_stack, _kids[_k]);
  }

  if (_mm.min == undefined) {
    return { min: undefined, max: undefined, valid: false };
  }

  return { min: _mm.min, max: _mm.max, valid: true };
}

// Draws 2D line with width.
function __poly_vp_line(_x1, _y1, _x2, _y2, _wd, _col) {
  draw_line_width_color(_x1, _y1, _x2, _y2, _wd, _col, _col);
}

// ---------------------------------------------------------------------------
// Viewport cache (per-frame)
// ---------------------------------------------------------------------------

// Returns the cached viewport when inputs are unchanged, else rebuilds.
// Compares raw numbers (never stringified: GML string() rounds to 2
// decimals, which blinded the old key to sub-0.01 camera motion and
// skipped rebuilds during smooth navigation).
// Same signature contract as __poly_viewport (takes _ed, returns vp).
function __poly_viewport_cached(_ed) {
  var _cam = _ed.rt.cam;
  var _pos = _cam.getLocalPosition();
  var _rot = _cam.getLocalRotation();
  var _comp = _cam.getCameraComponent();
  var _fov = _comp != undefined ? _comp.getFovY() : pi / 3.0;
  var _nr = _comp != undefined ? _comp.getNear() : 0.1;
  var _fr = _comp != undefined ? _comp.getFar() : 10000.0;
  var _gw = display_get_gui_width();
  var _gh = display_get_gui_height();
  var _sv = (__poly_scene_panel_open(_ed) && variable_struct_exists(_ed, "svp") && is_struct(_ed.svp) && _ed.svp.w > 0 && _ed.svp.h > 0) ? _ed.svp : undefined;
  var _k = (variable_struct_exists(_ed, "vp_pose") && is_struct(_ed.vp_pose)) ? _ed.vp_pose : undefined;

  if (is_struct(_ed.vp) && _k != undefined
    && _k.cpx == _pos.x && _k.cpy == _pos.y && _k.cpz == _pos.z
    && _k.crx == _rot.x && _k.cry == _rot.y && _k.crz == _rot.z && _k.crw == _rot.w
    && _k.fov == _fov && _k.nr == _nr && _k.fr == _fr
    && _k.gw == _gw && _k.gh == _gh
    && _k.sx == (_sv != undefined ? _sv.x : -1) && _k.sy == (_sv != undefined ? _sv.y : -1)
    && _k.sw == (_sv != undefined ? _sv.w : -1) && _k.sh == (_sv != undefined ? _sv.h : -1)
  && _k.yup == _ed.ndc_yup) {
    return _ed.vp;
  }

  _ed.vp = __poly_viewport(_ed);
  _ed.vp_pose = {
    cpx: _pos.x, cpy: _pos.y, cpz: _pos.z,
    crx: _rot.x, cry: _rot.y, crz: _rot.z, crw: _rot.w,
    fov: _fov, nr: _nr, fr: _fr, gw: _gw, gh: _gh,
    sx: (_sv != undefined ? _sv.x : -1), sy: (_sv != undefined ? _sv.y : -1),
    sw: (_sv != undefined ? _sv.w : -1), sh: (_sv != undefined ? _sv.h : -1),
    yup: _ed.ndc_yup,
  };
  return _ed.vp;
}

// ---------------------------------------------------------------------------
// Camera pose key (shared by viewport + outline cheap snapshots)
// ---------------------------------------------------------------------------

// Reads camera pose as plain numbers (viewcam ?? rt.cam). Undefined when
// no camera/pose is available, forcing the exact path in callers.
function __poly_cam_pose_key(_ed) {
  if (!is_struct(_ed) || !is_struct(_ed.rt)) return undefined;
  var _cam = undefined;

  if (variable_struct_exists(_ed, "viewcam") && _ed.viewcam != undefined) {
    _cam = _ed.viewcam;
  } else if (variable_struct_exists(_ed.rt, "cam")) {
    _cam = _ed.rt.cam;
  }

  if (_cam == undefined) return undefined;
  var _cp = _cam.getLocalPosition();
  var _cr = _cam.getLocalRotation();

  if (_cp == undefined || _cr == undefined) return undefined;
  return {
    cpx: _cp.x, cpy: _cp.y, cpz: _cp.z,
    crx: _cr.x, cry: _cr.y, crz: _cr.z, crw: _cr.w,
  };
}

// Compares two camera pose keys.
function __poly_pose_same(_a, _b) {
  if (!is_struct(_a) || !is_struct(_b)) return false;
  return _a.cpx == _b.cpx && _a.cpy == _b.cpy && _a.cpz == _b.cpz
    && _a.crx == _b.crx && _a.cry == _b.cry && _a.crz == _b.crz && _a.crw == _b.crw;
}

// ---------------------------------------------------------------------------
// Screen-space segment clipping (Cohen-Sutherland)
// ---------------------------------------------------------------------------

// Computes Cohen-Sutherland outcode for point.
function __poly_outcode(_x, _y, _w, _h) {
  var _code = 0;

  if (_x < 0) {
    _code |= 1;
  } else if (_x > _w) {
    _code |= 2;
  }

  if (_y < 0) {
    _code |= 4;
  } else if (_y > _h) {
    _code |= 8;
  }

  return _code;
}

// Clips 2D segment to window rectangle.
function __poly_clip_seg(_x0, _y0, _x1, _y1, _w, _h) {
  var _c0 = __poly_outcode(_x0, _y0, _w, _h);
  var _c1 = __poly_outcode(_x1, _y1, _w, _h);
  var _guard = 0;

  while (_guard < 8) {
    _guard++;

    if ((_c0 | _c1) == 0) return [ _x0, _y0, _x1, _y1 ];
    if ((_c0 & _c1) != 0) return undefined;
    var _cc = _c0 == 0 ? _c1 : _c0;
    var _cx = _x0;
    var _cy = _y0;

    if ((_cc & 1) != 0) {
      _cy = _y0 + (_y1 - _y0) * (0 - _x0) / (_x1 - _x0);
      _cx = 0;
    } else if ((_cc & 2) != 0) {
      _cy = _y0 + (_y1 - _y0) * (_w - _x0) / (_x1 - _x0);
      _cx = _w;
    } else if ((_cc & 4) != 0) {
      _cx = _x0 + (_x1 - _x0) * (0 - _y0) / (_y1 - _y0);
      _cy = 0;
    } else {
      _cx = _x0 + (_x1 - _x0) * (_h - _y0) / (_y1 - _y0);
      _cy = _h;
    }

    if (_cc == _c0) {
      _x0 = _cx;
      _y0 = _cy;
      _c0 = __poly_outcode(_x0, _y0, _w, _h);
    } else {
      _x1 = _cx;
      _y1 = _cy;
      _c1 = __poly_outcode(_x1, _y1, _w, _h);
    }
  }

  return [ _x0, _y0, _x1, _y1 ];
}
