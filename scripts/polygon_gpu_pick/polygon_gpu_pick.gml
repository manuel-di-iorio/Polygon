// polygon_gpu_pick — ID-buffer picking (click, rect, icons, cycling).

// ---------------------------------------------------------------------------
// State and ID codec
// ---------------------------------------------------------------------------

// Gets or creates GPU picking state.
function __polygon_gpupick_cfg(_ed) {
  if (_ed == undefined) return undefined;

  if (!variable_struct_exists(_ed, "gpupick") || !is_struct(_ed.gpupick)) {
    _ed.gpupick = {
      surf: undefined,
      sw: 0,
      sh: 0,
      buf: undefined,
      bw: 0,
      bh: 0,
      pixel_surf: undefined,
      pixel_buf: undefined,
      mats: [],
      mats_ok: undefined,
      failed: false,
      failed_msg: "",
      pending: undefined,
      cycle_x: -10000,
      cycle_y: -10000,
      cycle_time: -10000,
      cycle_index: -1,
    };
  }

  if (!variable_struct_exists(_ed.gpupick, "pixel_surf")) _ed.gpupick.pixel_surf = undefined;
  if (!variable_struct_exists(_ed.gpupick, "pixel_buf")) _ed.gpupick.pixel_buf = undefined;
  return _ed.gpupick;
}

// Marks GPU picking as failed.
function __polygon_gpupick_fail(_g, _msg) {
  if (_g != undefined) {
    _g.failed = true;
    _g.failed_msg = _msg;
    _g.pending = undefined;
  }
}

// Encodes pick ID into color.
function __polygon_gpupick_id_encode(_id) {
  var _lo = _id mod 255;
  var _hi = _id div 255;
  var _v = _lo / 255;
  return [ _v, _hi / 255, _v, 1.0 ];
}

// Decodes pick ID from color.
function __polygon_gpupick_id_decode(_b0, _b1, _b2) {
  var _d = abs(_b0 - _b2);

  if (_d > 2) return 0;
  var _lo = (_b0 + _b2) div 2;
  return _b1 * 255 + _lo;
}

// Gets or creates pick ID material.
function __polygon_gpupick_mat(_g, _id, _skinned) {
  if (_g.mats_ok == false) return undefined;

  while (array_length(_g.mats) < _id) {
    array_push(_g.mats, { s: undefined, k: undefined });
  }

  var _entry = _g.mats[_id - 1];
  var _slot = _skinned ? "k" : "s";

  if (_entry[$ _slot] != undefined) return _entry[$ _slot];
  var _mat = new GM3D_Material("polygon_pick_" + string(_id) + (_skinned ? "_k" : "_s"));
  _mat.setShader(GM3D_ERenderPass.Forward, _skinned ? shPolygonEditorIdSkin : shPolygonEditorId);
  _mat.setFloatArray("u_id", __polygon_gpupick_id_encode(_id));
  _entry[$ _slot] = _mat;
  _g.mats_ok = true;
  return _mat;
}

// Ensures pick surface and buffer sizes.
function __polygon_gpupick_surf(_ed, _g, _w, _h) {
  if (_w <= 0 || _h <= 0) return false;

  if (_g.surf != undefined && surface_exists(_g.surf) && _g.sw == _w && _g.sh == _h
  && _g.buf != undefined && _g.bw == _w && _g.bh == _h) {
    return true;
  }

  if (_g.surf != undefined && surface_exists(_g.surf)) __polygon_surf_retire(_ed, _g.surf);
  if (_g.buf != undefined) buffer_delete(_g.buf);
  _g.surf = undefined;
  _g.buf = undefined;
  _g.sw = 0;
  _g.sh = 0;
  _g.bw = 0;
  _g.bh = 0;
  _g.surf = surface_create(_w, _h);

  if (_g.surf == undefined || !surface_exists(_g.surf)) {
    _g.surf = undefined;
    return false;
  }

  _g.buf = buffer_create(_w * _h * 4, buffer_fixed, 1);

  if (_g.buf == undefined) {
    if (surface_exists(_g.surf)) surface_free(_g.surf);
    _g.surf = undefined;
    return false;
  }

  _g.sw = _w;
  _g.sh = _h;
  _g.bw = _w;
  _g.bh = _h;
  return true;
}

// ---------------------------------------------------------------------------
// Paint and render
// ---------------------------------------------------------------------------

// Paints one node with its ID material (mutes the node on any failure).
function __polygon_gpupick_paint_node(_g, _node, _id, _swapped, _muted) {
  var _comps = [];
  __polygon_walk_collect_comps(_node, _comps);

  for (var _c = 0, _n = array_length(_comps); _c < _n; _c++) {
    var _comp = _comps[_c].comp;
    var _mat = __polygon_gpupick_mat(_g, _id, _comps[_c].skinned);
    var _orig = _comp.getMaterial();

    if (_mat == undefined || _orig == undefined) {
      __polygon_walk_mute_node(_node, _muted);
      return false;
    }

    array_push(_swapped, { comp: _comp, orig: _orig });
    _comp.setMaterial(_mat);
  }

  return true;
}

// Paints one subtree node with its ID material (walk visitor with
// inherited mute state); returns the mute state for the children.
function __polygon_gpupick_paint_visit(_cur, _ctx, _inh) {
  var _mute = _inh || __polygon_locked_get(_ctx.ed, _cur);

  if (_mute) {
    __polygon_walk_mute_node(_cur, _ctx.muted);
  } else {
    __polygon_gpupick_paint_node(_ctx.g, _cur, _ctx.id, _ctx.swapped, _ctx.muted);
  }

  return _mute;
}

// Replaces subtree materials with ID materials.
function __polygon_gpupick_paint_tree(_ed, _g, _node, _id, _swapped, _muted, _mute) {
  __polygon_walk_tree_inherit(_node, __polygon_gpupick_paint_visit, { ed: _ed, g: _g, id: _id, swapped: _swapped, muted: _muted }, _mute);
}

// Collects pickable roots (tracked, visible, not chrome).
function __polygon_gpupick_roots(_ed, _all) {
  var _cam = variable_struct_exists(_ed.rt, "cam") ? _ed.rt.cam : undefined;
  var _grid = _ed[$ "grid_node"];
  var _preview = _ed[$ "drag_preview"];
  var _roots = [];

  for (var _i = 0, _n = array_length(_all); _i < _n; _i++) {
    var _node = _all[_i];

    if (_node == undefined || _node.parent != undefined) continue;

    if ((_grid != undefined && __polygon_node_same(_node, _grid)) || (_preview != undefined && __polygon_node_same(_node, _preview))
    || (_cam != undefined && __polygon_node_same(_node, _cam)) || __polygon_is_grid(_ed, _node) || __polygon_is_sky(_node)) {
      continue;
    }

    if (__polygon_hidden_get(_ed, _node)) continue;
    array_push(_roots, _node);
  }

  return _roots;
}

// Renders ID pass and maps nodes.
function __polygon_gpupick_render(_ed, _g, _all, _ignore) {
  if (_ed.renderer == undefined) {
    __polygon_gpupick_fail(_g, "renderer unavailable");
    return undefined;
  }

  var _roots = __polygon_gpupick_roots(_ed, _all);
  var _swapped = [];
  var _muted = [];
  var _nodes = [];
  var _id = 0;

  for (var _r = 0, _n = array_length(_roots); _r < _n; _r++) {
    if (_id >= 65025) {
      __polygon_gpupick_fail(_g, "too many pickables (>65025)");
      __polygon_walk_restore(_swapped, _muted);
      return undefined;
    }

    var _skip = (is_array(_ignore) && __polygon_node_list_has(_ignore, _roots[_r])) || __polygon_locked_get(_ed, _roots[_r]);

    if (_skip) {
      __polygon_gpupick_paint_tree(_ed, _g, _roots[_r], 0, _swapped, _muted, true);
      continue;
    }

    _id++;
    array_push(_nodes, _roots[_r]);
    __polygon_gpupick_paint_tree(_ed, _g, _roots[_r], _id, _swapped, _muted, false);

    if (_g.failed) {
      __polygon_walk_restore(_swapped, _muted);
      return undefined;
    }
  }

  surface_set_target(_g.surf);
  draw_clear(c_black);
  _ed.renderer.render(_ed.rt.scene);
  surface_reset_target();
  __polygon_walk_restore(_swapped, _muted);
  _ed.rt.scene.update(0);
  return { nodes: _nodes, w: _g.sw, h: _g.sh };
}

// Compares nodes by identity (wrappers are unique by id).
// ---------------------------------------------------------------------------
// Readback
// ---------------------------------------------------------------------------

// Prepares pick surface and scene nodes.
function __polygon_gpupick_begin(_ed, _g) {
  var _w = surface_get_width(application_surface);
  var _h = surface_get_height(application_surface);

  if (__polygon_scene_panel_open(_ed) && _ed.scene_w > 0 && _ed.scene_h > 0) {
    _w = _ed.scene_w;
    _h = _ed.scene_h;
  }

  if (!__polygon_gpupick_surf(_ed, _g, _w, _h)) {
    __polygon_gpupick_fail(_g, "pick surface unavailable");
    return undefined;
  }

  return _ed.rt.scene.getNodes();
}

// Renders and reads picked node.
function __polygon_gpupick_probe(_ed, _g, _all, _ignore, _sx, _sy) {
  var _pass = __polygon_gpupick_render(_ed, _g, _all, _ignore);

  if (_pass == undefined) return undefined;
  var _id = __polygon_gpupick_peek_surface_pixel(_g, _sx, _sy);

  if (_id == undefined) return undefined;

  if (_id <= 0 || _id > array_length(_pass.nodes)) {
    return { node: undefined, nodes: _pass.nodes };
  }

  return { node: _pass.nodes[_id - 1], nodes: _pass.nodes };
}

// Ensures the 1x1 staging surface and buffer exist.
function __polygon_gpupick_ensure_pixel(_g) {
  if (_g.pixel_surf == undefined || !surface_exists(_g.pixel_surf)) _g.pixel_surf = surface_create(1, 1);

  if (_g.pixel_surf == undefined || !surface_exists(_g.pixel_surf)) {
    __polygon_gpupick_fail(_g, "single-pixel staging surface unavailable");
    return false;
  }

  if (_g.pixel_buf == undefined || !buffer_exists(_g.pixel_buf)) _g.pixel_buf = buffer_create(4, buffer_fixed, 1);

  if (_g.pixel_buf == undefined || !buffer_exists(_g.pixel_buf)) {
    __polygon_gpupick_fail(_g, "single-pixel staging buffer unavailable");
    return false;
  }

  return true;
}

// Reads one pick pixel through a 1x1 staging surface, avoiding a full-frame
// surface-to-buffer transfer for click picking. Rectangle picking still needs
// the complete buffer via buffer_get_surface.
function __polygon_gpupick_peek_surface_pixel(_g, _sx, _sy) {
  if (_g.surf == undefined || !surface_exists(_g.surf)) {
    __polygon_gpupick_fail(_g, "pick surface lost before pixel readback");
    return undefined;
  }

  if (!__polygon_gpupick_ensure_pixel(_g)) return undefined;
  surface_copy_part(_g.pixel_surf, 0, 0, _g.surf, _sx, _sy, 1, 1);
  buffer_get_surface(_g.pixel_buf, _g.pixel_surf, 0);
  var _b0 = buffer_peek(_g.pixel_buf, 0, buffer_u8);
  var _b1 = buffer_peek(_g.pixel_buf, 1, buffer_u8);
  var _b2 = buffer_peek(_g.pixel_buf, 2, buffer_u8);
  return __polygon_gpupick_id_decode(_b0, _b1, _b2);
}

// Copies pick surface into buffer.
// Converts panel coordinates to surface coordinates.
function __polygon_gpupick_to_surf(_ed, _g, _mx, _my) {
  var _pw = _ed.scene_w;
  var _ph = _ed.scene_h;

  if (!(_pw > 0) || !(_ph > 0)) return [ clamp(floor(_mx), 0, _g.sw - 1), clamp(floor(_my), 0, _g.sh - 1) ];
  var _sx = clamp(floor(_mx * _g.sw / _pw), 0, _g.sw - 1);
  var _sy = clamp(floor(_my * _g.sh / _ph), 0, _g.sh - 1);
  return [ _sx, _sy ];
}

// Reads pick ID at pixel.
function __polygon_gpupick_peek(_g, _sx, _sy) {
  var _off = (_sy * _g.sw + _sx) * 4;
  var _b0 = buffer_peek(_g.buf, _off, buffer_u8);
  var _b1 = buffer_peek(_g.buf, _off + 1, buffer_u8);
  var _b2 = buffer_peek(_g.buf, _off + 2, buffer_u8);
  return __polygon_gpupick_id_decode(_b0, _b1, _b2);
}

// ---------------------------------------------------------------------------
// Click and rect picks
// ---------------------------------------------------------------------------

// Picks node under mouse click.
function __polygon_gpupick_click(_ed, _g, _mx, _my) {
  var _all = __polygon_gpupick_begin(_ed, _g);

  if (_all == undefined) return undefined;
  var _sp = __polygon_gpupick_to_surf(_ed, _g, _mx, _my);

  if (_sp == undefined) return undefined;
  var _res = __polygon_gpupick_probe(_ed, _g, _all, undefined, _sp[0], _sp[1]);

  if (_res == undefined) return undefined;
  return _res.node;
}

// Picks nodes inside screen rectangle.
function __polygon_gpupick_rect(_ed, _g, _r) {
  var _all = __polygon_gpupick_begin(_ed, _g);

  if (_all == undefined) return [];
  var _pass = __polygon_gpupick_render(_ed, _g, _all, undefined);

  if (_pass == undefined) return [];
  buffer_get_surface(_g.buf, _g.surf, 0);

  var _s0 = __polygon_gpupick_to_surf(_ed, _g, _r.x0, _r.y0);
  var _s1 = __polygon_gpupick_to_surf(_ed, _g, _r.x1, _r.y1);

  if (_s0 == undefined || _s1 == undefined) return [];
  var _x0 = min(_s0[0], _s1[0]);
  var _x1 = max(_s0[0], _s1[0]);
  var _y0 = min(_s0[1], _s1[1]);
  var _y1 = max(_s0[1], _s1[1]);
  var _area = (_x1 - _x0 + 1) * (_y1 - _y0 + 1);
  var _step = 1;

  if (_area > 1280 * 720) {
    _step = 3;
  } else if (_area > 640 * 480) {
    _step = 2;
  }

  // Pick IDs are dense and bounded to 1..65025. Use direct membership so
  // deduplicating sampled pixels stays linear in pixels plus unique IDs.
  var _seen = array_create(array_length(_pass.nodes) + 1, false);
  var _out = [];

  for (var _yy = _y0; _yy <= _y1; _yy += _step) {
    for (var _xx = _x0; _xx <= _x1; _xx += _step) {
      var _id = __polygon_gpupick_peek(_g, _xx, _yy);

      if (_id <= 0 || _id > array_length(_pass.nodes)) continue;
      if (_seen[_id]) continue;
      _seen[_id] = true;
      array_push(_out, _pass.nodes[_id - 1]);
    }
  }

  return _out;
}

// Queues deferred click picking request.
function __polygon_gpupick_request_click(_ed, _mx, _my, _shift) {
  var _g = __polygon_gpupick_cfg(_ed);

  if (_g == undefined || _g.failed) return;
  _g.pending = { kind: "click", x: _mx, y: _my, shift: _shift };
}

// Queues deferred rectangle picking request.
function __polygon_gpupick_request_rect(_ed, _r, _shift) {
  var _g = __polygon_gpupick_cfg(_ed);

  if (_g == undefined || _g.failed) return;
  _g.pending = { kind: "rect", x0: _r.x0, y0: _r.y0, x1: _r.x1, y1: _r.y1, shift: _shift };
}

// ---------------------------------------------------------------------------
// Icon queries
// ---------------------------------------------------------------------------

// Checks if a root node is an icon candidate (icon-only, selectable).
// Cheap checks first: registry/hidden/locked before the AABB walk.
function __polygon_gpupick_icon_cand(_ed, _node) {
  if (_node == undefined || _node.parent != undefined) return false;
  if (__polygon_hidden_get(_ed, _node) || __polygon_locked_get(_ed, _node)) return false;
  if (__polygon_is_grid(_ed, _node)) return false;
  if (__polygon_registry_find(_ed, _node) == undefined) return false;
  if (__polygon_node_aabb(_node).valid) return false;
  return true;
}

// Finds icon node near cursor.
function __polygon_gpupick_icon_at(_ed, _vp, _mx, _my) {
  var _best = undefined;
  var _bestd = 16;
  var _nodes = _ed.rt.scene.getNodes();

  for (var _i = 0, _n = array_length(_nodes); _i < _n; _i++) {
    var _node = _nodes[_i];

    if (!__polygon_gpupick_icon_cand(_ed, _node)) continue;
    var _sc = __polygon_world_to_screen(_vp, _node.getWorldPosition());

    if (_sc == undefined) continue;
    var _d = point_distance(_sc[0], _sc[1], _mx, _my);

    if (_d <= _bestd) {
      _bestd = _d;
      _best = _node;
    }
  }

  return _best;
}

// Finds icon nodes inside rectangle.
function __polygon_gpupick_icons_in_rect(_ed, _vp, _r) {
  var _out = [];
  var _nodes = _ed.rt.scene.getNodes();

  for (var _i = 0, _n = array_length(_nodes); _i < _n; _i++) {
    var _node = _nodes[_i];

    if (!__polygon_gpupick_icon_cand(_ed, _node)) continue;
    var _sc = __polygon_world_to_screen(_vp, _node.getWorldPosition());

    if (_sc != undefined && _sc[0] >= _r.x0 && _sc[0] <= _r.x1 && _sc[1] >= _r.y0 && _sc[1] <= _r.y1) array_push(_out, _node);
  }

  return _out;
}

// ---------------------------------------------------------------------------
// Execute
// ---------------------------------------------------------------------------

// Records cycle-pick state for repeated clicks.
function __polygon_gpupick_cycle_mark(_g, _x, _y, _idx) {
  _g.cycle_x = _x;
  _g.cycle_y = _y;
  _g.cycle_time = current_time;
  _g.cycle_index = _idx;
}

// Clears cycle-pick state.
function __polygon_gpupick_cycle_clear(_g) {
  _g.cycle_x = -10000;
  _g.cycle_y = -10000;
  _g.cycle_time = -10000;
  _g.cycle_index = -1;
}

// Selects one node and resets drag/tool state.
function __polygon_gpupick_select(_ed, _node) {
  __polygon_sel_assign(_ed, [ _node ]);
}

// Handles View-tool click (focus only).
function __polygon_gpupick_exec_view(_ed, _g, _vp, _req) {
  var _icon = __polygon_gpupick_icon_at(_ed, _vp, _req.x, _req.y);

  if (_icon != undefined) {
    __polygon_view_focus_node(_ed, _icon);
    return;
  }

  var _all = __polygon_gpupick_begin(_ed, _g);

  if (_all == undefined) return;
  var _sp = __polygon_gpupick_to_surf(_ed, _g, _req.x, _req.y);

  if (_sp == undefined) return;
  var _first = __polygon_gpupick_probe(_ed, _g, _all, undefined, _sp[0], _sp[1]);

  if (_first == undefined) return;
  if (_first.node != undefined) __polygon_view_focus_node(_ed, _first.node);
}

// Handles shift-click (toggle top hit).
function __polygon_gpupick_exec_shift(_ed, _g, _vp, _req) {
  var _top = __polygon_gpupick_icon_at(_ed, _vp, _req.x, _req.y);

  if (_top == undefined) {
    _top = __polygon_gpupick_click(_ed, _g, _req.x, _req.y);

    if (_g.failed) return;
  }

  if (_top != undefined) {
    __polygon_sel_toggle(_ed, _top);
    __polygon_sel_apply_tool(_ed);
  }

  __polygon_gpupick_cycle_mark(_g, _req.x, _req.y, -1);
}

// Handles empty click (clear selection).
function __polygon_gpupick_exec_empty(_ed, _g) {
  __polygon_gpupick_cycle_clear(_g);
  __polygon_sel_clear(_ed);

  if (_ed.giz.tool != PolygonEditorTool.View) _ed.lib_sel = undefined;
}

// Handles click on an already/repeatedly picked node (depth cycling).
function __polygon_gpupick_exec_cycle(_ed, _g, _req, _all, _sp, _first) {
  var _same = point_distance(_g.cycle_x, _g.cycle_y, _req.x, _req.y) <= 10 && current_time - _g.cycle_time <= 700;
  var _on_sel = array_length(_ed.sel) == 1 && __polygon_node_same(_ed.sel[0], _first.node);

  if (!_same && !_on_sel) {
    __polygon_gpupick_select(_ed, _first.node);
    __polygon_gpupick_cycle_mark(_g, _req.x, _req.y, 0);
    return;
  }

  var _stack = [ _first.node ];
  var _ignore = [ _first.node ];

  for (var _w = 0; _w < 8; _w++) {
    var _res = __polygon_gpupick_probe(_ed, _g, _all, _ignore, _sp[0], _sp[1]);

    if (_res == undefined) return;
    if (_res.node == undefined) break;
    array_push(_stack, _res.node);
    array_push(_ignore, _res.node);
  }

  var _base = (_same && _g.cycle_index >= 0) ? _g.cycle_index : (_on_sel ? 0 : -1);
  var _idx = (_base + 1) mod array_length(_stack);
  __polygon_gpupick_select(_ed, _stack[_idx]);
  __polygon_gpupick_cycle_mark(_g, _req.x, _req.y, _idx);
}

// Handles plain click pick.
function __polygon_gpupick_exec_click(_ed, _g, _vp, _req) {
  if (_ed.giz.tool == PolygonEditorTool.View) {
    __polygon_gpupick_exec_view(_ed, _g, _vp, _req);
    return;
  }

  if (_req.shift) {
    __polygon_gpupick_exec_shift(_ed, _g, _vp, _req);
    return;
  }

  var _icon = __polygon_gpupick_icon_at(_ed, _vp, _req.x, _req.y);

  if (_icon != undefined) {
    __polygon_gpupick_select(_ed, _icon);
    __polygon_gpupick_cycle_mark(_g, _req.x, _req.y, -1);
    return;
  }

  var _all = __polygon_gpupick_begin(_ed, _g);

  if (_all == undefined) return;
  var _sp = __polygon_gpupick_to_surf(_ed, _g, _req.x, _req.y);

  if (_sp == undefined) return;
  var _first = __polygon_gpupick_probe(_ed, _g, _all, undefined, _sp[0], _sp[1]);

  if (_first == undefined) return;

  if (_first.node == undefined) {
    __polygon_gpupick_exec_empty(_ed, _g);
    return;
  }

  __polygon_gpupick_exec_cycle(_ed, _g, _req, _all, _sp, _first);
}

// Handles rectangle pick.
function __polygon_gpupick_exec_rect(_ed, _g, _vp, _req) {
  var _box = { x0: _req.x0, y0: _req.y0, x1: _req.x1, y1: _req.y1 };
  var _mesh = __polygon_gpupick_rect(_ed, _g, _box);

  if (_g.failed) return;
  var _hits = __polygon_gpupick_icons_in_rect(_ed, _vp, _box);

  for (var _j = 0, _n = array_length(_mesh); _j < _n; _j++) array_push(_hits, _mesh[_j]);

  if (_req.shift) {
    for (var _i = 0, _nh = array_length(_hits); _i < _nh; _i++) if (!__polygon_sel_has(_ed, _hits[_i])) array_push(_ed.sel, _hits[_i]);
  } else {
    _ed.sel = _hits;
  }

  __polygon_sel_apply_tool(_ed);
}

// Executes pending pick and updates selection.
function __polygon_gpupick_execute(_ed) {
  if (_ed == undefined || _ed.active != true) return;
  var _g = __polygon_gpupick_cfg(_ed);

  if (_g == undefined || _g.pending == undefined || _g.failed) return;

  if (_ed.confirm != undefined || _ed.scene_dlg != undefined) {
    _g.pending = undefined;
    return;
  }

  var _vp = __polygon_viewport_cached(_ed);
  var _req = _g.pending;
  _g.pending = undefined;

  if (_req.kind == "click") {
    __polygon_gpupick_exec_click(_ed, _g, _vp, _req);
  } else if (_req.kind == "rect") {
    __polygon_gpupick_exec_rect(_ed, _g, _vp, _req);
  }
}

// ---------------------------------------------------------------------------
// Cleanup
// ---------------------------------------------------------------------------

// Frees picking surfaces and materials.
function __polygon_gpupick_cleanup(_ed) {
  if (_ed == undefined || !variable_struct_exists(_ed, "gpupick") || !is_struct(_ed.gpupick)) return;
  var _g = _ed.gpupick;

  if (_g.surf != undefined && surface_exists(_g.surf)) surface_free(_g.surf);
  if (_g.buf != undefined) buffer_delete(_g.buf);
  if (variable_struct_exists(_g, "pixel_surf") && _g.pixel_surf != undefined && surface_exists(_g.pixel_surf)) surface_free(_g.pixel_surf);
  if (variable_struct_exists(_g, "pixel_buf") && _g.pixel_buf != undefined && buffer_exists(_g.pixel_buf)) buffer_delete(_g.pixel_buf);

  if (is_array(_g.mats)) {
    for (var _i = 0, _n = array_length(_g.mats); _i < _n; _i++) {
      var _entry = _g.mats[_i];

      if (!is_struct(_entry)) continue;
      if (_entry.s != undefined) _entry.s.destroy();
      if (_entry.k != undefined) _entry.k.destroy();
    }
  }

  _ed.gpupick = undefined;
}
