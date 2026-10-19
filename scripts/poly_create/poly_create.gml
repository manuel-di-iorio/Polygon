// poly_create — public API.

// Applies user shortcut overrides over the default binding table.
// Each entry is an array of elements { key, mouse?, modifier? }:
//   { key: vk_control, modifier: true }   // held keyboard modifier
//   { key: ord("S") }                     // keyboard trigger
//   { key: mb_right, mouse: true }        // mouse trigger (held for cam_*)
//   { key: mb_right, mouse: true, modifier: true }  // held mouse button
// A bare real is accepted as a single keyboard trigger. Several triggers in
// one array are alternatives. The type (mouse vs keyboard) is explicit, never
// inferred from the code. Unknown names are ignored. Binding names live in
// __poly_keys_defaults; the actions whose meaning depends on the modifier are
// focus (plain) vs focus_search (Ctrl), snap (plain) vs snap_grid (Ctrl), and
// redo_shift (Ctrl+Shift+Z) alongside redo.
function __poly_keys_apply(_ed, _src) {
  if (!variable_struct_exists(_src, "keys") || !is_struct(_src.keys)) return;
  var _defs = _ed.cfg.keys;
  var _names = variable_struct_get_names(_src.keys);

  for (var _i = 0, _n = array_length(_names); _i < _n; _i++) {
    var _k = _names[_i];

    if (!variable_struct_exists(_defs, _k)) continue;
    var _v = _src.keys[$ _k];

    if (is_real(_v) || is_struct(_v)) _v = [ _v ];
    if (!is_array(_v)) continue;
    var _clone = [];

    for (var _j = 0, _m = array_length(_v); _j < _m; _j++) _clone[_j] = _v[_j];
    _defs[$ _k] = _clone;
  }
}

// Initializes editor state and restores view.
// Takes only the runtime adapter ({ scene?, assets?, cam?, on_create?,
// on_close?, on_compose?, keys? }): the editor owns its scene and never
// touches game instances. Init is static only (library + empty scene); the
// live scene is mirrored on every enable, when wrappers are detected by
// prefix and bare roots get fresh ids. Contract: on_create receives the
// wrapper node (walk the subtree for model content). Keys remaps the editor
// shortcuts (see __poly_keys_apply for the accepted names).
function poly_create(_rt) {
  var _src = is_struct(_rt) ? _rt : {};
  var _rtc = __poly_create_rt(_src);
  var _ed = __poly_create_state(_rtc);
  global.poly_inst = _ed;

  __poly_create_assets(_src);
  __poly_keys_apply(_ed, _src);

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
