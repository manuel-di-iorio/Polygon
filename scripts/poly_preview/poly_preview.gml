// poly_preview — offscreen preview stages (thumbnails, material spheres, animation hover popups).

// ---------------------------------------------------------------------------
// Stage lifecycle
// ---------------------------------------------------------------------------

// Builds a throwaway scene, renderer and framing camera for thumbnails.
function __poly_thumb_make_stage() {
  var _ts = GM3D_Scene.createEmpty();

  if (_ts == undefined) return undefined;
  var _renderer = new GM3D_Renderer();

  if (_renderer == undefined) {
    _ts.destroy();
    return undefined;
  }

  var _env = _ts.createNode("__thumb_env");
  var _envc = new GM3D_EnvironmentVolumeComponent();
  _env.addComponent(_envc);
  _envc.setSize(new GM3D_Vec3(20000, 20000, 20000));
  _envc.setAmbientColor(make_colour_rgb(70, 70, 85));
  _envc.setFogEnabled(false);
  var _sun = _ts.createNode("__thumb_sun");
  var _sunc = new GM3D_LightComponent();
  _sun.addComponent(_sunc);
  _sunc.setType(GM3D_ELightType.Directional);
  _sunc.setColor(c_white);
  _sunc.setIntensity(1.0);
  _sunc.setShadowEnabled(false);
  _sunc.setShadowResolution(1024);
  _sunc.setShadowDistance(30.0);
  _sunc.setShadowNormalOffset(0.05);
  // Raised key light, matching the demo sun so thumbs look like the scene.
  var _sun_dir = new GM3D_Vec3(0.35, 0.8, 0.45);
  _sun_dir.normalize();
  _sun.setLocalRotation(GM3D_Quaternion.fromLookRotation(_sun_dir, GM3D_Vec3.up()).normalizeSafe(0.000001));
  var _cam = _ts.createNode("__thumb_cam");
  var _camc = new GM3D_CameraComponent();
  _cam.addComponent(_camc);
  _camc.setProjection(GM3D_ECameraProjection.Perspective);
  _camc.setFovY(degtorad(40));
  _camc.setNear(0.1);
  _camc.setFar(10000);
  _camc.setScreenRect([ 0.0, 0.0, 1.0, 1.0 ]);
  _camc.setEnabled(true);
  return { ts: _ts, renderer: _renderer, cam: _cam };
}

// Frees a thumbnail stage built by __poly_thumb_make_stage.
function __poly_thumb_free_stage(_st) {
  if (!is_struct(_st)) return;
  if (_st.ts != undefined) _st.ts.destroy();
  _st.renderer = undefined;
}

// Returns a persistent preview stage cached on _ed under _key.
function __poly_pv_stage_cached(_ed, _key) {
  if (variable_struct_exists(_ed, _key) && is_struct(_ed[$ _key])) {
    var _hit = _ed[$ _key];

    if (_hit.ts != undefined && _hit.renderer != undefined && _hit.cam != undefined) return _hit;
  }

  var _st = __poly_thumb_make_stage();

  if (_st == undefined) return undefined;
  _ed[$ _key] = _st;
  return _st;
}

// Frees editor-captured thumbnails, keeping caller-owned ones.
function __poly_thumbs_free(_ed) {
  if (_ed == undefined) return;

  if (is_array(_ed.assets)) {
    for (var _i = 0, _n = array_length(_ed.assets); _i < _n; _i++) {
      var _entry = _ed.assets[_i];

      if (!is_struct(_entry) || !variable_struct_exists(_entry, "thumb_owned") || _entry.thumb_owned != true) continue;
      if (sprite_exists(_entry.thumb)) sprite_delete(_entry.thumb);
      _entry.thumb = -1;
      _entry.thumb_owned = undefined;
    }
  }

  if (variable_struct_exists(_ed, "thumb_stage") && is_struct(_ed.thumb_stage)) __poly_thumb_free_stage(_ed.thumb_stage);
  _ed.thumb_stage = undefined;
  _ed.thumb_queue = [];
  _ed.thumb_initializing = false;
}

// ---------------------------------------------------------------------------
// Spawn and shoot
// ---------------------------------------------------------------------------

// Clones one material with the editor lit shader (skips magenta fallbacks).
function __poly_pv_clone_lit(_ed, _comp, _skinned) {
  var _mat = _comp.getMaterial();

  if (_mat == undefined || _mat == _ed.magenta_mat || _mat == _ed.magenta_mat_skin) return;
  var _clone_fn = _mat[$ "clone"];

  if (_clone_fn == undefined) return;
  var _clone = method(_mat, _clone_fn)();

  if (_clone == undefined) return;
  _clone.setShader(GM3D_ERenderPass.Forward, _skinned ? shPolygonEditorLitSkin : shPolygonEditorLit);
  _comp.setMaterial(_clone);
}

// Spawns a model into a preview stage at origin with editor lit shaders.
// _rot_euler is [x, y, z] degrees or undefined; _asset is passed to on_create.
function __poly_pv_spawn_lit(_ed, _st, _model, _rot_euler = undefined, _asset = "") {
  var _node = _model.spawnInto(_st.ts, undefined);

  if (_node == undefined) return undefined;
  _node.setLocalPosition(new GM3D_Vec3(0, 0, 0));
  _node.setLocalScale(new GM3D_Vec3(1, 1, 1));

  if (is_array(_rot_euler) && array_length(_rot_euler) >= 3) _node.setLocalRotation(__poly_euler_to_quat(degtorad(_rot_euler[0]), degtorad(_rot_euler[1]), degtorad(_rot_euler[2])));
  __poly_magenta_fix(_ed, _node);

  if (variable_struct_exists(_ed.rt, "on_create")) _ed.rt.on_create(_node, _asset, _model, _node.name);
  // Previews always use the editor lit shaders (never custom ones).
  var _comps = [];
  __poly_walk_collect_tree(_node, _comps);

  for (var _c = 0, _n = array_length(_comps); _c < _n; _c++) __poly_pv_clone_lit(_ed, _comps[_c].comp, _comps[_c].skinned);
  return _node;
}

// Renders the current stage content to a new _size px sprite (undefined on failure).
function __poly_pv_shoot_sprite(_st, _size) {
  var _surf = surface_create(_size, _size);

  if (_surf == undefined || !surface_exists(_surf)) return undefined;
  surface_set_target(_surf);
  draw_clear_alpha(c_black, 0);
  _st.renderer.render(_st.ts);
  surface_reset_target();
  var _spr = sprite_create_from_surface(_surf, 0, 0, _size, _size, false, true, 0, 0);

  if (surface_exists(_surf)) surface_free(_surf);
  return sprite_exists(_spr) ? _spr : undefined;
}

// Aims a preview camera at a center from a back direction at distance.
function __poly_aim_cam(_cam, _ctr, _back, _dist) {
  _cam.setLocalPosition(new GM3D_Vec3(_ctr.x + _back.x * _dist, _ctr.y + _back.y * _dist, _ctr.z + _back.z * _dist));
  var _pos = _cam.getLocalPosition();
  var _fwd = new GM3D_Vec3(_pos.x - _ctr.x, _pos.y - _ctr.y, _pos.z - _ctr.z);
  _fwd.normalize();
  var _up = GM3D_Vec3.up();

  if (abs(_fwd.dot(_up)) >= 0.999) _up = GM3D_Vec3.forward();
  var _rot = GM3D_Quaternion.fromLookRotation(_fwd, _up);
  _cam.setLocalRotation(_rot.normalizeSafe(0.000001));
}

// Frames a library model for thumbnail capture.
function __poly_thumb_frame(_cam, _model) {
  var _ctr = new GM3D_Vec3(0, 1, 0);
  var _rad = 2.0;
  var _bs = _model.getBoundingSphere();

  if (is_struct(_bs) && variable_struct_exists(_bs, "origin") && variable_struct_exists(_bs, "radius")) {
    var _c = _bs.origin;
    _ctr = new GM3D_Vec3(_c.x, _c.y, _c.z);
    _rad = max(_bs.radius, 0.1);
  }

  var _back = new GM3D_Vec3(1, 0.55, 1.25);
  _back.normalize();
  var _tan = max(tan(degtorad(20)), 0.001);
  var _dist = max(_rad * 1.15 * sqrt(1 + _tan * _tan) / _tan, 1.5);
  __poly_aim_cam(_cam, _ctr, _back, _dist);
}

// Frames the editor preview sphere tightly (exact r=0.5 at origin: the
// model bounds are AABB-based and would leave the sphere at ~60%).
function __poly_thumb_frame_tight(_cam) {
  var _back = new GM3D_Vec3(1, 0.55, 1.25);
  _back.normalize();
  var _tan = max(tan(degtorad(20)), 0.001);
  var _radius = 0.5;
  var _dist = max(_radius * 1.25 * sqrt(1 + _tan * _tan) / _tan, 1.5);
  __poly_aim_cam(_cam, new GM3D_Vec3(0, 0, 0), _back, _dist);
}

// ---------------------------------------------------------------------------
// Asset thumbnails
// ---------------------------------------------------------------------------

// Renders one asset thumbnail (256px) applying its spawn rotation.
// Returns the sprite, or -1 when it cannot be rendered.
function __poly_thumb_shoot(_ed, _st, _entry) {
  var _size = 256;

  if (!is_struct(_entry) || _entry.model == undefined || !is_struct(_st) || _st.ts == undefined || _st.renderer == undefined || _st.cam == undefined) return -1;
  var _rot = undefined;
  var _spawn = __poly_spawn_t(_entry);

  if (_spawn != undefined) _rot = _spawn.rot;
  var _node = __poly_pv_spawn_lit(_ed, _st, _entry.model, _rot, _entry.key);

  if (_node == undefined) return -1;
  __poly_thumb_frame(_st.cam, _entry.model);
  _st.ts.update(0);
  var _spr = __poly_pv_shoot_sprite(_st, _size);
  __poly_destroy_subtree(_node);
  _st.ts.update(0);
  return _spr == undefined ? -1 : _spr;
}

// Buries a replaced thumbnail sprite (deferred delete: ImGui draws queued
// earlier this frame may still reference the old texture).
function __poly_thumb_bury(_ed, _entry) {
  if (_entry.thumb_owned == true && sprite_exists(_entry.thumb)) {
    if (is_array(_ed.thumb_graveyard)) {
      array_push(_ed.thumb_graveyard, { spr: _entry.thumb, ttl: 5 });
    } else {
      sprite_delete(_entry.thumb);
    }
  }
}

// Re-renders one asset thumbnail after its spawn rotation changed.
function __poly_thumb_recap_one(_ed, _entry) {
  if (_ed == undefined || !is_struct(_entry) || _entry.model == undefined) return;
  var _st = __poly_thumb_make_stage();

  if (_st == undefined) return;
  var _spr = __poly_thumb_shoot(_ed, _st, _entry);
  __poly_thumb_free_stage(_st);

  if (!sprite_exists(_spr)) return;
  __poly_thumb_bury(_ed, _entry);
  _entry.thumb = _spr;
  _entry.thumb_owned = true;
}


// ---------------------------------------------------------------------------
// Material and texture previews
// ---------------------------------------------------------------------------

// Loads an editor preview model once (sphere, triangle), warning once if missing.
function __poly_preview_src(_ed, _slot, _rel_path, _warn_tag) {
  if (_ed == undefined) return undefined;
  if (variable_struct_exists(_ed, _slot) && _ed[$ _slot] != undefined) return _ed[$ _slot];
  var _src = GM3D_Scene.loadGltf(working_directory + _rel_path);

  if (_src == undefined) {
    static _warned = {};

    if (!variable_struct_exists(_warned, _warn_tag)) variable_struct_set(_warned, _warn_tag, true);
    return undefined;
  }

  _src.freeze();
  _ed[$ _slot] = _src;
  return _src;
}

// Loads the editor sphere mesh for material previews (once).
// The GLB must carry TEXCOORD_0 (see other/tools/gen_sphere.ps1): without UVs
// every vertex samples the same texel and textured materials look flat.
function __poly_mat_sphere_src(_ed) {
  return __poly_preview_src(_ed, "mat_sphere", "__PolygonEditor__/models/sphere.glb", "mat_thumb");
}

// Loads the editor triangle mesh for flat texture previews (once).
// Oversized triangle (no indices): rasterizes to a quad on canvas.
function __poly_tri_src(_ed) {
  return __poly_preview_src(_ed, "tri_src", "__PolygonEditor__/models/triangle.glb", "texview");
}

// Returns a persistent stage for material previews (mirrors startup thumbs:
// one renderer reused across renders instead of fresh state each time).
function __poly_mat_stage(_ed) {
  return __poly_pv_stage_cached(_ed, "mat_stage");
}

// Returns a persistent stage for flat texture previews: ortho camera
// fixed on the oversized triangle (rasterizes to a quad on canvas),
// configured once and reused across renders.
function __poly_tex_stage(_ed) {
  if (variable_struct_exists(_ed, "tex_stage") && is_struct(_ed.tex_stage)) {
    var _hit = _ed.tex_stage;

    if (_hit.ts != undefined && _hit.renderer != undefined && _hit.cam != undefined) return _hit;
  }

  var _st = __poly_thumb_make_stage();

  if (_st == undefined) return undefined;
  var _comp = _st.cam.getCameraComponent();

  if (_comp != undefined) {
    _comp.setProjection(GM3D_ECameraProjection.Orthographic);
    _comp.setOrthoWidth(2.0);
    _comp.setOrthoHeight(2.0);
  }

  _st.cam.setLocalPosition(new GM3D_Vec3(0, 0, 5));
  var _fwd = new GM3D_Vec3(0, 0, 1);
  var _rot = GM3D_Quaternion.fromLookRotation(_fwd, GM3D_Vec3.up());
  _st.cam.setLocalRotation(_rot.normalizeSafe(0.000001));
  _ed.tex_stage = _st;
  return _st;
}

// Finds a cached material preview sprite (undefined when missing).
function __poly_mat_pv_find(_ed, _key) {
  if (is_struct(_ed) && variable_struct_exists(_ed, "mat_pv_map") && is_struct(_ed.mat_pv_map)
  && variable_struct_exists(_ed.mat_pv_map, _key)) {
    var _hit = _ed.mat_pv_map[$ _key];
    return sprite_exists(_hit) ? _hit : undefined;
  }

  for (var _i = 0, _n = array_length(_ed.mat_pv); _i < _n; _i++) {
    if (_ed.mat_pv[_i].key == _key) {
      var _spr = _ed.mat_pv[_i].spr;
      return sprite_exists(_spr) ? _spr : undefined;
    }
  }

  return undefined;
}

// Registers a material preview in queue + O(1) map.
function __poly_mat_pv_put(_ed, _key, _spr) {
  if (!is_struct(_ed)) return;

  if (!variable_struct_exists(_ed, "mat_pv_map") || !is_struct(_ed.mat_pv_map)) {
    _ed.mat_pv_map = {};
  }

  _ed.mat_pv_map[$ _key] = _spr;
}

// Returns the cached preview sprite for a material, queuing a render when missing.
function __poly_mat_thumb(_ed, _mm) {
  var _key = __poly_mat_key(_mm);

  if (_ed == undefined || _key == undefined) return undefined;
  if (!variable_struct_exists(_ed, "mat_pv") || !is_array(_ed.mat_pv)) _ed.mat_pv = [];
  var _hit = __poly_mat_pv_find(_ed, _key);

  if (_hit != undefined) return _hit;
  if (!variable_struct_exists(_ed, "mat_queue") || !is_array(_ed.mat_queue)) _ed.mat_queue = [];
  var _queued = false;

  for (var _q = 0, _nq = array_length(_ed.mat_queue); _q < _nq; _q++) {
    if (_ed.mat_queue[_q].key == _key) {
      _queued = true;
      break;
    }
  }

  var _failed = variable_struct_exists(_ed, "mat_fail") && is_struct(_ed.mat_fail) && variable_struct_exists(_ed.mat_fail, _key);

  if (!_queued && !_failed) {
    array_push(_ed.mat_queue, { mat: _mm, key: _key });
  }

  return undefined;
}

// Renders one material preview on the sphere (128px). Returns sprite or undefined.
function __poly_mat_thumb_render(_ed, _mm) {
  var _src = __poly_mat_sphere_src(_ed);

  if (_src == undefined) return undefined;
  var _st = __poly_mat_stage(_ed);

  if (_st == undefined) return undefined;
  var _node = _src.spawnInto(_st.ts, undefined);

  if (_node == undefined) return undefined;
  // Generic preview: clone the material and force the neutral static shader
  var _preview = _mm;
  var _clone_fn = _mm[$ "clone"];

  if (_clone_fn != undefined) {
    var _clone = method(_mm, _clone_fn)();

    if (_clone != undefined) {
      _clone.setShader(GM3D_ERenderPass.Forward, shPolygonEditorLit);
      _preview = _clone;
    }
  }

  var _comps = [];
  __poly_walk_collect_tree(_node, _comps);

  for (var _c = 0, _n = array_length(_comps); _c < _n; _c++) _comps[_c].comp.setMaterial(_preview);
  __poly_thumb_frame_tight(_st.cam);
  _st.ts.update(0);
  var _spr = __poly_pv_shoot_sprite(_st, 128);
  __poly_destroy_subtree(_node);
  _st.ts.update(0);

  return sprite_exists(_spr) ? _spr : undefined;
}

// Frees material preview cache, texture thumbnails, queue and sphere source.
function __poly_mat_pv_free(_ed) {
  if (_ed == undefined) return;
  __poly_mat_tex_pv_free(_ed);

  if (variable_struct_exists(_ed, "mat_pv") && is_array(_ed.mat_pv)) {
    for (var _i = 0, _n = array_length(_ed.mat_pv); _i < _n; _i++) if (sprite_exists(_ed.mat_pv[_i].spr)) sprite_delete(_ed.mat_pv[_i].spr);
    _ed.mat_pv = [];
  }

  _ed.mat_pv_map = {};
  _ed.mat_queue = [];
  _ed.mat_fail = {};

  if (variable_struct_exists(_ed, "tri_src") && _ed.tri_src != undefined) {
    _ed.tri_src.destroy();
    _ed.tri_src = undefined;
  }

  if (variable_struct_exists(_ed, "tex_stage") && is_struct(_ed.tex_stage)) {
    if (_ed.tex_stage.ts != undefined) _ed.tex_stage.ts.destroy();
    _ed.tex_stage = undefined;
  }

  if (variable_struct_exists(_ed, "mat_sphere") && _ed.mat_sphere != undefined) {
    _ed.mat_sphere.destroy();
    _ed.mat_sphere = undefined;
  }

  if (variable_struct_exists(_ed, "mat_stage") && is_struct(_ed.mat_stage)) {
    if (_ed.mat_stage.ts != undefined) _ed.mat_stage.ts.destroy();
    _ed.mat_stage = undefined;
  }
}

// ---------------------------------------------------------------------------
// Animation previews
// ---------------------------------------------------------------------------

// Returns persistent stage for animation previews (hover popups).
function __poly_anim_pv_stage(_ed) {
  return __poly_pv_stage_cached(_ed, "anim_stage");
}

// Finds animation component recursively in a spawned node.
function __poly_anim_pv_find(_node) {
  if (_node == undefined) return undefined;
  var _find = _node[$ "findAnimationComponent"];

  if (_find != undefined) {
    var _found = method(_node, _find)();

    if (_found != undefined) return _found;
  }

  var _get = _node[$ "getAnimationComponent"];

  if (_get != undefined) {
    var _comp = method(_node, _get)();

    if (_comp != undefined) return _comp;
  }

  var _kids = _node.getChildren();

  for (var _i = 0, _n = array_length(_kids); _i < _n; _i++) {
    var _nested = __poly_anim_pv_find(_kids[_i]);

    if (_nested != undefined) return _nested;
  }

  return undefined;
}

// Ensures preview node for model+index is spawned and looping.
function __poly_anim_pv_ensure(_ed, _model, _index, _loop = true) {
  var _st = __poly_anim_pv_stage(_ed);

  if (_st == undefined || _model == undefined) return false;
  if (variable_struct_exists(_ed, "anim_pv") && is_struct(_ed.anim_pv) && _ed.anim_pv.model == _model && _ed.anim_pv.index == _index && _ed.anim_pv.node != undefined) return true;

  if (variable_struct_exists(_ed, "anim_pv") && is_struct(_ed.anim_pv) && _ed.anim_pv.node != undefined) {
    __poly_destroy_subtree(_ed.anim_pv.node);
    _st.ts.update(0);
  }

  _ed.anim_pv = undefined;
  var _node = __poly_pv_spawn_lit(_ed, _st, _model);

  if (_node == undefined) return false;
  __poly_thumb_frame(_st.cam, _model);
  var _anim = __poly_anim_pv_find(_node);

  if (_anim != undefined) {
    _anim.setEnabled(true);
    _anim.setTime(0.0);
    _anim.setSpeed(1.0);
    _anim.play(_index, _loop);
  }

  _ed.anim_pv = { model: _model, index: _index, node: _node, comp: _anim, t: 0, playing: true, loop: _loop };
  _st.ts.update(0);
  return true;
}

// Returns animation duration in seconds (1.0 fallback).
function __poly_anim_pv_duration(_model, _index) {
  if (_model == undefined) return 1.0;
  var _get = _model[$ "getAnimation"];

  if (_get == undefined) return 1.0;
  var _anim = method(_model, _get)(_index);

  if (_anim != undefined && is_real(_anim.duration) && _anim.duration > 0.01) return _anim.duration;
  return 1.0;
}

// Tears down the animation preview when its window closed.
function __poly_anim_pv_close(_ed) {
  if (variable_struct_exists(_ed, "anim_pv") && is_struct(_ed.anim_pv) && _ed.anim_pv.node != undefined) {
    __poly_destroy_subtree(_ed.anim_pv.node);
    _ed.anim_pv = undefined;

    if (variable_struct_exists(_ed, "anim_stage") && is_struct(_ed.anim_stage) && _ed.anim_stage.ts != undefined) _ed.anim_stage.ts.update(0);
  }
}

// Restarts the preview animation from zero.
function __poly_anim_pv_restart(_comp, _ui, _pv, _loop) {
  _ui.restart = false;
  var _set_time = _comp[$ "setTime"];

  if (_set_time != undefined) method(_comp, _set_time)(0.0);
  _ui.playing = true;
  _ui.finished = false;
  var _resume = _comp[$ "resume"];

  if (_resume != undefined) {
    method(_comp, _resume)();
  } else {
    _comp.play(_ui.index, _loop);
  }

  _pv.playing = true;
}

// Syncs loop flag, pause state and finish detection for component playback.
function __poly_anim_pv_sync_comp(_comp, _ui, _pv, _loop, _dur) {
  if (_ui.restart == true) __poly_anim_pv_restart(_comp, _ui, _pv, _loop);

  if (_loop != (_pv.loop == true)) {
    var _get_time = _comp[$ "getTime"];
    var _t = _get_time != undefined ? method(_comp, _get_time)() : undefined;
    _comp.play(_ui.index, _loop);

    if (is_real(_t)) {
      var _set_time = _comp[$ "setTime"];

      if (_set_time != undefined) method(_comp, _set_time)(_t);
    }

    _pv.loop = _loop;
    _pv.playing = true;
    _ui.finished = false;

    if (is_real(_t) && _t >= _dur - 0.001) {
      var _rewind = _comp[$ "setTime"];

      if (_rewind != undefined) method(_comp, _rewind)(0.0);
    }
  }

  if (_ui.playing == true && _pv.playing != true) {
    var _resume = _comp[$ "resume"];

    if (_resume != undefined) {
      method(_comp, _resume)();
    } else {
      _comp.play(_ui.index, _loop);
    }

    _pv.playing = true;
  } else if (_ui.playing != true && _pv.playing == true) {
    var _pause = _comp[$ "pause"];

    if (_pause != undefined) method(_comp, _pause)();
    _pv.playing = false;
  }

  if (!_loop && _ui.finished != true) {
    var _get_now = _comp[$ "getTime"];
    var _now = _get_now != undefined ? method(_comp, _get_now)() : undefined;

    if (is_real(_now) && _now >= _dur - 0.001) {
      _ui.playing = false;
      _ui.finished = true;
      _pv.playing = false;
    }
  }
}

// Blits the animation stage to the 200px surface.
function __poly_anim_pv_blit(_ed, _st) {
  if (!surface_exists(_ed.anim_surf) || surface_get_width(_ed.anim_surf) != 200 || surface_get_height(_ed.anim_surf) != 200) {
    if (surface_exists(_ed.anim_surf)) __poly_surf_retire(_ed, _ed.anim_surf);
    _ed.anim_surf = surface_create(200, 200);
  }

  if (!surface_exists(_ed.anim_surf)) return;
  surface_set_target(_ed.anim_surf);
  draw_clear_alpha(c_black, 0);
  _st.renderer.render(_st.ts);
  surface_reset_target();
}

// Advances the opened animation preview and renders it to the 200px surface.
// Driven by _ed.anim_ui (set by clicking a row); nothing runs when closed.
function __poly_anim_pv_tick(_ed, _dt) {
  var _ui = (variable_struct_exists(_ed, "anim_ui") && is_struct(_ed.anim_ui)) ? _ed.anim_ui : undefined;

  if (_ui == undefined || _ui.model == undefined) {
    __poly_anim_pv_close(_ed);
    return;
  }

  _dt = clamp(_dt, 0, 0.05);
  var _loop = _ui.loop != false;

  if (!__poly_anim_pv_ensure(_ed, _ui.model, _ui.index, _loop)) return;
  var _st = __poly_anim_pv_stage(_ed);

  if (_st == undefined || !variable_struct_exists(_ed, "anim_pv") || !is_struct(_ed.anim_pv)) return;
  var _pv = _ed.anim_pv;
  var _speed = is_real(_ui.speed) ? max(_ui.speed, 0) : 1;
  var _dur = 1.0;

  if (is_struct(_pv) && variable_struct_exists(_pv, "dur") && is_real(_pv.dur) && _pv.dur > 0.01
  && variable_struct_exists(_pv, "dur_idx") && _pv.dur_idx == _ui.index && _pv.dur_model == _ui.model) {
    _dur = _pv.dur;
  } else {
    _dur = __poly_anim_pv_duration(_ui.model, _ui.index);

    if (is_struct(_pv)) {
      _pv.dur = _dur;
      _pv.dur_idx = _ui.index;
      _pv.dur_model = _ui.model;
    }
  }

  if (_pv.comp != undefined) {
    var _set_speed = _pv.comp[$ "setSpeed"];

    if (_set_speed != undefined) method(_pv.comp, _set_speed)(_speed);
    __poly_anim_pv_sync_comp(_pv.comp, _ui, _pv, _loop, _dur);
    _st.ts.update(_dt);
  } else {
    if (_ui.restart == true) {
      _ui.restart = false;
      _pv.t = 0;
      _ui.playing = true;
      _ui.finished = false;
    }

    if (_ui.playing == true) _pv.t += _dt * _speed;
    var _apply = _st.ts[$ "applyAnimation"];

    if (_apply != undefined) {
      if (_loop) {
        method(_st.ts, _apply)(_ui.index, _pv.t mod _dur);
      } else {
        if (_pv.t >= _dur) {
          _pv.t = _dur;
          _ui.playing = false;
          _ui.finished = true;
        }

        method(_st.ts, _apply)(_ui.index, min(_pv.t, _dur));
      }
    }

    _st.ts.update(0);
  }

  __poly_anim_pv_blit(_ed, _st);
}

// Frees animation preview node, stage and surface.
function __poly_anim_pv_free(_ed) {
  if (_ed == undefined) return;
  if (variable_struct_exists(_ed, "anim_pv") && is_struct(_ed.anim_pv) && _ed.anim_pv.node != undefined) __poly_destroy_subtree(_ed.anim_pv.node);
  _ed.anim_pv = undefined;

  if (variable_struct_exists(_ed, "anim_stage") && is_struct(_ed.anim_stage) && _ed.anim_stage.ts != undefined) _ed.anim_stage.ts.destroy();
  _ed.anim_stage = undefined;

  if (variable_struct_exists(_ed, "anim_surf") && surface_exists(_ed.anim_surf)) __poly_surf_retire(_ed, _ed.anim_surf);
  _ed.anim_surf = undefined;
  _ed.anim_ui = undefined;
}

// Frees every preview cache (thumbnails, materials, animations).

// Captures library thumbnails once at startup.
function __poly_capture_thumbnails() {
  var _ed = global.poly_inst;

  if (_ed.thumbs_done == true || _ed.thumb_initializing == true) return;
  if (!is_array(_ed.assets) || array_length(_ed.assets) == 0) return;
  _ed.thumb_stage = __poly_thumb_make_stage();

  if (_ed.thumb_stage == undefined) {
    _ed.thumbs_done = true;
    return;
  }

  _ed.thumb_queue = [];

  for (var _i = array_length(_ed.assets) - 1; _i >= 0; --_i) {
    var _entry = _ed.assets[_i];

    if (!is_struct(_entry) || _entry.model == undefined) continue;
    var _spawn = __poly_spawn_t(_entry);

    if (_spawn != undefined) _entry.thumb_rot = [ _spawn.rot[0], _spawn.rot[1], _spawn.rot[2] ];
    array_push(_ed.thumb_queue, _entry);
  }

  _ed.thumb_initializing = array_length(_ed.thumb_queue) > 0;

  if (!_ed.thumb_initializing) {
    __poly_thumb_free_stage(_ed.thumb_stage);
    _ed.thumb_stage = undefined;
    _ed.thumbs_done = true;
  }
}
