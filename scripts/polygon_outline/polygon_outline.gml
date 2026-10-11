// polygon_outline — selection outline mask capture and glow composite.

// ---------------------------------------------------------------------------
// State and materials
// ---------------------------------------------------------------------------

// Gets or creates outline state.
function __polygon_outline_cfg(_ed) {
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
    };
  }

  return _ed.outline;
}

// Backfills fields added after the outline struct was first created.
function __polygon_outline_ensure_fields(_o) {
  if (!variable_struct_exists(_o, "scale") || !is_real(_o.scale) || _o.scale <= 0) _o.scale = 1;
  if (!variable_struct_exists(_o, "uniforms")) _o.uniforms = undefined;
  if (!variable_struct_exists(_o, "cheap")) _o.cheap = undefined;
  if (!variable_struct_exists(_o, "mass_active")) _o.mass_active = false;
  if (!variable_struct_exists(_o, "mass_valid")) _o.mass_valid = false;
  if (!variable_struct_exists(_o, "mass_key")) _o.mass_key = undefined;
  if (!variable_struct_exists(_o, "mass_min")) _o.mass_min = undefined;
  if (!variable_struct_exists(_o, "mass_max")) _o.mass_max = undefined;
}

// Returns a cached uniform handle, looking it up once.
function __polygon_outline_uniform_cached(_o, _name) {
  if (!is_struct(_o.uniforms)) {
    _o.uniforms = {};
  }

  if (variable_struct_exists(_o.uniforms, _name)) return variable_struct_get(_o.uniforms, _name);
  var _h = shader_get_uniform(shPolygonEditorOutline, _name);
  variable_struct_set(_o.uniforms, _name, _h);
  return _h;
}

// Ensures outline mask materials exist.
function __polygon_outline_mats(_o) {
  if (_o.mats_ok == true && _o.white != undefined && _o.whiteSkin != undefined) return true;
  if (_o.mats_ok == false) return false;
  var _flat = new GM3D_Material("polygon_mask");
  _flat.setShader(GM3D_ERenderPass.Forward, shPolygonEditorMask);
  var _skin = new GM3D_Material("polygon_mask_skin");
  _skin.setShader(GM3D_ERenderPass.Forward, shPolygonEditorMaskSkin);
  _o.white = _flat;
  _o.whiteSkin = _skin;
  _o.mats_ok = true;
  return true;
}

// Preinitializes outline materials and surface.
function __polygon_outline_warmup(_ed, _o) {
  if (variable_struct_exists(_o, "warmed") && _o.warmed == true) return;
  _o.warmed = true;

  if (!__polygon_outline_mats(_o)) return;
  if (application_surface == undefined || !surface_exists(application_surface)) return;
  __polygon_outline_ensure_fields(_o);
  var _ws = max(1, round(_ed.scene_w * _o.scale));
  var _hs = max(1, round(_ed.scene_h * _o.scale));
  __polygon_outline_mask_surface(_ed, _o, _ws, _hs);
}

// Frees outline surfaces and materials.
function __polygon_outline_cleanup(_ed) {
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
function __polygon_outline_mask_surface(_ed, _o, _w, _h) {
  if (_w <= 0 || _h <= 0) return false;
  if (_o.mask != undefined && surface_exists(_o.mask) && _o.mw == _w && _o.mh == _h) return true;
  if (_o.mask != undefined && surface_exists(_o.mask)) __polygon_surf_retire(_ed, _o.mask);
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
function __polygon_outline_swap_comp(_comp, _skinned, _o, _swapped) {
  if (_comp == undefined) return;
  var _orig = _comp.getMaterial();

  if (_orig == undefined || _orig == _o.white || _orig == _o.whiteSkin) return;
  array_push(_swapped, { comp: _comp, orig: _orig });
  _comp.setMaterial(_skinned ? _o.whiteSkin : _o.white);
}

// Applies the mask state to one node using root metadata resolved once per tree.
function __polygon_outline_process_node(_node, _entry, _excluded, _sel_epoch, _o, _swapped, _muted) {
  if (_excluded || !__polygon_epoch_check(_entry, "__polygon_outline_epoch", _sel_epoch)) {
    __polygon_walk_mute_node(_node, _muted);
    return;
  }

  __polygon_outline_swap_comp(_node.getMeshComponent(), false, _o, _swapped);
  __polygon_outline_swap_comp(_node.getSkinnedMeshComponent(), true, _o, _swapped);
}

// Applies the mask state to one subtree node (walk visitor).
function __polygon_outline_visit(_cur, _ctx) {
  __polygon_outline_process_node(_cur, _ctx.entry, _ctx.excluded, _ctx.epoch, _ctx.o, _ctx.swapped, _ctx.muted);
}

// ---------------------------------------------------------------------------
// Change detection (cheap gate, zero string alloc)
// ---------------------------------------------------------------------------

// Reads the cheap change-detection snapshot (plain numbers + selection
// refs, zero strings). Returns undefined when it cannot be built reliably,
// forcing the render path.
function __polygon_outline_cheap_read(_ed, _o) {
  if (!is_array(_ed.sel) || _ed.vp == undefined || _ed.rt == undefined) return undefined;
  var _s = __polygon_cam_pose_key(_ed);

  if (_s == undefined) return undefined;
  _s.fov = _ed.vp.fovY;
  _s.nr = _ed.vp.near;
  _s.fr = _ed.vp.far;
  _s.ww = _ed.vp.winW;
  _s.wh = _ed.vp.winH;
  _s.n = array_length(_ed.sel);
  _s.trk = __polygon_reg_count(_ed);
  _s.sw = _ed.scene_w;
  _s.sh = _ed.scene_h;
  _s.sc = _o.scale;
  _s.sel = [];

  for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) array_push(_s.sel, _ed.sel[_i]);
  return _s;
}

// Compares a fresh snapshot against the stored one (state of the last
// rendered mask). Selection is compared by node identity: any transform
// edit flows through code that sets view_dirty or drags the gizmo, both of
// which bypass this gate; silent drift is caught by the viewport key,
// which clears the stored snapshot (see __polygon_view_needs_render).
function __polygon_outline_cheap_same(_a, _b) {
  if (!is_struct(_a) || !is_struct(_b)) return false;

  if (!__polygon_pose_same(_a, _b)
    || _a.fov != _b.fov || _a.nr != _b.nr || _a.fr != _b.fr
    || _a.ww != _b.ww || _a.wh != _b.wh
    || _a.sw != _b.sw || _a.sh != _b.sh
  || _a.n != _b.n || _a.trk != _b.trk || _a.sc != _b.sc) {
    return false;
  }

  if (!is_array(_a.sel) || !is_array(_b.sel) || array_length(_a.sel) != array_length(_b.sel)) return false;
  for (var _i = 0, _n = array_length(_a.sel); _i < _n; _i++) if (!__polygon_node_same(_a.sel[_i], _b.sel[_i])) return false;
  return true;
}

// Compares two mass-selection keys (selection identity + tracked count).
function __polygon_outline_mass_same(_a, _b) {
  if (!is_struct(_a) || !is_struct(_b) || _a.n != _b.n || _a.trk != _b.trk) return false;
  if (!is_array(_a.sel) || !is_array(_b.sel) || array_length(_a.sel) != array_length(_b.sel)) return false;
  for (var _i = 0, _n = array_length(_a.sel); _i < _n; _i++) if (!__polygon_node_same(_a.sel[_i], _b.sel[_i])) return false;
  return true;
}

// Refreshes the combined world-space AABB of the selection. World-space
// means camera motion never invalidates it: orbit frames reuse the stored
// box at zero cost. Mutations (view_dirty) and gizmo drags recompute.
function __polygon_outline_mass_refresh(_ed, _o) {
  var _dragging = variable_struct_exists(_ed, "giz") && is_struct(_ed.giz) && _ed.giz.drag != -1;
  var _sel = [];
  var _n = is_array(_ed.sel) ? array_length(_ed.sel) : 0;

  for (var _i = 0; _i < _n; _i++) array_push(_sel, _ed.sel[_i]);
  var _key = { n: _n, trk: __polygon_reg_count(_ed), sel: _sel };

  if (!_dragging && _ed.view_dirty != true && _o.mass_valid == true && __polygon_outline_mass_same(_key, _o.mass_key)) return;
  var _mm = { min: undefined, max: undefined };

  for (var _j = 0; _j < _n; _j++) {
    var _node = _ed.sel[_j];

    if (_node == undefined || __polygon_hidden_get(_ed, _node)) continue;
    if (__polygon_kind_of(_ed, _node) != "instance") continue;
    var _bb = __polygon_node_aabb(_node);

    if (!is_struct(_bb) || _bb.valid != true || _bb.min == undefined || _bb.max == undefined) continue;
    __polygon_aabb_grow(_mm, _bb.min);
    __polygon_aabb_grow(_mm, _bb.max);
  }

  _o.mass_min = _mm.min;
  _o.mass_max = _mm.max;
  _o.mass_valid = (_mm.min != undefined && _mm.max != undefined);
  _o.mass_key = _key;
  // Fresh box: the main surface must re-render to show it.
  _ed.view_dirty = true;
}

// Draws the stored combined AABB (mass-selection mode, no per-frame walks).
function __polygon_outline_mass_draw(_vp, _o) {
  static _gold = make_colour_rgb(255, 220, 80);
  if (_o.mass_valid != true || _o.mass_min == undefined || _o.mass_max == undefined) return;
  var _lx = _o.mass_min.x;
  var _ly = _o.mass_min.y;
  var _lz = _o.mass_min.z;
  var _hx = _o.mass_max.x;
  var _hy = _o.mass_max.y;
  var _hz = _o.mass_max.z;
  __polygon_overlay_box(_vp, [
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
function __polygon_outline_mark_sel(_ed, _epoch) {
  var _count = 0;

  if (!is_array(_ed.sel)) return 0;

  for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) {
    var _node = _ed.sel[_i];

    if (_node == undefined || __polygon_hidden_get(_ed, _node)) continue;
    if (__polygon_kind_of(_ed, _node) != "instance") continue;
    var _en = __polygon_registry_find(_ed, _node);

    if (_en != undefined && !__polygon_epoch_check(_en, "__polygon_outline_epoch", _epoch)) {
      __polygon_epoch_tag(_en, "__polygon_outline_epoch", _epoch);
      _count++;
    }
  }

  return _count;
}

// Renders selection mask for outline.
function __polygon_outline_capture(_ed) {
  if (_ed == undefined || _ed.active != true) return;
  if (!__polygon_scene_panel_open(_ed)) return;
  var _o = __polygon_outline_cfg(_ed);

  if (_o == undefined) return;
  if (_ed.rt == undefined || _ed.rt.scene == undefined || _ed.renderer == undefined) return;
  __polygon_outline_warmup(_ed, _o);
  __polygon_outline_ensure_fields(_o);

  // Selection size for the idle fast path below.
  var _sel_n = is_array(_ed.sel) ? array_length(_ed.sel) : 0;

  // Mass selection: one combined AABB instead of a per-pixel mask (no
  // second geometry render, no per-node material walks, orbit-safe).
  // Past 50 selected roots: single combined AABB instead of a per-pixel mask.
  if (_sel_n > 50) {
    _o.mass_active = true;
    _o.has = false;
    __polygon_outline_mass_refresh(_ed, _o);
    return;
  }

  _o.mass_active = false;

  // Cheap gate: transient states always re-render; view_dirty (set by every
  // editor mutation: history, props, hide, serializers) forces a refresh;
  // otherwise a plain-numbers snapshot decides. No string building, no
  // subtree walks on this path — that was the orbit bottleneck.
  var _dragging = variable_struct_exists(_ed, "giz") && is_struct(_ed.giz) && _ed.giz.drag != -1;

  if (!_dragging && _ed.view_dirty != true) {
    var _peek = __polygon_outline_cheap_read(_ed, _o);
    var _prev = _o[$ "cheap"];

    if (_peek != undefined && __polygon_outline_cheap_same(_peek, _prev)) {
      // Static and mask matches: nothing to do. Empty selection reuses
      // this path too (no mask to render, snapshot still tracks state).
      if (_sel_n == 0 || (_o.has && _o.mask != undefined && surface_exists(_o.mask))) return;
    }
  }

  _o.has = false;

  if (!variable_struct_exists(_o, "sel_epoch")) _o.sel_epoch = 0;
  _o.sel_epoch++;
  var _epoch = _o.sel_epoch;

  if (__polygon_outline_mark_sel(_ed, _epoch) == 0) {
    // Outline just disappeared (deselect/hide): force the main surface to
    // re-render, or the stale outline stays baked in with no later change
    // to invalidate it.
    if (_o.has == true) _ed.view_dirty = true;
    // Nothing renderable: remember the state so idle frames skip above.
    _o.cheap = __polygon_outline_cheap_read(_ed, _o);
    return;
  }

  if (!__polygon_outline_mats(_o)) return;
  if (application_surface == undefined || !surface_exists(application_surface)) return;
  var _w = _ed.scene_w;
  var _h = _ed.scene_h;

  if (!(_w > 0) || !(_h > 0)) return;
  // Freeze the outline while the requested size is still changing (active
  // resize): allocating + rendering a fresh mask every frame gets its depth
  // texture destroyed inside the pending submit. Render once it settles.
  var _settled = variable_struct_exists(_o, "req_w") && variable_struct_exists(_o, "req_h") && _o.req_w == _w && _o.req_h == _h;
  _o.req_w = _w;
  _o.req_h = _h;

  if (!_settled) return;
  // Scaled mask: same silhouette at a fraction of the geometry + fill cost.
  var _mw = max(1, round(_w * _o.scale));
  var _mh = max(1, round(_h * _o.scale));

  if (!__polygon_outline_mask_surface(_ed, _o, _mw, _mh)) return;
  var _grid = _ed[$ "grid_node"];
  var _preview = _ed[$ "drag_preview"];
  var _swapped = [];
  var _muted = [];
  var _nodes = _ed.rt.scene.getNodes();

  for (var _r = 0, _nn = array_length(_nodes); _r < _nn; _r++) {
    var _root = _nodes[_r];

    if (_root == undefined || _root.parent != undefined) continue;
    var _entry = __polygon_registry_find(_ed, _root);
    var _excluded = (_grid != undefined && __polygon_node_same(_root, _grid)) || (_preview != undefined && __polygon_node_same(_root, _preview));
    __polygon_walk_tree(_root, __polygon_outline_visit, { entry: _entry, excluded: _excluded, epoch: _epoch, o: _o, swapped: _swapped, muted: _muted });
  }

  surface_set_target(_o.mask);
  draw_clear(c_black);
  // Refresh world matrices: the camera moved in step after the last
  // scene.update, so without this the mask lags one move behind the
  // main render (visible as jitter while orbiting).
  _ed.rt.scene.update(0);
  _ed.renderer.render(_ed.rt.scene);
  surface_reset_target();
  _o.has = true;
  // Snapshot the rendered state AFTER rendering (resize-settle and surface
  // failures above bail out without storing, so the next frame retries).
  _o.cheap = __polygon_outline_cheap_read(_ed, _o);
  // Fresh mask: force the main surface to re-render so it gets
  // composited. Without this, a mask that becomes ready on a frame where
  // the view key does not change (e.g. selecting in a still viewport)
  // would sit unseen until the next camera move.
  _ed.view_dirty = true;

  __polygon_walk_restore(_swapped, _muted);
}

// Draws outline glow from mask.
function __polygon_outline_composite(_ed) {
  if (_ed == undefined || _ed.active != true) return;
  if (!variable_struct_exists(_ed, "outline") || !is_struct(_ed.outline)) return;
  var _o = _ed.outline;
  __polygon_outline_ensure_fields(_o);

  if (!_o.has || _o.mask == undefined || !surface_exists(_o.mask)) return;
  var _gw = _ed.scene_w;
  var _gh = _ed.scene_h;

  if (!(_gw > 0) || !(_gh > 0)) return;
  var _u_color = __polygon_outline_uniform_cached(_o, "u_color");
  var _u_texel = __polygon_outline_uniform_cached(_o, "u_texel");
  var _u_thick = __polygon_outline_uniform_cached(_o, "u_thickness");
  var _u_strength = __polygon_outline_uniform_cached(_o, "u_strength");
  var _u_glow = __polygon_outline_uniform_cached(_o, "u_glow");
  var _u_thresh = __polygon_outline_uniform_cached(_o, "u_threshold");
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
