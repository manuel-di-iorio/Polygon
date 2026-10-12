// poly_track — public API.

// Imports a live game node into the editor scene (copy) for editing.
// The game world is never touched: assets respawn from the library by
// id (keeping save provenance), lights/cameras/env are recreated from
// live settings. A live wrapper id is preserved; bare nodes get a fresh
// one. Returns the editor wrapper node, or undefined.
function poly_track(_kind, _asset_id, _node, _label = undefined) {
  var _ed = __poly_inst();

  if (_ed == undefined) return undefined;
  if (_node == undefined) return undefined;
  if (_kind == "light") return __poly_track_adopt_light(_ed, _node, _label);
  if (_kind == "camera") return __poly_track_adopt_camera(_ed, _node, _label);
  if (_kind == "environment") return __poly_track_adopt_env(_ed, _node, _label);
  var _model = __poly_asset_find(_ed, _asset_id);

  if (_model == undefined) return undefined;
  var _new = __poly_track_place_asset(_ed, _asset_id, _model, _node, _label);

  if (_new == undefined) return undefined;
  __poly_track_adopt_flags(_node, _new);
  return _new;
}
