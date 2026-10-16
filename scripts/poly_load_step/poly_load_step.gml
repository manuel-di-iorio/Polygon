// poly_load_step — public API.

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
      __poly_load_place(_job, _job.nodes[_job.idx]);

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
