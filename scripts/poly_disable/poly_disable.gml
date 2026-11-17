// poly_disable - public API.

// Disables the 3D editor. _reason (optional): "play" publishes the edited
// scene for on_close (poly_scene_snapshot / poly_sync_live), "reset" drops the
// edits so the live game keeps the state it had when the editor opened.
function poly_disable(_reason = "play") {
  __poly_set_active(global.poly_inst, false, _reason);
}
