// poly_load - public async API.

// Starts loading a scene file into a runtime scene (JSON v1 or PLYB .bin,
// auto-detected by extension with magic fallback, so mislabeled files
// still load). The file is parsed NOW (cheap); nodes spawn chunked across
// steps so big scenes never freeze: pump with poly_load_step().
// _assets: struct mapping asset key -> { model, on_create? } (same
// shape as the poly_create config).
// _on_create (optional): function(node, asset, model, id) called for
// every spawned instance, before the per-model on_create. Model stays 3rd
// so existing hooks keep working unchanged.
// _on_finish (optional): function(report) called once when the last node
// is placed. Report: { placed, failed, companions, warnings, placements }.
// Actor bindings saved by the editor (top-level "assets" map:
// { key: { type: "model", actor: { object, layer } } }) spawn a companion
// GameMaker instance per bound model via instance_create_layer, receiving
// { node, poly_id, poly_asset_id }. Missing objects or
// layers never fail the load: they become report warnings.
// Returns the job struct, or undefined when the file is missing/invalid.
// The scene must outlive the load.
function poly_load(_scene, _fname, _assets, _on_create = undefined, _on_finish = undefined) {
  if (_scene == undefined || _fname == undefined || _fname == "" || !is_struct(_assets)) return undefined;
  if (!file_exists(_fname)) return undefined;
  var _data = undefined;

  if (__poly_bin_is_path(_fname) || __poly_bin_has_magic(_fname)) _data = __poly_bin_load_data(_fname);

  if (_data == undefined) {
    var _json = "";
    var _f = file_text_open_read(_fname);

    if (_f < 0) return undefined;

    while (!file_text_eof(_f)) {
      _json += file_text_read_string(_f);
      file_text_readln(_f);
    }

    file_text_close(_f);

    if (_json == "") return undefined;

    _data = json_parse(_json);
  }

  if (!is_struct(_data) || !variable_struct_exists(_data, "nodes") || !is_array(_data.nodes)) return undefined;
  var _job = {
    scene: _scene,
    nodes: _data.nodes,
    idx: 0,
    assets: _assets,
    actors: __poly_file_assets(_data),
    on_create: _on_create,
    on_finish: _on_finish,
    physics: __poly_world_data(_data[$ "physics"]),
    report: { placed: 0, failed: 0, companions: 0, warnings: [], placements: [], physics: __poly_world_data(_data[$ "physics"]) },
  };
  __poly_load_jobs_push(_job);
  return _job;
}
