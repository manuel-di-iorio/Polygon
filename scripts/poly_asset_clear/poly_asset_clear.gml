// poly_asset_clear - public API.

// Clears all editor library assets.
function poly_asset_clear() {
  var _ed = __poly_inst();

  if (_ed == undefined) return;
  __poly_thumbs_free(_ed);
  _ed.assets = [];
  _ed.lib_sel = undefined;
  _ed.anim_ui = undefined;
}
