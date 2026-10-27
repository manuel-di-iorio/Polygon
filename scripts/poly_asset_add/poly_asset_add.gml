// poly_asset_add - public API.

// Adds model asset to editor library.
// Identity is the load path (_path): models with duplicate root names can
// coexist. When _path is omitted, the model root name is used as id.
// _on_create (optional) is called for every spawned instance of this model,
// after the global on_create, as (node, asset, model, id).
function poly_asset_add(_model, _kind = "prefab", _path = undefined, _on_create = undefined) {
  var _ed = __poly_inst();

  if (_ed == undefined) return undefined;
  if (!variable_struct_exists(_ed, "assets") || !is_array(_ed.assets)) _ed.assets = [];
  if (_model == undefined) return undefined;
  if (!is_string(_kind) || _kind == "") _kind = "prefab";
  var _root = __poly_model_key(_model);
  var _key = undefined;

  if (is_string(_path) && _path != "") {
    _key = _path;
  } else if (is_string(_root) && _root != "") {
    _key = _root;
  }

  if (!is_string(_key) || _key == "") return undefined;
  if (__poly_asset_get(_ed, _key) != undefined) return undefined;
  var _entry = { key: _key, model: _model, kind: _kind };

  if (is_string(_root) && _root != "") _entry.name = _root;
  else if (is_string(_key) && _key != "") {
    var _slash = string_last_pos("/", _key);
    var _base = (_slash > 0) ? string_copy(_key, _slash + 1, string_length(_key) - _slash) : _key;
    var _dot = string_last_pos(".", _base);
    if (_dot > 1) _base = string_copy(_base, 1, _dot - 1);
    if (_base != "") _entry.name = _base;
  }

  if (is_method(_on_create)) _entry.on_create = _on_create;
  array_push(_ed.assets, _entry);
  return _key;
}
