/// Small, dependency-free math helpers shared across systems and the stick
/// animation layer. Everything here is pure and unit-tested.
library;

import 'dart:math' as math;

const double kPi = math.pi;
const double kTau = math.pi * 2;
const double kHalfPi = math.pi / 2;

/// Degrees -> radians.
double rad(double degrees) => degrees * math.pi / 180.0;

/// Radians -> degrees.
double deg(double radians) => radians * 180.0 / math.pi;

/// Linear interpolation. [t] is NOT clamped (callers clamp when needed).
double lerpD(double a, double b, double t) => a + (b - a) * t;

/// Clamp to [lo, hi]. Returns [lo] if the range is degenerate.
double clampD(double v, double lo, double hi) {
  if (hi < lo) return lo;
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}

/// Shortest-arc angle interpolation (radians). Avoids the 359°->0° spin.
double lerpAngle(double a, double b, double t) {
  var diff = (b - a) % kTau;
  if (diff > kPi) diff -= kTau;
  if (diff < -kPi) diff += kTau;
  return a + diff * t;
}

/// Wrap an angle to (-pi, pi].
double wrapAngle(double a) {
  var x = a % kTau;
  if (x > kPi) x -= kTau;
  if (x <= -kPi) x += kTau;
  return x;
}

/// Move [current] toward [target] by at most [maxDelta]. No overshoot.
double approach(double current, double target, double maxDelta) {
  if (maxDelta <= 0) return current;
  final d = target - current;
  if (d.abs() <= maxDelta) return target;
  return current + (d.isNegative ? -maxDelta : maxDelta);
}

/// Smoothstep ease (0..1 in, 0..1 out). [t] clamped.
double easeInOut(double t) {
  final x = clampD(t, 0, 1);
  return x * x * (3 - 2 * x);
}

/// Quadratic ease-out.
double easeOut(double t) {
  final x = clampD(t, 0, 1);
  return 1 - (1 - x) * (1 - x);
}

/// Map [v] from [inMin..inMax] onto [outMin..outMax] (no clamp).
double remap(double v, double inMin, double inMax, double outMin, double outMax) {
  if (inMax == inMin) return outMin;
  return outMin + (v - inMin) / (inMax - inMin) * (outMax - outMin);
}

/// True when [v] is finite (not NaN/inf). Used to guard hot-path math.
bool finite(double v) => v.isFinite;
