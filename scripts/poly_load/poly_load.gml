// poly_load — public async API.

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

  if (__poly_bin_is_path(_fname) || __poly_bin_has_magic(_fname)) {
    _data = __poly_bin_load_data(_fname);
  }

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

    try {
      _data = json_parse(_json);
    } catch (_ex) {
      return undefined;
    }
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
    report: { placed: 0, failed: 0, companions: 0, warnings: [], placements: [] },
  };
  __poly_load_jobs_push(_job);
  return _job;
}

// Advances all pending poly_load jobs (up to _budget nodes each).
// Call every Step while a job is alive; finished jobs fire on_finish
// and are dropped. Returns the pending job count.
function poly_load_step(_budget = 48) {
  if (!variable_global_exists("__poly_load_jobs") || !is_array(global.__poly_load_jobs)) {
    global.__poly_load_jobs = [];
    return 0;
  }

  var _jobs = global.__poly_load_jobs;
  var _b = (is_real(_budget) && _budget >= 1) ? floor(_budget) : 48;

  for (var _j = array_length(_jobs) - 1; _j >= 0; _j--) {
    var _job = _jobs[_j];

    if (!is_struct(_job) || _job.scene == undefined) {
      array_delete(_jobs, _j, 1);
      continue;
    }

    var _n = array_length(_job.nodes);
    var _stop = min(_n, _job.idx + _b);

    while (_job.idx < _stop) {
      try {
        __poly_load_place(_job, _job.nodes[_job.idx]);
      } catch (_ex) {
        _job.report.failed++;
      }

      _job.idx++;
    }

    if (_job.idx >= _n) {
      _job.scene.update(0);
      array_delete(_jobs, _j, 1);
      if (is_method(_job.on_finish)) _job.on_finish(_job.report);
    }
  }

  return array_length(_jobs);
}

// Queues a runtime load job.
function __poly_load_jobs_push(_job) {
  if (!variable_global_exists("__poly_load_jobs") || !is_array(global.__poly_load_jobs)) global.__poly_load_jobs = [];
  array_push(global.__poly_load_jobs, _job);
}

// Places one descriptor of a job (hooks, companions and report included).
function __poly_load_place(_job, _p) {
  var _rep = _job.report;
  var _pl = __poly_load_node(_job.scene, _job.assets, _p);

  if (_pl == undefined) {
    _rep.failed++;
    return;
  }

  _rep.placed++;
  if (!is_struct(_pl) || _pl.kind != "instance") return;
  if (is_method(_job.on_create)) _job.on_create(_pl.node, _pl.asset, _pl.model, _pl.id);
  var _entry = _job.assets[$ _pl.asset];
  if (is_struct(_entry) && is_method(_entry[$ "on_create"])) _entry.on_create(_pl.node, _pl.asset, _pl.model, _pl.id);
  var _inst = undefined;

  if (__poly_load_actor(_job.actors, _pl, _rep)) {
    _rep.companions++;
    _inst = __poly_actor_of(_pl.id);
  }

  array_push(_rep.placements, { node: _pl.node, asset: _pl.asset, id: _pl.id, label: _pl.label, model: _pl.model, instance: _inst });
}
