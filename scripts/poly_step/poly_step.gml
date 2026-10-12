// poly_step — public API.

// Updates editor logic and draws UI.
function poly_step() {
  var _ed = __poly_inst();

  if (_ed == undefined) return;
  __poly_step(_ed, delta_time * 0.000001);
  __poly_ai_step(_ed);
  __poly_imgui_draw(_ed);
}
