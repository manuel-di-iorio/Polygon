// poly_create — public API.

// Initializes editor state and restores view.
// Takes only the runtime adapter ({ scene?, assets?, cam?, on_create?,
// on_close? }): the editor owns its scene and never touches game
// instances. Init is static only (library + empty scene); the live scene
// is mirrored on every enable, when wrappers are detected by prefix and
// bare roots get fresh ids. Contract: on_create receives the wrapper
// node (walk the subtree for model content).
function poly_create(_rt) {
  var _src = is_struct(_rt) ? _rt : {};
  var _rtc = __poly_create_rt(_src);
  var _ed = __poly_create_state(_rtc);
  global.poly_inst = _ed;

  __poly_create_assets(_src);

  __poly_viewcam_seed_from(_ed, _rtc.cam);
  __poly_cam_remember(_ed);
  __poly_ui_load(_ed);
  __poly_view_save(_ed);
  __poly_view_sync(_ed);
  __poly_grid_ensure(_ed);
  __poly_cameras_mute(_ed);
  global.poly_active = _ed.active;
  global.poly_inst = _ed;
  return _ed;
}
