// poly_imgui_history - History window (undo/redo action list).

// ---------------------------------------------------------------------------
// Window
// ---------------------------------------------------------------------------

// Draws the History window. It docks as a second tab next to the Inspector
// on first use; afterwards the user owns the dock layout.
function __poly_imgui_history_win(_ed) {
  var _ui = _ed.imgui;

  if (!_ui.win_hist.open) return;
  var _place = __poly_imgui_place(_ed).insp;

  if (!__poly_imgui_dock_fresh(_ed)) {
    var _insp_dock = _ui[$ "insp_dock"];

    if (is_real(_insp_dock) && _insp_dock != 0) __poly_imgui_dock_next(_insp_dock, ImGuiCond.FirstUseEver);
    ImGui.SetNextWindowPos(_place.x, _place.y, _ui.cond);
    ImGui.SetNextWindowSize(_place.w, _place.h, _ui.cond);
  }

  ImGui.SetNextWindowBgAlpha(1);

  var _flags = __poly_imgui_panel_flags(_ed, "hist");

  if (__poly_imgui_lock_move(_ed)) _flags = _flags | ImGuiWindowFlags.NoMove;

  if (!ImGui.Begin("History", _ui.win_hist, _flags)) {
    __poly_imgui_panel_save(_ed, "hist");
    ImGui.End();
    return;
  }

  __poly_imgui_panel_save(_ed, "hist");
  __poly_imgui_history_body(_ed);
  ImGui.End();
}

// ---------------------------------------------------------------------------
// List
// ---------------------------------------------------------------------------

// Tooltip for a restorable row.
function __poly_history_row_tip(_verb, _label, _steps) {
  if (_steps <= 1) return _verb + " \"" + _label + "\"";
  return _verb + " " + string(_steps) + " actions (back to before \"" + _label + "\")";
}

// Draws one restorable undo row (newest first).
function __poly_imgui_history_undo_row(_ed, _index, _count) {
  ImGui.PushID(_index);
  var _label = __poly_history_entry_label(_ed.undo[_index]);
  var _steps = max(1, _count - _index);
  var _detail = __poly_history_entry_detail(_ed.undo[_index]);
  var _tip = (_steps == 1 && _detail != "") ? _detail : __poly_history_row_tip("Undo", _label, _steps);
  var _hit = __poly_imgui_icon_btn(
    "##hist_undo",
    _tip,
    false,
    "U",
    "sprPolygonEditorIconRotate",
    15,
    15
  );

  ImGui.SameLine();
  ImGui.AlignTextToFramePadding();
  ImGui.TextUnformatted(_label);

  if (_hit) {
    _ed.hist_confirm = {
      open: true,
      action: "undo",
      index: _index,
      steps: _steps,
      label: _label,
      detail: _detail,
    };
  }

  ImGui.PopID();
}

// Draws one restorable redo row (next redo first).
function __poly_imgui_history_redo_row(_ed, _index, _count) {
  ImGui.PushID(1000 + _index);
  var _label = __poly_history_entry_label(_ed.redo[_index]);
  var _steps = max(1, _count - _index);
  var _detail = __poly_history_entry_detail(_ed.redo[_index]);
  var _tip = (_steps == 1 && _detail != "") ? _detail : __poly_history_row_tip("Redo", _label, _steps);
  var _hit = ImGui.ArrowButton("##hist_redo", ImGuiDir.Right);

  if (ImGui.IsItemHovered()) ImGui.SetTooltip(_tip);
  ImGui.SameLine();
  ImGui.AlignTextToFramePadding();
  ImGui.TextUnformatted(_label);

  if (_hit) {
    _ed.hist_confirm = {
      open: true,
      action: "redo",
      index: _index,
      steps: _steps,
      label: _label,
      detail: _detail,
    };
  }

  ImGui.PopID();
}

// Draws the undo and redo action stacks.
function __poly_imgui_history_body(_ed) {
  __poly_history_stacks(_ed);
  var _n_undo = array_length(_ed.undo);
  var _n_redo = array_length(_ed.redo);

  if (_n_undo == 0 && _n_redo == 0) {
    ImGui.TextDisabled("No actions yet");
    return;
  }

  ImGui.BeginChild("##hist_scroll", 0, 0, ImGuiChildFlags.None);

  for (var _i = _n_undo - 1; _i >= 0; _i--) __poly_imgui_history_undo_row(_ed, _i, _n_undo);
  for (var _j = _n_redo - 1; _j >= 0; _j--) __poly_imgui_history_redo_row(_ed, _j, _n_redo);

  ImGui.EndChild();
}

// ---------------------------------------------------------------------------
// Confirmation
// ---------------------------------------------------------------------------

// Draws the confirmation modal for a history restore.
function __poly_imgui_history_confirm(_ed) {
  var _dlg = _ed.hist_confirm;

  if (_dlg == undefined) return;

  if (_dlg.open == false) {
    _ed.hist_confirm = undefined;
    return;
  }

  var _begun = __poly_modal_begin(_ed, "Restore history state", 430, 142, _dlg);

  if (!_begun) {
    __poly_modal_end();
    return;
  }

  var _steps = (is_real(_dlg[$ "steps"]) && _dlg.steps > 0) ? round(_dlg.steps) : 1;
  var _label = (is_string(_dlg[$ "label"]) && _dlg.label != "") ? _dlg.label : "action";
  var _detail = (is_string(_dlg[$ "detail"]) && _dlg.detail != "") ? _dlg.detail : "";
  var _redo = _dlg.action == "redo";
  var _verb = _redo ? "Redo" : "Undo";
  var _what = _steps == 1 ? "1 action" : string(_steps) + " actions";

  ImGui.Text(_verb + " " + _what + "?");
  ImGui.TextDisabled((_redo ? "Redo up to: \"" : "Back to before: \"") + _label + "\"");
  if (_detail != "" && _steps == 1) ImGui.TextDisabled(_detail);
  // ImGui.Spacing();
  // if (_redo) ImGui.TextDisabled("The restored actions can still be undone.");

  if (ImGui.Button(_verb, 0, 0)) {
    var _ok = true;

    if (_redo) {
      for (var _si = 0; _si < _steps; _si++) {
        if (!__poly_history_apply(_ed, _ed.redo, _ed.undo)) { _ok = false; break; }
      }
    } else {
      for (var _sj = 0; _sj < _steps; _sj++) {
        if (!__poly_history_apply(_ed, _ed.undo, _ed.redo)) { _ok = false; break; }
      }
    }

    _ed.hist_confirm = undefined;
    if (_ok) _ed.view_dirty = true;
  }

  ImGui.SameLine();

  if (ImGui.Button("Cancel", 0, 0)) _ed.hist_confirm = undefined;
  __poly_modal_end();
}
