// polygon_ai — AI bridge: local TCP client to the Polygon MCP relay.
//
// The relay (other/mcp-relay, Node) listens on 127.0.0.1:5192. The game
// connects as a TCP client ONLY while the editor is active and the bridge
// is on (AI toolbar button). No socket is ever opened otherwise,
// so Polygon behaves exactly as before with no AI client attached.
//
// Wire protocol v1: compact JSON + "\n" (LF), UTF-8, both directions.
//   game  -> relay on connect: { "v": 1, "hello": "polygon-ai" }
//   relay -> game  (hello):    { "v": 1, "hello": "polygon-mcp-relay" }
//   relay -> game  (request):  { "id": "<uuid>", "op": "<op>", "params": { ... } }
//   game  -> relay (response): { "id": "<uuid>", "ok": true, "result": { ... } }
//                              { "id": "<uuid>", "ok": false, "error": "code: message" }
//
// Ops: status | hierarchy | selection | details | assets | raycast_down |
//      select | focus | create | transform | rename | delete | save | batch |
//      drop_to_ground | place_on
// Read ops expose world/model-space AABBs (see bounds below) so callers
// never guess Y: spawn with base_y / on_top_of, or snap with the two ops.
// Conventions (same as the scene format / save system):
//   - node identity is the stable wrapper id ("__PolygonEditor__N"), never the label.
//   - transforms are LOCAL to the wrapper node (it owns the instance transform).
//   - rotation input/output for create/transform is Euler DEGREES [rx, ry, rz],
//     XYZ order (same convention as library spawn defaults); details also
//     reports the stored quaternion [x, y, z, w].
//   - every mutation runs through the existing editor functions and is wrapped
//     in a history snapshot, so AI actions are undoable with Ctrl+Z.
// The bridge NEVER executes arbitrary GML: only the whitelisted ops above.

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

// Bridge diagnostics: always visible in the Output log (never on the socket).
function __polygon_ai_log(_msg) {
  show_debug_message("[polygon-ai] " + string(_msg));
}

// Verbose per-chunk log, gated behind _ed.ai_debug (default off).
function __polygon_ai_log_rx(_ed, _msg) {
  if (!is_struct(_ed) || !variable_struct_exists(_ed, "ai_debug") || _ed.ai_debug != true)  return;
  show_debug_message("[polygon-ai] " + string(_msg));
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

// Enables or disables the AI bridge (default off). Editor-internal: toggled
// from the AI button in the menu bar. When on, the editor connects to the
// relay at 127.0.0.1:_port while active.
function __polygon_ai_enable(_on = true, _port = 5192) {
  var _ed = __polygon_inst();

  if (_ed == undefined)  return false;
  var _ai = __polygon_ai_state(_ed);
  _ai.on = (_on == true);

  if (is_real(_port) && _port > 0 && _port < 65536)  _ai.port = floor(_port);
  __polygon_ai_log(_ai.on ? ("bridge on (port " + string(_ai.port) + ")") : "bridge off");

  if (_ai.on) {
    // Fresh toggle-on: immediate first attempt, backoff from 2s.
    _ai.retry_delay = 2;
    _ai.retry_tries = 0;
    _ai.retry_at = 0;
    _ai.ever = false;
    _ai.notice = "";
    _ai.notice_until = 0;
  } else {
    __polygon_ai_disconnect(_ed);
  }

  return _ai.on;
}

// ---------------------------------------------------------------------------
// State and step
// ---------------------------------------------------------------------------

// Returns the bridge state struct, creating it lazily.
function __polygon_ai_state(_ed) {
  if (!variable_struct_exists(_ed, "ai") || !is_struct(_ed.ai)) {
    _ed.ai = {
      on: false,
      port: 5192,
      sock: undefined,
      ready: false,
      connect_at: 0,
      rx: "",
      inbox: [],
      seen: {},
      seen_order: [],
      retry_at: 0,
      retry_delay: 2,
      retry_tries: 0,
      ever: false,
      notice: "",
      notice_until: 0,
    };
  }

  return _ed.ai;
}

// Records one failed attempt. Initial connects give up after 3 tries with a
// 10s notice; reconnects (a link existed before) retry forever with backoff.
function __polygon_ai_failed(_ed, _why) {
  var _ai = __polygon_ai_state(_ed);
  _ai.retry_tries++;

  if (!_ai.ever && _ai.retry_tries >= 3) {
    _ai.on = false;
    __polygon_ai_disconnect(_ed);
    _ai.notice = "AI Server not available";
    _ai.notice_until = current_time + 10000;
    __polygon_ai_log("relay unavailable after 3 attempts");
    return;
  }

  _ai.retry_at = current_time + _ai.retry_delay * 1000;
  __polygon_ai_log(_why + ", retry in " + string(_ai.retry_delay) + "s");
  _ai.retry_delay = min(_ai.retry_delay + 2, 30);
}

// Link state for UI: 0 = off, 1 = connecting, 2 = reconnecting, 3 = linked.
function __polygon_ai_link(_ed) {
  var _ai = __polygon_ai_state(_ed);

  if (!_ai.on)  return 0;
  if (_ai.sock != undefined && _ai.ready)  return 3;
  return _ai.ever ? 2 : 1;
}

// Per-frame pump, called from polygon_step(). Handles connect retry when
// active+enabled, clean disconnect otherwise, and inbox execution.
function __polygon_ai_step(_ed) {
  if (_ed == undefined)  return;
  var _ai = __polygon_ai_state(_ed);

  if (!_ed.active || !_ai.on) {
    if (_ai.sock != undefined)  __polygon_ai_disconnect(_ed);
    _ai.inbox = [];
    _ai.rx = "";
    return;
  }

  if (_ai.sock == undefined) {
    if (current_time >= _ai.retry_at) {
      if (__polygon_ai_connect(_ed)) {
        // Wait for the async result; failures go through __polygon_ai_failed.
        _ai.retry_at = current_time + 30000;
      } else {
        __polygon_ai_failed(_ed, "relay unreachable");
      }
    }

    return;
  }

  // Connecting but no async answer within 5s: drop and count it.
  if (!_ai.ready && current_time - _ai.connect_at > 5000) {
    __polygon_ai_disconnect(_ed);
    __polygon_ai_failed(_ed, "connect timed out");
    return;
  }

  if (!_ai.ready)  return;
  var _budget = 8;

  while (array_length(_ai.inbox) > 0 && _budget > 0) {
    _budget--;
    var _msg = array_shift(_ai.inbox);
    var _res = undefined;

    try {
      if (is_struct(_msg) && variable_struct_exists(_msg, "op"))  __polygon_ai_log("op " + string(_msg.op) + " " + string(_msg.id));
      _res = __polygon_ai_exec(_ed, _msg);
    } catch (_ex) {
      __polygon_ai_log("exec crashed: " + string(_ex));
      _res = is_struct(_msg) && is_string(_msg.id)
        ? __polygon_ai_fail(_msg.id, "crashed", string(_ex))
        : undefined;
    }

    if (_res != undefined) {
      var _id = is_struct(_msg) && variable_struct_exists(_msg, "id") ? _msg.id : undefined;

      if (is_string(_id)) {
        _ai.seen[$ _id] = _res;
        array_push(_ai.seen_order, _id);

        while (array_length(_ai.seen_order) > 128) {
          var _old = array_shift(_ai.seen_order);
          variable_struct_remove(_ai.seen, _old);
        }
      }

      if (!__polygon_ai_send(_ed, _res))  break;
    }
  }
}

// ---------------------------------------------------------------------------
// Connection
// ---------------------------------------------------------------------------

// Opens the TCP client socket to the relay (non-blocking: the result
// arrives in the Async Networking event as network_type_non_blocking_connect).
function __polygon_ai_connect(_ed) {
  var _ai = __polygon_ai_state(_ed);
  __polygon_ai_disconnect(_ed);

  var _sock = network_create_socket(network_socket_tcp);

  if (_sock < 0) {
    __polygon_ai_log("socket create failed");
    return false;
  }

  if (network_connect_raw_async(_sock, "127.0.0.1", _ai.port) < 0) {
    network_destroy(_sock);
    return false;
  }

  _ai.sock = _sock;
  _ai.ready = false;
  _ai.connect_at = current_time;
  _ai.rx = "";
  return true;
}

// Closes the relay socket, if any.
function __polygon_ai_disconnect(_ed) {
  if (_ed == undefined || !variable_struct_exists(_ed, "ai") || !is_struct(_ed.ai))  return;
  var _ai = _ed.ai;

  if (_ai.sock != undefined) {
    __polygon_ai_log("disconnected");
    network_destroy(_ai.sock);
    _ai.sock = undefined;
  }

  _ai.ready = false;
  _ai.rx = "";
  _ai.inbox = [];
}

// Sends one compact JSON line to the relay. False when the link is down.
function __polygon_ai_send(_ed, _map) {
  var _ai = __polygon_ai_state(_ed);

  if (_ai.sock == undefined || !_ai.ready)  return false;
  var _json = json_stringify(_map) + chr(10);
  var _len = string_byte_length(_json);
  var _buf = buffer_create(_len, buffer_fixed, 1);
  buffer_write(_buf, buffer_text, _json);
  network_send_raw(_ai.sock, _buf, buffer_tell(_buf));
  buffer_delete(_buf);
  return true;
}

// ---------------------------------------------------------------------------
// Async Networking event (oEditor, Other_11)
// ---------------------------------------------------------------------------

// Handles relay traffic: data chunks (framed lines) and link loss.
// Public entry point, called from the oEditor Async Networking event.
function polygon_ai_net() {
  var _ed = __polygon_inst();

  if (_ed == undefined || async_load == undefined)  return;
  var _ai = __polygon_ai_state(_ed);
  var _type = async_load[? "type"];

  if (_type == network_type_non_blocking_connect) {
    if (async_load[? "id"] != _ai.sock || _ai.ready)  return;
    if (async_load[? "succeeded"] == true) {
      _ai.ready = true;
      _ai.ever = true;
      _ai.retry_delay = 2;
      _ai.retry_tries = 0;
      __polygon_ai_log("connected to relay 127.0.0.1:" + string(_ai.port));
      __polygon_ai_send(_ed, { v: 1, hello: "polygon-ai" });
    } else {
      __polygon_ai_disconnect(_ed);
      __polygon_ai_failed(_ed, "connect refused");
    }

    return;
  }

  if (_type == network_type_data) {
    if (async_load[? "id"] != _ai.sock)  return;
    var _buf = async_load[? "buffer"];

    if (_buf == undefined)  return;
    buffer_seek(_buf, buffer_seek_start, 0);
    var _chunk = buffer_read(_buf, buffer_text);
    __polygon_ai_log_rx(_ed, "rx " + string(string_length(_chunk)) + " chars");
    __polygon_ai_frame(_ed, _chunk);
    return;
  }

  if (_type == network_type_down || _type == network_type_disconnect)  __polygon_ai_disconnect(_ed);
}

// Appends a chunk, splits complete lines, parses and queues requests.
function __polygon_ai_frame(_ed, _chunk) {
  var _ai = __polygon_ai_state(_ed);

  if (!is_string(_chunk) || _chunk == "")  return;
  _ai.rx += _chunk;

  if (string_length(_ai.rx) > 1000000) {
    _ai.rx = "";
    _ai.inbox = [];
    return;
  }

  var _lines = string_split(_ai.rx, chr(10));
  _ai.rx = _lines[array_length(_lines) - 1];

  for (var _i = 0, _n = array_length(_lines) - 1; _i < _n; _i++) {
    var _line = _lines[_i];

    if (_line == "")  continue;
    if (string_char_at(_line, 1) != "{" || string_char_at(_line, string_length(_line)) != "}")  continue;
    var _msg = json_parse(_line);

    if (!is_struct(_msg))  continue;
    // Relay hello (no id): version gate, then drop.
    if (!variable_struct_exists(_msg, "id")) {
      if (variable_struct_exists(_msg, "hello") && _msg.hello == "polygon-mcp-relay") {
        if (!variable_struct_exists(_msg, "v") || _msg.v != 1) {
          __polygon_ai_log("protocol mismatch, dropping");
          __polygon_ai_disconnect(_ed);
        } else {
          __polygon_ai_log("handshake ok (protocol v1)");
        }
      }

      continue;
    }

    // Idempotent replay: resend cached response without re-executing.
    if (is_string(_msg.id) && variable_struct_exists(_ai.seen, _msg.id)) {
      __polygon_ai_send(_ed, _ai.seen[$ _msg.id]);
      continue;
    }

    if (array_length(_ai.inbox) < 512)  array_push(_ai.inbox, _msg);
  }
}

// ---------------------------------------------------------------------------
// Execution
// ---------------------------------------------------------------------------

// Modal UI open: mutations would conflict with dialogs/inline rename.
// Builds an error response.
function __polygon_ai_fail(_id, _code, _msg) {
  return { id: _id, ok: false, error: _code + ": " + _msg };
}

// Validates a 3-number vector param.
function __polygon_ai_num3(_v) {
  return is_array(_v) && array_length(_v) == 3 && is_real(_v[0]) && is_real(_v[1]) && is_real(_v[2])
    && !is_nan(_v[0]) && !is_nan(_v[1]) && !is_nan(_v[2])
    && abs(_v[0]) < 1000000000 && abs(_v[1]) < 1000000000 && abs(_v[2]) < 1000000000;
}

// Resolves a tracked, non-system node by stable id. Returns the node,
// or undefined when unknown/untracked/system (callers report not_found).
function __polygon_ai_node(_ed, _id) {
  if (!is_string(_id) || _id == "")  return undefined;
  var _node = __polygon_find_by_id(_ed, _id);

  if (_node == undefined || __polygon_registry_find(_ed, _node) == undefined)  return undefined;
  if (__polygon_is_grid(_ed, _node) || __polygon_is_sky(_node))  return undefined;
  return _node;
}

// ---------------------------------------------------------------------------
// Shared param validators (single source for single ops + batch dry-run).
// Each returns undefined when valid, else the reason string, so composites
// chain with ??. Ops wrap the reason into {error...}; __polygon_ai_check
// returns it ("" only at the end of a satisfied chain).
// ---------------------------------------------------------------------------

// Required id-string field.
function __polygon_ai_v_id(_p) {
  if (!variable_struct_exists(_p, "id") || !is_string(_p[$ "id"]))  return "id (string) required";
  return undefined;
}

// Required id-string field that must resolve to a node.
function __polygon_ai_v_node(_ed, _p, _req_msg) {
  var _r = __polygon_ai_v_id(_p);

  if (_r != undefined)  return _req_msg == undefined ? _r : _req_msg;
  return __polygon_ai_v_resolve(_ed, _p);
}

// Resolves _p.id, reporting unknown nodes.
function __polygon_ai_v_resolve(_ed, _p) {
  if (__polygon_ai_node(_ed, _p[$ "id"]) == undefined)  return "unknown or system node: " + _p[$ "id"];
  return undefined;
}

// vec3 field: required (missing or bad -> _req_msg) or optional (bad -> _bad_msg).
function __polygon_ai_v_vec3(_p, _k, _required, _req_msg, _bad_msg) {
  if (!variable_struct_exists(_p, _k))  return _required ? _req_msg : undefined;
  if (!__polygon_ai_num3(_p[$ _k]))  return _required ? _req_msg : _bad_msg;
  return undefined;
}

// Optional bounded number field (|v| < 1e9, not NaN).
function __polygon_ai_v_num(_p, _k, _msg) {
  if (!variable_struct_exists(_p, _k))  return undefined;
  var _v = _p[$ _k];

  if (!is_real(_v) || is_nan(_v) || abs(_v) >= 1000000000)  return _msg;
  return undefined;
}

// Optional node-id-string field.
function __polygon_ai_v_idstr(_p, _k, _msg) {
  if (!variable_struct_exists(_p, _k))  return undefined;
  var _v = _p[$ _k];

  if (!is_string(_v) || _v == "")  return _msg;
  return undefined;
}

// Builds a raw error struct.
function __polygon_ai_err(_code, _msg) {
  return { error: true, error_code: _code, error_msg: _msg };
}

// Maps a validator reason to its error code (protocol-stable).
function __polygon_ai_v_code(_reason) {
  if (string_pos("unknown or system node", _reason) == 1)  return "not_found";
  if (string_pos("asset not in library", _reason) == 1)  return "unknown_asset";
  return "bad_params";
}

// Wraps a validator reason into an op error struct.
function __polygon_ai_v_err(_reason) {
  return __polygon_ai_err(__polygon_ai_v_code(_reason), _reason);
}

// Validates create params.
function __polygon_ai_v_create(_ed, _p) {
  if (!variable_struct_exists(_p, "asset") || !is_string(_p[$ "asset"]) || _p[$ "asset"] == "")  return "asset (library key) required";
  return __polygon_ai_v_vec3(_p, "position", true, "position ([x, y, z] numbers) required", undefined)
    ?? __polygon_ai_v_vec3(_p, "rotation", false, undefined, "rotation must be [rx, ry, rz] euler degrees")
    ?? __polygon_ai_v_vec3(_p, "scale", false, undefined, "scale must be [sx, sy, sz] numbers")
    ?? __polygon_ai_v_num(_p, "base_y", "base_y must be a number (world bottom Y)")
    ?? __polygon_ai_v_idstr(_p, "on_top_of", "on_top_of must be a node id string")
    ?? __polygon_ai_v_num(_p, "gap", "gap must be a number")
    ?? __polygon_ai_v_exclusive(_p)
    ?? __polygon_ai_v_asset(_ed, _p)
    ?? __polygon_ai_v_onsupport(_ed, _p);
}

// Rejects base_y + on_top_of together.
function __polygon_ai_v_exclusive(_p) {
  if (variable_struct_exists(_p, "base_y") && variable_struct_exists(_p, "on_top_of"))  return "use only one of base_y / on_top_of";
  return undefined;
}

// Checks the asset is in the library with a model.
function __polygon_ai_v_asset(_ed, _p) {
  var _entry = __polygon_asset_get(_ed, _p[$ "asset"]);

  if (_entry == undefined || _entry.model == undefined)  return "asset not in library: " + _p[$ "asset"];
  return undefined;
}

// Resolves the on_top_of support node when present.
function __polygon_ai_v_onsupport(_ed, _p) {
  if (!variable_struct_exists(_p, "on_top_of"))  return undefined;
  if (__polygon_ai_node(_ed, _p[$ "on_top_of"]) == undefined)  return "unknown or system node: " + _p[$ "on_top_of"];
  return undefined;
}

// Validates transform params.
function __polygon_ai_v_transform(_ed, _p) {
  var _r = __polygon_ai_v_id(_p);

  if (_r != undefined)  return _r;
  _r = __polygon_ai_v_oneof(_p);

  if (_r != undefined)  return _r;
  return __polygon_ai_v_vec3(_p, "position", false, undefined, "position must be [x, y, z] numbers")
    ?? __polygon_ai_v_vec3(_p, "rotation", false, undefined, "rotation must be [rx, ry, rz] euler degrees")
    ?? __polygon_ai_v_vec3(_p, "scale", false, undefined, "scale must be [sx, sy, sz] numbers")
    ?? __polygon_ai_v_node(_ed, _p);
}

// Requires one of position/rotation/scale.
function __polygon_ai_v_oneof(_p) {
  if (!variable_struct_exists(_p, "position") && !variable_struct_exists(_p, "rotation") && !variable_struct_exists(_p, "scale"))  return "one of position/rotation/scale required";
  return undefined;
}

// Validates rename params.
function __polygon_ai_v_rename(_ed, _p) {
  var _r = __polygon_ai_v_id(_p);

  if (_r != undefined)  return _r;
  _r = __polygon_ai_v_label(_p);

  if (_r != undefined)  return _r;
  return __polygon_ai_v_node(_ed, _p);
}

// Validates the rename label.
function __polygon_ai_v_label(_p) {
  var _lb = _p[$ "label"];

  if (!is_string(_lb) || _lb == "" || string_length(_lb) > 64)  return "label (1..64 chars) required";
  return undefined;
}

// Resolves an ids array (non-empty when _nonempty).
function __polygon_ai_v_ids(_ed, _p, _nonempty) {
  if (!variable_struct_exists(_p, "ids") || !is_array(_p[$ "ids"]) || (_nonempty && array_length(_p[$ "ids"]) == 0))  return _nonempty ? "ids (non-empty array) required" : "ids (array of string) required";
  var _ids = _p[$ "ids"];

  for (var _i = 0, _n = array_length(_ids); _i < _n; _i++) {
    var _node = __polygon_ai_node(_ed, _ids[_i]);

    if (_node == undefined || (_nonempty && _ed.rt != undefined && __polygon_node_same(_node, _ed.rt.cam)))  return "unknown or system node: " + string(_ids[_i]);
  }

  return undefined;
}

// Validates drop_to_ground params.
function __polygon_ai_v_drop(_ed, _p) {
  var _r = __polygon_ai_v_id(_p);

  if (_r != undefined)  return _r;
  _r = __polygon_ai_v_num(_p, "ground_y", "ground_y must be a number");

  if (_r != undefined)  return _r;
  return __polygon_ai_v_node(_ed, _p);
}

// Validates place_on params.
function __polygon_ai_v_stack(_ed, _p) {
  var _r = __polygon_ai_v_id(_p);

  if (_r != undefined)  return _r;
  _r = __polygon_ai_v_idstr(_p, "on", "on (support node id) required");

  if (_r != undefined)  return _r;
  _r = __polygon_ai_v_num(_p, "gap", "gap must be a number");

  if (_r != undefined)  return _r;
  _r = __polygon_ai_v_node(_ed, _p);

  if (_r != undefined)  return _r;
  if (__polygon_ai_node(_ed, _p[$ "on"]) == undefined)  return "unknown or system node: " + _p[$ "on"];
  return undefined;
}

// Reads a wrapper transform as plain data (quaternion + euler degrees).
function __polygon_ai_transform_of(_node) {
  var _pos = _node.getLocalPosition();
  var _rot = _node.getLocalRotation();
  var _sca = _node.getLocalScale();

  if (_pos == undefined || _rot == undefined || _sca == undefined)  return undefined;
  var _e = __polygon_quat_to_euler(_rot);
  return {
    position: [ _pos.x, _pos.y, _pos.z ],
    rotation_quat: [ _rot.x, _rot.y, _rot.z, _rot.w ],
    rotation_euler_deg: [ radtodeg(_e[0]), radtodeg(_e[1]), radtodeg(_e[2]) ],
    scale: [ _sca.x, _sca.y, _sca.z ],
  };
}

// Summarizes one tracked root for hierarchy/selection output.
function __polygon_ai_node_info(_ed, _node) {
  var _en = __polygon_registry_find(_ed, _node);

  if (_en == undefined)  return undefined;
  var _info = {
    id: _en.id,
    kind: is_string(_en.kind) ? _en.kind : "instance",
    label: is_string(_en.label) ? _en.label : _en.id,
    asset: is_string(_en.asset) ? _en.asset : "",
    selected: __polygon_sel_has(_ed, _node),
    hidden: _en.hidden == true,
    locked: _en.locked == true,
  };
  var _t = __polygon_ai_transform_of(_node);

  if (_t != undefined)  _info.transform = _t;
  // World-space AABB (uses the existing __polygon_node_aabb helper):
  // { valid, min:[x,y,z], max, size, center, bottom, top }.
  // bottom/top are world Y: rest objects with bottom == support top.
  var _b = __polygon_ai_bounds_of(_node);

  if (_b != undefined)  _info.bounds = _b;
  return _info;
}

// Computes the world-space AABB of a wrapper subtree as plain data.
// Returns { valid:false } when the subtree has no measurable geometry.
function __polygon_ai_bounds_of(_node) {
  if (_node == undefined) {
    return { valid: false };
  }

  var _box = __polygon_node_aabb(_node);

  if (!is_struct(_box) || _box.valid != true || _box.min == undefined || _box.max == undefined) {
    return { valid: false };
  }

  var _mn = _box.min;
  var _mx = _box.max;
  return {
    valid: true,
    min: [ _mn.x, _mn.y, _mn.z ],
    max: [ _mx.x, _mx.y, _mx.z ],
    size: [ _mx.x - _mn.x, _mx.y - _mn.y, _mx.z - _mn.z ],
    center: [ (_mn.x + _mx.x) * 0.5, (_mn.y + _mx.y) * 0.5, (_mn.z + _mx.z) * 0.5 ],
    bottom: _mn.y,
    top: _mx.y,
  };
}

// Shifts a root wrapper vertically so its world bottom lands on
// _desired (world Y). Wrappers live at scene root, so a local Y shift
// equals a world shift; one correction is exact for translations.
// Returns the fresh world bounds, or undefined when unmeasurable.
function __polygon_ai_snap_bottom(_ed, _node, _desired) {
  if (_ed == undefined || _node == undefined || !is_real(_desired))  return undefined;
  _ed.rt.scene.update(0);
  var _before = __polygon_ai_bounds_of(_node);

  if (!is_struct(_before) || _before.valid != true)  return undefined;
  var _dy = _desired - _before.bottom;

  if (abs(_dy) > 0.000001) {
    var _pos = _node.getLocalPosition();
    _node.setLocalPosition(new GM3D_Vec3(_pos.x, _pos.y + _dy, _pos.z));
    _ed.rt.scene.update(0);
  }

  return __polygon_ai_bounds_of(_node);
}

// Executes one relay request, returning the response map.
function __polygon_ai_exec(_ed, _msg) {
  if (!is_struct(_msg) || !is_string(_msg.id) || !is_string(_msg.op))  return undefined;
  var _id = _msg.id;
  var _op = _msg.op;
  var _p = (variable_struct_exists(_msg, "params") && is_struct(_msg.params)) ? _msg.params : {};

  // Mutations are rejected while a dialog/inline gesture owns the scene.
  switch (_op) {
    case "select": case "focus": case "create": case "transform":
    case "rename": case "delete": case "save": case "batch":
    case "drop_to_ground": case "place_on":
      if (_ed.confirm != undefined || _ed.about != undefined || _ed.scene_dlg != undefined
        || _ed.delete_confirm != undefined || _ed.giz.drag != -1) {
        return __polygon_ai_fail(_id, "busy", "editor dialog or drag in progress");
      }
      break;
  }

  var _r = undefined;

  switch (_op) {
    case "status": _r = __polygon_ai_op_status(_ed); break;
    case "hierarchy": _r = __polygon_ai_op_hierarchy(_ed); break;
    case "selection": _r = __polygon_ai_op_selection(_ed); break;
    case "assets": _r = __polygon_ai_op_assets(_ed); break;
    case "details": _r = __polygon_ai_op_details(_ed, _p); break;
    case "select": _r = __polygon_ai_op_select(_ed, _p); break;
    case "focus": _r = __polygon_ai_op_focus(_ed, _p); break;
    case "create": _r = __polygon_ai_op_create(_ed, _p, true); break;
    case "transform": _r = __polygon_ai_op_transform(_ed, _p, true); break;
    case "rename": _r = __polygon_ai_op_rename(_ed, _p, true); break;
    case "delete": _r = __polygon_ai_op_delete(_ed, _p, true); break;
    case "save": _r = __polygon_ai_op_save(_ed, _p); break;
    case "batch": _r = __polygon_ai_op_batch(_ed, _p); break;
    case "raycast_down": _r = __polygon_ai_op_raycast(_ed, _p); break;
    case "drop_to_ground": _r = __polygon_ai_op_drop(_ed, _p, true); break;
    case "place_on": _r = __polygon_ai_op_stack(_ed, _p, true); break;
    default: return __polygon_ai_fail(_id, "unknown_op", "unsupported op: " + _op);
  }

  if (!is_struct(_r))  return __polygon_ai_fail(_id, "failed", "empty result for op: " + _op);
  if (variable_struct_exists(_r, "error"))  return __polygon_ai_fail(_id, _r.error_code, _r.error_msg);
  return { id: _id, ok: true, result: _r };
}

// ---------------------------------------------------------------------------
// Read ops
// ---------------------------------------------------------------------------

function __polygon_ai_op_status(_ed) {
  return {
    bridge: "polygon-ai/1",
    active: _ed.active == true,
    tracked: __polygon_reg_count(_ed),
    selected: is_array(_ed.sel) ? array_length(_ed.sel) : 0,
    scene_file: is_string(_ed.scene_file) ? _ed.scene_file : "",
    dirty: _ed.dirty == true,
  };
}

function __polygon_ai_op_hierarchy(_ed) {
  var _pairs = __polygon_root_pairs(_ed);
  var _out = [];

  for (var _i = 0, _n = array_length(_pairs); _i < _n; _i++) {
    var _info = __polygon_ai_node_info(_ed, _pairs[_i].node);

    if (_info != undefined)  array_push(_out, _info);
  }

  return { nodes: _out };
}

function __polygon_ai_op_selection(_ed) {
  var _out = [];

  if (is_array(_ed.sel)) {
    for (var _i = 0, _n = array_length(_ed.sel); _i < _n; _i++) {
      var _info = __polygon_ai_node_info(_ed, _ed.sel[_i]);

      if (_info != undefined)  array_push(_out, _info);
    }
  }

  return { nodes: _out };
}

function __polygon_ai_op_assets(_ed) {
  var _out = [];

  if (is_array(_ed.assets)) {
    for (var _i = 0, _n = array_length(_ed.assets); _i < _n; _i++) {
      var _entry = _ed.assets[_i];

      if (is_struct(_entry) && is_string(_entry.key)) {
        var _item = { key: _entry.key, label: __polygon_asset_label(_entry) };
        // Model-space bounds + pivot: bottom is the model-space min Y,
        // so resting Y = supportTopY - bottom * scaleY (before rotation).
        // origin is "base" (bottom ~= 0), "center", or "custom".
        var _ab = __polygon_asset_bounds(_entry);

        if (is_struct(_ab))  _item.bounds = _ab;
        array_push(_out, _item);
      }
    }
  }

  return { assets: _out };
}

function __polygon_ai_op_details(_ed, _p) {
  if (!variable_struct_exists(_p, "id") || !is_string(_p.id))  return __polygon_ai_err("bad_params", "id (string) required");
  var _node = __polygon_ai_node(_ed, _p.id);

  if (_node == undefined)  return __polygon_ai_err("not_found", "unknown or system node: " + _p.id);
  var _desc = __polygon_node_to_descriptor(_ed, _node);

  if (_desc == undefined)  return __polygon_ai_err("not_found", "no descriptor for: " + _p.id);
  _desc.selected = __polygon_sel_has(_ed, _node);
  // World-space AABB of this instance + model-space bounds of its asset,
  // so callers can rest objects exactly (bottom == support top).
  var _wb = __polygon_ai_bounds_of(_node);

  if (is_struct(_wb))  _desc.bounds = _wb;
  var _en = __polygon_registry_find(_ed, _node);

  if (_en != undefined && is_string(_en.asset) && _en.asset != "") {
    var _ab2 = __polygon_asset_bounds(__polygon_asset_get(_ed, _en.asset));

    if (is_struct(_ab2))  _desc.asset_bounds = _ab2;
  }

  return _desc;
}

// ---------------------------------------------------------------------------
// Write ops (each takes _commit: single ops commit alone, batch commits once)
// ---------------------------------------------------------------------------

function __polygon_ai_op_select(_ed, _p) {
  if (!variable_struct_exists(_p, "ids") || !is_array(_p.ids))  return __polygon_ai_err("bad_params", "ids (array of string) required");
  var _nodes = [];
  var _missing = [];
  var _locked = [];

  for (var _i = 0, _n = array_length(_p.ids); _i < _n; _i++) {
    var _node = __polygon_ai_node(_ed, _p.ids[_i]);

    if (_node == undefined) {
      array_push(_missing, _p.ids[_i]);
      continue;
    }

    if (__polygon_locked_get(_ed, _node)) {
      array_push(_locked, _p.ids[_i]);
      continue;
    }

    array_push(_nodes, _node);
  }

  if (array_length(_missing) > 0)  return __polygon_ai_err("not_found", "unknown node(s): " + json_stringify(_missing));
  __polygon_sel_assign(_ed, _nodes);
  _ed.giz.hover = -1;
  _ed.scene_anchor = array_length(_nodes) > 0 ? _nodes[0] : undefined;
  _ed.view_dirty = true;

  var _ids = [];

  for (var _j = 0, _m = array_length(_nodes); _j < _m; _j++) {
    var _en = __polygon_registry_find(_ed, _nodes[_j]);
    array_push(_ids, _en != undefined ? _en.id : "?");
  }

  return { selected: _ids, skipped_locked: _locked };
}

function __polygon_ai_op_focus(_ed, _p) {
  if (!variable_struct_exists(_p, "id") || !is_string(_p.id))  return __polygon_ai_err("bad_params", "id (string) required");
  var _node = __polygon_ai_node(_ed, _p.id);

  if (_node == undefined)  return __polygon_ai_err("not_found", "unknown or system node: " + _p.id);
  if (__polygon_view_focus_node(_ed, _node) != true)  return __polygon_ai_err("failed", "cannot focus: " + _p.id);
  return { focused: _p.id };
}

function __polygon_ai_op_create(_ed, _p, _commit) {
  var _vr = __polygon_ai_v_create(_ed, _p);

  if (_vr != undefined)  return __polygon_ai_v_err(_vr);
  var _rot = _p[$ "rotation"] ?? [ 0, 0, 0 ];
  var _sca = [ 1, 1, 1 ];

  if (variable_struct_exists(_p, "scale"))  _sca = [ max(_p.scale[0], 0.01), max(_p.scale[1], 0.01), max(_p.scale[2], 0.01) ];
  // Optional resting: base_y (world bottom target), on_top_of (support id),
  // gap (extra lift, default 0). X/Z always come from position; Y is
  // corrected after spawn by measuring the real world AABB, so any pivot
  // convention (base/center) lands exactly.
  var _base_y = _p[$ "base_y"];
  var _on_id = _p[$ "on_top_of"];
  var _gap = _p[$ "gap"] ?? 0.0;

  var _entry = __polygon_asset_get(_ed, _p.asset);

  // Fail fast on unknown support before touching the scene.
  var _support = _on_id != undefined ? __polygon_ai_node(_ed, _on_id) : undefined;

  var _base = __polygon_asset_label(_entry);

  if (variable_struct_exists(_p, "label") && is_string(_p.label) && _p.label != "")  _base = _p.label;
  var _before = _commit ? __polygon_history_snap(_ed) : undefined;
  var _node = __polygon_place(
    _ed,
    _p.asset,
    _entry.model,
    [ _p.position[0], _p.position[1], _p.position[2] ],
    __polygon_euler_to_quat(degtorad(_rot[0]), degtorad(_rot[1]), degtorad(_rot[2])),
    _sca,
    __polygon_fresh_label(_ed, _base)
  );

  if (_node == undefined)  return __polygon_ai_err("failed", "spawn failed for asset: " + _p.asset);
  __polygon_spawn_shadow_apply(_ed, _entry, _node);
  _ed.rt.scene.update(0);

  // Resting correction (measured, not guessed).
  var _bounds = __polygon_ai_bounds_of(_node);

  if (_on_id != undefined || _base_y != undefined) {
    var _want = undefined;

    if (_on_id != undefined) {
      var _sb = __polygon_ai_bounds_of(_support);

      if (!is_struct(_sb) || _sb.valid != true) {
        __polygon_spawn_unregister(_ed, _node);
        __polygon_destroy_subtree(_node);
        _ed.rt.scene.update(0);
        return __polygon_ai_err("failed", "support has no measurable bounds: " + _on_id);
      }

      _want = _sb.top + _gap;
    } else {
      _want = _base_y + _gap;
    }

    _bounds = __polygon_ai_snap_bottom(_ed, _node, _want);

    if (!is_struct(_bounds) || _bounds.valid != true) {
      __polygon_spawn_unregister(_ed, _node);
      __polygon_destroy_subtree(_node);
      _ed.rt.scene.update(0);
      return __polygon_ai_err("failed", "spawned node has no measurable bounds");
    }
  }

  var _en = __polygon_registry_find(_ed, _node);
  __polygon_sel_assign(_ed, [ _node ]);

  if (_commit)  __polygon_history_commit(_ed, _before);
  var _res = { id: _en != undefined ? _en.id : _node.name, label: _en != undefined ? _en.label : "" };

  if (is_struct(_bounds) && _bounds.valid == true)  _res.bounds = _bounds;
  return _res;
}

// Casts a vertical ray down from (x, from_y, z) and reports the first hit:
// the highest tracked top at/below from_y whose XZ footprint contains the
// point. No physics involved (the editor scene has no PhysicsWorld): the
// "ray" is resolved by scanning world AABBs. Read-only.
// Returns { found:false } or { found:true, top, id }.
function __polygon_ai_op_raycast(_ed, _p) {
  if (!variable_struct_exists(_p, "x") || !is_real(_p.x) || is_nan(_p.x) || abs(_p.x) >= 1000000000)  return __polygon_ai_err("bad_params", "x (number) required");
  if (!variable_struct_exists(_p, "z") || !is_real(_p.z) || is_nan(_p.z) || abs(_p.z) >= 1000000000)  return __polygon_ai_err("bad_params", "z (number) required");
  var _from = 1000000000.0;

  if (variable_struct_exists(_p, "from_y")) {
    if (!is_real(_p.from_y) || is_nan(_p.from_y) || abs(_p.from_y) >= 1000000000)  return __polygon_ai_err("bad_params", "from_y must be a number (ray origin height)");
    _from = _p.from_y;
  }

  var _ignore = undefined;

  if (variable_struct_exists(_p, "ignore") && is_string(_p.ignore) && _p.ignore != "")  _ignore = _p.ignore;
  var _eps = 0.001;
  var _best_top = undefined;
  var _best_id = undefined;
  var _pairs = __polygon_root_pairs(_ed);

  for (var _i = 0, _n = array_length(_pairs); _i < _n; _i++) {
    var _en = _pairs[_i].en;

    if (_en == undefined || !is_string(_en.id))  continue;
    if (_ignore != undefined && _en.id == _ignore)  continue;
    var _b = __polygon_ai_bounds_of(_pairs[_i].node);

    if (!is_struct(_b) || _b.valid != true)  continue;
    if (_p.x < _b.min[0] - _eps || _p.x > _b.max[0] + _eps)  continue;
    if (_p.z < _b.min[2] - _eps || _p.z > _b.max[2] + _eps)  continue;
    if (_b.top > _from + _eps)  continue;
    if (_best_top == undefined || _b.top > _best_top) {
      _best_top = _b.top;
      _best_id = _en.id;
    }
  }

  if (_best_top == undefined) {
    return { found: false };
  }

  return { found: true, top: _best_top, id: _best_id };
}

// Snaps one node so its world bottom rests on ground_y (default 0).
function __polygon_ai_op_drop(_ed, _p, _commit) {
  var _vr = __polygon_ai_v_drop(_ed, _p);

  if (_vr != undefined)  return __polygon_ai_v_err(_vr);
  var _gy = _p[$ "ground_y"] ?? 0.0;
  var _node = __polygon_ai_node(_ed, _p.id);

  if (__polygon_locked_get(_ed, _node))  return __polygon_ai_err("locked", "node is locked: " + _p.id);
  var _before = _commit ? __polygon_history_snap(_ed) : undefined;
  var _b = __polygon_ai_snap_bottom(_ed, _node, _gy);

  if (!is_struct(_b) || _b.valid != true)  return __polygon_ai_err("failed", "node has no measurable bounds: " + _p.id);
  if (_commit)  __polygon_history_commit(_ed, _before);
  return { id: _p.id, ground_y: _gy, bounds: _b };
}

// Rests one node on top of another (bottom = support top + gap).
function __polygon_ai_op_stack(_ed, _p, _commit) {
  var _vr = __polygon_ai_v_stack(_ed, _p);

  if (_vr != undefined)  return __polygon_ai_v_err(_vr);
  var _gap = _p[$ "gap"] ?? 0.0;
  var _node = __polygon_ai_node(_ed, _p.id);

  if (__polygon_locked_get(_ed, _node))  return __polygon_ai_err("locked", "node is locked: " + _p.id);
  var _support = __polygon_ai_node(_ed, _p.on);

  if (_support == undefined)  return __polygon_ai_err("not_found", "unknown or system node: " + _p.on);
  var _sb = __polygon_ai_bounds_of(_support);

  if (!is_struct(_sb) || _sb.valid != true)  return __polygon_ai_err("failed", "support has no measurable bounds: " + _p.on);
  var _before = _commit ? __polygon_history_snap(_ed) : undefined;
  var _b = __polygon_ai_snap_bottom(_ed, _node, _sb.top + _gap);

  if (!is_struct(_b) || _b.valid != true)  return __polygon_ai_err("failed", "node has no measurable bounds: " + _p.id);
  if (_commit)  __polygon_history_commit(_ed, _before);
  return { id: _p.id, on: _p.on, gap: _gap, bounds: _b };
}

function __polygon_ai_op_transform(_ed, _p, _commit) {
  var _vr = __polygon_ai_v_transform(_ed, _p);

  if (_vr != undefined)  return __polygon_ai_v_err(_vr);
  var _has_pos = variable_struct_exists(_p, "position");
  var _has_rot = variable_struct_exists(_p, "rotation");
  var _has_sca = variable_struct_exists(_p, "scale");
  var _node = __polygon_ai_node(_ed, _p.id);

  if (__polygon_locked_get(_ed, _node))  return __polygon_ai_err("locked", "node is locked: " + _p.id);
  var _before = _commit ? __polygon_history_snap(_ed) : undefined;

  if (_has_pos)  _node.setLocalPosition(new GM3D_Vec3(_p.position[0], _p.position[1], _p.position[2]));
  if (_has_rot)  _node.setLocalRotation(__polygon_euler_to_quat(degtorad(_p.rotation[0]), degtorad(_p.rotation[1]), degtorad(_p.rotation[2])));
  if (_has_sca)  _node.setLocalScale(new GM3D_Vec3(max(_p.scale[0], 0.01), max(_p.scale[1], 0.01), max(_p.scale[2], 0.01)));
  _ed.rt.scene.update(0);

  if (_commit)  __polygon_history_commit(_ed, _before);
  return { id: _p.id, transform: __polygon_ai_transform_of(_node) };
}

function __polygon_ai_op_rename(_ed, _p, _commit) {
  var _vr = __polygon_ai_v_rename(_ed, _p);

  if (_vr != undefined)  return __polygon_ai_v_err(_vr);
  var _node = __polygon_ai_node(_ed, _p.id);

  // Same commit path as the hierarchy inline rename.
  var _before = _commit ? __polygon_history_snap(_ed) : undefined;
  var _en = __polygon_registry_find(_ed, _node);

  if (_en != undefined)  _en.label = _p.label;
  if (_commit)  __polygon_history_commit(_ed, _before);
  return { id: _p.id, label: _p.label };
}

function __polygon_ai_op_delete(_ed, _p, _commit) {
  if (!variable_struct_exists(_p, "ids") || !is_array(_p.ids) || array_length(_p.ids) == 0)  return __polygon_ai_err("bad_params", "ids (non-empty array) required");
  var _victims = [];
  var _missing = [];

  for (var _i = 0, _n = array_length(_p.ids); _i < _n; _i++) {
    var _node = __polygon_ai_node(_ed, _p.ids[_i]);

    if (_node == undefined) {
      array_push(_missing, _p.ids[_i]);
      continue;
    }

    if (_ed.rt != undefined && __polygon_node_same(_node, _ed.rt.cam)) {
      array_push(_missing, _p.ids[_i]);
      continue;
    }

    array_push(_victims, _node);
  }

  if (array_length(_missing) > 0)  return __polygon_ai_err("not_found", "unknown/protected node(s): " + json_stringify(_missing));
  // Same destroy path as manual multi-delete (silent: no confirm dialog).
  // Selection is filtered BEFORE destroying (destroyed nodes are unreadable).
  var _before = _commit ? __polygon_history_snap(_ed) : undefined;
  var _ids = [];
  var _kept = [];

  for (var _k = 0, _nk = array_length(_ed.sel); _k < _nk; _k++) {
    var _dead = false;

    for (var _v = 0, _nv = array_length(_victims); _v < _nv; _v++) {
      if (__polygon_node_same(_ed.sel[_k], _victims[_v])) {
        _dead = true;
        break;
      }
    }

    if (!_dead)  array_push(_kept, _ed.sel[_k]);
  }

  for (var _j = 0, _m = array_length(_victims); _j < _m; _j++) {
    var _en = __polygon_registry_find(_ed, _victims[_j]);

    if (_en != undefined)  array_push(_ids, _en.id);
    __polygon_spawn_unregister(_ed, _victims[_j]);
    __polygon_destroy_subtree(_victims[_j]);
  }

  _ed.rt.scene.update(0);
  __polygon_sel_assign(_ed, _kept);

  if (_commit)  __polygon_history_commit(_ed, _before);
  return { deleted: _ids };
}

function __polygon_ai_op_save(_ed, _p) {
  var _name = (variable_struct_exists(_p, "name") && is_string(_p.name)) ? _p.name : "";

  if (_name != "") {
    if (!__polygon_save_named(_ed, _name))  return __polygon_ai_err("failed", "could not save scene as: " + _name);
  } else {
    if (!is_string(_ed.scene_file) || _ed.scene_file == "")  return __polygon_ai_err("no_file", "no scene file yet: pass name");
    if (!__polygon_save_scene(_ed))  return __polygon_ai_err("failed", "could not write scene file");
  }

  return { file: _ed.scene_file };
}

// Validates then applies a batch of ops with a single history entry
// (one Ctrl+Z undoes the whole batch). Ops: create|transform|rename|
// delete|select|drop_to_ground|place_on (each with its own params struct).
// Note: like transform, on_top_of/on must reference an already existing
// node (same-batch forward refs fail validation); create platforms first,
// then stack in a second batch.
function __polygon_ai_op_batch(_ed, _p) {
  if (!variable_struct_exists(_p, "ops") || !is_array(_p.ops) || array_length(_p.ops) == 0)  return __polygon_ai_err("bad_params", "ops (non-empty array) required");
  if (array_length(_p.ops) > 64)  return __polygon_ai_err("bad_params", "at most 64 ops per batch");
  // Phase 1: validate everything before touching the scene.
  for (var _i = 0, _n = array_length(_p.ops); _i < _n; _i++) {
    var _op = _p.ops[_i];

    if (!is_struct(_op) || !variable_struct_exists(_op, "op") || !is_string(_op.op))  return __polygon_ai_err("bad_params", "ops[" + string(_i) + "].op (string) required");
    var _pp = (variable_struct_exists(_op, "params") && is_struct(_op.params)) ? _op.params : {};
    var _chk = __polygon_ai_check(_ed, _op.op, _pp);

    if (_chk != undefined)  return __polygon_ai_err("bad_params", "ops[" + string(_i) + "] " + _op.op + ": " + _chk);
  }

  // Phase 2: apply with one history entry.
  var _before = __polygon_history_snap(_ed);
  var _results = [];

  for (var _j = 0, _m = array_length(_p.ops); _j < _m; _j++) {
    var _op2 = _p.ops[_j];
    var _pp2 = (variable_struct_exists(_op2, "params") && is_struct(_op2.params)) ? _op2.params : {};
    var _r = __polygon_ai_apply(_ed, _op2.op, _pp2);

    if (variable_struct_exists(_r, "error")) {
      __polygon_history_commit(_ed, _before);
      return __polygon_ai_err(_r.error_code, "ops[" + string(_j) + "] " + _op2.op + ": " + _r.error_msg);
    }

    array_push(_results, _r);
  }

  __polygon_history_commit(_ed, _before);
  return { results: _results };
}

// Dry-run validation shared by batch phase 1 ("" = ok, else reason).
// Same validators as the single ops: no drift between phase 1 and phase 2.
function __polygon_ai_check(_ed, _op, _p) {
  switch (_op) {
    case "create": return __polygon_ai_v_create(_ed, _p);
    case "transform": return __polygon_ai_v_transform(_ed, _p);
    case "rename": return __polygon_ai_v_rename(_ed, _p);
    case "delete": return __polygon_ai_v_ids(_ed, _p, true);
    case "select": return __polygon_ai_v_ids(_ed, _p, false);
    case "drop_to_ground": return __polygon_ai_v_drop(_ed, _p);
    case "place_on": return __polygon_ai_v_stack(_ed, _p);
  }

  return "unsupported batch op: " + _op;
}

// Applies one validated batch op without committing (_commit=false).
function __polygon_ai_apply(_ed, _op, _p) {
  switch (_op) {
    case "create": return __polygon_ai_op_create(_ed, _p, false);
    case "transform": return __polygon_ai_op_transform(_ed, _p, false);
    case "rename": return __polygon_ai_op_rename(_ed, _p, false);
    case "delete": return __polygon_ai_op_delete(_ed, _p, false);
    case "select": return __polygon_ai_op_select(_ed, _p);
    case "drop_to_ground": return __polygon_ai_op_drop(_ed, _p, false);
    case "place_on": return __polygon_ai_op_stack(_ed, _p, false);
  }

  return __polygon_ai_err("unknown_op", "unsupported batch op: " + _op);
}
