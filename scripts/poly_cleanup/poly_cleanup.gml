// poly_cleanup — public API.

// Releases editor resources and restores scene.
function poly_cleanup(_ed = undefined) {
  _ed ??= __poly_inst();

  if (_ed == undefined) return;
  __poly_outline_cleanup(_ed);
  __poly_gpupick_cleanup(_ed);
  __poly_ai_disconnect(_ed);
  __poly_thumbs_free(_ed);
  __poly_mat_pv_free(_ed);
  __poly_anim_pv_free(_ed);
  __poly_graveyard_free(_ed);

  if (surface_exists(_ed.scene_surf)) surface_free(_ed.scene_surf);
  _ed.scene_surf = undefined;
  if (surface_exists(_ed[$ "scene_hi"])) surface_free(_ed.scene_hi);
  _ed.scene_hi = undefined;
  if (surface_exists(_ed[$ "scene_smaa_e"])) surface_free(_ed.scene_smaa_e);
  _ed.scene_smaa_e = undefined;
  if (surface_exists(_ed[$ "scene_smaa_w"])) surface_free(_ed.scene_smaa_w);
  _ed.scene_smaa_w = undefined;

  if (surface_exists(_ed[$ "smaa_lut_area"])) surface_free(_ed.smaa_lut_area);
  _ed.smaa_lut_area = -1;

  if (surface_exists(_ed[$ "smaa_lut_search"])) surface_free(_ed.smaa_lut_search);
  _ed.smaa_lut_search = -1;

  if (variable_struct_exists(_ed, "smaa_lut_sprs") && is_array(_ed.smaa_lut_sprs)) {
    for (var _i = 0, _n = array_length(_ed.smaa_lut_sprs); _i < _n; _i++) if (sprite_exists(_ed.smaa_lut_sprs[_i])) sprite_delete(_ed.smaa_lut_sprs[_i]);
    _ed.smaa_lut_sprs = [];
  }

  _ed.renderer = undefined;
  __poly_ui_save(_ed);
  __poly_rt_ini_save();
  __poly_drop_preview_clear(_ed);
  __poly_view_restore(_ed);
  __poly_bg_restore(_ed);
  __poly_cameras_restore(_ed);
  _ed.show_unlit = false;
  __poly_unlit_apply(_ed);

  if (_ed.viewcam != undefined) {
    var _vcc = _ed.viewcam.getCameraComponent();

    if (_vcc != undefined) _vcc.setEnabled(false);
  }

  __poly_grid_remove(_ed);
  __poly_sky_remove(_ed);

  if (variable_struct_exists(_ed, "sky_src") && _ed.sky_src != undefined) {
    _ed.sky_src.destroy();
    _ed.sky_src = undefined;
  }

  _ed.sky_mat = undefined;
  _ed.show_shadows = true;
  __poly_shadowpreview_apply(_ed);
  _ed.grid_mat = undefined;

  if (variable_struct_exists(_ed, "grid_src") && _ed.grid_src != undefined) {
    _ed.grid_src.destroy();
    _ed.grid_src = undefined;
  }

  if (variable_global_exists("poly_inst") && global.poly_inst == _ed) global.poly_inst = undefined;
  if (variable_global_exists("poly_active")) global.poly_active = false;
}
