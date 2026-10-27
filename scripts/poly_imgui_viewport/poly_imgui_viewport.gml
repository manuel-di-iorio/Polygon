// poly_imgui_viewport - Scene viewport panel + render to surface.

// ---------------------------------------------------------------------------
// Surface lifetime
// ---------------------------------------------------------------------------

// Shared surface lifetime for ImGui-displayed surfaces (viewport, anim preview):
// never surface_free() a texture ImGui may have recorded this frame - retire
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

// Renders live scene to scene surface.
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

  if (!__poly_view_needs_render(_ed)) return;
  _ed.view_dirty = false;

  surface_set_target(_ed.scene_surf);
  draw_clear(c_black);
  _ed.renderer.render(_ed.rt.scene);
  __poly_compose_viewport(_ed);
  surface_reset_target();
}
