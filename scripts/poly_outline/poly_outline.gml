// poly_outline — selection outline mask capture and glow composite.

// ---------------------------------------------------------------------------
// State and materials
// ---------------------------------------------------------------------------

// Gets or creates outline state.
function __poly_outline_cfg(_ed) {
  if (_ed == undefined) return undefined;

  if (!variable_struct_exists(_ed, "outline") || !is_struct(_ed.outline)) {
    _ed.outline = {
      mask: undefined,
      mw: 0,
      mh: 0,
      has: false,
      white: undefined,
      whiteSkin: undefined,
      mats_ok: undefined,
      warmed: false,
      color: [ 0.369, 0.467, 0.608 ], // #5E779B (was orange [1.0, 0.55, 0.1], keep for future use)
      thickness: 1,
      strength: 1.5,
      glow: 0.75,
      threshold: 0.9,
      // Mask resolution factor (1 = full-res).
      scale: 1,
      // Cached shader uniform handles (avoids 6 lookups per composite).
      uniforms: undefined,
      // Cheap change-detection snapshot (plain numbers + selection refs,
      // zero string alloc). Represents the state of the last rendered mask.
      cheap: undefined,
      // Mass-selection single box (world-space, camera-independent).
      mass_active: false,
      mass_valid: false,
      mass_key: undefined,
      mass_min: undefined,
      mass_max: undefined,
      // Walk cache: component sets for the mask state, reused on
      // camera/drag frames without getChildren/getMaterial lookups.
      // Rebuilt whenever view_dirty or the membership key changes.
      walk_key: undefined,
      walk_swapped: undefined,
      walk_muted: undefined,
    };
  }

  return _ed.outline;
}

// Backfills fields added after the outline struct was first created.
function __poly_outline_ensure_fields(_o) {
  if (!variable_struct_exists(_o, "scale") || !is_real(_o.scale) || _o.scale <= 0) _o.scale = 1;
  if (!variable_struct_exists(_o, "uniforms")) _o.uniforms = undefined;
  if (!variable_struct_exists(_o, "cheap")) _o.cheap = undefined;
  if (!variable_struct_exists(_o, "mass_active")) _o.mass_active = false;
  if (!variable_struct_exists(_o, "mass_valid")) _o.mass_valid = false;
  if (!variable_struct_exists(_o, "mass_key")) _o.mass_key = undefined;
  if (!variable_struct_exists(_o, "mass_min")) _o.mass_min = undefined;
  if (!variable_struct_exists(_o, "mass_max")) _o.mass_max = undefined;
  if (!variable_struct_exists(_o, "walk_key")) _o.walk_key = undefined;
  if (!variable_struct_exists(_o, "walk_swapped")) _o.walk_swapped = undefined;
  if (!variable_struct_exists(_o, "walk_muted")) _o.walk_muted = undefined;
}

// Returns a cached uniform handle, looking it up once.
function __poly_outline_uniform_cached(_o, _name) {
  if (!is_struct(_o.uniforms)) {
    _o.uniforms = {};
  }

  if (variable_struct_exists(_o.uniforms, _name)) return variable_struct_get(_o.uniforms, _name);
  var _h = shader_get_uniform(shPolygonEditorOutline, _name);
  variable_struct_set(_o.uniforms, _name, _h);
  return _h;
}

// Ensures outline mask materials exist.
function __poly_outline_mats(_o) {
  if (_o.mats_ok == true && _o.white != undefined && _o.whiteSkin != undefined) return true;
  if (_o.mats_ok == false) return false;
  var _flat = new GM3D_Material("poly_mask");
  _flat.setShader(GM3D_ERenderPass.Forward, shPolygonEditorMask);
  var _skin = new GM3D_Material("poly_mask_skin");
  _skin.setShader(GM3D_ERenderPass.Forward, shPolygonEditorMaskSkin);
  _o.white = _flat;
  _o.whiteSkin = _skin;
  _o.mats_ok = true;
  return true;
}

// Preinitializes outline materials and surface.
function __poly_outline_warmup(_ed, _o) {
  if (variable_struct_exists(_o, "warmed") && _o.warmed == true) return;
  _o.warmed = true;

  if (!__poly_outline_mats(_o)) return;
  if (application_surface == undefined || !surface_exists(application_surface)) return;
  __poly_outline_ensure_fields(_o);
  var _ws = __poly_mask_want(_ed);
  __poly_outline_mask_surface(_ed, _o, _ws[0], _ws[1]);
}

// Frees outline surfaces and materials.
function __poly_outline_cleanup(_ed) {
  if (_ed == undefined || !variable_struct_exists(_ed, "outline") || !is_struct(_ed.outline)) return;
  var _o = _ed.outline;

  if (_o.mask != undefined && surface_exists(_o.mask)) surface_free(_o.mask);
  if (_o.white != undefined) _o.white.destroy();
  if (_o.whiteSkin != undefined) _o.whiteSkin.destroy();
  _ed.outline = undefined;
}

// ---------------------------------------------------------------------------
// Mask surface
// ---------------------------------------------------------------------------

// Ensures outline mask surface size (old size retired, never freed live:
// the mask is a render target of this frame's not-yet-submitted commands).
function __poly_outline_mask_surface(_ed, _o, _w, _h) {
  if (_w <= 0 || _h <= 0) return false;
  if (_o.mask != undefined && surface_exists(_o.mask) && _o.mw == _w && _o.mh == _h) return true;
  if (_o.mask != undefined && surface_exists(_o.mask)) __poly_surf_retire(_ed, _o.mask);
  _o.mask = undefined;
  _o.mw = 0;
  _o.mh = 0;
  _o.mask = surface_create(_w, _h);
  _o.mw = _w;
  _o.mh = _h;

  if (!surface_exists(_o.mask)) {
    _o.mask = undefined;
    return false;
  }

  return true;
}

// ---------------------------------------------------------------------------
// Node processing
// ---------------------------------------------------------------------------

// Swaps one component to the mask material, recording the original.
function __poly_outline_swap_comp(_comp, _skinned, _o, _swapped) {
  if (_comp == undefined) return;
  var _orig = _comp.getMaterial();

  if (_orig == undefined || _orig == _o.white || _orig == _o.whiteSkin) return;
  array_push(_swapped, { comp: _comp, orig: _orig, skinned: _skinned });
  _comp.setMaterial(_skinned ? _o.whiteSkin : _o.white);
}

// Applies the mask state to one node using root metadata resolved once per tree.
function __poly_outline_process_node(_node, _entry, _excluded, _sel_epoch, _o, _swapped, _muted) {
  if (_excluded || !__poly_epoch_check(_entry, "__poly_outline_epoch", _sel_epoch)) {
    __poly_walk_mute_node(_node, _muted);
    return;
  }

  var _comps = [];
  __poly_walk_collect_comps(_node, _comps);

  for (var _i = 0, _n = array_length(_comps); _i < _n; _i++) {
    __poly_outline_swap_comp(_comps[_i].comp, _comps[_i].skinned, _o, _swapped);
  }
}

// Applies the mask state to one subtree node (walk visitor).
function __poly_outline_visit(_cur, _ctx) {
  __poly_outline_process_node(_cur, _ctx.entry, _ctx.excluded, _ctx.epoch, _ctx.o, _ctx.swapped, _ctx.muted);
}

// Disables shadow casting on swapped (selected) comps for the mask
// render. Muted non-selected comps are already disabled, so this covers
// every caster in the mask pass. Saves exact flags for restore: no
// light realloc, no global state touched.
function __poly_outline_shadow_off(_swapped) {
  var _saved = [];
  var _cb = GM3D_EMeshComponentFlags.CastShadows;

  for (var _i = 0, _n = array_length(_swapped); _i < _n; _i++) {
    var _comp = _swapped[_i].comp;
    var _get = _comp[$ "getFlags"];
    var _set = _comp[$ "setFlags"];

    if (_get == undefined || _set == undefined) continue;
    var _fl = method(_comp, _get)();

    if (!is_real(_fl) || (_fl & _cb) == 0) continue;
    array_push(_saved, { comp: _comp, flags: _fl });
    method(_comp, _set)(_fl & ~_cb);
  }

  return _saved;
}

// Restores exact shadow flags saved by __poly_outline_shadow_off.
function __poly_outline_shadow_restore(_saved) {
  for (var _i = 0, _n = array_length(_saved); _i < _n; _i++) {
    var _set = _saved[_i].comp[$ "setFlags"];

    if (_set == undefined) continue;
    method(_saved[_i].comp, _set)(_saved[_i].flags);
  }
}

// Builds the walk-cache key: selection membership + registry size +
// grid/preview identity. Transforms are excluded on purpose: gizmo drags
// change transforms every frame but the component set is identical, so
// drag frames reuse the cache. Any structural or material mutation sets
// view_dirty, which forces a rebuild below.
function __poly_outline_walk_key(_ed) {
  var _sel = [];
  var _n = is_array(_ed.sel) ? array_length(_ed.sel) : 0;

  for (var _i = 0; _i < _n; _i++) array_push(_sel, _ed.sel[_i]);
  return {
    n: _n,
    trk: __poly_reg_count(_ed),
    sel: _sel,
    grid: _ed[$ "grid_node"],
    preview: _ed[$ "drag_preview"],
  };
}

// Compares two walk-cache keys (node identity, never references).
function __poly_outline_walk_same(_a, _b) {
  if (!is_struct(_a) || !is_struct(_b) || _a.n != _b.n || _a.trk != _b.trk) return false;
  if (!is_array(_a.sel) || !is_array(_b.sel) || array_length(_a.sel) != array_length(_b.sel)) return false;
  for (var _i = 0, _n = array_length(_a.sel); _i < _n; _i++) if (!__poly_node_same(_a.sel[_i], _b.sel[_i])) return false;
  var _ga = _a.grid;
  var _gb = _b.grid;

  if (_ga == undefined || _gb == undefined) {
    if (_ga != _gb) return false;
  } else if (!__poly_node_same(_ga, _gb)) return false;

  var _pa = _a.preview;
  var _pb = _b.preview;

  if (_pa == undefined || _pb == undefined) {
    if (_pa != _pb) return false;
  } else if (!__poly_node_same(_pa, _pb)) return false;

  return true;
}

// Reapplies a cached mask state without any scene walk: no getChildren,
// no getMeshComponent, no getMaterial lookups. Returns false when there
// is nothing cached.
function __poly_outline_walk_apply(_ed, _o) {
  if (!is_array(_o.walk_swapped) || !is_array(_o.walk_muted)) return false;
  var _sw = _o.walk_swapped;
  var _mu = _o.walk_muted;

  for (var _i = 0, _n = array_length(_sw); _i < _n; _i++) {
    var _s = _sw[_i];

    if (_s.comp == undefined || _s.orig == undefined) continue;
    _s.comp.setMaterial(_s.skinned == true ? _o.whiteSkin : _o.white);
  }

  for (var _j = 0, _m = array_length(_mu); _j < _m; _j++) {
    if (_mu[_j].comp == undefined) continue;
    _mu[_j].comp.setEnabled(false);
  }

  return true;
}

// ---------------------------------------------------------------------------
// Change detection (cheap gate, zero string alloc)
// ---------------------------------------------------------------------------

// Wanted mask size this frame: pass size when the scratch is ready,
// scene size as fallback (keeps every 3D pass of the frame uniform).
function __poly_mask_want(_ed) {
  if (_ed.hi_ready) return __poly_pass_size(_ed);
  return [ max(1, round(_ed.scene_w)), max(1, round(_ed.scene_h)) ];
}

// Reads the cheap change-detection snapshot (plain numbers + selection
// refs + wanted mask size, zero strings). Returns undefined when it
// cannot be built reliably, forcing the render path.
function __poly_outline_cheap_read(_ed, _o) {
  if (!is_array(_ed.sel) || _ed.vp == undefined || _ed.rt == undefined) return undefined;
  var _s = __poly_cam_pose_key(_ed);

  if (_s == undefined) return undefined;
  _s.fov = _ed.vp.fovY;
  _s.nr = _ed.vp.near;
  _s.fr = _ed.vp.far;
  _s.ww = _ed.vp.winW;
  _s.wh = _ed.vp.winH;
  _s.n = array_length(_ed.sel);
  _s.trk = __poly_reg_count(_ed);
  _s.sw = _ed.scene_w;
  _s.sh = _ed.scene_h;
  _s.sc = _o.scale;
  var _mw = __poly_mask_want(_ed);
  _s.mw = _mw[0];
  _s.mh = _mw[1];
  _s.sel = [];

  for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) array_push(_s.sel, _ed.sel[_i]);
  _s.trs = __poly_sel_trs(_ed.sel);
  return _s;
}

// Compares a fresh snapshot against the stored one (state of the last
// rendered mask). Selection is compared by node identity plus exact
// local transforms, so silent edits (no commit yet) still refresh.
function __poly_outline_cheap_same(_a, _b) {
  if (!is_struct(_a) || !is_struct(_b)) return false;

  if (!__poly_pose_same(_a, _b)
    || _a.fov != _b.fov || _a.nr != _b.nr || _a.fr != _b.fr
    || _a.ww != _b.ww || _a.wh != _b.wh
    || _a.sw != _b.sw || _a.sh != _b.sh
  || _a.n != _b.n || _a.trk != _b.trk || _a.sc != _b.sc) {
    return false;
  }

  if (!is_array(_a.sel) || !is_array(_b.sel) || array_length(_a.sel) != array_length(_b.sel)) return false;
  for (var _i = 0, _n = array_length(_a.sel); _i < _n; _i++) if (!__poly_node_same(_a.sel[_i], _b.sel[_i])) return false;
  if (!is_array(_a.trs) || !is_array(_b.trs) || array_length(_a.trs) != array_length(_b.trs)) return false;
  for (var _j = 0, _m = array_length(_a.trs); _j < _m; _j++) if (_a.trs[_j] != _b.trs[_j]) return false;
  if (_a.mw != _b.mw || _a.mh != _b.mh) return false;
  return true;
}

// Compares two mass-selection keys (identity + tracked count + transforms).
// World-space box: no view/size fields, camera motion never invalidates it.
function __poly_outline_mass_same(_a, _b) {
  if (!is_struct(_a) || !is_struct(_b) || _a.n != _b.n || _a.trk != _b.trk) return false;
  if (!is_array(_a.sel) || !is_array(_b.sel) || array_length(_a.sel) != array_length(_b.sel)) return false;
  for (var _i = 0, _n = array_length(_a.sel); _i < _n; _i++) if (!__poly_node_same(_a.sel[_i], _b.sel[_i])) return false;
  if (!is_array(_a.trs) || !is_array(_b.trs) || array_length(_a.trs) != array_length(_b.trs)) return false;
  for (var _j = 0, _m = array_length(_a.trs); _j < _m; _j++) if (_a.trs[_j] != _b.trs[_j]) return false;
  return true;
}

// Refreshes the combined world-space AABB of the selection. World-space
// means camera motion never invalidates it: orbit frames reuse the stored
// box at zero cost. Mutations (view_dirty) and gizmo drags recompute.
function __poly_outline_mass_refresh(_ed, _o) {
  var _dragging = variable_struct_exists(_ed, "giz") && is_struct(_ed.giz) && _ed.giz.drag != -1;
  var _sel = [];
  var _n = is_array(_ed.sel) ? array_length(_ed.sel) : 0;

  for (var _i = 0; _i < _n; _i++) array_push(_sel, _ed.sel[_i]);
  var _key = { n: _n, trk: __poly_reg_count(_ed), sel: _sel, trs: __poly_sel_trs(_ed.sel) };

  if (!_dragging && _ed.view_dirty != true && _o.mass_valid == true && __poly_outline_mass_same(_key, _o.mass_key)) return;
  var _mm = { min: undefined, max: undefined };

  for (var _j = 0; _j < _n; _j++) {
    var _node = _ed.sel[_j];

    if (_node == undefined || __poly_hidden_get(_ed, _node)) continue;
    if (__poly_kind_of(_ed, _node) != "instance") continue;
    var _bb = __poly_node_aabb(_node);

    if (!is_struct(_bb) || _bb.valid != true || _bb.min == undefined || _bb.max == undefined) continue;
    __poly_aabb_grow(_mm, _bb.min);
    __poly_aabb_grow(_mm, _bb.max);
  }

  _o.mass_min = _mm.min;
  _o.mass_max = _mm.max;
  _o.mass_valid = (_mm.min != undefined && _mm.max != undefined);
  _o.mass_key = _key;
  // Fresh box: the main surface must re-render to show it.
  _ed.view_dirty = true;
}

// Draws the stored combined AABB (mass-selection mode, no per-frame walks).
function __poly_outline_mass_draw(_vp, _o) {
  static _gold = make_colour_rgb(255, 220, 80);
  if (_o.mass_valid != true || _o.mass_min == undefined || _o.mass_max == undefined) return;
  var _lx = _o.mass_min.x;
  var _ly = _o.mass_min.y;
  var _lz = _o.mass_min.z;
  var _hx = _o.mass_max.x;
  var _hy = _o.mass_max.y;
  var _hz = _o.mass_max.z;
  __poly_overlay_box(_vp, [
    new GM3D_Vec3(_lx, _ly, _lz),
    new GM3D_Vec3(_hx, _ly, _lz),
    new GM3D_Vec3(_lx, _hy, _lz),
    new GM3D_Vec3(_hx, _hy, _lz),
    new GM3D_Vec3(_lx, _ly, _hz),
    new GM3D_Vec3(_hx, _ly, _hz),
    new GM3D_Vec3(_lx, _hy, _hz),
    new GM3D_Vec3(_hx, _hy, _hz),
    ], 1.5, _gold);
}

// ---------------------------------------------------------------------------
// Capture and composite
// ---------------------------------------------------------------------------

// Marks selected asset entries for this capture, returning the count.
function __poly_outline_mark_sel(_ed, _epoch) {
  var _count = 0;

  if (!is_array(_ed.sel)) return 0;

  for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) {
    var _node = _ed.sel[_i];

    if (_node == undefined || __poly_hidden_get(_ed, _node)) continue;
    if (__poly_kind_of(_ed, _node) != "instance") continue;
    var _en = __poly_registry_find(_ed, _node);

    if (_en != undefined && !__poly_epoch_check(_en, "__poly_outline_epoch", _epoch)) {
      __poly_epoch_tag(_en, "__poly_outline_epoch", _epoch);
      _count++;
    }
  }

  return _count;
}

// Renders selection mask for outline.
function __poly_outline_capture(_ed) {
  if (_ed == undefined || _ed.active != true) return;
  if (!__poly_scene_panel_open(_ed)) return;
  var _o = __poly_outline_cfg(_ed);

  if (_o == undefined) return;
  if (_ed.rt == undefined || _ed.rt.scene == undefined || _ed.renderer == undefined) return;
  __poly_outline_ensure_fields(_o);
  // Mask follows the common offscreen pass scale (SSAA): mixed 3D
  // resolutions in one frame invalidate the whole submit. Thickness
  // compensation in the composite already handles arbitrary scales.
  _o.scale = __poly_pass_scale(_ed);
  __poly_outline_warmup(_ed, _o);

  // Selection size for the idle fast path below.
  var _sel_n = is_array(_ed.sel) ? array_length(_ed.sel) : 0;

  // Mass selection: one combined AABB instead of a per-pixel mask (no
  // second geometry render, no per-node material walks, orbit-safe).
  // Past 150 selected roots: single combined AABB instead of a per-pixel mask.
  if (_sel_n > 150) {
    _o.mass_active = true;
    _o.has = false;
    __poly_outline_mass_refresh(_ed, _o);
    return;
  }

  _o.mass_active = false;

  // Cheap gate: transient states always re-render; view_dirty (set by every
  // editor mutation: history, props, hide, serializers) forces a refresh;
  // otherwise a plain-numbers snapshot decides. No string building, no
  // subtree walks on this path — that was the orbit bottleneck.
  var _dragging = variable_struct_exists(_ed, "giz") && is_struct(_ed.giz) && _ed.giz.drag != -1;

  if (!_dragging && _ed.view_dirty != true) {
    var _peek = __poly_outline_cheap_read(_ed, _o);
    var _prev = _o[$ "cheap"];

    if (_peek != undefined && __poly_outline_cheap_same(_peek, _prev)) {
      // Static and mask matches: nothing to do. Empty selection reuses
      // this path too (no mask to render, snapshot still tracks state).
      if (_sel_n == 0 || (_o.has && _o.mask != undefined && surface_exists(_o.mask))) return;
    }
  }

  _o.has = false;

  if (!variable_struct_exists(_o, "sel_epoch")) _o.sel_epoch = 0;
  _o.sel_epoch++;
  var _epoch = _o.sel_epoch;

  if (__poly_outline_mark_sel(_ed, _epoch) == 0) {
    // Outline just disappeared (deselect/hide): force the main surface to
    // re-render, or the stale outline stays baked in with no later change
    // to invalidate it.
    if (_o.has == true) _ed.view_dirty = true;
    // Nothing renderable: remember the state so idle frames skip above.
    _o.cheap = __poly_outline_cheap_read(_ed, _o);
    return;
  }

  if (!__poly_outline_mats(_o)) return;
  if (application_surface == undefined || !surface_exists(application_surface)) return;
  var _w = _ed.scene_w;
  var _h = _ed.scene_h;

  if (!(_w > 0) || !(_h > 0)) return;
  // Freeze reallocs while the requested size is still changing (active
  // resize): allocating a fresh mask every frame gets its depth texture
  // destroyed inside the pending submit. Skip the render meanwhile (the
  // previous mask stays on screen); render once it settles.
  var _settled = variable_struct_exists(_o, "req_w") && variable_struct_exists(_o, "req_h") && _o.req_w == _w && _o.req_h == _h;
  _o.req_w = _w;
  _o.req_h = _h;

  if (!_settled) return;
  // Mask at the frame's wanted size (matches the main pass by
  // construction: full-res when ready, scene size as fallback).
  var _ms = __poly_mask_want(_ed);

  if (!__poly_outline_mask_surface(_ed, _o, _ms[0], _ms[1])) return;

  var _grid = _ed[$ "grid_node"];
  var _preview = _ed[$ "drag_preview"];
  var _t_walk0 = get_timer();
  // Walk cache: camera/drag frames reuse the component sets without any
  // getChildren/getMaterial lookups. view_dirty (any structural or
  // material mutation) or a membership change forces a full re-walk.
  var _wkey = __poly_outline_walk_key(_ed);
  var _swapped = [];
  var _muted = [];
  var _cached = (_ed.view_dirty != true) && __poly_outline_walk_same(_wkey, _o.walk_key)
    && is_array(_o.walk_swapped) && is_array(_o.walk_muted);

  if (_cached) {
    _swapped = _o.walk_swapped;
    _muted = _o.walk_muted;
    __poly_outline_walk_apply(_ed, _o);
  } else {
    var _nodes = _ed.rt.scene.getNodes();

    for (var _r = 0, _nn = array_length(_nodes); _r < _nn; _r++) {
      var _root = _nodes[_r];

      if (_root == undefined || _root.parent != undefined) continue;
      var _entry = __poly_registry_find(_ed, _root);
      var _excluded = (_grid != undefined && __poly_node_same(_root, _grid)) || (_preview != undefined && __poly_node_same(_root, _preview));
      __poly_walk_tree(_root, __poly_outline_visit, { entry: _entry, excluded: _excluded, epoch: _epoch, o: _o, swapped: _swapped, muted: _muted });
    }

    _o.walk_key = _wkey;
    _o.walk_swapped = _swapped;
    _o.walk_muted = _muted;
  }

  var _t_walk1 = get_timer();
  // No shadow casting in the mask pass (unlit white): saves the shadow
  // pass draw calls on the selected subset. Flags only, no light
  // realloc.
  var _flag_saved = __poly_outline_shadow_off(_swapped);

  surface_set_target(_o.mask);
  draw_clear(c_black);
  // No scene.update(0) here: poly_draw already refreshed world
  // matrices this frame after all Step mutations (camera, gizmo, preview).
  // Material/enabled swaps above do not affect transforms.
  var _t_render0 = get_timer();
  _ed.renderer.render(_ed.rt.scene);
  var _t_render1 = get_timer();
  surface_reset_target();
  _o.has = true;
  // Snapshot the rendered state AFTER rendering (resize-settle and surface
  // failures above bail out without storing, so the next frame retries).
  _o.cheap = __poly_outline_cheap_read(_ed, _o);
  // Fresh mask: force the main surface to re-render so it gets
  // composited. Without this, a mask that becomes ready on a frame where
  // the view key does not change (e.g. selecting in a still viewport)
  // would sit unseen until the next camera move.
  _ed.view_dirty = true;

  var _t_restore0 = get_timer();
  __poly_outline_shadow_restore(_flag_saved);
  __poly_walk_restore(_swapped, _muted);
  var _t_restore1 = get_timer();
  _ed.dbg_outline_walk_us = _t_walk1 - _t_walk0;
  _ed.dbg_outline_render_us = _t_render1 - _t_render0;
  _ed.dbg_outline_restore_us = _t_restore1 - _t_restore0;
  _ed.dbg_outline_cached = _cached;
}

// Draws outline glow from mask.
function __poly_outline_composite(_ed) {
  if (_ed == undefined || _ed.active != true) return;
  if (!variable_struct_exists(_ed, "outline") || !is_struct(_ed.outline)) return;
  var _o = _ed.outline;
  __poly_outline_ensure_fields(_o);

  if (!_o.has || _o.mask == undefined || !surface_exists(_o.mask)) return;
  var _gw = _ed.scene_w;
  var _gh = _ed.scene_h;

  if (!(_gw > 0) || !(_gh > 0)) return;
  var _u_color = __poly_outline_uniform_cached(_o, "u_color");
  var _u_texel = __poly_outline_uniform_cached(_o, "u_texel");
  var _u_thick = __poly_outline_uniform_cached(_o, "u_thickness");
  var _u_strength = __poly_outline_uniform_cached(_o, "u_strength");
  var _u_glow = __poly_outline_uniform_cached(_o, "u_glow");
  var _u_thresh = __poly_outline_uniform_cached(_o, "u_threshold");
  var _was_blend = gpu_get_blendenable();
  shader_set(shPolygonEditorOutline);

  if (_u_color != -1) shader_set_uniform_f(_u_color, _o.color[0], _o.color[1], _o.color[2]);
  if (_u_texel != -1 && _o.mw > 0 && _o.mh > 0) shader_set_uniform_f(_u_texel, 1.0 / _o.mw, 1.0 / _o.mh);

  if (_u_thick != -1) {
    // Keep the on-screen outline width constant across mask scales:
    // 1 mask texel covers 1/scale screen pixels, so the Sobel radius
    // in mask-texel units must shrink with the scale.
    shader_set_uniform_f(_u_thick, _o.thickness * _o.scale);
  }

  if (_u_strength != -1) shader_set_uniform_f(_u_strength, _o.strength);
  if (_u_glow != -1) shader_set_uniform_f(_u_glow, _o.glow);
  if (_u_thresh != -1) shader_set_uniform_f(_u_thresh, _o.threshold);
  gpu_set_blendenable(true);
  draw_surface_stretched(_o.mask, 0, 0, _gw, _gh);
  shader_reset();
  gpu_set_blendenable(_was_blend);
  draw_set_alpha(1);
  draw_set_color(c_white);
}
