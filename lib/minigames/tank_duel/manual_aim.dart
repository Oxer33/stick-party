import 'dart:math' as math;
import 'dart:ui';

import '../../core/math2.dart';

/// A player-DRIVEN barrel angle, clamped to a firing band `[minAngle, maxAngle]`.
///
/// This is the manual-aim mechanic that replaces the old auto-sweep: the player
/// DRAGS to point the barrel and it holds where it was left (sticky between
/// shots). [aimToward] turns a world point (the touch) into a clamped angle so a
/// drag anywhere maps onto the band; [nudge] turns a tiny manual delta (used by
/// the test / fine input) into a clamped angle. Read [angle] (radians) or the
/// unit [direction] vector. Pure value object — no clock, no Random.
class ManualAim {
  /// Lower bound of the firing band (radians).
  final double minAngle;

  /// Upper bound of the firing band (radians).
  final double maxAngle;

  double _angle;

  /// Creates a manual aim clamped into `[minAngle, maxAngle]`.
  ///
  /// Throws [ArgumentError] when bounds are non-finite or [maxAngle] < [minAngle]
  /// (mirroring [AimSweep] so a bad band fails loudly the same way). The initial
  /// [angle] is clamped into the band.
  ManualAim({
    required this.minAngle,
    required this.maxAngle,
    double angle = 0,
  }) : _angle = 0 {
    if (!minAngle.isFinite || !maxAngle.isFinite) {
      throw ArgumentError('angles must be finite (min=$minAngle, max=$maxAngle)');
    }
    if (maxAngle < minAngle) {
      throw ArgumentError('maxAngle ($maxAngle) < minAngle ($minAngle)');
    }
    _angle = clampD(angle, minAngle, maxAngle);
  }

  /// Current aim angle in radians, always within `[minAngle, maxAngle]`.
  double get angle => _angle;

  /// Band center (the inward normal) — the rest aim when nothing is dragged.
  double get center => (minAngle + maxAngle) * 0.5;

  /// Unit vector pointing along [angle] (`cos`, `sin`).
  Offset get direction => Offset(math.cos(_angle), math.sin(_angle));

  /// Aim fraction in `[0, 1]`: 0 at [minAngle], 1 at [maxAngle]. Returns 0 for a
  /// degenerate band. Handy for drawing an aim gauge.
  double get progress {
    final span = maxAngle - minAngle;
    if (span <= 0) return 0;
    return clampD((_angle - minAngle) / span, 0, 1);
  }

  /// Point the barrel at world [target] as seen from [pivot]: take the heading
  /// pivot→target, then CLAMP it into the band so a drag past the edge of the arc
  /// just rests on the band limit. Ignores a target on top of the pivot (keeps
  /// the last angle) and any non-finite input.
  void aimToward(Offset pivot, Offset target) {
    final d = target - pivot;
    if (!d.dx.isFinite || !d.dy.isFinite) return;
    if (d.distanceSquared < 1e-6) return;
    setAngle(_clampToBand(math.atan2(d.dy, d.dx)));
  }

  /// Set the aim directly to [a], clamped into the band. Non-finite is ignored.
  void setAngle(double a) {
    if (!a.isFinite) return;
    _angle = _clampToBand(a);
  }

  /// Nudge the aim by [delta] radians, clamped into the band. Lets a fine input
  /// (or a test) steer the barrel toward a solved lead without a touch point.
  void nudge(double delta) {
    if (!delta.isFinite) return;
    _angle = _clampToBand(_angle + delta);
  }

  /// Clamp an arbitrary heading into `[minAngle, maxAngle]`. The heading is first
  /// unwrapped relative to the band center so a target BEHIND the tank (heading
  /// near ±pi away) still resolves to the nearest band edge instead of flipping.
  double _clampToBand(double a) {
    final span = maxAngle - minAngle;
    if (span <= 0) return minAngle;
    // Re-center the angle on the band's midpoint, take the shortest wrap, then
    // fold it back so e.g. a tank at the bottom can't "aim through its own hull".
    final mid = center;
    final rel = wrapAngle(a - mid);
    return clampD(mid + rel, minAngle, maxAngle);
  }
}
