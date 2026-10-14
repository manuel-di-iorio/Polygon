// poly_core — init, frame entry points, render queues, state, cleanup.

enum PolygonEditorTool {
  View = 0,
  Translate = 1,
  Rotate = 2,
  Scale = 3,
}

// ---------------------------------------------------------------------------
// State accessor and init
// ---------------------------------------------------------------------------

// Returns the editor state, or undefined when the editor object is absent.
// Lets the game call editor entry points unconditionally (drop-in safe).
function __poly_inst() {
  if (!variable_global_exists("poly_inst")) return undefined;
  return global.poly_inst;
}

// Copies known runtime hooks (never game instances) into editor-owned state.
// The live scene is kept as a non-owning ref for enable-time import.
function __poly_create_rt(_src) {
  var _rtc = { scene: GM3D_Scene.createEmpty() };

  if (variable_struct_exists(_src, "on_create")) _rtc.on_create = _src.on_create;
  if (variable_struct_exists(_src, "on_close")) _rtc.on_close = _src.on_close;
  if (variable_struct_exists(_src, "cam")) _rtc.cam = _src.cam;
  if (variable_struct_exists(_src, "scene")) _rtc.live_scene = _src.scene;
  return _rtc;
}

// Registers prefab entries from the adapter assets struct:
// { assetKey: { model, on_create? } }.
function __poly_create_assets(_src) {
  if (!variable_struct_exists(_src, "assets") || !is_struct(_src.assets)) return;
  var _keys = variable_struct_get_names(_src.assets);

  for (var _i = 0, _n = array_length(_keys); _i < _n; _i++) {
    var _k = _keys[_i];
    var _a = _src.assets[$ _k];

    if (!is_struct(_a) || _a.model == undefined) continue;
    poly_asset_add(_a.model, "prefab", _k, _a[$ "on_create"]);
  }
}

// Rebuilds the editor scene from the live game scene (mirror).
// Runs on every enable: wrappers with ids are preserved, bare roots get
// fresh ids. With no live scene (or no live roots), defaults spawn.
function __poly_import_live(_ed) {
  __poly_drop_preview_clear(_ed);
  var _tracked = __poly_root_tracked(_ed);

  for (var _d = 0, _nd = array_length(_tracked); _d < _nd; _d++) __poly_destroy_subtree(_tracked[_d]);
  _ed.rt.scene.update(0);
  __poly_reg_clear(_ed);
  var _nodes = undefined;

  if (variable_struct_exists(_ed.rt, "live_scene") && _ed.rt.live_scene != undefined) _nodes = _ed.rt.live_scene.getNodes();

  if (_nodes != undefined) for (var _i = 0, _n = array_length(_nodes); _i < _n; _i++) __poly_track_adopt_auto(_ed, _nodes[_i]);

  _ed.rt.scene.update(0);

  if (__poly_gamecam_resolve(_ed) == undefined) __poly_gamecam_ensure(_ed);
  if (__poly_light_count(_ed) == 0) __poly_default_sun(_ed);
  if (__poly_env_node(_ed) == undefined) __poly_create_env(_ed);
  _ed.rt.scene.update(0);
  __poly_seq_reseed(_ed);
}


// ---------------------------------------------------------------------------
// Frame entry points
// ---------------------------------------------------------------------------





// ---------------------------------------------------------------------------
// Render queues
// ---------------------------------------------------------------------------

// Shoots one startup thumbnail and finishes the queue when drained.
function __poly_thumbs_pump(_ed) {
  if (_ed.thumbs_done != true) __poly_capture_thumbnails();

  if (_ed.thumb_initializing == true && is_array(_ed.thumb_queue) && array_length(_ed.thumb_queue) > 0) {
    var _entry = array_pop(_ed.thumb_queue);
    var _spr = __poly_thumb_shoot(_ed, _ed.thumb_stage, _entry);

    if (sprite_exists(_spr)) {
      _entry.thumb = _spr;
      _entry.thumb_owned = true;
    }

    if (array_length(_ed.thumb_queue) == 0) {
      __poly_thumb_free_stage(_ed.thumb_stage);
      _ed.thumb_stage = undefined;
      _ed.thumb_initializing = false;
      _ed.thumbs_done = true;
    }

    return;
  }

  if (variable_struct_exists(_ed, "thumb_queue") && is_array(_ed.thumb_queue) && array_length(_ed.thumb_queue) > 0) {
    var _now = current_time;
    var _last = (variable_struct_exists(_ed, "thumb_last_ms") && is_real(_ed.thumb_last_ms)) ? _ed.thumb_last_ms : -100000;

    if (_now - _last >= 500) {
      _ed.thumb_last_ms = _now;
      __poly_thumb_recap_one(_ed, array_pop(_ed.thumb_queue));
    }
  }
}

// Frees one expired thumbnail graveyard entry.
function __poly_thumb_graveyard_free(_entry) {
  if (sprite_exists(_entry.spr)) sprite_delete(_entry.spr);
}

// Merges one rendered material preview into the cache (one per frame).
function __poly_mat_queue_merge(_ed, _key, _spr) {
  for (var _i = 0, _n = array_length(_ed.mat_pv); _i < _n; _i++) {
    if (_ed.mat_pv[_i].key == _key) {
      if (sprite_exists(_ed.mat_pv[_i].spr)) {
        array_push(_ed.thumb_graveyard, { spr: _ed.mat_pv[_i].spr, ttl: 5 });
      }

      _ed.mat_pv[_i].spr = _spr;
      __poly_mat_pv_put(_ed, _key, _spr);
      return;
    }
  }

  array_push(_ed.mat_pv, { key: _key, spr: _spr });
  __poly_mat_pv_put(_ed, _key, _spr);
}

// Renders at most one queued material preview per frame.
function __poly_mat_queue_pump(_ed) {
  if (!variable_struct_exists(_ed, "mat_queue") || !is_array(_ed.mat_queue) || array_length(_ed.mat_queue) == 0) return;
  // Bound auxiliary 3D rendering to one material preview per frame.
  var _req = array_pop(_ed.mat_queue);
  var _spr = __poly_mat_thumb_render(_ed, _req.mat);

  if (sprite_exists(_spr)) {
    __poly_mat_queue_merge(_ed, _req.key, _spr);
  } else {
    if (!variable_struct_exists(_ed, "mat_fail") || !is_struct(_ed.mat_fail)) {
      _ed.mat_fail = {};
    }

    _ed.mat_fail[$ _req.key] = true;
  }
}

// ---------------------------------------------------------------------------
// Viewport compose
// ---------------------------------------------------------------------------

// Draws the rubber-band rectangle into the scene surface.
function __poly_compose_rect(_ed) {
  static _fill = make_colour_rgb(90, 140, 250);
  if (_ed.rect == undefined || !_ed.rect.on || !variable_struct_exists(_ed, "svp") || !is_struct(_ed.svp)) return;
  var _r = __poly_rect_norm(_ed.rect);
  var _ox = _ed.svp.x;
  var _oy = _ed.svp.y;
  draw_set_alpha(0.15);
  draw_set_color(_fill);
  draw_rectangle(_r.x0 - _ox, _r.y0 - _oy, _r.x1 - _ox, _r.y1 - _oy, false);
  draw_set_alpha(1);
  draw_rectangle(_r.x0 - _ox, _r.y0 - _oy, _r.x1 - _ox, _r.y1 - _oy, true);
}

// Draws the fly-speed notice into the scene surface.
function __poly_compose_speedtip(_ed, _vp) {
  static _bg = make_colour_rgb(22, 28, 38);
  static _edge = make_colour_rgb(90, 103, 120);
  static _bar = make_colour_rgb(80, 210, 190);
  static _txt = make_colour_rgb(170, 184, 199);
  if (!(_ed.cam_speed_notice > 0)) return;
  var _w = 174;
  var _h = 36;
  var _x = clamp(_vp.winW - _w - 12, 8, _vp.winW - _w - 8);
  var _y = clamp(_vp.winH - _h - 12, 8, _vp.winH - _h - 8);
  var _al = min(1, _ed.cam_speed_notice * 2);
  draw_set_alpha(_al * 0.94);
  draw_set_color(_bg);
  draw_rectangle(_x, _y, _x + _w, _y + _h, true);
  draw_set_alpha(_al * 0.8);
  draw_set_color(_edge);
  draw_rectangle(_x, _y, _x + _w, _y + _h, false);
  draw_set_alpha(_al);
  draw_set_color(_bar);
  draw_rectangle(_x, _y + 5, _x + 3, _y + _h - 5, true);
  draw_set_color(_txt);
  draw_text_transformed(_x + 12, _y + 11, "FLY SPEED", 0.8, 0.8, 0);
  draw_set_halign(fa_right);
  draw_set_color(c_white);
  draw_text(_x + _w - 12, _y + 9, string_format(_ed.cam_fly_speed, 0, 1));
  draw_set_halign(fa_left);
}

// Renders viewport overlays into scene surface (target already set).
function __poly_compose_viewport(_ed) {
  var _vp = __poly_viewport_cached(_ed);
  var _was_blend = gpu_get_blendenable();
  var _was_mode = gpu_get_blendmode_ext_sepalpha();
  gpu_set_blendenable(true);
  gpu_set_blendmode_ext_sepalpha(bm_src_alpha, bm_inv_src_alpha, bm_inv_dest_alpha, bm_one);
  __poly_outline_composite(_ed);

  if (variable_struct_exists(_ed, "outline") && is_struct(_ed.outline) && _ed.outline.mass_active == true && _ed.vis_outline != false) __poly_outline_mass_draw(_vp, _ed.outline);
  __poly_gizmo_draw(_ed, _vp);
  __poly_overlay_draw(_ed, _vp);
  __poly_viewcube_draw(_ed);
  __poly_compose_rect(_ed);

  draw_set_alpha(1);
  draw_set_color(c_white);
  draw_set_halign(fa_left);
  draw_set_valign(fa_top);

  __poly_compose_speedtip(_ed, _vp);

  draw_set_alpha(1);
  draw_set_color(c_white);
  draw_set_halign(fa_left);
  draw_set_valign(fa_top);

  // Feather ignore GM1020
  gpu_set_blendmode_ext_sepalpha(_was_mode);
  gpu_set_blendenable(_was_blend);
}

// ---------------------------------------------------------------------------
// Window UI and cleanup
// ---------------------------------------------------------------------------

// Draws the drag ghost file name outside the viewport.
function __poly_draw_drag_ghost(_ed) {
  static _ghost = make_colour_rgb(90, 140, 250);
  if (!(_ed.drag_lib != undefined && _ed.drag_moved)) return;
  var _mx = device_mouse_x_to_gui(0);
  var _my = device_mouse_y_to_gui(0);

  if (__poly_drag_in_viewport(_ed, _mx, _my)) return;
  draw_set_color(_ghost);
  draw_rectangle(_mx + 14, _my + 10, _mx + 150, _my + 32, false);
  draw_set_color(c_white);
  draw_set_valign(fa_middle);
  draw_text(_mx + 22, _my + 21, __poly_display_from_key(_ed.drag_lib.asset.key));
  draw_set_valign(fa_top);
}


// Frees the surface graveyard.
function __poly_graveyard_free(_ed) {
  if (!variable_struct_exists(_ed, "surf_graveyard") || !is_array(_ed.surf_graveyard)) return;
  for (var _i = 0, _n = array_length(_ed.surf_graveyard); _i < _n; _i++) if (surface_exists(_ed.surf_graveyard[_i].surf)) surface_free(_ed.surf_graveyard[_i].surf);
  _ed.surf_graveyard = [];
}


// ---------------------------------------------------------------------------
// Background and view sizes
// ---------------------------------------------------------------------------

// Applies dark background and hides layer.
function __poly_bg_apply(_ed) {
  if (_ed == undefined) return;
  if (!variable_struct_exists(_ed, "prev_win_colour") || _ed.prev_win_colour == undefined) _ed.prev_win_colour = window_get_colour();
  window_set_colour(#181825);
  var _layer = layer_get_id("Background");
  _ed.bg_layer = _layer;

  if (_layer != -1) layer_set_visible(_layer, false);
}

// Restores previous window background color.
function __poly_bg_restore(_ed) {
  if (_ed == undefined) return;

  if (variable_struct_exists(_ed, "prev_win_colour") && _ed.prev_win_colour != undefined) {
    window_set_colour(_ed.prev_win_colour);
    _ed.prev_win_colour = undefined;
  }

  if (variable_struct_exists(_ed, "bg_layer") && _ed.bg_layer != undefined && _ed.bg_layer != -1) layer_set_visible(_ed.bg_layer, true);
  _ed.bg_layer = undefined;
}

// Synchronizes application surface to window size.
function __poly_view_sync(_ed) {
  var _ww = window_get_width();
  var _wh = window_get_height();

  if (_ww <= 0 || _wh <= 0) return;

  if (!variable_struct_exists(_ed, "view_sync")) {
    _ed.view_sync = { w: -1, h: -1 };
  }

  if (_ed.view_sync.w == _ww && _ed.view_sync.h == _wh) return;
  _ed.view_sync.w = _ww;
  _ed.view_sync.h = _wh;

  if (surface_exists(application_surface)) surface_resize(application_surface, _ww, _wh);
  display_set_gui_size(_ww, _wh);
}

// Saves current surface and GUI sizes.
function __poly_view_save(_ed) {
  var _view = { sw: -1, sh: -1, gw: -1, gh: -1 };

  if (surface_exists(application_surface)) {
    _view.sw = surface_get_width(application_surface);
    _view.sh = surface_get_height(application_surface);
  }

  _view.gw = display_get_gui_width();
  _view.gh = display_get_gui_height();
  _ed.view_prev = _view;
}

// Restores previously saved surface sizes.
function __poly_view_restore(_ed) {
  if (_ed == undefined || !is_struct(_ed.view_prev)) return;
  var _view = _ed.view_prev;
  _ed.view_prev = undefined;

  if (_view.sw > 0 && _view.sh > 0 && surface_exists(application_surface)) surface_resize(application_surface, _view.sw, _view.sh);
  if (_view.gw > 0 && _view.gh > 0) display_set_gui_size(_view.gw, _view.gh);
}

// ---------------------------------------------------------------------------
// Active state and public API
// ---------------------------------------------------------------------------

// Tears down editor chrome when closing.
function __poly_deactivate(_ed) {
  __poly_drop_preview_clear(_ed);
  __poly_view_restore(_ed);
  __poly_bg_restore(_ed);
  __poly_grid_remove(_ed);
  __poly_sky_remove(_ed);
  __poly_cameras_restore(_ed);

  if (_ed.viewcam != undefined) {
    var _vcc = _ed.viewcam.getCameraComponent();

    if (_vcc != undefined) _vcc.setEnabled(false);
  }

  __poly_cam_home(_ed);
  _ed.show_shadows = true;
  __poly_shadowpreview_apply(_ed);
  _ed.show_unlit = false;
  __poly_unlit_apply(_ed);

  if (variable_struct_exists(_ed.rt, "on_close")) _ed.rt.on_close();
}

// Sets up editor chrome when opening (fresh mirror of the live scene).
function __poly_activate(_ed) {
  __poly_view_save(_ed);
  __poly_view_sync(_ed);
  __poly_import_live(_ed);
  __poly_bg_apply(_ed);
  __poly_grid_ensure(_ed);
  __poly_cameras_mute(_ed);
  __poly_viewcam_seed(_ed);
  __poly_sel_clear(_ed);
  __poly_history_clear(_ed);
  _ed.scene_file = "";
  _ed.dirty = false;
  _ed.open_snapshot = __poly_serialize_scene(_ed);
}

// Toggles editor active state with setup.
function __poly_set_active(_ed, _on) {
  if (_ed == undefined) return;
  var _was = _ed.active;
  _ed.active = _on;
  global.poly_active = _on;

  if (_was && !_on) {
    __poly_deactivate(_ed);
  } else if (!_was && _on) {
    __poly_activate(_ed);
  }
}




// ---------------------------------------------------------------------------
// Editor state
// ---------------------------------------------------------------------------

// Sub-state constructors (split of the former __poly_create_state literal;
// same fields, same defaults — only grouped for readability).
function __poly_state_giz() {
  return {
    tool: PolygonEditorTool.Translate,
    hover: -1,
    drag: -1,
    size: 120,
    starts: [],
    pivot: undefined,
    dir: undefined,
    axis_idx: 0,
    plane_n: undefined,
    center: false,
    planar: false,
    world_len: 1,
    start_hit: undefined,
    mx0: 0,
    my0: 0,
    piv_sx: 0,
    piv_sy: 0,
    rot_mx: 0,
    rot_my: 0,
    rot_tx: 1,
    rot_ty: 0,
    total_ang: 0,
    display_ang: 0,
    len: 1,
    len_key: undefined,
    orient: 1,
    pivot_mode: 0,
    sector_t0: 0,
  };
}

function __poly_state_imgui() {
  return {
    cond: ImGuiCond.FirstUseEver,
    style_init: false,
    win_assets: { open: true },
    win_hier: { open: true },
    win_insp: { open: true },
    win_toolbar: { open: true },
    win_cube: { open: true },
    win_scene: { open: true },
    reset_layout: false,
    filter: "",
    scene_filter: "",
    ax_active: {},
    ax_draft: {},
    ax_before: {},
    flt_active: {},
    flt_draft: {},
    show_kind: { m: true, l: true, c: true, e: true },
    scene_eye_idx: -1,
    scene_eye_till: 0,
  };
}

function __poly_state_thumb() {
  return {
    thumb_queue: [],
    thumb_graveyard: [],
    surf_graveyard: [],
    mat_pv: [],
    mat_pv_map: {},
    mat_queue: [],
    mat_sphere: undefined,
    anim_stage: undefined,
    anim_pv: undefined,
    anim_surf: undefined,
    anim_ui: undefined,
  };
}

function __poly_state_view() {
  return {
    svp: { x: 0, y: 0, w: 1366, h: 768 },
    svp_hover: false,
    vp: undefined,
    viewcam: undefined,
    cam_anim: undefined,
    cam_home: undefined,
    cam_orbit: false,
    cam_pan: false,
    cam_zoom: false,
    cam_fly: false,
    cam_orbit_target: undefined,
    cam_orbit_radius: 10,
    cam_zoom_target: undefined,
    cam_fly_speed: 5,
    cam_speed_notice: 0,
  };
}

// Creates default editor state struct.
function __poly_create_state(_rt) {
  var _giz = __poly_state_giz();
  var _imgui = __poly_state_imgui();
  var _thumb = __poly_state_thumb();
  var _view = __poly_state_view();
  var _ed = {
    rt: _rt,
    renderer: new GM3D_Renderer(),
    cfg: {
      ndc_yup: true,
      keys: {
        tool_view: ord("Q"),
        tool_move: ord("W"),
        tool_rotate: ord("E"),
        tool_scale: ord("R"),
        del: vk_delete,
        save: ord("S"),
        dupe: ord("D"),
        close: ord("W"),
        new_scene: ord("N"),
        cancel: vk_escape,
        focus: ord("F"),
        undo: ord("Z"),
        redo: ord("Y"),
        rename: vk_f2,
        load: ord("L"),
        pivot: ord("Z"),
        orient: ord("X"),
        snap: 92,
      },
      snap: { on: false, pos: 0.5, rot: 15 },
      gizmo_px: 90,
      duplicate_offset: 0.6,
    },
    active: false,
    dirty: false,
    assets: [],
    thumbs_done: false,
    thumb_initializing: false,
    sel: [],
    reg: {},
    id_seq: 1,
    asset_meta: {},
    models_bg: undefined,
    models_mdown: false,
    hier_rect: undefined,
    hier_mdown: false,
    hier_rows: [],
    hier_row_y: {},
    hier_row_h: 0,
    ndc_yup: true,
    giz: _giz,
    scene_click_idx: -1,
    scene_click_time: -10000,
    scene_anchor: undefined,
    rename_name: undefined,
    rename_id: undefined,
    confirm: undefined,
    delete_confirm: undefined,
    about: undefined,
    scene_dlg: undefined,
    show_fps: false,
    undo: [],
    redo: [],
    imgui: _imgui,
    input_owner: undefined,
    drag_lib: undefined,
    drag_moved: false,
    drag_preview: undefined,
    lib_sel: undefined,
    thumb_queue: _thumb.thumb_queue,
    thumb_graveyard: _thumb.thumb_graveyard,
    surf_graveyard: _thumb.surf_graveyard,
    mat_pv: _thumb.mat_pv,
    mat_pv_map: _thumb.mat_pv_map,
    mat_queue: _thumb.mat_queue,
    mat_sphere: _thumb.mat_sphere,
    anim_stage: _thumb.anim_stage,
    anim_pv: _thumb.anim_pv,
    anim_surf: _thumb.anim_surf,
    anim_ui: _thumb.anim_ui,
    rect: undefined,
    press_vp: false,
    press_x: 0,
    press_y: 0,
    viewpan_moved: false,
    scene_surf: undefined,
    scene_hi: undefined,
    aa_mode: "ssaa",
    aa_k: 2,
    aa_used: 1,
    scene_stable_w: -1,
    scene_stable_h: -1,
    view_dirty: true,
    view_key: undefined,
    scene_w: 480,
    scene_h: 270,
    svp: _view.svp,
    svp_hover: _view.svp_hover,
    cube_armed: undefined,
    cube_hover: undefined,
    cube_face: undefined,
    cube_moved: false,
    cube_gx: 0,
    cube_gy: 0,
    cube_off: [ 48, 48 ],
    vp: _view.vp,
    viewcam: _view.viewcam,
    cam_anim: _view.cam_anim,
    cam_home: _view.cam_home,
    cam_orbit: _view.cam_orbit,
    cam_pan: _view.cam_pan,
    cam_zoom: _view.cam_zoom,
    cam_fly: _view.cam_fly,
    cam_orbit_target: _view.cam_orbit_target,
    cam_orbit_radius: _view.cam_orbit_radius,
    cam_zoom_target: _view.cam_zoom_target,
    cam_fly_speed: _view.cam_fly_speed,
    cam_speed_notice: _view.cam_speed_notice,
    hist_before: undefined,
    wrap: undefined,
    cube_geom: undefined,
    scene_file: "",
    open_snapshot: undefined,
    snap_on: false,
    snap_pos: 0.5,
    snap_rot: 15,
    snap_to_grid: true,
    snap_x: true,
    snap_y: true,
    snap_z: true,
    show_grid: true,
    show_shadows: true,
    show_unlit: false,
    show_hidden: false,
    vis_sky: true,
    vis_outline: true,
    unlit_quiet: false,
    unlit_orig: [],
    magenta_mat: undefined,
    magenta_mat_skin: undefined,
    grid_step: 1,
    grid_node: undefined,
    grid_src: undefined,
    grid_mat: undefined,
    sky_node: undefined,
    sky_src: undefined,
    sky_mat: undefined,
    prev_win_colour: undefined,
    bg_layer: undefined,
    gw: 1366,
    gh: 768,
  };
  return _ed;
}

// ---------------------------------------------------------------------------
// Step
// ---------------------------------------------------------------------------

// Processes input, cameras, and interactions.
function __poly_step(_ed, _dt) {
  _ed.gw = max(320, display_get_gui_width());
  _ed.gh = max(200, display_get_gui_height());
  var _keys = _ed.cfg.keys;

  if (!_ed.active) return;
  if (keyboard_check_pressed(vk_f9)) _ed.show_fps = !_ed.show_fps;
  __poly_view_sync(_ed);

  if (_ed.open_snapshot == undefined && _ed.dirty != true) _ed.open_snapshot = __poly_serialize_scene(_ed);
  // Chunked scene loads progress here (even with the Load dialog open).
  if (variable_struct_exists(_ed, "load_job") && is_struct(_ed.load_job)) __poly_load_scene_pump(_ed);
  var _input = __poly_input_context(_ed, _keys);
  var _vp = _input.vp;
  _ed.vp = _vp;

  var _modal = _ed.confirm != undefined || _ed.about != undefined || _ed.scene_dlg != undefined;

  if (_modal) {
    // A running chunked load owns its dialog: ESC must not kill it
    // mid-load (the scene would be left half-built).
    var _loading = variable_struct_exists(_ed, "load_job") && is_struct(_ed.load_job);

    if (!_loading && !_input.typing && keyboard_check_pressed(_keys.cancel)) {
      _ed.confirm = undefined;
      _ed.about = undefined;
      _ed.scene_dlg = undefined;
    }

    return;
  }

  var _camera_owner_ok = _input.owner == undefined || __poly_input_owner_is_camera(_input.owner);
  _input.camera_keys = (_input.typing == false || (keyboard_check(vk_alt) && !_input.text_input)) && _camera_owner_ok;
  _input.camera_viewport = _input.vin && _camera_owner_ok;

  if (!_input.camera_viewport && keyboard_check(vk_alt)) _input.camera_viewport = _camera_owner_ok && __poly_drag_in_viewport(_ed, _input.mx, _input.my);
  _input.camera_zoom = _input.camera_viewport && _ed.drag_lib == undefined && _camera_owner_ok;
  __poly_cam_fly(_ed, _input, _dt);
  _input.owner = __poly_input_owner_sync(_ed);
  _input.gesture_active = _input.owner != undefined && !__poly_input_owner_is_camera(_input.owner);
  __poly_cam_anim_step(_ed, _dt);
  __poly_grid_ensure(_ed);
  __poly_grid_follow(_ed);
  __poly_sky_ensure(_ed);
  __poly_sky_sync(_ed);

  __poly_step_hotkeys(_ed, _input);
  __poly_step_cancel(_ed, _input);

  if (__poly_step_gizmo(_ed, _input)) return;
  if (__poly_step_libdrop(_ed, _input)) return;
  if (__poly_step_rect(_ed, _input)) return;
  __poly_step_hover(_ed, _input);
}

// ---------------------------------------------------------------------------
// Drag preview
// ---------------------------------------------------------------------------

// Spawns the drag preview wrapper on first update (model inside,
// so commit registers an already-wrapped node).
function __poly_drop_preview_spawn(_ed, _asset, _spawn) {
  if (_asset == undefined || _asset.model == undefined) return undefined;
  var _wrap = __poly_spawn(_ed, {
    kind: "instance",
    asset: _asset,
    model: _asset.model,
    scale: _spawn.sca,
    rot: _spawn.rot,
    id: __poly_wrap_new(_ed),
    skip_hook: true,
    skip_register: true,
  });

  if (_wrap == undefined) return undefined;
  _ed.drag_preview = _wrap;
  return _wrap;
}

// Updates asset drag preview position.
function __poly_drop_preview_update(_ed, _drop) {
  if (_ed == undefined || _ed.drag_lib == undefined || _drop == undefined) return;
  if (_ed.drag_preview == undefined) __poly_drop_preview_spawn(_ed, _ed.drag_lib.asset, __poly_spawn_apply(_ed.drag_lib.asset));
  var _pv = _ed.drag_preview;

  if (_pv == undefined) return;
  _pv.setLocalPosition(new GM3D_Vec3(_drop.x, _drop.y, _drop.z));

  _ed.rt.scene.update(0);
}

// Removes asset drag preview node.
function __poly_drop_preview_clear(_ed) {
  if (_ed == undefined) return;

  if (_ed.drag_preview != undefined) {
    __poly_destroy_subtree(_ed.drag_preview);
    _ed.drag_preview = undefined;

    if (_ed.rt != undefined && _ed.rt.scene != undefined) _ed.rt.scene.update(0);
  }
}
