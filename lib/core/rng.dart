import 'dart:math';

/// Seedable RNG wrapper so combat, drafts, loot and procedural art are
/// deterministic in tests (`SeededRng(42)`) and varied in play (`SeededRng()`).
class SeededRng {
  final Random _r;

  SeededRng([int? seed]) : _r = Random(seed);

  /// Uniform double in [0, 1).
  double next() => _r.nextDouble();

  /// Uniform double in [min, max).
  double range(double min, double max) => min + _r.nextDouble() * (max - min);

  /// Uniform int in [min, max). Returns [min] when the range is degenerate.
  int intRange(int min, int max) => max <= min ? min : min + _r.nextInt(max - min);

  /// True with probability [p] (clamped to [0, 1]).
  bool chance(double p) {
    if (p <= 0) return false;
    if (p >= 1) return true;
    return _r.nextDouble() < p;
  }

  /// Random element of [items]. Throws on empty (caller guards).
  T pick<T>(List<T> items) => items[_r.nextInt(items.length)];

  /// Random sign (+1 or -1).
  double sign() => _r.nextBool() ? 1.0 : -1.0;

  /// Symmetric jitter in [-amount, amount).
  double jitter(double amount) => range(-amount, amount);
}
