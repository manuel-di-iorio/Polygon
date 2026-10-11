// polygon_dlg_about — about dialog.

// Shows about dialog.
function __polygon_imgui_about(_ed) {
  var _dlg = _ed.about;

  if (_dlg == undefined) return;

  if (_dlg.open == false) {
    _ed.about = undefined;
    return;
  }

  var _begun = __polygon_modal_begin(_ed, "About Polygon Editor", 380, 110, _dlg);

  if (!_begun) {
    __polygon_modal_end();
    return;
  }

  ImGui.Text("Developed by Emmanuel Di Iorio aka Xeryan.");
  ImGui.Text("Released under the MIT License - 2026.");
  ImGui.Text("Third-party assets belong to their owners.");

  if (ImGui.Button("OK", 0, 0)) _ed.about = undefined;
  __polygon_modal_end();
}
