import '../core/rng.dart';

/// Bot skill tier. Set once per session; shared by all bot slots.
enum BotDifficulty { easy, medium, hard }

/// Tuning for bot behavior. Games read this to time/aim synthetic taps so
/// they never branch on human-vs-bot beyond "is this slot a bot?".
class BotProfile {
  /// Base reaction delay in seconds before a bot acts on a stimulus.
  final double reactionSec;

  /// Probability [0..1] the bot makes a deliberate mistake (mistime / miss).
  final double errorRate;

  /// Aim/timing accuracy [0..1] for games that need precision (1 = perfect).
  final double accuracy;

  const BotProfile({
    required this.reactionSec,
    required this.errorRate,
    required this.accuracy,
  });

  factory BotProfile.forDifficulty(BotDifficulty d) => switch (d) {
        BotDifficulty.easy =>
          const BotProfile(reactionSec: 0.55, errorRate: 0.35, accuracy: 0.55),
        BotDifficulty.medium =>
          const BotProfile(reactionSec: 0.32, errorRate: 0.18, accuracy: 0.78),
        BotDifficulty.hard =>
          const BotProfile(reactionSec: 0.16, errorRate: 0.07, accuracy: 0.93),
      };

  /// Reaction delay with symmetric jitter (±25%) for natural variance.
  double jitteredReaction(SeededRng rng) =>
      (reactionSec + rng.jitter(reactionSec * 0.25)).clamp(0.05, 2.0);
}

/// Lightweight per-bot reaction clock. A game ticks it; [ready] flips true once
/// the (jittered) delay elapses, then the game acts and calls [arm] again.
class ReactionClock {
  double _remaining;
  bool _fired = false;

  ReactionClock(BotProfile profile, SeededRng rng)
      : _remaining = profile.jitteredReaction(rng);

  bool get ready => _fired;

  /// Advance the clock; returns true exactly once when it elapses.
  bool tick(double dt) {
    if (_fired) return false;
    _remaining -= dt;
    if (_remaining <= 0) {
      _fired = true;
      return true;
    }
    return false;
  }

  /// Re-arm for the next reaction with a fresh jittered delay.
  void arm(BotProfile profile, SeededRng rng) {
    _remaining = profile.jitteredReaction(rng);
    _fired = false;
  }
}
