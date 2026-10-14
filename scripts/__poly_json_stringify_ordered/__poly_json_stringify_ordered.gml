// v1.2.0

#macro __JSON_CH_QUOTE   34
#macro __JSON_CH_COMMA   44
#macro __JSON_CH_LBRACE  123
#macro __JSON_CH_RBRACE  125
#macro __JSON_CH_LBRACK  91
#macro __JSON_CH_RBRACK  93
#macro __JSON_CH_ZERO    48

/// @function json_stringify_ordered(value, [prettify], [compact])
/// @description Converts any value (struct, array, or primitive) to a JSON string with sorted keys.
/// @param {any} value The value to convert to JSON
/// @param {bool} [prettify=false] Whether to include pretty formatting
/// @param {real} [compact=0] Threshold (in UTF-8 BYTES) below which arrays/structs stay on a single line. 0 = disabled.
/// @return {string} The JSON string
function json_stringify_ordered(value, prettify = false, compact = 0) {
  // Buffer reused across calls: no create/delete on every invocation,
  // and no leak if serialization throws midway.
  static buf = buffer_create(4096, buffer_grow, 1);
  buffer_seek(buf, buffer_seek_start, 0);

  __json_write_value(value, buf, 0, prettify, compact);

  buffer_write(buf, buffer_u8, 0); // null terminator
  var result = buffer_peek(buf, 0, buffer_string);

  // Don't keep a huge buffer alive after a single large serialization
  if (buffer_get_size(buf) > 4194304) buffer_resize(buf, 4096);
  return result;
}

/// @function __json_write_value(v, buf, indent, pretty, compact)
/// @description Recursive writer (pretty or minified mode).
/// @param {any} v The value to serialize
/// @param {id.buffer} buf The target buffer
/// @param {real} indent Current indentation level
/// @param {bool} pretty Whether to use pretty formatting
/// @param {real} compact Single-line threshold in bytes (only used when pretty)
/// @private
function __json_write_value(v, buf, indent, pretty, compact) {
  if (is_struct(v)) {
    if (pretty && compact > 0) {
      // Speculative single-line attempt written straight into the main buffer,
      // aborting as soon as the threshold is exceeded. On failure, rewind and write pretty.
      var start = buffer_tell(buf);
      if (__json_write_inline(v, buf, start + compact)) return;
      buffer_seek(buf, buffer_seek_start, start);
    }

    var keys = variable_struct_get_names(v);
    array_sort(keys, true);
    var kl = array_length(keys);

    buffer_write(buf, buffer_u8, __JSON_CH_LBRACE);
    if (pretty) {
      var nl_in = __json_nl_pad(indent + 1);
      for (var i = 0; i < kl; i++) {
        var k = keys[i];
        buffer_write(buf, buffer_text, nl_in);
        buffer_write(buf, buffer_text, __json_key(k));
        buffer_write(buf, buffer_text, ": ");
        __json_write_value(v[$ k], buf, indent + 1, true, compact);
        if (i < kl - 1) buffer_write(buf, buffer_u8, __JSON_CH_COMMA);
      }
      buffer_write(buf, buffer_text, __json_nl_pad(indent));
    } else {
      for (var i = 0; i < kl; i++) {
        var k = keys[i];
        buffer_write(buf, buffer_text, __json_key(k));
        buffer_write(buf, buffer_u8, 58); // ':'
        __json_write_value(v[$ k], buf, 0, false, 0);
        if (i < kl - 1) buffer_write(buf, buffer_u8, __JSON_CH_COMMA);
      }
    }
    buffer_write(buf, buffer_u8, __JSON_CH_RBRACE);
  }
  else if (is_array(v)) {
    if (pretty && compact > 0) {
      var start = buffer_tell(buf);
      if (__json_write_inline(v, buf, start + compact)) return;
      buffer_seek(buf, buffer_seek_start, start);
    }

    var al = array_length(v);

    buffer_write(buf, buffer_u8, __JSON_CH_LBRACK);
    if (pretty) {
      var nl_in = __json_nl_pad(indent + 1);
      for (var i = 0; i < al; i++) {
        buffer_write(buf, buffer_text, nl_in);
        __json_write_value(v[i], buf, indent + 1, true, compact);
        if (i < al - 1) buffer_write(buf, buffer_u8, __JSON_CH_COMMA);
      }
      buffer_write(buf, buffer_text, __json_nl_pad(indent));
    } else {
      for (var i = 0; i < al; i++) {
        __json_write_value(v[i], buf, 0, false, 0);
        if (i < al - 1) buffer_write(buf, buffer_u8, __JSON_CH_COMMA);
      }
    }
    buffer_write(buf, buffer_u8, __JSON_CH_RBRACK);
  }
  else {
    __json_write_primitive(v, buf);
  }
}

/// @function __json_write_inline(v, buf, limit)
/// @description Writes v on a single line ("{ "a": 1, "b": 2 }") directly into the buffer.
///   Returns false as soon as the buffer position reaches `limit` (i.e. length >= threshold).
/// @param {any} v The value to serialize
/// @param {id.buffer} buf The target buffer
/// @param {real} limit Absolute buffer position that must not be reached
/// @return {bool} True if the value fit under the limit
/// @private
function __json_write_inline(v, buf, limit) {
  if (is_struct(v)) {
    var n = variable_struct_names_count(v);
    if (n == 0) {
      buffer_write(buf, buffer_text, "{}");
      return buffer_tell(buf) < limit;
    }
    // Each member takes at least 6 bytes: if it can't possibly fit, skip get_names + sort
    if (buffer_tell(buf) + n * 6 >= limit) return false;

    var keys = variable_struct_get_names(v);
    array_sort(keys, true);

    buffer_write(buf, buffer_text, "{ ");
    for (var i = 0; i < n; i++) {
      var k = keys[i];
      buffer_write(buf, buffer_text, __json_key(k));
      buffer_write(buf, buffer_text, ": ");
      if (!__json_write_inline(v[$ k], buf, limit)) return false;
      if (i < n - 1) buffer_write(buf, buffer_text, ", ");
      if (buffer_tell(buf) >= limit) return false;
    }
    buffer_write(buf, buffer_text, " }");
    return buffer_tell(buf) < limit;
  }

  if (is_array(v)) {
    var al = array_length(v);
    if (al == 0) {
      buffer_write(buf, buffer_text, "[]");
      return buffer_tell(buf) < limit;
    }
    // Each element takes at least 2 bytes (value + separator)
    if (buffer_tell(buf) + al * 2 >= limit) return false;

    buffer_write(buf, buffer_text, "[ ");
    for (var i = 0; i < al; i++) {
      if (!__json_write_inline(v[i], buf, limit)) return false;
      if (i < al - 1) buffer_write(buf, buffer_text, ", ");
      if (buffer_tell(buf) >= limit) return false;
    }
    buffer_write(buf, buffer_text, " ]");
    return buffer_tell(buf) < limit;
  }

  // Long strings: fail before escaping/writing them
  if (is_string(v) && buffer_tell(buf) + string_byte_length(v) >= limit) return false;

  __json_write_primitive(v, buf);
  return buffer_tell(buf) < limit;
}

/// @function __json_write_primitive(v, buf)
/// @description Writes a primitive value to the buffer in JSON format.
///   Handles strings, handles, numbers (including int64), booleans and special values
///   (`undefined`, `NaN`, `Infinity`). Unsupported types are written as null.
/// @param {any} v The primitive value
/// @param {id.buffer} buf The target buffer
/// @private
function __json_write_primitive(v, buf) {
  if (is_string(v)) {
    buffer_write(buf, buffer_u8, __JSON_CH_QUOTE);
    buffer_write(buf, buffer_text, __json_escape_string(v));
    buffer_write(buf, buffer_u8, __JSON_CH_QUOTE);
  }
  else if (is_real(v) || is_int64(v)) {
    if ((v - v) == 0) { // finite number (NaN and infinity both give NaN here)
      if (is_int64(v)) {
        buffer_write(buf, buffer_text, "\"@i64@");
        __json_write_int64_hex(v, buf);
        buffer_write(buf, buffer_text, "$i64$\"");
      } else {
        buffer_write(buf, buffer_text, string(v));
      }
    }
    else if (is_nan(v)) {
      buffer_write(buf, buffer_text, "\"@@nan$$\"");
    }
    else {
      buffer_write(buf, buffer_text, (v > 0) ? "\"@@infinity$$\"" : "\"@@-infinity$$\"");
    }
  }
  else if (is_bool(v)) {
    buffer_write(buf, buffer_text, v ? "true" : "false");
  }
  else if (is_undefined(v)) {
    buffer_write(buf, buffer_text, "null");
  }
  else if (is_handle(v)) {
    buffer_write(buf, buffer_u8, __JSON_CH_QUOTE);
    buffer_write(buf, buffer_text, __json_escape_string(string(v)));
    buffer_write(buf, buffer_u8, __JSON_CH_QUOTE);
  }
  else {
    buffer_write(buf, buffer_text, "null"); // unhandled types: still produce valid JSON
  }
}

/// @function __json_nl_pad(n)
/// @description Returns "\n" followed by 2*n spaces, cached (no string_repeat per container).
/// @param {real} n The indentation level
/// @return {string}
/// @private
function __json_nl_pad(n) {
  static pads = ["\n"];
  var l = array_length(pads);
  while (l <= n) {
    array_push(pads, pads[l - 1] + "  ");
    l++;
  }
  return pads[n];
}

/// @function __json_key(k)
/// @description Returns the key already escaped and wrapped in quotes. Keys repeat a lot
///   (same fields across many objects), so the result is cached.
/// @param {string} k The struct key
/// @return {string}
/// @private
function __json_key(k) {
  static cache = {};
  static count = 0;
  var q = cache[$ k];
  if (q != undefined) return q;
  q = "\"" + __json_escape_string(k) + "\"";
  if (count < 4096) { // cap so dynamic keys can't make the cache grow unbounded
    cache[$ k] = q;
    count++;
  }
  return q;
}

/// @function __json_escape_string(str)
/// @description Escapes a string for JSON inclusion. Only calls string_replace_all
///   for characters that are actually present.
/// @param {string} str The string to escape
/// @return {string} The escaped string
/// @private
function __json_escape_string(str) {
  var s = str;
  if (string_pos("\\", s)) s = string_replace_all(s, "\\", "\\\\"); // must stay first
  if (string_pos("\"", s)) s = string_replace_all(s, "\"", "\\\"");
  if (string_pos("\n", s)) s = string_replace_all(s, "\n", "\\n");
  if (string_pos("\r", s)) s = string_replace_all(s, "\r", "\\r");
  if (string_pos("\t", s)) s = string_replace_all(s, "\t", "\\t");
  if (string_pos("\b", s)) s = string_replace_all(s, "\b", "\\b");
  if (string_pos("\f", s)) s = string_replace_all(s, "\f", "\\f");
  return s;
}

/// @function __json_write_int64_hex(v, buf)
/// @description Writes an int64 as lowercase hex directly into the buffer (no temporary strings).
///   Values >= 0: no leading zeros. Negative values: 16-digit two's complement.
/// @param {int64} v The value to write
/// @param {id.buffer} buf The target buffer
/// @private
function __json_write_int64_hex(v, buf) {
  static codes = [48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 97, 98, 99, 100, 101, 102]; // '0'-'9', 'a'-'f'
  if (v == 0) {
    buffer_write(buf, buffer_u8, __JSON_CH_ZERO);
    return;
  }
  var started = false;
  for (var i = 60; i >= 0; i -= 4) {
    var d = (v >> i) & 15;
    if (d != 0) started = true;
    if (started) buffer_write(buf, buffer_u8, codes[d]);
  }
}
