// poly_ai_net - public API.

// Handles relay traffic: data chunks (framed lines) and link loss.
// Public entry point, called from the oEditor Async Networking event.
function poly_ai_net() {
  var _ed = __poly_inst();

  if (_ed == undefined || async_load == undefined) return;
  var _ai = __poly_ai_state(_ed);
  var _type = async_load[? "type"];

  if (_type == network_type_non_blocking_connect) {
    if (async_load[? "id"] != _ai.sock || _ai.ready) return;

    if (async_load[? "succeeded"] == true) {
      _ai.ready = true;
      _ai.ever = true;
      _ai.retry_delay = 2;
      _ai.retry_tries = 0;
      __poly_ai_log("connected to relay 127.0.0.1:" + string(_ai.port));
      __poly_console_log(_ed, "MCP connected to relay 127.0.0.1:" + string(_ai.port));
      __poly_ai_send(_ed, { v: 1, hello: "poly-ai" });
    } else {
      __poly_ai_disconnect(_ed);
      __poly_ai_failed(_ed, "connect refused");
    }

    return;
  }

  if (_type == network_type_data) {
    if (async_load[? "id"] != _ai.sock) return;
    var _buf = async_load[? "buffer"];

    if (_buf == undefined) return;
    buffer_seek(_buf, buffer_seek_start, 0);
    var _chunk = buffer_read(_buf, buffer_text);
    __poly_ai_log_rx(_ed, "rx " + string(string_length(_chunk)) + " chars");
    __poly_ai_frame(_ed, _chunk);
    return;
  }

  if (_type == network_type_down || _type == network_type_disconnect) __poly_ai_disconnect(_ed);
}
