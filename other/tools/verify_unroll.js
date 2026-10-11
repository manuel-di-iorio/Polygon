// Verify roll-removal: same view dir + same yaw, zero roll.
function norm(q) {
  var l = Math.hypot(q[0], q[1], q[2], q[3]);
  return [q[0] / l, q[1] / l, q[2] / l, q[3] / l];
}
function mul(a, b) {
  var ax = a[0], ay = a[1], az = a[2], aw = a[3];
  var bx = b[0], by = b[1], bz = b[2], bw = b[3];
  return [
    aw * bx + ax * bw + ay * bz - az * by,
    aw * by - ax * bz + ay * bw + az * bx,
    aw * bz + ax * by - ay * bx + az * bw,
    aw * bw - ax * bx - ay * by - az * bz
  ];
}
function axisAngle(ax, ay, az, t) {
  var s = Math.sin(t / 2);
  return [ax * s, ay * s, az * s, Math.cos(t / 2)];
}
function rotVec(q, v) { // q*v*q^-1 for unit q
  var c = [-q[0], -q[1], -q[2], q[3]];
  var t = mul(q, [v[0], v[1], v[2], 0]);
  var r = mul(t, c);
  return [r[0], r[1], r[2]];
}
function dot(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
function cross(a, b) {
  return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
}
function sub(a, b) { return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]; }
function scale(v, s) { return [v[0] * s, v[1] * s, v[2] * s]; }
function len(v) { return Math.hypot(v[0], v[1], v[2]); }
function deg(r) { return (r * 180 / Math.PI).toFixed(2); }

function viewDir(q) { var f = rotVec(q, [0, 0, 1]); return [-f[0], -f[1], -f[2]]; }
function yawOfV(v) { return Math.atan2(v[0], -v[2]); }
function upOf(q) { return rotVec(q, [0, 1, 0]); }
function rollOf(q) {
  var f = viewDir(q), u = upOf(q), wu = [0, 1, 0];
  var w = sub(wu, scale(f, dot(wu, f)));
  if (len(w) < 0.001) return 0;
  var lw = len(w); w = scale(w, 1 / lw);
  return Math.atan2(dot(cross(w, u), f), dot(w, u));
}
// candidate: out = R(f, -roll) * q
function unroll(q) {
  var f = viewDir(q), u = upOf(q), wu = [0, 1, 0];
  var w = sub(wu, scale(f, dot(wu, f)));
  if (len(w) < 0.001) return q.slice();
  var lw = len(w); w = scale(w, 1 / lw);
  var roll = Math.atan2(dot(cross(w, u), f), dot(w, u));
  var fl = len(f); var fn = scale(f, 1 / fl);
  var R = axisAngle(fn[0], fn[1], fn[2], -roll);
  return norm(mul(R, q));
}

var y30 = axisAngle(0, 1, 0, 30 * Math.PI / 180);
var f0 = viewDir(y30);
var r20 = axisAngle(f0[0], f0[1], f0[2], 20 * Math.PI / 180);
var cases = {
  fileCam: norm([-0.04529624432325363, 0.7482538223266602, -0.07446056604385376, 0.6576626896858215]),
  identity: [0, 0, 0, 1],
  pitchDown20: axisAngle(1, 0, 0, -20 * Math.PI / 180),
  yaw30roll20: norm(mul(r20, y30))
};
Object.keys(cases).forEach(function (name) {
  var q = cases[name];
  var v0 = viewDir(q);
  var out = unroll(q);
  var v1 = viewDir(out);
  console.log(name + ": yaw " + deg(yawOfV(v0)) + " -> " + deg(yawOfV(v1)) +
    " | roll " + deg(rollOf(q)) + " -> " + deg(rollOf(out)) +
    " | view [" + v1.map(function (x) { return x.toFixed(3); }).join(",") + "]" +
    " | up [" + upOf(out).map(function (x) { return x.toFixed(3); }).join(",") + "]");
});
