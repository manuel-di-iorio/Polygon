// polygon_dlg_scene — scene new/load/save-as dialog.

// Shows save/load scene dialog (name only, fixed folder).
function __polygon_imgui_scene_dlg(_ed) {
  var _dlg = _ed.scene_dlg;

  if (_dlg == undefined) return;

  if (_dlg.open == false) {
    _ed.scene_dlg = undefined;
    return;
  }

  var _is_save = _dlg.mode != "load";
  var _w = 400;
  var _h = _is_save ? 120 : 360;
  var _begun = __polygon_modal_begin(_ed, _is_save ? "Save scene" : "Load scene", _w, _h, _dlg);

  if (!_begun) {
    __polygon_modal_end();
    return;
  }

  if (variable_struct_exists(_dlg, "delete_pending") && is_string(_dlg.delete_pending)) {
    __polygon_scene_dlg_delete(_dlg);
  } else {
    __polygon_scene_dlg_form(_ed, _dlg, _is_save);
  }

  __polygon_modal_end();
}

// Draws the delete-confirmation variant of the dialog.
function __polygon_scene_dlg_delete(_dlg) {
  var _name = _dlg.delete_pending;
  ImGui.Spacing();
  ImGui.Text("Are you sure you want to delete");
  ImGui.Text("the scene \"" + _name + "\"?");
  ImGui.Spacing();
  ImGui.TextDisabled("This cannot be undone.");
  ImGui.Dummy(0, 16);

  if (ImGui.Button("Delete", 0, 0)) {
    if (__polygon_delete_scene_named(_name)) {
      if (_dlg.name == _name) {
        _dlg.name = "";
        _dlg.buf = __polygon_imgui_pad("");
      }

      _dlg.list = __polygon_scene_list();
    } else {
      _dlg.error = "Could not delete scene \"" + _name + "\".";
      _dlg.err_name = _dlg.name;
    }

    _dlg.delete_pending = undefined;
  }

  ImGui.SameLine();

  if (ImGui.Button("Cancel", 0, 0)) _dlg.delete_pending = undefined;
}

// Draws the name field, scene list and action buttons.
function __polygon_scene_dlg_form(_ed, _dlg, _is_save) {
  ImGui.Text("Scene name:");

  if (!variable_struct_exists(_dlg, "buf") || !is_string(_dlg.buf)) _dlg.buf = __polygon_imgui_pad(_dlg.name);
  var _out = ImGui.InputText("##scene_dlg_name", _dlg.buf, ImGuiInputTextFlags.AutoSelectAll);

  if (is_string(_out)) {
    _dlg.buf = _out;
    _dlg.name = string_trim(_out);
  }

  if (_dlg.error != "" && _dlg.name != _dlg.err_name) {
    _dlg.error = "";
    _dlg.err_name = "";
  }

  if (!_is_save) __polygon_scene_dlg_list(_ed, _dlg);
  __polygon_scene_dlg_status(_ed, _dlg, _is_save);

  if (ImGui.Button(_is_save ? "Save" : "Load", 0, 0)) __polygon_scene_dlg_commit(_ed, _is_save);
  ImGui.SameLine();

  if (ImGui.Button("Cancel", 0, 0)) _ed.scene_dlg = undefined;
  if (_ed.scene_dlg != undefined && keyboard_check_pressed(vk_enter)) __polygon_scene_dlg_commit(_ed, _is_save);
}

// Draws the searchable list of saved scenes (load mode).
function __polygon_scene_dlg_list(_ed, _dlg) {
  ImGui.Separator();
  ImGui.TextDisabled("Existing:");
  ImGui.SetNextItemWidth(-1);

  if (!variable_struct_exists(_dlg, "search") || !is_string(_dlg.search)) _dlg.search = "";
  _dlg.search = __polygon_imgui_text_hint("##scene_dlg_search", "Search scene..", _dlg.search);
  var _filter = string_lower(string_trim(_dlg.search));
  var _matched = 0;

  if (ImGui.BeginChild("##scenes_list_child", 0, -88 - 30, ImGuiChildFlags.Borders)) {
    var _sel_w = ImGui.GetContentRegionAvailX() - 28 - 8;

    for (var _i = 0, _n = array_length(_dlg.list); _i < _n; _i++) {
      var _name = _dlg.list[_i];

      if (_filter != "" && string_pos(_filter, string_lower(_name)) <= 0) continue;
      ImGui.PushID(_i);
      _matched++;

      if (ImGui.Selectable(_name, _dlg.name == _name, 0, _sel_w, 0)) {
        _dlg.name = _name;
        _dlg.buf = __polygon_imgui_pad(_name);
      }

      if (ImGui.IsMouseDoubleClicked(0) && ImGui.IsItemHovered()) __polygon_scene_dlg_do_load(_ed);
      ImGui.SameLine();

      if (ImGui.SmallButton("x##del_" + string(_i))) _dlg.delete_pending = _name;
      ImGui.PopID();
    }
  }

  ImGui.EndChild();
  _dlg._matched = _matched;
}

// Draws the one-line status under the form.
function __polygon_scene_dlg_status(_ed, _dlg, _is_save) {
  if (_dlg.error != "") {
    ImGui.Text("Error: " + _dlg.error);
  } else if (_is_save && __polygon_scene_dlg_exists(_ed, _dlg.name)) {
    ImGui.TextDisabled("Exists - saving will overwrite.");
  } else if (!_is_save && array_length(_dlg.list) == 0) {
    ImGui.TextDisabled("No saved scenes yet.");
  } else if (!_is_save && string_length(string_trim(_dlg.search)) > 0 && _dlg._matched == 0) {
    ImGui.TextDisabled("No scenes match your search.");
  } else {
    ImGui.Text("");
  }
}

// Runs the Save/Load action for the current dialog state.
function __polygon_scene_dlg_commit(_ed, _is_save) {
  if (_is_save) {
    __polygon_scene_dlg_do_save(_ed);
  } else {
    __polygon_scene_dlg_do_load(_ed);
  }
}

// Checks if sanitized name matches a listed scene.
function __polygon_scene_dlg_exists(_ed, _name) {
  var _clean = string_lower(__polygon_sanitize_scene_name(_name));

  if (_clean == "") return false;
  var _list = _ed.scene_dlg.list;

  for (var _i = 0, _n = array_length(_list); _i < _n; _i++) if (string_lower(_list[_i]) == _clean) return true;
  return false;
}
