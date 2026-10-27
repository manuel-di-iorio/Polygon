// poly_is_active - public API.

// Checks if editor is active.
function poly_is_active() {
  var _ed = __poly_inst();

  if (_ed == undefined) return false;
  return _ed.active == true;
}
