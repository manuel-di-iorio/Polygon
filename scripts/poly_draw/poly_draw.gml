// poly_draw - public API.

// Single call for the Draw event: shader warmup, then outline mask,
// GPU picking and scene panel render.
function poly_draw() {
  var _ed = __poly_inst();

  if (_ed == undefined) return;

  // Shader warmup (once).
  if (!(variable_struct_exists(_ed, "shaders_warmed") && _ed.shaders_warmed == true)) {
    _ed.shaders_warmed = true;
    var _surf = surface_create(8, 8);

    if (_surf != undefined && surface_exists(_surf)) {
      surface_set_target(_surf);
      draw_clear(c_black);
      var _shaders = __poly_editor_shaders();

      for (var _i = 0, _n = array_length(_shaders); _i < _n; _i++) {
        shader_set(_shaders[_i]);
        draw_rectangle(0, 0, 2, 2, false);
        shader_reset();
      }

      surface_reset_target();

      if (surface_exists(_surf)) surface_free(_surf);
    }
  }

  if (_ed.active) {
    // Single per-frame world-matrix refresh, placed here so every pass
    // below (pick, outline, panel render + overlays) shares one consistent
    // camera pose.
    _ed.rt.scene.update(0);
    _ed.vp = __poly_viewport_cached(_ed);
    // Decide the offscreen 3D size for THIS frame up front: every 3D pass
    // below (pick, mask, main) must share it, or mixed resolutions in one
    // frame invalidate the whole submit. Ensures (and progressively
    // creates) the scratch surface as a side effect.
    _ed.hi_ready = true;
    __poly_thumbs_pump(_ed);
    __poly_mat_queue_pump(_ed);
    __poly_anim_pv_tick(_ed, delta_time * 0.000001);
  }

  __poly_graveyard_step(_ed[$ "thumb_graveyard"], __poly_thumb_graveyard_free);
  // Pick first: it applies pending clicks/rects to the selection, and the
  // outline capture must see the post-pick state - otherwise a deselect
  // re-renders the main surface with the stale mask and nothing ever
  // invalidates it again.
  __poly_gpupick_execute(_ed);
  __poly_outline_capture(_ed);
  __poly_graveyard_step(_ed[$ "surf_graveyard"], __poly_surf_graveyard_free);
  __poly_scene_panel_render(_ed);
  __poly_ai_capture_draw(_ed);
}
