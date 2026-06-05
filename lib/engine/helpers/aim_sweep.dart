import 'dart:math' as math;
import 'dart:ui';

import '../../core/math2.dart';

/// An aim angle that ping-pongs back and forth between [minAngle] and
/// [maxAngle] at a constant angular [speed].
///
/// This is the "moving cursor" mechanic for tap-to-fire aiming games: the
/// barrel/arrow sweeps continuously and a player taps to lock in whatever angle
/// it is showing right now. Read [angle] (radians) or the unit [direction]
/// vector at the moment of the tap.
///
/// Used by Tank Duel and Archer Pop.
class AimSweep {
  /// Lower bound of the sweep (radians).
  final double minAngle;

  /// Upper bound of the sweep (radians).
  final double maxAngle;

  /// Angular speed in radians per second.
  final double speed;

  double _angle;

  /// +1 sweeping toward [maxAngle], -1 sweeping toward [minAngle].
  int _dir = 1;

  /// Creates a sweep.
  ///
  /// Throws [ArgumentError] when bounds/speed are non-finite, when
  /// [maxAngle] < [minAngle], or when [speed] < 0. The initial [angle] is
  /// clamped into `[minAngle, maxAngle]`.
  AimSweep({
    required this.minAngle,
    required this.maxAngle,
    this.speed = 1.6,
    double angle = 0,
  }) : _angle = 0 {
    if (!minAngle.isFinite || !maxAngle.isFinite || !speed.isFinite) {
      throw ArgumentError('angles and speed must be finite '
          '(min=$minAngle, max=$maxAngle, speed=$speed)');
    }
    if (maxAngle < minAngle) {
      throw ArgumentError('maxAngle ($maxAngle) < minAngle ($minAngle)');
    }
    if (speed < 0) {
      throw ArgumentError.value(speed, 'speed', 'must be >= 0');
    }
    _angle = clampD(angle, minAngle, maxAngle);
  }

  /// Current aim angle in radians, always within `[minAngle, maxAngle]`.
  double get angle => _angle;

  /// Unit vector pointing along [angle] (`cos`, `sin`). Multiply by a speed to
  /// launch a projectile in this direction.
  Offset get direction => Offset(math.cos(_angle), math.sin(_angle));

  /// Sweep fraction in `[0, 1]`: 0 at [minAngle], 1 at [maxAngle]. Handy for
  /// drawing a power/aim gauge. Returns 0 when the range is degenerate.
  double get progress {
    final span = maxAngle - minAngle;
    if (span <= 0) return 0;
    return clampD((_angle - minAngle) / span, 0, 1);
  }

  /// Advance the sweep by [dt] seconds, reflecting off either bound so the
  /// motion ping-pongs. Non-positive or non-finite [dt] is ignored. A
  /// degenerate range (min == max) holds the angle still.
  void update(double dt) {
    if (!dt.isFinite || dt <= 0) return;
    final span = maxAngle - minAngle;
    if (span <= 0) {
      _angle = minAngle;
      return;
    }

    var next = _angle + _dir * speed * dt;

    // Reflect repeatedly in case a very large dt overshoots multiple times,
    // so the angle always lands inside the band with a correct direction.
    while (next < minAngle || next > maxAngle) {
      if (next > maxAngle) {
        next = maxAngle - (next - maxAngle);
        _dir = -1;
      } else if (next < minAngle) {
        next = minAngle + (minAngle - next);
        _dir = 1;
      }
    }
    _angle = next;
  }

  /// Reset to [minAngle] sweeping upward toward [maxAngle].
  void reset() {
    _angle = minAngle;
    _dir = 1;
  }
}
