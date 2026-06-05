import '../../core/math2.dart';

/// A single accumulating "fill" meter driven by taps, with optional decay.
///
/// This is the shared mechanic behind every "press fast" minigame:
///
/// * **No-decay racers** (Tap Sprint, Button Masher): leave [decayPerSec] at 0
///   so the meter only ever climbs and the first player to reach [maxValue]
///   wins. The raw [tapCount] is also useful for a "most taps in N seconds"
///   variant.
/// * **Decaying meters** (Tug of War, hold-the-lead games): set
///   [decayPerSec] > 0 so the value bleeds away each frame and players must
///   keep mashing to hold or grow their position.
///
/// The meter is intentionally mutable: it lives for exactly one round and is
/// cheap to tick every frame. Construct one per player.
class TapMashMeter {
  /// How much a single [tap] adds to [value].
  final double tapImpulse;

  /// How much [value] bleeds off per second inside [update]. 0 = no decay.
  final double decayPerSec;

  /// Upper bound for [value]; also the denominator for [progress].
  final double maxValue;

  double _value;
  int _tapCount = 0;

  /// Creates a meter.
  ///
  /// Throws [ArgumentError] when [maxValue] is not strictly positive, when
  /// [tapImpulse] or [decayPerSec] is negative, or when the initial [value] is
  /// negative. Non-finite inputs are also rejected so a bad value can never
  /// poison the per-frame math.
  TapMashMeter({
    this.tapImpulse = 0.05,
    this.decayPerSec = 0.0,
    this.maxValue = 1.0,
    double value = 0,
  }) : _value = value {
    if (!finite(maxValue) || maxValue <= 0) {
      throw ArgumentError.value(maxValue, 'maxValue', 'must be > 0 and finite');
    }
    if (!finite(tapImpulse) || tapImpulse < 0) {
      throw ArgumentError.value(
          tapImpulse, 'tapImpulse', 'must be >= 0 and finite');
    }
    if (!finite(decayPerSec) || decayPerSec < 0) {
      throw ArgumentError.value(
          decayPerSec, 'decayPerSec', 'must be >= 0 and finite');
    }
    if (!finite(value) || value < 0) {
      throw ArgumentError.value(value, 'value', 'must be >= 0 and finite');
    }
    _value = clampD(value, 0, maxValue);
  }

  /// Register one tap: bumps [value] by [tapImpulse], capped at [maxValue],
  /// and increments [tapCount]. [tapCount] keeps counting even when the meter
  /// is already [full] (useful for "most taps" scoring).
  void tap() {
    _value = _value + tapImpulse;
    if (_value > maxValue) _value = maxValue;
    _tapCount++;
  }

  /// Advance one frame: decays [value] by `decayPerSec * dt`, floored at 0.
  /// Negative or non-finite [dt] is ignored so a bad clock can't add charge.
  void update(double dt) {
    if (decayPerSec == 0) return;
    if (!finite(dt) || dt <= 0) return;
    _value = _value - decayPerSec * dt;
    if (_value < 0) _value = 0;
  }

  /// Current raw fill in `[0, maxValue]`.
  double get value => _value;

  /// Fill as a fraction in `[0, 1]` (i.e. `value / maxValue`, clamped).
  double get progress => clampD(_value / maxValue, 0, 1);

  /// True once the meter has reached [maxValue].
  bool get full => _value >= maxValue;

  /// Total number of [tap] calls since construction or the last [reset].
  int get tapCount => _tapCount;

  /// Reset value and tap count to zero for a rematch within the same object.
  void reset() {
    _value = 0;
    _tapCount = 0;
  }
}
