// poly_load — public API.

// Loads scene file into runtime scene (JSON or PLYB .bin, auto-detected
// by extension with magic fallback, so mislabeled files still load).
// _assets: struct mapping asset key -> { model, on_create? } (same
// shape as the poly_create config).
// _on_create (optional): function(node, asset, model, id) called for
// every spawned instance, before the per-model on_create. Model stays 3rd
// so existing hooks keep working unchanged.
// Actor bindings saved by the editor (top-level "assets" map:
// { key: { type: "model", actor: { object, layer } } }) spawn a companion
// GameMaker instance per bound model via instance_create_layer, receiving
// { node, poly_id, poly_asset_id }. Missing objects or
// layers never fail the load: they become report warnings.
// Returns { placed, failed, companions, warnings }.
function poly_load(_scene, _fname, _assets, _on_create = undefined) {
  var _rep = { placed: 0, failed: 0, companions: 0, warnings: [], placements: [] };

  if (_scene == undefined || _fname == undefined || _fname == "" || !is_struct(_assets)) return _rep;
  if (!file_exists(_fname)) return _rep;
  var _data = undefined;

  if (__poly_bin_is_path(_fname) || __poly_bin_has_magic(_fname)) {
    _data = __poly_bin_load_data(_fname);
  }

  if (_data == undefined) {
    var _json = "";
    var _f = file_text_open_read(_fname);

    if (_f < 0) return _rep;

    while (!file_text_eof(_f)) {
      _json += file_text_read_string(_f);
      file_text_readln(_f);
    }

    file_text_close(_f);

    if (_json == "") return _rep;

    try {
      _data = json_parse(_json);
    } catch (_ex) {
      return _rep;
    }
  }

  if (!is_struct(_data) || !variable_struct_exists(_data, "nodes") || !is_array(_data.nodes)) return _rep;
  var _actors = __poly_file_assets(_data);
  var _nodes = _data.nodes;

  for (var _i = 0, _nnod = array_length(_nodes); _i < _nnod; ++_i) {
    var _pl = __poly_load_node(_scene, _assets, _nodes[_i]);

    if (_pl == undefined) {
      _rep.failed++;
      continue;
    }

    _rep.placed++;
    if (!is_struct(_pl) || _pl.kind != "instance") continue;
    if (is_method(_on_create)) _on_create(_pl.node, _pl.asset, _pl.model, _pl.id);
    var _entry = _assets[$ _pl.asset];
    if (is_struct(_entry) && is_method(_entry[$ "on_create"])) _entry.on_create(_pl.node, _pl.asset, _pl.model, _pl.id);
    var _inst = undefined;

    if (__poly_load_actor(_actors, _pl, _rep)) {
      _rep.companions++;
      _inst = __poly_actor_of(_pl.id);
    }

    array_push(_rep.placements, { node: _pl.node, asset: _pl.asset, id: _pl.id, label: _pl.label, model: _pl.model, instance: _inst });
  }

  _scene.update(0);
  return _rep;
}
