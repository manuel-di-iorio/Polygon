// poly_imgui_viewport — Scene viewport panel + render to surface.

// ---------------------------------------------------------------------------
// Surface lifetime
// ---------------------------------------------------------------------------

// Shared surface lifetime for ImGui-displayed surfaces (viewport, anim preview):
// never surface_free() a texture ImGui may have recorded this frame — retire
// it instead; the graveyard frees it once no submit can reference it.
// TTL 16 frames: mode switches retire several large surfaces at once while
// the backend still drains deep queues, and short TTLs freed textures
// still in flight (validation errors + dropped submits).
function __poly_surf_retire(_ed, _surf) {
  if (!surface_exists(_surf)) return;
  if (!variable_struct_exists(_ed, "surf_graveyard") || !is_array(_ed.surf_graveyard)) _ed.surf_graveyard = [];
  array_push(_ed.surf_graveyard, { surf: _surf, ttl: 16 });
}

// Frees one expired surface graveyard entry.
function __poly_surf_graveyard_free(_entry) {
  if (surface_exists(_entry.surf)) surface_free(_entry.surf);
}

// Generic TTL graveyard step: ages entries backwards, calling _free_fn on
// expiry and removing them. Shared by surface/thumb/sprite graveyards.
function __poly_graveyard_step(_arr, _free_fn) {
  if (!is_array(_arr)) return;

  for (var _i = array_length(_arr) - 1; _i >= 0; _i--) {
    var _entry = _arr[_i];
    _entry.ttl--;

    if (_entry.ttl <= 0) {
      if (_free_fn != undefined) _free_fn(_entry);
      array_delete(_arr, _i, 1);
    }
  }
}

// ---------------------------------------------------------------------------
// Change key
// ---------------------------------------------------------------------------

// Builds a change key for the viewport picture (camera, sizes, settings,
// selection, hover). Transient activity (drag/rect/preview/notice) forces
// a render every frame and is reported via busy.
function __poly_view_busy(_ed) {
  if (variable_struct_exists(_ed, "cube_moved") && _ed.cube_moved == true) return true;
  if (variable_struct_exists(_ed, "giz") && is_struct(_ed.giz) && _ed.giz.drag != -1) return true;
  if (variable_struct_exists(_ed, "rect") && is_struct(_ed.rect) && _ed.rect.on == true) return true;
  if (variable_struct_exists(_ed, "drag_preview") && _ed.drag_preview != undefined) return true;
  if (is_real(_ed.cam_speed_notice) && _ed.cam_speed_notice > 0) return true;
  if (__poly_inspector_gesturing(_ed)) return true;
  return false;
}

// Appends the camera pose to the view key.
// 5 decimals: string() rounds to 2, so slow moves (orbit is 0.18 deg/px,
// fly can crawl at 0.001/frame) would not flip the key and frames would
// be skipped in steps instead of rendering smoothly.
function __poly_view_cam_key(_key, _ed) {
  var _cam = undefined;

  if (_ed.viewcam != undefined) {
    _cam = _ed.viewcam;
  } else if (_ed.rt != undefined) {
    _cam = _ed.rt.cam;
  }

  if (_cam == undefined) return _key;
  var _pos = _cam.getLocalPosition();

  if (_pos != undefined) _key += string_format(_pos.x, 0, 5) + "," + string_format(_pos.y, 0, 5) + "," + string_format(_pos.z, 0, 5) + "|";
  var _rot = _cam.getLocalRotation();

  if (_rot != undefined) _key += string_format(_rot.x, 0, 5) + "," + string_format(_rot.y, 0, 5) + "," + string_format(_rot.z, 0, 5) + "," + string_format(_rot.w, 0, 5) + "|";
  return _key;
}

// Appends one selected node (id + live transform) to the view key.
function __poly_view_sel_key(_key, _ed, _node) {
  if (_node == undefined) return _key + "x";
  var _en = __poly_registry_find(_ed, _node);

  if (_en == undefined || !is_string(_en.id)) return _key + "?";
  _key += _en.id;
  var _pos = _node.getLocalPosition();

  if (_pos != undefined) _key += string(_pos.x) + "," + string(_pos.y) + "," + string(_pos.z);
  // Rotation (euler degrees keep precision at drag speed) and scale must
  // invalidate too, or live rotation/scale edits keep the stale surface.
  var _rot = _node.getLocalRotation();

  if (_rot != undefined) {
    var _euler = __poly_quat_to_euler(_rot);

    if (is_array(_euler) && array_length(_euler) >= 3) _key += "," + string(radtodeg(_euler[0])) + "," + string(radtodeg(_euler[1])) + "," + string(radtodeg(_euler[2]));
  }

  var _sca = _node.getLocalScale();

  if (_sca != undefined) _key += "," + string(_sca.x) + "," + string(_sca.y) + "," + string(_sca.z);
  return _key;
}

function __poly_view_key(_ed) {
  var _key = __poly_view_cam_key("", _ed);
  _key += "w" + string(_ed.scene_w) + "x" + string(_ed.scene_h);
  _key += "|g" + string(_ed.grid_step) + (_ed.show_grid == true ? "1" : "0");
  _key += (_ed.show_shadows != false ? "1" : "0") + (_ed.show_unlit == true ? "1" : "0");
  _key += "|h" + string(_ed.giz.hover) + "," + string(_ed.cube_hover);
  _key += "|tool" + string(_ed.giz.tool);
  _key += "|t" + string(__poly_reg_count(_ed));

  if (is_array(_ed.sel)) {
    _key += "|s" + string(array_length(_ed.sel));

    for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) _key = __poly_view_sel_key(_key, _ed, _ed.sel[_i]);
  }

  _key += "|p" + string(variable_struct_exists(_ed, "drag_preview") && _ed.drag_preview != undefined ? 1 : 0);
  _key += string(variable_struct_exists(_ed, "rect") && is_struct(_ed.rect) && _ed.rect.on == true ? 1 : 0);
  _key += string(is_real(_ed.cam_speed_notice) && _ed.cam_speed_notice > 0 ? 1 : 0);
  return _key;
}

// Checks the ordered selection snapshot for changes (updates it).
function __poly_view_sel_changed(_ed) {
  var _prev = (variable_struct_exists(_ed, "view_selprev") && is_array(_ed.view_selprev)) ? _ed.view_selprev : undefined;
  var _n = is_array(_ed.sel) ? array_length(_ed.sel) : 0;
  var _changed = true;

  if (_prev != undefined && array_length(_prev) == _n) {
    _changed = false;

    for (var _i = 0; _i < _n; _i++) {
      if (!__poly_node_same(_prev[_i], _ed.sel[_i])) {
        _changed = true;
        break;
      }
    }
  }

  if (_changed) {
    var _cur = [];

    for (var _j = 0; _j < _n; _j++) array_push(_cur, _ed.sel[_j]);
    _ed.view_selprev = _cur;
  }

  return _changed;
}

// Normalizes viewcube hover to a stable scalar for the cheap snapshot:
// -1 when the cube panel is closed or no cone is hit (moving the mouse
// elsewhere never changes the picture); otherwise a per-cone code, so
// highlight transitions still re-render. The raw value is a fresh array
// per hover query, which would never compare equal across frames.
function __poly_cube_hover_key(_ed) {
  if (!variable_struct_exists(_ed, "imgui") || !is_struct(_ed.imgui)
    || !variable_struct_exists(_ed.imgui, "win_cube") || !is_struct(_ed.imgui.win_cube)
  || _ed.imgui.win_cube.open != true) {
    return -1;
  }

  var _hov = _ed[$ "cube_hover"];

  if (is_array(_hov) && array_length(_hov) >= 2 && is_real(_hov[0]) && is_real(_hov[1])) return _hov[0] * 10 + (_hov[1] > 0 ? 1 : 2);
  return -1;
}

// Reads the cheap viewport snapshot (plain numbers, no strings).
// Covers every scalar input of __poly_view_key; selection transforms
// stay in the string key (exact fallback below). Returns undefined when
// it cannot be built, forcing the exact path.
function __poly_view_cheap_read(_ed) {
  if (_ed.vp == undefined || _ed.rt == undefined) return undefined;
  var _pose = __poly_cam_pose_key(_ed);

  if (_pose == undefined) return undefined;
  _pose.sw = _ed.scene_w;
  _pose.sh = _ed.scene_h;
  _pose.gs = _ed.grid_step;
  _pose.sg = _ed.show_grid == true ? 1 : 0;
  _pose.sh_ = _ed.show_shadows != false ? 1 : 0;
  _pose.un = _ed.show_unlit == true ? 1 : 0;
  _pose.hov = (is_array(_ed.sel) && array_length(_ed.sel) > 0) ? _ed.giz.hover : -1;
  _pose.cube = __poly_cube_hover_key(_ed);
  _pose.tool = _ed.giz.tool;
  _pose.trk = __poly_reg_count(_ed);
  _pose.pv = (variable_struct_exists(_ed, "drag_preview") && _ed.drag_preview != undefined) ? 1 : 0;
  _pose.rc = (variable_struct_exists(_ed, "rect") && is_struct(_ed.rect) && _ed.rect.on == true) ? 1 : 0;
  _pose.nt = (is_real(_ed.cam_speed_notice) && _ed.cam_speed_notice > 0) ? 1 : 0;
  return _pose;
}

// Compares two cheap viewport snapshots.
function __poly_view_cheap_same(_a, _b) {
  if (!is_struct(_a) || !is_struct(_b)) return false;
  return _a.cpx == _b.cpx && _a.cpy == _b.cpy && _a.cpz == _b.cpz
    && _a.crx == _b.crx && _a.cry == _b.cry && _a.crz == _b.crz && _a.crw == _b.crw
    && _a.sw == _b.sw && _a.sh == _b.sh
    && _a.gs == _b.gs && _a.sg == _b.sg
    && _a.sh_ == _b.sh_ && _a.un == _b.un
    && _a.hov == _b.hov && _a.cube == _b.cube && _a.tool == _b.tool
    && _a.trk == _b.trk && _a.pv == _b.pv && _a.rc == _b.rc && _a.nt == _b.nt;
}

// Dirty-reason bitmask for the cheap viewport snapshot: tells *what* changed
// without building the expensive string key (string_format x7 + quat_to_euler
// per selected node). Any bit set means the surface must re-render.
enum PolygonViewDirty {
  None     = 0,
  Camera   = 1, // camera pose (hot case: continuous navigation)
  Size     = 2, // scene surface size
  Settings = 4, // grid_step/show_grid/shadows/unlit
  State    = 8, // hover/tool/cube/regcount/preview/rect/notice
}

// Diffs two cheap snapshots into a PolygonViewDirty mask (0 = identical).
function __poly_view_cheap_mask(_a, _b) {
  if (!is_struct(_a) || !is_struct(_b)) return PolygonViewDirty.Camera | PolygonViewDirty.Size | PolygonViewDirty.Settings | PolygonViewDirty.State;
  var _m = PolygonViewDirty.None;

  if (_a.cpx != _b.cpx || _a.cpy != _b.cpy || _a.cpz != _b.cpz
  || _a.crx != _b.crx || _a.cry != _b.cry || _a.crz != _b.crz || _a.crw != _b.crw) {
    _m |= PolygonViewDirty.Camera;
  }

  if (_a.sw != _b.sw || _a.sh != _b.sh) _m |= PolygonViewDirty.Size;
  if (_a.gs != _b.gs || _a.sg != _b.sg || _a.sh_ != _b.sh_ || _a.un != _b.un) _m |= PolygonViewDirty.Settings;

  if (_a.hov != _b.hov || _a.cube != _b.cube || _a.tool != _b.tool || _a.trk != _b.trk
  || _a.pv != _b.pv || _a.rc != _b.rc || _a.nt != _b.nt) {
    _m |= PolygonViewDirty.State;
  }

  return _m;
}

// Checks if the scene surface needs a re-render (dirty flag, key change
// or transient activity). FPS text is excluded on purpose: it is drawn
// live in Draw GUI instead of baked into the surface.
function __poly_view_needs_render(_ed) {
  if (_ed.view_dirty == true) return true;
  if (__poly_view_busy(_ed)) return true;
  // Keep an ordered snapshot to catch selection changes without registry lookups.
  if (__poly_view_sel_changed(_ed)) return true;
  // Cheap gate: static frames skip the string-key build (expensive with
  // big selections). Any scalar change short-circuits to render via the
  // dirty-reason mask; the string key stays only as fallback when the
  // cheap snapshot cannot be built.
  var _cheap = __poly_view_cheap_read(_ed);
  var _prev_cheap = _ed[$ "view_cheap"];

  if (_cheap != undefined && __poly_view_cheap_same(_cheap, _prev_cheap)) return false;
  _ed.view_cheap = _cheap;

  if (_cheap != undefined) {
    // A scalar changed: a re-render is certainly needed, building the
    // string key would be pure overhead (hot case = camera moving).
    // The mask is kept on _ed for debugging/profiling.
    _ed.view_mask = __poly_view_cheap_mask(_cheap, _prev_cheap);

    // Same as the old exact-key path: a picture change invalidates
    // the outline's cheap snapshot (covers silent transform drift).
    if (variable_struct_exists(_ed, "outline") && is_struct(_ed.outline)) _ed.outline.cheap = undefined;
    return true;
  }

  // Cheap snapshot cannot be built (vp/cam missing): fall back to the exact key.
  var _key = __poly_view_key(_ed);

  if (!variable_struct_exists(_ed, "view_key") || _ed.view_key != _key) {
    _ed.view_key = _key;
    // The viewport picture changed in a way the outline gate cannot see
    // (e.g. silent transform drift): force a mask refresh next capture.
    if (variable_struct_exists(_ed, "outline") && is_struct(_ed.outline)) _ed.outline.cheap = undefined;
    return true;
  }

  return false;
}

// ---------------------------------------------------------------------------
// Panels
// ---------------------------------------------------------------------------

// Draws floating FPS panel (F9). Draggable, auto-sized, no dock.
function __poly_imgui_fps(_ed) {
  if (_ed.show_fps != true) return;
  // Anchor on first use; ImGui keeps the user's later manual position.
  ImGui.SetNextWindowPos(_ed.gw - 12, _ed.gh - 12, ImGuiCond.FirstUseEver, 1, 1);
  var _flags = ImGuiWindowFlags.NoCollapse | ImGuiWindowFlags.AlwaysAutoResize;

  if (!ImGui.Begin("Debug", undefined, _flags)) {
    ImGui.End();
    return;
  }

  ImGui.Text("FPS: " + string(round(fps_real)));
  ImGui.End();
}

// Draws live scene panel rendered to surface.
function __poly_imgui_scene_panel(_ed) {
  var _ui = _ed.imgui;

  if (!_ui.win_scene.open) return;
  var _place = __poly_imgui_place(_ed).scene;

  if (!__poly_imgui_dock_fresh(_ed)) {
    ImGui.SetNextWindowPos(_place.x, _place.y, _ui.cond);
    ImGui.SetNextWindowSize(_place.w, _place.h, _ui.cond);
  }

  var _flags = ImGuiWindowFlags.NoScrollbar | ImGuiWindowFlags.NoScrollWithMouse;

  if (__poly_imgui_lock_move(_ed)) _flags = _flags | ImGuiWindowFlags.NoMove;

  if (!ImGui.Begin("Scene", _ui.win_scene, _flags)) {
    _ed.svp_hover = false;
    ImGui.End();
    return;
  }

  var _aw = max(160, ImGui.GetContentRegionAvailX());
  var _ah = _aw * 9 / 16;
  _ah = max(120, ImGui.GetContentRegionAvailY());

  var _dw = _aw;
  var _dh = _ah;
  _ed.scene_w = clamp(round(_dw), 160, 1920);
  _ed.scene_h = clamp(round(_dh), 90, 1080);
  _ed.svp = { x: ImGui.GetCursorScreenPosX(), y: ImGui.GetCursorScreenPosY(), w: _dw, h: _dh };
  _ed.svp_hover = ImGui.IsWindowHovered();

  if (surface_exists(_ed.scene_surf)) {
    // Display at integer size (fractional ImGui sizes would resample):
    // never larger than the available region.
    ImGui.Surface(_ed.scene_surf, c_white, 1, min(_dw, _ed.scene_w), min(_dh, _ed.scene_h));
  } else {
    ImGui.TextDisabled("No scene");
  }

  ImGui.End();
}

// Checks if scene panel is open.
function __poly_scene_panel_open(_ed) {
  if (_ed == undefined || !variable_struct_exists(_ed, "imgui") || !is_struct(_ed.imgui)) return false;
  if (!variable_struct_exists(_ed.imgui, "win_scene") || !is_struct(_ed.imgui.win_scene)) return false;
  return _ed.imgui.win_scene.open == true;
}

// Effective AA mode: off, fxaa, smaa or ssaa (anything else falls back to ssaa).
function __poly_aa_mode(_ed) {
  var _m = _ed[$ "aa_mode"];
  if (!__poly_aa_known(_m)) _m = "off";
  return _m;
}

// Switches AA mode and forces a re-render.
function __poly_aa_set(_ed, _mode) {
  if (!__poly_aa_known(_mode)) return;
  _ed.aa_mode = _mode;
  _ed.view_dirty = true;
}

// Checks a mode string.
function __poly_aa_known(_mode) {
  return _mode == "off" || _mode == "ssaa" || _mode == "fxaa" || _mode == "smaa";
}

// Effective AA factor: always the setting (1, 1.5 or 2). No stillness
// gate: switching factors between motion and rest caused visible AA
// on/off popping on every re-render.
function __poly_aa_factor(_ed) {
  var _want = (is_real(_ed[$ "aa_k"]) && _ed.aa_k >= 1) ? _ed.aa_k : 1;
  return _want;
}

// Common scale for ALL offscreen 3D passes of a frame (pick, outline
// mask, hi-res scene). Mixed resolutions in one frame invalidate the
// whole WebGPU submit (the renderer's internal targets get reallocated
// mid-frame while recorded commands still reference them).
function __poly_pass_scale(_ed) {
  if (__poly_aa_mode(_ed) != "ssaa") return 1;
  var _w = max(1, _ed.scene_w);
  var _h = max(1, _ed.scene_h);
  var _k = __poly_aa_factor(_ed);
  var _kcap = min(4096 / _w, 4096 / _h);
  if (_k > _kcap) _k = max(_kcap, 1);
  return _k;
}

// Common offscreen 3D pass size for this frame.
function __poly_pass_size(_ed) {
  var _k = __poly_pass_scale(_ed);
  return [ max(1, floor(_ed.scene_w * _k)), max(1, floor(_ed.scene_h * _k)) ];
}

// True when the scratch surface exists at the size this frame needs
// (ensuring it as a side effect). All 3D passes of a frame must agree
// on one size; when false the frame falls back to matching 1x passes.
function __poly_hi_ready(_ed) {
  var _mode = __poly_aa_mode(_ed);
  var _need = undefined;

  if (_mode == "ssaa" && __poly_pass_scale(_ed) > 1) {
    _need = __poly_pass_size(_ed);
  } else if (_mode == "fxaa" || _mode == "smaa") {
    _need = [ max(1, round(_ed.scene_w)), max(1, round(_ed.scene_h)) ];
  }

  if (_need == undefined) return true;
  __poly_scene_hi_ensure(_ed, _need[0], _need[1]);
  return surface_exists(_ed[$ "scene_hi"])
    && surface_get_width(_ed.scene_hi) == _need[0]
    && surface_get_height(_ed.scene_hi) == _need[1];
}

// Renders live scene to scene surface (with optional supersampling:
// 3D renders hi-res into scene_hi, then downsamples; overlays compose
// at display res on scene_surf so gizmo lines and text stay sharp).
function __poly_scene_panel_render(_ed) {
  if (_ed == undefined || !_ed.active) return;
  if (!__poly_scene_panel_open(_ed)) return;
  if (_ed.rt == undefined || _ed.rt.scene == undefined || _ed.renderer == undefined) return;
  var _w = clamp(round(_ed.scene_w), 160, 1920);
  var _h = clamp(round(_ed.scene_h), 90, 1080);

  if (_w <= 0 || _h <= 0) return;

  if (!surface_exists(_ed.scene_surf) || surface_get_width(_ed.scene_surf) != _w || surface_get_height(_ed.scene_surf) != _h) {
    var _stable = variable_struct_exists(_ed, "scene_stable_w") && variable_struct_exists(_ed, "scene_stable_h") && _ed.scene_stable_w == _w && _ed.scene_stable_h == _h;

    if (!surface_exists(_ed.scene_surf) || _stable) {
      if (surface_exists(_ed.scene_surf)) __poly_surf_retire(_ed, _ed.scene_surf);
      _ed.scene_surf = surface_create(_w, _h);
      _ed.view_dirty = true;
    }
  }

  _ed.scene_stable_w = _w;
  _ed.scene_stable_h = _h;

  if (!surface_exists(_ed.scene_surf)) return;
  var _mode = __poly_aa_mode(_ed);
  var _k = (_mode == "ssaa") ? __poly_pass_scale(_ed) : 1;
  var _ukey = _mode + ":" + string(_k);

  if (!__poly_view_needs_render(_ed) && _ukey == _ed[$ "aa_used"]) return;
  _ed.view_dirty = false;
  _ed.aa_used = _ukey;

  if (_mode == "ssaa" && _k > 1 && _ed.hi_ready) {
    surface_set_target(_ed.scene_hi);
    draw_clear(c_black);
    _ed.renderer.render(_ed.rt.scene);
    surface_reset_target();
    surface_set_target(_ed.scene_surf);
    draw_clear(c_black);
    var _was_blend = gpu_get_blendenable();
    var _was_filter = gpu_get_texfilter();
    gpu_set_blendenable(false);
    gpu_set_texfilter(true);
    draw_surface_stretched(_ed.scene_hi, 0, 0, _w, _h);
    gpu_set_texfilter(_was_filter);
    gpu_set_blendenable(_was_blend);
    __poly_compose_viewport(_ed);
    surface_reset_target();
    return;
  }

  if ((_mode == "ssaa" && _k > 1) || (_mode == "fxaa" && shader_is_compiled(shPolygonEditorFXAA)) || (_mode == "smaa" && shader_is_compiled(shPolygonEditorSMAAEdge))) {
    // Scratch not ready at the right size (mode switch/resize/memory):
    // direct 1x render now, and retry ("pending" forces next frame).
    _ed.aa_used = "pending";
  }

  if (_mode == "smaa" && shader_is_compiled(shPolygonEditorSMAAEdge) && _ed.hi_ready) {
    // Raw 1x 3D into the scratch surface, SMAA edge/blend/resolve onto
    // scene_surf, then compose overlays on the resolved image (sharp).
    surface_set_target(_ed.scene_hi);
    draw_clear(c_black);
    _ed.renderer.render(_ed.rt.scene);
    surface_reset_target();

    if (__poly_smaa_resolve(_ed, _ed.scene_hi, _w, _h)) {
      surface_set_target(_ed.scene_surf);
      __poly_compose_viewport(_ed);
      surface_reset_target();
      return;
    }

    // Resolve failed: direct 1x render now, retry next frame.
    _ed.aa_used = "pending";
  }

  if (_mode == "fxaa" && shader_is_compiled(shPolygonEditorFXAA) && _ed.hi_ready) {
    // Raw 1x 3D into the scratch surface, FXAA-resolve onto scene_surf,
    // then compose overlays on the resolved image (they stay sharp).
    surface_set_target(_ed.scene_hi);
    draw_clear(c_black);
    _ed.renderer.render(_ed.rt.scene);
    surface_reset_target();

    if (__poly_fxaa_resolve(_ed, _ed.scene_hi, _w, _h)) {
      surface_set_target(_ed.scene_surf);
      __poly_compose_viewport(_ed);
      surface_reset_target();
      return;
    }

    // Resolve failed: direct 1x render now, retry next frame.
    _ed.aa_used = "pending";
  }

  surface_set_target(_ed.scene_surf);
  draw_clear(c_black);
  _ed.renderer.render(_ed.rt.scene);
  __poly_compose_viewport(_ed);
  surface_reset_target();
}

// Ensures the scratch surface exists at w,h (retiring the old one).
// Recreates on missing size; during active resizes keeps the old surface
// one frame (reallocating a 3D target every frame hazards pending
// submits) and reports not-ready so the caller falls back to direct.
// True only when the surface exists AT the requested size.
function __poly_scene_hi_ensure(_ed, _w, _h) {
  if (surface_exists(_ed[$ "scene_hi"]) && surface_get_width(_ed.scene_hi) == _w && surface_get_height(_ed.scene_hi) == _h) {
    _ed.hi_stable_w = _w;
    _ed.hi_stable_h = _h;
    return true;
  }

  var _stable = variable_struct_exists(_ed, "hi_stable_w") && variable_struct_exists(_ed, "hi_stable_h") && _ed.hi_stable_w == _w && _ed.hi_stable_h == _h;

  if (!surface_exists(_ed[$ "scene_hi"]) || _stable) {
    if (surface_exists(_ed[$ "scene_hi"])) __poly_surf_retire(_ed, _ed.scene_hi);
    _ed.scene_hi = surface_create(max(1, _w), max(1, _h));

    if (!surface_exists(_ed[$ "scene_hi"])) return false;


    _ed.hi_stable_w = _w;
    _ed.hi_stable_h = _h;
    return surface_get_width(_ed.scene_hi) == _w && surface_get_height(_ed.scene_hi) == _h;
  }

  _ed.hi_stable_w = _w;
  _ed.hi_stable_h = _h;
  return false;
}

// FXAA-resolves _src (raw 3D) onto scene_surf. False when unavailable.
function __poly_fxaa_resolve(_ed, _src, _w, _h) {
  static _u = -2;

  if (_u == -2) _u = shader_get_uniform(shPolygonEditorFXAA, "u_texel");
  if (_u < 0 || !surface_exists(_src) || !surface_exists(_ed.scene_surf)) return false;
  surface_set_target(_ed.scene_surf);
  draw_clear(c_black);
  var _was_blend = gpu_get_blendenable();
  var _was_filter = gpu_get_texfilter();
  gpu_set_blendenable(false);
  gpu_set_texfilter(true);
  shader_set(shPolygonEditorFXAA);
  shader_set_uniform_f(_u, 1.0 / max(_w, 1), 1.0 / max(_h, 1));
  draw_surface(_src, 0, 0);
  shader_reset();
  gpu_set_texfilter(_was_filter);
  gpu_set_blendenable(_was_blend);
  surface_reset_target();
  return true;
}

// Lazily loads the official SMAA LUTs from datafiles, baked 1:1 into
// surfaces. Area is 160x560 RG (linear), search is 64x16 R (point).
// The source sprites stay alive for the session: deleting one right after
// its blit destroys its texture while the copy may still be queued
// (WebGPU validation error + black LUT). Surfaces are re-baked after
// VRAM loss. False when the PNGs are missing or fail validation.
function __poly_smaa_luts(_ed) {
  if (!variable_struct_exists(_ed, "smaa_lut_sprs")) _ed.smaa_lut_sprs = [];

  if (array_length(_ed.smaa_lut_sprs) != 2
    || !sprite_exists(_ed.smaa_lut_sprs[0]) || sprite_get_width(_ed.smaa_lut_sprs[0]) != 160
  || !sprite_exists(_ed.smaa_lut_sprs[1]) || sprite_get_width(_ed.smaa_lut_sprs[1]) != 64) {
    for (var _i = 0, _n = array_length(_ed.smaa_lut_sprs); _i < _n; _i++) if (sprite_exists(_ed.smaa_lut_sprs[_i])) sprite_delete(_ed.smaa_lut_sprs[_i]);
    _ed.smaa_lut_sprs = [];
    var _dir = working_directory + "__PolygonEditor__/smaa/";

    if (!file_exists(_dir + "smaa_area.png") || !file_exists(_dir + "smaa_search.png")) return false;
    var _sa = sprite_add(_dir + "smaa_area.png", 1, false, false, 0, 0);
    var _ss = sprite_add(_dir + "smaa_search.png", 1, false, false, 0, 0);

    if (_sa < 0 || !sprite_exists(_sa) || sprite_get_width(_sa) != 160 || sprite_get_height(_sa) != 560 || sprite_get_number(_sa) != 1
    || _ss < 0 || !sprite_exists(_ss) || sprite_get_width(_ss) != 64 || sprite_get_height(_ss) != 16 || sprite_get_number(_ss) != 1) {
      if (_sa >= 0 && sprite_exists(_sa)) sprite_delete(_sa);
      if (_ss >= 0 && sprite_exists(_ss)) sprite_delete(_ss);
      return false;
    }

    _ed.smaa_lut_sprs = [ _sa, _ss ];
  }

  var _ok = true;

  if (!surface_exists(_ed[$ "smaa_lut_area"])
    && !__poly_smaa_lut_blit(_ed, "smaa_lut_area", _ed.smaa_lut_sprs[0], 160, 560)) _ok = false;
  if (!surface_exists(_ed[$ "smaa_lut_search"])
    && !__poly_smaa_lut_blit(_ed, "smaa_lut_search", _ed.smaa_lut_sprs[1], 64, 16)) _ok = false;
  return _ok;
}

// Copies a LUT sprite 1:1 into its surface (unfiltered, exact texels).
// The sprite itself is kept alive by the caller (see above).
function __poly_smaa_lut_blit(_ed, _field, _spr, _w, _h) {
  var _surf = surface_create(_w, _h);

  if (!surface_exists(_surf)) return false;
  var _was_blend = gpu_get_blendenable();
  var _was_filter = gpu_get_texfilter();
  gpu_set_blendenable(false);
  gpu_set_texfilter(false);
  surface_set_target(_surf);
  draw_clear_alpha(c_black, 0);
  draw_sprite(_spr, 0, 0, 0);
  surface_reset_target();
  gpu_set_texfilter(_was_filter);
  gpu_set_blendenable(_was_blend);

  if (!surface_exists(_surf) || surface_get_width(_surf) != _w || surface_get_height(_surf) != _h) return false;
  _ed[$ _field] = _surf;
  return true;
}

// Ensures one 1x SMAA scratch surface (edges/weights) at w,h.
// Same resize-stable dance as the hi scratch: during active resizes the
// old surface survives one frame and the caller falls back to direct.
function __poly_smaa_scratch(_ed, _field, _stable, _w, _h) {
  var _cur = _ed[$ _field];

  if (surface_exists(_cur) && surface_get_width(_cur) == _w && surface_get_height(_cur) == _h) {
    _ed[$ _stable] = { w: _w, h: _h };
    return true;
  }

  var _st = _ed[$ _stable];
  var _ok = is_struct(_st) && _st[$ "w"] == _w && _st[$ "h"] == _h;

  if (!surface_exists(_cur) || _ok) {
    if (surface_exists(_cur)) __poly_surf_retire(_ed, _cur);
    _ed[$ _field] = surface_create(max(1, _w), max(1, _h));

    if (!surface_exists(_ed[$ _field])) return false;
    _ed[$ _stable] = { w: _w, h: _h };
    return surface_get_width(_ed[$ _field]) == _w && surface_get_height(_ed[$ _field]) == _h;
  }

  _ed[$ _stable] = { w: _w, h: _h };
  return false;
}

// SMAA-resolves _src (raw 1x 3D) onto scene_surf via edge, blend-weights
// and neighborhood passes. False when unavailable (shaders, LUTs or
// scratch surfaces), so the caller falls back to a direct render.
function __poly_smaa_resolve(_ed, _src, _w, _h) {
  static _u_e = -2;
  static _u_b = -2;
  static _u_r = -2;
  static _s_area = -2;
  static _s_search = -2;
  static _s_blend = -2;
  _ed.smaa_err = "shaders";

  if (!shader_is_compiled(shPolygonEditorSMAAEdge)
    || !shader_is_compiled(shPolygonEditorSMAABlend)
    || !shader_is_compiled(shPolygonEditorSMAAResolve)) return false;
  _ed.smaa_err = "luts";

  if (!__poly_smaa_luts(_ed)) return false;
  _ed.smaa_err = "scratch";

  if (!surface_exists(_src) || !surface_exists(_ed.scene_surf)) return false;
  if (!__poly_smaa_scratch(_ed, "scene_smaa_e", "smaa_e_stable", _w, _h)) return false;
  if (!__poly_smaa_scratch(_ed, "scene_smaa_w", "smaa_w_stable", _w, _h)) return false;
  _ed.smaa_err = "samplers";
  if (_u_e == -2) _u_e = shader_get_uniform(shPolygonEditorSMAAEdge, "u_texel");
  if (_u_b == -2) _u_b = shader_get_uniform(shPolygonEditorSMAABlend, "u_texel");
  if (_u_r == -2) _u_r = shader_get_uniform(shPolygonEditorSMAAResolve, "u_texel");
  if (_s_area == -2) _s_area = shader_get_sampler_index(shPolygonEditorSMAABlend, "u_areaTex");
  if (_s_search == -2) _s_search = shader_get_sampler_index(shPolygonEditorSMAABlend, "u_searchTex");
  if (_s_blend == -2) _s_blend = shader_get_sampler_index(shPolygonEditorSMAAResolve, "u_blendTex");

  if (_u_e < 0 || _u_b < 0 || _u_r < 0 || _s_area < 0 || _s_search < 0 || _s_blend < 0) return false;
  var _tx = 1.0 / max(_w, 1);
  var _ty = 1.0 / max(_h, 1);
  var _was_blend = gpu_get_blendenable();
  var _was_filter = gpu_get_texfilter();
  gpu_set_blendenable(false);
  gpu_set_texfilter(true);

  // Pass 1: edges of the raw render.
  surface_set_target(_ed.scene_smaa_e);
  draw_clear(c_black);
  shader_set(shPolygonEditorSMAAEdge);
  shader_set_uniform_f(_u_e, _tx, _ty);
  draw_surface(_src, 0, 0);
  shader_reset();
  surface_reset_target();

  // Pass 2: blend weights from edges + LUTs.
  surface_set_target(_ed.scene_smaa_w);
  draw_clear(c_black);
  shader_set(shPolygonEditorSMAABlend);
  shader_set_uniform_f(_u_b, _tx, _ty);
  texture_set_stage(_s_area, surface_get_texture(_ed.smaa_lut_area));
  texture_set_stage(_s_search, surface_get_texture(_ed.smaa_lut_search));
  draw_surface(_ed.scene_smaa_e, 0, 0);
  shader_reset();
  surface_reset_target();

  // Pass 3: blend the raw render with the weights onto scene_surf.
  surface_set_target(_ed.scene_surf);
  draw_clear(c_black);
  shader_set(shPolygonEditorSMAAResolve);
  shader_set_uniform_f(_u_r, _tx, _ty);
  texture_set_stage(_s_blend, surface_get_texture(_ed.scene_smaa_w));
  draw_surface(_src, 0, 0);
  shader_reset();
  surface_reset_target();

  gpu_set_texfilter(_was_filter);
  gpu_set_blendenable(_was_blend);

  if (!surface_exists(_ed.scene_smaa_e) || !surface_exists(_ed.scene_smaa_w)) {
    _ed.smaa_err = "output lost";
    return false;
  }

  _ed.smaa_err = "ok";
  return true;
}
