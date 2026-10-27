// poly_dlg_confirm - confirm modal dialog.

// Shows unsaved changes confirmation dialog.
function __poly_imgui_confirm(_ed) {
  var _dlg = _ed.confirm;

  if (_dlg == undefined) return;

  if (_dlg.open == false) {
    _ed.confirm = undefined;
    return;
  }

  var _begun = __poly_modal_begin(_ed, "Unsaved changes", 340, 90, _dlg);

  if (!_begun) {
    __poly_modal_end();
    return;
  }

  static _what_by_action = {
    "new": "creating a new scene",
    load: "loading a new scene",
  };
  var _what = variable_struct_exists(_what_by_action, _dlg.action) ? _what_by_action[$ _dlg.action] : "exiting";
  ImGui.Text("Do you want to save changes");
  ImGui.Text("before " + _what + "?");

  if (ImGui.Button("Save", 0, 0)) {
    if (__poly_save_or_ask(_ed, _dlg.action)) __poly_confirm_do(_ed, _dlg.action);
    _ed.confirm = undefined;
  }

  ImGui.SameLine();

  if (ImGui.Button("Don't save", 0, 0)) {
    if (_dlg.action == "close") __poly_discard_changes(_ed);
    __poly_confirm_do(_ed, _dlg.action);
    _ed.confirm = undefined;
  }

  ImGui.SameLine();

  if (ImGui.Button("Cancel", 0, 0)) _ed.confirm = undefined;
  __poly_modal_end();
}

// Shows multi-delete confirmation dialog.
function __poly_imgui_delete_confirm(_ed) {
  var _dlg = _ed.delete_confirm;

  if (_dlg == undefined) return;

  if (_dlg.open == false) {
    _ed.delete_confirm = undefined;
    return;
  }

  var _begun = __poly_modal_begin(_ed, "Delete objects?", 320, 110, _dlg);

  if (!_begun) {
    __poly_modal_end();
    return;
  }

  var _count = variable_struct_exists(_dlg, "count") && is_real(_dlg.count) ? _dlg.count : array_length(_ed.sel);
  ImGui.Text("Delete " + string(_count) + " selected objects?");
  ImGui.TextDisabled("This can be undone (" + __poly_bind_label(_ed.cfg.keys, "undo") + ").");

  if (ImGui.Button("Delete", 0, 0)) {
    _ed.delete_confirm = undefined;
    __poly_delete_sel(_ed);
  }

  ImGui.SameLine();

  if (ImGui.Button("Cancel", 0, 0)) _ed.delete_confirm = undefined;
  __poly_modal_end();
}
